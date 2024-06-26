/*
* Orion - Odyssey API Service
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

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // For Debugging Purposes: TheContrappostoShop Internal Debug API URL (Simulated Odyssey)
  // During production, this will be the actual Odyssey API URL (currently assuming to localhost)
  static const String apiUrl = kDebugMode ? "https://dev.plyktra.de" : 'http://127.0.0.1:12357';

  // Method for creating a Uri object based on http or https protocol
  static Uri dynUri(String apiUrl, String path, Map<String, dynamic> queryParams) {
    if (queryParams.containsKey('file_path')) {
      queryParams['file_path'] = queryParams['file_path'].toString().replaceAll('//', '');
    }

    if (apiUrl.startsWith('https://')) {
      return Uri.https(apiUrl.replaceFirst('https://', ''), path, queryParams);
    } else if (apiUrl.startsWith('http://')) {
      return Uri.http(apiUrl.replaceFirst('http://', ''), path, queryParams);
    } else {
      throw ArgumentError('apiUrl must start with either http:// or https://');
    }
  }

  ///
  /// GET METHODS TO ODYSSEY
  ///

  // Get current status of the printer
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await http.get(
      dynUri(apiUrl, '/status', {}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  // Get list of files and directories in a specific location with pagination
  // Takes 3 parameters : location [string], pageSize [int] and pageIndex [int]
  static Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory) async {
    final queryParams = {
      "location": location,
      "subdirectory": subdirectory,
      "page_index": pageIndex.toString(),
      "page_size": pageSize.toString(),
    };
    final response = await http.get(dynUri(apiUrl, '/files', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  // Get file metadata
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<Map<String, dynamic>> getFileMetadata(String location, String filePath) async {
    final queryParams = {"location": location, "file_path": filePath};
    final response = await http.get(dynUri(apiUrl, '/file/metadata', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  // Get file thumbnail
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<Uint8List> getFileThumbnail(String location, String filePath) async {
    final queryParams = {"location": location, "file_path": filePath};
    final response = await http.get(dynUri(apiUrl, '/file/thumbnail', queryParams));

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to fetch thumbnail');
    }
  }

  ///
  /// POST METHODS TO ODYSSEY
  ///

  // Start printing a given file
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<void> startPrint(String location, String filePath) async {
    final response = await http.post(
      dynUri(apiUrl, '/print/start', {
        'location': location,
        'file_path': filePath,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to post data');
    }
  }

  // Cancel the print
  static Future<Null> cancelPrint() async {
    final response = await http.post(dynUri(apiUrl, '/print/cancel', {}));

    if (response.statusCode != 200) {
      // TODO check the response sent by odyssey
      throw Exception('Failed to post data');
    }
  }

  // Pause the print
  static Future<Null> pausePrint() async {
    final response = await http.post(dynUri(apiUrl, '/print/pause', {}));

    if (response.statusCode != 200) {
      // TODO check the response sent by odyssey
      throw Exception('Failed to post data');
    }
  }

  // Resume the print
  static Future<Null> resumePrint() async {
    final response = await http.post(dynUri(apiUrl, '/print/resume', {}));

    if (response.statusCode != 200) {
      // TODO check the response sent by odyssey
      throw Exception('Failed to post data');
    }
  }

  // Move the Z axis
  // Takes 1 param height [double] which is the desired position of the Z axis
  static Future<Map<String, dynamic>> move(double height) async {
    final response = await http.post(
      dynUri(apiUrl, '/manual', {}),
      headers: {"Content-Type": "application/json"},
      body: json.encode({'z': height}),
    );

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data');
    }
  }

  // Toggle cure
  // Takes 1 param cure [bool] which define if we start or stop the curing
  static Future<Map<String, dynamic>> manualCure(bool cure) async {
    final response = await http.post(
      dynUri(apiUrl, '/manual', {}),
      headers: {"Content-Type": "application/json"},
      body: json.encode({'cure': cure}),
    );

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data');
    }
  }

  ///
  /// DELETE METHODS TO ODYSSEY
  ///

  // TODO: Implement deleteFile method properly
  // Delete a file
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<Map<String, dynamic>> deleteFile(String location, String filename) async {
    final queryParams = {"location": location, "filename": filename};
    final response = await http.delete(dynUri(apiUrl, '/files', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }
}
