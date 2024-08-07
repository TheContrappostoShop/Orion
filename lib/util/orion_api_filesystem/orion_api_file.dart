/*
* Orion - Orion API File
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

import 'package:universal_io/io.dart';

import 'package:orion/util/orion_api_filesystem/orion_api_item.dart';

class OrionApiFile implements OrionApiItem {
  final File? file;
  @override
  final String path;
  final String name;
  final int? lastModified;
  final String? locationCategory;
  @override
  final String parentPath;
  final double? usedMaterial;
  final double? printTime;
  final double? layerHeight;
  final int? layerCount;

  OrionApiFile({
    this.file,
    required this.path,
    required this.name,
    required this.parentPath,
    this.lastModified,
    this.locationCategory,
    this.usedMaterial,
    this.printTime,
    this.layerHeight,
    this.layerCount,
  });

  factory OrionApiFile.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> fileData = json['file_data'] ?? {};

    return OrionApiFile(
      file: fileData['path'] != null ? File(fileData['path']) : null,
      path: fileData['path'] ?? '',
      name: fileData['name'] ?? '',
      lastModified: fileData['last_modified'] ?? 0,
      parentPath: fileData['parent_path'] ?? '',
      locationCategory: json['location_category'],
      usedMaterial: json['used_material'] ?? 0.0,
      printTime: json['print_time'] ?? 0.0,
      layerHeight: json['layer_height'] ?? 0.0,
      layerCount: json['layer_count'] ?? 0,
    );
  }
}
