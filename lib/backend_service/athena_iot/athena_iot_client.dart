/*
* Orion - Athena IoT Client
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
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'models/athena_printer_data.dart';
import 'models/athena_feature_flags.dart';
import 'models/athena_kinematic_status.dart';
import 'models/force_leveling_workflow.dart';

class AthenaIotClient {
  AthenaIotClient(this.baseUrl,
      {http.Client Function()? clientFactory, Duration? requestTimeout})
      : _clientFactory = clientFactory ?? http.Client.new,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 5) {
    _log = Logger('AthenaIotClient');
  }

  final String baseUrl;
  late final Logger _log;
  final http.Client Function() _clientFactory;
  final Duration _requestTimeout;

  http.Client _createClient() {
    final inner = _clientFactory();
    return _TimeoutHttpClient(inner, _requestTimeout, _log, 'AthenaIoT');
  }

  Future<Map<String, dynamic>> getPrinterData() async {
    try {
      final baseNoSlash = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/athena-iot/orion/printer_data');
      final client = _createClient();
      _log.fine('received data: $uri');
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) return <String, dynamic>{};
        final decoded = json.decode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return <String, dynamic>{};
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.fine('Failed to fetch Athena printer_data', e, st);
      return <String, dynamic>{};
    }
  }

  /// Typed parser for `printer_data` returning an [AthenaPrinterData].
  Future<AthenaPrinterData?> getPrinterDataModel() async {
    final raw = await getPrinterData();
    try {
      if (raw.isEmpty) return null;
      return AthenaPrinterData.fromJson(raw);
    } catch (e, st) {
      _log.fine('Failed to parse Athena printer_data into model', e, st);
      return null;
    }
  }

  Future<Map<String, dynamic>> getFeatureFlags() async {
    try {
      final baseNoSlash = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/athena-iot/orion/feature_flags');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) return <String, dynamic>{};
        final decoded = json.decode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return <String, dynamic>{};
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.fine('Failed to fetch Athena feature_flags', e, st);
      return <String, dynamic>{};
    }
  }

  /// Typed parser for `feature_flags` returning an [AthenaFeatureFlags].
  Future<AthenaFeatureFlags?> getFeatureFlagsModel() async {
    final raw = await getFeatureFlags();
    try {
      if (raw.isEmpty) return null;
      return AthenaFeatureFlags.fromJson(raw);
    } catch (e, st) {
      _log.fine('Failed to parse Athena feature_flags into model', e, st);
      return null;
    }
  }

  /// Raw fetch of kinematic status endpoint.
  Future<Map<String, dynamic>> getKinematicStatus() async {
    try {
      final baseNoSlash = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/athena-iot/status/kinematic');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) return <String, dynamic>{};
        final decoded = json.decode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return <String, dynamic>{};
      } finally {
        client.close();
      }
    } catch (e) {
      // Silent failure: return empty map on any error to keep callers simple
      // without emitting logs during frequent polling.
      return <String, dynamic>{};
    }
  }

  /// Typed parser for kinematic status returning an [AthenaKinematicStatus].
  Future<AthenaKinematicStatus?> getKinematicStatusModel() async {
    final raw = await getKinematicStatus();
    try {
      if (raw.isEmpty) return null;
      return AthenaKinematicStatus.fromJson(raw);
    } catch (e) {
      // Silent parse failure: return null.
      return null;
    }
  }

  Future<ForceLevelingWorkflowResponse> runForceLevelingWorkflow(
    String endpoint, {
    String? screenType,
  }) async {
    final safeEndpoint = endpoint.replaceAll(RegExp(r'^/+|/+$'), '');
    final baseNoSlash = baseUrl.replaceAll(RegExp(r'/+$'), '');
    // The probe_standardarm / probe_offset endpoints accept a `screentype`
    // query parameter (glass | waverelease) so the probe can account for
    // the screen surface.  Other workflow steps don't take it.
    final uri = Uri.parse(
      '$baseNoSlash/athena-iot/forcesensor/workflow/$safeEndpoint',
    ).replace(
      queryParameters:
          (screenType != null &&
                  (safeEndpoint == 'probe_standardarm' ||
                      safeEndpoint == 'probe_offset'))
              ? {'screentype': screenType}
              : null,
    );
    final client = _createClient();
    try {
      _log.info(
        'Force leveling workflow request: POST $uri '
        '(endpoint=$safeEndpoint, timeout=${_requestTimeout.inSeconds}s)',
      );
      final resp = await client.post(uri);
      Map<String, dynamic>? decodedMap;
      if (resp.body.trim().isNotEmpty) {
        try {
          final decoded = json.decode(resp.body);
          if (decoded is Map<String, dynamic>) {
            decodedMap = decoded;
          } else if (decoded is Map) {
            decodedMap = Map<String, dynamic>.from(decoded);
          }
        } catch (e, st) {
          _log.fine('Failed to decode force workflow response', e, st);
        }
      }
      _log.info(
        'Force leveling workflow response: endpoint=$safeEndpoint '
        'status=${resp.statusCode} body=${_shortBody(resp.body)}',
      );

      if (resp.statusCode == 200 && decodedMap != null) {
        final parsed = ForceLevelingWorkflowResponse.fromJson(
          decodedMap,
          statusCode: resp.statusCode,
        );
        _log.info(
          'Force leveling workflow parsed: endpoint=$safeEndpoint '
          'result=${parsed.result} homed=${parsed.machineHomed} '
          'offset=${parsed.zOffsetApplied} error="${parsed.error}"',
        );
        return parsed;
      }

      return ForceLevelingWorkflowResponse.httpFailure(
        statusCode: resp.statusCode,
        message:
            'Force leveling workflow failed: ${resp.statusCode} ${resp.body}',
        body: decodedMap,
      );
    } on TimeoutException catch (e) {
      return ForceLevelingWorkflowResponse(
        result: false,
        error: e.message ?? 'Athena IoT request timed out.',
        connectionFailed: true,
      );
    } on SocketException catch (e) {
      _log.warning(
        'Force leveling workflow socket failure: endpoint=$safeEndpoint uri=$uri',
        e,
      );
      return ForceLevelingWorkflowResponse(
        result: false,
        error: _networkErrorMessage(e.message),
        connectionFailed: true,
      );
    } on http.ClientException catch (e) {
      _log.warning(
        'Force leveling workflow client failure: endpoint=$safeEndpoint uri=$uri',
        e,
      );
      return ForceLevelingWorkflowResponse(
        result: false,
        error: _networkErrorMessage(e.message),
        connectionFailed: true,
      );
    } catch (e) {
      _log.warning(
        'Force leveling workflow unexpected failure: endpoint=$safeEndpoint uri=$uri',
        e,
      );
      return ForceLevelingWorkflowResponse(
        result: false,
        error: e.toString(),
      );
    } finally {
      client.close();
    }
  }

  String _networkErrorMessage(String detail) {
    final trimmed = detail.trim();
    if (trimmed.isEmpty) {
      return 'Could not reach the Athena IoT workflow service.';
    }
    return 'Could not reach the Athena IoT workflow service. $trimmed';
  }

  String _shortBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 800) return compact;
    return '${compact.substring(0, 800)}...';
  }

  /// Show a corner alignment pattern on the projector.
  ///
  /// [location] must be one of: front-left, front-right, back-left, back-right.
  /// Returns `true` on success (plain text "Ok"), `false` on failure.
  Future<bool> showCornerScreen(String location) async {
    final validLocations = {
      'front-left',
      'front-right',
      'back-left',
      'back-right',
    };
    if (!validLocations.contains(location)) {
      _log.warning('Invalid corner location: $location');
      return false;
    }
    return _getSpecialScreen(
      path: '/athena-iot/specialscreens/corner',
      queryParams: {'location': location},
    );
  }

  /// Show the center alignment pattern on the projector.
  /// Returns `true` on success (plain text "Ok"), `false` on failure.
  Future<bool> showCenterScreen() async {
    return _getSpecialScreen(path: '/athena-iot/specialscreens/center');
  }

  /// Turn off the projector's UV LED, hiding any active special screen.
  /// Returns `true` on success (plain text "Ok"), `false` on failure.
  Future<bool> uvledOff() async {
    return _getSpecialScreen(path: '/athena-iot/specialscreens/uvled_off');
  }

  /// Shared helper for special screens GET requests.
  Future<bool> _getSpecialScreen({
    required String path,
    Map<String, String>? queryParams,
  }) async {
    try {
      final baseNoSlash = baseUrl.replaceAll(RegExp(r'/+$'), '');
      final uri =
          Uri.parse('$baseNoSlash$path').replace(queryParameters: queryParams);
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        final body = resp.body.trim();
        _log.info(
          'Special screen response: $path status=${resp.statusCode} body="$body"',
        );
        if (resp.statusCode == 200 && body == 'Ok') return true;
        if (resp.statusCode == 400) {
          _log.warning('Special screen bad request: $path body="$body"');
          return false;
        }
        _log.warning(
          'Special screen failed: $path status=${resp.statusCode} body="$body"',
        );
        return false;
      } finally {
        client.close();
      }
    } on SocketException catch (e) {
      _log.warning('Special screen connection failed: $path', e);
      return false;
    } on http.ClientException catch (e) {
      _log.warning('Special screen HTTP error: $path', e);
      return false;
    } catch (e, st) {
      _log.warning('Special screen unexpected error: $path', e, st);
      return false;
    }
  }
}

class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient(this._inner, this._timeout, this._log, this._label);

  final http.Client _inner;
  final Duration _timeout;
  final Logger _log;
  final String _label;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final future = _inner.send(request);
    return future.timeout(_timeout, onTimeout: () {
      final msg =
          '$_label ${request.method} ${request.url} timed out after ${_timeout.inSeconds}s';
      _log.warning(msg);
      throw TimeoutException(msg);
    });
  }

  @override
  void close() {
    _inner.close();
  }
}
