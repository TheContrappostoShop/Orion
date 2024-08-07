/*
* Orion - Search File Screen
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

//import 'package:orion/files/details_screen.dart';

import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';
import 'package:path/path.dart' as path;

class SearchFileScreen extends StatefulWidget {
  final GlobalKey<SpawnOrionTextFieldState> searchKey =
      GlobalKey<SpawnOrionTextFieldState>();

  SearchFileScreen({super.key});

  @override
  SearchFileScreenState createState() => SearchFileScreenState();
}

class SearchFileScreenState extends State<SearchFileScreen> {
  List<FileSystemEntity> filteredFiles = [];
  final ScrollController _scrollController = ScrollController();
  bool isLoading = false;
  String searchText = '';

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
        return Directory('/');
    }
  }

  Future<void> searchFiles(String searchText) async {
    setState(() {
      isLoading = true;
    });

    if (searchText.isEmpty) {
      setState(() {
        filteredFiles = [];
        isLoading = false;
      });
    } else {
      final Directory initialDir = getInitialDir(Theme.of(context).platform);
      final results = await compute(_searchFilesInBackground,
          {'searchText': searchText, 'initialDir': initialDir});

      setState(() {
        filteredFiles = results;
        isLoading = false;
      });
    }
  }

  static List<FileSystemEntity> _searchFilesInBackground(
      Map<String, dynamic> args) {
    String searchText = args['searchText'];
    Directory initialDir = args['initialDir'];

    List<FileSystemEntity> files = initialDir
        .listSync(recursive: true)
        .where((entity) => entity.statSync().type == FileSystemEntityType.file)
        .toList();

    if (searchText.isEmpty) {
      return [];
    } else {
      List<FileSystemEntity> filteredFiles = files.where((file) {
        String fileName = path.basename(file.path).toLowerCase();
        return fileName.contains(searchText.toLowerCase()) &&
            fileName.endsWith('.sl1');
      }).toList();

      // Sort the files so that .sl1 files come first
      filteredFiles.sort((a, b) {
        int compareValueA = a.path.toLowerCase().endsWith('.sl1') ? 0 : 1;
        int compareValueB = b.path.toLowerCase().endsWith('.sl1') ? 0 : 1;
        return compareValueA.compareTo(compareValueB);
      });

      return filteredFiles;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              AppBar(
                toolbarHeight: 90,
                backgroundColor: Colors.transparent,
                //elevation: 1,
                actions: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width - 55,
                    child: Padding(
                      padding:
                          const EdgeInsets.only(right: 15), // Adjust as needed
                      child: SpawnOrionTextField(
                        key: widget.searchKey,
                        keyboardHint: "Search File Name",
                        locale: Localizations.localeOf(context).toString(),
                        scrollController: _scrollController,
                        isHidden: false,
                        onChanged: (text) {
                          searchFiles(text);
                          searchText = text;
                        },
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredFiles.isEmpty
                        ? searchText == ''
                            ? const Center(
                                child: Text('Enter Search Term.',
                                    style: TextStyle(fontSize: 24)))
                            : const Center(
                                child: Text('No Results (╯°□°)╯︵ ┻━┻',
                                    style: TextStyle(fontSize: 24)))
                        : ListView.builder(
                            itemCount: filteredFiles.length,
                            itemBuilder: (context, index) {
                              FileSystemEntity file = filteredFiles[index];
                              FileStat fileStat = file.statSync();
                              bool isSl1 = file.path.endsWith('.sl1');
                              return ListTile(
                                leading: const Icon(Icons.insert_drive_file),
                                title: Text(file.path,
                                    style: TextStyle(
                                        color: isSl1 ? null : Colors.grey)),
                                subtitle: isSl1
                                    ? Text(
                                        'Last modified: ${fileStat.modified}')
                                    : null,
                                onTap: () {
                                  if (file is File &&
                                      file.path.endsWith('.sl1')) {
                                    /*Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            DetailScreen(file: file),
                                      ),
                                    );*/
                                  }
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
