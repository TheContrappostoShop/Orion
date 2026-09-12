/*
* Orion - Backend Client
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

import 'dart:typed_data';
import 'dart:async';

import 'package:orion/backend_service/domain/models.dart';

/// Minimal abstraction over the Backend API used by providers. This allows
/// swapping implementations (real HTTP client, mock, or unit-test doubles)
/// while keeping providers free from direct dependency on ApiService.
abstract class BackendClient {
  Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory);

  Future<bool> usbAvailable();

  Future<Map<String, dynamic>> getFileMetadata(
      String location, String filePath);

  Future<Map<String, dynamic>> getConfig();

  Future<String> getBackendVersion();

  Future<Uint8List> getFileThumbnail(
      String location, String filePath, String size);

  Future<void> startPrint(String location, String filePath);

  Future<Map<String, dynamic>> deleteFile(String location, String filePath);

  /// Invalidate any backend-side or client-side file/cache metadata.
  ///
  /// Backends that don't cache may keep the default no-op behavior.
  Future<void> invalidateCache() async {}

  /// Import a file to backend-managed storage.
  ///
  /// Returns backend-specific identifier (e.g. plate ID) when available.
  /// Implementations that don't support import should throw [UnsupportedError].
  Future<int?> importFile(FileImportRequest request) async {
    throw UnsupportedError('File import is not supported by this backend.');
  }

  /// Fetch normalized resin settings for a profile.
  ///
  /// Implementations that don't support profiles may return null.
  Future<ResinSettings?> getResinSettings(int profileId) async {
    return null;
  }

  /// Save only normal exposure to a resin profile without mutating unrelated fields.
  ///
  /// Implementations that don't support profile editing should throw
  /// [UnsupportedError].
  Future<void> saveResinExposure(int profileId, double normalCureTime) async {
    throw UnsupportedError(
        'Resin profile editing is not supported by this backend.');
  }

  /// Save full normalized resin settings for a profile.
  ///
  /// Implementations should persist all supported fields from [settings].
  Future<void> saveResinSettings(int profileId, ResinSettings settings) async {
    throw UnsupportedError(
        'Saving resin settings is not supported by this backend.');
  }

  // Status-related
  Future<Map<String, dynamic>> getStatus();

  /// Stream of status updates from the server. Implementations may expose
  /// an SSE / streaming endpoint. Each emitted Map corresponds to a JSON
  /// object parsed from the stream's data payloads.
  Stream<Map<String, dynamic>> getStatusStream();

  /// Fetch recent notifications from the backend. Returns a list of JSON
  /// objects representing notifications. Some backends (e.g. NanoDLP)
  /// expose a `/notification` endpoint that returns an array.
  Future<List<Map<String, dynamic>>> getNotifications();

  /// Fetch kinematic status information when available. This is an optional
  /// backend feature that returns a JSON-like map describing kinematic state
  /// (for example Athena's `/athena-iot/status/kinematic` payload).
  /// Implementations that do not support kinematic status should return null.
  Future<Map<String, dynamic>?> getKinematicStatus();

  /// Disable / acknowledge a notification on the backend when supported.
  /// The timestamp argument is the numeric timestamp provided by the
  /// notification payload (e.g. NanoDLP uses an integer timestamp).
  Future<void> disableNotification(int timestamp);

  // Print control
  Future<void> cancelPrint();
  Future<void> pausePrint();
  Future<void> resumePrint();

  // Manual controls and hardware commands
  Future<Map<String, dynamic>> move(double height);

  /// Send a relative Z move in millimeters (positive = up, negative = down).
  /// This maps directly to the device's relative move endpoints when
  /// available (e.g. NanoDLP /z-axis/move/.../micron/...).
  Future<Map<String, dynamic>> moveDelta(double deltaMm);

  /// Whether the client supports a direct "move to top limit" command.
  Future<bool> canMoveToTop();
  Future<bool> canMoveToFloor();

  /// Move the Z axis directly to the device's top limit if supported.
  Future<Map<String, dynamic>> moveToTop();
  Future<Map<String, dynamic>> moveToFloor();
  Future<Map<String, dynamic>> manualCure(bool cure);
  Future<Map<String, dynamic>> manualHome();
  Future<Map<String, dynamic>> manualCommand(String command);
  Future<Map<String, dynamic>> emergencyStop();
  Future<void> displayTest(String test);

  /// Fetch a specific 2D layer PNG from a NanoDLP-style plates endpoint.
  /// plateId is the numeric plate identifier and layer is the layer index
  /// (as reported by the backend). Implementations that don't support this
  /// may return a placeholder image or empty bytes.
  Future<Uint8List> getPlateLayerImage(int plateId, int layer);

  /// Fetch recent analytics entries. `n` requests the last N entries.
  /// Returns a list of JSON objects with keys like 'ID', 'T', 'V'.
  Future<List<Map<String, dynamic>>> getAnalytics(int n);

  /// Fetch a single analytic value by metric id (e.g. /analytic/value/6).
  /// Returns the raw value (number or string) or null on failure.
  Future<dynamic> getAnalyticValue(int id);

  /// Fetch backend machine metadata where available (e.g. NanoDLP /json/db/machine.json).
  /// Returns a map representation of the machine or an empty map when unsupported.
  Future<Map<String, dynamic>> getMachine();

  /// Fetch the full JSON payload for a profile by id when supported by the
  /// backend (e.g. NanoDLP's /profile/json/`<id>` endpoint). Returns an empty
  /// map when unsupported or on failure.
  Future<Map<String, dynamic>> getProfileJson(int id);

  /// Edit a profile by posting form fields to the backend's profile edit
  /// endpoint (e.g. POST /profile/edit/`<id>`). The `fields` map is encoded
  /// as multipart/form-data. Implementations should return the parsed JSON
  /// response when available or an empty map on success/unsupported.
  Future<Map<String, dynamic>> editProfile(int id, Map<String, dynamic> fields);

  /// Create a new profile by cloning [sourceId] and applying [fields], which
  /// use the backend's own field names (e.g. NanoDLP's `Title`, `CureTime`).
  ///
  /// Returns the created profile's raw payload when the backend can report it
  /// and an empty map otherwise. Implementations without profile cloning
  /// should leave the default, which throws [UnsupportedError].
  Future<Map<String, dynamic>> cloneProfile(
      int sourceId, Map<String, dynamic> fields) async {
    throw UnsupportedError(
        'Cloning resin profiles is not supported by this backend.');
  }

  /// Return the backend's notion of the default profile id when available.
  /// This abstracts parsing machine metadata (e.g. NanoDLP's machine.json)
  /// so callers don't need to inspect raw maps.
  Future<int?> getDefaultProfileId();

  /// Set the backend's default profile id. Backends that support a dedicated
  /// default-profile endpoint (e.g. NanoDLP's /profile/default/`<id>`) should
  /// implement this to persist the change on the device. Implementations that
  /// cannot set a default profile should throw or return a failed future.
  Future<void> setDefaultProfileId(int id);

  /// Tare the force sensor if supported by the backend.
  /// Returns a boolean indicating success or failure.
  Future<dynamic> tareForceSensor();

  /// Update the backend service if supported.
  /// Returns a boolean indicating success or failure.
  Future<dynamic> updateBackend();

  /// Set and Get vat temperature if supported by the backend.
  /// Returns a boolean indicating success or failure.
  Future<dynamic> setVatTemperature(double temperature);
  Future<dynamic> getVatTemperature();

  /// Check if vat temperature control is enabled.
  /// Returns a boolean indicating enabled status.
  Future<bool> isVatTemperatureControlEnabled();

  // Set and Get chamber temperature if supported by the backend.
  /// Returns a boolean indicating success or failure.
  Future<dynamic> setChamberTemperature(double temperature);
  Future<dynamic> getChamberTemperature();

  /// Check if chamber temperature control is enabled.
  /// Returns a boolean indicating enabled status.
  Future<bool> isChamberTemperatureControlEnabled();

  /// Trigger preheat and mix operation at the specified temperature.
  /// This is an Athena-specific feature exposed via /athena-iot/control/preheat_and_mix
  Future<void> preheatAndMix(double temperature);

  /// Trigger preheat and mix operation without temperature (standalone mode).
  /// This is an Athena-specific feature exposed via /athena-iot/control/preheat_and_mix_standalone
  Future<void> preheatAndMixStandalone();

  /// Get the URL for a calibration model preview image by ID.
  /// Returns the full URL path to the image (e.g. http://host/static/shots/calibration-images/1.png)
  /// or null if not supported by the backend.
  Future<String?> getCalibrationImageUrl(int modelId);

  /// Get available calibration models from the backend.
  /// Returns a list of calibration models with metadata.
  Future<List<Map<String, dynamic>>> getCalibrationModels();

  /// Start a calibration print job.
  /// Returns true if the job was successfully submitted.
  Future<bool> startCalibrationPrint({
    required int calibrationModelId,
    required List<double> exposureTimes,
    required int profileId,
  });

  /// Get the current slicer progress (0.0 to 1.0).
  /// Returns null if slicer is not running.
  Future<double?> getSlicerProgress();

  /// Check if calibration plate (PlateID 0) has been fully processed.
  /// Used for accurate calibration completion detection since /slicer
  /// doesn't report calibration progress correctly.
  /// Returns null if unable to determine.
  Future<bool?> isCalibrationPlateProcessed();

  /// Set Z offset if supported by the backend.
  /// Returns a boolean indicating success or failure.
  Future<bool> setZOffset(double offset);

  /// Reset Z offset to default if supported by the backend.
  /// Returns a boolean indicating success or failure.
  Future<bool> resetZOffset();
}
