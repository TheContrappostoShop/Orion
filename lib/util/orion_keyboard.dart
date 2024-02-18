/*
 *    Custom Keyboard for Orion
 *    Copyright (c) 2024 TheContrappostoShop (Paul S.)
 *    GPLv3 Licensing (see LICENSE)
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orion/themes/themes.dart';

class OrionKeyboard extends StatefulWidget {
  const OrionKeyboard({super.key});

  @override
  OrionKeyboardState createState() => OrionKeyboardState();
}

class OrionKeyboardState extends State<OrionKeyboard> {
  final ValueNotifier<bool> _isShiftEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isCapsEnabled = ValueNotifier<bool>(false);

  // Lookup table for en_US keyboard layout
  final Map<String, String> _keyboardLayout = {
    'row1': 'qwertyuiop',
    'row2': 'asdfghjkl',
    'row3': 'zxcvbnm',
    'bottomRow1': '123',
    'bottomRow2': '',
    'bottomRow3': 'return',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isShiftEnabled,
      builder: (context, isShiftEnabled, child) {
        return SizedBox(
          height: MediaQuery.of(context).size.height / 2.0,
          width: MediaQuery.of(context).size.width,
          child: Column(
            children: [
              buildRow(_keyboardLayout['row1']!),
              buildRow(_keyboardLayout['row2']!),
              buildRow(_keyboardLayout['row3']!, hasShiftAndBackspace: true),
              buildBottomRow(),
            ],
          ),
        );
      },
    );
  }

  Widget buildRow(String rowCharacters, {bool hasShiftAndBackspace = false}) {
    return Expanded(
      child: Row(
        children: [
          SizedBox(width: hasShiftAndBackspace ? 10 : 0),
          if (hasShiftAndBackspace)
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isCapsEnabled,
                builder: (context, isCapsEnabled, child) {
                  return KeyboardButton(
                    text: _isCapsEnabled.value ? "⇪" : "⇧",
                    onPressed: () {
                      if (_isShiftEnabled.value == true) {
                        if (_isCapsEnabled.value == false) {
                          _isCapsEnabled.value = true;
                        } else {
                          _isCapsEnabled.value = false;
                          _isShiftEnabled.value = !_isShiftEnabled.value;
                        }
                      } else {
                        _isShiftEnabled.value = !_isShiftEnabled.value;
                      }
                      if (kDebugMode) {
                        print("ShiftState ${_isShiftEnabled.value}");
                        print("CapsState ${_isCapsEnabled.value}");
                      }
                    },
                    isShiftEnabled: _isShiftEnabled,
                    isCapsEnabled: _isCapsEnabled,
                  );
                },
              ),
            ),
          const SizedBox(width: 10),
          ...rowCharacters
              .split('')
              .expand((char) => [
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isShiftEnabled,
                        builder: (context, isShiftEnabled, child) {
                          return KeyboardButton(
                            text: isShiftEnabled ? char.toUpperCase() : char,
                            isShiftEnabled: _isShiftEnabled,
                            isCapsEnabled: _isCapsEnabled,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ])
              .toList()
            ..removeLast(),
          SizedBox(width: hasShiftAndBackspace ? 10 : 0),
          if (hasShiftAndBackspace)
            Expanded(
              child: KeyboardButton(
                text: "⌫",
                isShiftEnabled: _isShiftEnabled,
                isCapsEnabled: _isCapsEnabled,
              ),
            ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget buildBottomRow() {
    return Expanded(
      child: Row(
        children: [
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: KeyboardButton(
              text: _keyboardLayout['bottomRow1']!,
              isShiftEnabled: _isShiftEnabled,
              isCapsEnabled: _isCapsEnabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: KeyboardButton(
              text: _keyboardLayout['bottomRow2']!,
              isShiftEnabled: _isShiftEnabled,
              isCapsEnabled: _isCapsEnabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 1,
            child: KeyboardButton(
              text: _keyboardLayout['bottomRow3']!,
              isShiftEnabled: ValueNotifier<bool>(false),
              isCapsEnabled: _isCapsEnabled,
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

class KeyboardButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final ValueChanged<String>? onKeyPress;
  final ValueNotifier<bool> isShiftEnabled;
  final ValueNotifier<bool> isCapsEnabled;

  const KeyboardButton({
    super.key,
    required this.text,
    this.onPressed,
    this.onKeyPress,
    required this.isShiftEnabled,
    required this.isCapsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: _getButtonBackgroundColor(context),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(25)),
          ),
        ),
        onPressed: onPressed ??
            () => isCapsEnabled.value ? null : isShiftEnabled.value = false,
        child: Container(
          alignment: Alignment.center,
          child: ValueListenableBuilder<bool>(
            valueListenable: isShiftEnabled,
            builder: (context, isShiftEnabled, child) {
              return Text(
                isShiftEnabled ? text.toUpperCase() : text.toLowerCase(),
                style: const TextStyle(fontSize: 20),
              );
            },
          ),
        ),
      ),
    );
  }

  // This method returns the background color for the keyboard button based on the text value.
  // The brightness of the color is determined by a lookup table.
  Color? _getButtonBackgroundColor(BuildContext context) {
    final lookupTable = {
      // 3.0 is the brightness factor for the shift button
      // 1.3 is the brightness factor for modifier keys
      '⇧': isShiftEnabled.value ? 3.0 : 1.3,
      '⇪': isCapsEnabled.value ? 3.0 : 1.3,
      '⌫': 1.3,
      '123': 1.3,
      'return': 1.3,
    };

    // 1.8 is the brightness factor for all alphanumeric keys
    final brightness = lookupTable[text] ?? 1.8;
    return Theme.of(context).colorScheme.surface.withBrightness(brightness);
  }
}
