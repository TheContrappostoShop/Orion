// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:vk/vk.dart';

import 'normal_error_screen.dart';
import 'fatal_error_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  _StatusScreenState createState() => _StatusScreenState();
}

/// The status screen
class _StatusScreenState extends State<StatusScreen> {
  bool showKeyboard = false;
  final TextEditingController _controllerText = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Status')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Center(
            child: Text(
              'Printer is ready.',
              style: TextStyle(fontSize: 24),
            ),
          ),
          ElevatedButton(
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
              setState(() {
                showKeyboard = !showKeyboard;
              });
            },
            child: const Text('Open Keyboard'),
          ),
          if (showKeyboard)
            Container(
              color: Theme.of(context).colorScheme.primary,
              height: MediaQuery.of(context).size.height / 2,
              child: VirtualKeyboard(
                height: MediaQuery.of(context).size.height / 2,
                type: VirtualKeyboardType.Alphanumeric,
                textController: _controllerText,
                builder: (BuildContext ctx, VirtualKeyboardKey key) {
                  return Container(
                    decoration: const BoxDecoration(color: Colors.red),
                    child: Center(
                      child: Text(key.text ?? '',
                          style: const TextStyle(color: Colors.red)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
