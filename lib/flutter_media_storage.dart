library flutter_media_storage;

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Serializable object that represents one piece of downloaded
/// media.
class _MediaData {
  final String url;
  final String filename;
  final String type;
  final DateTime lastUpdate;

  const _MediaData({
    required this.url,
    required this.filename,
    required this.type,
    required this.lastUpdate,
  });

  _MediaData.fromJson(Map<String, dynamic> json)
      : url = json['url'],
        filename = json['name'],
        type = json['type'],
        lastUpdate = DateTime.parse(json['last_update']);

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': filename,
        'type': type,
        'last_update': lastUpdate.toIso8601String(),
      };
}

/// Returns the correct media type for the media specified in [url].
///
/// For this to work the [url] has to contain the file ending.
///
/// Flutter supports these types & file endings for images:
/// - JPEG -> .jpg, .jpeg, .jfif, .pjpeg, .pjp
/// - PNG -> .png
/// - (Animated) GIF -> .gif
/// - (Animated) WebP -> .webp
/// - BMP -> .bmp, .dib
/// - WBMP -> wbmp
///
/// Flutter supports these types & file endings for videos:
String _getFileType(String filename) {
  //? In case of unknown data.
  if (filename.endsWith('.dat')) return 'binary';
  final imageEndings = [
    '.jpg',
    '.jpeg',
    '.jfif',
    '.pjpeg',
    '.pjp',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.dib',
    '.wbmp',
  ];
  final isImage = imageEndings.fold<bool>(
      false,
      (previousValue, element) =>
          (filename.endsWith(element) || previousValue));
  return isImage ? 'image' : 'video';
}

/// Find the path to the current platform's documents directory.
///
/// On iOS this is NSDocumentDirectory, on Android the AppData directory.
Future<String> get _localPath async =>
    (await getApplicationDocumentsDirectory()).path;

/// Returns the full file path of the file adressed by [filename].
///
/// [path] as the correct user directory path of the device has to be
/// provided.
///
/// Files will be stored in `<path>/<directory>/<filename with extension>`
/// where `<directory>` is either `image`, `video` or `binary` depending
/// on the given filename's type. See [_getFileType] for more info on how
/// this is determined.
String _getFilepath(String path, String filename) {
  var directory = _getFileType(filename);
  return '$path/$directory/$filename';
}

class _MediaFileStorage {
  /// Returns a reference to the file's full location.
  Future<File> _getLocalFile(filename) async {
    final path = await _localPath;
    final filepath = _getFilepath(path, filename);
    return File(filepath);
  }

  /// Writes a [File] called [filename]  in the device's appropriate
  /// directory containing the contents of [url].
  ///
  /// This will download the required data from [url] using an Http
  /// GET request. Then the contents are written on a [File] object
  /// with the correct reference. If such a file didn't exist before
  /// calling this, this will create that file. Otherwise the old
  /// contents of that file reference will be overridden.
  ///
  /// Technically [filename] could be optional, if the url contains
  /// the file's name and extension. But since that is not neccessarily
  /// the case [filename] in the form of `image1.png` or similar has to
  /// be provided.
  ///
  /// Completes the Future and returns null if either the reading
  /// operation or the download fails.
  Future<File?> writeMediaToDisc({
    required String url,
    required String filename,
  }) async {
    try {
      // Downloading the url's contents as bytes.
      final response = await http.get(Uri.parse(url));
      final List<int> bytes = response.bodyBytes;

      // Getting/creating a reference to the media's local file.
      var file = await _getLocalFile(filename);
      if (!(await file.exists())) {
        file = await file.create(recursive: true);
      }

      // Writing to that file.
      return await file.writeAsBytes(bytes);
    } catch (e) {
      print('Exception in writeMediaToDisc: $e');
      return null;
    }
  }

  /// Deletes the file named [filename] (in its correct path) if it exists.
  Future<void> deleteMediaFromDiscIfPresent(String filename) async {
    try {
      final file = await _getLocalFile(filename);
      file.delete();
    } catch (e) {
      return;
    }
  }

  /// Reads media from given file as byte array and returns those
  /// bytes as [List<int>]. This is usable for almost every byte
  /// operation from other libraries that use [List<Uint8>].
  ///
  /// If the reading operation fails, this will return null.
  Future<List<int>?> readMediaAsBytes(String filename) async {
    try {
      // Getting a reference to the media's local file.
      final file = await _getLocalFile(filename);

      // Reading the file.
      final bytes = await file.readAsBytes();
      return bytes;
    } catch (e) {
      print('Exception in readMediaAsBytes: $e');
      return null;
    }
  }

