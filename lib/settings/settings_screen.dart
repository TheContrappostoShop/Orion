/*
* Orion - Seattings Screen
* Copyright (C) 2024 TheContrappostoShop (PaulGD0, shifubrams)
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:orion/pubspec.dart';
import 'package:orion/settings/debug_screen.dart';
import 'package:orion/util/markdown_screen.dart';
import 'package:provider/provider.dart';
import 'package:about/about.dart';

import 'calibrate_screen.dart';
import 'wifi_screen.dart';
import 'about_screen.dart';

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
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 15.0),
            child: IconButton(
              icon: const Icon(
                Icons.info,
              ),
              iconSize: 35,
              onPressed: () {
                showAboutPage(
                    context: context,
                    values: {
                      'version': Pubspec.version,
                      'buildNumber': Pubspec.versionBuild.toString(),
                      'year': DateTime.now().year.toString(),
                    },
                    applicationVersion:
                        'Version {{ version }}, Build {{ buildNumber }}',
                    applicationName: 'Orion',
                    applicationLegalese:
                        'GPLv3 - Copyright © TheContrappostoShop {{ year buildType }}',
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(left: 10, right: 10),
                        child: Card(
                            child: ListTile(
                          leading: const Icon(Icons.list, size: 30),
                          title: const Text(
                            'Changelog',
                            style: TextStyle(fontSize: 24),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MarkdownScreen(
                                    filename: 'CHANGELOG.md'),
                              ),
                            );
                          },
                        )),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(10),
                        child: Card(
                          child: LicensesPageListTile(
                            title: Text(
                              'Open-Source Licenses',
                              style: TextStyle(fontSize: 24),
                            ),
                            icon: Icon(
                              Icons.favorite,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ],
                    applicationIcon: const FlutterLogo(
                      size: 100,
                    ));
              },
            ),
          ),
        ],
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
