/*
* Orion - Localization
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
