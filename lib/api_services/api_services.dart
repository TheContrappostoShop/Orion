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
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static final _logger = Logger('ApiService');
  // For Debugging Purposes: TheContrappostoShop Internal Debug API URL (Simulated Odyssey)
  // During production, this will be the actual Odyssey API URL (currently assuming to localhost)
  static const String apiUrl =
      kDebugMode ? "https://dev.plyktra.de" : 'http://127.0.0.1:12357';

  // Method for creating a Uri object based on http or https protocol
  static Uri dynUri(
      String apiUrl, String path, Map<String, dynamic> queryParams) {
    if (queryParams.containsKey('file_path')) {
      queryParams['file_path'] =
          queryParams['file_path'].toString().replaceAll('//', '');
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

  static Future<http.Response> odysseyGet(
      String endpoint, Map<String, dynamic> queryParams) async {
    var uri = dynUri(apiUrl, endpoint, queryParams);
    _logger.fine('Odyssey GET $uri');

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return response;
    } else {
      throw Exception('Odyssey GET call failed: $response');
    }
  }

  static Future<http.Response> odysseyPost(
      String endpoint, Map<String, dynamic> queryParams) async {
    var uri = dynUri(apiUrl, endpoint, queryParams);
    _logger.fine('Odyssey POST $uri');

    final response = await http.post(uri);

    if (response.statusCode == 200) {
      return response;
    } else {
      throw Exception('Odyssey POST call failed: $response');
    }
  }

  static Future<http.Response> odysseyDelete(
      String endpoint, Map<String, dynamic> queryParams) async {
    var uri = dynUri(apiUrl, endpoint, queryParams);
    _logger.fine('Odyssey DELETE $uri');

    final response = await http.delete(uri);

    if (response.statusCode == 200) {
      return response;
    } else {
      throw Exception('Odyssey DELETE call failed: $response');
    }
  }

  // Get current status of the printer
  static Future<Map<String, dynamic>> getStatus() async {
    _logger.info("getStatus");
    final response = await odysseyGet('/status', {});
    return json.decode(response.body);
  }

  // Get current status of the printer
  static Future<Map<String, dynamic>> getConfig() async {
    _logger.info("getConfig");
    final response = await odysseyGet('/config', {});
    return json.decode(response.body);
  }

  // Get list of files and directories in a specific location with pagination
  // Takes 3 parameters : location [string], pageSize [int] and pageIndex [int]
  static Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory) async {
    _logger.info(
        "listItems location=$location pageSize=$pageSize pageIndex=$pageIndex subdirectory=$subdirectory");
    final queryParams = {
      "location": location,
      "subdirectory": subdirectory,
      "page_index": pageIndex.toString(),
      "page_size": pageSize.toString(),
    };

    final response = await odysseyGet('/files', queryParams);
    return json.decode(response.body);
  }

  // Get file metadata
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<Map<String, dynamic>> getFileMetadata(
      String location, String filePath) async {
    _logger.info("getFileMetadata location=$location filePath=$filePath");
    final queryParams = {"location": location, "file_path": filePath};

    final response = await odysseyGet('/file/metadata', queryParams);
    return json.decode(response.body);
  }

  // Get file thumbnail
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<Uint8List> getFileThumbnail(
      String location, String filePath) async {
    _logger.info("getFileThumbnail location=$location filePath=$filePath");
    final queryParams = {"location": location, "file_path": filePath};

    final response = await odysseyGet('/file/thumbnail', queryParams);
    return response.bodyBytes;
  }

  ///
  /// POST METHODS TO ODYSSEY
  ///

  // Start printing a given file
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<void> startPrint(String location, String filePath) async {
    _logger.info("startPrint location=$location filePath=$filePath");

    final queryParams = {
      'location': location,
      'file_path': filePath,
    };

    await odysseyPost('/print/start', queryParams);
  }

  // Cancel the print
  static Future<void> cancelPrint() async {
    _logger.info("cancelPrint");

    await odysseyPost('/print/cancel', {});
  }

  // Pause the print
  static Future<void> pausePrint() async {
    _logger.info("pausePrint");

    await odysseyPost('/print/pause', {});
  }

  // Resume the print
  static Future<void> resumePrint() async {
    _logger.info("resumePrint");

    await odysseyPost('/print/resume', {});
  }

  // Move the Z axis
  // Takes 1 param height [double] which is the desired position of the Z axis
  static Future<Map<String, dynamic>> move(double height) async {
    _logger.info("move height=$height");

    final response = await odysseyPost('/manual', {'z': height});
    return json.decode(response.body);
  }

  // Toggle cure
  // Takes 1 param cure [bool] which define if we start or stop the curing
  static Future<Map<String, dynamic>> manualCure(bool cure) async {
    _logger.info("manualCure cure=$cure");

    final response = await odysseyPost('/manual', {'cure': cure});
    return json.decode(response.body);
  }

  // Home Z axis
  static Future<Map<String, dynamic>> manualHome() async {
    _logger.info("manualHome");

    final response = await odysseyPost('/manual/home', {});
    return json.decode(response.body);
  }

  // Issue hardware-layer command
  // Takes 1 param command [String] which holds the command to run
  static Future<Map<String, dynamic>> manualCommand(String command) async {
    _logger.info("manualCommand");

    final response =
        await odysseyPost('/manual/hardware_command', {'command': command});
    return json.decode(response.body);
  }

  ///
  /// DELETE METHODS TO ODYSSEY
  ///

  // Delete a file
  // Takes 2 parameters : location [string] and filePath [String]
  static Future<Map<String, dynamic>> deleteFile(
      String location, String filePath) async {
    _logger.info("deleteFile location=$location fileName=$filePath");
    final queryParams = {
      'location': location,
      'file_path': filePath,
    };

    final response = await odysseyDelete('/files', queryParams);
    return json.decode(response.body);
  }
}
