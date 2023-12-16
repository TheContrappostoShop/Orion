import 'dart:async';
import 'dart:io';
import 'details_screen.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  // ignore: library_private_types_in_public_api
  _FilesScreenState createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late Directory _directory;
  late List<FileSystemEntity> _files;
  bool _sortByAlpha = true;
  bool _sortAscending = true;

  @override
  void initState() {
    _directory = Directory('/Users/${Platform.environment['USER']}/Downloads');
    _files = [];
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkFullDiskAccess(context);
      _getFiles();

      Future.delayed(const Duration(seconds: 0), () {
        setState(() {
          _files = _directory
              .listSync()
              .where((file) =>
                  file is Directory &&
                      !path.basename(file.path).startsWith('.') ||
                  file is File &&
                      !path.basename(file.path).startsWith('.') &&
                      path.basename(file.path).toLowerCase().endsWith('.sl1'))
              .toList()
            ..sort((a, b) {
              int compare = _compareFileTypes(a, b);
              if (compare != 0) return compare;
              return a.path.toLowerCase().compareTo(b.path.toLowerCase());
            });
        });
        _sortByAlpha = false;
        _toggleSortOrder();
      });
    });
  }

  void refresh() {
    _getFiles();
    setState(
      () {
        _files = _directory
            .listSync()
            .where((file) =>
                file is Directory &&
                    !path.basename(file.path).startsWith('.') ||
                file is File &&
                    !path.basename(file.path).startsWith('.') &&
                    path.basename(file.path).toLowerCase().endsWith('.sl1'))
            .toList();
      },
    );
    _sortAscending = !_sortAscending;
    _toggleSortOrder();
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
        Directory('/Users/${Platform.environment['USER']}/Downloads');
    List<FileSystemEntity> files = getAccessibleDirectories(directory);
    files = files
        .where((file) =>
            file is Directory &&
                !path.basename(file.path).startsWith('.') &&
                !path.basename(file.path).startsWith('\$RECYCLE.BIN') ||
            file is File &&
                !path.basename(file.path).startsWith('.') &&
                path.basename(file.path).toLowerCase().endsWith('.sl1'))
        .toList()
      ..sort((a, b) {
        int compare = _compareFileTypes(a, b);
        if (compare != 0) return compare;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
    setState(() {
      _directory = directory;
      _files = files;
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _sortAscending = !_sortAscending;
      _files.sort((a, b) {
        if (_sortByAlpha) {
          int compare = _compareFileTypes(a, b);
          if (compare != 0) return compare;
          return _sortAscending
              ? a.path.toLowerCase().compareTo(b.path.toLowerCase())
              : b.path.toLowerCase().compareTo(a.path.toLowerCase());
        } else {
          int compare = _compareFileTypes(a, b);
          if (compare != 0) return compare;
          return _sortAscending
              ? a.statSync().modified.compareTo(b.statSync().modified)
              : b.statSync().modified.compareTo(a.statSync().modified);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_directory.path.replaceFirst('/Users/paul/', '')),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: IconButton(
              icon: const Icon(Icons.sort_by_alpha),
              iconSize: 30,
              onPressed: () {
                _sortByAlpha = true;
                _toggleSortOrder();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: IconButton(
              icon: const Icon(Icons.date_range),
              iconSize: 30,
              onPressed: () {
                _sortByAlpha = false;
                _toggleSortOrder();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
            child: IconButton(
              icon: const Icon(Icons.refresh),
              iconSize: 30,
              onPressed: () {
                refresh();
              },
            ),
          ),
        ],
      ),
      // ignore: unnecessary_null_comparison
      body: _directory == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _files.length + 1,
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.subdirectory_arrow_left_rounded),
                    title: Row(
                      children: const [
                        Text('Leave Directory', style: TextStyle(fontSize: 24)),
                      ],
                    ),
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
                              return a.path
                                  .toLowerCase()
                                  .compareTo(b.path.toLowerCase());
                            });
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
                    },
                  );
                } else {
                  final FileSystemEntity file = _files[index - 1];
                  final String fileName = path.basename(file.path);
                  //final String fileExtension = path.extension(file.path);
                  final String displayName =
                      file is Directory ? fileName : fileName;
                  final String fileSize = file is File
                      ? file.statSync().size >= 1000000
                          ? '${(file.statSync().size / 1048576).toStringAsFixed(2)} MB'
                          : file.statSync().size >= 1000
                              ? '${(file.statSync().size / 1024).toStringAsFixed(2)} KB'
                              : '${file.statSync().size} B'
                      : '';
                  final String subtitle =
                      '$fileSize - ${DateFormat.yMd().add_jm().format(file.statSync().modified)}'; // Add this line
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 10.0),
                    child: ListTile(
                      leading: file is Directory
                          ? const IconTheme(
                              data: IconThemeData(color: Colors.grey),
                              child: Icon(Icons.folder),
                            )
                          : const Icon(Icons.insert_drive_file),
                      title: Text(
                        displayName,
                        style: TextStyle(
                            fontSize: 24,
                            color: file is Directory ? Colors.grey : null),
                      ),
                      subtitle: file is File ? Text(subtitle) : null,
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
                                  return a.path
                                      .toLowerCase()
                                      .compareTo(b.path.toLowerCase());
                                });
                            });
                          } else {
                            if (file is File) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      DetailScreen(file: file),
                                ),
                              );
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
                                              _files.removeAt(index - 1);
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
                    ),
                  );
                }
              },
            ),
    );
  }
}
