/*
* Orion - Orion List Tile
* Copyright (C) 2024 TheContrappostoShop (PaulGD03)
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

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class OrionListTile extends StatelessWidget {
  final String title;
  final dynamic icon;
  final bool value;
  final bool ignoreColor;
  final Function(bool) onChanged;

  const OrionListTile({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    this.ignoreColor = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
        style:
            TextStyle(fontSize: 24.0, color: ignoreColor ? Colors.white : null),
      ),
      trailing: Transform.scale(
        scale: 1.2, // adjust this value to change the size of the Switch
        child: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
      leading: icon is IconData
          ? Icon(icon, size: 24.0, color: ignoreColor ? Colors.white : null)
          : icon is Function
              ? PhosphorIcon(icon(PhosphorIconsStyle.bold),
                  size: 24.0, color: ignoreColor ? Colors.white : null)
              : null,
    );
  }
}
