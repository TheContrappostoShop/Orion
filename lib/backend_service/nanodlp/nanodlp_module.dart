/*
* Orion - NanoDLP Backend Module
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
import 'package:orion/backend_service/backend_registry.dart';
import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/nanodlp/nanodlp_http_client.dart';

/// NanoDLP backend module for the registry-based backend system.
/// Encapsulates all NanoDLP-specific initialization and capability declarations.
class NanoDlpModule implements BackendModule {
  static final _log = Logger('NanoDlpModule');

  @override
  String get id => 'nanodlp';

  @override
  String get displayName => 'NanoDLP';

  @override
  BackendClient createClient() {
    _log.fine('Creating NanoDLP HTTP client');
    return NanoDlpHttpClient();
  }

  /// Declare which features NanoDLP supports.
  /// These capability flags are queried by UI and providers to gate features.
  @override
  Map<String, bool> getCapabilities() {
    return {
      // File management
      BackendCapabilities.supportsImportFile: true,
      BackendCapabilities.supportsLocalFilesProvider: true,

      // Profile management
      BackendCapabilities.supportsProfiles: true,
      BackendCapabilities.supportsProfileEdit: true,

      // Calibration
      BackendCapabilities.supportsCalibration: true,

      // Athena IoT integration (Athena is a machine that runs on NanoDLP)
      BackendCapabilities.supportsAthena: true,
      BackendCapabilities.supportsAthenaUpdates: true,
      BackendCapabilities.supportsAthenaFeatureFlags: true,
      BackendCapabilities.supportsForceLeveling: true,

      // Temperature/vat control
      BackendCapabilities.supportsVatTemperature: true,
      BackendCapabilities.supportsChamberTemperature: true,

      // Notifications
      BackendCapabilities.supportsNotifications: true,

      // Analytics
      BackendCapabilities.supportsAnalytics: true,

      // Cache invalidation
      BackendCapabilities.supportsCacheInvalidation: true,

      // Streaming
      BackendCapabilities.supportsSseStatusStream: false,

      // RGB / LED lighting
      BackendCapabilities.supportsRgbLighting: true,
    };
  }

  @override
  List<String> getSupportedSubmodules() => [
        BackendSubmodules.athenaIot, // NanoDLP supports Athena IoT services
      ];

  /// Initialize NanoDLP backend when activated.
  /// Currently no special setup needed, but kept as a hook for future needs
  /// (e.g., pre-fetching machine info, setting up WebSocket connections, etc.).
  @override
  Future<void> initialize() async {
    _log.info('Initializing NanoDLP backend module');
    // Future: Pre-load machine metadata, set up real-time connections, etc.
  }

  /// Dispose NanoDLP backend when deactivated.
  /// Cleanup routine called when switching backends or shutting down app.
  @override
  Future<void> dispose() async {
    _log.info('Disposing NanoDLP backend module');
    // Future: Close WebSocket connections, clear caches, etc.
  }
}
