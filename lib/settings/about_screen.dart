// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
        leftPadding = (screenWidth - maxWidth - 150.dg) / 3;
        rightPadding = leftPadding;
        _standardColor = Theme.of(context).textTheme.bodyLarge!.color;
      });
    });

    const String title = kDebugMode ? 'Debug Machine' : 'Prometheus mSLA';
    const String serialNumber =
        kDebugMode ? 'S/N: DBG-0001-001' : 'No S/N Available';
    const String apiVersion =
        kDebugMode ? 'Odyssey: Simulated' : 'Odyssey: 0.1.0 Alpha';
    const String boardType =
        kDebugMode ? 'Hardware: Debugger' : 'Hardware: Apollo 3.5.2';
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
                          fontSize: 24.sp,
                          fontWeight: FontWeight.bold,
                          color: _standardColor),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20.sp),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      serialNumber,
                      key: textKey2,
                      style: TextStyle(fontSize: 20.sp, color: _standardColor),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 15.sp),
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
                            style: TextStyle(
                                fontSize: 20.sp, color: _standardColor),
                          );
                        } else {
                          return Text(
                            'Orion: N/A',
                            key: textKey3,
                            style: TextStyle(
                                fontSize: 20.sp, color: _standardColor),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(height: 15.sp),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      apiVersion,
                      key: textKey4,
                      style: TextStyle(fontSize: 20.sp, color: _standardColor),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 15.sp),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      boardType,
                      key: textKey5,
                      style: TextStyle(fontSize: 20.sp, color: _standardColor),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 15.sp),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: leftPadding),
                  child: FittedBox(
                    child: Text(
                      warranty,
                      key: textKey6,
                      style: TextStyle(fontSize: 20.sp, color: _standardColor),
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
                    data: 'https://github.com/TheContrappostoShop/Orion',
                    version: QrVersions.auto,
                    size: 150.dg,
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
    );
  }
}
