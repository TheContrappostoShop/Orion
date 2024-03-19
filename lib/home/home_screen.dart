import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  /// Constructs a [HomeScreen]
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const Size homeBtnSize = Size(200, 110);
    final theme = Theme.of(context).copyWith(
        elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(
      minimumSize: MaterialStateProperty.resolveWith<Size?>(
        (Set<MaterialState> states) {
          return homeBtnSize;
        },
      ),
    )));
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
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth > 600) {
              // Adjust as needed
              // Horizontal layout
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/status'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48),
                        Text('Status', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/files'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 48),
                        Text('Print Files', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/settings'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_outlined, size: 48),
                        Text('Settings', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              // Vertical layout
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/status'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48),
                        Text('Status', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/files'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 48),
                        Text('Print Files', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/settings'),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_outlined, size: 48),
                        Text('Settings', style: TextStyle(fontSize: 24)),
                      ],
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }
}

/// A live clock widget
class LiveClock extends StatefulWidget {
  /// Constructs a [LiveClock]
  const LiveClock({super.key});

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
