import 'locales/en_US.orionkb.dart' show en_US_keyboardLayout;
import 'locales/de_DE.orionkb.dart' show de_DE_keyboardLayout;

class OrionLocale {
  final String locale;
  final Map<String, String> keyboardLayout;

  OrionLocale({required this.locale, required this.keyboardLayout});

  static OrionLocale getLocale(String locale) {
    switch (locale) {
      case 'en_US':
        return OrionLocale(
            locale: 'en_US', keyboardLayout: en_US_keyboardLayout);
      case 'de_DE':
        return OrionLocale(
            locale: 'de_DE', keyboardLayout: de_DE_keyboardLayout);
      default:
        return OrionLocale(
            locale: 'en_US', keyboardLayout: en_US_keyboardLayout);
    }
  }
}
