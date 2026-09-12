/*
* Orion - Nano Profile Denormalize Test
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

import 'package:test/test.dart';

import 'package:orion/backend_service/nanodlp/models/nano_profiles.dart';

void main() {
  group('normalizeForEdit', () {
    test('reads the NanoDLP profile schema', () {
      final normalized = NanoProfile.normalizeForEdit({
        'CureTime': 2.5,
        'SupportCureTime': 12.5,
        'WaitHeight': 5.5,
        'SupportLayerNumber': 4,
        'WaitAfterPrint': 1.4,
        'TopWait': 1.8,
        // 0/1 enable flag, not a burn-in layer count
        'TransitionalLayer': 0,
      });

      expect(normalized['normal_cure_time'], 2.5);
      expect(normalized['burn_in_cure_time'], 12.5);
      expect(normalized['lift_after_print'], 5.5);
      expect(normalized['burn_in_count'], 4);
      expect(normalized['wait_after_cure'], 1.4);
      expect(normalized['wait_after_life'], 1.8);
    });

    test('lift distance is WaitHeight, not the peel-detection minimum', () {
      // Shape of a real device payload: CustomValues overlays the profile and
      // carries both PdPeelMinLiftDistance and ZLiftDistance. Neither is the
      // stored lift distance.
      final normalized = NanoProfile.normalizeForEdit({
        'WaitHeight': 5.5,
        'CustomValues': {
          'PdPeelMinLiftDistance': '2',
          'ZLiftDistance': '99',
        },
      });

      expect(normalized['lift_after_print'], 5.5);
    });

    test('falls back to defaults when the payload is empty', () {
      final normalized = NanoProfile.normalizeForEdit({});

      expect(normalized['normal_cure_time'], 8.0);
      expect(normalized['burn_in_cure_time'], 10.0);
      expect(normalized['lift_after_print'], 5.0);
      expect(normalized['burn_in_count'], 3);
      expect(normalized['wait_after_cure'], 2.0);
      expect(normalized['wait_after_life'], 2.0);
    });
  });

  group('denormalizeForBackend', () {
    test('updates only supplied fields', () {
      final backend = NanoProfile.denormalizeForBackend(
        {'normal_cure_time': 2.75},
      );

      expect(backend, equals({'CureTime': 2.75}));
    });

    test('maps all known normalized fields to the NanoDLP schema', () {
      final backend = NanoProfile.denormalizeForBackend({
        'burn_in_cure_time': 12.5,
        'normal_cure_time': 2.8,
        'lift_after_print': 6.0,
        'burn_in_count': 5,
        'wait_after_cure': 1.4,
        'wait_after_life': 1.8,
      });

      expect(
        backend,
        equals({
          'SupportCureTime': 12.5,
          'CureTime': 2.8,
          'WaitHeight': 6.0,
          'SupportLayerNumber': 5,
          'WaitAfterPrint': 1.4,
          'TopWait': 1.8,
        }),
      );
    });

    test('round-trips through normalizeForEdit', () {
      final normalized = <String, dynamic>{
        'normal_cure_time': 2.8,
        'burn_in_cure_time': 12.5,
        'lift_after_print': 6.0,
        'burn_in_count': 5,
        'wait_after_cure': 1.4,
        'wait_after_life': 1.8,
      };

      final backend = NanoProfile.denormalizeForBackend(normalized);

      expect(NanoProfile.normalizeForEdit(backend), equals(normalized));
    });
  });
}
