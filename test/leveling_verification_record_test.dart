/*
* Orion - Leveling Verification Record Test
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/tools/athena/leveling_log_entry.dart';
import 'package:orion/tools/athena/leveling_verification_record.dart';

/// One session, two checks: the first failed, the second passed.  Layout is
/// the block `LevelingLogService.logCornerCheck` writes.
const String _logWithFailedThenPassed = '''
======================================================================
LEVELING SESSION  sess-A
Timestamp          2026-09-15 10:11:12 (local)
Variant            pro
Screen Type        tempered_glass
Recheck            #0 (initial)
Result             FAILED \u2014 total deviation 0.210 mm (limit 0.100 mm)
======================================================================
Corner Measurements:
  Pos  Corner        Z (mm)      1st Peak (gf)   2nd Peak (gf)   1st Over.   2nd Over.
  FL   Front Left    0.60        -800.00        -810.00       0.10        0.20
  FR   Front Right   0.62        -820.00        -830.00       0.10        0.20
  BR   Back Right    0.80        -900.00        -910.00       0.10        0.20
  BL   Back Left     0.78        -880.00        -890.00       0.10        0.20
----------------------------------------------------------------------
Front Avg Z: 0.610 mm    Back Avg Z: 0.790 mm    Gap: 0.180 mm (back lower)
Min Z: 0.600 mm    Max Z: 0.800 mm    Range: 0.200 mm
Coupling Est: -0.000200 mm/gf  (\u22485000 gf needed per 1 mm of gap movement)
Probe Config: (not reported by backend)
======================================================================

======================================================================
LEVELING SESSION  sess-A
Timestamp          2026-09-15 10:24:30 (local)
Variant            pro
Screen Type        tempered_glass
Recheck            #1
Result             PASSED \u2014 total deviation 0.042 mm (limit 0.100 mm)
======================================================================
Corner Measurements:
  Pos  Corner        Z (mm)      1st Peak (gf)   2nd Peak (gf)   1st Over.   2nd Over.
  FL   Front Left    0.79        -820.00        -830.00       0.10        0.20
  FR   Front Right   0.81        -830.00        -840.00       0.10        0.20
  BR   Back Right    0.80        -900.00        -910.00       0.10        0.20
  BL   Back Left     0.78        -880.00        -890.00       0.10        0.20
----------------------------------------------------------------------
Front Avg Z: 0.800 mm    Back Avg Z: 0.790 mm    Gap: 0.010 mm (back lower)
Min Z: 0.780 mm    Max Z: 0.810 mm    Range: 0.030 mm
Coupling Est: -0.000180 mm/gf  (\u22485556 gf needed per 1 mm of gap movement)
  Command:   -60 gf at gap 0.180 mm (BACK screw)
  Gauge:     target -880 gf, user stopped at -870 gf (achieved -50 of -60 gf)
  Measured:  gap moved -0.170 mm \u2192 sample -0.000283 mm/gf
  [ACCEPTED]
Probe Configuration:
  1st Stage Speed:       -1000
  2nd Stage Speed:       -500
======================================================================

''';

void main() {
  group('LevelingVerificationRecord snapshot', () {
    test('round-trips through JSON without losing the rendered values', () {
      final record = LevelingVerificationRecord(
        timestamp: '2026-09-15T10:24:30.000Z',
        variant: 'pro',
        deviationMm: 0.042,
        cornerZs: const {'FL': 0.79, 'FR': 0.81, 'BR': 0.80, 'BL': 0.78},
        totalChecks: 2,
      );

      final decoded = LevelingVerificationRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, isNotNull);
      expect(decoded!.timestamp, '2026-09-15T10:24:30.000Z');
      expect(decoded.variant, 'pro');
      expect(decoded.deviationMm, closeTo(0.042, 1e-9));
      expect(decoded.cornerZs, record.cornerZs);
      expect(decoded.totalChecks, 2);
      expect(decoded.frontAvgZ, closeTo(0.80, 1e-9));
      expect(decoded.backAvgZ, closeTo(0.79, 1e-9));
      expect(decoded.rangeMm, closeTo(0.03, 1e-9));
      expect(decoded.frontBackGapMm, closeTo(0.01, 1e-9));
    });

    test('rejects a snapshot missing the measured values', () {
      expect(LevelingVerificationRecord.fromJson(const {}), isNull);
      expect(
        LevelingVerificationRecord.fromJson(
            const {'timestamp': 't', 'variant': 'pro'}),
        isNull,
      );
      expect(
        LevelingVerificationRecord.fromJson(
            const {'timestamp': 't', 'variant': 'pro', 'deviation_mm': 'x'}),
        isNull,
      );
    });

    test('keeps only measured corners and counts the session checks', () {
      final entry = LevelingLogEntry(
        sessionId: 'sess-A',
        timestamp: '2026-09-15T10:24:30.000Z',
        variant: 'pro',
        recheckNumber: 2,
        corners: const {
          'FL': CornerLogData(finalZ: 0.79),
          'FR': CornerLogData(finalZ: 0.81),
          'BR': CornerLogData(),
          'BL': CornerLogData(),
        },
        totalDeviationMm: 0.042,
        passed: true,
      );

      final record = LevelingVerificationRecord.fromLogEntry(entry);

      expect(record.cornerZs, const {'FL': 0.79, 'FR': 0.81});
      expect(record.totalChecks, 3, reason: 'initial check + two rechecks');
      expect(record.deviationMm, closeTo(0.042, 1e-9));
      // Only the front plane was measured — no back average, so no gap.
      expect(record.frontAvgZ, closeTo(0.80, 1e-9));
      expect(record.backAvgZ, isNull);
      expect(record.frontBackGapMm, isNull);
    });
  });

  group('LevelingVerificationRecord from the log', () {
    test('reads the last passed session and its measurements', () {
      final record =
          LevelingVerificationRecord.fromLogText(_logWithFailedThenPassed);

      expect(record, isNotNull);
      expect(record!.timestamp, '2026-09-15 10:24:30');
      expect(record.variant, 'pro');
      expect(record.deviationMm, closeTo(0.042, 1e-9));
      expect(record.totalChecks, 2, reason: 'two checks logged for sess-A');
      expect(record.cornerZs, const {
        'FL': 0.79,
        'FR': 0.81,
        'BR': 0.80,
        'BL': 0.78,
      });
      expect(record.frontAvgZ, closeTo(0.80, 1e-9));
      expect(record.backAvgZ, closeTo(0.79, 1e-9));
      expect(record.rangeMm, closeTo(0.03, 1e-9));
      expect(record.frontBackGapMm, closeTo(0.01, 1e-9));
    });

    test('returns nothing when no check has passed', () {
      final firstSession = _logWithFailedThenPassed.indexOf('LEVELING SESSION');
      final secondSession = _logWithFailedThenPassed.indexOf(
          'LEVELING SESSION', firstSession + 1);
      final failedOnly =
          _logWithFailedThenPassed.substring(0, secondSession);

      expect(LevelingVerificationRecord.fromLogText(failedOnly), isNull);
      expect(LevelingVerificationRecord.fromLogText(''), isNull);
    });
  });
}
