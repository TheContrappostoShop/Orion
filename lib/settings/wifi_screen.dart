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

  Icon getSignalStrengthIcon(
      dynamic signalStrengthReceived, String platform) {
    int signalStrength = 0;
    try {
      signalStrength = int.parse(signalStrengthReceived);
    } catch (e) {
      print(e);
      return Icon(Icons.warning_rounded);
    }
    if (platform == 'linux') {
      if (signalStrength >= 80) {
        return Icon(Icons.network_wifi_rounded,color: Colors.green[700],);
      } else if (signalStrength >= 60) {
        return Icon(Icons.network_wifi_3_bar_rounded,color: Colors.green[700]);
      } else if (signalStrength >= 40) {
        return Icon(Icons.network_wifi_2_bar_rounded,color: Colors.orangeAccent);
      } else if (signalStrength >= 20) {
        return Icon(Icons.network_wifi_1_bar_rounded,color: Colors.orangeAccent);
      }
      return Icon(Icons.warning_rounded, color: Colors.red);
    } else {
      if (signalStrength >= -50) {
        return Icon(Icons.network_wifi_rounded,color: Colors.green[700],);
      } else if (signalStrength >= -60) {
        return Icon(Icons.network_wifi_3_bar_rounded,color: Colors.green[700]);
      } else if (signalStrength >= -70) {
        return Icon(Icons.network_wifi_2_bar_rounded,color: Colors.orangeAccent);
      }
      return Icon(Icons.warning_rounded, color: Colors.red[700]);
    }
  }

  var platform;
  Future<List<Map<String, String>>> _getWifiNetworks() async {
    try {
      var result;
      switch (Theme.of(context).platform) {
        case TargetPlatform.macOS:
          result = await Process.run('/usr/local/bin/airport', ['-s']);
          platform = 'macos';
          break;
        case TargetPlatform.linux:
          result = await Process.run('nmcli', ['device', 'wifi', 'list']);
          platform = 'linux';
          break;
        default:
      }
      if (result.exitCode == 0) {
        final List<Map<String, String>> networks = [];
        final List<String> lines = result.stdout.toString().split('\n');

        // Skip the first two lines (header and separator)
        for (int i = 2; i < lines.length; i++) {
          final List<String> columns = lines[i].split(RegExp(r'\s+'));

          if (columns.length >= 7) {
            networks.add({
              'SSID': platform == 'linux' ? columns[2] : columns[1],
              // 'MODE': columns[1],
              // 'CHAN': columns[2],
              // 'RATE': columns[3],
              'SIGNAL': platform == 'linux' ? columns[7] : columns[2],
              // 'SECURITY': columns[5],
              // 'ACTIVE': columns[6],
            });
          }
        }
        return networks;
      } else {
        print('Failed to get Wi-Fi networks');
        return [];
      }
    } catch (e) {
      print('Error: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, String>>>(
        future: _getWifiNetworks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else {
              final List<Map<String, String>> networks = snapshot.data ?? [];
              return ListView.builder(
                itemCount: networks.length,
                itemBuilder: (context, index) {
                  final network = networks[index];
                  return ListTile(
                    title: Text('SSID: ${network['SSID']}'),
                    subtitle: Text('Signal: ${network['SIGNAL']} dBm'),
                    trailing:
                        getSignalStrengthIcon(network['SIGNAL']!, platform),
                    // Add onTap logic to connect to the selected network if needed
                    onTap: () {
                      // Your logic to connect to this network
                    },
                  );
                },
              );
            }
          }
        },
      ),
    );
  }
}
