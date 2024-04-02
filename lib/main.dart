import 'package:flutter/foundation.dart';

import 'package:orion/home/home_screen.dart';
import 'package:orion/status/status_screen.dart';
import 'package:orion/files/files_screen.dart';
import 'package:orion/settings/settings_screen.dart';
import 'package:orion/settings/calibrate_screen.dart';
import 'package:orion/settings/wifi_screen.dart';
import 'package:orion/settings/about_screen.dart';
import 'package:orion/themes/themes.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_size/window_size.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Orion());
}

void macDebug() {
  if (kDebugMode) {
    setWindowTitle('Orion Debug - Prometheus mSLA');
    setWindowMinSize(const Size(480, 480));
    setWindowMaxSize(const Size(800, 800));
  }
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

class Orion extends StatefulWidget {
  const Orion({super.key});

  @override
  OrionState createState() => OrionState();
}

class OrionState extends State<Orion> {
  ThemeMode _themeMode = ThemeMode.system;

  void changeThemeMode(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.macOS) {
      macDebug();
    }
    return ScreenUtilInit(
      designSize: const Size(800, 480),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return Provider<Function>.value(
          value: changeThemeMode,
          child: SizedBox(
            child: MaterialApp.router(
              debugShowCheckedModeBanner: true,
              routerConfig: _router,
              theme: themeLight,
              darkTheme: themeDark,
              themeMode: _themeMode,
            ),
          ),
        );
      },
    );
  }
}
