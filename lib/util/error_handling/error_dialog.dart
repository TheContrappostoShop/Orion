/*
* Orion - Error Dialog
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import 'package:orion/glasser/glasser.dart';

void showErrorDialog(BuildContext context, String errorCode) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return GlassAlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.red.shade400,
                size: 26,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getErrorTitle(context, errorCode),
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      FlutterI18n.translate(context, 'error.code')
                          .replaceAll('%s', errorCode),
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade400,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Text(
            _getErrorMessage(context, errorCode),
            style: const TextStyle(
              fontSize: 20,
              height: 1.5,
            ),
          ),
          actions: [
            GlassButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 60),
              ),
              child: Text(FlutterI18n.translate(context, 'common.close')),
            ),
          ],
        );
      },
    );
  });
}

/// Look up the translated error title for the given error code.
String _getErrorTitle(BuildContext context, String code) {
  final key = code.toLowerCase().replaceAll('-', '');
  return FlutterI18n.translate(context, 'error.${key}Title');
}

/// Look up the translated error message for the given error code.
String _getErrorMessage(BuildContext context, String code) {
  final key = code.toLowerCase().replaceAll('-', '');
  return FlutterI18n.translate(context, 'error.${key}Msg');
}
