import 'dart:io' as io;

import 'package:orion/util/orion_api_filesystem/orion_api_item.dart';

class OrionApiFile implements OrionApiItem {
  final io.File? file;
  final String path;
  final String name;
  final int? lastModified;
  final String? locationCategory;
  final double? usedMaterial;
  final double? printTime;
  final double? layerHeight;
  final int? layerCount;

  OrionApiFile({
    this.file,
    required this.path,
    required this.name,
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
      file: fileData['path'] != null ? io.File(fileData['path']) : null,
      path: fileData['path'] ?? '',
      name: fileData['name'] ?? '',
      lastModified: fileData['last_modified'] ?? 0,
      locationCategory: json['location_category'],
      usedMaterial: json['used_material'] ?? 0.0,
      printTime: json['print_time'] ?? 0.0,
      layerHeight: json['layer_height'] ?? 0.0,
      layerCount: json['layer_count'] ?? 0,
    );
  }
}
