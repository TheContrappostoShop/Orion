import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orion/settings/debug_screen.dart';
import 'package:provider/provider.dart';

import 'calibrate_screen.dart';
import 'wifi_screen.dart';
import 'about_screen.dart';

/// The settings screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final changeThemeMode =
        Provider.of<Function>(context) as void Function(ThemeMode);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _selectedIndex == 0
          ? const CalibrateScreen()
          : _selectedIndex == 1
              ? const WifiScreen()
              : _selectedIndex == 2
                  ? const AboutScreen()
                  : DebugScreen(changeThemeMode: changeThemeMode),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
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
          if (kDebugMode)
            BottomNavigationBarItem(
              icon: Icon(Icons.bug_report),
              label: 'Debug',
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
