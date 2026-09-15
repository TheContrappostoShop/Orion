/*
* Orion - Status Provider
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
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/backend_service/backend_registry.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/backend_service/odyssey/models/status_models.dart';
import 'package:orion/backend_service/athena_iot/models/athena_kinematic_status.dart';
import 'dart:typed_data';
import 'package:orion/util/thumbnail_cache.dart';
import 'package:orion/util/sl1_thumbnail.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_thumbnail_generator.dart';
import 'package:orion/backend_service/providers/analytics_provider.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_file.dart';

/// Polls the backend `/status` endpoint and exposes a typed [StatusModel].
///
/// Responsibilities:
/// * Periodic polling (and optional SSE) with backoff
/// * Transitional UI flags for pause/cancel
/// * Lazy thumbnail fetching and caching
/// * Convenience accessors for the UI
class StatusProvider extends ChangeNotifier {
  final BackendClient _client;
  final _log = Logger('StatusProvider');
  // Optional analytics provider used to expose convenience getters for
  // time-series metrics (e.g. MCU / outside temperature). This is an
  // optional, non-critical dependency — callers may prefer to read
  // AnalyticsProvider directly from the widget tree. Keep this nullable
  // to avoid hard coupling during construction in tests.
  AnalyticsProvider? _analyticsProvider;

  StatusModel? _status;
  AthenaKinematicStatus? _kinematicStatus;
  String? _deviceStatusMessage;
  int? _resinTemperature;
  double? _cpuTemperature;
  Duration? _prevLayerDuration;

  // When true, kinematic status is polled continuously (useful for wizard
  // screens that need to detect when homing/moving completes). When false,
  // kinematic status is only fetched on-demand via refreshKinematicStatus().
  bool _continuousKinematicPolling = false;
  Timer? _kinematicPollTimer;
  static const Duration _kinematicPollInterval = Duration(milliseconds: 500);

  /// When printing, we may surface the live current-layer time reported via
  /// NanoDLP analytics (key: 'LayerTime'). When available, we prefer this
  /// value for UI responsiveness during an active print. This is stored
  /// separately for clarity but may be applied to `_prevLayerDuration` as a
  /// proxy while printing so existing UI bindings continue to work.
  Duration? _currentLayerDuration;

  // Track observed layer numbers and timestamps so we can compute a
  // previous-layer duration when the backend does not provide PrevLayerTime
  // reliably on every snapshot. When we detect the layer number increase we
  // compute the elapsed time since the previous layer observation.
  int? _lastObservedLayer;
  DateTime? _lastObservedLayerTime;

  /// Optional raw device-provided status message (e.g. NanoDLP "Status"
  /// field). When present this may be used to override the app bar title
  /// on the `StatusScreen` so device-provided messages like
  /// "Peel Detection Started" are surfaced directly.
  String? get deviceStatusMessage => _deviceStatusMessage;
  StatusModel? get status => _status;
  AthenaKinematicStatus? get kinematicStatus => _kinematicStatus;

  /// Current resin temperature reported by the backend (degrees Celsius).
  int? get resinTemperature => _resinTemperature;

  /// CPU temperature reported by the backend `temp` field (degrees Celsius).
  /// May be fractional so exposed as a double. Null when unavailable.
  double? get cpuTemperature => _cpuTemperature;

  /// Duration of the previous layer as reported by the backend. The backend
  /// reports `PrevLayerTime` in nanoseconds; we convert it to [Duration].
  Duration? get prevLayerDuration => _prevLayerDuration;

  /// Current (ongoing) layer duration while printing, if available from
  /// analytics (key: 'LayerTime'). This differs from `prevLayerDuration`
  /// which represents the previous completed layer; however, we may proxy
  /// `LayerTime` into `prevLayerDuration` while printing to simplify UI.
  Duration? get currentLayerDuration => _currentLayerDuration;

  /// Previous layer time in seconds as a double (null when unavailable).
  double? get prevLayerSeconds => _prevLayerDuration == null
      ? null
      : _prevLayerDuration!.inMilliseconds / 1000.0;

  double? get currentLayerSeconds => _currentLayerDuration == null
      ? null
      : _currentLayerDuration!.inMilliseconds / 1000.0;

  // Note: MCU and UV/outside temperatures are provided via the NanoDLP
  // analytics time-series. Consumers should use `AnalyticsProvider` and
  // request `getLatestForKey('TemperatureMCU')` or
  // `getLatestForKey('TemperatureOutside')` as appropriate.

  bool _loading = true;
  bool get isLoading => _loading;

  Object? _error;
  Object? get error => _error;

  bool _isCanceling =
      false; // UI transitional state until backend reflects cancel
  bool get isCanceling => _isCanceling;
  bool _isPausing =
      false; // UI transitional state until backend reflects pause/resume
  bool get isPausing => _isPausing;

  // Track if the Status Screen is currently open/visible to the user.
  // This allows other components (like update notifications) to avoid
  // interrupting the user while they are viewing print status/results.
  bool _isStatusScreenOpen = false;
  bool get isStatusScreenOpen => _isStatusScreenOpen;

  /// Inhibitor flag set by the leveling wizard so the standby screen does
  /// not activate while a force-leveling workflow is in progress.
  bool _isLevelingWorkflowActive = false;
  bool get isLevelingWorkflowActive => _isLevelingWorkflowActive;

  void setLevelingWorkflowActive(bool active) {
    if (_isLevelingWorkflowActive == active) return;
    _isLevelingWorkflowActive = active;
    notifyListeners();
  }

  /// Update the visibility state of the Status Screen.
  void setStatusScreenOpen(bool isOpen) {
    if (_isStatusScreenOpen == isOpen) return;
    _isStatusScreenOpen = isOpen;
    // We notify listeners so watchers can react to screen transitions
    // (e.g. enabling/disabling notifications).
    notifyListeners();
  }

  // Awaiting state: after a cancel/finish & reset, we keep the UI in a loading
  // spinner until we observe a NEW active print (Printing or Paused) AND the
  // thumbnail is considered ready. We do not attempt to guess by filename so
  // re-printing the same file still forces a clean re-wait.
  bool _awaitingNewPrintData = false;
  DateTime? _awaitingSince; // timestamp we began waiting for coherent data
  bool get awaitingNewPrintData => _awaitingNewPrintData;
  static const Duration _awaitingTimeout = Duration(seconds: 12);
  // Minimum spinner gating: when starting a new print we may want to ensure
  // the UI shows a small loading animation so the transition feels natural.
  DateTime? _minSpinnerUntil;
  bool get minSpinnerActive =>
      _minSpinnerUntil != null && DateTime.now().isBefore(_minSpinnerUntil!);
  // We deliberately removed expected file name gating; re-printing the same
  // file should still show a clean loading phase.

  Uint8List? _thumbnailBytes;
  Uint8List? get thumbnailBytes => _thumbnailBytes;
  bool _thumbnailReady =
      false; // becomes true once we have a path OR decide none needed
  bool get thumbnailReady => _thumbnailReady;
  // Retry tracking for placeholder thumbnails. Keyed by file path.
  final Map<String, int> _thumbnailRetries = {};
  static const int _maxThumbnailRetries = 3;

  /// Readiness for displaying a new print after a reset.
  /// Requirements:
  /// * Printer is actively printing or paused (job started)
  /// * We have printData with fileData (metadata populated)
  /// * Thumbnail attempt completed (success OR failed => _thumbnailReady true)
  bool get newPrintReady {
    final s = _status;
    if (s == null) return false;
    final active = s.isPrinting || s.isPaused;
    final hasFile = s.printData?.fileData != null;
    return active && hasFile && _thumbnailReady;
  }

  Timer? _timer;
  Timer? _backoffTimer;
  bool _polling = false;
  int _pollIntervalSeconds = 2;
  static const int _minPollIntervalSeconds = 2;
  static const int _maxPollIntervalSeconds = 60;
  static const int _standbyPollIntervalSeconds = 30;
  bool _standbyMode = false;
  // SSE reconnect tuning: aggressive base retry for local devices + small jitter.
  static const int _sseReconnectBaseSeconds = 3;
  // Don't attempt SSE if polling is repeatedly failing. If polling shows
  // consecutive errors above this threshold, skip SSE reconnect attempts
  // until polls recover.
  static const int _ssePollErrorThreshold = 3;
  int _sseConsecutiveErrors = 0;

  /// SSE support tri-state: null = unknown, true = supported, false = unsupported
  bool? _sseSupported;

  /// True once we've successfully established an SSE subscription at least once
  bool _sseEverConnected = false;

  /// True once we've attempted an SSE subscription (even if it failed)
  // bool _sseAttempted = false; // reserved for future introspection
  // Exponential backoff counters
  int _consecutiveErrors = 0;
  static const int _maxReconnectAttempts = 20;
  DateTime? _nextPollRetryAt;
  DateTime? _nextSseRetryAt;
  // int _sseConsecutiveErrors = 0; // reserved for future use
  bool _fetchInFlight = false;
  bool _disposed = false;

  bool _backendSupports(String capability) {
    try {
      final cfg = OrionConfig();
      final configuredBackend = cfg.getString('backend', category: 'advanced');
      final backendId =
          configuredBackend.isEmpty ? BackendIds.odyssey : configuredBackend;
      final registry = BackendRegistry();
      return registry.supportsCapability(backendId, capability) ?? false;
    } catch (_) {
      return false;
    }
  }

  // True while the provider is attempting the first initial connection.
  // This is used by the UI to show a startup/splash screen until the
  // first status refresh completes (success or failure).
  bool _initialAttemptInProgress = true;

  bool get initialAttemptInProgress => _initialAttemptInProgress;

  // True once we've received at least one successful status response. Used
  // by the startup gate and connection error handling logic to differentiate
  // between initial startup and post-startup connection loss.
  bool _everHadSuccessfulStatus = false;

  bool get hasEverConnected => _everHadSuccessfulStatus;

  // SSE (Server-Sent Events) client state. When streaming is active we
  // rely on incoming events instead of the periodic polling loop.
  bool _sseConnected = false;
  StreamSubscription<Map<String, dynamic>>? _sseStreamSub;

  // Exposed getters for UI/dialogs to present attempt counters and next retry
  // timestamps.
  int get pollAttemptCount => _consecutiveErrors;
  int get sseAttemptCount => _sseConsecutiveErrors;
  int get maxReconnectAttempts => _maxReconnectAttempts;
  DateTime? get nextPollRetryAt => _nextPollRetryAt;
  DateTime? get nextSseRetryAt => _nextSseRetryAt;
  DateTime? get nextRetryAt {
    if (_nextPollRetryAt == null) return _nextSseRetryAt;
    if (_nextSseRetryAt == null) return _nextPollRetryAt;
    return _nextPollRetryAt!.isBefore(_nextSseRetryAt!)
        ? _nextPollRetryAt
        : _nextSseRetryAt;
  }

  bool? get sseSupported => _sseSupported;

  StatusProvider({BackendClient? client, AnalyticsProvider? analytics})
      : _client = client ?? BackendService() {
    _analyticsProvider = analytics;
    // Prefer an SSE subscription when the backend supports it. If the
    // connection fails we fall back to the existing polling loop. See
    // comments in _tryStartSse for detailed reconnect / fallback behavior.
    _tryStartSse();
  }

  /// Attach or replace the AnalyticsProvider after construction. This is
  /// useful when the provider is created via DI and the AnalyticsProvider
  /// becomes available afterwards (or in tests).
  void setAnalyticsProvider(AnalyticsProvider? analytics) {
    _analyticsProvider = analytics;
  }

  /// Convenience getter: latest MCU temperature from analytics (degrees C).
  /// Returns null if analytics aren't available or the value is missing.
  double? get mcuTemperature {
    try {
      final v = _analyticsProvider?.getLatestForKey('TemperatureMCU');
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    } catch (_) {
      return null;
    }
  }

  /// Convenience getter: latest outside/UV temperature from analytics.
  double? get uvTemperature {
    try {
      final v = _analyticsProvider?.getLatestForKey('TemperatureOutside');
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    } catch (_) {
      return null;
    }
  }

  void _startPolling() {
    // Start an async polling loop that adapts interval on errors.
    // The loop is cancelable via [_polling] so that when an SSE stream
    // becomes active we can stop polling to avoid duplicate requests.
    if (_polling || _sseConnected || _disposed) return;
    _polling = true;
    Future<void>(() async {
      try {
        await refresh();
        while (!_disposed && _polling && !_sseConnected) {
          try {
            await Future.delayed(Duration(seconds: _pollIntervalSeconds));
          } catch (_) {
            // ignore
          }
          if (_disposed || !_polling || _sseConnected) break;
          await refresh();
        }
      } finally {
        // Ensure flag is cleared when the loop exits for any reason.
        _polling = false;
      }
    });
  }

  /// Try to subscribe to SSE (status stream). On failure we fall back to
  /// polling and schedule reconnect attempts with backoff.
  Future<void> _tryStartSse() async {
    if (_sseConnected || _disposed) return;
    // If we've determined SSE is unsupported, don't retry it.
    if (_sseSupported == false) {
      _log.info('SSE previously determined unsupported; skipping SSE attempts');
      _startPolling();
      return;
    }
    // If backend does not advertise SSE support, skip stream attempts.
    try {
      final supportsSse =
          _backendSupports(BackendCapabilities.supportsSseStatusStream);
      if (!supportsSse) {
        _log.info('Backend does not support SSE status stream; using polling');
        _startPolling();
        return;
      }
      // If polling has been failing repeatedly, avoid attempting SSE until
      // polls recover. This prevents wasting SSE attempts while API is
      // clearly unreachable.
      if (_consecutiveErrors >= _ssePollErrorThreshold) {
        _log.info(
            'Skipping SSE attempt because polling has $_consecutiveErrors consecutive errors');
        _startPolling();
        return;
      }
    } catch (_) {
      // If config read fails, proceed to attempt SSE as a best-effort.
    }

    _log.info('Attempting SSE subscription via BackendClient.getStatusStream');
    try {
      final stream = _client.getStatusStream();
      // When SSE becomes active, cancel any existing polling loop so we rely
      // on the event stream instead of periodic polling.
      _sseConnected = true;
      _sseEverConnected = true;
      _sseSupported = true;
      _polling = false;

      // Reset SSE error counter on successful subscription
      _sseConsecutiveErrors = 0;
      _sseStreamSub = stream.listen((raw) async {
        try {
          // Capture any raw device status text (mapper sets 'device_status_message')
          try {
            _deviceStatusMessage =
                (raw['device_status_message'] ?? raw['Status'] ?? raw['status'])
                    ?.toString();
          } catch (_) {
            _deviceStatusMessage = null;
          }
          // Capture resin temperature if the backend provides it (common NanoDLP fields)
          try {
            final maybeTemp = raw['resin'] ??
                raw['Resin'] ??
                raw['resin_temperature'] ??
                raw['ResinTemperature'];
            int? parsedTemp;
            if (maybeTemp == null) {
              parsedTemp = null;
            } else if (maybeTemp is num) {
              parsedTemp = maybeTemp.toInt();
            } else {
              final s = maybeTemp
                  .toString()
                  .trim()
                  .toLowerCase()
                  .replaceAll('°', '')
                  .replaceAll('c', '')
                  .trim();
              final numStr = s.replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
              parsedTemp =
                  double.tryParse(numStr)?.round() ?? int.tryParse(numStr);
            }
            _resinTemperature = parsedTemp;
          } catch (_) {
            // ignore parsing errors and leave _resinTemperature unchanged
          }
          // Capture CPU temperature from `temp` field if present. Exposed as
          // a double since some backends report fractional CPU temps.
          try {
            final maybeCpu = raw['temp'] ?? raw['Temp'] ?? raw['cpu_temp'];
            double? parsedCpu;
            if (maybeCpu == null) {
              parsedCpu = null;
            } else if (maybeCpu is num) {
              parsedCpu = maybeCpu.toDouble();
            } else {
              final s = maybeCpu
                  .toString()
                  .trim()
                  .toLowerCase()
                  .replaceAll('°', '')
                  .replaceAll('c', '')
                  .trim();
              final numStr = s.replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
              parsedCpu = double.tryParse(numStr);
            }
            _cpuTemperature = parsedCpu;
          } catch (_) {
            // ignore
          }
          // PrevLayerTime parsing deferred until after we parse the StatusModel
          // so the provider can prefer a normalized model field when present.
          // MCU and UV/outside temperatures are provided by NanoDLP analytics
          // time-series. Consumers should use AnalyticsProvider.getLatestForKey
          // to read `TemperatureMCU` and `TemperatureOutside`.
          final parsed = StatusModel.fromJson(raw);

          // Compute prev-layer time from observed layer changes when the
          // backend does not include PrevLayerTime frequently. This is a
          // best-effort heuristic: when we observe the layer number change
          // (increment), record the time delta as the previous-layer duration.
          try {
            final now = DateTime.now();
            final observedLayer = parsed.layer;
            if (observedLayer != null) {
              if (_lastObservedLayer == null) {
                _lastObservedLayer = observedLayer;
                _lastObservedLayerTime = now;
              } else if (observedLayer != _lastObservedLayer) {
                // If layer increased, compute delta; if it decreased or reset
                // (e.g. new job), just re-seed the timestamp.
                if (observedLayer > (_lastObservedLayer ?? -999999)) {
                  final prevTime = _lastObservedLayerTime ?? now;
                  final delta = now.difference(prevTime);
                  // Only accept reasonable durations (e.g., >0s and <24h)
                  if (delta.inSeconds > 0 && delta.inHours < 24) {
                    _prevLayerDuration = delta;
                  }
                }
                _lastObservedLayer = observedLayer;
                _lastObservedLayerTime = now;
              }
            }
          } catch (e, st) {
            _log.fine(
                'Failed to compute PrevLayerTime from layer change: $e', e, st);
          }
          // Prefer the raw NanoDLP `PrevLayerTime` when present. Some adapters
          // expose this field with differing units/format, so parse it first
          // and fall back to the model-normalized `prev_layer_seconds` when
          // the raw key is absent.
          try {
            final maybePrevRaw =
                raw['PrevLayerTime'] ?? raw['prev_layer_seconds'];
            if (maybePrevRaw != null) {
              if (maybePrevRaw is num) {
                final n = maybePrevRaw.toDouble();
                if (n >= 1e9) {
                  // nanoseconds -> microseconds
                  final micros = (n / 1000).round();
                  _prevLayerDuration = Duration(microseconds: micros);
                } else if (n >= 1e3) {
                  // already microseconds
                  _prevLayerDuration = Duration(microseconds: n.round());
                } else {
                  // seconds -> microseconds
                  _prevLayerDuration =
                      Duration(microseconds: (n * 1e6).round());
                }
              } else {
                final s = maybePrevRaw
                    .toString()
                    .trim()
                    .replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
                final asDouble = double.tryParse(s);
                if (asDouble != null) {
                  if (asDouble >= 1e9) {
                    final micros = (asDouble / 1000).round();
                    _prevLayerDuration = Duration(microseconds: micros);
                  } else if (asDouble >= 1e3) {
                    _prevLayerDuration =
                        Duration(microseconds: asDouble.round());
                  } else {
                    _prevLayerDuration =
                        Duration(microseconds: (asDouble * 1e6).round());
                  }
                } else {
                  // leave previous _prevLayerDuration unchanged when the raw
                  // value can't be parsed — prefer retaining the last-seen
                  // completed-layer time so the UI doesn't flash to N/A.
                }
              }
              try {
                // _log.fine('SSE PrevLayerTime raw value: $maybePrevRaw');
              } catch (_) {}
            } else if (parsed.prevLayerSeconds != null) {
              final micros = (parsed.prevLayerSeconds! * 1e6).round();
              _prevLayerDuration = Duration(microseconds: micros);
            } else {
              // Do not clear _prevLayerDuration when the payload omits the
              // PrevLayerTime field; keep the last known value until an
              // explicit reset occurs. This prevents flicker when some
              // NanoDLP snapshots omit the key intermittently.
            }
          } catch (e, st) {
            _log.warning('Error parsing PrevLayerTime (SSE)', e, st);
          }
          // While printing, prefer live LayerTime from analytics (if available)
          // as it represents the ongoing layer duration. If present, apply it
          // as the current layer duration and proxy it into _prevLayerDuration
          // so existing UI bindings continue to work.
          try {
            if (parsed.isPrinting && _analyticsProvider != null) {
              final lv = _analyticsProvider!.getLatestForKey('LayerTime');
              if (lv != null) {
                double? secs;
                if (lv is num) secs = lv.toDouble();
                secs ??= double.tryParse(lv.toString());
                if (secs != null) {
                  final micros = (secs * 1e6).round();
                  _currentLayerDuration = Duration(microseconds: micros);
                  // Proxy into prev-layer for UI simplicity during active print
                  _prevLayerDuration = _currentLayerDuration;
                  _log.finer(
                      'SSE LayerTime from analytics (ms): ${_currentLayerDuration!.inMilliseconds}');
                }
              }
            } else {
              _currentLayerDuration = null;
            }
          } catch (e, st) {
            _log.fine('Failed to read LayerTime from analytics', e, st);
          }
          // (previous snapshot removed) transitional clears now rely on the
          // parsed payload directly.

          // Lazy thumbnail acquisition (same rules as refresh)
          if (parsed.isPrinting &&
              _thumbnailBytes == null &&
              !_thumbnailReady) {
            final fileData = parsed.printData?.fileData;
            if (fileData != null) {
              final path = fileData.path;
              // Use empty string for default (root) directory. Previously we
              // used '/', which resulted in '/filename' being requested from
              // the API and caused thumbnail fetches to fail for root files.
              String subdir = '';
              if (path.contains('/')) {
                subdir = path.substring(0, path.lastIndexOf('/'));
              }
              try {
                final file = OrionApiFile(
                  path: path,
                  name: fileData.name,
                  parentPath: subdir,
                  lastModified: fileData.lastModified ?? 0,
                  locationCategory: fileData.locationCategory,
                );
                await _fetchAndHandleThumbnail(
                  location: fileData.locationCategory ?? 'Local',
                  subdirectory: subdir,
                  fileName: fileData.name,
                  file: file,
                  size: 'Large',
                );
              } catch (e, st) {
                _log.warning('Thumbnail fetch failed (SSE)', e, st);
                // Mark ready to avoid indefinite spinner when fetch errors
                _thumbnailReady = true;
              }
            }
          }

          _status = parsed;
          _error = null;
          _loading = false;
          _consecutiveErrors = 0;
          _pollIntervalSeconds = _minPollIntervalSeconds;
          // If we were previously awaiting a new print, consider the print
          // started as soon as the backend reports an active job (printing
          // or paused). Waiting for file metadata or thumbnails can cause
          // long spinners on some backends that populate those fields
          // asynchronously; prefer showing the status immediately and
          // update metadata when it becomes available.
          if (_awaitingNewPrintData) {
            _awaitingNewPrintData = false;
            _awaitingSince = null;
          }

          // Use model-level hints when available. The mapper/state-handler
          // may populate `cancel_latched` for NanoDLP and `finished` to
          // indicate an Idle snapshot that represents a completed job.
          // Prefer these hints over string-matching to avoid duplicating
          // backend-specific logic here.
          final cancelLatched = parsed.cancelLatched == true;
          final finishedHint = parsed.finished == true;
          final pauseLatched = parsed.pauseLatched == true;
          // Only mark transitional cancel when the canonical status or
          // the handler indicates an in-flight cancel (i.e. not an Idle
          // snapshot). If we observe an Idle snapshot that appears
          // canceled (cancel_latched + Idle), prefer the final canceled
          // state and clear the transitional flag so UI buttons enable.
          if (parsed.status == 'Canceling' ||
              (cancelLatched && parsed.status != 'Idle')) {
            _isCanceling = true;
          } else if (_isCanceling &&
              (parsed.isCanceled || finishedHint || parsed.status == 'Idle')) {
            _isCanceling = false;
          }

          if (pauseLatched || parsed.status == 'Pausing') {
            _isPausing = true;
          } else if (_isPausing && parsed.isPaused) {
            _isPausing = false;
          }
        } catch (e, st) {
          _log.warning('Failed to handle SSE payload', e, st);
        }
        if (!_disposed) notifyListeners();
      }, onError: (err, st) {
        _log.warning('SSE stream error, falling back to polling', err, st);
        _closeSse();
        if (!_disposed) _startPolling();
        // If we previously had a working SSE subscription, retry with
        // exponential backoff because we know the backend supported SSE.
        if (_sseEverConnected) {
          _sseConsecutiveErrors =
              min(_sseConsecutiveErrors + 1, _maxReconnectAttempts);
          final delaySec = _computeBackoff(_sseConsecutiveErrors,
              base: _sseReconnectBaseSeconds, max: _maxPollIntervalSeconds);
          _log.warning(
              'SSE stream error; scheduling reconnect in ${delaySec}s (attempt $_sseConsecutiveErrors)');
          _nextSseRetryAt = DateTime.now().add(Duration(seconds: delaySec));
          Future.delayed(Duration(seconds: delaySec), () {
            _nextSseRetryAt = null;
            if (!_sseConnected && !_disposed) _tryStartSse();
          });
        } else {
          // We never established SSE successfully. Decide whether to mark
          // SSE unsupported or to keep trying later. If polling is healthy
          // (no recent consecutive poll errors) then the server likely
          // doesn't support SSE and we should not keep retrying.
          // mark that we've attempted SSE (implicit via logs)
          if (_consecutiveErrors < _ssePollErrorThreshold) {
            _sseSupported = false;
            _log.info(
                'SSE appears unsupported (stream error while polling healthy); disabling SSE attempts');
          } else {
            // Polling currently unhealthy; we'll continue polling and let
            // refresh() attempt SSE after polls recover.
            _log.info(
                'SSE stream error while polls unhealthy; will retry SSE after poll recovery');
          }
        }
      }, onDone: () {
        _log.info('SSE stream closed by server; falling back to polling');
        _closeSse();
        if (!_disposed) _startPolling();
        if (_sseEverConnected) {
          _sseConsecutiveErrors =
              min(_sseConsecutiveErrors + 1, _maxReconnectAttempts);
          final delaySec = _computeBackoff(_sseConsecutiveErrors,
              base: _sseReconnectBaseSeconds, max: _maxPollIntervalSeconds);
          _log.warning(
              'SSE stream closed by server; scheduling reconnect in ${delaySec}s (attempt $_sseConsecutiveErrors)');
          _nextSseRetryAt = DateTime.now().add(Duration(seconds: delaySec));
          Future.delayed(Duration(seconds: delaySec), () {
            _nextSseRetryAt = null;
            if (!_sseConnected && !_disposed) _tryStartSse();
          });
        } else {
          // mark that we've attempted SSE (implicit via logs)
          if (_consecutiveErrors < _ssePollErrorThreshold) {
            _sseSupported = false;
            _log.info(
                'SSE appears unsupported (stream closed while polling healthy); disabling SSE attempts');
          } else {
            _log.info(
                'SSE closed while polls unhealthy; will retry SSE after poll recovery');
          }
        }
      }, cancelOnError: true);
    } catch (e, st) {
      _log.info('SSE subscription failed; using polling', e, st);
      _sseConnected = false;
      // mark that we've attempted SSE (implicit via logs)
      if (!_disposed) _startPolling();
      // If polling is healthy, the server likely doesn't support SSE;
      // otherwise schedule reconnects because network may be flaky.
      if (_consecutiveErrors < _ssePollErrorThreshold) {
        _sseSupported = false;
        _log.info(
            'SSE appears unsupported (subscription failed while polls healthy); disabling SSE attempts');
      } else {
        _sseConsecutiveErrors =
            min(_sseConsecutiveErrors + 1, _maxReconnectAttempts);
        final delaySec = _computeBackoff(_sseConsecutiveErrors,
            base: _sseReconnectBaseSeconds, max: _maxPollIntervalSeconds);
        _log.warning(
            'SSE subscription failed; scheduling reconnect in ${delaySec}s (attempt $_sseConsecutiveErrors)');
        _nextSseRetryAt = DateTime.now().add(Duration(seconds: delaySec));
        Future.delayed(Duration(seconds: delaySec), () {
          _nextSseRetryAt = null;
          if (!_sseConnected && !_disposed) _tryStartSse();
        });
      }
    }
  }

  void _closeSse() {
    _sseConnected = false;
    try {
      _sseStreamSub?.cancel();
    } catch (_) {}
    _sseStreamSub = null;
    // Event buffer removed; nothing to clear here.
  }

  bool _kinematicFetchInFlight = false;

  /// Enable or disable continuous kinematic polling.
  ///
  /// When enabled, kinematic status is polled every 500ms automatically.
  /// Use this for wizard screens that need to detect when homing/moving
  /// completes. When disabled (default), use [refreshKinematicStatus] to
  /// fetch status on-demand (e.g., after button presses).
  void setContinuousKinematicPolling(bool enabled) {
    if (_continuousKinematicPolling == enabled) return;
    _continuousKinematicPolling = enabled;
    _log.fine('Continuous kinematic polling: $enabled');
    if (enabled) {
      _startKinematicPolling();
    } else {
      _stopKinematicPolling();
    }
  }

  /// Whether continuous kinematic polling is currently enabled.
  bool get isContinuousKinematicPollingEnabled => _continuousKinematicPolling;

  void _startKinematicPolling() {
    if (_kinematicPollTimer != null || _disposed) return;
    _log.fine('Starting kinematic polling timer');
    // Fetch immediately, then on interval
    refreshKinematicStatus();
    _kinematicPollTimer =
        Timer.periodic(_kinematicPollInterval, (_) => refreshKinematicStatus());
  }

  void _stopKinematicPolling() {
    _kinematicPollTimer?.cancel();
    _kinematicPollTimer = null;
    _log.fine('Stopped kinematic polling timer');
  }

  /// Manually clears the homed status. This is useful when an emergency stop
  /// or other event is known to invalidate the homed state, even if the
  /// backend hasn't reported it yet.
  void clearHomedStatus() {
    if (_kinematicStatus != null) {
      _kinematicStatus = AthenaKinematicStatus(
        homed: false,
        offset: _kinematicStatus!.offset,
        position: _kinematicStatus!.position,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
  }

  /// Explicitly refresh kinematic status (Z position, offset, homed state).
  /// Call this after button presses that affect Z position instead of relying
  /// on continuous polling. Returns the updated status or null on error.
  Future<AthenaKinematicStatus?> refreshKinematicStatus(
      {int maxAttempts = 3}) async {
    if (_kinematicFetchInFlight || _disposed) return _kinematicStatus;
    _kinematicFetchInFlight = true;

    int attempts = 0;

    try {
      while (attempts < maxAttempts) {
        attempts++;
        try {
          final kinMap = await _client.getKinematicStatus();
          if (_disposed) return _kinematicStatus;

          if (kinMap != null) {
            final kin = AthenaKinematicStatus.fromJson(
                Map<String, dynamic>.from(kinMap));
            _kinematicStatus = kin;
            notifyListeners();
            return kin;
          }
          _log.warning(
              'Kinematic status fetch attempt $attempts/$maxAttempts returned null');
        } catch (e, st) {
          _log.warning(
              'Kinematic status fetch attempt $attempts/$maxAttempts failed',
              e,
              st);
        }

        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_disposed) return _kinematicStatus;
        }
      }

      _log.warning(
          'All $maxAttempts kinematic status fetch attempts failed; keeping last known status.');
      return _kinematicStatus;
    } finally {
      _kinematicFetchInFlight = false;
    }
  }

  /// Fetch the latest status snapshot from the backend. This method is
  /// re-entrancy guarded and performs the following at a high level:
  /// - parses the payload into `StatusModel`
  /// - updates thumbnails lazily
  /// - adjusts polling interval and backoff on success/failure
  /// - updates transitional flags (pause/cancel)
  Future<void> refresh({bool force = false}) async {
    if (_fetchInFlight) return; // simple re-entrancy guard
    _fetchInFlight = true;
    final startedAt = DateTime.now();
    // Snapshot fields to avoid emitting notifications on every successful
    // polling refresh when nothing meaningful changed. This reduces churn
    // for listeners (e.g., ConnectionErrorWatcher) in polling-only backends
    // like NanoDLP. Also snapshot transitional flags so clearing them will
    // reliably cause a UI update even when the backend payload is otherwise
    // identical.
    final prevError = _error;
    final prevConsecutive = _consecutiveErrors;
    final prevLoading = _loading;
    final prevSseSupported = _sseSupported;
    final prevIsPausing = _isPausing;
    final prevIsCanceling = _isCanceling;
    // Capture previous status JSON so we can detect meaningful payload changes
    // (e.g. z position, progress) and notify UI even if other counters are
    // unchanged. Use JSON encoding of the model's toJson for a stable compare.
    final prevStatusJson = _status?.toJson();
    // Helper to compute a small fingerprint capturing the fields that
    // usually change while a print is active. This avoids noisy full-JSON
    // comparisons and ensures the UI updates when z/progress/layer change.
    String fingerprint(StatusModel? s) {
      if (s == null) return '';
      final z = s.physicalState.z.toStringAsFixed(3);
      final layer = s.layer?.toString() ?? '';
      final total = s.printData?.layerCount.toString() ?? '';
      final paused = s.isPaused ? '1' : '0';
      final status = s.status;
      return '$status|$paused|$layer|$total|$z';
    }

    final prevFingerprint = fingerprint(_status);
    bool statusChangedByFingerprint = false;
    try {
      // If a backoff is active (we've scheduled a delayed reconnect), skip
      // refresh attempts unless explicitly forced. This prevents concurrent
      // overlapping retries while a backoff timer is running.
      if (!force && _backoffTimer != null) {
        _log.fine(
            'Skipping refresh because backoff timer is active (nextPollRetryAt=$_nextPollRetryAt)');
        _fetchInFlight = false;
        return;
      }
      final raw = await _client.getStatus();
      // Capture device message if present
      try {
        _deviceStatusMessage =
            (raw['device_status_message'] ?? raw['Status'] ?? raw['status'])
                ?.toString();
      } catch (_) {
        _deviceStatusMessage = null;
      }
      // Capture resin temperature if available
      try {
        final maybeTemp = raw['resin'] ??
            raw['Resin'] ??
            raw['resin_temperature'] ??
            raw['ResinTemperature'];
        int? parsedTemp;
        if (maybeTemp == null) {
          parsedTemp = null;
        } else if (maybeTemp is num) {
          parsedTemp = maybeTemp.toInt();
        } else {
          final s = maybeTemp
              .toString()
              .trim()
              .toLowerCase()
              .replaceAll('°', '')
              .replaceAll('c', '')
              .trim();
          final numStr = s.replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
          parsedTemp = double.tryParse(numStr)?.round() ?? int.tryParse(numStr);
        }
        _resinTemperature = parsedTemp;
      } catch (_) {
        // ignore
      }
      // Capture CPU temperature from `temp` field if present.
      try {
        final maybeCpu = raw['temp'] ?? raw['Temp'] ?? raw['cpu_temp'];
        double? parsedCpu;
        if (maybeCpu == null) {
          parsedCpu = null;
        } else if (maybeCpu is num) {
          parsedCpu = maybeCpu.toDouble();
        } else {
          final s = maybeCpu
              .toString()
              .trim()
              .toLowerCase()
              .replaceAll('°', '')
              .replaceAll('c', '')
              .trim();
          final numStr = s.replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
          parsedCpu = double.tryParse(numStr);
        }
        _cpuTemperature = parsedCpu;
      } catch (_) {
        // ignore
      }
      // PrevLayerTime parsing will be handled after parsing StatusModel so
      // we can prefer the model's normalized 'prev_layer_seconds' when present.
      // Capture CPU temperature from `temp` field if present.
      try {
        final maybeCpu = raw['temp'] ?? raw['Temp'] ?? raw['cpu_temp'];
        double? parsedCpu;
        if (maybeCpu == null) {
          parsedCpu = null;
        } else if (maybeCpu is num) {
          parsedCpu = maybeCpu.toDouble();
        } else {
          final s = maybeCpu
              .toString()
              .trim()
              .toLowerCase()
              .replaceAll('°', '')
              .replaceAll('c', '')
              .trim();
          final numStr = s.replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
          parsedCpu = double.tryParse(numStr);
        }
        _cpuTemperature = parsedCpu;
      } catch (_) {
        // ignore
      }
      // UV / outside temperature is sourced from NanoDLP analytics.
      // Consumers should query AnalyticsProvider.getLatestForKey('TemperatureOutside').
      final parsed = StatusModel.fromJson(raw);

      // Compute prev-layer time from observed layer changes when the
      // backend does not include PrevLayerTime frequently. This is a
      // best-effort heuristic: when we observe the layer number change
      // (increment), record the time delta as the previous-layer duration.
      try {
        final now = DateTime.now();
        final observedLayer = parsed.layer;
        if (observedLayer != null) {
          if (_lastObservedLayer == null) {
            _lastObservedLayer = observedLayer;
            _lastObservedLayerTime = now;
          } else if (observedLayer != _lastObservedLayer) {
            // If layer increased, compute delta; if it decreased or reset
            // (e.g. new job), just re-seed the timestamp.
            if (observedLayer > (_lastObservedLayer ?? -999999)) {
              final prevTime = _lastObservedLayerTime ?? now;
              final delta = now.difference(prevTime);
              // Only accept reasonable durations (e.g., >0s and <24h)
              if (delta.inSeconds > 0 && delta.inHours < 24) {
                _prevLayerDuration = delta;
                _log.finer(
                    'Computed PrevLayerTime from layer change (ms): ${_prevLayerDuration!.inMilliseconds}');
              }
            }
            _lastObservedLayer = observedLayer;
            _lastObservedLayerTime = now;
          }
        }
      } catch (e, st) {
        _log.fine(
            'Failed to compute PrevLayerTime from layer change: $e', e, st);
      }
      // Prefer model-level prev-layer seconds when available. Fallback to
      // raw keys otherwise (supports nanoseconds, microseconds, seconds).
      try {
        final maybePrevRaw = raw['PrevLayerTime'] ?? raw['prev_layer_seconds'];
        if (maybePrevRaw != null) {
          if (maybePrevRaw is num) {
            final n = maybePrevRaw.toDouble();
            if (n >= 1e9) {
              // nanoseconds -> microseconds
              final micros = (n / 1000).round();
              _prevLayerDuration = Duration(microseconds: micros);
            } else if (n >= 1e3) {
              // already microseconds
              _prevLayerDuration = Duration(microseconds: n.round());
            } else {
              // seconds -> microseconds
              _prevLayerDuration = Duration(microseconds: (n * 1e6).round());
            }
          } else {
            final s = maybePrevRaw
                .toString()
                .trim()
                .replaceAll(RegExp(r'[^0-9+\-.eE]'), '');
            final asDouble = double.tryParse(s);
            if (asDouble != null) {
              if (asDouble >= 1e9) {
                final micros = (asDouble / 1000).round();
                _prevLayerDuration = Duration(microseconds: micros);
              } else if (asDouble >= 1e3) {
                _prevLayerDuration = Duration(microseconds: asDouble.round());
              } else {
                _prevLayerDuration =
                    Duration(microseconds: (asDouble * 1e6).round());
              }
            } else {
              // leave previous value unchanged when parsing fails
            }
          }
          try {
            // _log.fine('Poll PrevLayerTime raw value: $maybePrevRaw');
          } catch (_) {}
        } else if (parsed.prevLayerSeconds != null) {
          final micros = (parsed.prevLayerSeconds! * 1e6).round();
          _prevLayerDuration = Duration(microseconds: micros);
        } else {
          // Do not clear on absence; preserve last known PrevLayerTime.
        }
      } catch (e, st) {
        _log.warning('Error parsing PrevLayerTime (poll)', e, st);
      }
      // Prefer live LayerTime from analytics when printing
      try {
        if (parsed.isPrinting && _analyticsProvider != null) {
          final lv = _analyticsProvider!.getLatestForKey('LayerTime');
          if (lv != null) {
            double? secs;
            if (lv is num) secs = lv.toDouble();
            secs ??= double.tryParse(lv.toString());
            if (secs != null) {
              final micros = (secs * 1e6).round();
              _currentLayerDuration = Duration(microseconds: micros);
              _prevLayerDuration =
                  _currentLayerDuration; // proxy for UI during active print
              _log.fine(
                  'Poll LayerTime from analytics (ms): ${_currentLayerDuration!.inMilliseconds}');
            }
          }
        } else {
          _currentLayerDuration = null;
        }
      } catch (e, st) {
        _log.fine('Failed to read LayerTime from analytics (poll)', e, st);
      }
      // Compute fingerprint difference to detect meaningful changes that
      // should update the UI (z/layer/progress/etc.). This allows the
      // UI to update every poll while printing without requiring full JSON
      // equality checks that can hide small numeric changes.
      final nowFingerprint = fingerprint(parsed);
      statusChangedByFingerprint = prevFingerprint != nowFingerprint;
      // If a print is active (printing or paused) treat the poll as a
      // meaningful update so the UI refreshes every interval. Some
      // NanoDLP installs report minimal numeric changes that may be lost
      // by strict comparisons; forcing updates during active prints keeps
      // the UI responsive and in sync with the device.
      // PrevLayerTime parsing deferred until after we've parsed the model
      // so we can prefer the model's normalized value when available.
      if (parsed.isPrinting || parsed.isPaused) {
        statusChangedByFingerprint = true;
      }
      // Transitional clears will be based on the freshly parsed payload.

      // Attempt lazy thumbnail acquisition (only while printing and not yet fetched)
      if (parsed.isPrinting && _thumbnailBytes == null && !_thumbnailReady) {
        final fileData = parsed.printData?.fileData;
        if (fileData != null) {
          final path = fileData.path;
          // Use empty string for default (root) directory to match how
          // ThumbnailUtil expects an absent subdirectory.
          String subdir = '';
          if (path.contains('/')) {
            subdir = path.substring(0, path.lastIndexOf('/'));
          }
          try {
            final file = OrionApiFile(
              path: path,
              name: fileData.name,
              parentPath: subdir,
              lastModified: fileData.lastModified ?? 0,
              locationCategory: fileData.locationCategory,
            );
            await _fetchAndHandleThumbnail(
              location: fileData.locationCategory ?? 'Local',
              subdirectory: subdir,
              fileName: fileData.name,
              file: file,
              size: 'Large',
            );
          } catch (e, st) {
            _log.warning('Thumbnail fetch failed', e, st);
            // Even on failure we mark ready to avoid indefinite spinner.
            _thumbnailReady = true;
          }
        }
      }
      // NOTE: We no longer mark thumbnail ready when not printing; we explicitly
      // wait for an active job (printing/paused) so a reprint of the same file
      // still forces a clean spinner until the job restarts.

      _status = parsed;
      // Kinematic status (Z position, offset, homed) is not polled
      // continuously to reduce backend load. Screens that need it should call
      // refreshKinematicStatus() explicitly (e.g. after button presses).
      _error = null;
      _loading = false;
      _everHadSuccessfulStatus = true;

      // Successful refresh -> shorten polling interval
      _pollIntervalSeconds = _minPollIntervalSeconds;
      // Reset polling error counter; when polls are healthy we may try to
      // opportunistically establish an SSE subscription.
      final wasErroring = _consecutiveErrors > 0;
      _consecutiveErrors = 0;
      if (wasErroring) {
        _log.fine('Status refresh succeeded; consecutive error counter reset');
      }
      if (wasErroring && !_sseConnected && !_disposed) {
        // Defer SSE attempt slightly so any racing logic in _tryStartSse can
        // act after the current refresh completes.
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!_sseConnected && !_disposed) _tryStartSse();
        });
      }

      if (_awaitingNewPrintData) {
        final timedOut = _awaitingSince != null &&
            DateTime.now().difference(_awaitingSince!) > _awaitingTimeout;
        // If backend reports active printing/paused we clear awaiting early
        // (do not strictly require file metadata or thumbnail). Additionally,
        // if the backend reports a finished snapshot (idle with layer data)
        // or a canceled snapshot we should also clear awaiting so the UI
        // doesn't remain stuck on a spinner for backends (like NanoDLP)
        // that may briefly lose the 'printing' flag during transition.
        if (newPrintReady ||
            parsed.isPrinting ||
            parsed.isPaused ||
            // Treat a finished snapshot (idle but with layers) as valid
            // to clear awaiting so the UI can present the final state.
            (parsed.isIdle && parsed.layer != null) ||
            // Canceled snapshots should also clear awaiting.
            parsed.isCanceled ||
            timedOut) {
          _awaitingNewPrintData = false;
          _awaitingSince = null;
        }
      }

      // Clear transitional flags when the backend's paused/canceled state
      // changes compared to our previous snapshot. Prefer model-level hints
      // `cancelLatched` and `finished` provided by the mapper/state-handler
      // so adapter-specific semantics stay in the adapter layer.
      final cancelLatched = parsed.cancelLatched == true;
      final finishedHint = parsed.finished == true;
      final pauseLatched = parsed.pauseLatched == true;
      // Only mark transitional cancel when the canonical status or
      // the handler indicates an in-flight cancel (i.e. not an Idle
      // snapshot). If we observe an Idle snapshot that appears
      // canceled (cancel_latched + Idle), prefer the final canceled
      // state and clear the transitional flag so UI buttons enable.
      if (parsed.status == 'Canceling' ||
          (cancelLatched && parsed.status != 'Idle')) {
        _isCanceling = true;
      } else if (_isCanceling &&
          (parsed.isCanceled || finishedHint || parsed.status == 'Idle')) {
        _isCanceling = false;
      }

      if (pauseLatched || parsed.status == 'Pausing') {
        _isPausing = true;
      } else if (_isPausing && parsed.isPaused) {
        _isPausing = false;
      }
    } catch (e, st) {
      _log.severe('Status refresh failed', e, st);
      _error = e;
      _loading = false;
      // On failure, increase consecutive error count and back off polling
      _consecutiveErrors = min(_consecutiveErrors + 1, _maxReconnectAttempts);
      // Keep backoff short until we've ever seen a successful status so the
      // startup experience remains responsive. After the first success we
      // revert to the normal ramp-to-60s behavior for subsequent failures.
      final maxBackoff = _everHadSuccessfulStatus ? _maxPollIntervalSeconds : 5;
      final backoff = _computeBackoff(_consecutiveErrors,
          base: _minPollIntervalSeconds, max: maxBackoff);
      _pollIntervalSeconds = backoff;
      _nextPollRetryAt = DateTime.now().add(Duration(seconds: backoff));
      _log.fine(
          'Scheduling poll backoff for ${backoff}s (nextPollRetryAt=$_nextPollRetryAt)');

      // Cancel any existing backoff timer and schedule a single timer that
      // will restart polling when it expires. Mark backoff active while the
      // timer is running so other refresh() calls can skip attempting work.
      try {
        _backoffTimer?.cancel();
      } catch (_) {}
      _backoffTimer = Timer(Duration(seconds: backoff), () {
        _nextPollRetryAt = null;
        try {
          _backoffTimer = null;
        } catch (_) {}
        _log.fine('Backoff expired; attempting to restart polling');
        if (!_sseConnected && !_disposed) _startPolling();
      });

      // Immediately stop the current polling loop so backoff is effective
      // right away.
      _polling = false;
      final elapsed = DateTime.now().difference(startedAt);
      final millis = elapsed.inMilliseconds;
      final elapsedStr = millis >= 1000
          ? '${(millis / 1000).toStringAsFixed(1)}s'
          : '${millis}ms';
      _log.warning(
          'Status refresh failed after $elapsedStr; backing off polling for ${_pollIntervalSeconds}s (attempt $_consecutiveErrors)');
    } finally {
      _fetchInFlight = false;
      // The initial attempt is finished once we've done at least one fetch
      // (success or failure). Clear the flag so UI can dismiss any startup
      // overlay.
      if (_initialAttemptInProgress) {
        _initialAttemptInProgress = false;
      }
      if (!_disposed) {
        // Only notify listeners if one of the meaningful observable fields
        // actually changed. This avoids spamming watchers with identical
        // state on each poll when the backend is healthy. Additionally,
        // compare the previous status model JSON so UI will update when
        // backend fields (z/progress/layer) change between polls.
        final nowError = _error;
        final nowConsecutive = _consecutiveErrors;
        final nowLoading = _loading;
        final nowSseSupported = _sseSupported;
        final nowIsPausing = _isPausing;
        final nowIsCanceling = _isCanceling;
        final nowStatusJson = _status?.toJson();
        // Prefer fingerprint-based change detection for performance and to
        // ensure per-second updates while printing. Fall back to full JSON
        // comparison if necessary.
        bool statusChanged = statusChangedByFingerprint;
        if (!statusChanged) {
          try {
            final p = json.encode(prevStatusJson);
            final n = json.encode(nowStatusJson);
            statusChanged = p != n;
          } catch (_) {
            statusChanged = true;
          }
        }

        var shouldNotify = (prevError != nowError) ||
            (prevConsecutive != nowConsecutive) ||
            (prevLoading != nowLoading) ||
            (prevSseSupported != nowSseSupported) ||
            (prevIsPausing != nowIsPausing) ||
            (prevIsCanceling != nowIsCanceling) ||
            statusChanged;
        // For polling-only backends (no SSE support), ensure active prints
        // still trigger regular UI updates each poll interval.
        try {
          final isPollingOnly =
              !_backendSupports(BackendCapabilities.supportsSseStatusStream);
          if (!shouldNotify &&
              isPollingOnly &&
              (_status?.isPrinting == true || _status?.isPaused == true)) {
            shouldNotify = true;
          }
        } catch (_) {
          // If config read fails, don't change shouldNotify.
        }
        if (shouldNotify) notifyListeners();
      }
    }
  }

  int _computeBackoff(int attempts, {required int base, required int max}) {
    // Exponential: base * 2^attempts with cap, plus random jitter up to 50%.
    final raw = base * pow(2, attempts);
    int secs = raw.toInt();
    if (secs > max) secs = max;
    // Add jitter up to 50% of the computed backoff to avoid thundering herd.
    final rand = Random();
    final jitter = rand.nextInt((secs ~/ 2) + 1);
    secs = secs + jitter;
    if (secs > max) secs = max;
    return secs;
  }

  // --- Derived UI convenience ---
  String get displayStatus =>
      _status?.displayLabel(
        transitionalCancel: _isCanceling,
        transitionalPause: _isPausing,
      ) ??
      'Unknown';

  double get progress => _status?.progress ?? 0.0;

  Color statusColor(BuildContext context) =>
      _status?.statusColor(
        context,
        transitionalPause: _isPausing,
        transitionalCancel: _isCanceling,
      ) ??
      Colors.grey;

  // --- Actions ---
  /// Toggle between pause and resume depending on current backend state.
  Future<void> pauseOrResume() async {
    final s = _status;
    if (s == null) return;
    if (s.isPaused) {
      // resume
      if (_isPausing) return; // already in transition
      _isPausing = true;
      notifyListeners();
      try {
        await _client.resumePrint();
        // Clear transitional flag proactively on success so the UI doesn't
        // remain in a spinning 'resuming' state while the backend takes a
        // moment to reflect the new paused=false status.
        _isPausing = false;
        if (!_disposed) notifyListeners();
      } catch (e, st) {
        _log.severe('Resume failed', e, st);
        _isPausing = false; // revert transitional flag
      } finally {
        refresh();
      }
    } else {
      // pause
      if (_isPausing) return;
      _isPausing = true;
      notifyListeners();
      try {
        await _client.pausePrint();
      } catch (e, st) {
        _log.severe('Pause failed', e, st);
        _isPausing = false;
      } finally {
        refresh();
      }
    }
  }

  /// Initiate print cancel action. Transitional flag cleared once backend reflects.
  Future<void> cancel() async {
    if (_isCanceling) return;
    _isCanceling = true;
    notifyListeners();
    try {
      await _client.cancelPrint();
    } catch (e, st) {
      _log.severe('Cancel failed', e, st);
      // keep flag (still canceling) to avoid flicker; will clear when API reflects
    } finally {
      refresh();
    }
  }

  /// Clear current status so UI shows a neutral/loading state prior to the
  /// next print starting. Polling continues and will repopulate on refresh.
  /// Reset the provider to a neutral/loading state. Optionally provide an
  /// Clears any error state, allowing the connection error dialog to be
  /// dismissed. Useful when performing operations (like updates) where
  /// connection loss is expected.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Pauses polling and SSE, useful during system updates where connection
  /// loss is expected and error dialogs should not be shown.
  void pausePolling() {
    _polling = false;
    _timer?.cancel();
    _timer = null;
    _sseStreamSub?.cancel();
    _sseStreamSub = null;
    _sseConnected = false;
    _error = null;
    notifyListeners();
  }

  /// Resumes polling after being paused.
  void resumePolling() {
    if (!_polling && !_disposed) {
      _startPolling();
    }
  }

  /// Enter standby mode: switch to slow polling (30s) instead of pausing
  /// entirely, so we can still detect remotely-started prints.
  void enterStandbyMode() {
    if (_standbyMode) return;
    _standbyMode = true;
    // Tear down SSE to save resources; fall back to slow polling.
    _sseStreamSub?.cancel();
    _sseStreamSub = null;
    _sseConnected = false;
    _pollIntervalSeconds = _standbyPollIntervalSeconds;
    // Restart polling loop with the new interval if not already running.
    if (!_polling && !_disposed) {
      _startPolling();
    }
  }

  /// Exit standby mode: restore normal polling interval and reconnect SSE.
  void exitStandbyMode() {
    if (!_standbyMode) return;
    _standbyMode = false;
    _pollIntervalSeconds = _minPollIntervalSeconds;
    // Reconnect SSE for real-time updates.
    if (!_disposed) {
      _tryStartSse();
    }
  }

  /// initial thumbnail (bytes) and file path or plate id so the UI can
  /// immediately render a cached preview while the backend populates
  /// active job metadata. This is useful when starting a print from the
  /// DetailsScreen where the thumbnail is already available.
  void resetStatus({
    Uint8List? initialThumbnailBytes,
    String? initialFilePath,
    int? initialPlateId,
  }) {
    _log.fine('resetStatus called — purging stale status and thumbnails');
    // Purge cached status and transient state immediately so UI shows a
    // clean spinner instead of stale values while we fetch fresh status.
    _status = null;
    _thumbnailBytes = initialThumbnailBytes;
    _thumbnailReady = initialThumbnailBytes != null;
    _error = null;
    _loading = true; // so consumer screens can show a spinner if they mount
    // Clear transitional flags so UI isn't stuck in a paused/canceling state
    // when starting a fresh session.
    _isCanceling = false;
    _isPausing = false;
    _awaitingNewPrintData = true; // begin awaiting active print
    _awaitingSince = DateTime.now();
    // Clear thumbnail retry counters for fresh session
    _thumbnailRetries.clear();
    // Clear any previously-observed layer timing so we don't show stale values
    // when starting a fresh print session.
    _prevLayerDuration = null;
    _currentLayerDuration = null;
    _lastObservedLayer = null;
    _lastObservedLayerTime = null;
    // Ensure the UI shows a minimum spinner duration so the user perceives
    // a loading phase even if the backend responds very quickly.
    _minSpinnerUntil = DateTime.now().add(const Duration(seconds: 2));
    notifyListeners();

    // Schedule a notify when the minimum spinner window expires so UI can
    // re-evaluate its conditions (refresh() may complete earlier and
    // already clear loading). The delayed callback is guarded by the
    // provider's disposed flag.
    Future.delayed(const Duration(seconds: 2), () {
      if (_disposed) return;
      _minSpinnerUntil = null;
      // Notify listeners so consumers can dismiss the forced spinner.
      notifyListeners();
    });

    // Kick off an immediate refresh to populate fresh status. If a fetch
    // is already in flight, refresh() will no-op via its guard.
    try {
      // Fire-and-forget; refresh handles its own errors and notifications.
      Future.microtask(() => refresh());
    } catch (_) {
      // ignore — refresh has internal error handling
    }
  }

  Future<void> _fetchAndHandleThumbnail({
    required String location,
    required String subdirectory,
    required String fileName,
    required OrionApiFile file,
    String size = 'Large',
  }) async {
    final pathKey = file.path;
    try {
      bool bypassCache = false;
      try {
        final meta =
            await BackendService().getFileMetadata(location, file.path);
        final plateId = meta['plate_id'] as int?;
        if (plateId == 0) {
          bypassCache = true;
        }
      } catch (_) {
        // ignore metadata failures; fall back to cached path
      }

      final bytes = bypassCache
          ? await ThumbnailUtil.extractThumbnailBytes(
              location,
              subdirectory,
              fileName,
              size: size,
            )
          : await ThumbnailCache.instance.getThumbnail(
              location: location,
              subdirectory: subdirectory,
              fileName: fileName,
              file: file,
              size: size,
            );

      if (bytes == null) {
        _thumbnailBytes = null;
        _thumbnailReady = true;
        return;
      }

      final placeholder = NanoDlpThumbnailGenerator.generatePlaceholder(
          NanoDlpThumbnailGenerator.largeWidth,
          NanoDlpThumbnailGenerator.largeHeight);
      final isPlaceholder =
          bytes.length == placeholder.length && _bytesEqual(bytes, placeholder);

      // If we already have a real thumbnail cached in provider, keep it.
      if (isPlaceholder) {
        if (_thumbnailBytes != null &&
            !_bytesEqual(_thumbnailBytes!, placeholder)) {
          _thumbnailReady = true;
          return;
        }

        final tried = (_thumbnailRetries[pathKey] ?? 0);
        if (tried < _maxThumbnailRetries) {
          _thumbnailRetries[pathKey] = tried + 1;
          final fresh = await ThumbnailCache.instance.getThumbnail(
            location: location,
            subdirectory: subdirectory,
            fileName: fileName,
            file: file,
            size: size,
            forceRefresh: true,
          );
          if (fresh != null) {
            final freshIsPlaceholder = fresh.length == placeholder.length &&
                _bytesEqual(fresh, placeholder);
            if (!freshIsPlaceholder) {
              _thumbnailBytes = fresh;
              _thumbnailReady = true;
              return;
            }
          }
          // keep trying on subsequent polls; don't mark ready yet
          return;
        }

        // Exhausted retries: accept placeholder if we don't have a real one
        if (_thumbnailBytes == null ||
            _bytesEqual(_thumbnailBytes!, placeholder)) {
          _thumbnailBytes = bytes;
        }
        _thumbnailReady = true;
        return;
      }

      // Normal: use the non-placeholder bytes
      _thumbnailBytes = bytes;
      _thumbnailReady = true;
      return;
    } catch (e, st) {
      _log.warning('Thumbnail fetch failed', e, st);
      _thumbnailBytes = null;
      _thumbnailReady = true;
      return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    try {
      _backoffTimer?.cancel();
    } catch (_) {}
    _stopKinematicPolling();
    super.dispose();
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.lengthInBytes != b.lengthInBytes) return false;
  for (int i = 0; i < a.lengthInBytes; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
