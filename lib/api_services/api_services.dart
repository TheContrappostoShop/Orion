import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  final String apiUrl = "http://localhost:12357";

  ApiService();

  // GET METHODS TO ODYSSEY

  /// Get current status of the printer
  Future<Map<String, dynamic>> getStatus() async {
    final response = await http.get(Uri.parse('$apiUrl/status'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  /// Get list of files in a specific location with pagination
  /// Takes 3 parameters : location [string], pageSize [int] and pageIndex [int]
  ///
  /// returns TODO
  Future<Map<String, dynamic>> listFiles(
      String location, int pageSize, int pageIndex) async {
    final queryParams = {
      "location": location,
      "page_index": pageIndex,
      "page_size": pageSize
    };
    final response = await http.get(Uri.http(apiUrl, '/files', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  /// Get a file
  /// Takes 2 parameters : location [string] and filename [String]
  ///
  /// returns TODO
  Future<Map<String, dynamic>> getFile(String location, String filename) async {
    final queryParams = {"location": location, "filename": filename};
    final response = await http.get(Uri.http(apiUrl, '/files', queryParams));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to fetch status');
    }
  }

  /**
   * POST METHODS TO ODYSSEY 
   */

  /// Start printing a given file
  /// Takes 2 parameters : location [string] and filename [String]
  ///
  /// returns TODO
  Future<Map<String, dynamic>> startPrint(
      String location, String filename) async {
    final response = await http.post(
      Uri.parse('$apiUrl/print/start/'),
      headers: {"Content-Type": "application/json"},
      body: json.encode({location: location, filename: filename}),
    );

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data');
    }
  }

  /// Cancel the print
  ///
  /// returns TODO
  Future<Map<String, dynamic>> cancelPrint() async {
    final response = await http.post(Uri.parse('$apiUrl/print/cancel'));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data');
    }
  }

  /// Pause the print
  ///
  /// returns TODO
  Future<Map<String, dynamic>> pausePrint() async {
    final response = await http.post(Uri.parse('$apiUrl/print/pause'));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data');
    }
  }

  /// Resume the print
  ///
  /// returns TODO
  Future<Map<String, dynamic>> resumePrint() async {
    final response = await http.post(Uri.parse('$apiUrl/print/resume'));

    if (response.statusCode == 200) {
      // TODO check the response sent by odyssey
      return json.decode(response.body);
    } else {
      throw Exception('Failed to post data');
    }
  }

  /// Move the Z axis
  /// Takes 1 param height [double] which is the desired position of the Z axis
  ///
  /// returns TODO
  Future<Map<String, dynamic>> move(double height) async {
    final response = await http.post(
      Uri.parse('$apiUrl/manual'),
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

  /// Toggle cure
  /// Takes 1 param on [bool] which define if we start or stop the curing
  ///
  /// returns TODO
  Future<Map<String, dynamic>> manualCure(bool cure) async {
    final response = await http.post(
      Uri.parse('$apiUrl/manual'),
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

  /**
   * DELETE METHODS TO ODYSSEY 
   */

  /// Delete a file
  /// Takes 2 parameters : location [string] and filename [String]
  ///
  /// returns TODO
  Future<Map<String, dynamic>> deleteFile(
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
