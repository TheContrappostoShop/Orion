import 'package:flutter/material.dart';

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
        children: const [
          Center(
            child: Text(
              'Printer is ready.',
              style: TextStyle(fontSize: 24),
            ),
          ),
        ],
      ),
    );
  }
}
