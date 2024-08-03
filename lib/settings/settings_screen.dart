/*
* Orion - Settings Screen
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:about/about.dart';

import 'package:orion/pubspec.dart';
import 'package:orion/settings/about_screen.dart';
import 'package:orion/settings/debug_screen.dart';
import 'package:orion/settings/general_screen.dart';
import 'package:orion/settings/update_screen.dart';
import 'package:orion/settings/wifi_screen.dart';
import 'package:orion/util/markdown_screen.dart';

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
            padding: const EdgeInsets.only(right: 16.0),
            child: _selectedIndex == 2
                ? IconButton(
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
                            'commit': Pubspec.versionFull
                                        .toString()
                                        .split('+')[1] ==
                                    'SELFCOMPILED'
                                ? 'Local Build'
                                : 'Commit ${Pubspec.versionFull.toString().split('+')[1]}',
                            'year': DateTime.now().year.toString(),
                          },
                          applicationVersion:
                              'Version {{ version }} - {{ commit }}',
                          applicationName: 'Orion',
                          applicationLegalese:
                              'GPLv3 - Copyright © TheContrappostoShop {{ year }}',
                          children: <Widget>[
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 10, right: 10),
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
                                      builder: (context) =>
                                          const MarkdownScreen(
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
                  )
                : null,
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? const GeneralCfgScreen()
          : _selectedIndex == 1
              ? const WifiScreen()
              : _selectedIndex == 2
                  ? const AboutScreen()
                  : _selectedIndex == 3
                      ? const UpdateScreen()
                      : DebugScreen(changeThemeMode: changeThemeMode),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'General',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.network_wifi),
            label: 'WiFi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info),
            label: 'About',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.update), label: 'Updates'),
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
