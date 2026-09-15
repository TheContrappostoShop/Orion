/*
* Orion - Backend Service
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

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/athena_iot/athena_iot_client.dart';
import 'package:orion/backend_service/athena_iot/models/athena_feature_flags.dart';
import 'package:orion/backend_service/athena_iot/models/athena_printer_data.dart';
import 'package:orion/backend_service/athena_iot/models/force_leveling_workflow.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/backend_service/backend_registry.dart';
import 'package:orion/backend_service/odyssey/odyssey_http_client.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_simulated_client.dart';
import 'package:orion/util/orion_config.dart';

/// BackendService is a small façade that selects a concrete
/// `BackendClient` implementation at runtime. This centralizes the
/// point where an alternative backend implementation (different API)
/// can be swapped in without changing providers or UI code.
///
/// As of Phase 0 refactoring, backends are registered via BackendRegistry
/// and selected at runtime based on configuration, eliminating scattered
/// type checks and direct client instantiation throughout the codebase.
class BackendService implements BackendClient {
  static final _log = Logger('BackendService');
  static BackendService? _sharedInstance;

  /// Simulated corner probe index, cycles 0..3 on each `probe_corner` call.
  static int _simCornerIndex = -1;
  static bool _sharedListenerRegistered = false;

  BackendClient _delegate;

  /// Default constructor: picks the concrete implementation based on
  /// configuration (or defaults to the HTTP adapter). The selected
  /// delegate may be reloaded later by calling [reloadFromConfig].
  ///
  /// By default this returns a shared singleton instance to avoid repeatedly
  /// constructing backend clients in call sites that invoke `BackendService()`
  /// inside polling loops or one-shot helper calls.
  factory BackendService({BackendClient? delegate}) {
    // Explicit delegate injection should create an isolated instance.
    if (delegate != null) {
      return BackendService._internal(
        delegate: delegate,
        registerSharedConfigListener: false,
      );
    }

    return _sharedInstance ??= BackendService._internal(
      delegate: _chooseFromConfig(),
      registerSharedConfigListener: true,
    );
  }

  BackendService._internal({
    BackendClient? delegate,
    required bool registerSharedConfigListener,
  }) : _delegate = delegate ?? _chooseFromConfig() {
    if (registerSharedConfigListener) {
      _registerConfigListener();
    }
  }

  /// Replaces the delegate backing the shared instance ([BackendService]).
  ///
  /// Test-only hook: widget tests need the screens that call `BackendService()`
  /// directly to talk to a fake backend. Production code always selects the
  /// delegate from configuration.
  @visibleForTesting
  static void debugSetSharedDelegate(BackendClient delegate) {
    _sharedInstance ??= BackendService._internal(
      delegate: delegate,
      registerSharedConfigListener: false,
    );
    _sharedInstance!._delegate = delegate;
  }

  // Automatically reload the delegate when the on-disk config is updated.
  // We register a listener with OrionConfig so onboarding or settings
  // flows that call setString()/setFlag() cause the backend to re-evaluate.
  void _registerConfigListener() {
    if (_sharedListenerRegistered) return;
    OrionConfig.addChangeListener(_handleConfigChange);
    _sharedListenerRegistered = true;
  }

  void _handleConfigChange() {
    try {
      reloadFromConfig();
    } catch (_) {
      // ignore
    }
  }

  /// Dispose the backend service and remove any registered listeners.
  void dispose() {
    // The shared singleton intentionally keeps its listener for app lifetime.
    if (identical(this, _sharedInstance)) return;
    try {
      OrionConfig.removeChangeListener(_handleConfigChange);
    } catch (_) {}
  }

  /// Re-read configuration and pick a new backend implementation.
  ///
  /// This is useful when configuration (for example `orion.cfg` or
  /// `vendor.cfg`) has been updated after app startup and you need the
  /// BackendService to switch between real and simulated adapters.
  void reloadFromConfig() {
    try {
      _delegate = _chooseFromConfig();
    } catch (_) {
      // Keep the existing delegate on any error while reloading.
    }
  }

  static BackendClient _chooseFromConfig() {
    try {
      final cfg = OrionConfig();

      // Developer-mode simulated backend flag (developer.simulated = true)
      // Simulated client is still special-cased for testing.
      final simulated = cfg.getFlag('simulated', category: 'developer');
      if (simulated) {
        _log.info('Creating simulated NanoDLP client (developer mode)');
        return NanoDlpSimulatedClient();
      }

      // Use registry to select the backend ID and create client directly.
      final configuredBackend = cfg.getString('backend', category: 'advanced');
      final backendId =
          configuredBackend.isEmpty ? 'odyssey' : configuredBackend;
      final registry = BackendRegistry();
      final module = registry.getModule(backendId);

      if (module != null) {
        _log.info('Selected backend: $backendId from registry');
        return module.createClient();
      }

      _log.warning(
          'Backend module not registered: $backendId, falling back to Odyssey');
    } catch (e, st) {
      _log.warning('Error choosing backend from config', e, st);
    }

    // Fallback to Odyssey
    return OdysseyHttpClient();
  }

  // Forward all BackendClient methods to the selected delegate.
  @override
  Future<Map<String, dynamic>> listItems(
          String location, int pageSize, int pageIndex, String subdirectory) =>
      _delegate.listItems(location, pageSize, pageIndex, subdirectory);

  @override
  Future<bool> usbAvailable() => _delegate.usbAvailable();

  /// Invalidate cached file listings when supported by the backend.
  /// Call this when files may have been modified externally (e.g., deleted via WebUI).
  /// Backends that don't support caching (e.g., Odyssey) will no-op.
  void invalidateFilesCache() {
    // Check if current backend supports cache invalidation via registry.
    final cfg = OrionConfig();
    final configuredBackend = cfg.getString('backend', category: 'advanced');
    final backendId = configuredBackend.isEmpty ? 'odyssey' : configuredBackend;
    final registry = BackendRegistry();

    final supportsCaching = registry.supportsCapability(
            backendId, BackendCapabilities.supportsCacheInvalidation) ??
        false;

    if (!supportsCaching) {
      _log.fine('Backend $backendId does not support cache invalidation');
      return;
    }

    _delegate.invalidateCache();
    _log.fine('Invalidated backend cache for $backendId');
  }

  @override
  Future<Map<String, dynamic>> getFileMetadata(
          String location, String filePath) =>
      _delegate.getFileMetadata(location, filePath);

  @override
  Future<Map<String, dynamic>> getConfig() => _delegate.getConfig();

  @override
  Future<String> getBackendVersion() => _delegate.getBackendVersion();

  @override
  Future<Uint8List> getFileThumbnail(
          String location, String filePath, String size) =>
      _delegate.getFileThumbnail(location, filePath, size);

  @override
  Future<void> startPrint(String location, String filePath) =>
      _delegate.startPrint(location, filePath);

  @override
  Future<Map<String, dynamic>> deleteFile(String location, String filePath) =>
      _delegate.deleteFile(location, filePath);

  /// Import a file from USB/local storage to the backend's internal storage.
  ///
  /// This is only supported on backends that declare import capability.
  /// Check [supportsCapability] before calling to avoid errors.
  ///
  /// Returns the plate ID if successful, null if ID couldn't be determined.
  /// Throws UnsupportedError if backend doesn't support file import.
  @override
  Future<int?> importFile(FileImportRequest request) async {
    // Check if current backend supports file import via registry.
    final cfg = OrionConfig();
    final configuredBackend = cfg.getString('backend', category: 'advanced');
    final backendId = configuredBackend.isEmpty ? 'odyssey' : configuredBackend;

    final supportsImport =
        supportsCapability(BackendCapabilities.supportsImportFile);

    if (!supportsImport) {
      throw UnsupportedError(
          'File import is not supported by backend: $backendId');
    }

    return _delegate.importFile(request);
  }

  @override
  Future<void> invalidateCache() => _delegate.invalidateCache();

  @override
  Future<ResinSettings?> getResinSettings(int profileId) =>
      _delegate.getResinSettings(profileId);

  @override
  Future<void> saveResinExposure(int profileId, double normalCureTime) =>
      _delegate.saveResinExposure(profileId, normalCureTime);

  @override
  Future<void> saveResinSettings(int profileId, ResinSettings settings) =>
      _delegate.saveResinSettings(profileId, settings);

  /// Convenience method to check if the current backend supports a capability.
  /// Returns false if capability is not found or backend is not registered.
  bool supportsCapability(String capabilityName) {
    try {
      final cfg = OrionConfig();
      final configuredBackend = cfg.getString('backend', category: 'advanced');
      final backendId =
          configuredBackend.isEmpty ? 'odyssey' : configuredBackend;
      final registry = BackendRegistry();
      return registry.supportsCapability(backendId, capabilityName) ?? false;
    } catch (e) {
      _log.warning('Error checking capability: $capabilityName', e);
      return false;
    }
  }

  String _resolveAthenaBaseUrl() {
    try {
      final cfg = OrionConfig();
      final base = cfg.getString('nanodlp.base_url', category: 'advanced');
      final useCustom = cfg.getFlag('useCustomUrl', category: 'advanced');
      final custom = cfg.getString('customUrl', category: 'advanced');
      if (base.isNotEmpty) return base;
      if (useCustom && custom.isNotEmpty) return custom;
    } catch (_) {}
    return 'http://localhost';
  }

  AthenaIotClient? _createAthenaClient({Duration? requestTimeout}) {
    if (!supportsCapability(BackendCapabilities.supportsAthenaUpdates)) {
      return null;
    }
    final athenaBase = _resolveAthenaBaseUrl();
    return AthenaIotClient(athenaBase, requestTimeout: requestTimeout);
  }

  /// Fetch typed Athena printer_data via backend capability-gated access.
  Future<AthenaPrinterData?> getAthenaPrinterDataModel(
      {Duration? requestTimeout}) async {
    try {
      final client = _createAthenaClient(requestTimeout: requestTimeout);
      if (client == null) return null;
      return await client.getPrinterDataModel();
    } catch (e, st) {
      _log.warning('Failed to fetch Athena printer_data model', e, st);
      return null;
    }
  }

  /// Fetch typed Athena feature_flags via backend capability-gated access.
  Future<AthenaFeatureFlags?> getAthenaFeatureFlagsModel(
      {Duration? requestTimeout}) async {
    try {
      final client = _createAthenaClient(requestTimeout: requestTimeout);
      if (client == null) return null;
      return await client.getFeatureFlagsModel();
    } catch (e, st) {
      _log.warning('Failed to fetch Athena feature_flags model', e, st);
      return null;
    }
  }

  /// Fetch Athena printer_data through the backend façade.
  ///
  /// Returns an empty map when Athena updates are not supported or when
  /// data is temporarily unavailable.
  Future<Map<String, dynamic>> getAthenaPrinterData() async {
    try {
      final model = await getAthenaPrinterDataModel();
      return model?.toJson() ?? <String, dynamic>{};
    } catch (e, st) {
      _log.warning(
          'Failed to fetch Athena printer_data via BackendService', e, st);
      return <String, dynamic>{};
    }
  }

  Future<ForceLevelingWorkflowResponse> runForceLevelingWorkflow(
    String endpoint, {
    String? screenType,
    Duration? requestTimeout,
  }) async {
    // Simulated mode: return fake success data so devs can skip through the
    // workflow without a real printer or Athena connection.
    try {
      final cfg = OrionConfig();
      if (cfg.getFlag('simulated', category: 'developer')) {
        _log.info('Simulated force leveling workflow: endpoint=$endpoint');
        // Cycle through different Z values for corner probes so the deviation
        // is large enough (>0.1mm) to trigger the adjustment mode.
        const cornerZValues = [5.000, 5.030, 5.180, 5.210];
        late final double secondZ;
        if (endpoint == 'probe_corner') {
          // Use a static counter that cycles 0..3 so each of the 4 corner
          // probes gets a different Z value.
          _simCornerIndex = (_simCornerIndex + 1) % 4;
          secondZ = cornerZValues[_simCornerIndex];
        } else {
          secondZ = 5.0;
        }
        return ForceLevelingWorkflowResponse(
          result: true,
          error: '',
          machineHomed: true,
          measurements: ForceProbeMeasurements(
            firstStageTriggerZ: 10.0,
            firstStageTriggerForce: -15.0,
            firstStagePeakForce: -18.0,
            secondStageTriggerZ: secondZ,
            secondStageTriggerForce: -20.0,
            secondStagePeakForce: -22.0,
          ),
          zOffsetApplied:
              endpoint == 'probe_offset' || endpoint == 'probe_standardarm'
                  ? 0.5
                  : null,
          parkHeightMm: 150.0,
        );
      }
    } catch (_) {
      // Fall through to real backend if config can't be read.
    }

    if (!supportsCapability(BackendCapabilities.supportsForceLeveling)) {
      return const ForceLevelingWorkflowResponse(
        result: false,
        error: 'Force leveling is not supported by this backend.',
      );
    }

    try {
      final client = _createAthenaClient(requestTimeout: requestTimeout);
      if (client == null) {
        return const ForceLevelingWorkflowResponse(
          result: false,
          error: 'Athena IoT client is not available.',
        );
      }
      return await client.runForceLevelingWorkflow(endpoint,
          screenType: screenType);
    } catch (e, st) {
      _log.warning('Failed to run force leveling workflow: $endpoint', e, st);
      return ForceLevelingWorkflowResponse(
        result: false,
        error: e.toString(),
      );
    }
  }

  /// Show a corner alignment pattern on the projector via special screens.
  ///
  /// [location] must be one of: front-left, front-right, back-left, back-right.
  /// Returns `true` on success, `false` on failure or when Athena is unavailable.
  Future<bool> showSpecialScreenCorner(
    String location, {
    Duration? requestTimeout,
  }) async {
    try {
      final client = _createAthenaClient(requestTimeout: requestTimeout);
      if (client == null) return false;
      return await client.showCornerScreen(location);
    } catch (e, st) {
      _log.warning('Failed to show special screen corner: $location', e, st);
      return false;
    }
  }

  /// Show the center alignment pattern on the projector via special screens.
  /// Returns `true` on success, `false` on failure or when Athena is unavailable.
  Future<bool> showSpecialScreenCenter({Duration? requestTimeout}) async {
    try {
      final client = _createAthenaClient(requestTimeout: requestTimeout);
      if (client == null) return false;
      return await client.showCenterScreen();
    } catch (e, st) {
      _log.warning('Failed to show special screen center', e, st);
      return false;
    }
  }

  /// Turn off the projector's UV LED, hiding any active special screen.
  /// Returns `true` on success, `false` on failure or when Athena is unavailable.
  Future<bool> turnOffSpecialScreens({Duration? requestTimeout}) async {
    try {
      final client = _createAthenaClient(requestTimeout: requestTimeout);
      if (client == null) return false;
      return await client.uvledOff();
    } catch (e, st) {
      _log.warning('Failed to turn off special screens', e, st);
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getStatus() => _delegate.getStatus();

  @override
  Stream<Map<String, dynamic>> getStatusStream() => _delegate.getStatusStream();

  @override
  Future<List<Map<String, dynamic>>> getNotifications() =>
      _delegate.getNotifications();

  @override
  Future<Map<String, dynamic>?> getKinematicStatus() =>
      _delegate.getKinematicStatus();

  @override
  Future<void> disableNotification(int timestamp) =>
      _delegate.disableNotification(timestamp);

  @override
  Future<void> cancelPrint() => _delegate.cancelPrint();

  @override
  Future<void> pausePrint() => _delegate.pausePrint();

  @override
  Future<void> resumePrint() => _delegate.resumePrint();

  @override
  Future<Map<String, dynamic>> move(double height) => _delegate.move(height);

  @override
  Future<Map<String, dynamic>> moveDelta(double deltaMm) =>
      _delegate.moveDelta(deltaMm);

  @override
  Future<bool> canMoveToTop() => _delegate.canMoveToTop();

  @override
  Future<Map<String, dynamic>> moveToTop() => _delegate.moveToTop();

  @override
  Future<bool> canMoveToFloor() => _delegate.canMoveToFloor();

  @override
  Future<Map<String, dynamic>> moveToFloor() => _delegate.moveToFloor();

  @override
  Future<Map<String, dynamic>> manualCure(bool cure) =>
      _delegate.manualCure(cure);

  @override
  Future<Map<String, dynamic>> manualHome() => _delegate.manualHome();

  @override
  Future<Map<String, dynamic>> manualCommand(String command) =>
      _delegate.manualCommand(command);

  @override
  Future<Map<String, dynamic>> emergencyStop() => _delegate.emergencyStop();

  @override
  Future<void> displayTest(String test) => _delegate.displayTest(test);

  @override
  Future<Uint8List> getPlateLayerImage(int plateId, int layer) =>
      _delegate.getPlateLayerImage(plateId, layer);

  @override
  Future<List<Map<String, dynamic>>> getAnalytics(int n) =>
      _delegate.getAnalytics(n);

  @override
  Future<dynamic> getAnalyticValue(int id) => _delegate.getAnalyticValue(id);

  @override
  Future<Map<String, dynamic>> getMachine() => _delegate.getMachine();

  @override
  Future<int?> getDefaultProfileId() => _delegate.getDefaultProfileId();

  @override
  Future<Map<String, dynamic>> editProfile(
      int id, Map<String, dynamic> fields) async {
    try {
      return await _delegate.editProfile(id, fields);
    } catch (e, _) {
      // Treat backend-specific errors as empty result so callers don't crash
      return {};
    }
  }

  /// Clone a profile. Failures are propagated on purpose: creating a profile
  /// is a user-visible action and the UI must be able to report a failure
  /// rather than claim success.
  @override
  Future<Map<String, dynamic>> cloneProfile(
          int sourceId, Map<String, dynamic> fields) =>
      _delegate.cloneProfile(sourceId, fields);

  @override
  Future<Map<String, dynamic>> getProfileJson(int id) async {
    try {
      return await _delegate.getProfileJson(id);
    } catch (e, _) {
      // Don't let backend-specific fetch failures throw into UI code —
      // treat as unsupported/empty result.
      // Note: individual delegates should log details; keep this quiet
      // at info level to avoid spamming.
      return {};
    }
  }

  @override
  Future<void> setDefaultProfileId(int id) => _delegate.setDefaultProfileId(id);

  @override
  Future<dynamic> tareForceSensor() => _delegate.tareForceSensor();

  @override
  Future<dynamic> updateBackend() => _delegate.updateBackend();

  @override
  Future setChamberTemperature(double temperature) =>
      _delegate.setChamberTemperature(temperature);

  @override
  Future setVatTemperature(double temperature) =>
      _delegate.setVatTemperature(temperature);

  @override
  Future getChamberTemperature() => _delegate.getChamberTemperature();

  @override
  Future getVatTemperature() => _delegate.getVatTemperature();

  @override
  Future<bool> isChamberTemperatureControlEnabled() {
    return _delegate.isChamberTemperatureControlEnabled();
  }

  @override
  Future<bool> isVatTemperatureControlEnabled() {
    return _delegate.isVatTemperatureControlEnabled();
  }

  @override
  Future<void> preheatAndMix(double temperature) =>
      _delegate.preheatAndMix(temperature);

  @override
  Future<void> preheatAndMixStandalone() => _delegate.preheatAndMixStandalone();

  @override
  Future<String?> getCalibrationImageUrl(int modelId) =>
      _delegate.getCalibrationImageUrl(modelId);

  @override
  Future<List<Map<String, dynamic>>> getCalibrationModels() =>
      _delegate.getCalibrationModels();

  @override
  Future<bool> startCalibrationPrint({
    required int calibrationModelId,
    required List<double> exposureTimes,
    required int profileId,
  }) =>
      _delegate.startCalibrationPrint(
        calibrationModelId: calibrationModelId,
        exposureTimes: exposureTimes,
        profileId: profileId,
      );

  @override
  Future<double?> getSlicerProgress() => _delegate.getSlicerProgress();

  @override
  Future<bool?> isCalibrationPlateProcessed() =>
      _delegate.isCalibrationPlateProcessed();

  @override
  Future<bool> resetZOffset() => _delegate.resetZOffset();

  @override
  Future<bool> setZOffset(double offset) => _delegate.setZOffset(offset);
}
