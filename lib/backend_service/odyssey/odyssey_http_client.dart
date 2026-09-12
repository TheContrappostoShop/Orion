/*
* Orion - NanoDLP HTTP Client
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
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_thumbnail_generator.dart';

class OdysseyHttpClient implements BackendClient {
  late final String apiUrl;
  final _log = Logger('OdysseyHttpClient');
  final http.Client Function() _clientFactory;
  final Duration _requestTimeout;

  OdysseyHttpClient(
      {http.Client Function()? clientFactory, Duration? requestTimeout})
      : _clientFactory = clientFactory ?? http.Client.new,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 2) {
    try {
      OrionConfig config = OrionConfig();
      final customUrl = config.getString('customUrl', category: 'advanced');
      final useCustomUrl = config.getFlag('useCustomUrl', category: 'advanced');
      apiUrl = useCustomUrl ? customUrl : 'http://localhost:12357';
    } catch (e) {
      throw Exception('Failed to load orion.cfg: $e');
    }
  }

  http.Client _createClient() {
    final inner = _clientFactory();
    return _TimeoutHttpClient(inner, _requestTimeout, _log, 'Odyssey');
  }

  @override
  Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory) async {
    final queryParams = {
      'location': location,
      'subdirectory': subdirectory,
      'page_index': pageIndex.toString(),
      'page_size': pageSize.toString(),
    };
    final resp = await _odysseyGet('/files', queryParams);
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  @override
  Future<bool> usbAvailable() async {
    try {
      await listItems('Local', 1, 0, '');
    } catch (e) {
      return false;
    }

    try {
      await listItems('Usb', 1, 0, '');
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getFileMetadata(
      String location, String filePath) async {
    final queryParams = {'location': location, 'file_path': filePath};
    final resp = await _odysseyGet('/file/metadata', queryParams);
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getConfig() async {
    final resp = await _odysseyGet('/config', {});
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  @override
  Future<String> getBackendVersion() async {
    return 'Odyssey ?.?.?'; //(await _odysseyGet('/version', {})).body;
  }

  @override
  Future<Map<String, dynamic>> getStatus() async {
    final resp = await _odysseyGet('/status', {});
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> getKinematicStatus() async {
    // Odyssey backend does not expose a kinematic status endpoint.
    _log.fine('getKinematicStatus not supported on Odyssey');
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAnalytics(int n) async {
    // Odyssey doesn't currently define a standard analytics endpoint. As a
    // best-effort, try '/analytic/data/<n>' on Odyssey host; otherwise return
    // an empty list.
    try {
      final uri = _dynUri(apiUrl, '/analytic/data/$n', {});
      final client = _createClient();
      final resp = await client.get(uri);
      client.close();
      if (resp.statusCode != 200) return [];
      final decoded = json.decode(resp.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<dynamic> getAnalyticValue(int id) async {
    // Odyssey doesn't support the scalar NanoDLP analytic/value endpoint.
    // Return null to indicate unsupported / no-value.
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final resp = await _odysseyGet('/notification', {});
      final decoded = json.decode(resp.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Stream<Map<String, dynamic>> getStatusStream() async* {
    final uri = _dynUri(apiUrl, '/status/stream', {});
    final request = http.Request('GET', uri);

    final client = _createClient();
    try {
      final streamed = await client.send(request);
      final stream = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        if (line.startsWith('data:')) {
          final payload = line.substring(5).trim();
          if (payload.isEmpty) continue;
          try {
            final jsonObj = json.decode(payload) as Map<String, dynamic>;
            yield jsonObj;
          } catch (e) {
            continue;
          }
        }
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<void> cancelPrint() async {
    await _odysseyPost('/print/cancel', {});
  }

  @override
  Future<void> pausePrint() async {
    await _odysseyPost('/print/pause', {});
  }

  @override
  Future<void> resumePrint() async {
    await _odysseyPost('/print/resume', {});
  }

  @override
  Future<Map<String, dynamic>> move(double height) async {
    final resp = await _odysseyPost('/manual', {'z': height.toString()});
    return json.decode(resp.body == '' ? '{}' : resp.body)
        as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> moveDelta(double deltaMm) async {
    final resp = await _odysseyPost('/manual', {'dz': deltaMm.toString()});
    return json.decode(resp.body == '' ? '{}' : resp.body)
        as Map<String, dynamic>;
  }

  @override
  Future<bool> canMoveToTop() async => true;

  @override
  Future<bool> canMoveToFloor() async => true;

  @override
  Future<Map<String, dynamic>> moveToTop() async =>
      throw UnimplementedError('moveToTop not supported by Odyssey backend');

  @override
  Future<Map<String, dynamic>> moveToFloor() async =>
      throw UnimplementedError('moveToFloor not supported by Odyssey backend');

  @override
  Future<Map<String, dynamic>> manualCure(bool cure) async {
    final resp = await _odysseyPost('/manual', {'cure': cure.toString()});
    return json.decode(resp.body == '' ? '{}' : resp.body)
        as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> manualHome() async {
    final resp = await _odysseyPost('/manual/home', {});
    return json.decode(resp.body == '' ? '{}' : resp.body)
        as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> manualCommand(String command) async {
    final resp =
        await _odysseyPost('/manual/hardware_command', {'command': command});
    return json.decode(resp.body == '' ? '{}' : resp.body)
        as Map<String, dynamic>;
  }

  @override
  Future<void> displayTest(String test) async {
    await _odysseyPost('/manual/display_test', {'test': test});
  }

  @override
  Future<Map<String, dynamic>> emergencyStop() async {
    return await manualCommand('M112');
  }

  @override
  Future<Uint8List> getFileThumbnail(
      String location, String filePath, String size) async {
    final queryParams = {
      'location': location,
      'file_path': filePath,
      'size': size
    };
    final resp = await _odysseyGet('/file/thumbnail', queryParams);
    return resp.bodyBytes;
  }

  @override
  Future<Uint8List> getPlateLayerImage(int plateId, int layer) async {
    // Odyssey backend does not generally provide NanoDLP-style plate layer
    // images. Return a placeholder matching the canonical NanoDLP large
    // size so callers can display a consistent image.
    try {
      // Use the NanoDLP thumbnail generator's placeholder if available.
      // Importing here avoids adding a package-level dependency at the
      // top-level of this file which may not be desired for all builds.
      // However, NanoDlpThumbnailGenerator is a light-weight helper already
      // present in the project.
      // ignore: avoid_dynamic_calls
      return Future.value(NanoDlpThumbnailGenerator.generatePlaceholder(
          NanoDlpThumbnailGenerator.largeWidth,
          NanoDlpThumbnailGenerator.largeHeight));
    } catch (_) {
      return Future.value(Uint8List(0));
    }
  }

  @override
  Future<void> startPrint(String location, String filePath) async {
    await _odysseyPost(
        '/print/start', {'location': location, 'file_path': filePath});
  }

  @override
  Future<Map<String, dynamic>> deleteFile(
      String location, String filePath) async {
    final resp = await _odysseyDelete(
        '/file', {'location': location, 'file_path': filePath});
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  @override
  Future<void> invalidateCache() async {
    // No file list cache in Odyssey adapter.
    return;
  }

  @override
  Future<int?> importFile(FileImportRequest request) async {
    throw UnsupportedError('File import is not supported by Odyssey backend.');
  }

  @override
  Future<ResinSettings?> getResinSettings(int profileId) async {
    // Odyssey currently does not expose resin profile edit APIs.
    return null;
  }

  @override
  Future<void> saveResinExposure(int profileId, double normalCureTime) async {
    throw UnsupportedError(
        'Resin profile editing is not supported by Odyssey backend.');
  }

  @override
  Future<void> saveResinSettings(int profileId, ResinSettings settings) async {
    throw UnsupportedError(
        'Saving resin settings is not supported by Odyssey backend.');
  }

  // Internal helpers
  Uri _dynUri(String apiUrl, String path, Map<String, dynamic> queryParams) {
    if (queryParams.containsKey('file_path')) {
      queryParams['file_path'] =
          queryParams['file_path'].toString().replaceAll('//', '');
    }

    if (apiUrl.startsWith('https://')) {
      return Uri.https(apiUrl.replaceFirst('https://', ''), path, queryParams);
    } else if (apiUrl.startsWith('http://')) {
      return Uri.http(apiUrl.replaceFirst('http://', ''), path, queryParams);
    } else {
      throw ArgumentError('apiUrl must start with either http:// or https://');
    }
  }

  Future<http.Response> _odysseyGet(
      String endpoint, Map<String, dynamic> queryParams) async {
    final uri = _dynUri(apiUrl, endpoint, queryParams);
    final client = _createClient();
    try {
      final response = await client.get(uri);
      if (response.statusCode == 200) return response;
      throw Exception(
          'Odyssey GET call failed: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  Future<http.Response> _odysseyPost(
      String endpoint, Map<String, dynamic> queryParams) async {
    final uri = _dynUri(apiUrl, endpoint, queryParams);
    final client = _createClient();
    try {
      final response = await client.post(uri);
      if (response.statusCode == 200) return response;
      throw Exception(
          'Odyssey POST call failed: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  Future<http.Response> _odysseyDelete(
      String endpoint, Map<String, dynamic> queryParams) async {
    final uri = _dynUri(apiUrl, endpoint, queryParams);
    final client = _createClient();
    try {
      final response = await client.delete(uri);
      if (response.statusCode == 200) return response;
      throw Exception(
          'Odyssey DELETE call failed: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  @override
  Future<void> disableNotification(int timestamp) {
    throw UnimplementedError();
  }

  @override
  Future tareForceSensor() {
    throw UnimplementedError();
  }

  @override
  Future updateBackend() {
    // TODO: implement updateBackend
    throw UnimplementedError();
  }

  @override
  Future setChamberTemperature(double temperature) {
    // TODO: implement setChamberTemperature
    throw UnimplementedError();
  }

  @override
  Future setVatTemperature(double temperature) {
    // TODO: implement setVatTemperature
    throw UnimplementedError();
  }

  @override
  Future<bool> isChamberTemperatureControlEnabled() {
    // TODO: implement isChamberTemperatureControlEnabled
    throw UnimplementedError();
  }

  @override
  Future<bool> isVatTemperatureControlEnabled() {
    // TODO: implement isVatTemperatureControlEnabled
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> getMachine() async {
    // Odyssey backend does not expose NanoDLP-style machine.json. Provide
    // a best-effort map using getConfig() information so callers can still
    // query something useful.
    try {
      final cfg = await getConfig();
      final general = cfg['general'] as Map<String, dynamic>? ?? {};
      final advanced = cfg['advanced'] as Map<String, dynamic>? ?? {};
      return {
        'Name': general['hostname'] ?? '',
        'UUID': advanced['uuid'] ?? '',
        'DefaultProfile': 0,
        'CustomValues': {},
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<int?> getDefaultProfileId() async {
    // Odyssey doesn't expose NanoDLP-style default profile metadata. Return
    // null to indicate no default profile is known.
    try {
      final m = await getMachine();
      final cand =
          m['DefaultProfile'] ?? m['defaultProfileId'] ?? m['defaultProfile'];
      if (cand == null) return null;
      return int.tryParse('$cand');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setDefaultProfileId(int id) async {
    // Odyssey doesn't provide a standard default-profile endpoint. Best-effort
    // no-op so callers can attempt to set a default without crashing.
    return;
  }

  @override
  Future<Map<String, dynamic>> getProfileJson(int id) async {
    // Odyssey backend doesn't expose NanoDLP-style profile JSON. Return an
    // empty map to indicate unsupported.
    return {};
  }

  @override
  Future<Map<String, dynamic>> editProfile(
      int id, Map<String, dynamic> fields) async {
    // Odyssey does not provide a NanoDLP-style profile edit endpoint.
    // Implement as a no-op that returns an empty map to indicate unsupported.
    _log.fine('editProfile called on OdysseyHttpClient (unsupported) id=$id');
    return {};
  }

  @override
  Future<Map<String, dynamic>> cloneProfile(
      int sourceId, Map<String, dynamic> fields) async {
    // Odyssey has no profile create/clone endpoint. Throwing (rather than
    // returning an empty map) keeps the UI from reporting a clone that never
    // happened.
    _log.fine('cloneProfile called on OdysseyHttpClient (unsupported) '
        'source=$sourceId');
    throw UnsupportedError(
        'Cloning resin profiles is not supported by Odyssey backend.');
  }

  @override
  Future getChamberTemperature() {
    // TODO: implement getChamberTemperature
    throw UnimplementedError();
  }

  @override
  Future getVatTemperature() {
    // TODO: implement getVatTemperature
    throw UnimplementedError();
  }

  @override
  Future<void> preheatAndMix(double temperature) async {
    // Odyssey does not support Athena-specific preheat_and_mix endpoint
    _log.fine('preheatAndMix called on OdysseyHttpClient (unsupported)');
    return;
  }

  @override
  Future<void> preheatAndMixStandalone() async {
    // Odyssey does not support Athena-specific preheat_and_mix_standalone endpoint
    _log.fine(
        'preheatAndMixStandalone called on OdysseyHttpClient (unsupported)');
    return;
  }

  @override
  Future<String?> getCalibrationImageUrl(int modelId) async {
    // Odyssey does not support calibration images
    _log.fine(
        'getCalibrationImageUrl called on OdysseyHttpClient (unsupported)');
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getCalibrationModels() async {
    // Odyssey does not support calibration models
    _log.fine('getCalibrationModels called on OdysseyHttpClient (unsupported)');
    return [];
  }

  @override
  Future<bool> startCalibrationPrint({
    required int calibrationModelId,
    required List<double> exposureTimes,
    required int profileId,
  }) async {
    _log.fine(
        'startCalibrationPrint called on OdysseyHttpClient (unsupported)');
    return false;
  }

  @override
  Future<double?> getSlicerProgress() async {
    _log.fine('getSlicerProgress called on OdysseyHttpClient (unsupported)');
    return null;
  }

  @override
  Future<bool?> isCalibrationPlateProcessed() async {
    _log.fine(
        'isCalibrationPlateProcessed called on OdysseyHttpClient (unsupported)');
    return null;
  }

  @override
  Future<bool> resetZOffset() {
    // TODO: implement resetZOffset
    throw UnimplementedError();
  }

  @override
  Future<bool> setZOffset(double offset) {
    // TODO: implement setZOffset
    throw UnimplementedError();
  }
}

class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner, this._timeout, this._log, this._label);

  final http.Client _inner;
  final Duration _timeout;
  // ignore: unused_field
  final Logger _log;
  final String _label;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final future = _inner.send(request);
    return future.timeout(_timeout, onTimeout: () {
      final msg =
          '$_label ${request.method} ${request.url} timed out after ${_timeout.inSeconds}s';
      // Downgrade to FINE to avoid noisy repeated WARN logs when the
      // higher-level StatusProvider already reports backend errors.
      _log.fine(msg);
      throw TimeoutException(msg);
    });
  }

  @override
  void close() {
    _inner.close();
  }
}
