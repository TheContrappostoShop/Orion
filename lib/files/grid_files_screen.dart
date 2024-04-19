import 'dart:async';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:orion/files/search_file_screen.dart';
import 'package:path/path.dart' as path;

import 'details_screen.dart';

/*
 *    Orion Grid Files Screen
 *    Copyright (c) 2024 TheContrappostoShop (Paul S, shifubrams)
 *    GPLv3 Licensing (see LICENSE)
 */

ScrollController _scrollController = ScrollController();

Directory getInitialDir(platform) {
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
class GridFilesScreen extends StatefulWidget {
  const GridFilesScreen({super.key});
  @override
  GridFilesScreenState createState() => GridFilesScreenState();
}

class GridFilesScreenState extends State<GridFilesScreen> {
  late Directory _directory;
  late List<FileSystemEntity> _files;
  bool _sortByAlpha = true;
  bool _sortAscending = true;

  @override
  void initState() {
    _directory = getInitialDir(context);
    _files = [];
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getFiles();

      Future.delayed(const Duration(seconds: 0), () {
        setState(() {
          _files = _directory.listSync().where(_isValidFileOrDirectory).toList()
            ..sort((a, b) {
              int compare = _compareFileTypes(a, b);
              if (compare != 0) return compare;
              return a.path.toLowerCase().compareTo(b.path.toLowerCase());
            });
        });
      });
    });
  }

  void refresh() {
    setState(() {
      _files = _directory.listSync().where(_isValidFileOrDirectory).toList();
    });
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

  bool _isValidFileOrDirectory(FileSystemEntity entity) {
    return entity is Directory &&
            !path.basename(entity.path).startsWith('.') &&
            !path.basename(entity.path).startsWith('\$RECYCLE.BIN') ||
        entity is File &&
            !path.basename(entity.path).startsWith('.') &&
            path.basename(entity.path).toLowerCase().endsWith('.sl1');
  }

  int _compareFileTypes(FileSystemEntity a, FileSystemEntity b) {
    bool aIsSl1 = a is File && a.path.toLowerCase().endsWith('.sl1');
    bool bIsSl1 = b is File && b.path.toLowerCase().endsWith('.sl1');
    if (aIsSl1 && !bIsSl1) return -1;
    if (!aIsSl1 && bIsSl1) return 1;
    return 0;
  }

  List<FileSystemEntity> _sortFiles(List<FileSystemEntity> files) {
    files.sort((a, b) {
      int compare = _compareFileTypes(a, b);
      if (compare != 0) return compare;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return files;
  }

  Future<void> _getFiles() async {
    final Directory directory = getInitialDir(Theme.of(context).platform);
    List<FileSystemEntity> files = getAccessibleDirectories(directory);
    files = files.where(_isValidFileOrDirectory).toList();
    files = _sortFiles(files);
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

  String _getDisplayNameForDirectory(Directory directory) {
    final lookupTable = {
      'gcodes': 'Print Files',
      'Download': 'Download',
      'Downloads': 'Downloads',
      'Documents': 'Documents',
      'Desktop': 'Desktop',
    };

    String directoryName = path.basename(directory.path);
    return lookupTable[directoryName] ?? directory.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getDisplayNameForDirectory(_directory),
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
          : Padding(
              padding:
                  EdgeInsets.only(left: 10.sp, right: 10.sp, bottom: 10.sp),
              child: GridView.builder(
                controller: _scrollController,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    mainAxisSpacing: 5.sp,
                    crossAxisSpacing: 5.sp,
                    crossAxisCount: MediaQuery.of(context).orientation ==
                            Orientation.landscape
                        ? 4
                        : 2),
                itemCount: _files.length + 1,
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    // Card that navigates to the parent directory
                    return Card(
                      elevation: 1,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10.sp),
                        onTap: () {
                          try {
                            _scrollController.jumpTo(0);
                            final parentDirectory = _directory.parent;
                            setState(() {
                              _directory = parentDirectory;
                              _files = parentDirectory
                                  .listSync()
                                  .where(_isValidFileOrDirectory)
                                  .toList();
                              _files = _sortFiles(_files);
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
                        child: GridTile(
                          footer: const GridTileBar(
                            backgroundColor: Colors.transparent,
                          ),
                          child: Icon(
                            Icons.subdirectory_arrow_left_rounded,
                            size: 60.h,
                          ),
                        ),
                      ),
                    );
                  } else {
                    final FileSystemEntity file = _files[index - 1];
                    final String fileName = path.basename(file.path);
                    final String displayName =
                        file is Directory ? fileName : fileName;

                    // Card that navigates to the file or directory
                    return Card(
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10.sp),
                        onTap: () {
                          if (file is Directory) {
                            _scrollController.jumpTo(0);
                            setState(() {
                              _directory = file;
                              _files = _directory
                                  .listSync()
                                  .where(_isValidFileOrDirectory)
                                  .toList();
                              _files = _sortFiles(_files);
                            });
                          } else if (file is File) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DetailScreen(file: file),
                              ),
                            );
                          }
                        },
                        // File name that hovers over the file
                        child: GridTile(
                          footer: file is File
                              ? Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(10.sp),
                                      bottomRight: Radius.circular(10.sp),
                                    ),
                                  ),
                                  elevation: 2,
                                  child: GridTileBar(
                                    title: AutoSizeText(
                                      displayName,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      minFontSize: 20,
                                      style: TextStyle(
                                        fontSize: 24.sp,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyLarge!
                                            .color,
                                      ),
                                    ),
                                  ),
                                )
                              : GridTileBar(
                                  title: AutoSizeText(
                                    displayName,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    minFontSize: 20,
                                    style: TextStyle(
                                      fontSize: 24.sp,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                          child: file is Directory
                              ? IconTheme(
                                  data: const IconThemeData(color: Colors.grey),
                                  child: Icon(Icons.folder, size: 60.h),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(4.5),
                                  child: FutureBuilder<String>(
                                    future: DetailScreen.extractThumbnail(
                                        file as File,
                                        DetailScreen.generateHash(file.path)),
                                    builder: (BuildContext context,
                                        AsyncSnapshot<String> snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const CircularProgressIndicator();
                                      } else if (snapshot.error != null) {
                                        return const Icon(Icons.error);
                                      } else {
                                        return ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                              7.75), // Adjust the border radius as needed
                                          child: Image.file(
                                            File(snapshot.data!),
                                            fit: BoxFit
                                                .cover, // Use BoxFit.cover to ensure the image covers the entire card
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
    );
  }
}
