/*
* Orion - WiFi Screen
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

// ignore_for_file: avoid_print, use_build_context_synchronously, library_private_types_in_public_api, unused_field

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:orion/util/orion_kb/orion_keyboard_expander.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});

  @override
  _WifiScreenState createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  List<String> wifiNetworks = [];
  String? currentWifiSSID;
  Future<List<Map<String, String>>>? _networksFuture;
  Color? _standardColor = Colors.white.withOpacity(0.0);
  final Logger _logger = Logger('Wifi');

  final GlobalKey<SpawnOrionTextFieldState> wifiPasswordKey =
      GlobalKey<SpawnOrionTextFieldState>();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _networksFuture = _getWifiNetworks();
  }

  Future<String> _getIPAddress() async {
    String ipAddress;
    try {
      final List<NetworkInterface> networkInterfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      ipAddress = networkInterfaces.first.addresses.first.address;
    } on PlatformException catch (e) {
      print('Failed to get IP Address: $e');
      ipAddress = 'Failed to get IP Address';
    }
    return ipAddress;
  }

  Icon getSignalStrengthIcon(dynamic signalStrengthReceived, String platform) {
    int signalStrength = 0;

    try {
      signalStrength = int.parse(signalStrengthReceived);
    } catch (e) {
      print(e);
      return const Icon(Icons.warning_rounded);
    }

    // Define the icons for each platform
    final Map<int, Icon> linuxIcons = {
      100: Icon(Icons.network_wifi_rounded, color: Colors.green[300], size: 30),
      80: Icon(Icons.network_wifi_rounded, color: Colors.green[300], size: 30),
      60: Icon(Icons.network_wifi_3_bar_rounded,
          color: Colors.green[300], size: 30),
      40: Icon(Icons.network_wifi_2_bar_rounded,
          color: Colors.orange[300], size: 30),
      20: Icon(Icons.network_wifi_1_bar_rounded,
          color: Colors.orange[300], size: 30),
      0: Icon(Icons.warning_rounded, color: Colors.red[300], size: 30),
    };

    final Map<int, Icon> otherIcons = {
      10: Icon(Icons.network_wifi_rounded, color: Colors.green[300], size: 30),
      0: Icon(Icons.network_wifi_rounded, color: Colors.green[300], size: 30),
      -50: Icon(Icons.network_wifi_3_bar_rounded,
          color: Colors.green[300], size: 30),
      -70: Icon(Icons.network_wifi_2_bar_rounded,
          color: Colors.orange[300], size: 30),
      -90: Icon(Icons.warning_rounded, color: Colors.red[300], size: 30),
    };

    // Choose the correct map of icons based on the platform
    final Map<int, Icon> icons = platform == 'linux' ? linuxIcons : otherIcons;

    // Find the first icon where the signal strength is less than or equal to the threshold
    for (var threshold in icons.keys.toList().reversed) {
      if (signalStrength <= threshold) {
        return icons[threshold]!;
      }
    }

    // If no icon was found, return a warning icon
    return const Icon(Icons.warning_rounded);
  }

  late String platform;
  Future<List<Map<String, String>>> _getWifiNetworks(
      {bool alreadyConnected = false}) async {
    wifiNetworks.clear();
    try {
      if (Theme.of(context).platform == TargetPlatform.macOS &&
          !alreadyConnected) {
        currentWifiSSID = 'test';
      }
      ProcessResult? result;
      switch (Theme.of(context).platform) {
        case TargetPlatform.macOS:
          platform = 'macos';
          final List<Map<String, String>> networks = [];
          // Generate fake output
          for (int i = 0; i < 10; i++) {
            networks.add({
              'SSID': 'Network $i',
              'SIGNAL':
                  '${-30 - i * 5}', // Signal strength decreases with each network
              'BSSID': '00:0a:95:9d:68:1$i',
              'RSSI': '${-30 - i * 5}',
              'CHANNEL': '${1 + i}',
              'HT': 'Y',
              'CC': 'US',
              'SECURITY': '(WPA2)'
            });
          }
          //if (!alreadyConnected) currentWifiSSID = networks.first['SSID'];
          return networks;
        case TargetPlatform.linux:
          platform = 'linux';
          // Get the current Wi-Fi network
          await Process.run('sudo', ['nmcli', 'device', 'wifi', 'rescan']);
          _logger.info('Rescanning Wi-Fi networks');
          result = await Process.run('nmcli', ['device', 'wifi', 'list']);
          try {
            var result = await Process.run(
                'nmcli', ['-t', '-f', 'active,ssid', 'dev', 'wifi']);
            var lines = result.stdout.toString().split('\n');
            var activeNetworkLine =
                lines.firstWhere((line) => line.startsWith('yes:'));
            var activeNetworkSSID = activeNetworkLine.split(':')[1];
            if (!alreadyConnected) currentWifiSSID = activeNetworkSSID;
            _logger.info(activeNetworkSSID);
          } catch (e) {
            _logger.severe('Failed to get current Wi-Fi network: $e');
          }
          _logger.info('Getting Wi-Fi networks');
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
            pattern = RegExp(
              r"(?:(\*)\s+)?([0-9A-Fa-f:]{17})\s+(.*?)\s+(Infra)\s+(\d+)\s+([\d\sMbit/s]+)\s+(\d+)\s+([\w▂▄▆█_]+)\s+(.*)",
              multiLine: true,
            );
            break;
          default:
        }

        // Skip the first two lines (header and separator)
        for (int i = 2; i < lines.length; i++) {
          final RegExpMatch? match = pattern.firstMatch(lines[i]);

          if (match != null) {
            print('---------------------------');
            for (int i = 1; i < match.groupCount; i++) {
              print('Group $i: ${match.group(i)}');
            }

            if (platform == 'macos') {
              networks.add({
                'SSID': match.group(1) ?? '',
                'SIGNAL': match.group(2) ?? '',
                'SECURITY': match.group(8) ?? '',
              });
            } else if (platform == 'linux') {
              networks.add({
                'SSID': match.group(3) ?? '',
                'SIGNAL': match.group(7) ?? '',
                'SECURITY': match.group(9) ?? '',
              });
            }
          }
        }

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

  void connectToNetwork(String ssid, String password) async {
    try {
      final result = await Process.run('sudo',
          ['nmcli', 'dev', 'wifi', 'connect', ssid, 'password', password]);
      if (result.exitCode == 0) {
        setState(() {
          currentWifiSSID = ssid;
          _networksFuture = _getWifiNetworks(alreadyConnected: true);
        });
        _logger.info('Connected to $ssid');
      } else {
        _logger.warning('Failed to connect to $ssid');
      }
    } catch (e) {
      _logger.warning('Failed to connect to Wi-Fi network: $e');
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

  String signalStrengthToQuality(int signalStrength) {
    if (signalStrength >= -50) {
      return 'Perfect';
    } else if (signalStrength >= -60) {
      return 'Good';
    } else if (signalStrength >= -70) {
      return 'Fair';
    } else {
      return 'Weak';
    }
  }

  @override
  Widget build(BuildContext context) {
    _standardColor = Theme.of(context).textTheme.bodyLarge!.color;
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
              if (currentSSID.isNotEmpty) {
                return FutureBuilder<String>(
                  future: _getIPAddress(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      } else {
                        final String ipAddress = snapshot.data ?? '';
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 16),
                            child: Column(
                              children: [
                                const Spacer(),
                                Card.outlined(
                                  elevation: 5,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: <Widget>[
                                      const SizedBox(height: 10),
                                      RichText(
                                        text: TextSpan(
                                          style: DefaultTextStyle.of(context)
                                              .style,
                                          children: <TextSpan>[
                                            TextSpan(
                                              text: 'Connected: ',
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                            ),
                                            TextSpan(
                                              text: currentSSID,
                                              style: TextStyle(
                                                fontSize: 26,
                                                fontWeight: FontWeight.normal,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Divider(height: 1),
                                      const SizedBox(height: 25),
                                      Text(
                                        'IP Address: $ipAddress',
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                      const SizedBox(height: 25),
                                      Text(
                                        'Signal Strength: ${signalStrengthToQuality(int.parse(networks.first['SIGNAL']!))} [${networks.first['SIGNAL']}]',
                                        style: const TextStyle(fontSize: 24),
                                      ),
                                      const SizedBox(height: 25),
                                      ElevatedButton(
                                        onPressed: () async {
                                          try {
                                            //await Process.run('nmcli', ['dev', 'disconnect', 'iface', 'wlan0']);
                                            setState(() {
                                              currentWifiSSID = null;
                                              _networksFuture =
                                                  _getWifiNetworks(
                                                      alreadyConnected: true);
                                            });
                                          } catch (e) {
                                            print(
                                                'Failed to disconnect Wi-Fi: $e');
                                          }
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(15),
                                          child: Text(
                                            'Disconnect',
                                            style: TextStyle(fontSize: 24),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 25),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                        );
                      }
                    }
                  },
                );
              } else {
                return ListView.builder(
                  itemCount: networks.length,
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    return Padding(
                      padding:
                          const EdgeInsets.only(left: 16, right: 16, top: 5),
                      child: Card.outlined(
                        elevation: 1,
                        child: ListTile(
                          key: ValueKey(network['SSID']),
                          title: Text(
                            '${network['SSID']}',
                            style: TextStyle(
                              fontSize: 22,
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
                              fontSize: 18,
                              color: network['SSID'] == currentSSID
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withAlpha(130)
                                  : null,
                            ),
                          ),
                          trailing: getSignalStrengthIcon(
                              network['SIGNAL']!, platform),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Center(
                                      child: Text(
                                          'Connect to ${network['SSID']}')),
                                  content: SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width * 0.5,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        children: [
                                          SpawnOrionTextField(
                                            key: wifiPasswordKey,
                                            keyboardHint: 'Enter Password',
                                            locale:
                                                Localizations.localeOf(context)
                                                    .toString(),
                                          ),
                                          OrionKbExpander(
                                              textFieldKey: wifiPasswordKey),
                                        ],
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('Close',
                                          style: TextStyle(fontSize: 20)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        connectToNetwork(
                                            network['SSID']!,
                                            wifiPasswordKey.currentState!
                                                .getCurrentText());
                                        Navigator.of(context).pop();
                                      },
                                      child: const Text('Confirm',
                                          style: TextStyle(fontSize: 20)),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              }
            }
          }
        },
      ),
      floatingActionButton: currentWifiSSID != null
          ? null
          : SizedBox(
              height: 70,
              width: 70,
              child: FloatingActionButton(
                onPressed: () async {
                  await Future.delayed(const Duration(milliseconds: 100));
                  setState(() {
                    _networksFuture = _getWifiNetworks();
                  });
                },
                child: const Icon(Icons.refresh_rounded, size: 40),
              ),
            ),
    );
  }
}
