import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wifi_flutter/wifi_flutter.dart';
import 'package:wifi_info_flutter/wifi_info_flutter.dart';

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

class WifiScreen extends StatelessWidget {
  const WifiScreen({Key? key}) : super(key: key);

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

  Future<List<CommonInterface>> getWifiNetworks(BuildContext context) async {
    // Check if the app is running on macOS
    if (Theme.of(context).platform == TargetPlatform.macOS) {
      // Return a list of 10 random placeholder networks
      List<MockWifiNetwork> mockNetworks =
          List<MockWifiNetwork>.generate(10, (int index) {
        return MockWifiNetwork(
            ssid: 'Mock Network $index', signalStrength: index * 10);
      });
      mockNetworks.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
      return mockNetworks;
    } else {
      // Fetch the list of available WiFi networks
      final Iterable<WifiNetwork> wifiNetworks = await WifiFlutter.wifiNetworks;
      final List<CommonInterface> sortedWifiNetworks =
          wifiNetworks.map((WifiNetwork wifiNetwork) {
        return wifiNetwork as CommonInterface;
      }).toList();
      sortedWifiNetworks
          .sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
      return sortedWifiNetworks;
    }
  }

  Future<String> getWifiIP(BuildContext context) async {
    // Check if the app is running on macOS
    if (Theme.of(context).platform == TargetPlatform.macOS) {
      // Return a mock IP address
      return Future.value('192.168.1.1');
    } else {
      // Fetch the IP address of the connected WiFi network
      String? wifiIP = await WifiInfo().getWifiIP();
      return wifiIP ?? 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        FutureBuilder<String>(
          future: getWifiIP(context),
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              final String wifiIP = snapshot.data ?? 'Unknown';
              return ListTile(
                title: Text(
                  'IP Address: $wifiIP',
                  style: const TextStyle(fontSize: 24),
                ),
              );
            }
          },
        ),
        Expanded(
          child: FutureBuilder<List<CommonInterface>>(
            future: getWifiNetworks(context),
            builder: (BuildContext context,
                AsyncSnapshot<List<CommonInterface>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              } else {
                final List<CommonInterface> wifiNetworks = snapshot.data ?? [];
                return ListView.builder(
                  itemCount: wifiNetworks.length,
                  itemBuilder: (BuildContext context, int index) {
                    final CommonInterface wifiNetwork = wifiNetworks[index];
                    final bool isWeakSignal = wifiNetwork.signalStrength < 20;
                    Widget listItem = ListTile(
                      leading: Icon(
                          getSignalStrengthIcon(wifiNetwork.signalStrength)),
                      title: Text('SSID: ${wifiNetwork.ssid}',
                          style: TextStyle(
                              color: isWeakSignal
                                  ? const Color.fromARGB(255, 100, 100, 100)
                                  : null)),
                      subtitle: Text(
                        'Signal Strength: ${wifiNetwork.signalStrength}',
                        style: TextStyle(
                            color: isWeakSignal
                                ? const Color.fromARGB(255, 100, 100, 100)
                                : null),
                      ),
                    );

                    if (isWeakSignal) {
                      return IgnorePointer(
                        child: listItem,
                      );
                    } else {
                      return InkWell(
                        onTap: () {
                          if (kDebugMode) {
                            print('Tapped ${wifiNetwork.ssid}');
                          }
                        },
                        child: listItem,
                      );
                    }
                  },
                );
              }
            },
          ),
        ),
      ],
    );
  }
}
