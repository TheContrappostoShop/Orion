/*
* Orion - Debug Screen
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
import 'package:orion/util/orion_kb/orion_keyboard_expander.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';

class DebugScreen extends StatefulWidget {
  final Function(ThemeMode) changeThemeMode;

  const DebugScreen({super.key, required this.changeThemeMode});

  @override
  DebugScreenState createState() => DebugScreenState();
}

class DebugScreenState extends State<DebugScreen> {
  final GlobalKey<SpawnOrionTextFieldState> debugTextFieldKey =
      GlobalKey<SpawnOrionTextFieldState>();
  final GlobalKey<SpawnOrionTextFieldState> dialogTextFieldKey =
      GlobalKey<SpawnOrionTextFieldState>();
  final ScrollController _scrollController = ScrollController();

  bool themeToggle = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = MediaQuery.of(context).platformBrightness;
    themeToggle = brightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewportConstraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewportConstraints.maxHeight,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Center(
                      child: Text(
                        'Internal Debug Screen\nNOT FOR PUBLIC RELEASE',
                        style: TextStyle(fontSize: 25, color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 15),
                      child: SpawnOrionTextField(
                        key: debugTextFieldKey,
                        keyboardHint: "Debug Test Field",
                        locale: Localizations.localeOf(context).toString(),
                        scrollController: _scrollController,
                        isHidden: true,
                      ),
                    ),
                    /*Padding(
                      padding: const EdgeInsets.all(10),
                      child: ElevatedButton(
                          onPressed: () {
                            String text = debugTextFieldKey.currentState!
                                .getCurrentText();
                            if (kDebugMode) {
                              print("[Debug]: DebugTestField content: $text");
                            }
                            debugTextFieldKey.currentState!.clearText();
                          },
                          child:
                              const Text('[Debug] Read TextField to Console')),
                    ),*/
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: ElevatedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Center(
                                    child: Text('WiFi-Test-0123 Password')),
                                content: SizedBox(
                                  width: MediaQuery.of(context).size.width *
                                      0.5, // Half the screen width
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        SpawnOrionTextField(
                                          key: dialogTextFieldKey,
                                          keyboardHint: "Enter Password",
                                          locale:
                                              Localizations.localeOf(context)
                                                  .toString(),
                                          scrollController: _scrollController,
                                        ),
                                        OrionKbExpander(
                                            textFieldKey: dialogTextFieldKey),
                                      ],
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('Close'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('Confirm'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        child: const Text(
                          '[Debug] OrionTextField Dialog Test',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Switch(
                        value: themeToggle,
                        onChanged: (bool value) {
                          setState(
                            () {
                              themeToggle = value;
                              widget.changeThemeMode(themeToggle
                                  ? ThemeMode.dark
                                  : ThemeMode.light);
                            },
                          );
                        },
                      ),
                    ),
                    OrionKbExpander(textFieldKey: debugTextFieldKey)
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
