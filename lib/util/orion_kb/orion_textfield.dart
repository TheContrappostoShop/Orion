/*
* Orion - Orion Textfield
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

import 'package:flutter/material.dart';
import 'package:orion/themes/themes.dart';
import 'package:orion/util/orion_kb/orion_keyboard_modal.dart';

class OrionTextField extends StatefulWidget {
  final ValueNotifier<bool> isKeyboardOpen;
  final String keyboardHint;
  final TextEditingController controller;
  final String locale;
  final bool isHidden;
  final Function(String) onChanged;

  const OrionTextField({
    super.key,
    required this.isKeyboardOpen,
    required this.keyboardHint,
    required this.controller,
    required this.locale,
    required this.isHidden,
    required this.onChanged,
  });

  @override
  OrionTextFieldState createState() => OrionTextFieldState();
}

class OrionTextFieldState extends State<OrionTextField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  final focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    TextStyle style = const TextStyle(fontSize: 20);

    return GestureDetector(
      onTap: () {
        widget.isKeyboardOpen.value = true;
        if (widget.controller.text.isEmpty) {
          widget.controller.text = '\u200B';
        }
        Navigator.of(context)
            .push(OrionKbModal(
                textController: widget.controller, locale: widget.locale))
            .then(
          (result) {
            widget.isKeyboardOpen.value = false;
            if (result != null) {
              widget.controller.text = result;
              widget.onChanged(
                  result.replaceAll('\u200B', '').replaceAll('\u00A0', ' '));
            }
            if (widget.controller.text == '\u200B') {
              widget.controller.text = '';
            }
          },
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: AbsorbPointer(
          child: Padding(
            padding: const EdgeInsets.only(left: 0.0, right: 0.0, top: 0.0),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: widget.isKeyboardOpen,
                  builder: (context, isKeyboardOpen, child) {
                    return TextField(
                      controller: widget.controller,
                      readOnly: true,

                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: isKeyboardOpen
                                ? Theme.of(context)
                                    .colorScheme
                                    .inversePrimary
                                    .withBrightness(1.2)
                                : Theme.of(context).textTheme.bodyLarge!.color!,
                          ),
                        ),
                        labelText: widget.keyboardHint,
                      ),
                      // Hide the original text, We overlay our own with an animated line (cursor)
                      style: style.copyWith(
                          color: Colors.transparent, fontSize: 28),
                    );
                  },
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(left: 12.0, right: 12.0, top: 2),
                  child: AnimatedBuilder(
                    animation: _animController,
                    builder: (BuildContext context, Widget? child) {
                      return Text.rich(
                        TextSpan(
                          text: !widget.isHidden
                              ? widget.controller.text.replaceAll(' ', '\u00A0')
                              : widget.controller.text
                                  .replaceAll(RegExp('[^\u200B]'), '•'),
                          style: style.copyWith(
                            color: widget.isKeyboardOpen.value
                                ? Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color!
                                    .withBrightness(1.2)
                                : Theme.of(context).textTheme.bodyLarge!.color!,
                          ),
                          children: [
                            WidgetSpan(
                              child: Opacity(
                                opacity: _animController.value,
                                child: Container(
                                  width: 1.5,
                                  height: 20,
                                  color: widget.isKeyboardOpen.value
                                      ? Theme.of(context)
                                          .textTheme
                                          .bodyLarge!
                                          .color!
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    widget.controller.dispose();
    _animController.dispose();
    super.dispose();
  }
}
