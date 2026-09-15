/*
* Orion - Nano Profile Manufacturer Lock Test
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

NanoProfile profileOf(Map<String, dynamic> entry) {
  final profiles = NanoProfile.parseFromJson([entry]);
  expect(profiles, hasLength(1));
  return profiles.single;
}

void main() {
  test('ManufacturerLock true marks the profile locked', () {
    final profile = profileOf({
      'ResinID': 0,
      'ProfileID': 1,
      'Title': 'General Purpose / Standard Resin',
      'ManufacturerLock': true,
    });

    expect(profile.locked, isTrue);
    expect(profile.toMap()['locked'], isTrue);
  });

  test('ManufacturerLock false leaves the profile unlocked', () {
    final profile = profileOf({
      'ResinID': 2,
      'ProfileID': 3,
      'Title': 'My Custom Resin',
      'ManufacturerLock': false,
    });

    expect(profile.locked, isFalse);
  });

  test('ManufacturerLock accepts numeric and string forms', () {
    for (final lockedValue in [1, 'true', '1']) {
      final profile = profileOf({
        'ProfileID': 4,
        'Title': 'Vendor Resin',
        'ManufacturerLock': lockedValue,
      });
      expect(profile.locked, isTrue, reason: '$lockedValue');
    }

    for (final unlockedValue in [0, 'false', '0']) {
      final profile = profileOf({
        'ProfileID': 5,
        'Title': 'User Resin',
        'ManufacturerLock': unlockedValue,
      });
      expect(profile.locked, isFalse, reason: '$unlockedValue');
    }
  });

  test('explicit locked flag still takes precedence', () {
    final profile = profileOf({
      'ProfileID': 6,
      'Title': 'Vendor Resin',
      'locked': true,
      'ManufacturerLock': false,
    });

    expect(profile.locked, isTrue);
  });

  test('bracket-prefix heuristic still applies without lock signals', () {
    final locked = profileOf({
      'ProfileID': 7,
      'Title': '[AFP] Vendor Resin',
    });
    expect(locked.locked, isTrue);

    final unlocked = profileOf({
      'ProfileID': 8,
      'Title': 'General Purpose / Standard Resin',
    });
    expect(unlocked.locked, isFalse);
  });
}
