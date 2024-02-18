import 'package:flutter/material.dart';
import 'package:orion/status/error_print_failure.dart';
import 'package:orion/status/fatal_error_screen.dart';
import 'package:orion/status/normal_error_screen.dart';
import 'package:orion/util/orion_kb_container.dart';
import 'package:orion/util/orion_keyboard_modal.dart';

/// The calibrate screen
class DebugScreen extends StatelessWidget {
  /// Constructs a [DebugScreen]
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Text(
              'Orion Debug - OrionKbModal, OrionKbContainer, OrionTextField',
              style: TextStyle(fontSize: 14, color: Colors.red),
            ),
          ),
          /*ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ErrorScreen()),
              );
            },
            child: const Text('Go to Error Screen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FatalScreen()),
              );
            },
            child: const Text('Go to Fatal Error Screen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PrintErrorScreen()),
              );
            },
            child: const Text('Go to Print Error Screen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(OrionKbModal());
            },
            child: const Text('Open Keyboard'),
          ),*/
          const SpawnOrionKB(),
        ],
      ),
    );
  }
}
