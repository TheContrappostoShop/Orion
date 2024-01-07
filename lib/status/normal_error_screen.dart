import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ErrorScreen extends StatefulWidget {
  const ErrorScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ErrorScreenState createState() => _ErrorScreenState();
}

/// The about screen
class _ErrorScreenState extends State<ErrorScreen> {
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

    const String title = 'UV Panel Overheated!';
    const String hint = 'Scan QR Code for Guidance';
    const String boardVersion = 'Board: Apollo 3.5.2';
    const String referenceCode = 'Reference Code: S1-AP-UV-OH';
    const String restartNote = 'Please Restart to Continue.';

    return Scaffold(
      backgroundColor: const Color.fromARGB(215, 207, 124, 0),
      /*appBar: AppBar(
        title: const Text('DEBUG ORION ERROR WATCHDOG'),
      ),*/
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
                      hint,
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
                      boardVersion,
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
                      referenceCode,
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
                      restartNote,
                      key: textKey5,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: rightPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  QrImageView(
                    data: 'https://github.com/TheContrappostoShop',
                    version: QrVersions.auto,
                    size: 250.0,
                    eyeStyle: QrEyeStyle(color: _standardColor),
                    dataModuleStyle: QrDataModuleStyle(
                        color: _standardColor,
                        dataModuleShape: QrDataModuleShape.circle),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all(
                    const Color.fromARGB(255, 207, 124, 0)),
                overlayColor: MaterialStateProperty.all(
                    Theme.of(context).primaryColor.withOpacity(0.2)),
                minimumSize: MaterialStateProperty.all(
                    const Size(double.infinity, kToolbarHeight * 1.2)),
                shape: MaterialStateProperty.all(const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero)),
              ),
              child: Text('Restart Printer',
                  style: TextStyle(fontSize: 22, color: _standardColor)),
            ),
          ),
          const SizedBox(
              height: kToolbarHeight,
              child: VerticalDivider(
                  width: 2, color: Color.fromARGB(215, 207, 124, 0))),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all(
                    const Color.fromARGB(255, 207, 124, 0)),
                overlayColor: MaterialStateProperty.all(
                    Theme.of(context).primaryColor.withOpacity(0.2)),
                minimumSize: MaterialStateProperty.all(
                    const Size(double.infinity, kToolbarHeight * 1.2)),
                shape: MaterialStateProperty.all(const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero)),
              ),
              child: Text('Advanced Information',
                  style: TextStyle(fontSize: 22, color: _standardColor)),
            ),
          ),
        ],
      ),
    );
  }
}
