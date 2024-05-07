/*
* Orion - Print Error Screen
* Copyright (C) 2024 TheContrappostoShop (PaulGD0, shifubrams)
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PrintErrorScreen extends StatefulWidget {
  const PrintErrorScreen({super.key});

  @override
  PrintErrorScreenState createState() => PrintErrorScreenState();
}

/// The about screen
class PrintErrorScreenState extends State<PrintErrorScreen> {
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

    const String title = 'Print Failure Detected!';
    const String hint = 'Scan QR Code for Guidance';
    const String boardVersion = 'Board: Apollo 3.5.2';
    const String referenceCode = 'Reference Code: S1-AP-PR-FA';
    const String restartNote = 'Please Check For Problems.';

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
              child: Text('Resume Print',
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
              child: Text('Cancel Print',
                  style: TextStyle(fontSize: 22, color: _standardColor)),
            ),
          ),
        ],
      ),
    );
  }
}
