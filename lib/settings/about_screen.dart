// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:package_info/package_info.dart';

Future<String> getVersionNumber() async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return '${packageInfo.version} | Build ${packageInfo.buildNumber}';
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _AboutScreenState createState() => _AboutScreenState();
}

/// The about screen
class _AboutScreenState extends State<AboutScreen> {
  double leftPadding = 0;
  double rightPadding = 0;
  Color? _standardColor = Colors.white.withOpacity(0.0);
  Color? _qrColor = Colors.white.withOpacity(0.0);

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
        _standardColor = null;
        _qrColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black;
      });
    });

    const String title = 'Custom Printer';
    const String serialNumber = 'No S/N Available';
    const String apiVersion = 'Odyssey: 0.1.0 Alpha';
    const String boardType = 'Hardware: Apollo 3.5.2';
    const String warranty = 'No Warranty Available';

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
                          return Text('Orion: ${snapshot.data}',
                              key: textKey3,
                              style: TextStyle(
                                  fontSize: 20, color: _standardColor));
                        } else {
                          return const CircularProgressIndicator();
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
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      warranty,
                      key: textKey6,
                      style: TextStyle(fontSize: 20, color: _standardColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(
                  height: kToolbarHeight /
                      2), //TODO: Figure out why centered text looks off without this
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
                    data: 'https://github.com/TheContrappostoShop/Orion',
                    version: QrVersions.auto,
                    size: 220.0,
                    eyeStyle: QrEyeStyle(color: _qrColor),
                    dataModuleStyle: QrDataModuleStyle(
                        color: _qrColor,
                        dataModuleShape: QrDataModuleShape.circle),
                  ),
                  const SizedBox(height: kToolbarHeight / 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
