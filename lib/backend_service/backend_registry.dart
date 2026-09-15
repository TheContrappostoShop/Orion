/*
* Orion - Backend Registry
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

import 'package:logging/logging.dart';
import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/athena_iot/athena_iot_submodule.dart';
import 'package:orion/backend_service/nanodlp/nanodlp_module.dart';
import 'package:orion/backend_service/odyssey/odyssey_module.dart';

// Export all available backend modules so they're accessible through this
// registry import. When adding a new backend, add its module export here
// and register it in registerBuiltInModules() below.
export 'package:orion/backend_service/nanodlp/nanodlp_module.dart';
export 'package:orion/backend_service/odyssey/odyssey_module.dart';
export 'package:orion/backend_service/athena_iot/athena_iot_submodule.dart';

/// Canonical backend identifiers.
class BackendIds {
  static const nanodlp = 'nanodlp';
  static const odyssey = 'odyssey';
}

/// Canonical backend capability keys.
class BackendCapabilities {
  static const supportsImportFile = 'supportsImportFile';
  static const supportsLocalFilesProvider = 'supportsLocalFilesProvider';
  static const supportsProfiles = 'supportsProfiles';
  static const supportsProfileEdit = 'supportsProfileEdit';
  static const supportsCalibration = 'supportsCalibration';
  static const supportsAthena = 'supportsAthena';
  static const supportsAthenaUpdates = 'supportsAthenaUpdates';
  static const supportsAthenaFeatureFlags = 'supportsAthenaFeatureFlags';
  static const supportsForceLeveling = 'supportsForceLeveling';
  static const supportsVatTemperature = 'supportsVatTemperature';
  static const supportsChamberTemperature = 'supportsChamberTemperature';
  static const supportsNotifications = 'supportsNotifications';
  static const supportsAnalytics = 'supportsAnalytics';
  static const supportsCacheInvalidation = 'supportsCacheInvalidation';
  static const supportsSseStatusStream = 'supportsSseStatusStream';
  static const supportsRgbLighting = 'supportsRgbLighting';
}

/// Canonical backend submodule identifiers.
class BackendSubmodules {
  static const athenaIot = 'athena_iot';
}

/// Service submodules (e.g., Athena IoT, file import, analytics) that can be
/// optionally loaded and shared across multiple backends.
abstract class BackendSubmodule {
  /// Unique identifier for this submodule (e.g., 'athena_iot', 'file_import').
  String get id;

  /// Human-readable name for logging/debugging.
  String get displayName;

  /// Initialize the submodule (called when first accessed or at app startup).
  Future<void> initialize() async {}

  /// Dispose the submodule (called on app shutdown or when unloading).
  Future<void> dispose() async {}
}

/// Base interface for pluggable backend modules.
/// Each backend (NanoDLP, Odyssey, etc.) implements this to register itself
/// with the system in one place, eliminating scattered type checks and imports.
abstract class BackendModule {
  /// Unique identifier for this backend (e.g., 'nanodlp', 'odyssey').
  String get id;

  /// Human-readable display name for UI selection/identification.
  String get displayName;

  /// Factory method to create a concrete BackendClient instance.
  BackendClient createClient();

  /// Optional: Lifecycle hook called when the module is activated.
  /// Use for initialization: pre-loading machine info, setting up caches, etc.
  Future<void> initialize() async {}

  /// Optional: Lifecycle hook called when the module is deactivated.
  /// Use for cleanup: closing connections, flushing caches, etc.
  Future<void> dispose() async {}

  /// Declare which features/capabilities this backend supports.
  /// UI and providers query this map to conditionally show features.
  /// Examples: supportsImportFile, supportsCalibration, supportsProfiles, supportsAthena.
  Map<String, bool> getCapabilities();

  /// Return list of submodule IDs this backend supports (e.g., ['athena_iot']).
  List<String> getSupportedSubmodules() => [];
}

/// Central registry for all backend modules.
/// Singleton pattern: use [BackendRegistry()] to get/create the instance.
///
/// Usage:
/// ```dart
/// final registry = BackendRegistry();
/// registry.register(NanoDlpModule());
/// registry.register(OdysseyModule());
///
/// final client = registry.createClient('nanodlp');
/// final module = registry.getModule('nanodlp');
/// final supported = module?.getCapabilities()['supportsImportFile'] ?? false;
/// ```
class BackendRegistry {
  static final _instance = BackendRegistry._();
  static final _log = Logger('BackendRegistry');

  final Map<String, BackendModule> _modules = {};
  final Map<String, BackendModule> _activeModules = {};

  factory BackendRegistry() => _instance;

  BackendRegistry._();

  final Map<String, BackendSubmodule> _submodules = {};
  final Map<String, Map<String, bool>> _submoduleInitState =
      {}; // backendId -> {submoduleId -> isInitialized}

  /// Register a backend module so it can be selected at runtime.
  /// Should be called during app initialization in main.dart.
  void register(BackendModule module) {
    _modules[module.id] = module;
    _log.info(
        'Registered backend module: ${module.id} (${module.displayName})');
  }

  /// Retrieve a module by its unique id.
  BackendModule? getModule(String id) => _modules[id];

  /// List all registered backend modules.
  List<BackendModule> listModules() => _modules.values.toList();

  /// Create and initialize a BackendClient for the given backend id.
  /// Returns null if the module is not registered.
  /// Call [dispose] on the returned client when done to clean up resources.
  Future<BackendClient?> createClient(String id) async {
    final module = _modules[id];
    if (module == null) {
      _log.warning('Attempted to create client for unregistered backend: $id');
      return null;
    }

    try {
      final client = module.createClient();
      await module.initialize();
      _activeModules[id] = module;
      _log.info('Initialized backend: $id');
      return client;
    } catch (e, st) {
      _log.severe('Failed to initialize backend $id', e, st);
      return null;
    }
  }

  /// Dispose a backend module and clean up resources.
  Future<void> disposeModule(String id) async {
    final module = _activeModules.remove(id);
    if (module != null) {
      try {
        await module.dispose();
        _log.info('Disposed backend: $id');
      } catch (e, st) {
        _log.warning('Error disposing backend $id', e, st);
      }
    }
  }

  /// Get a capability value from a registered module.
  /// Returns null if module is not found or capability is undefined.
  bool? supportsCapability(String moduleId, String capability) {
    final module = _modules[moduleId];
    return module?.getCapabilities()[capability];
  }

  /// Dispose all active modules (called on app shutdown).
  Future<void> disposeAll() async {
    final ids = _activeModules.keys.toList();
    for (final id in ids) {
      await disposeModule(id);
    }
    _log.info('All backend modules disposed');
  }

  /// Register all built-in backend modules.
  /// Call this once at app startup (e.g., in main.dart).
  /// When adding a new backend:
  ///   1. Add its module export at top of this file
  ///   2. Add register() call below
  /// That's it—no other changes needed!
  void registerBuiltInModules() {
    // Import NanoDlpModule and OdysseyModule are exported from this file,
    // so they're available to callers without separate imports.
    register(NanoDlpModule());
    register(OdysseyModule());

    _log.info('Registered all built-in backend modules');
  }

  /// Register a service submodule (e.g., Athena IoT, file import).
  /// Submodules are backend-agnostic services that multiple backends can use.
  void registerSubmodule(BackendSubmodule submodule) {
    _submodules[submodule.id] = submodule;
    _log.info('Registered submodule: ${submodule.displayName}');
  }

  /// Get a submodule by ID.
  BackendSubmodule? getSubmodule(String id) => _submodules[id];

  /// Get all submodules supported by a specific backend.
  List<BackendSubmodule> getSubmodulesForBackend(String backendId) {
    final module = getModule(backendId);
    if (module == null) return [];

    final supportedIds = module.getSupportedSubmodules();
    return supportedIds
        .map((id) => _submodules[id])
        .whereType<BackendSubmodule>()
        .toList();
  }

  /// Initialize all submodules for a given backend.
  Future<void> initializeSubmodulesForBackend(String backendId) async {
    if (!_submoduleInitState.containsKey(backendId)) {
      _submoduleInitState[backendId] = {};
    }

    final submodules = getSubmodulesForBackend(backendId);
    for (final submodule in submodules) {
      if (_submoduleInitState[backendId]![submodule.id] != true) {
        await submodule.initialize();
        _submoduleInitState[backendId]![submodule.id] = true;
        _log.info(
            'Initialized submodule ${submodule.displayName} for backend $backendId');
      }
    }
  }

  /// Dispose all submodules for a given backend.
  Future<void> disposeSubmodulesForBackend(String backendId) async {
    if (!_submoduleInitState.containsKey(backendId)) return;

    final submodules = getSubmodulesForBackend(backendId);
    for (final submodule in submodules) {
      if (_submoduleInitState[backendId]![submodule.id] == true) {
        await submodule.dispose();
        _submoduleInitState[backendId]![submodule.id] = false;
        _log.info(
            'Disposed submodule ${submodule.displayName} for backend $backendId');
      }
    }
  }

  /// Register all built-in service submodules.
  /// When adding a new submodule, add registerSubmodule() call below.
  void registerBuiltInSubmodules() {
    registerSubmodule(AthenaIotSubmodule());
    _log.info('Registered all built-in submodules');
  }
}
