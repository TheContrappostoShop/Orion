/*
 *    Custom Modal to display the Orion Keyboard
 *    Copyright (c) 2024 TheContrappostoShop (Paul S.)
 *    GPLv3 Licensing (see LICENSE)
 */

import 'package:flutter/material.dart';
import 'package:orion/util/orion_kb/orion_keyboard.dart';

class OrionKbModal extends ModalRoute<String> {
  final TextEditingController textController;
  final String locale;

  OrionKbModal({
    required this.textController,
    required this.locale,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => true;

  @override
  Color get barrierColor => Colors.black.withOpacity(0.2);

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final radius = (width > height) ? width / 30 : height / 30;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(radius),
              topRight: Radius.circular(radius),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5.0),
            child: OrionKeyboard(
              controller: textController,
              locale: locale,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.5),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      )),
      child: FractionallySizedBox(
        heightFactor: 0.5,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
    );
  }
}
