/*
* Orion - Config
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

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'dart:convert';

class OrionConfig {
  final _logger = Logger('OrionConfig');
  late final String _configPath;

  OrionConfig() {
    _configPath = Platform.environment['ORION_CFG'] ?? '.';
  }

  ThemeMode getThemeMode() {
    var config = _getConfig();
    var themeMode = config['general']?['themeMode'] ?? 'light';
    return themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  void setThemeMode(ThemeMode themeMode) {
    var config = _getConfig();
    config['general'] ??= {};
    config['general']['themeMode'] =
        themeMode == ThemeMode.dark ? 'dark' : 'light';
    _writeConfig(config);
  }

  void setFlag(String flagName, bool value, {String category = 'general'}) {
    var config = _getConfig();
    config[category] ??= {};
    config[category][flagName] = value;
    _logger.config('setFlag: $flagName to $value');

    _writeConfig(config);
  }

  void setString(String key, String value, {String category = 'general'}) {
    var config = _getConfig();
    config[category] ??= {};
    config[category][key] = value;

    if (value == '') {
      _logger.config('setString: cleared $key');
    } else {
      _logger.config('setString: $key to ${value == '' ? 'NULL' : value}');
    }

    _writeConfig(config);
  }

  bool getFlag(String flagName, {String category = 'general'}) {
    var config = _getConfig();
    return config[category]?[flagName] ?? false;
  }

  String getString(String key, {String category = 'general'}) {
    var config = _getConfig();
    return config[category]?[key] ?? '';
  }

  void toggleFlag(String flagName, {String category = 'general'}) {
    bool currentValue = getFlag(flagName, category: category);
    setFlag(flagName, !currentValue, category: category);
  }

  Map<String, dynamic> _getConfig() {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var configFile = File(fullPath);

    if (!configFile.existsSync() || configFile.readAsStringSync().isEmpty) {
      var defaultConfig = {
        'general': {
          'themeMode': 'dark',
        },
        'advanced': {},
      };
      _writeConfig(defaultConfig);
      return defaultConfig;
    }

    return json.decode(configFile.readAsStringSync());
  }

  void _writeConfig(Map<String, dynamic> config) {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var configFile = File(fullPath);
    var encoder = const JsonEncoder.withIndent('  ');
    configFile.writeAsStringSync(encoder.convert(config));
  }

  void blowUp(BuildContext context, String imagePath) {
    _logger.severe('Blowing up the app');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return FutureBuilder(
          future: Future.delayed(const Duration(seconds: 4)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SafeArea(
                child: Dialog(
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  insetPadding: EdgeInsets.zero,
                  backgroundColor: Theme.of(context).colorScheme.background,
                  child: const Center(
                    child: SizedBox(
                        height: 75,
                        width: 75,
                        child: CircularProgressIndicator()),
                  ),
                ),
              );
            } else {
              Future.delayed(const Duration(seconds: 10), () {
                Navigator.of(context).pop(true);
              });
              return SafeArea(
                child: Dialog(
                  insetPadding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.fill,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}
