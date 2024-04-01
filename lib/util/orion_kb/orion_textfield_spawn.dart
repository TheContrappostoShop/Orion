/*
 *    Container to display the Orion Keyboard + Textfield
 *    Copyright (c) 2024 TheContrappostoShop (Paul S.)
 *    GPLv3 Licensing (see LICENSE)
 */

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:orion/util/orion_kb/orion_textfield.dart';

class SpawnOrionTextField extends StatefulWidget {
  final String keyboardHint;
  final String locale;
  final bool isHidden;
  final bool noShove;
  final Function(String) onChanged;

  const SpawnOrionTextField({
    super.key,
    required this.keyboardHint,
    required this.locale,
    this.isHidden = false,
    this.noShove = false,
    this.onChanged = _defaultOnChanged,
  });

  // Do nothing
  static void _defaultOnChanged(String text) {}

  @override
  SpawnOrionTextFieldState createState() => SpawnOrionTextFieldState();
}

class SpawnOrionTextFieldState extends State<SpawnOrionTextField> {
  final ValueNotifier<bool> isKeyboardOpen = ValueNotifier<bool>(false);
  final TextEditingController _controller = TextEditingController();

  double padding = 0.0;
  int duration = 300; // Define duration here

  String getCurrentText() {
    String text = _controller.text;
    text = text
        .replaceAll('\u200B', '')
        .replaceAll('\u00A0', ' '); // Strip \u200B from the text
    return text;
  }

  void clearText() {
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double screenHeight = mediaQuery.size.height;
    final double keyboardHeight = screenHeight / 2;

    return ValueListenableBuilder<bool>(
      valueListenable: isKeyboardOpen,
      builder: (context, keyboardOpen, child) {
        if (keyboardOpen) {
          RenderBox renderBox = context.findRenderObject() as RenderBox;
          double distanceFromBottomToTextField = screenHeight -
              renderBox.localToGlobal(Offset.zero).dy -
              renderBox.size.height;
          double distance = max(0.0, keyboardHeight);

          if (distanceFromBottomToTextField < keyboardHeight) {
            distance = keyboardHeight - distanceFromBottomToTextField + 15.0;
          } else {
            distance = 0.0;
          }

          //TODO: Fix the animation duration and delay

          int containerAnimationDuration =
              (300 * (distance / screenHeight)).round();
          int delay = 0;

          Future.delayed(Duration(milliseconds: delay), () {
            setState(() {
              padding = distance;
              if (widget.noShove) padding = 0.0;
              duration = containerAnimationDuration;
            });
          });
        } else {
          padding = 0.0;
        }

        return AnimatedContainer(
          duration: keyboardOpen
              ? Duration(milliseconds: duration)
              : const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: padding),
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    OrionTextField(
                      isKeyboardOpen: isKeyboardOpen,
                      keyboardHint: widget.keyboardHint,
                      controller: _controller,
                      locale: widget.locale,
                      isHidden: widget.isHidden,
                      onChanged: widget.onChanged,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: IconButton(
                        onPressed: () {
                          _controller.clear();
                          widget.onChanged('');
                        },
                        icon: const Icon(Icons.clear_outlined),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
