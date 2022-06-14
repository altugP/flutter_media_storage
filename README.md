# Flutter Media Storage

> A simple package to download and store/persist media in flutter apps.

---

## 📋 Table of Contents

- [Setup and Usage](#setup-and-usage)
  - [Installation](#installation)
  - [Usage](#usage)
- [How it works](#how-it-works)
- [Example app](#example-app)

---

<h2 id="setup-and-usage">🔧 Setup and Usage</h2>

### Installation

#### Option 1: Depending on it

You can load this package as dependency by adding this git repository to your
existing `pubspec.yaml` as:

```yml
dependencies:
  flutter_media_storage:
    git:
      url: git://github.com/altugP/flutter_media_storage.git
```

After adding the git dependency you install it by running `flutter pug get` as
you would any "normal"/published package. Then you can import the library in
Dart code using:

```dart
import 'package:flutter_media_storage/flutter_media_storage.dart';
```

#### Option 2: Copy-Paste the required file

This library was created as a single file library, meaning you can just copy
the `flutter_media_storage.dart` file from the `src` directory, paste it into
your code base at your desired destination and use it as if you coded this
yourself.

### Usage

To use this library all you need is an instance of `MediaStorage`:

```dart
import 'package:flutter_media_storage/flutter_media_storage.dart';

// ...

// Step 1: Create an instance.
final storage = MediaStorage();
```

To assure correctness you should first load all the stored files from the device
before using the storage. This is done by calling `init()` which returns a Future:

```dart
// Step 2: Call init() to load all potentially existing files on the device.
await storage.init();
```

Now `storage` can be used to get data from urls:

```dart
// Example url for an image.
final url = 'https://www.kindacode.com/wp-content/uploads/2022/02/orange.jpeg';

//? Getting the file. If it is not loaded on the device it will be called
//? <current_datetime>.dat and will be classified as binary file. If it is
//? already downloaded this will return the correct file as is from storage.
final File? = await storage.getDataAsFile(url);

//? Same call as above, but in case of a download the file will be called
//? orange.jpg and will be categorized as image file.
final File? = await storage.getDataAsFile(
  url,
  filename: 'orange.jpg',
);

//? Same call as the previous two, but this will always force a new download.
//? The old entry will be deleted.
final File? = await storage.getDataAsFile(
  url,
  filename: 'orange.jpg',
  isUpdate: true,
);

//? The three calls above also be done using `getDataAsBinary()` using the same
//? args. But that will return a List<int>?.

//? Getting a list of all loaded medias' data.
final data = storage.listLoaded();
for (Map map in data) {
  print('${map['url']} locally stored. Was last updated on ${DateTiime.parse(map['last_update'])}');
}
```

---

<h2 id="how-it-works">🔍 How it works</h2>

Brief overview of the classes:

- **MediaData**: A serializable object that represents one downloaded media entity. This is mainly metadata. The stored information includes: original url, filename on disc, file type (video, image, unspecified) and date of last update.
- **MediaFileStorage**: A class that handles IO operations to (de-)serialize `MediaData` objects as well as the media files themself as byte files. This class is used to download media, create the metadata objects and handle all of them.
- **LoadedMediaStorage**: A class that handles (de-)serializing a list of `MediaData` objects. Each downloaded medium triggers the creation of a `MediaData` object. If such an object exists for a url then a file containing the content of that url is present on the device and the object points to that file. `LoadedMediaStorage` is used to persist a list of all `MediaData` objects
and allow searching for urls in that list.
- **MediaStorage**: The main class to use as a user. It contains private instances of the aforementioned classes and calls the required functions as needed. It exposes two `get` functions that take in a url and optionally a filename if the user wants to specify where to save the contents of the url.

Each media (either a video or an image) is adressed by its original url. The
user calls `getDataAsFile()` or `getDataAsBinary()` and provides a url. Then
a search is triggered. If the url is found in one of the stored `MediaData`
objects then the file with the contents of the url is already stored on the
device. If the user has not set the `isUpdate` flag in the functions then that
file is returned as either a file or a list of bytes. Otherwise it is treated
as if the file didn't exist. An HTTP GET request is performed to the url and
the responses body is interpreted as bytes and stored in a file. The file will
either be named after the current date (.dat) or be named after the optional
file name the user has provided in the two functions. Then a `MediaData` object
of this url is created and stored into the list. IO calls to persist the
changes are triggered. After they have completed the required file is returned.
If something goes wrong null will be returned.

---

<h2 id="example-app">📱 Example app</h2>
