/*
* Orion - UV Safety Timer Test
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

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/tools/athena/uv_safety_timer.dart';

void main() {
  test('fires onExpire after the 30 second window', () {
    fakeAsync((async) {
      var expired = false;
      final timer = UvSafetyTimer(() => expired = true);

      timer.arm();

      async.elapse(UvSafetyTimer.timeout - const Duration(seconds: 1));
      expect(expired, isFalse);

      async.elapse(const Duration(seconds: 1));
      expect(expired, isTrue);
    });
  });

  test('disarm cancels the pending expiry', () {
    fakeAsync((async) {
      var expired = false;
      final timer = UvSafetyTimer(() => expired = true);

      timer.arm();
      timer.disarm();

      async.elapse(UvSafetyTimer.timeout + const Duration(seconds: 1));
      expect(expired, isFalse);
    });
  });

  test('re-arming restarts the window', () {
    fakeAsync((async) {
      var expired = false;
      final timer = UvSafetyTimer(() => expired = true);

      timer.arm();
      async.elapse(UvSafetyTimer.timeout - const Duration(seconds: 1));

      // A new screen is shown — the window starts over.
      timer.arm();
      async.elapse(UvSafetyTimer.timeout - const Duration(seconds: 1));
      expect(expired, isFalse);

      async.elapse(const Duration(seconds: 1));
      expect(expired, isTrue);
    });
  });
}
