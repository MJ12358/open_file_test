import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: MainApp());
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late List<File> _files;
  late StreamController<List<File>> _streamController;

  // this is from the 'path_provider' package
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
            icon: const Icon(Icons.create_new_folder),
            onPressed: _createFile,
          )
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
                onTap: () => _openFile(file),
                onLongPress: () => _deleteFile(file),
              );
            },
          );
        },
      ),
    );
  }

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

  Future<void> _createFile() async {
    final Directory dir = await directory;
    final String name = DateTime.now().millisecondsSinceEpoch.toString();
    final File file = File('${dir.path}/$name.txt');

    file.writeAsStringSync('test');

    _files.add(file);
    _streamController.add(_files);
  }

  Future<void> _openFile(File file) async {
    try {
      // this permission shouldn't be required
      // since we are reading from our own app's directory
      // "external-files-path" represents the apps own
      // private external storage
      // eg. "/sdcard/Android/data/com.example.app/files"
      // but what about when this file is stored in
      // eg. "/data/user/0/com.example.app"
      await Permission.storage.request();
    } catch (e) {
      _showDialog('Permission Failed', e.toString());
    }

    try {
      // when attempting to open a file within our own app's directory
      // this will fail,
      final OpenResult result = await OpenFile.open(file.path);
      final String message = 'Type: ${result.type}\nMessage: ${result.message}';
      if (result.type != ResultType.done) {
        _showDialog('OpenFile Result', message);
      }
    } catch (e) {
      _showDialog('OpenFile Failed', e.toString());
    }
  }

  void _deleteFile(File file) {
    file.deleteSync();
    _files.remove(file);
    _streamController.add(_files);
  }

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
}