  /// Reads media from given file as file and returns a reference
  /// to that file.
  ///
  /// This cannot fail, since no IO operations are being performed.
  Future<File> readMediaAsFile(String filename) async {
    // Getting a reference to the media's local file.
    final file = await _getLocalFile(filename);
    return file;
  }
}

/// Handles storing as well as (de-)seriazing a list of [_MediaData] objects.
class _LoadedMediaStorage {
  List<_MediaData> _store = <_MediaData>[];

  /// Returns a reference to the main file's full location.
  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/loaded_media.json');
  }

  /// Checks if a data entry for the given [url] is already loaded on the
  /// device.
  bool isDataLoaded(String url) =>
      _store.map((e) => e.url).toList().contains(url);

  /// Either returns the [_MediaData] entry for the given [url] or returns
  /// null if that url has not been loaded yet.
  _MediaData? getEntry(String url) {
    if (!isDataLoaded(url)) return null;
    return _store.where((e) => e.url == url).toList()[0];
  }

  /// Pushes [data] into [_store] and triggers an IO operation
  /// to serialize the entire [_store].
  ///
  /// This also returns the newest reference to the main file
  /// containing the list of all loaded [_MediaData].
  Future<File?> addToStore(_MediaData data) async {
    _store.add(data);
    return await writeStore();
  }

  /// Deletes all [_MediaData] objects from the store and
  /// returns their filenames as a list to delete them
  /// later on.
  ///
  ///! Important: Don't call this after adding a new entry.
  ///!            All new entries are to be added after this
  ///!            has completed so they don't get deleted.
  List<String> removeFromStoreIfPresent(String url) {
    final data = _store.where((e) => e.url == url).toList();
    final filenames = <String>[];
    if (data.isNotEmpty) {
      //? At least one entry with the url found.
      // ignore: avoid_function_literals_in_foreach_calls
      data.forEach((e) {
        filenames.add(e.filename);
        _store.remove(e);
      });
      return filenames;
    }
    //? No such entry found.
    return <String>[];
  }

  /// Converts all loaded [_MediaData] inside [_store] to json objects
  /// and writes them all as json list to the device's storage as
  /// `loaded_media.json`.
  ///
  /// This also returns the newest reference to the main file
  /// containing the list of all loaded [_MediaData]. If anything went
  /// wrong, this returns null.
  Future<File?> writeStore() async {
    try {
      // Getting reference/creating file.
      var file = await _localFile;
      if (!(await file.exists())) {
        file = await file.create(recursive: true);
      }

      // Converting all loaded data entries to Map<String, dynamic> and
      // writing them all as a JSON list to the file.
      var list = <Map>[];
      // ignore: avoid_function_literals_in_foreach_calls
      _store.forEach((e) => list.add(e.toJson()));
      var jsonString = jsonEncode(list);
      return await file.writeAsString(jsonString);
    } catch (e) {
      print('Exception in writeStore: $e');
      return null;
    }
  }

  /// Reads `loaded_media.json` and updates [_store]'s entries with
  /// the ones serialized in said file.
  ///
  /// This also returns a reference to the contents of the main file.
  /// If anything went wrong, this will return null.
  Future<List<_MediaData>?> readStore([bool update = true]) async {
    try {
      if (update) {
        // Getting a reference to the main file.
        final file = await _localFile;

        // Reading the contents as list.
        final jsonString = await file.readAsString();
        List list = jsonDecode(jsonString);
        var tmp = <_MediaData>[];
        for (var e in list) {
          tmp.add(_MediaData.fromJson(e as Map<String, dynamic>));
        }
        _store = tmp;
      }
      return _store;
    } catch (e) {
      print('Exception in readStore: $e');
      return null;
    }
  }
}

/// Handles all IO operations for loaded files as well as the table
/// containing all loaded files.
///
/// This internally contains two storages, [_entryStorage] and
/// [_listStorage].
///
/// _listStorage: contains list of [_MediaData] which is basically
/// metadata for stored entries on the devide.
///
/// _entryStorage: contains functions to load, download and write
/// media data from the list above or the internet.
///
/// This class keeps track of all loaded media using their metadata
/// from [_listStorage]'s list. That list is updated after every IO
/// operation if needed. To access a medium this class searches if
/// required medium is already loaded by checking if any entry from
/// the aforementioned list contains a given url. If it does then that
/// search's result's corresponding file can be loaded and returned
/// using [_entryStorage] and the file's name set in its metadata.
/// Otherwise [_entryStorage] is used to download the medium, store it
/// on the device, trigger an update on [_listStorage] and after all
/// that return the new file.
class MediaStorage {
  final _MediaFileStorage _entryStorage;
  final _LoadedMediaStorage _listStorage;

