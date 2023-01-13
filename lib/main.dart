import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';

void main() => runApp(DevicePreview(
      enabled: !kReleaseMode,
      builder: (context) => const Orion(),
    ));

class Orion extends StatelessWidget {
  const Orion({super.key});

  static const appTitle = 'Orion MSLA Control';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: appTitle,
        useInheritedMediaQuery: true,
        locale: DevicePreview.locale(context),
        builder: DevicePreview.appBuilder,
        theme: ThemeData(
          brightness: Brightness.light,
          colorSchemeSeed: const Color(0xff6750a4),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xff6750a4),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: Scaffold(
          appBar: AppBar(
            title: const Text(appTitle),
          ),
          body: const Navigation(),
        ));
  }
}

class Navigation extends StatefulWidget {
  const Navigation({super.key});

  @override
  State<Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<Navigation> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        bottomNavigationBar: NavigationBar(
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          onDestinationSelected: (int index) {
            setState(() {
              currentPageIndex = index;
            });
          },
          selectedIndex: currentPageIndex,
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder),
              label: 'Files',
            ),
            NavigationDestination(
              icon: Icon(Icons.code),
              label: 'Console',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings),
              label: 'Settings',
            )
          ],
        ),
        body: <Widget>[
          Container(
            alignment: Alignment.center,
            child: const Text('Page 1'),
          ),
          Container(
            alignment: Alignment.center,
            child: const Text('Page 2'),
          ),
          Container(
            alignment: Alignment.center,
            child: const Text('Page 3'),
          ),
          Container(
            alignment: Alignment.center,
            child: const Text('Page 4'),
          ),
        ][currentPageIndex]);
  }
}
