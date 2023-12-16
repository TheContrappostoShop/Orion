import 'package:flutter/material.dart';

import 'normal_error_screen.dart';
import 'fatal_error_screen.dart';

/// The status screen
class StatusScreen extends StatelessWidget {
  /// Constructs a [StatusScreen]
  const StatusScreen({Key? key}) : super(key: key);

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
        ],
      ),
    );
  }
}
