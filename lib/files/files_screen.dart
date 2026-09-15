/*
* Orion - Files Screen
* Copyright (C) 2024 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:orion/files/search_file_screen.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

ScrollController _scrollController = ScrollController();

Directory getInitialDir(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.macOS:
      return Directory('/Users/${Platform.environment['USER']}/Documents');
    case TargetPlatform.linux:
      return Directory(
          '/home/${Platform.environment['USER']}/printer_data/gcodes');
    case TargetPlatform.windows:
      return Directory(
          '%userprofile%'); // WARN Not sure if that works for windows developers. To be tested
    default:
      return Directory(
          '/home/${Platform.environment['USER']}/printer_data/gcodes');
  }
}

/// The files screen
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  FilesScreenState createState() => FilesScreenState();
}

class FilesScreenState extends State<FilesScreen> {
  late Directory _directory;
  late List<FileSystemEntity> _files;
  bool _sortByAlpha = true;
  bool _sortAscending = true;

  @override
  void initState() {
    _directory = getInitialDir(Theme.of(context).platform);
    _files = [];
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
        //_sortByAlpha = false;
        //_toggleSortOrder();
      });
    });
  }

  void refresh() {
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
    final Directory directory = getInitialDir(Theme.of(context).platform);
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
        title: Text(
          path.basename(_directory.path) == 'gcodes'
              ? FlutterI18n.translate(context, 'files.printFiles')
              : path.basename(_directory.path) == 'Download' ||
                      path.basename(_directory.path) == "Downloads"
                  ? path.basename(_directory.path)
                  : _directory.path,
        ),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: IconButton(
              icon: const Icon(Icons.search),
              iconSize: 30,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchFileScreen(),
                  ),
                );
              },
            ),
          ),
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
              controller: _scrollController,
              itemCount: _files.length + 1,
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.subdirectory_arrow_left_rounded),
                    title: Row(
                      children: [
                        I18nText('files.leaveDirectory',
                            child: Text('', style: TextStyle(fontSize: 24))),
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
                            SnackBar(
                              content: Text(FlutterI18n.translate(
                                  context, 'print.notPermitted')),
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
                            _scrollController.jumpTo(0.0);
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
                              /*Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      DetailScreen(file: file),
                                ),
                              );*/
                            }
                          }
                        } catch (e) {
                          if (e is FileSystemException) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(FlutterI18n.translate(
                                    context, 'print.notPermitted')),
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
                                    return GlassAlertDialog(
                                      title: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_forever_rounded,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                            size: 26,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(FlutterI18n.translate(
                                                    context,
                                                    'files.deleteFile')),
                                                Text(
                                                  path.basename(file.path),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.grey.shade400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      content: Text(
                                        FlutterI18n.translate(
                                            context, 'files.deleteConfirm'),
                                        style: TextStyle(
                                          height: 1.5,
                                          fontSize: 20,
                                        ),
                                      ),
                                      actions: [
                                        GlassButton(
                                          tint: GlassButtonTint.neutral,
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(0, 60),
                                          ),
                                          child: Text(FlutterI18n.translate(
                                              context, 'common.cancel')),
                                        ),
                                        GlassButton(
                                          tint: GlassButtonTint.negative,
                                          onPressed: () {
                                            file.deleteSync();
                                            setState(() {
                                              _files.removeAt(index - 1);
                                            });
                                            Navigator.of(context).pop();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    FlutterI18n.translate(
                                                        context,
                                                        'files.fileDeleted')),
                                              ),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size(0, 60),
                                          ),
                                          child: Text(FlutterI18n.translate(
                                              context, 'common.delete')),
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
