/*
* Orion - Screw Calibration Store
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
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:orion/util/orion_config.dart';
import 'package:path/path.dart' as path;

/// Persists the per-screw force→Z coupling estimates across leveling
/// sessions in `orion_leveling_calibration.json`, next to `orion.cfg`.
///
/// Coupling is a physical property of the plate's lever geometry — it
/// does not change between sessions (field data: the same screws
/// measured within ±15% across sessions a day apart).  Persisting the
/// estimates means every session starts calibrated instead of
/// relearning from the generic seed, whose 3× mismatch cost a
/// half-effective first cycle per screw in the field.
///
/// Staleness is self-correcting: stored values only pre-seed the
/// controllers (via `ScrewController.adoptSeed`), and the first
/// accepted sample of a session replaces the seed outright.
class ScrewCalibrationStore {
  ScrewCalibrationStore({String? directory}) : _directoryOverride = directory;

  /// Name of the store, resolved next to `orion.cfg`. Exposed so callers that
  /// must preserve state across an install (see `OrionUpdateProvider`) can
  /// name it without duplicating the literal.
  static const String fileName = 'orion_leveling_calibration.json';

  static final _log = Logger('ScrewCalibrationStore');
  final String? _directoryOverride;
  String? _resolvedDir;

  String _resolveDir() {
    final override = _directoryOverride;
    if (override != null) return override;
    final configDir = OrionConfig.configDirectory;
    if (configDir != null && configDir.isNotEmpty) return configDir;
    try {
      final execDir = path.dirname(Platform.resolvedExecutable);
      if (execDir.isNotEmpty) return execDir;
    } catch (_) {}
    try {
      return Directory.current.path;
    } catch (_) {}
    return '.';
  }

  String get filePath {
    _resolvedDir ??= _resolveDir();
    return path.join(_resolvedDir!, fileName);
  }

  /// Read the stored couplings (mm/gf), keyed by screw id
  /// ('fl', 'fr', 'back').  Missing file or malformed content → empty.
  Future<Map<String, double>> load() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      final couplings = decoded['couplings'];
      if (couplings is! Map<String, dynamic>) return {};
      final result = <String, double>{};
      for (final entry in couplings.entries) {
        final v = (entry.value as num?)?.toDouble();
        // Only physically-possible (negative) values are usable.
        if (v != null && v < 0) result[entry.key] = v;
      }
      return result;
    } catch (e, st) {
      _log.warning('Failed to load screw calibration', e, st);
      return {};
    }
  }

  /// Merge [couplingMmPerGf] for [screw] ('fl', 'fr', 'back') into the
  /// stored calibration.
  Future<void> save(String screw, double couplingMmPerGf) async {
    try {
      final existing = await load();
      existing[screw] = couplingMmPerGf;
      final file = File(filePath);
      await file.writeAsString(jsonEncode({
        'couplings': existing,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }));
      _log.info(
          'Screw calibration saved: $screw=${couplingMmPerGf.toStringAsFixed(6)} mm/gf');
    } catch (e, st) {
      _log.warning('Failed to save screw calibration', e, st);
    }
  }
}
