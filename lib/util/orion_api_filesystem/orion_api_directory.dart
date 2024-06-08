/*
* Orion - Orion API Directory
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

// ignore_for_file: unused_element

import 'package:orion/util/orion_api_filesystem/orion_api_item.dart';

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
