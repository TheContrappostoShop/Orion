/*
 *    Orion File Search Screen
 *    Copyright (c) 2024 TheContrappostoShop (Paul S.)
 *    GPLv3 Licensing (see LICENSE)
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';

class SearchFileScreen extends StatefulWidget {
  final GlobalKey<SpawnOrionTextFieldState> searchKey =
      GlobalKey<SpawnOrionTextFieldState>();

  SearchFileScreen({super.key});

  @override
  SearchFileScreenState createState() => SearchFileScreenState();
}

class SearchFileScreenState extends State<SearchFileScreen> {
  List<FileSystemEntity> files = [];
  List<FileSystemEntity> filteredFiles = [];

  @override
  void initState() {
    super.initState();
    files = Directory.current
        .listSync()
        .where((entity) => entity.statSync().type == FileSystemEntityType.file)
        .toList(); // Filter out directories
    filteredFiles = files;
  }

  void searchFiles(String searchText) {
    if (searchText.isEmpty) {
      setState(() {
        filteredFiles = files;
      });
    } else {
      setState(() {
        filteredFiles =
            files.where((file) => file.path.contains(searchText)).toList();
      });
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
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.only(top: 7.5, left: 6),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
                // Add other AppBar properties as needed
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredFiles.length,
                  itemBuilder: (context, index) {
                    FileSystemEntity file = filteredFiles[index];
                    FileStat fileStat = file.statSync();
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(file.path),
                      subtitle: Text('Last modified: ${fileStat.modified}'),
                      onTap: () {
                        // Handle file tap
                      },
                      onLongPress: () {
                        // Handle file long press
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
                top: 15.0, left: 55, right: 15), // Adjust as needed
            child: SpawnOrionTextField(
              key: widget.searchKey,
              keyboardHint: "Search File Name",
              locale: Localizations.localeOf(context).toString(),
              isHidden: false,
              noShove: true,
              onChanged: (text) {
                searchFiles(text);
                print("Search text: $text");
              },
            ),
          ),
        ],
      ),
    );
  }
}
