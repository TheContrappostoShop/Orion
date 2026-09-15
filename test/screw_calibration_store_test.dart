/*
* Orion - Screw Calibration Store Tests
* Copyright (C) 2026 Open Resin Alliance
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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/tools/athena/screw_calibration_store.dart';
import 'package:orion/tools/athena/screw_controller.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ScrewCalibrationStore', () {
    late String tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('screw_cal_test_').path;
    });

    tearDown(() {
      Directory(tmpDir).deleteSync(recursive: true);
    });

    test('load returns empty map when no file exists', () async {
      final store = ScrewCalibrationStore(directory: tmpDir);
      expect(await store.load(), isEmpty);
    });

    test('save then load round-trips correctly', () async {
      final store = ScrewCalibrationStore(directory: tmpDir);
      await store.save('back', -1.66e-4);
      await store.save('fl', -2.15e-4);

      final loaded = await store.load();
      expect(loaded['back'], closeTo(-1.66e-4, 1e-9));
      expect(loaded['fl'], closeTo(-2.15e-4, 1e-9));
    });

    test('ignores physically-impossible positive values', () async {
      // Write a broken file — positive coupling is a measurement
      // artifact that must never seed a controller.
      final jsonFile = File(path.join(tmpDir, 'orion_leveling_calibration.json'));
      await jsonFile.writeAsString(
          '{"couplings":{"back":5e-4,"fr":-2.0e-4}}');
      final store = ScrewCalibrationStore(directory: tmpDir);
      final loaded = await store.load();
      expect(loaded['back'], isNull); // rejected
      expect(loaded['fr'], closeTo(-2.0e-4, 1e-9)); // still loaded
    });

    test('save overwrites an existing key', () async {
      final store = ScrewCalibrationStore(directory: tmpDir);
      await store.save('back', -1.66e-4);
      await store.save('back', -1.85e-4); // second session, same screw
      final loaded = await store.load();
      expect(loaded['back'], closeTo(-1.85e-4, 1e-9));
    });

    test('adoptSeed from stored calibration matches load value', () {
      final ctrl = ScrewController();
      ctrl.adoptSeed(-1.66e-4);
      expect(ctrl.coupling, closeTo(-1.66e-4, 1e-9));
      expect(ctrl.hasMeasuredSample, isFalse); // adopted, not measured
      // A command seeded at the real coupling is sized correctly:
      final cmd = ctrl.command(zGapMm: 0.2);
      expect(cmd.forceDeltaGf,
          closeTo(0.7 * 0.2 / -1.66e-4, 1.0));
    });
  });
}
