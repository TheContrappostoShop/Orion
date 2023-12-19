import 'package:flutter/material.dart';

import 'calibrate_screen.dart';
import 'wifi_screen.dart';
import 'about_screen.dart';

/// The settings screen
class SettingsScreen extends StatefulWidget {
  /// Constructs a [SettingsScreen]
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _selectedIndex == 0
          ? const CalibrateScreen()
          : _selectedIndex == 1
              ?  WifiScreen()
              : const AboutScreen(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Calibrate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.network_wifi),
            label: 'WiFi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info),
            label: 'About',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
        unselectedItemColor: Theme.of(context)
            .colorScheme
            .secondary, // set the inactive icon color to red
      ),
    );
  }
}
