import 'package:flutter/material.dart';

/// The calibrate screen
class CalibrateScreen extends StatelessWidget {
  /// Constructs a [CalibrateScreen]
  const CalibrateScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Calibrate',
        style: TextStyle(fontSize: 24),
      ),
    );
  }
}
