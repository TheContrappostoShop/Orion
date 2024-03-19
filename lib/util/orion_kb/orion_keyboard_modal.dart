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
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30.0),
              topRight: Radius.circular(30.0),
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
    double heightFactor = (240 / MediaQuery.of(context).size.height);
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      heightFactor = (320 / MediaQuery.of(context).size.height);
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.5),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      )),
      child: FractionallySizedBox(
        heightFactor: heightFactor,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
    );
  }
}
