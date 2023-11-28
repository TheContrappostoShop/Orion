import 'dart:async';
import 'dart:io';
import 'details_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';

void checkFullDiskAccess(BuildContext context) {
  final documentsDir =
      Directory('/Users/${Platform.environment['USER']}/Documents');
  try {
    documentsDir.listSync();
  } catch (e) {
    if (e is FileSystemException) {
      final executablePath = Platform.resolvedExecutable;
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Full Disk Access Required'),
            content: Text(
              'This app requires full disk access. Please open System Preferences, '
              'navigate to Security & Privacy > Privacy > Full Disk Access, '
              'and check the box for this app. The app is located at: $executablePath',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }
}

/// The files screen
class FilesScreen extends StatefulWidget {
  const FilesScreen({Key? key}) : super(key: key);
  @override
  _FilesScreenState createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late Directory _directory;
  late List<FileSystemEntity> _files;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkFullDiskAccess(context);
    });
    _getFiles();
  }

  List<FileSystemEntity> getAccessibleDirectories(Directory directory) {
    var accessibleDirectories = <FileSystemEntity>[];
    var entities = directory.listSync();
    for (var entity in entities) {
      if (entity is Directory) {
        try {
          entity.listSync(); // Try to read the directory
          accessibleDirectories.add(entity); // If successful, add to the list
        } catch (e) {
          if (e is FileSystemException) {
            // If a FileSystemException is thrown, the directory is not accessible
            // So we do nothing and move on to the next entity
          }
        }
      }
    }
    return accessibleDirectories;
  }

  int _compareFileTypes(FileSystemEntity a, FileSystemEntity b) {
    bool aIsSl1 = a is File && a.path.toLowerCase().endsWith('.sl1');
    bool bIsSl1 = b is File && b.path.toLowerCase().endsWith('.sl1');
    if (aIsSl1 && !bIsSl1) return -1;
    if (!aIsSl1 && bIsSl1) return 1;
    return 0;
  }

  Future<void> _getFiles() async {
    //final Directory directory = Directory.systemTemp;
    final Directory directory =
        Directory('/Users/${Platform.environment['USER']}/Documents');
    List<FileSystemEntity> files = getAccessibleDirectories(directory);
    files = files
        .where((file) =>
            file is Directory && !path.basename(file.path).startsWith('.') ||
            file is File &&
                !path.basename(file.path).startsWith('.') &&
                path.basename(file.path).toLowerCase().endsWith('.sl1'))
        .toList()
      ..sort((a, b) {
        int compare = _compareFileTypes(a, b);
        if (compare != 0) return compare;
        return a.path.compareTo(b.path);
      });
    setState(() {
      _directory = directory;
      _files = files;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_directory.path.replaceFirst('/Users/paul/', '')),
      ),
      // ignore: unnecessary_null_comparison
      body: _directory == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _files.length,
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return ListTile(
                      title: const Text('↰  Parent Directory',
                          style: TextStyle(fontSize: 24)),
                      onTap: () {
                        try {
                          final parentDirectory = _directory.parent;
                          setState(() {
                            _directory = parentDirectory;
                            _files = parentDirectory
                                .listSync()
                                .where((file) =>
                                    file is Directory &&
                                        !path
                                            .basename(file.path)
                                            .startsWith('.') ||
                                    file is File &&
                                        !path
                                            .basename(file.path)
                                            .startsWith('.') &&
                                        path
                                            .basename(file.path)
                                            .toLowerCase()
                                            .endsWith('.sl1'))
                                .toList()
                              ..sort((a, b) {
                                int compare = _compareFileTypes(a, b);
                                if (compare != 0) return compare;
                                return a.path.compareTo(b.path);
                              });
                            ;
                          });
                        } catch (e) {
                          if (e is FileSystemException) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Operation not permitted'),
                              ),
                            );
                          }
                        }
                      });
                } else {
                  final FileSystemEntity file = _files[index];
                  final String fileName = path.basename(file.path);
                  //final String fileExtension = path.extension(file.path);
                  final String displayName =
                      file is Directory ? '$fileName/' : fileName;
                  final String fileSize = file is File
                      ? file.statSync().size >= 1000000
                          ? '${(file.statSync().size / 1048576).toStringAsFixed(2)} MB'
                          : file.statSync().size >= 1000
                              ? '${(file.statSync().size / 1024).toStringAsFixed(2)} KB'
                              : '${file.statSync().size} B'
                      : '';
                  return Container(
                      margin: const EdgeInsets.symmetric(vertical: 10.0),
                      child: ListTile(
                        title: Text(
                          displayName,
                          style: TextStyle(
                              fontSize: 24,
                              color: file is Directory
                                  ? Colors.grey
                                  : Colors.white),
                        ),
                        subtitle: file is File ? Text(fileSize) : null,
                        onTap: () {
                          try {
                            if (file is Directory) {
                              setState(() {
                                _directory = file;
                                _files = file
                                    .listSync()
                                    .where((file) =>
                                        file is Directory &&
                                            !path
                                                .basename(file.path)
                                                .startsWith('.') ||
                                        file is File &&
                                            !path
                                                .basename(file.path)
                                                .startsWith('.') &&
                                            path
                                                .basename(file.path)
                                                .toLowerCase()
                                                .endsWith('.sl1'))
                                    .toList()
                                  ..sort((a, b) {
                                    int compare = _compareFileTypes(a, b);
                                    if (compare != 0) return compare;
                                    return a.path.compareTo(b.path);
                                  });
                                ;
                              });
                            } else {
                              if (file is File) {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          DetailScreen(file: file),
                                    ));
                              }
                            }
                          } catch (e) {
                            if (e is FileSystemException) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Operation not permitted'),
                                ),
                              );
                            }
                          }
                        },
                        trailing: file is File
                            ? IconButton(
                                icon: const Icon(Icons.delete),
                                iconSize: 32.0,
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: const Text('Confirm Delete'),
                                        content: const Text(
                                            'Are you sure you want to delete this file?'),
                                        actions: <Widget>[
                                          TextButton(
                                            child: const Text('Cancel'),
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                          TextButton(
                                            child: const Text('Delete'),
                                            onPressed: () {
                                              file.deleteSync();
                                              setState(() {
                                                _files.removeAt(index);
                                              });
                                              Navigator.of(context).pop();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'File deleted successfully.')),
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              )
                            : const SizedBox.shrink(),
                      ));
                }
              },
            ),
    );
  }
}
