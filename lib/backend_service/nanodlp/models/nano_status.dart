/*
* Orion - NanoDLP Status Model
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

import 'nano_file.dart';

// Minimal NanoDLP status DTO
class NanoStatus {
  // Raw fields from NanoDLP /status
  final bool printing;
  final bool paused;
  final String? statusMessage;
  final int? currentHeight; // possibly microns or device units
  final int? layerId;
  final int? layersCount;
  final double? resinLevel; // mm or percent depending on device
  final double? temp;
  final double? mcuTemp;
  final String? rawJsonStatus;

  // Existing convenience fields
  final String state; // 'printing' | 'paused' | 'idle'
  final int? stateCode; // raw numeric 'State' field from NanoDLP when present
  final double? progress; // 0.0 - 1.0
  final NanoFile? file; // not always present in NanoDLP status
  final double? z; // z position (converted if needed)
  final bool curing;
  // Previous layer time reported by NanoDLP. NanoDLP provides this as
  // nanoseconds in some installs (key: PrevLayerTime). Preserve raw
  // integer nanoseconds when present so mappers/providers can convert.
  final int? prevLayerTimeNs;

  NanoStatus({
    required this.printing,
    required this.paused,
    this.statusMessage,
    this.currentHeight,
    this.layerId,
    this.layersCount,
    this.resinLevel,
    this.temp,
    this.mcuTemp,
    this.rawJsonStatus,
    required this.state,
    this.stateCode,
    this.progress,
    this.file,
    this.z,
    this.curing = false,
    this.prevLayerTimeNs,
  });

  factory NanoStatus.fromJson(Map<String, dynamic> json) {
    // The NanoDLP /status payloads vary between installs. File/plate metadata
    // may appear under different keys (lower/upper case or different names).
    // Search a set of likely candidate keys and pick the first Map-like value.
    NanoFile? nf;
    final candidateFileKeys = [
      'file',
      'File',
      'plate',
      'Plate',
      'file_data',
      'FileData',
      'fileData',
      'current_file',
      'CurrentFile',
      'job',
      'Job',
    ];
    for (final k in candidateFileKeys) {
      final val = json[k];
      if (val is Map<String, dynamic>) {
        nf = NanoFile.fromJson(Map<String, dynamic>.from(val));
        break;
      }
      if (val is Map) {
        try {
          nf = NanoFile.fromJson(Map<String, dynamic>.from(val));
          break;
        } catch (_) {
          // ignore and continue
        }
      }
    }

    // Helpers
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) {
        // Some devices send '24.85°C' — strip non-numeric
        final cleaned = v.replaceAll(RegExp(r'[^0-9+\-\.]'), '');
        return double.tryParse(cleaned);
      }
      return null;
    }

    final printing = json['Printing'] == true ||
        json['printing'] == true ||
        json['Started'] == 1 ||
        json['started'] == 1;
    final paused = json['Paused'] == true || json['paused'] == true;
    final statusMessage =
        json['Status']?.toString() ?? json['status']?.toString();
    final currentHeight = parseInt(json['CurrentHeight'] ??
        json['current_height'] ??
        json['CurrentHeight']);
    final layerId =
        parseInt(json['LayerID'] ?? json['layer_id'] ?? json['LayerID']);
    final layersCount = parseInt(
        json['LayersCount'] ?? json['layers_count'] ?? json['LayersCount']);
    final resinLevel = parseDouble(
        json['resin'] ?? json['ResinLevelMm'] ?? json['resin_level_mm']);
    final temp = parseDouble(json['temp']);
    final mcuTemp = parseDouble(json['mcu']);
    final curing = json['Curing'] == true || json['curing'] == true;

    // Map to simple state
    String state;
    if (printing) {
      state = 'printing';
    } else if (paused) {
      state = 'paused';
    } else {
      state = 'idle';
    }

    // Try to parse a numeric State field when present. NanoDLP may include
    // a 'State' integer that provides more granular machine state values.
    int? stateCode;
    try {
      final sc = json['State'] ?? json['state'] ?? json['STATE'];
      if (sc is int) stateCode = sc;
      if (sc is String) stateCode = int.tryParse(sc);
    } catch (_) {
      stateCode = null;
    }

    double? progress;
    if (layerId != null && layersCount != null && layersCount > 0) {
      // Treat the reported layerId as the layer currently being printed;
      // compute progress based on completed layers (layerId - 1) so the
      // in-progress layer is not counted as finished.
      final completed = (layerId - 1).clamp(0, layersCount);
      progress = (completed / layersCount).clamp(0.0, 1.0).toDouble();
    }

    double? z;
    if (currentHeight != null) {
      // NanoDLP reports current height in device-specific units on the
      // target installs we support. For these devices 1 mm == 6400 units.
      // Convert device units to millimeters so downstream mappers/consumers
      // receive a sensible `z` value. Example: 320 -> 320 / 6400 = 0.05 mm.
      z = currentHeight / 6400.0;
    }

    return NanoStatus(
      printing: printing,
      paused: paused,
      statusMessage: statusMessage,
      currentHeight: currentHeight,
      layerId: layerId,
      layersCount: layersCount,
      resinLevel: resinLevel,
      temp: temp,
      mcuTemp: mcuTemp,
      rawJsonStatus: json['Status']?.toString() ?? json.toString(),
      state: state,
      stateCode: stateCode,
      progress: progress,
      file: nf,
      z: z,
      curing: curing,
      prevLayerTimeNs: (() {
        try {
          final cand = json['PrevLayerTime'];
          return cand;
        } catch (_) {}
        return null;
      })(),
    );
  }

  Map<String, dynamic> toJson() => {
        'printing': printing,
        'paused': paused,
        'statusMessage': statusMessage,
        'currentHeight': currentHeight,
        'layerId': layerId,
        'layersCount': layersCount,
        'resinLevel': resinLevel,
        'temp': temp,
        'mcuTemp': mcuTemp,
        'state': state,
        'stateCode': stateCode,
        'progress': progress,
        'file': file?.toJson(),
        'z': z,
        'curing': curing,
        'PrevLayerTime': prevLayerTimeNs,
      };
}
