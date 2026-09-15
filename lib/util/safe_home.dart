/*
* Orion - Safe Home Utility
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

import 'package:flutter/material.dart';
import 'package:orion/backend_service/providers/manual_provider.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:provider/provider.dart';

/// Homes the Z axis and waits until the controller confirms the axis has
/// physically stopped moving.
///
/// Klipper reports the homing command as complete as soon as it's received,
/// before the axis finishes moving.  This polls [StatusProvider]'s kinematic
/// status after the command completes so callers can safely chain further
/// movement commands without racing the axis.
Future<bool> safeHome(BuildContext context) async {
  final manual = Provider.of<ManualProvider>(context, listen: false);
  final ok = await manual.manualHome();
  if (!ok || !context.mounted) return ok;
  return safeHomePoll(context);
}

/// Polls [StatusProvider]'s kinematic status after a home command has
/// already been issued (e.g. by a backend prepare step).  Use this when
/// you only need to wait for the axis to settle, without triggering a
/// new home.
Future<bool> safeHomePoll(BuildContext context) async {
  final statusProvider =
      Provider.of<StatusProvider>(context, listen: false);
  await statusProvider.refreshKinematicStatus(maxAttempts: 10);
  return true;
}

/// Moves the Z axis to the floor and waits until the controller confirms
/// the axis has physically stopped.  Like [safeHome], this polls kinematic
/// status after the move command to cover the Klipper race.
Future<bool> safeFloor(BuildContext context) async {
  final manual = Provider.of<ManualProvider>(context, listen: false);
  final ok = await manual.moveToFloor();
  if (!ok || !context.mounted) return ok;
  return safeHomePoll(context);
}

/// Moves the Z axis to the top and waits until the controller confirms
/// the axis has physically stopped.
Future<bool> safeTop(BuildContext context) async {
  final manual = Provider.of<ManualProvider>(context, listen: false);
  final ok = await manual.moveToTop();
  if (!ok || !context.mounted) return ok;
  return safeHomePoll(context);
}
