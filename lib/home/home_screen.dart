import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  /// Constructs a [HomeScreen]
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                      left: MediaQuery.of(context).size.width * 0.02),
                  child: const LiveClock(),
                ),
              ],
            ),
            const Text(
              'Prometheus mSLA',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              onPressed: () => context.go('/status'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 110),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.info_outline, size: 48),
                  Text('Status', style: TextStyle(fontSize: 24)),
                ],
              ),
            ),
            const SizedBox(width: 20),
            ElevatedButton(
              onPressed: () => context.go('/files'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 110),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.folder_open_outlined, size: 48),
                  Text('Print Files', style: TextStyle(fontSize: 24)),
                ],
              ),
            ),
            const SizedBox(width: 20),
            ElevatedButton(
              onPressed: () => context.go('/settings'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 110),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.settings_outlined, size: 48),
                  Text('Settings', style: TextStyle(fontSize: 24)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

/// A live clock widget
class LiveClock extends StatefulWidget {
  /// Constructs a [LiveClock]
  const LiveClock({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _LiveClockState createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late Timer _timer;
  late DateTime _dateTime;

  @override
  void initState() {
    super.initState();
    _dateTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      setState(() {
        _dateTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${_dateTime.hour.toString().padLeft(2, '0')}:${_dateTime.minute.toString().padLeft(2, '0')}',
      style: const TextStyle(fontSize: 20),
    );
  }
}
