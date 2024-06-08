/*
* Orion - About Screen
* Copyright (C) 2024 TheContrappostoShop
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

// ignore_for_file: avoid_print
// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:orion/pubspec.dart';
import 'package:orion/themes/themes.dart';
import 'package:orion/util/orion_config.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:toastification/toastification.dart';

Future<String> getVersionNumber() async {
  return Pubspec.version;
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  _AboutScreenState createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  double leftPadding = 0;
  double rightPadding = 0;
  int qrTapCount = 0;
  bool developerMode = false;
  Color? _standardColor = Colors.white.withOpacity(0.0);

  Toastification toastification = Toastification();

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
        leftPadding = (screenWidth - maxWidth - 220) / 3;
        rightPadding = leftPadding;
        _standardColor = Theme.of(context).textTheme.bodyLarge!.color;
      });
    });

    void handleQrTap() {
      setState(() {
        if (OrionConfig().getFlag('developerMode', category: 'advanced')) {
          toastification.show(
            context: context,
            type: ToastificationType.success,
            style: ToastificationStyle.fillColored,
            autoCloseDuration: const Duration(seconds: 2),
            title: const Text('You are already a developer'),
            alignment: Alignment.topCenter,
            primaryColor: Colors.green,
            backgroundColor:
                Theme.of(context).colorScheme.surface.withBrightness(1.35),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          );
        } else {
          qrTapCount++;
          if (qrTapCount >= 5) {
            OrionConfig().setFlag('developerMode', true, category: 'advanced');
            toastification.show(
              context: context,
              type: ToastificationType.success,
              style: ToastificationStyle.fillColored,
              autoCloseDuration: const Duration(seconds: 2),
              title: const Text(
                  'Developer Mode Activated: You are now a developer!'),
              alignment: Alignment.topCenter,
              primaryColor: Colors.green,
              backgroundColor:
                  Theme.of(context).colorScheme.surface.withBrightness(1.35),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            );
          } else {
            toastification.show(
              context: context,
              type: ToastificationType.info,
              style: ToastificationStyle.flatColored,
              autoCloseDuration: const Duration(seconds: 2),
              title: Text(
                  'You are ${5 - qrTapCount} ${5 - qrTapCount == 1 ? 'tap' : 'taps'} away from becoming a developer'),
              alignment: Alignment.topCenter,
              primaryColor: Theme.of(context).colorScheme.primary,
              backgroundColor:
                  Theme.of(context).colorScheme.surface.withBrightness(1.35),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              showProgressBar: false,
            );
          }
        }
      });
    }

    const String title = kDebugMode ? 'Debug Machine' : 'Prometheus mSLA';
    const String serialNumber =
        kDebugMode ? 'S/N: DBG-0001-001' : 'No S/N Available';
    const String apiVersion = kDebugMode ? 'Odyssey: Simulated' : 'Odyssey: ?';
    const String boardType =
        kDebugMode ? 'Hardware: Debugger' : 'Hardware: Apollo 3.5.2';

    return Scaffold(
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
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _standardColor),
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
                      style: TextStyle(fontSize: 20, color: _standardColor),
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
                    child: FutureBuilder<String>(
                      future: getVersionNumber(),
                      builder: (BuildContext context,
                          AsyncSnapshot<String> snapshot) {
                        if (snapshot.hasData) {
                          return Text(
                            'Orion: ${snapshot.data}',
                            key: textKey3,
                            style:
                                TextStyle(fontSize: 20, color: _standardColor),
                          );
                        } else {
                          return Text(
                            'Orion: N/A',
                            key: textKey3,
                            style:
                                TextStyle(fontSize: 20, color: _standardColor),
                          );
                        }
                      },
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
                      style: TextStyle(fontSize: 20, color: _standardColor),
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
                      style: TextStyle(fontSize: 20, color: _standardColor),
                    ),
                  ),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: handleQrTap,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: rightPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    QrImageView(
                      data: 'https://github.com/TheContrappostoShop/Orion',
                      version: QrVersions.auto,
                      size: 220,
                      eyeStyle: QrEyeStyle(color: _standardColor),
                      dataModuleStyle: QrDataModuleStyle(
                          color: _standardColor,
                          dataModuleShape: QrDataModuleShape.circle),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
