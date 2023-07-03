import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:dart_extensionz/dart_extensionz.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// https://github.com/crazecoder/open_file/issues/255
///
/// To see the issue in action,
/// please modify "android\app\src\main\res\xml\filepaths.xml".
///
/// And possibly "android\app\src\main\AndroidManifest.xml".
///
/// Then run `flutter clean` and `flutter pub get`.

void main() {
  runApp(const App());
}

/// Entry point for this example app
/// wraps [Main] in a [MaterialApp].
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Main());
  }
}

/// The main stateful widget.
class Main extends StatefulWidget {
  const Main({super.key});

  @override
  State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  late List<File> _files;
  late StreamController<List<File>> _streamController;

  /// This is from the 'path_provider' package.
  ///
  /// A directory where the application may place data that is user-generated.
  Future<Directory> get directory async {
    final Directory dir = await getApplicationDocumentsDirectory();
    log('PathProvider: ${dir.path}');
    return dir;
  }

  @override
  void initState() {
    super.initState();
    _files = <File>[];
    _streamController = StreamController<List<File>>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open File Test'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openAppSettings,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: () {
              _getFileTypeSelector().then((String? value) {
                if (value != null) {
                  _createFile(value);
                }
              });
            },
          ),
        ],
      ),
      body: StreamBuilder<List<File>>(
        stream: _streamController.stream,
        builder: (BuildContext context, AsyncSnapshot<List<File>> snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.length,
            itemBuilder: (_, int index) {
              final File file = snapshot.data![index];
              return ListTile(
                title: Text(file.path),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  _getOpenerSelector().then((FileOpener? value) {
                    if (value != null) {
                      _openFile(file, value);
                    }
                  });
                },
                onLongPress: () => _deleteFile(file),
              );
            },
          );
        },
      ),
    );
  }

  /// List the files from our [directory].
  Future<void> _listFiles() async {
    final Directory dir = await directory;

    return dir
        .list(followLinks: false)
        .toList()
        .then((List<FileSystemEntity> entities) {
      _files = entities.whereType<File>().toList();
      _streamController.add(_files);
    });
  }

  /// Create a file with the specified [fileType].
  Future<void> _createFile(String fileType) async {
    final Directory dir = await directory;
    final String name = DateTime.now().millisecondsSinceEpoch.toString();
    final File file = File('${dir.path}/$name.$fileType');

    file.writeAsStringSync('test');

    _files.add(file);
    _streamController.add(_files);
  }

  /// Open a [file] with the specified [opener].
  Future<void> _openFile(File file, FileOpener opener) async {
    late String errorTitle;

    try {
      errorTitle = 'Permission Failed';
      await _getPermission();

      switch (opener) {
        case FileOpener.androidIntent:
          errorTitle = 'AndroidIntent Failed';
          await _openViaAndroidIntentPlus(file);
        case FileOpener.openFile:
          errorTitle = 'OpenFile Failed';
          await _openViaOpenFile(file);
        case FileOpener.urlLauncher:
          errorTitle = 'UrlLauncher Failed';
          await _openViaUrlLauncher(file);
        // case FileOpener.flutterOpenFilez:
        //   errorTitle = 'FlutterOpenFilez Failed';
        //   await _openViaFlutterOpenFilez(file);
      }
    } catch (e) {
      _showDialog(errorTitle, e.toString());
    }
  }

  /// Delete a [file].
  void _deleteFile(File file) {
    file.deleteSync();
    _files.remove(file);
    _streamController.add(_files);
  }

  /// Show a dialog with the specified [title] and [content].
  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(content)),
        );
      },
    );
  }

  /// Show a dialog to select a file type.
  ///
  /// This allows changing the file's extension.
  Future<String?> _getFileTypeSelector() {
    final List<String> fileTypes = <String>[
      'html',
      'json',
      'mp4',
      'mp3',
      'pdf',
      'txt',
    ];

    return showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Choose File Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: fileTypes.map((String e) {
              return SimpleDialogOption(
                child: Text(e),
                onPressed: () => Navigator.pop(context, e),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Show a dialog to select the file opener.
  ///
  /// This allows using different packages to open the file.
  Future<FileOpener?> _getOpenerSelector() {
    return showDialog<FileOpener>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Choose Opener'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: FileOpener.values.map((FileOpener e) {
              return SimpleDialogOption(
                child: Text(e.label),
                onPressed: () => Navigator.pop(context, e),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Obtain permission to open a file.
  ///
  /// This permission shouldn't be required
  /// since we are reading from our own app's directory.
  ///
  /// "external-files-path" represents the apps own
  /// private external storage
  /// eg. "/sdcard/Android/data/com.example.app/files"
  ///
  /// But what about when this file is stored in
  /// eg. "/data/user/0/com.example.app"
  Future<void> _getPermission() async {
    final PermissionStatus status = await Permission.storage.request();
    if (status.isDenied) {
      throw Exception(status.toString());
    }
  }

  /// Open the system settings
  Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  /// Open the [file] with the 'android_intent_plus' package.
  Future<void> _openViaAndroidIntentPlus(File file) {
    final AndroidIntent intent = AndroidIntent(
      action: 'action_view',
      data: Uri.encodeFull(file.path),
      type: file.mimeType, // this is from the 'dart_extensions' package
    );
    return intent.launch();
  }

  /// Open the [file] with the 'open_file' package.
  Future<void> _openViaOpenFile(File file) async {
    final OpenResult result = await OpenFile.open(file.path);
    final String message = 'Type: ${result.type}\nMessage: ${result.message}';
    if (result.type != ResultType.done) {
      _showDialog('OpenFile Result', message);
    }
  }

  /// Open the [file] with the 'url_launcher' package.
  Future<void> _openViaUrlLauncher(File file) {
    return launchUrlString(file.path);
  }

  /// Open the [file] with the 'flutter_open_filez' package.
  // Future<void> _openViaFlutterOpenFilez(File file) {
  //   return FlutterOpenFilez().open(file.path);
  // }
}

enum FileOpener {
  androidIntent,
  openFile,
  urlLauncher,
  // flutterOpenFilez, // would like to create my own plugin
}

extension on FileOpener {
  String get label {
    switch (this) {
      case FileOpener.androidIntent:
        return 'android_intent_plus';
      case FileOpener.openFile:
        return 'open_file';
      case FileOpener.urlLauncher:
        return 'url_launcher';
      // case FileOpener.flutterOpenFilez:
      //   return 'flutter_open_filez';
    }
  }
}
