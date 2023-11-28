import 'package:flutter/material.dart';
import 'package:wifi_info_flutter/wifi_info_flutter.dart';

class WifiScreen extends StatelessWidget {
  const WifiScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: WifiInfo().getWifiName(),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          final String wifiName = snapshot.data ?? 'Unknown';
          return ListTile(
            title: Text(
              'SSID: $wifiName',
              style: const TextStyle(fontSize: 24),
            ),
          );
        }
      },
    );
  }
}
