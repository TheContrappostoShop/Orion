/*
* Orion - Orion Keyboard Expander
* Copyright (C) 2024 TheContrappostoShop (PaulGD0, shifubrams)
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
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';

class OrionKbExpander extends StatelessWidget {
  final GlobalKey<SpawnOrionTextFieldState> textFieldKey;

  const OrionKbExpander({super.key, required this.textFieldKey});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.delayed(Duration.zero),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return ValueListenableBuilder<bool>(
            valueListenable: textFieldKey.currentState?.isKeyboardOpen ??
                ValueNotifier<bool>(false),
            builder: (context, isKeyboardOpen, child) {
              return ValueListenableBuilder<double>(
                valueListenable: textFieldKey.currentState?.expandDistance ??
                    ValueNotifier<double>(0.0),
                builder: (context, expandDistance, child) {
                  return AnimatedContainer(
                    curve: Curves.easeInOut,
                    duration: const Duration(milliseconds: 300),
                    height: isKeyboardOpen ? expandDistance : 0,
                  );
                },
              );
            },
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
