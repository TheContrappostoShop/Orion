// ignore_for_file: avoid_print, use_build_context_synchronously, library_private_types_in_public_api
import 'dart:io';
import 'package:flutter/material.dart';

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});

  @override
  _WifiScreenState createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  List<String> wifiNetworks = [];
  String? currentWifiSSID;
  Future<List<Map<String, String>>>? _networksFuture;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _networksFuture = _getWifiNetworks();
  }

  Icon getSignalStrengthIcon(dynamic signalStrengthReceived, String platform) {
    int signalStrength = 0;
    try {
      signalStrength = int.parse(signalStrengthReceived);
    } catch (e) {
      print(e);
      return const Icon(Icons.warning_rounded);
    }

    var icons = {
      80: Icon(Icons.network_wifi_rounded, color: Colors.green[300]),
      60: Icon(Icons.network_wifi_3_bar_rounded, color: Colors.green[300]),
      40: Icon(Icons.network_wifi_2_bar_rounded, color: Colors.orange[300]),
      20: Icon(Icons.network_wifi_1_bar_rounded, color: Colors.orange[300]),
      0: Icon(Icons.warning_rounded, color: Colors.red[300]),
    };

    if (platform == 'linux') {
      for (var threshold in icons.keys.toList().reversed) {
        if (signalStrength >= threshold) {
          return icons[threshold]!;
        }
      }
    } else {
      icons = {
        -0: Icon(Icons.network_wifi_rounded, color: Colors.green[300]),
        -50: Icon(Icons.network_wifi_3_bar_rounded, color: Colors.green[300]),
        -70: Icon(Icons.network_wifi_2_bar_rounded, color: Colors.orange[300]),
        -90: Icon(Icons.warning_rounded, color: Colors.red[300]),
      };

      signalStrength = signalStrength.abs();
      for (var threshold in icons.keys.toList().reversed) {
        if (signalStrength >= threshold.abs()) {
          return icons[threshold]!;
        }
      }
    }
    return const Icon(Icons.warning_rounded);
  }

  late String platform;
  Future<List<Map<String, String>>> _getWifiNetworks() async {
    wifiNetworks.clear();
    try {
      ProcessResult? result;
      ProcessResult? currentSSID;
      switch (Theme.of(context).platform) {
        case TargetPlatform.macOS:
          result = await Process.run(
              '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport',
              ['-s']);
          currentSSID = await Process.run(
            '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport',
            ['-I'],
          );
          platform = 'macos';
          final match =
              RegExp(r'SSID: (.*)').firstMatch(currentSSID.stdout.toString());
          currentWifiSSID = match?.group(1)?.trim() ?? '';
          break;
        case TargetPlatform.linux:
          result = await Process.run('nmcli', ['device', 'wifi', 'list']);
          platform = 'linux';
          break;
        default:
      }
      if (result?.exitCode == 0) {
        final List<Map<String, String>> networks = [];
        final List<String> lines = result!.stdout.toString().split('\n');

        RegExp pattern = RegExp('');

        switch (Theme.of(context).platform) {
          case TargetPlatform.macOS:
            pattern = RegExp(
                r'^\s*(.+?)\s{2,}(.+?)\s{2,}([^]+?)\s{2,}([^]+?)\s{2,}([^]+)$');
            break;
          case TargetPlatform.linux:
            pattern = RegExp('');
            break;
          default:
        }

        // Skip the first two lines (header and separator)
        for (int i = 2; i < lines.length; i++) {
          final RegExpMatch? match = pattern.firstMatch(lines[i]);

          if (match != null) {
            /*if (kDebugMode) {
              print('---------------------------');
              for (int i = 1; i < match.groupCount; i++) {
                print('Group $i: ${match.group(i)}');
              }
            }*/

            networks.add({
              'SSID': match.group(1) ?? '',
              'SIGNAL': match.group(2) ?? '',
            });
          }
        }
        print('Current Network: $currentWifiSSID');
        // Sort by strongest signal
        networks.sort((a, b) {
          if (a['SSID'] == currentWifiSSID) {
            return -1;
          } else if (b['SSID'] == currentWifiSSID) {
            return 1;
          } else {
            int signalA = int.parse(a['SIGNAL'] ?? '0');
            int signalB = int.parse(b['SIGNAL'] ?? '0');
            return signalB.compareTo(signalA);
          }
        });
        return mergeNetworks(networks);
      } else {
        print('Failed to get Wi-Fi networks');
        return [];
      }
    } catch (e) {
      print('Error: $e');
      return [];
    }
  }

  List<Map<String, String>> mergeNetworks(List<Map<String, String>> networks) {
    var mergedNetworks = <String, Map<String, String>>{};

    for (var network in networks) {
      var ssid = network['SSID'];
      if (mergedNetworks.containsKey(ssid)) {
        var existingNetwork = mergedNetworks[ssid]!;
        var existingSignalStrength = int.parse(existingNetwork['SIGNAL']!);
        var newSignalStrength = int.parse(network['SIGNAL']!);
        if (newSignalStrength > existingSignalStrength) {
          mergedNetworks[ssid ?? ''] = network;
        }
      } else {
        mergedNetworks[ssid ?? ''] = network;
      }
    }

    return mergedNetworks.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, String>>>(
        future: _networksFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else {
              final List<Map<String, String>> networks = snapshot.data ?? [];
              final String currentSSID = currentWifiSSID ?? '';
              return ListView.builder(
                itemCount: networks.length,
                itemBuilder: (context, index) {
                  final network = networks[index];
                  return ListTile(
                    key: ValueKey(network['SSID']),
                    title: Text(
                      '${network['SSID']}',
                      style: TextStyle(
                        color: network['SSID'] == currentSSID
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withAlpha(130)
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      'Signal Strength: ${network['SIGNAL']} dBm',
                      style: TextStyle(
                        color: network['SSID'] == currentSSID
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withAlpha(130)
                            : null,
                      ),
                    ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Future.delayed(const Duration(milliseconds: 100));
          setState(() {
            _networksFuture = _getWifiNetworks();
          });
        },
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }
}
