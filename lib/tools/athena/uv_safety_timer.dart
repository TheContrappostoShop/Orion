/*
* Orion - UV Safety Timer
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

import 'dart:async';

/// One-shot safety timeout for the projector's UV special screens.
///
/// Showing a special screen projects UV onto the build plate, which is
/// hazardous while hands may be near it. [arm] starts a [timeout] window
/// after which [onExpire] fires (sending the uvled_off command), even if
/// the wizard never proceeded to a step that turns the screen off itself.
/// Re-arming restarts the window; [disarm] cancels it.
class UvSafetyTimer {
  UvSafetyTimer(this.onExpire);

  /// Called when an armed window elapses.
  final void Function() onExpire;

  static const timeout = Duration(seconds: 30);

  Timer? _timer;

  /// Starts the safety window, restarting it if one is already running.
  void arm() {
    _timer?.cancel();
    _timer = Timer(timeout, () {
      _timer = null;
      onExpire();
    });
  }

  /// Cancels any pending window.
  void disarm() {
    _timer?.cancel();
    _timer = null;
  }
}
