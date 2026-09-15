/*
* Orion - Odyssey Backend Module
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
import 'package:orion/backend_service/odyssey/odyssey_http_client.dart';

/// Odyssey backend module for the registry-based backend system.
/// Encapsulates all Odyssey-specific initialization and capability declarations.
class OdysseyModule implements BackendModule {
  static final _log = Logger('OdysseyModule');

  @override
  String get id => 'odyssey';

  @override
  String get displayName => 'Odyssey';

  @override
  BackendClient createClient() {
    _log.fine('Creating Odyssey HTTP client');
    return OdysseyHttpClient();
  }

  /// Declare which features Odyssey supports.
  /// These capability flags are queried by UI and providers to gate features.
  /// Currently, Odyssey is minimally implemented; most profile/calibration
  /// features are NanoDLP-specific and will return false.
  @override
  Map<String, bool> getCapabilities() {
    return {
      // File management
      BackendCapabilities.supportsImportFile: false,
      BackendCapabilities.supportsLocalFilesProvider: false,

      // Profile management
      BackendCapabilities.supportsProfiles: false,
      BackendCapabilities.supportsProfileEdit: false,

      // Calibration
      BackendCapabilities.supportsCalibration: false,

      // Athena IoT integration
      BackendCapabilities.supportsAthena: false,
      BackendCapabilities.supportsAthenaUpdates: false,
      BackendCapabilities.supportsAthenaFeatureFlags: false,
      BackendCapabilities.supportsForceLeveling: false,

      // Temperature/vat control
      BackendCapabilities.supportsVatTemperature: false,
      BackendCapabilities.supportsChamberTemperature: false,

      // Notifications
      BackendCapabilities.supportsNotifications: true,

      // Analytics
      BackendCapabilities.supportsAnalytics: false,

      // Cache invalidation
      BackendCapabilities.supportsCacheInvalidation: false,

      // Streaming
      BackendCapabilities.supportsSseStatusStream: true,

      // RGB / LED lighting
      BackendCapabilities.supportsRgbLighting: false,
    };
  }

  @override
  List<String> getSupportedSubmodules() => [];

  /// Initialize Odyssey backend when activated.
  /// Currently no special setup needed, but kept as a hook for future needs.
  @override
  Future<void> initialize() async {
    _log.info('Initializing Odyssey backend module');
    // Future: Set up Odyssey-specific connections, fetch config, etc.
  }

  /// Dispose Odyssey backend when deactivated.
  /// Cleanup routine called when switching backends or shutting down app.
  @override
  Future<void> dispose() async {
    _log.info('Disposing Odyssey backend module');
    // Future: Close connections, cleanup resources, etc.
  }
}
