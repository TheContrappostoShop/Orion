/*
* Orion - Leveling Verification Record
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

import 'package:orion/tools/athena/leveling_log_entry.dart';
import 'package:orion/tools/athena/leveling_log_service.dart';
import 'package:orion/util/orion_config.dart';

/// Summary of the last passed corner check — what the Verify Leveling screen
/// renders.
///
/// The wizard stores this in `orion.cfg` (`leveling.lastPassedSession`) when a
/// check passes, because `orion.cfg` is the machine state that survives an
/// update and travels with the config.  `orion_level.log` remains the
/// human-readable audit trail; [load] falls back to parsing it for sessions
/// recorded before the snapshot existed.
class LevelingVerificationRecord {
  LevelingVerificationRecord({
    required this.timestamp,
    required this.variant,
    required this.deviationMm,
    required this.cornerZs,
    required this.totalChecks,
  });

  /// When the check ran: UTC ISO-8601 for records stored in `orion.cfg`,
  /// log-formatted text for records parsed out of the log.
  final String timestamp;

  /// Leveling variant/arm id (e.g. `'pro'`).
  final String variant;

  /// Total corner deviation (mm) of the passing check.
  final double deviationMm;

  /// Measured Z per corner, keyed by `'FL'`/`'FR'`/`'BR'`/`'BL'`.
  final Map<String, double> cornerZs;

  /// Number of checks run in the session that produced this record.
  final int totalChecks;

  late final CornerStats _stats =
      CornerStats.fromLookup((label) => cornerZs[label]);

  double? get frontAvgZ => _stats.frontAvgZ;
  double? get backAvgZ => _stats.backAvgZ;
  double? get rangeMm => _stats.rangeMm;
  double? get frontBackGapMm => _stats.frontBackGapMm;

  /// Build the snapshot persisted for a check that just passed.  The check
  /// that just ran is the last one of its session so far, so the session's
  /// check count is its recheck index plus one (the initial check is 0).
  factory LevelingVerificationRecord.fromLogEntry(LevelingLogEntry entry) {
    final corners = <String, double>{};
    entry.corners.forEach((label, data) {
      final z = data.finalZ;
      if (z != null) corners[label] = z;
    });
    return LevelingVerificationRecord(
      timestamp: entry.timestamp,
      variant: entry.variant,
      deviationMm: entry.totalDeviationMm,
      cornerZs: corners,
      totalChecks: entry.recheckNumber + 1,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp,
        'variant': variant,
        'deviation_mm': deviationMm,
        'corners': cornerZs,
        'total_checks': totalChecks,
      };

  /// Decode a stored snapshot, or null when it is malformed.
  static LevelingVerificationRecord? fromJson(Map<String, dynamic> json) {
    final timestamp = json['timestamp'];
    final variant = json['variant'];
    final deviation = json['deviation_mm'];
    if (timestamp is! String || variant is! String || deviation is! num) {
      return null;
    }

    final corners = <String, double>{};
    final rawCorners = json['corners'];
    if (rawCorners is Map) {
      rawCorners.forEach((key, value) {
        if (key is String && value is num) corners[key] = value.toDouble();
      });
    }

    final checks = json['total_checks'];
    return LevelingVerificationRecord(
      timestamp: timestamp,
      variant: variant,
      deviationMm: deviation.toDouble(),
      cornerZs: corners,
      totalChecks: checks is int ? checks : 1,
    );
  }

  /// The record to show: `orion.cfg` first, then the log written by runs that
  /// predate the snapshot.  Null when the printer has no recorded session.
  static LevelingVerificationRecord? load() {
    final stored = OrionConfig().getLastPassedLevelingSession();
    if (stored != null) {
      final record = fromJson(stored);
      if (record != null) return record;
    }

    for (final path in <String>[
      LevelingLogService.logFilePath,
      LevelingLogService.fileName,
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final parsed = fromLogText(file.readAsStringSync());
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Parse the last PASSED session block out of a log file's [text].
  static LevelingVerificationRecord? fromLogText(String text) {
    final lines = text.split('\n');

    // Find the last PASSED Result line, then walk backward to the session
    // header, and forward to the closing separator to capture the full block.
    int? passedLine;
    for (int i = lines.length - 1; i >= 0; i--) {
      if (lines[i].contains('PASSED') && lines[i].contains('total deviation')) {
        passedLine = i;
        break;
      }
    }
    if (passedLine == null) return null;

    int? headerLine;
    for (int i = passedLine; i >= 0; i--) {
      if (lines[i].contains('LEVELING SESSION')) {
        headerLine = i;
        break;
      }
    }
    if (headerLine == null) return null;

    // Walk forward to the NEXT session header (or EOF), then back up to the
    // separator just before it — that's the true end of this session's data
    // (the first separator after the header closes only the header block;
    // corner measurements follow it).
    final sep = '=' * 70;
    int closeLine = lines.length;
    for (int i = headerLine + 1; i < lines.length; i++) {
      if (lines[i].contains('LEVELING SESSION')) {
        for (int j = i - 1; j > headerLine; j--) {
          if (lines[j].startsWith(sep)) {
            closeLine = j;
            break;
          }
        }
        break;
      }
    }
    if (closeLine == lines.length) {
      for (int j = lines.length - 1; j > headerLine; j--) {
        if (lines[j].startsWith(sep)) {
          closeLine = j;
          break;
        }
      }
    }

    final block = lines.sublist(headerLine, closeLine).join('\n');

    final timestampRaw = _extractLine(block, 'Timestamp');
    final timestamp = timestampRaw.replaceAll('(local)', '').trim();

    final sessionId = _extractLine(block, 'LEVELING SESSION');
    int totalChecks = 0;
    if (sessionId.isNotEmpty) {
      for (final line in lines) {
        if (line.contains(sessionId)) totalChecks++;
      }
    }

    final deviationStr = _extractLine(block, 'Result');
    final deviationMatch =
        RegExp(r'total deviation (\d+\.\d+) mm').firstMatch(deviationStr);
    final deviationMm = deviationMatch != null
        ? double.tryParse(deviationMatch.group(1)!) ?? 0.0
        : 0.0;

    final cornerZs = <String, double>{};
    const cornerLabels = ['FL', 'FR', 'BR', 'BL'];
    for (final label in cornerLabels) {
      final z = _extractCornerZ(block, label);
      if (z != null) cornerZs[label] = z;
    }

    return LevelingVerificationRecord(
      timestamp: timestamp,
      variant: _extractLine(block, 'Variant'),
      deviationMm: deviationMm,
      cornerZs: cornerZs,
      totalChecks: totalChecks > 0 ? totalChecks : 1,
    );
  }
}

/// Match a line starting with [label], then skip whitespace (and an optional
/// colon), then capture the rest.  `\s*` (not `\s+`) after the colon so short
/// gaps (e.g. `LEVELING SESSION  <uuid>`) match.
String _extractLine(String block, String label) {
  final pattern = RegExp('^\\s*$label\\s*:?\\s*(.+)', multiLine: true);
  return pattern.firstMatch(block)?.group(1)?.trim() ?? '';
}

/// Z of a corner row in the measurements table.
///
/// Rows look like: `  FL   Front Left    0.79       -828.74   ...` — the first
/// decimal number after the corner name is the Z value.
double? _extractCornerZ(String block, String label) {
  for (final line in block.split('\n')) {
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith(label)) continue;
    // Ensure the next char is whitespace (not part of a longer word).
    if (trimmed.length > label.length &&
        trimmed[label.length] != ' ' &&
        trimmed[label.length] != '\t') {
      continue;
    }
    final numbers = RegExp(r'(-?\d+\.\d+)').allMatches(trimmed).toList();
    if (numbers.isNotEmpty) {
      return double.tryParse(numbers.first.group(1)!);
    }
  }
  return null;
}
