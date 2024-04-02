/*
 *    Orion Debug Screen
 *    Copyright (c) 2024 TheContrappostoShop (Paul S.)
 *    GPLv3 Licensing (see LICENSE)
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';

class DebugScreen extends StatefulWidget {
  final Function(ThemeMode) changeThemeMode;

  const DebugScreen({super.key, required this.changeThemeMode});

  @override
  DebugScreenState createState() => DebugScreenState();
}

class DebugScreenState extends State<DebugScreen> {
  final GlobalKey<SpawnOrionTextFieldState> debugTextFieldKey = GlobalKey<SpawnOrionTextFieldState>();
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
    double bottom = Theme.of(context).navigationBarTheme.height ?? 80;

    return Scaffold(
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        controller: _scrollController,
        child: Column(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Internal Debug Screen\nNOT FOR PUBLIC RELEASE',
                      style: TextStyle(fontSize: 20, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: ElevatedButton(
                      onPressed: () {
                        String text = debugTextFieldKey.currentState!.getCurrentText();
                        if (kDebugMode) {
                          print("[Debug]: DebugTestField content: $text");
                        }
                        debugTextFieldKey.currentState!.clearText();
                      },
                      child: const Text('[Debug] Read TextField to Console')),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Center(child: Text('WiFi-Test-0123 Password')),
                            content: SizedBox(
                              width: MediaQuery.of(context).size.width * 0.5, // Half the screen width
                              child: SpawnOrionTextField(
                                keyboardHint: "Enter Password",
                                locale: Localizations.localeOf(context).toString(),
                                scrollController: _scrollController,
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
                    child: const Text('[Debug] OrionTextField Dialog Test'),
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
                          widget.changeThemeMode(themeToggle ? ThemeMode.dark : ThemeMode.light);
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  child: SpawnOrionTextField(
                    key: debugTextFieldKey,
                    keyboardHint: "Debug Test Field",
                    locale: Localizations.localeOf(context).toString(),
                    scrollController: _scrollController,
                    isHidden: true,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: bottom,
                ),
              ],
            ),
          ),
          const SizedBox(
            height: 1000,
          ),
        ]),
      ),
    );
  }
}
