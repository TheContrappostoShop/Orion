import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _AboutScreenState createState() => _AboutScreenState();
}

/// The about screen
class _AboutScreenState extends State<AboutScreen> {
  double leftPadding = 0;
  double rightPadding = 0;

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
      });
    });

    const String title = 'Prometheus mSLA';
    const String serialNumber = 'Serial: CS-PROM2023DEV';
    const String orionVersion = 'Orion: 0.1.0 Alpha';
    const String apiVersion = 'Odyssey: 0.1.0 Alpha';
    const String boardType = 'Board: Apollo 3.5.2';
    const String warranty = 'Warranty Date: 0000-00-00';

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
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
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
                      style: const TextStyle(fontSize: 20),
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
                      style: const TextStyle(fontSize: 20),
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
                      style: const TextStyle(fontSize: 20),
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
                      style: const TextStyle(fontSize: 20),
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
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kToolbarHeight / 2),
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
                    data: 'https://github.com/TheContrappostoShop',
                    version: QrVersions.auto,
                    size: 220.0,
                    foregroundColor: Colors.white,
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
