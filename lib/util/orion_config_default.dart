// orion_config_default.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

String _configPath = Platform.environment['ORION_CFG'] ?? '.';

Map<String, dynamic> getConfig() {
  var fullPath = path.join(_configPath, 'orion.cfg');
  var configFile = File(fullPath);

  if (!configFile.existsSync() || configFile.readAsStringSync().isEmpty) {
    var defaultConfig = {
      'general': {
        'themeMode': 'dark',
      },
      'advanced': {},
    };
    writeConfig(defaultConfig);
    return defaultConfig;
  }

  return json.decode(configFile.readAsStringSync());
}

void writeConfig(Map<String, dynamic> config) {
  var fullPath = path.join(_configPath, 'orion.cfg');
  var configFile = File(fullPath);
  var encoder = const JsonEncoder.withIndent('  ');
  configFile.writeAsStringSync(encoder.convert(config));
}
