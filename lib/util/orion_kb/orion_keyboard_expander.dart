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
