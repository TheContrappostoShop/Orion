import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  /// Constructs a [HomeScreen]
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    // High DPI devices will have a pixelRatio if 2.0, set them to 1.0.
    double scaleFactor = 1 /
        ((ScreenUtil().pixelRatio ?? 1.0) == 2.0
            ? 1.0
            : (ScreenUtil().pixelRatio ?? 1.0));

    Size homeBtnSize = Size(220 * scaleFactor, 130 * scaleFactor);

    final theme = Theme.of(context).copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: MaterialStateProperty.resolveWith<Size?>(
            (Set<MaterialState> states) {
              return homeBtnSize;
            },
          ),
        ),
      ),
    );

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
            if (MediaQuery.of(context).orientation == Orientation.landscape) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/status'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48 * scaleFactor),
                        Text('Status',
                            style: TextStyle(fontSize: 24 * scaleFactor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/files'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined,
                            size: 48 * scaleFactor),
                        Text('Print Files',
                            style: TextStyle(fontSize: 24 * scaleFactor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/settings'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_outlined, size: 48 * scaleFactor),
                        Text('Settings',
                            style: TextStyle(fontSize: 24 * scaleFactor)),
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48 * scaleFactor),
                        Text('Status',
                            style: TextStyle(fontSize: 24 * scaleFactor)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/files'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_outlined,
                            size: 48 * scaleFactor),
                        Text('Print Files',
                            style: TextStyle(fontSize: 24 * scaleFactor)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: theme.elevatedButtonTheme.style,
                    onPressed: () => context.go('/settings'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.settings_outlined, size: 48 * scaleFactor),
                        Text('Settings',
                            style: TextStyle(fontSize: 24 * scaleFactor)),
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
