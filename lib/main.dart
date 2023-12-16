import 'home/home_screen.dart';
import 'status/status_screen.dart';
import 'files/files_screen.dart';
import 'settings/settings_screen.dart';
import 'settings/calibrate_screen.dart';
import 'settings/wifi_screen.dart';
import 'settings/about_screen.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_size/window_size.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setWindowMinSize(const Size(800, 480));
  setWindowMaxSize(const Size(800, 480));
  runApp(const Orion());
}

/// The route configuration.
final GoRouter _router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'files',
          builder: (BuildContext context, GoRouterState state) {
            return const FilesScreen();
          },
        ),
        GoRoute(
          path: 'settings',
          builder: (BuildContext context, GoRouterState state) {
            return const SettingsScreen();
          },
          routes: <RouteBase>[
            GoRoute(
              path: 'calibrate',
              builder: (BuildContext context, GoRouterState state) {
                return const CalibrateScreen();
              },
            ),
            GoRoute(
              path: 'wifi',
              builder: (BuildContext context, GoRouterState state) {
                return const WifiScreen();
              },
            ),
            GoRoute(
              path: 'about',
              builder: (BuildContext context, GoRouterState state) {
                return const AboutScreen();
              },
            ),
          ],
        ),
        GoRoute(
          path: 'status',
          builder: (BuildContext context, GoRouterState state) {
            return const StatusScreen();
          },
        ),
      ],
    ),
  ],
);

/// The main app.
class Orion extends StatelessWidget {
  /// Constructs a [Orion]
  const Orion({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 800,
      height: 480,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xff6750a4),
            useMaterial3: true),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xff6750a4),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
      ),
    );
  }
}
