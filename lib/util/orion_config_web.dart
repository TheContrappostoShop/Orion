// orion_config_web.dart
import 'dart:convert';
import 'dart:html';

Map<String, dynamic> getConfig() {
  var configJson = window.localStorage['orionConfig'];
  if (configJson == null || configJson.isEmpty) {
    var defaultConfig = {
      'general': {
        'themeMode': 'dark',
      },
      'advanced': {},
    };
    writeConfig(defaultConfig);
    return defaultConfig;
  }
  return json.decode(configJson);
}

void writeConfig(Map<String, dynamic> config) {
  var encoder = const JsonEncoder.withIndent('  ');
  window.localStorage['orionConfig'] = encoder.convert(config);
}
