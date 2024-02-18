/*
 *    Custom Textfield to display the Orion Keyboard
 *    Copyright (c) 2024 TheContrappostoShop (Paul S.)
 *    GPLv3 Licensing (see LICENSE)
 */

import 'package:flutter/material.dart';
import 'package:orion/util/orion_keyboard_modal.dart';

class OrionTextField extends StatefulWidget {
  final ValueNotifier<bool> isKeyboardOpen;

  const OrionTextField({super.key, required this.isKeyboardOpen});

  @override
  OrionTextFieldState createState() => OrionTextFieldState();
}

class OrionTextFieldState extends State<OrionTextField> {
  late FocusNode _focusNode;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _controller = TextEditingController();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.isKeyboardOpen.value = true;
        Navigator.of(context).push(OrionKbModal()).then(
          (result) {
            widget.isKeyboardOpen.value = false;
            if (result != null) {
              _controller.text = result;
            }
          },
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: AbsorbPointer(
          child: TextField(
            focusNode: _focusNode,
            controller: _controller,
            readOnly: true,
            showCursor: true, // to prevent the system keyboard from showing
            decoration: const InputDecoration(
              hintText: 'Tap to enter text',
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }
}
