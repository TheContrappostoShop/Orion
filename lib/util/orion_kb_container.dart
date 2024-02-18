// OrionKbContainer.dart
import 'package:flutter/material.dart';
import 'package:orion/util/orion_textfield.dart';

class SpawnOrionKB extends StatefulWidget {
  const SpawnOrionKB({super.key});

  @override
  SpawnOrionKBState createState() => SpawnOrionKBState();
}

class SpawnOrionKBState extends State<SpawnOrionKB> {
  final ValueNotifier<bool> isKeyboardOpen = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    double halfScreenHeight = MediaQuery.of(context).size.height / 2;

    return ValueListenableBuilder<bool>(
      valueListenable: isKeyboardOpen,
      builder: (context, keyboardOpen, child) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding:
              EdgeInsets.only(bottom: keyboardOpen ? halfScreenHeight : 0.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Your other widgets...
              OrionTextField(isKeyboardOpen: isKeyboardOpen),
            ],
          ),
        );
      },
    );
  }
}
