/*
* Orion - Edit Resin Screen Test
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_i18n/loaders/decoders/json_decode_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/backend_service/nanodlp/models/nano_profiles.dart';
import 'package:orion/backend_service/providers/analytics_provider.dart';
import 'package:orion/backend_service/providers/resins_provider.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/materials/edit_resin_screen.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/util/providers/wifi_provider.dart';
import 'package:orion/widgets/orion_app_bar.dart';

import '../fakes/fake_odyssey_client.dart';

/// Backend double covering what the edit screen touches: the profile list it
/// is opened from, one profile to edit, and the two write paths.
class _FakeResinsBackend extends FakeBackendClient {
  final List<Map<String, dynamic>> profiles = [
    {
      'ProfileID': 1,
      'Title': 'Locked Resin',
      'ManufacturerLock': true,
      'CureTime': 2.0,
      'SupportCureTime': 20.0,
      'WaitHeight': 5.0,
      'SupportLayerNumber': 4,
      'WaitAfterPrint': 0.0,
      'TopWait': 0.0,
    },
    {
      'ProfileID': 5,
      'Title': 'User Resin',
      'ManufacturerLock': false,
      'CureTime': 7.9,
      'SupportCureTime': 18.1,
      'WaitHeight': 8.9,
      'SupportLayerNumber': 12,
      'WaitAfterPrint': 5.5,
      'TopWait': 9.7,
    },
  ];

  int saveCalls = 0;
  int cloneCalls = 0;
  Map<String, dynamic>? lastCloneFields;

  @override
  Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory) async {
    if (location.toLowerCase() != 'resins') {
      return {'files': <Map<String, dynamic>>[]};
    }
    return {
      'files':
          NanoProfile.parseFromJson(profiles).map((p) => p.toMap()).toList(),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getCalibrationModels() async => [];

  @override
  Future<int?> getDefaultProfileId() async => 5;

  @override
  Future<Map<String, dynamic>> getProfileJson(int id) async {
    for (final profile in profiles) {
      if ('${profile['ProfileID']}' == '$id') {
        return Map<String, dynamic>.from(profile);
      }
    }
    return {};
  }

  @override
  Future<void> saveResinSettings(int profileId, ResinSettings settings) async {
    saveCalls++;
  }

  @override
  Future<Map<String, dynamic>> cloneProfile(
      int sourceId, Map<String, dynamic> fields) async {
    cloneCalls++;
    lastCloneFields = Map<String, dynamic>.from(fields);
    final clone = Map<String, dynamic>.from(profiles.first)
      ..['ProfileID'] = 100
      ..['Title'] = fields['Title']
      ..['ManufacturerLock'] = false;
    profiles.add(clone);
    return clone;
  }

  @override
  Future<Map<String, dynamic>> getStatus() async => {};

  @override
  Stream<Map<String, dynamic>> getStatusStream() => const Stream.empty();
}

class _Harness {
  _Harness(this._status, this._analytics, this._wifi);

  final StatusProvider _status;
  final AnalyticsProvider _analytics;
  final WiFiProvider _wifi;

  /// The app bar's status widget polls, so the notifiers have to be disposed
  /// inside the test body (pending timers are checked before tear-downs), and
  /// their in-flight polling delays have to drain afterwards.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    _status.dispose();
    _analytics.dispose();
    _wifi.dispose();
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<_Harness> _pumpEditScreen(
  WidgetTester tester, {
  required ResinProfile resin,
  required Future<void> Function() onSaved,
}) async {
  final backend = BackendService(); // shared instance, faked per test
  final status = StatusProvider(client: backend);
  final analytics = AnalyticsProvider(client: backend);
  final wifi = WiFiProvider(startPolling: false);

  final delegate = FlutterI18nDelegate(
    translationLoader: FileTranslationLoader(
      useCountryCode: false,
      fallbackFile: 'en',
      basePath: 'assets/i18n',
      decodeStrategies: [JsonDecodeStrategy()],
    ),
  );
  await delegate.load(const Locale('en'));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StatusProvider>.value(value: status),
        ChangeNotifierProvider<AnalyticsProvider>.value(value: analytics),
        ChangeNotifierProvider<WiFiProvider>.value(value: wifi),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [delegate],
        supportedLocales: const [Locale('en')],
        home: EditResinScreen(resin: resin, onSaved: onSaved),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(status, analytics, wifi);
}

void main() {
  testWidgets('refreshing the provider surfaces a newly cloned profile',
      (tester) async {
    final backend = _FakeResinsBackend();
    final provider = ResinsProvider(service: BackendService(delegate: backend));
    // Drain the post-frame refresh the constructor schedules, so the explicit
    // refresh calls below and the final dispose are deterministic.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await provider.refresh();
    expect(provider.resins.map((r) => r.name), contains('Locked Resin'));

    final clone = await backend.cloneProfile(1, {'Title': 'My Copy'});
    expect(clone['ProfileID'], 100);

    await provider.refresh();
    final names = provider.resins.map((r) => r.name).toList();
    expect(names, contains('My Copy'));
    expect(provider.userResins.map((r) => r.name), contains('My Copy'));
    expect(
      provider.resins.firstWhere((r) => r.name == 'My Copy').locked,
      isFalse,
    );

    provider.dispose();
  });

  testWidgets('saving an editable profile writes it and refreshes the owner',
      (tester) async {
    final backend = _FakeResinsBackend();
    BackendService.debugSetSharedDelegate(backend);
    var refreshes = 0;

    final harness = await _pumpEditScreen(
      tester,
      resin: ResinProfile('User Resin', meta: const {'ProfileID': 5}),
      onSaved: () async => refreshes++,
    );
    try {
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(backend.saveCalls, 1);
      expect(backend.cloneCalls, 0);
      // The materials list must be refreshed as part of the save, otherwise
      // the user has to leave the page to see the change.
      expect(refreshes, 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('saving a locked profile clones it and refreshes the owner',
      (tester) async {
    final backend = _FakeResinsBackend();
    BackendService.debugSetSharedDelegate(backend);
    var refreshes = 0;

    final harness = await _pumpEditScreen(
      tester,
      resin: ResinProfile(
        'Locked Resin',
        meta: const {'ProfileID': 1, 'ManufacturerLock': true},
        locked: true,
      ),
      onSaved: () async => refreshes++,
    );
    try {
      await tester.tap(find.text('Save'));
      // The clone dialog hosts the on-screen keyboard, which animates
      // continuously, so settle with bounded pumps instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The clone name dialog opens with the source profile's name plus
      // " copy" pre-filled (behind a zero-width prefix the field adds).
      expect(find.text('Name Profile'), findsOneWidget);
      expect(find.textContaining('Locked Resin copy'), findsWidgets);
      expect(find.text('Save'), findsNWidgets(2));
      await tester.tap(find.text('Save').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(backend.cloneCalls, 1);
      expect(backend.saveCalls, 0);
      expect(backend.lastCloneFields?['Title'], 'Locked Resin copy');
      // The clone is a brand new profile, so the list has to be re-read.
      expect(refreshes, 1);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('content sits on the shared edge inset, not a looser one',
      (tester) async {
    final backend = _FakeResinsBackend();
    BackendService.debugSetSharedDelegate(backend);

    final harness = await _pumpEditScreen(
      tester,
      resin: ResinProfile('User Resin', meta: const {'ProfileID': 5}),
      onSaved: () async {},
    );
    try {
      // The first row holds two cards; the left one shows the leading inset and
      // the right one the trailing, which is why this reads both.
      final cards = find.byType(GlassCard);
      final left = tester.getRect(cards.first);
      final right = tester.getRect(cards.at(1));
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      // GlassCard applies its 4px margin inside this box, so the box edge is
      // the settings inset and the painted card lands on the baseline of 20.
      // Leaving the shell at screenHorizontal puts the page 4px wider than
      // every other Orion screen instead.
      expect(left.left, OrionSpacing.settingsScreenHorizontal);
      expect(right.right, width - OrionSpacing.settingsScreenHorizontal);

      // Same story at the top: under OrionAppBar the tight offset is the one
      // that keeps the gap to the bar in line with the rest of the app.
      final bar = tester.getRect(find.byType(OrionAppBar));
      expect(
        left.top - bar.bottom,
        OrionSpacing.settingsScreenPaddingTightTop.top,
      );
    } finally {
      await harness.dispose(tester);
    }
  });
}
