import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/*
 *    Orion API Services
 *    Copyright (c) 2024 TheContrappostoShop (PaulGD03, shifubrams)
 *    GPLv3 Licensing (see LICENSE)
 */

class ApiService {
  // For Debugging Purposes: TheContrappostoShop Internal Debug API URL (Simulated Odyssey)
  // During production, this will be the actual Odyssey API URL (currently assuming to localhost)
  static const String apiUrl =
      kDebugMode ? "dev.plyktra.de" : '127.0.0.1:12357';

  ///
  /// GET METHODS TO ODYSSEY
  ///

  // Get current status of the printer
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await http.get(
      Uri.parse('http://apiUrl/status'),
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
      "subdirectory": subdirectory == '/' ? '' : subdirectory,
      "page_index": pageIndex.toString(),
      "page_size": pageSize.toString(),
    };
    final response = await http.get(Uri.http(apiUrl, '/files', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  // Get file metadata
  // Takes 2 parameters : location [string] and filename [String]
  static Future<Map<String, dynamic>> getFileMetadata(
      String location, String file_path) async {
    final queryParams = {"location": location, "file_path": file_path};
    final response =
        await http.get(Uri.http(apiUrl, '/file/metadata', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  // Get file thumbnail
  // Takes 2 parameters : location [string] and filename [String]
  static Future<Uint8List> getFileThumbnail(
      String location, String file_path) async {
    final queryParams = {"location": location, "file_path": file_path};
    final response =
        await http.get(Uri.http(apiUrl, '/file/thumbnail', queryParams));

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
  // Takes 2 parameters : location [string] and filename [String]
  static Future<Null> startPrint(String location, String filename) async {
    final response = await http.post(
      Uri.parse('http://$apiUrl/print/start/$location/$filename'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to post data');
    }
  }

  // Cancel the print
  static Future<Null> cancelPrint() async {
    final response = await http.post(Uri.parse('http://$apiUrl/print/cancel'));

    if (response.statusCode != 200) {
      // TODO check the response sent by odyssey
      throw Exception('Failed to post data');
    }
  }

  // Pause the print
  static Future<Null> pausePrint() async {
    final response = await http.post(Uri.parse('http://$apiUrl/print/pause'));

    if (response.statusCode != 200) {
      // TODO check the response sent by odyssey
      throw Exception('Failed to post data');
    }
  }

  // Resume the print
  static Future<Null> resumePrint() async {
    final response = await http.post(Uri.parse('http://$apiUrl/print/resume'));

    if (response.statusCode != 200) {
      // TODO check the response sent by odyssey
      throw Exception('Failed to post data');
    }
  }

  // Move the Z axis
  // Takes 1 param height [double] which is the desired position of the Z axis
  static Future<Map<String, dynamic>> move(double height) async {
    final response = await http.post(
      Uri.parse('http://$apiUrl/manual'),
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
  // Takes 1 param on [bool] which define if we start or stop the curing
  static Future<Map<String, dynamic>> manualCure(bool cure) async {
    final response = await http.post(
      Uri.parse('http://apiUrl/manual'),
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

  // Delete a file
  // Takes 2 parameters : location [string] and filename [String]
  static Future<Map<String, dynamic>> deleteFile(
      String location, String filename) async {
    final queryParams = {"location": location, "filename": filename};
    final response = await http.delete(Uri.http(apiUrl, '/files', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }
}
