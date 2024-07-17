/*
* Orion - Grid Files Screen
* Copyright (C) 2024 TheContrappostoShop
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// ignore_for_file: unnecessary_type_check, use_build_context_synchronously
// import 'package:orion/files/search_file_screen.dart';

import 'dart:async';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/files/details_screen.dart';
import 'package:orion/util/error_handling/error_dialog.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_directory.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_file.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_item.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/util/sl1_thumbnail.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';

ScrollController _scrollController = ScrollController();

class GridFilesScreen extends StatefulWidget {
  const GridFilesScreen({super.key});
  @override
  GridFilesScreenState createState() => GridFilesScreenState();
}

class GridFilesScreenState extends State<GridFilesScreen> {
  final _logger = Logger('GridFiles');
  final ApiService _api = ApiService();

  late String _directory = '';
  late String _subdirectory = '';
  late String _defaultDirectory = '';

  late List<OrionApiItem> _items = [];
  late Future<List<OrionApiItem>> _itemsFuture = Future.value([]);
  late Completer<List<OrionApiItem>> _itemsCompleter =
      Completer<List<OrionApiItem>>();

  String location = '';
  //bool _sortByAlpha = true;
  //bool _sortAscending = true;
  bool _isUSB = false;
  bool _usbAvailable = false;
  bool _apiErrorState = false;
  bool _isLoading = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    final OrionConfig config = OrionConfig();
    _isUSB = config.getFlag('useUsbByDefault');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_defaultDirectory.isEmpty) {
        final items = await _getItems('<init>', true);
        if (items.isNotEmpty) {
          _defaultDirectory = path.dirname(items.first.path);
          _directory = _defaultDirectory;
        } else {
          _defaultDirectory = '~';
          _directory = _defaultDirectory;
        }
        _itemsCompleter.complete(items);
      }
    });
  }

  Future<void> refresh() async {
    //_sortAscending = !_sortAscending;
    //_toggleSortOrder();
    setState(() {
      _isLoading = true; // Indicate loading state
    });
    try {
      final items =
          await _getItems(_directory, false); // Fetch latest items from API
      _itemsCompleter = Completer<List<OrionApiItem>>(); // Reset the completer
      _itemsCompleter.complete(items); // Complete with new items
      setState(() {
        _items = items; // Update items
        _isLoading = false; // Reset loading state
      });
    } catch (e) {
      setState(() {
        _apiErrorState = true;
        showErrorDialog(context, 'PINK-CARROT');
        _isLoading = false;
      });
    }
  }

  Future<List<OrionApiItem>> _getItems(String directory,
      [bool init = false]) async {
    _logger.warning(
        await _api.usbAvailable() ? 'USB Available' : 'USB Not Available');
    _usbAvailable = await _api.usbAvailable();
    if (!_usbAvailable) _isUSB = false;
    try {
      setState(() {
        _isLoading = true;
      });
      _apiErrorState = false;
      _subdirectory = path.relative(directory, from: _defaultDirectory);
      if (init) _subdirectory = '';
      if (directory == _defaultDirectory) {
        _subdirectory = '';
      }

      location = _isUSB ? 'Usb' : 'Local';

      final itemResponse =
          await _api.listItems(location, 100, 0, _subdirectory);

      final List<OrionApiFile> files = (itemResponse['files'] as List)
          .where((item) => item != null)
          .map<OrionApiFile>((item) => OrionApiFile.fromJson(item))
          .toList();

      final List<OrionApiDirectory> dirs = (itemResponse['dirs'] as List)
          .where((item) => item != null)
          .map<OrionApiDirectory>((item) => OrionApiDirectory.fromJson(item))
          .toList();

      final List<OrionApiItem> items = [...dirs, ...files];
      if (items.isNotEmpty) {}

      /*if (kDebugMode) {
        print('---------------------------------------');
        print("Device: ${_isUSB ? 'USB' : 'Internal'}");
        print("Parent Path: $_parentPath");
        print("Subdirectory: $_subdirectory");
        print("Fetched: ${files.length} files and ${dirs.length} directories.");
      }*/

      setState(() {
        _isLoading = false;
      });
      return items;
    } catch (e) {
      _logger.severe('Failed to fetch files', e);
      setState(() {
        _isLoading = false;
      });
      _apiErrorState = true;
      showErrorDialog(context, 'PINK-CARROT');
      return [];
    }
  }

  /*void _toggleSortOrder() {
    setState(() {
      _items.sort((a, b) {
        if (a is OrionApiFile && b is OrionApiFile) {
          if (a.lastModified == null || b.lastModified == null) {
            return 0; // or any default value
          }
          return _sortAscending
              ? a.lastModified!.compareTo(b.lastModified!)
              : b.lastModified!.compareTo(a.lastModified!);
        }
        return 0;
      });
    });
  }*/

  String _getDisplayNameForDirectory(String directory) {
    if (directory == _defaultDirectory && !_apiErrorState) {
      return _isUSB == false ? 'Print Files (Internal)' : 'Print Files (USB)';
    }

    // If it's a subdirectory of the default directory, only show the directory name
    if (_apiErrorState) return 'Odyssey API Error';
    return "$directory ${_isUSB ? '(USB)' : '(Internal)'}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getDisplayNameForDirectory(_directory),
        ),
        centerTitle: false,
        actions: <Widget>[
          /*Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: IconButton(
              icon: const Icon(Icons.search,
                  color: Color.fromARGB(255, 99, 99, 99)),
              iconSize: 35,
              onPressed: () {
                // TODO: Re-implement search
                /*Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchFileScreen(),
                  ),
                );*/
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: IconButton(
              icon: const Icon(Icons.sort_by_alpha,
                  color: Color.fromARGB(255, 99, 99, 99)),
              iconSize: 35,
              onPressed: () {
                // TODO: Implement in API
                /*_sortByAlpha = true;
                _toggleSortOrder();*/
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 5.0),
            child: IconButton(
              icon: const Icon(Icons.date_range,
                  color: Color.fromARGB(255, 99, 99, 99)),
              iconSize: 35,
              onPressed: () {
                // TODO: Implement in API
                /*_sortByAlpha = false;
                _toggleSortOrder();*/
              },
            ),
          ),*/
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
            child: IconButton(
              icon: const Icon(
                Icons.refresh,
              ),
              iconSize: 35,
              onPressed: () {
                refresh();
              },
            ),
          ),
        ],
      ),
      // ignore: unnecessary_null_comparison
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<OrionApiItem>>(
              future: _itemsCompleter.future,
              builder: (BuildContext context,
                  AsyncSnapshot<List<OrionApiItem>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    snapshot.connectionState == ConnectionState.none) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                } else if (snapshot.hasError) {
                  return const Center(
                    child: Text('Failed to fetch files'),
                  );
                } else {
                  _items = snapshot.data!;
                  return Padding(
                    padding:
                        const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                    child: GridView.builder(
                      controller: _scrollController,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          childAspectRatio: 1.03,
                          mainAxisSpacing: 5,
                          crossAxisSpacing: 5,
                          crossAxisCount: MediaQuery.of(context).orientation ==
                                  Orientation.landscape
                              ? 4
                              : 2),
                      itemCount: _items.length + 1,
                      itemBuilder: (BuildContext context, int index) {
                        if (index == 0) {
                          // Card that navigates to the parent directory
                          return Card(
                            elevation: 1,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: !_usbAvailable &&
                                      !_isUSB &&
                                      _directory == _defaultDirectory
                                  ? null
                                  : _directory == _defaultDirectory
                                      ? () async {
                                          _isUSB = !_isUSB;
                                          _itemsFuture = _getItems(_directory);
                                          _itemsCompleter =
                                              Completer<List<OrionApiItem>>();
                                          final items = await _itemsFuture;
                                          _itemsCompleter.complete(items);
                                          setState(() {
                                            _items = items;
                                          });
                                        }
                                      : () async {
                                          try {
                                            _scrollController.jumpTo(0);
                                            final parentDirectory =
                                                path.dirname(_directory);
                                            _directory = parentDirectory;
                                            setState(() {
                                              _isNavigating = true;
                                            });
                                            _itemsFuture =
                                                _getItems(parentDirectory);
                                            _itemsCompleter =
                                                Completer<List<OrionApiItem>>();
                                            final items = await _itemsFuture;
                                            _itemsCompleter.complete(items);
                                            setState(() {
                                              _items = items;
                                              _isNavigating = false;
                                            });
                                          } catch (e) {
                                            _logger.severe(
                                                'Failed to navigate to parent directory',
                                                e);
                                            if (e is FileSystemException) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Operation not permitted'),
                                                ),
                                              );
                                            }
                                          }
                                        },
                              child: GridTile(
                                footer: Card(
                                  color: Colors.transparent,
                                  elevation: 0,
                                  child: GridTileBar(
                                    backgroundColor: Colors.transparent,
                                    title: AutoSizeText(
                                      _directory == _defaultDirectory
                                          ? _isUSB == false
                                              ? _usbAvailable
                                                  ? 'Switch to USB'
                                                  : 'USB unavailable'
                                              : 'Switch to Internal'
                                          : 'Parent Directory',
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      minFontSize: 18,
                                      style: const TextStyle(
                                          fontSize: 24,
                                          color: Colors.grey,
                                          fontFamily: 'AtkinsonHyperlegible'),
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: PhosphorIcon(
                                      _directory == _defaultDirectory
                                          ? _isUSB == false
                                              ? _usbAvailable
                                                  ? PhosphorIcons.usb()
                                                  : PhosphorIcons.xCircle()
                                              : PhosphorIcons.hardDrives()
                                          : PhosphorIcons.arrowUUpLeft(),
                                      size: 75,
                                      color: Colors.grey),
                                ),
                              ),
                            ),
                          );
                        } else {
                          final OrionApiItem item = _items[index - 1];
                          final String fileName = path.basename(item.path);
                          final String displayName = fileName;

                          // Card that navigates to the file or directory
                          return Card(
                            elevation: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                if (item is OrionApiDirectory) {
                                  _scrollController.jumpTo(0);
                                  _directory = item.path;
                                  setState(() {
                                    _isNavigating = true;
                                  });
                                  _itemsFuture = _getItems(item.path);
                                  _itemsCompleter =
                                      Completer<List<OrionApiItem>>();
                                  final items = await _itemsFuture;
                                  _itemsCompleter.complete(items);
                                  setState(() {
                                    _items = items;
                                    _isNavigating = false;
                                  });
                                } else if (item is OrionApiFile) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DetailScreen(
                                        fileName: fileName,
                                        fileSubdirectory: _subdirectory,
                                        fileLocation: location,
                                      ),
                                    ),
                                  );
                                }
                              },
                              // File name that hovers over the file
                              child: _isNavigating
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : GridTile(
                                      footer: Card(
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.only(
                                            bottomLeft: Radius.circular(10),
                                            bottomRight: Radius.circular(10),
                                          ),
                                        ),
                                        color: item is OrionApiFile
                                            ? Theme.of(context)
                                                .cardColor
                                                .withOpacity(0.65)
                                            : Colors.transparent,
                                        elevation: item is OrionApiFile ? 2 : 0,
                                        child: GridTileBar(
                                          title: AutoSizeText(
                                            displayName,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            minFontSize: 20,
                                            style: TextStyle(
                                                fontSize: 24,
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge!
                                                    .color,
                                                fontFamily:
                                                    'AtkinsonHyperlegible'),
                                          ),
                                        ),
                                      ),
                                      child: item is OrionApiDirectory
                                          ? IconTheme(
                                              data: const IconThemeData(
                                                  color: Colors.grey),
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 15),
                                                child: PhosphorIcon(
                                                    PhosphorIcons.folder(),
                                                    size: 75),
                                              ),
                                            )
                                          : Padding(
                                              padding:
                                                  const EdgeInsets.all(4.5),
                                              child: FutureBuilder<String>(
                                                future: ThumbnailUtil
                                                    .extractThumbnail(
                                                  location,
                                                  _subdirectory,
                                                  fileName,
                                                ),
                                                builder: (BuildContext context,
                                                    AsyncSnapshot<String>
                                                        snapshot) {
                                                  if (snapshot
                                                          .connectionState ==
                                                      ConnectionState.waiting) {
                                                    return const Padding(
                                                        padding:
                                                            EdgeInsets.all(60),
                                                        child:
                                                            CircularProgressIndicator());
                                                  } else if (snapshot.error !=
                                                      null) {
                                                    return const Icon(
                                                        Icons.error);
                                                  } else {
                                                    return ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
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
                  );
                }
              },
            ),
    );
  }
}
