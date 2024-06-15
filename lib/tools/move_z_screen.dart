/*
* Orion - Move Z Screen
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

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/util/error_handling/error_dialog.dart';

class MoveZScreen extends StatefulWidget {
  const MoveZScreen({super.key});

  @override
  MoveZScreenState createState() => MoveZScreenState();
}

class MoveZScreenState extends State<MoveZScreen> {
  final _logger = Logger('MoveZScreen');
  final ApiService _api = ApiService();

  double maxZ = 0.0;
  double step = 0.1;
  bool _apiErrorState = false;

  Future<void> moveZ(double distance) async {
    try {
      _logger.info('Moving Z by $distance');
      _api.manualCommand('G91');
      await Future.delayed(const Duration(milliseconds: 200));
      _api.move(distance);
    } catch (e) {
      _logger.severe('Failed to move Z: $e');
    }
  }

  void getMaxZ() async {
    try {
      Map<String, dynamic> config = await _api.getConfig();
      setState(() {
        maxZ = config['printer']['max_z'];
      });
    } catch (e) {
      setState(() {
        _apiErrorState = true;
      });
      if (mounted) showErrorDialog(context, 'PINK-CARROT');
      _logger.severe('Failed to get max Z: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    getMaxZ();
  }

  @override
  Widget build(BuildContext context) {
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
              return const Size(double.infinity, double.infinity);
            },
          ),
        ),
      ),
    );

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      _apiErrorState ? null : () => moveZ(step),
                                  style: theme.elevatedButtonTheme.style,
                                  child:
                                      const Icon(Icons.arrow_upward, size: 50),
                                ),
                              ),
                              const SizedBox(height: 30),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _apiErrorState
                                      ? null
                                      : () => moveZ(-step),
                                  style: theme.elevatedButtonTheme.style,
                                  child: const Icon(Icons.arrow_downward,
                                      size: 50),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 30),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [0.1, 1.0, 10.0, 50.0].expand((value) {
                              return [
                                Flexible(
                                  child: ChoiceChip(
                                    label: SizedBox(
                                      width: double.infinity,
                                      child: Text(
                                        '$value mm',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize:
                                              22, // Adjust the font size here.
                                        ),
                                      ),
                                    ),
                                    selected: step == value,
                                    onSelected: _apiErrorState
                                        ? null
                                        : (selected) {
                                            if (selected) {
                                              setState(() {
                                                step = value;
                                              });
                                            }
                                          },
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ];
                            }).toList()
                              ..removeLast(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 30),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _apiErrorState
                          ? null
                          : () async {
                              _logger.info('Moving to ZMAX');
                              _api.manualCommand('G90');
                              await Future.delayed(
                                  const Duration(milliseconds: 200));
                              _api.manualCommand('G1 Z$maxZ F3000');
                            },
                      style: theme.elevatedButtonTheme.style,
                      child: const Text(
                        'Move to Top',
                        style: TextStyle(
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _apiErrorState
                          ? null
                          : () {
                              _logger.info('Moving to ZMIN');
                              _api.manualHome();
                            },
                      style: theme.elevatedButtonTheme.style,
                      child: const Text(
                        'Move to Home',
                        style: TextStyle(
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _apiErrorState
                          ? null
                          : () {
                              _logger.severe('EMERGENCY STOP');
                              _api.manualCommand('M112');
                            },
                      style: theme.elevatedButtonTheme.style,
                      child: Text(
                        'Emergency Stop',
                        style: TextStyle(
                          fontSize: 24,
                          color: _apiErrorState
                              ? null
                              : Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