  _MediaFileStorage get entryStore => _entryStorage;
  _LoadedMediaStorage get mainStore => _listStorage;

  MediaStorage()
      : _entryStorage = _MediaFileStorage(),
        _listStorage = _LoadedMediaStorage();

  /// Reads the stored list of all downloaded data. Call this on start.
  Future<void> init() async {
    _listStorage.readStore();
  }

  /// Returns a list of all loaded [_MediaData] objects in form of a
  /// json-esque Map.
  List<Map> listLoaded() {
    final list = <Map>[];
    // ignore: avoid_function_literals_in_foreach_calls
    _listStorage._store.forEach((e) => list.add(e.toJson()));
    return list;
  }

  Future<dynamic> _getData(
    String url,
    Function read, {
    String? filename, // Name of the new file, if it has to be created.
    bool isUpdate = false,
  }) async {
    bool isDataLoaded = _listStorage.isDataLoaded(url);
    //? If data is loaded and not needed to be updated, then return the file
    //? from the metadata's info.
    if (isDataLoaded && !isUpdate) {
      print('File was loaded and is being returned as is from the device.');
      var data = _listStorage.getEntry(url)!;
      print('This file was last updated on ${data.lastUpdate}.');
      return await read(data.filename);
    }
    //? Otherwise a new download is requested.
    print('Downloading the data and updating everything.');
    filename ??=
        '${DateTime.now().toIso8601String().replaceAll('-', '_').replaceAll(':', '_').split('.')[0]}.dat';
    var res =
        await _entryStorage.writeMediaToDisc(url: url, filename: filename);
    //? Downloading went wrong.
    if (res == null) return null;
    //? If not, then the list is updated.
    var newEntry = _MediaData(
      url: url,
      filename: filename,
      type: _getFileType(filename),
      lastUpdate: DateTime.now(),
    );
    //? Removing the previous entries with this url.
    final filesToDelete = _listStorage.removeFromStoreIfPresent(url);
    //? Removing the prevously downloaded file of this url.
    for (var name in filesToDelete) {
      await _entryStorage.deleteMediaFromDiscIfPresent(name);
    }
    // Serializes everything after updating.
    await _listStorage.addToStore(newEntry);
    print('Downloaded data, wrote it to storage and updated everything.');
    return await read(filename);
  }

  /// Returns the data from [url] as [File] or null, if an error occurred.
  ///
  /// If you need the data as byte array, use [getDataAsBinary].
  ///
  /// If [url]'s contents are already loaded and [isUpdate] is not set,
  /// then the loaded data will be read from the device's storage and
  /// returned as is. Otherwise this will firstly try to download the data
  /// from [url] and store that as a binary file on the device, then update
  /// the list of all loaded data and return the newly downloaded file as
  /// [File].
  ///
  /// If a download is needed then [filename] has to be set. The downloaded
  /// data will be stored on the correct system path under the name [filename].
  /// If no name is given but a new file is to be created, this function will
  /// create a file named after the current date with file extension `.dat`.
  Future<File?> getDataAsFile(
    String url, {
    String? filename,
    bool isUpdate = false,
  }) async =>
      await _getData(
        url,
        _entryStorage.readMediaAsFile,
        filename: filename,
        isUpdate: isUpdate,
      );

  /// Returns the data from [url] as [List<int>] or null, if an error occurred.
  /// The returned list is a list of all bytes of the file and can be
  /// interpreted as any Uint8 parameter required in other functions.
  ///
  /// If you need the data as [File], use [getDataAsFile].
  ///
  /// If [url]'s contents are already loaded and [isUpdate] is not set,
  /// then the loaded data will be read from the device's storage and
  /// returned as is. Otherwise this will firstly try to download the data
  /// from [url] and store that as a binary file on the device, then update
  /// the list of all loaded data and return the newly downloaded file as
  /// [List<int>].
  ///
  /// If a download is needed then [filename] has to be set. The downloaded
  /// data will be stored on the correct system path under the name [filename].
  /// If no name is given but a new file is to be created, this function will
  /// create a file named after the current date with file extension `.dat`.
  Future<List<int>?> getDataAsBinary(
    String url, {
    String? filename,
    bool isUpdate = false,
  }) async =>
      await _getData(
        url,
        _entryStorage.readMediaAsBytes,
        filename: filename,
        isUpdate: isUpdate,
      );
}
