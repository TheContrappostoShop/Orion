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
