/*
* Orion - NanoDLP Simulated Backend Client
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_thumbnail_generator.dart';
import 'package:orion/backend_service/nanodlp/models/nano_status.dart';
import 'package:orion/backend_service/nanodlp/nanodlp_mappers.dart';
import 'package:orion/util/orion_config.dart';

/// Printerless, deterministic NanoDLP simulator for development/testing.
///
/// Intentionally avoids background timers to keep tests stable.
class NanoDlpSimulatedClient implements BackendClient {
  NanoDlpSimulatedClient({int totalLayers = 200, double layerSeconds = 2.5})
      : _totalLayers = max(1, totalLayers),
        _layerSeconds = layerSeconds <= 0 ? 2.5 : layerSeconds {
    _seedProfiles();
    _loadPersistedState();
    _useDefaultPrintTiming();
  }

  final int _totalLayers;
  final double _layerSeconds;

  int _activeTotalLayers = 0;
  double _activeLayerSeconds = 0.0;

  final StreamController<Map<String, dynamic>> _statusController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _printing = false;
  bool _paused = false;
  bool _cancelLatched = false;
  int _currentLayer = 0;

  String _currentFilePath = '/sim/demo_print.gcode';
  String _currentFileName = 'demo_print.gcode';

  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pauseAccumulated = Duration.zero;

  int? _defaultProfileId = 1;
  double _zOffset = 0.0;
  double _zHeightMm = 0.0;
  double _vatTemp = 23.0;
  double _chamberTemp = 24.0;

  final bool _vatHeaterPresent = true;
  final bool _chamberHeaterPresent = true;

  bool _vatControlEnabled = false;
  bool _chamberControlEnabled = false;

  final List<Map<String, dynamic>> _files = [];
  final Map<int, Map<String, dynamic>> _profiles = {};

  DateTime? _calibrationStartedAt;
  bool _calibrationPlateProcessed = false;
  int? _lastCalibrationModelId;
  int? _lastCalibrationProfileId;
  List<double> _lastCalibrationExposureTimes = const [];

  static const Duration _calibrationPreparationDuration = Duration(seconds: 2);
  static const int _calibrationPrintLayers = 10;
  static const double _calibrationPrintLayerSeconds = 0.8;
  static const String _persistedStateFile = 'simulated_backend_state.json';

  String? _stateFilePath() {
    try {
      final cfg = OrionConfig();
      final dir = cfg.getConfigPath();
      if (dir.isEmpty) return null;
      return '$dir/$_persistedStateFile';
    } catch (_) {
      return null;
    }
  }

  void _loadPersistedState() {
    try {
      final filePath = _stateFilePath();
      if (filePath == null) return;
      final file = File(filePath);
      if (!file.existsSync()) return;

      final raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;

      final state = Map<String, dynamic>.from(decoded);
      final persistedProfiles = state['profiles'];
      if (persistedProfiles is Map) {
        for (final entry in persistedProfiles.entries) {
          final id = int.tryParse(entry.key.toString());
          if (id == null) continue;
          if (entry.value is Map) {
            _profiles[id] = Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }

      final defaultProfileId = state['defaultProfileId'];
      if (defaultProfileId != null) {
        _defaultProfileId =
            int.tryParse('$defaultProfileId') ?? _defaultProfileId;
      }
    } catch (_) {
      // Ignore persistence loading errors in simulator mode.
    }
  }

  void _persistState() {
    try {
      final filePath = _stateFilePath();
      if (filePath == null) return;
      final file = File(filePath);

      final profiles = <String, dynamic>{};
      for (final entry in _profiles.entries) {
        profiles[entry.key.toString()] = entry.value;
      }

      final payload = {
        'schemaVersion': 1,
        'defaultProfileId': _defaultProfileId,
        'profiles': profiles,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(payload));
    } catch (_) {
      // Ignore persistence write errors in simulator mode.
    }
  }

  void _useDefaultPrintTiming() {
    _activeTotalLayers = _totalLayers;
    _activeLayerSeconds = _layerSeconds;
  }

  void _useCalibrationPrintTiming() {
    _activeTotalLayers = _calibrationPrintLayers;
    _activeLayerSeconds = _calibrationPrintLayerSeconds;
  }

  void _upsertFile({required String name, required String path}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final idx = _files.indexWhere((f) => f['path'] == path);
    final item = {
      'name': name,
      'path': path,
      'last_modified': now,
    };
    if (idx >= 0) {
      _files[idx] = item;
    } else {
      _files.insert(0, item);
    }
  }

  void _startPrintInternal(String filePath) {
    _currentFilePath = filePath.trim().isEmpty ? _currentFilePath : filePath;
    _currentFileName = _currentFilePath.split('/').last;
    _printing = true;
    _paused = false;
    _cancelLatched = false;
    _currentLayer = 0;
    _startedAt = DateTime.now();
    _pausedAt = null;
    _pauseAccumulated = Duration.zero;
  }

  double _calibrationPreparationProgress() {
    final started = _calibrationStartedAt;
    if (started == null) return 0.0;
    if (_calibrationPlateProcessed) return 1.0;
    final elapsedMs = DateTime.now().difference(started).inMilliseconds;
    final totalMs = _calibrationPreparationDuration.inMilliseconds;
    if (totalMs <= 0) return 1.0;
    return (elapsedMs / totalMs).clamp(0.0, 1.0);
  }

  void _syncCalibrationProgress() {
    if (_calibrationStartedAt == null || _calibrationPlateProcessed) return;
    final progress = _calibrationPreparationProgress();
    if (progress >= 0.93) {
      _calibrationPlateProcessed = true;
      if (!_printing) {
        final modelId = _lastCalibrationModelId ?? 0;
        _useCalibrationPrintTiming();
        _startPrintInternal('/sim/calibration_$modelId.gcode');
        _emitStatus();
      }
    }
  }

  void _seedProfiles() {
    for (var i = 1; i <= 3; i++) {
      _profiles[i] = {
        'ResinID': i,
        'ProfileID': i,
        'Title': 'Sim Resin #$i',
        'Desc': 'Simulated profile',
        'normal_cure_time': 2.0 + i,
        'burn_in_cure_time': 12.0,
        'lift_after_print': 5.0,
        'burn_in_count': 4,
        'wait_after_cure': 1.5,
        'wait_after_life': 1.5,
        'CustomValues': {
          'normal_cure_time': '${2.0 + i}',
          'burn_in_cure_time': '12.0',
          'lift_after_print': '5.0',
          'burn_in_count': '4',
          'wait_after_cure': '1.5',
          'wait_after_life': '1.5',
        }
      };
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    _files.addAll([
      {
        'name': 'demo_print.gcode',
        'path': '/sim/demo_print.gcode',
        'last_modified': now,
      },
      {
        'name': 'calibration_plate.gcode',
        'path': '/sim/calibration_plate.gcode',
        'last_modified': now - 5000,
      }
    ]);
  }

  void _syncProgress() {
    _syncCalibrationProgress();
    if (!_printing || _paused || _startedAt == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(_startedAt!).inMilliseconds / 1000.0;
    final active = elapsed - _pauseAccumulated.inMilliseconds / 1000.0;
    final layer =
        min(_activeTotalLayers, max(0, active ~/ _activeLayerSeconds));
    if (layer != _currentLayer) _currentLayer = layer;

    if (_currentLayer >= _activeTotalLayers) {
      _printing = false;
      _paused = false;
      _pausedAt = null;
      _useDefaultPrintTiming();
    }
  }

  Map<String, dynamic> _nanoStatus() {
    _syncProgress();
    return {
      'Printing': _printing,
      'Paused': _paused,
      'Status': _printing
          ? (_paused ? 'Paused' : 'Printing')
          : (_cancelLatched ? 'Canceled' : 'Idle'),
      'State': _printing ? (_paused ? 6 : 5) : 0,
      'LayerID': _currentLayer,
      'LayersCount': _activeTotalLayers,
      'CurrentHeight': (_zHeightMm * 6400).round(),
      'PrevLayerTime': (_activeLayerSeconds * 1e9).round(),
      'resin': _vatTemp,
      'temp': _chamberTemp,
      'mcu': 46.0,
      'file': {
        'name': _currentFileName,
        'path': _currentFilePath,
        'layer_count': _activeTotalLayers,
      },
      'calibration': {
        'model_id': _lastCalibrationModelId,
        'profile_id': _lastCalibrationProfileId,
        'exposure_times': _lastCalibrationExposureTimes,
        'processed': _calibrationPlateProcessed,
      },
      'cancel_latched': _cancelLatched,
      'pause_latched': _paused,
    };
  }

  Map<String, dynamic> _mappedStatus() {
    final raw = _nanoStatus();
    try {
      final ns = NanoStatus.fromJson(Map<String, dynamic>.from(raw));
      return nanoStatusToOdysseyMap(ns);
    } catch (_) {
      return raw;
    }
  }

  void _emitStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(_mappedStatus());
    }
  }

  @override
  Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory) async {
    if (location.toLowerCase() == 'resins') {
      final profileItems = _profiles.values.map((p) {
        final id = p['ProfileID'] ?? p['ResinID'];
        final title = (p['Title'] ?? p['title'] ?? 'Sim Resin').toString();
        return <String, dynamic>{
          'id': id,
          'ProfileID': id,
          'ResinID': p['ResinID'] ?? id,
          'title': title,
          'name': title,
          'path': '/sim/resins/$id',
          'locked': false,
        };
      }).toList(growable: false);

      final start = pageIndex * pageSize;
      final end = min(profileItems.length, start + pageSize);
      final page = (start >= 0 && start < profileItems.length)
          ? profileItems.sublist(start, end)
          : <Map<String, dynamic>>[];
      return {
        'resins': page,
        'files': page,
        'dirs': <Map<String, dynamic>>[],
        'page_index': pageIndex,
        'page_size': pageSize,
        'total': profileItems.length,
      };
    }

    final start = pageIndex * pageSize;
    final end = min(_files.length, start + pageSize);
    final page = (start >= 0 && start < _files.length)
        ? _files.sublist(start, end)
        : <Map<String, dynamic>>[];
    return {
      'files': page,
      'dirs': <Map<String, dynamic>>[],
      'page_index': pageIndex,
      'page_size': pageSize,
      'total': _files.length,
    };
  }

  @override
  Future<bool> usbAvailable() async => true;

  @override
  Future<Map<String, dynamic>> getFileMetadata(
      String location, String filePath) async {
    final normalizedPath = filePath.trim().toLowerCase();
    final isCalibrationFile = normalizedPath.contains('/calibration_') ||
        normalizedPath.endsWith('/0') ||
        normalizedPath == '0';

    return {
      if (isCalibrationFile) 'plate_id': 0,
      'file_data': {
        'path': filePath,
        'name': filePath.split('/').last,
        'last_modified': DateTime.now().millisecondsSinceEpoch,
        'parent_path': '/sim',
      }
    };
  }

  @override
  Future<Map<String, dynamic>> getConfig() async => {
        'general': {'hostname': 'sim-nanodlp'},
        'advanced': {'backend': 'nanodlp', 'simulated': true},
      };

  @override
  Future<String> getBackendVersion() async => 'nanodlp-sim-3.0';

  @override
  Future<Uint8List> getFileThumbnail(
      String location, String filePath, String size) async {
    if (size == 'thumb') {
      return NanoDlpThumbnailGenerator.generatePlaceholder(160, 96);
    }
    return NanoDlpThumbnailGenerator.generatePlaceholder(
      NanoDlpThumbnailGenerator.largeWidth,
      NanoDlpThumbnailGenerator.largeHeight,
    );
  }

  @override
  Future<void> startPrint(String location, String filePath) async {
    _calibrationStartedAt = null;
    _calibrationPlateProcessed = false;
    _useDefaultPrintTiming();
    _startPrintInternal(filePath);
    _emitStatus();
  }

  @override
  Future<Map<String, dynamic>> deleteFile(
      String location, String filePath) async {
    _files.removeWhere((f) => f['path'] == filePath);
    return {'deleted': true};
  }

  @override
  Future<void> invalidateCache() async {}

  @override
  Future<int?> importFile(FileImportRequest request) async {
    final id = _files.length + 1;
    final name = request.jobName.trim().isNotEmpty
        ? request.jobName.trim()
        : 'imported_$id.gcode';
    _files.insert(0, {
      'name': name,
      'path': '/sim/$name',
      'last_modified': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  @override
  Future<ResinSettings?> getResinSettings(int profileId) async {
    final p = await getProfileJson(profileId);
    return ResinSettings.fromNormalizedMap(p);
  }

  @override
  Future<void> saveResinExposure(int profileId, double normalCureTime) async {
    await editProfile(profileId, {'normal_cure_time': normalCureTime});
  }

  @override
  Future<void> saveResinSettings(int profileId, ResinSettings settings) async {
    await editProfile(profileId, settings.toNormalizedMap());
  }

  @override
  Future<Map<String, dynamic>> getStatus() async => _mappedStatus();

  @override
  Stream<Map<String, dynamic>> getStatusStream() {
    Future.microtask(_emitStatus);
    return _statusController.stream;
  }

  @override
  Future<List<Map<String, dynamic>>> getNotifications() async => [];

  @override
  Future<Map<String, dynamic>?> getKinematicStatus() async => {
        'homed': true,
        'offset': _zOffset,
        'position': _zHeightMm,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

  @override
  Future<void> disableNotification(int timestamp) async {}

  @override
  Future<void> cancelPrint() async {
    _printing = false;
    _paused = false;
    _cancelLatched = true;
    _currentLayer = 0;
    _calibrationStartedAt = null;
    _calibrationPlateProcessed = false;
    _useDefaultPrintTiming();
    _emitStatus();
  }

  @override
  Future<void> pausePrint() async {
    if (!_printing || _paused) return;
    _paused = true;
    _pausedAt = DateTime.now();
    _emitStatus();
  }

  @override
  Future<void> resumePrint() async {
    if (!_printing || !_paused) return;
    if (_pausedAt != null) {
      _pauseAccumulated += DateTime.now().difference(_pausedAt!);
    }
    _paused = false;
    _pausedAt = null;
    _emitStatus();
  }

  @override
  Future<Map<String, dynamic>> move(double height) async {
    _zHeightMm = height;
    return {'ok': true, 'z': _zHeightMm};
  }

  @override
  Future<Map<String, dynamic>> moveDelta(double deltaMm) async {
    _zHeightMm += deltaMm;
    return {'ok': true, 'z': _zHeightMm};
  }

  @override
  Future<bool> canMoveToTop() async => true;

  @override
  Future<bool> canMoveToFloor() async => true;

  @override
  Future<Map<String, dynamic>> moveToTop() async {
    _zHeightMm = 200;
    return {'ok': true, 'z': _zHeightMm};
  }

  @override
  Future<Map<String, dynamic>> moveToFloor() async {
    _zHeightMm = 0;
    return {'ok': true, 'z': _zHeightMm};
  }

  @override
  Future<Map<String, dynamic>> manualCure(bool cure) async => {'ok': true};

  @override
  Future<Map<String, dynamic>> manualHome() async {
    _zHeightMm = 0;
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> manualCommand(String command) async => {
        'ok': true,
        'command': command,
      };

  @override
  Future<Map<String, dynamic>> emergencyStop() async {
    await cancelPrint();
    return {'stopped': true};
  }

  @override
  Future<void> displayTest(String test) async {}

  @override
  Future<Uint8List> getPlateLayerImage(int plateId, int layer) async {
    return NanoDlpThumbnailGenerator.generatePlaceholder(320, 200);
  }

  @override
  Future<List<Map<String, dynamic>>> getAnalytics(int n) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = [
      {'T': 7, 'V': _chamberTemp, 'id': now},
      {'T': 12, 'V': _chamberTemp, 'id': now},
      {'T': 23, 'V': _chamberTemp, 'id': now},
      {'T': 25, 'V': _vatTemp, 'id': now},
      {'T': 31, 'V': _currentLayer, 'id': now},
    ];
    return rows.take(max(0, n)).toList();
  }

  @override
  Future<dynamic> getAnalyticValue(int id) async {
    switch (id) {
      case 7:
      case 12:
      case 23:
        return _chamberTemp;
      case 25:
        return _vatTemp;
      default:
        return Random().nextDouble() * 10;
    }
  }

  @override
  Future<Map<String, dynamic>> getMachine() async => {
        'Name': 'NanoDLP-Sim',
        'UUID': 'sim-uuid',
        'DefaultProfile': _defaultProfileId,
        'CustomValues': {
          'VatHeaterPresent': _vatHeaterPresent ? '1' : '0',
          'ChamberHeaterPresent': _chamberHeaterPresent ? '1' : '0',
        },
      };

  @override
  Future<Map<String, dynamic>> getProfileJson(int id) async {
    return Map<String, dynamic>.from(
      _profiles[id] ??
          {
            'ProfileID': id,
            'Title': 'Sim Resin #$id',
            'Desc': 'Auto-generated profile',
            'normal_cure_time': 3.0,
            'burn_in_cure_time': 12.0,
            'lift_after_print': 5.0,
            'burn_in_count': 4,
            'wait_after_cure': 1.5,
            'wait_after_life': 1.5,
            'CustomValues': {
              'normal_cure_time': '3.0',
              'burn_in_cure_time': '12.0',
              'lift_after_print': '5.0',
              'burn_in_count': '4',
              'wait_after_cure': '1.5',
              'wait_after_life': '1.5',
            },
          },
    );
  }

  @override
  Future<Map<String, dynamic>> editProfile(
      int id, Map<String, dynamic> fields) async {
    final base = await getProfileJson(id);
    final merged = Map<String, dynamic>.from(base);
    final custom = merged['CustomValues'] is Map
        ? Map<String, dynamic>.from(merged['CustomValues'])
        : <String, dynamic>{};

    fields.forEach((k, v) {
      merged[k] = v;
      custom[k] = '$v';
    });

    merged['CustomValues'] = custom;
    _profiles[id] = merged;
    _persistState();
    return merged;
  }

  @override
  Future<int?> getDefaultProfileId() async => _defaultProfileId;

  @override
  Future<Map<String, dynamic>> cloneProfile(
      int sourceId, Map<String, dynamic> fields) async {
    final clone = Map<String, dynamic>.from(await getProfileJson(sourceId));
    final nextId = _profiles.keys.isEmpty ? 1 : _profiles.keys.reduce(max) + 1;
    clone['ProfileID'] = nextId;
    clone['ManufacturerLock'] = false;

    final custom = clone['CustomValues'] is Map
        ? Map<String, dynamic>.from(clone['CustomValues'] as Map)
        : <String, dynamic>{};
    fields.forEach((key, value) {
      clone[key] = value;
      custom[key] = '$value';
    });
    clone['CustomValues'] = custom;

    _profiles[nextId] = clone;
    _persistState();
    return clone;
  }

  @override
  Future<void> setDefaultProfileId(int id) async {
    _defaultProfileId = id;
    _persistState();
  }

  @override
  Future<dynamic> tareForceSensor() async => true;

  @override
  Future<dynamic> updateBackend() async => true;

  @override
  Future setChamberTemperature(double temperature) async {
    _chamberTemp = temperature;
    _chamberControlEnabled = temperature > 0.0;
    return true;
  }

  @override
  Future setVatTemperature(double temperature) async {
    _vatTemp = temperature;
    _vatControlEnabled = temperature > 0.0;
    return true;
  }

  @override
  Future<bool> isChamberTemperatureControlEnabled() async =>
      _chamberControlEnabled;

  @override
  Future<bool> isVatTemperatureControlEnabled() async => _vatControlEnabled;

  @override
  Future getChamberTemperature() async => _chamberTemp;

  @override
  Future getVatTemperature() async => _vatTemp;

  @override
  Future<void> preheatAndMix(double temperature) async {
    await setVatTemperature(temperature);
  }

  @override
  Future<void> preheatAndMixStandalone() async {}

  @override
  Future<String?> getCalibrationImageUrl(int modelId) async {
    return 'http://localhost/static/shots/calibration-images/$modelId.png';
  }

  @override
  Future<List<Map<String, dynamic>>> getCalibrationModels() async {
    return [
      {
        'id': 1,
        'name': 'J3D Calibration RERF',
        'models': 6,
        'info': {'resinRequired': 21, 'height': 3700},
      },
      {
        'id': 2,
        'name': 'J3D Calibration Boxes of Calibration',
        'models': 6,
        'info': {'resinRequired': 9, 'height': 10100},
      },
    ];
  }

  @override
  Future<bool> startCalibrationPrint({
    required int calibrationModelId,
    required List<double> exposureTimes,
    required int profileId,
  }) async {
    _lastCalibrationModelId = calibrationModelId;
    _lastCalibrationProfileId = profileId;
    _lastCalibrationExposureTimes = List<double>.from(exposureTimes);

    _calibrationStartedAt = DateTime.now();
    _calibrationPlateProcessed = false;

    final filePath = '/sim/calibration_$calibrationModelId.gcode';
    _upsertFile(name: 'calibration_$calibrationModelId.gcode', path: filePath);
    _currentFilePath = filePath;
    _currentFileName = filePath.split('/').last;
    _cancelLatched = false;
    _emitStatus();
    return true;
  }

  @override
  Future<double?> getSlicerProgress() async {
    _syncCalibrationProgress();
    if (_calibrationStartedAt != null) {
      return _calibrationPreparationProgress();
    }

    if (!_printing) return null;
    _syncProgress();
    return (_currentLayer / _activeTotalLayers).clamp(0.0, 1.0);
  }

  @override
  Future<bool?> isCalibrationPlateProcessed() async {
    _syncCalibrationProgress();
    if (_calibrationStartedAt == null && !_calibrationPlateProcessed) {
      return null;
    }
    return _calibrationPlateProcessed;
  }

  @override
  Future<bool> resetZOffset() async {
    _zOffset = 0;
    return true;
  }

  @override
  Future<bool> setZOffset(double offset) async {
    _zOffset = offset;
    return true;
  }

  void dispose() {
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }
}
