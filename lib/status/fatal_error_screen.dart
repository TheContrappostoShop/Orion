import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qr_flutter/qr_flutter.dart';

class FatalScreen extends StatefulWidget {
  const FatalScreen({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _FatalScreenState createState() => _FatalScreenState();
}

/// The about screen
class _FatalScreenState extends State<FatalScreen> {
  double leftPadding = 0;
  double rightPadding = 0;

  Color? _standardColor = Colors.white;

  final GlobalKey textKey1 = GlobalKey();
  final GlobalKey textKey2 = GlobalKey();
  final GlobalKey textKey3 = GlobalKey();
  final GlobalKey textKey4 = GlobalKey();
  final GlobalKey textKey5 = GlobalKey();
  final GlobalKey textKey6 = GlobalKey();

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final keys = [textKey1, textKey2, textKey3, textKey4, textKey5, textKey6];
      double maxWidth = 0;

      for (var key in keys) {
        final width = key.currentContext?.size?.width ?? 0;
        if (width > maxWidth) {
          maxWidth = width;
        }
      }

      final screenWidth = MediaQuery.of(context).size.width;
      setState(() {
        leftPadding = (screenWidth - maxWidth - 250) / 3;
        rightPadding = leftPadding;
        _standardColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black;
      });
    });

    const String title = 'Cooling Fan Failure!';
    const String serialNumber = 'Scan QR Code for Guidance';
    const String orionVersion = 'Board: Apollo 3.5.2';
    const String apiVersion = 'Reference Code: S1-AP-CF-F';
    const String boardType = 'Power Cycle to Continue.';

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 207, 0, 0),
      appBar: AppBar(
        title: const Text('DEBUG ORION ERROR WATCHDOG'),
      ),
      body: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      title,
                      key: textKey1,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      serialNumber,
                      key: textKey2,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      orionVersion,
                      key: textKey3,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      apiVersion,
                      key: textKey4,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      boardType,
                      key: textKey5,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
              //const SizedBox(height: kToolbarHeight / 2),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: rightPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  QrImage(
                    data: 'https://prometheus-msla.org',
                    version: QrVersions.auto,
                    size: 250.0,
                    foregroundColor: _standardColor,
                  ),
                  //const SizedBox(height: kToolbarHeight / 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
