/*
* Orion - Home Screen
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/main.dart';
import 'package:orion/util/orion_config.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final OrionConfig _config = OrionConfig();
  bool isRemote = false;

  @override
  Widget build(BuildContext context) {
    Size homeBtnSize = const Size(double.infinity, double.infinity);

    final theme = Theme.of(context).copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: MaterialStateProperty.resolveWith<OutlinedBorder?>(
            (Set<MaterialState> states) {
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              );
            },
          ),
          minimumSize: MaterialStateProperty.resolveWith<Size?>(
            (Set<MaterialState> states) {
              return homeBtnSize;
            },
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Prometheus mSLA',
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        leadingWidth: 120,
        leading: const Center(
          child: Padding(
            padding: EdgeInsets.only(left: 15),
            child: LiveClock(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 25),
            child: InkWell(
              onTap: () {
                isRemote =
                    _config.getFlag('useCustomUrl', category: 'advanced');
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return Dialog(
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width *
                            0.5, // 80% of screen width
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Power Options ${isRemote ? '(Remote)' : '(Local)'}',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 20, right: 20),
                              child: SizedBox(
                                height: 65,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    _api.manualCommand('FIRMWARE_RESTART');
                                  },
                                  child: const Text(
                                    'Firmware Restart',
                                    style: TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(
                                height:
                                    20), // Add some spacing between the buttons
                            if (!isRemote)
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 20, right: 20),
                                child: SizedBox(
                                  height: 65,
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Process.run('sudo', ['reboot', 'now']);
                                    },
                                    child: const Text(
                                      'Reboot System',
                                      style: TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                              ),
                            if (!isRemote) const SizedBox(height: 20),
                            if (!isRemote)
                              Padding(
                                padding:
                                    const EdgeInsets.only(left: 20, right: 20),
                                child: SizedBox(
                                  height: 65,
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Process.run('sudo', ['shutdown', 'now']);
                                    },
                                    child: const Text(
                                      'Shutdown System',
                                      style: TextStyle(fontSize: 24),
                                    ),
                                  ),
                                ),
                              ),
                            if (!isRemote) const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              child: const Icon(Icons.power_settings_new_outlined, size: 38),
            ),
          ),
        ],
      ),
      body: Center(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(height: 5),
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 20),
                      Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style,
                          onPressed: () => context.go('/gridfiles'),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.print_outlined, size: 52),
                              Text('Print', style: TextStyle(fontSize: 28)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 20),
                      Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style,
                          onPressed: () => context.go('/tools'),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.handyman_outlined, size: 52),
                              Text('Tools', style: TextStyle(fontSize: 28)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style,
                          onPressed: () => context.go('/settings'),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.settings_outlined, size: 52),
                              Text('Settings', style: TextStyle(fontSize: 28)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A live clock widget
class LiveClock extends StatefulWidget {
  const LiveClock({super.key});

  @override
  LiveClockState createState() => LiveClockState();
}

class LiveClockState extends State<LiveClock> {
  late Timer _timer;
  late DateTime _dateTime;

  @override
  void initState() {
    super.initState();
    _dateTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      setState(() {
        _dateTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
        '${_dateTime.hour.toString().padLeft(2, '0')}:${_dateTime.minute.toString().padLeft(2, '0')}',
        style: const TextStyle(fontSize: 28));
  }
}
