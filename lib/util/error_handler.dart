/*
* Orion - Error Handler
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

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class ErrorHandler {
  static final _logger = Logger('ErrorHandler');

  static void onError(Object error, StackTrace stackTrace) {
    _logger.severe("Error encountered:", error, stackTrace);
    return;
  }

  static void onErrorDetails(FlutterErrorDetails details) {
    _logger.severe(
        "Flutter error encountered:", details.exception, details.stack);
    return;
  }
}
