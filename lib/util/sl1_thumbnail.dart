/*
* Orion - Thumbnail Util
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
import 'package:logging/logging.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class ThumbnailUtil {
  static final _logger = Logger('ThumbnailUtil');
  static final ApiService _api = ApiService();

  static Future<String> extractThumbnail(
      String location, String subdirectory, String filename,
      {String size = "Small"}) async {
    try {
      String finalLocation = _isDefaultDir(subdirectory)
          ? filename
          : [subdirectory, filename].join('/');
      final bytes = await _api.getFileThumbnail(location, finalLocation, size);

      if (kIsWeb) {
        // On web, return a data URL
        final base64Data = base64Encode(bytes);
        return 'data:image/png;base64,$base64Data';
      } else {
        // On non-web platforms, save the file to the local file system
        final tempDir = await getTemporaryDirectory();
        final orionTmpDir =
            Directory('${tempDir.path}/oriontmp/$finalLocation');
        if (!await orionTmpDir.exists()) {
          await orionTmpDir.create(recursive: true);
        }

        final filePath = size == "Small"
            ? '${orionTmpDir.path}/thumbnail400x400.png'
            : '${orionTmpDir.path}/thumbnail840x400.png';
        final outputFile = File(filePath);
        outputFile.writeAsBytesSync(bytes);

        // Check the total size of the oriontmp directory
        int totalSize = 0;
        final files = orionTmpDir.listSync(recursive: true);
        for (var file in files) {
          if (file is File) {
            totalSize += await file.length();
          }
        }

        // If the total size exceeds 100MB, delete the oldest files
        if (totalSize > 100 * 1024 * 1024) {
          files.sort(
              (a, b) => a.statSync().modified.compareTo(b.statSync().modified));
          while (totalSize > 100 * 1024 * 1024 && files.isNotEmpty) {
            int fileSize = await (files.first as File).length();
            await files.first.delete();
            totalSize -= fileSize;
            files.removeAt(0);
          }
        }

        return filePath;
      }
    } catch (e) {
      _logger.severe('Failed to fetch thumbnail', e);
    }

    return 'assets/images/placeholder.png';
  }

  static bool _isDefaultDir(String subdirectory) {
    return subdirectory == '';
  }
}
