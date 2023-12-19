import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

abstract class CommonInterface {
  String get ssid;
  int get signalStrength;
}

class MockWifiNetwork implements CommonInterface {
  @override
  final String ssid;
  @override
  final int signalStrength;

  MockWifiNetwork({required this.ssid, required this.signalStrength});
}

class WifiScreen extends StatefulWidget {
  @override
  _WifiScreenState createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  List<String> wifiNetworks = [];

  @override
  void initState() {
    super.initState();
    _getWifiNetworks();
  }

  IconData getSignalStrengthIcon(int signalStrength) {
    if (signalStrength >= 80) {
      return Icons.network_wifi_rounded;
    } else if (signalStrength >= 60) {
      return Icons.network_wifi_3_bar_rounded;
    } else if (signalStrength >= 40) {
      return Icons.network_wifi_2_bar_rounded;
    } else if (signalStrength >= 20) {
      return Icons.network_wifi_1_bar_rounded;
    } else {
      return Icons.warning_rounded;
    }
  }

  Future<void> _getWifiNetworks() async {
    try {
      // Execute 'nmcli' command to list Wi-Fi networks
      final result = await Process.run('nmcli', ['device', 'wifi', 'list']);
      if (result.exitCode == 0) {
        // Parsing output to get Wi-Fi networks
        wifiNetworks = result.stdout.toString().split('\n');
      } else {
        print('Failed to get Wi-Fi networks');
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     
      body: ListView.builder(
        itemCount: wifiNetworks.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(wifiNetworks[index]),
            // You can add more onTap logic to connect to the selected network
            onTap: () {
              // Your logic to connect to this network
              // For Linux, this would involve executing appropriate commands
              // using Process class based on the selected network
            },
          );
        },
      ),
    );
  }
}
  

  // @override
  // Widget build(BuildContext context) {
  //   _getWifiNetworks();
  //   return Column(
  //     children: <Widget>[
  //       FutureBuilder<String>(
  //         future: getWifiIP(context),
  //         builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
  //           if (snapshot.connectionState == ConnectionState.waiting) {
  //             return const CircularProgressIndicator();
  //           } else if (snapshot.hasError) {
  //             return Text('Error: ${snapshot.error}');
  //           } else {
  //             final String wifiIP = snapshot.data ?? 'Unknown';
  //             return ListTile(
  //               title: Text(
  //                 'IP Address: $wifiIP',
  //                 style: const TextStyle(fontSize: 24),
  //               ),
  //             );
  //           }
  //         },
  //       ),
  //       Expanded(
  //         child: FutureBuilder<ConnectivityResult>(
  //           future: getWifiNetworks(context),
  //           builder: (BuildContext context,
  //               AsyncSnapshot<ConnectivityResult> snapshot) {
  //             if (snapshot.connectionState == ConnectionState.waiting) {
  //               return const CircularProgressIndicator();
  //             } else if (snapshot.hasError) {
  //               return Text('Error: ${snapshot.error}');
  //             } else {
  //               return Text('test');
  //             }
  //           },
  //         ),
  //       ),
  //     ],
  //   );
  // }
// }
