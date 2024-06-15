/*
* Orion - Tools Screen
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
import 'package:orion/tools/exposure_screen.dart';
import 'package:orion/tools/move_z_screen.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  ToolsScreenState createState() => ToolsScreenState();
}

class ToolsScreenState extends State<ToolsScreen> {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
      ),
      body: _selectedIndex == 0
          ? const MoveZScreen()
          : _selectedIndex == 1
              ? const ExposureScreen()
              : const MoveZScreen(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.height),
            label: 'Move Z',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lightbulb),
            label: 'Exposure',
          ),
          /*BottomNavigationBarItem(
            icon: Icon(Icons.check),
            label: 'Self Test',
          ),*/
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
        unselectedItemColor: Theme.of(context).colorScheme.secondary,
      ),
    );
  }
}
