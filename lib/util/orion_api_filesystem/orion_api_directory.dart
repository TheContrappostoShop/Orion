/*
* Orion - Orion API Directory
* Copyright (C) 2024 TheContrappostoShop (PaulGD0, shifubrams)
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

// ignore_for_file: unused_element

import 'package:orion/api_services/api_services.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_item.dart';
import 'package:path/path.dart' as path;

class OrionApiDirectory implements OrionApiItem {
  @override
  final String path;
  final String name;
  final int lastModified;
  final String locationCategory;
  @override
  final String parentPath;

  OrionApiDirectory({
    required this.path,
    required this.name,
    required this.lastModified,
    required this.locationCategory,
    required this.parentPath,
  });

  factory OrionApiDirectory.fromJson(Map<String, dynamic> json) {
    return OrionApiDirectory(
      path: json['path'],
      name: json['name'],
      lastModified: json['last_modified'],
      locationCategory: json['location_category'],
      parentPath: json['parent_path'],
    );
  }
}

// _getDirs method
Future<List<OrionApiDirectory>> _getDirs(
    String directory, String defaultDirectory) async {
  try {
    String subdirectory = path.relative(directory, from: defaultDirectory);

    final response =
        await ApiService.listItems('uploads', 100, 0, subdirectory);

    final List<OrionApiDirectory> dirs = (response['dirs'] as List)
        .where((item) => item != null)
        .map<OrionApiDirectory>((item) {
      OrionApiDirectory dir = OrionApiDirectory.fromJson(item);
      return dir;
    }).toList();

    return dirs;
  } catch (e) {
    return [];
  }
}
