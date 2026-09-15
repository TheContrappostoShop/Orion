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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:orion/backend_service/nanodlp/models/nano_file.dart';
import 'package:orion/backend_service/nanodlp/models/nano_status.dart';
import 'package:orion/backend_service/nanodlp/models/nano_manual.dart';
import 'package:orion/backend_service/nanodlp/nanodlp_mappers.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_thumbnail_generator.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_form_controls.dart';
import 'package:orion/backend_service/nanodlp/models/nano_profiles.dart';
import 'package:orion/backend_service/nanodlp/models/nano_machine.dart';
import 'package:flutter/foundation.dart';
import 'package:orion/backend_service/backend_client.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/backend_service/athena_iot/athena_iot_client.dart';

/// NanoDLP adapter (initial implementation)
///
/// Implements a small subset of the `BackendClient` contract needed for
/// StatusProvider and thumbnail fetching. Other methods remain unimplemented
/// and should be added as needed.
class NanoDlpHttpClient implements BackendClient {
  late final String apiUrl;
  final _log = Logger('NanoDlpHttpClient');
  final http.Client Function() _clientFactory;
  final Duration _requestTimeout;
  // Increase plates cache TTL so we don't re-query the plates list on every
  // frequent status poll. Plates metadata is relatively static during a
  // print session so a 2-minute cache avoids needless network load.
  static const Duration _platesCacheTtl = Duration(seconds: 120);
  List<NanoFile>? _platesCacheData;
  DateTime? _platesCacheTime;
  Future<List<NanoFile>>? _platesCacheFuture;
  // Cache a resolved PlateID -> NanoFile mapping so we don't repeatedly
  // perform list lookups for the same active plate while status is polled.
  int? _resolvedPlateId;
  NanoFile? _resolvedPlateFile;
  DateTime? _resolvedPlateTime;
  static const Duration _thumbnailCacheTtl = Duration(seconds: 30);
  static const Duration _thumbnailPlaceholderCacheTtl = Duration(seconds: 5);
  final Map<String, _ThumbnailCacheEntry> _thumbnailCache = {};
  final Map<String, Future<_ThumbnailCacheEntry>> _thumbnailInFlight = {};
  // Cache for opportunistic Athena kinematic status to avoid hammering the
  // Athena endpoint when StatusProvider polls frequently. TTL is small so
  // UI sees near-real-time values but the Athena client isn't called every
  // single poll.
  Map<String, dynamic>? _kinematicCache;
  DateTime? _kinematicCacheTime;
  static const Duration _kinematicCacheTtl = Duration(seconds: 2);

  NanoDlpHttpClient(
      {http.Client Function()? clientFactory, Duration? requestTimeout})
      : _clientFactory = clientFactory ?? http.Client.new,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 5) {
    _createdAt = DateTime.now();
    try {
      final cfg = OrionConfig();
      final base = cfg.getString('nanodlp.base_url', category: 'advanced');
      final useCustom = cfg.getFlag('useCustomUrl', category: 'advanced');
      final custom = cfg.getString('customUrl', category: 'advanced');

      if (base.isNotEmpty) {
        apiUrl = base;
      } else if (useCustom && custom.isNotEmpty) {
        apiUrl = custom;
      } else {
        apiUrl = 'http://localhost';
      }
    } catch (e) {
      apiUrl = 'http://localhost';
    }
    // _log.info('constructed NanoDlpHttpClient apiUrl=$apiUrl'); // commented out to reduce noise
  }

  http.Client _createClient() {
    final inner = _clientFactory();
    return _TimeoutHttpClient(inner, _requestTimeout, _log, 'NanoDLP');
  }

  AthenaIotClient _createAthenaClient({Duration? requestTimeout}) {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    return AthenaIotClient(
      baseNoSlash,
      clientFactory: _clientFactory,
      requestTimeout: requestTimeout ?? _requestTimeout,
    );
  }

  // Timestamp when this client instance was created. Used to avoid
  // performing potentially expensive plate-list resolution during the
  // very first status poll immediately at app startup.
  late final DateTime _createdAt;

  // --- Minimal implemented APIs ---
  @override
  Future<Map<String, dynamic>> getStatus() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/status');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('NanoDLP status call failed: ${resp.statusCode}');
      }
      final decoded = json.decode(resp.body) as Map<String, dynamic>;
      // Remove very large fields we don't need (e.g. FillAreas) to avoid
      // costly parsing and memory churn when polling /status frequently.
      if (decoded.containsKey('FillAreas')) {
        try {
          decoded.remove('FillAreas');
        } catch (_) {
          // ignore any removal errors; parsing will continue without it
        }
      }
      var nano = NanoStatus.fromJson(decoded);

      // If the status payload doesn't include file metadata but does include
      // a PlateID, try to resolve the plate from the plates list so we can
      // populate file metadata & enable thumbnail lookup on the UI.
      if (nano.file == null) {
        int? plateId;
        try {
          final candidate = decoded['PlateID'] ??
              decoded['plate_id'] ??
              decoded['Plateid'] ??
              decoded['plateId'];
          if (candidate is int) plateId = candidate;
          if (candidate is String) plateId = int.tryParse(candidate);
        } catch (_) {
          plateId = null;
        }
        if (plateId != null) {
          try {
            // If we previously resolved this plate and the cache is fresh,
            // reuse it.
            if (_resolvedPlateId == plateId &&
                _resolvedPlateFile != null &&
                _resolvedPlateTime != null &&
                DateTime.now().difference(_resolvedPlateTime!) <
                    _platesCacheTtl) {
              final found = _resolvedPlateFile!;
              nano = NanoStatus(
                printing: nano.printing,
                paused: nano.paused,
                statusMessage: nano.statusMessage,
                currentHeight: nano.currentHeight,
                layerId: nano.layerId,
                layersCount: nano.layersCount,
                resinLevel: nano.resinLevel,
                temp: nano.temp,
                mcuTemp: nano.mcuTemp,
                rawJsonStatus: nano.rawJsonStatus,
                state: nano.state,
                stateCode: nano.stateCode,
                progress: nano.progress,
                file: found,
                z: nano.z,
                curing: nano.curing,
              );
            } else {
              // Only attempt to resolve plate metadata when a job is active
              // (printing). Avoid fetching the plates list while the device
              // is idle to minimize network traffic at startup.
              if (!nano.printing) {
                // Skipping PlateID $plateId resolve because printer is not printing
              } else {
                // Don't block status fetch on plates list resolution. Schedule
                // a background task to refresh plates and populate the
                // resolved-plate cache for subsequent polls and thumbnail
                // lookups. However, avoid doing this immediately at startup
                // (many installs poll status right away) — only schedule the
                // async resolve if this client was created more than 2s ago.
                final age = DateTime.now().difference(_createdAt);
                if (age < const Duration(seconds: 2)) {
                  _log.fine(
                      'Skipping PlateID $plateId resolve during startup (age=${age.inMilliseconds}ms)');
                } else {
                  _log.fine('Scheduling async resolve for PlateID $plateId');
                  Future(() async {
                    try {
                      final plates = await _fetchPlates();
                      final found = plates.firstWhere(
                          (p) => p.plateId != null && p.plateId == plateId,
                          orElse: () => const NanoFile());
                      if (found.plateId != null) {
                        // Cache resolved plate for future polls
                        _log.fine('Resolved PlateID $plateId -> ${found.name}');
                        _resolvedPlateId = plateId;
                        _resolvedPlateFile = found;
                        _resolvedPlateTime = DateTime.now();
                      }
                    } catch (e, st) {
                      _log.fine('Async PlateID resolve failed', e, st);
                    }
                  });
                }
              }
            }
          } catch (e, st) {
            _log.fine(
                'Failed to resolve PlateID $plateId to plate metadata', e, st);
          }
        }
      }

      return nanoStatusToOdysseyMap(nano);
    } catch (e, st) {
      _log.fine('NanoDLP getStatus failed', e, st);
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/notification');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) return [];
      final decoded = json.decode(resp.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
      return [];
    } catch (e) {
      // Silent on per-call failure: higher-level StatusProvider will report
      // backend connectivity issues. Suppress fine-level noise here.
      return [];
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> usbAvailable() async {
    // NanoDLP runs on a networked device, USB availability is not applicable.
    return false;
  }

  @override
  Stream<Map<String, dynamic>> getStatusStream() async* {
    const pollInterval = Duration(seconds: 2);
    while (true) {
      try {
        final m = await getStatus();
        yield m;
      } catch (_) {
        // ignore and continue
      }
      await Future.delayed(pollInterval);
    }
  }

  @override
  Future<Map<String, dynamic>?> getKinematicStatus() async {
    // Return cached value when recent to avoid calling Athena every poll.
    try {
      if (_kinematicCache != null && _kinematicCacheTime != null) {
        final age = DateTime.now().difference(_kinematicCacheTime!);
        if (age <= _kinematicCacheTtl) {
          return _kinematicCache;
        }
      }

      // Use a longer timeout (10s) for kinematic status as the endpoint can be slow
      final athena =
          _createAthenaClient(requestTimeout: const Duration(seconds: 10));
      final kin = await athena.getKinematicStatusModel();
      if (kin == null) {
        _kinematicCache = null;
        _kinematicCacheTime = DateTime.now();
        return null;
      }
      final map = kin.toJson();
      _kinematicCache = map;
      _kinematicCacheTime = DateTime.now();
      return map;
    } catch (e) {
      // Silent failure: avoid logging to keep polling quiet.
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAnalytics(int n) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/analytic/data/$n');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) return [];
      final decoded = json.decode(resp.body);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      }
      return [];
    } catch (e) {
      // Suppress fine-level noise; keep failure behavior but don't log here.
      return [];
    } finally {
      client.close();
    }
  }

  @override
  Future<dynamic> getAnalyticValue(int id) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/analytic/value/$id');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) return null;
      final body = resp.body.trim();
      // NanoDLP returns a plain numeric value like "-3.719..." so try parsing
      final v = double.tryParse(body);
      if (v != null) return v;
      // Fallback: try JSON decode (in case the server returns JSON)
      try {
        final decoded = json.decode(body);
        return decoded;
      } catch (_) {
        return body;
      }
    } catch (e) {
      // Suppress fine-level noise; return null on failure.
      return null;
    } finally {
      client.close();
    }
  }

  @override
  Future<Uint8List> getFileThumbnail(
      String location, String filePath, String size) async {
    final dims = _thumbnailDimensions(size);
    Uint8List placeholder() {
      _log.fine(
          'Using placeholder thumbnail for $filePath ($size -> ${dims.$1}x${dims.$2})');
      return NanoDlpThumbnailGenerator.generatePlaceholder(dims.$1, dims.$2);
    }

    final normalizedPath =
        filePath.replaceAll(RegExp(r'^/+'), '').toLowerCase();
    var cacheKey =
        _thumbnailCacheKey('missing:$normalizedPath', dims.$1, dims.$2);
    final cachedBeforeLookup = _getCachedThumbnail(cacheKey);
    if (cachedBeforeLookup != null) {
      return cachedBeforeLookup;
    }

    NanoFile? plate;
    try {
      plate = await _findPlateForPath(filePath);
    } catch (e, st) {
      _log.warning(
          'NanoDLP failed locating plate for thumbnail: $filePath', e, st);
      final bytes = placeholder();
      _storeThumbnail(cacheKey, bytes, placeholder: true);
      return bytes;
    }

    if (plate == null) {
      _log.fine('NanoDLP thumbnail lookup found no plate for $filePath');
      final bytes = placeholder();
      _storeThumbnail(cacheKey, bytes, placeholder: true);
      return bytes;
    }
    cacheKey =
        _thumbnailCacheKeyForPlate(plate, normalizedPath, dims.$1, dims.$2);
    final cached = _getCachedThumbnail(cacheKey);
    if (cached != null) {
      return cached;
    }

    if (plate.plateId == null || !plate.previewAvailable) {
      _log.fine(
          'NanoDLP plate ${plate.resolvedPath} has no preview (plateId=${plate.plateId}, preview=${plate.previewAvailable})');
      final bytes = placeholder();
      _storeThumbnail(cacheKey, bytes, placeholder: true);
      return bytes;
    }

    final inflight = _thumbnailInFlight[cacheKey];
    if (inflight != null) {
      final entry = await inflight;
      final cachedEntry = _getCachedThumbnail(cacheKey);
      if (cachedEntry != null) {
        return cachedEntry;
      }
      _storeThumbnailEntry(cacheKey, entry);
      return entry.bytes;
    }

    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/static/plates/${plate.plateId}/3d.png');
    final future = _downloadThumbnail(uri, 'plate ${plate.plateId}');
    _thumbnailInFlight[cacheKey] = future;
    try {
      final entry = await future;
      _storeThumbnailEntry(cacheKey, entry);
      return entry.bytes;
    } finally {
      if (identical(_thumbnailInFlight[cacheKey], future)) {
        _thumbnailInFlight.remove(cacheKey);
      }
    }
  }

  /// Import a file from USB/local storage to NanoDLP's internal storage.
  ///
  /// When connecting to localhost, sends the file path directly (USBFile field).
  /// When connecting to a remote NanoDLP, uploads the file content (ZipFile multipart).
  /// Returns true if successful.
  ///
  /// Throws an exception if the request fails.
  /// Returns the plate ID if successful, null if ID couldn't be determined.
  @override
  Future<int?> importFile(FileImportRequest request) async {
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/plate/add');
      _log.info(
          'NanoDLP importFile request: $uri (file: ${request.usbFilePath}, job: ${request.jobName})');

      final httpRequest = http.MultipartRequest('POST', uri);

      // Determine if we're connecting to localhost
      final isLocalhost = uri.host == 'localhost' ||
          uri.host == '127.0.0.1' ||
          uri.host.startsWith('127.');

      if (isLocalhost) {
        // For localhost, send the file path directly (NanoDLP can access it locally)
        httpRequest.fields['USBFile'] = request.usbFilePath;
      } else {
        // For remote instances, upload the file content
        final file = File(request.usbFilePath);
        if (!await file.exists()) {
          throw Exception('File not found: ${request.usbFilePath}');
        }

        final fileBytes = await file.readAsBytes();
        final fileName = path.basename(request.usbFilePath);

        // Use "ZipFile" as the field name, matching the WebUI form for remote uploads
        httpRequest.files.add(
          http.MultipartFile.fromBytes(
            'ZipFile',
            fileBytes,
            filename: fileName,
          ),
        );
      }

      // Add form fields: Path (job name) and ProfileID
      httpRequest.fields['Path'] = request.jobName;
      httpRequest.fields['ProfileID'] = request.profileId.toString();

      // Set Accept header to match WebUI behavior
      httpRequest.headers['Accept'] =
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7';

      final client = _createClient();
      try {
        // Use longer timeout for file uploads (default 5s is too short for large files)
        const uploadTimeout = Duration(seconds: 60);
        final response = await httpRequest.send().timeout(uploadTimeout);
        final statusCode = response.statusCode;
        final responseBody = await response.stream.bytesToString();

        _log.info('NanoDLP importFile response: $statusCode');
        if (responseBody.isNotEmpty) {
          _log.fine('NanoDLP importFile response body: $responseBody');
        }

        if (statusCode == 200 || statusCode == 302) {
          // 200 = success, 302 = redirect (also indicates success)
          int? plateId;

          // Try to extract plate ID from Location header for 302 redirects
          if (statusCode == 302) {
            final location = response.headers['location'];
            if (location != null) {
              // Location typically contains the plate ID, e.g., "/plate/1" or similar
              final match = RegExp(r'/(\d+)').firstMatch(location);
              if (match != null) {
                plateId = int.tryParse(match.group(1)!);
                _log.info('NanoDLP importFile successful, plateId: $plateId');
              }
            }
          }

          // Invalidate plates cache so the new file appears in listings
          _platesCacheData = null;
          _platesCacheTime = null;
          _platesCacheFuture = null;

          return plateId;
        } else {
          _log.warning('NanoDLP importFile failed: $statusCode $responseBody');
          throw Exception('Import failed: HTTP $statusCode');
        }
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.severe('NanoDLP importFile error', e, st);
      rethrow;
    }
  }

  /// Invalidate the plates (files) cache to force a fresh fetch on next request.
  /// Use this when files have been added, deleted, or modified externally (e.g., via WebUI).
  void invalidatePlatesCache() {
    _platesCacheData = null;
    _platesCacheTime = null;
    _platesCacheFuture = null;
    _log.fine('Plates cache invalidated');
  }

  @override
  Future<void> invalidateCache() async {
    invalidatePlatesCache();
  }

  @override
  Future<ResinSettings?> getResinSettings(int profileId) async {
    final profileJson = await getProfileJson(profileId);
    if (profileJson.isEmpty) return null;
    final normalized = NanoProfile.normalizeForEdit(profileJson);
    return ResinSettings.fromNormalizedMap(normalized);
  }

  @override
  Future<void> saveResinExposure(int profileId, double normalCureTime) async {
    // NanoDLP's profile edit endpoint may treat omitted fields as zero/default.
    // To keep single-value updates non-destructive, fetch current settings and
    // submit a full merged payload.
    final existing = await getResinSettings(profileId);
    if (existing == null) {
      throw StateError(
          'Unable to load existing resin settings for profile $profileId');
    }

    final merged = ResinSettings(
      burnInCureTime: existing.burnInCureTime,
      normalCureTime: normalCureTime,
      liftAfterPrint: existing.liftAfterPrint,
      burnInCount: existing.burnInCount,
      waitAfterCure: existing.waitAfterCure,
      waitAfterLife: existing.waitAfterLife,
    );

    await saveResinSettings(profileId, merged);
  }

  /// Fields rewritten by NanoDLP's simple edit endpoint that [ResinSettings]
  /// does not model. The endpoint writes a value for every field it knows, so
  /// anything missing from the body is stored as zero.
  static const List<String> _simpleEditPreservedFields = [
    'ZStepWait',
    'WaitBeforePrint',
    'LiftSpeed',
    'RetractSpeed',
  ];

  @override
  Future<void> saveResinSettings(int profileId, ResinSettings settings) async {
    final backendFields =
        NanoProfile.denormalizeForBackend(settings.toNormalizedMap());
    await _echoSimpleEditFields(profileId, backendFields);
    await editProfile(profileId, backendFields);
  }

  /// Copy the current values of [_simpleEditPreservedFields] into [fields]
  /// when the caller doesn't set them, so saving exposure settings doesn't
  /// zero the profile's speed fields.
  Future<void> _echoSimpleEditFields(
      int profileId, Map<String, dynamic> fields) async {
    if (_simpleEditPreservedFields.every(fields.containsKey)) return;

    final current = await getProfileJson(profileId);
    if (current.isEmpty) {
      throw StateError(
          'Unable to load existing resin settings for profile $profileId');
    }
    for (final key in _simpleEditPreservedFields) {
      final value = current[key];
      if (!fields.containsKey(key) && value != null) fields[key] = value;
    }
  }

  // --- Unimplemented / TODOs ---
  @override
  Future<void> cancelPrint() async {
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/printer/stop');
      _log.info('NanoDLP stopPrint request: $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP stopPrint failed: ${resp.statusCode} ${resp.body}');
          throw Exception('NanoDLP stopPrint failed: ${resp.statusCode}');
        }
        // Some installs return JSON or plain text; ignore body and treat 200 as success
        return;
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP stopPrint error', e, st);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> deleteFile(
      String location, String filePath) async {
    try {
      // Resolve plate ID from path/name if possible.
      int? plateId = int.tryParse(filePath);
      if (plateId == null) {
        final plate = await _findPlateForPath(filePath);
        if (plate != null && plate.plateId != null) {
          plateId = plate.plateId;
        }
      }

      if (plateId == null) {
        throw Exception('NanoDLP deleteFile failed: plate ID not found');
      }

      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/plate/delete/$plateId');
      _log.info('NanoDLP deleteFile request: $uri');

      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200 &&
            resp.statusCode != 204 &&
            resp.statusCode != 302) {
          _log.warning(
              'NanoDLP deleteFile failed: ${resp.statusCode} ${resp.body}');
          throw Exception('NanoDLP deleteFile failed: ${resp.statusCode}');
        }

        // Invalidate plates cache so deleted file disappears immediately.
        invalidatePlatesCache();

        return {
          'success': true,
          'plate_id': plateId,
        };
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.severe('NanoDLP deleteFile error', e, st);
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> getFileMetadata(
      String location, String filePath) async {
    try {
      final plate = await _findPlateForPath(filePath);
      if (plate != null) {
        return plate.toOdysseyMetadata();
      }
      return {
        'file_data': {
          'path': filePath,
          'name': filePath,
          'last_modified': 0,
          'parent_path': '',
        },
      };
    } catch (e, st) {
      _log.warning('NanoDLP getFileMetadata failed for $filePath', e, st);
      throw Exception('NanoDLP getFileMetadata failed: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getConfig() async =>
      // NanoDLP doesn't have a separate /config endpoint in many setups.
      // Use /status as a best-effort source for device info and expose a
      // minimal config-shaped map expected by ConfigModel.fromJson.
      () async {
        final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
        final uri = Uri.parse('$baseNoSlash/status');
        final client = _createClient();
        try {
          final resp = await client.get(uri);
          if (resp.statusCode != 200) {
            throw Exception('NanoDLP status call failed: ${resp.statusCode}');
          }
          final decoded = json.decode(resp.body) as Map<String, dynamic>;

          // Map relevant keys into a config-shaped map
          final general = <String, dynamic>{
            'hostname': decoded['Hostname'] ?? decoded['hostname'] ?? '',
            'ip': decoded['IP'] ?? decoded['ip'] ?? '',
            'status': decoded['Status'] ?? decoded['status'] ?? '',
          };

          final advanced = <String, dynamic>{
            'backend': 'nanodlp',
            'nanodlp': {
              'build': decoded['Build'] ?? decoded['build'],
              'version': decoded['Version'] ?? decoded['version'],
            }
          };

          final machine = <String, dynamic>{
            'disk': decoded['disk'] ?? decoded['Disk'],
            'wifi': decoded['Wifi'] ?? decoded['wifi'],
            'resin_level': decoded['resin'] ??
                decoded['ResinLevelMm'] ??
                decoded['resin_level_mm'],
          };

          // Attempt to enrich the vendor section with optional Athena IoT
          // payloads when available on Athena-derived NanoDLP installs.
          final vendor = <String, dynamic>{};
          try {
            final athena = _createAthenaClient();
            final athenaDataModel = await athena.getPrinterDataModel();
            if (athenaDataModel != null) {
              vendor['athena_printer_data'] = athenaDataModel.toJson();
            }
            final athenaFlagsModel = await athena.getFeatureFlagsModel();
            if (athenaFlagsModel != null) {
              vendor['athena_feature_flags'] = athenaFlagsModel.toJson();
            }
            try {
              final athenaKinematic = await athena.getKinematicStatusModel();
              if (athenaKinematic != null) {
                vendor['athena_kinematic_status'] = athenaKinematic.toJson();
              }
            } catch (e, st) {
              _log.fine('Ignoring athena kinematic fetch failure', e, st);
            }
          } catch (e, st) {
            _log.fine('Ignoring athena IoT enrichment failure', e, st);
          }

          return {
            'general': general,
            'advanced': advanced,
            'machine': machine,
            'vendor': vendor,
          };
        } finally {
          client.close();
        }
      }();

  @override
  Future<String> getBackendVersion() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/static/image_version');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.fine('NanoDLP image_version returned ${resp.statusCode}');
        return 'NanoDLP';
      }

      final body = resp.body.trim();
      if (body.isEmpty) return 'NanoDLP';

      // Try to capture a full semver and any following +metadata tokens,
      // e.g. "Athena2-16K-CM5+0.9.9+2025-08-01" -> capture "0.9.9+2025-08-01".
      final fullSemverWithMeta =
          RegExp(r'\d+\.\d+\.\d+(?:\+[^\s]+)*').firstMatch(body);
      if (fullSemverWithMeta != null) {
        return 'NanoDLP ${fullSemverWithMeta.group(0)}';
      }

      // Fallback: capture X.Y or X.Y.Z and any +metadata following it.
      final partialWithMeta =
          RegExp(r'\d+\.\d+(?:\.\d+)?(?:\+[^\s]+)*').firstMatch(body);
      if (partialWithMeta != null) {
        return 'NanoDLP ${partialWithMeta.group(0)}';
      }

      // As a last resort, try to pick a token after "+" or return the raw body.
      final plusParts = body.split('+');
      final candidate = plusParts.firstWhere((p) => RegExp(r'\d').hasMatch(p),
          orElse: () => body);
      return 'NanoDLP ${candidate.trim()}';
    } catch (e, st) {
      _log.fine('Failed to fetch backend version', e, st);
      return 'NanoDLP';
    } finally {
      client.close();
    }
  }

  // Athena IoT integration moved to athena_iot client implementation.

  @override
  Future<Map<String, dynamic>> listItems(
      String location, int pageSize, int pageIndex, String subdirectory) async {
    try {
      // Special-case: callers may request 'Resins' which NanoDLP exposes
      // only via an HTML page. Scrape the /profiles page for profile names
      // and ids and return them as a files-like list.
      if (location.toLowerCase() == 'resins') {
        try {
          final profiles = await _fetchProfiles();
          _log.info(
              'listItems: mapped ${profiles.length} resin profiles from NanoDLP');
          return {
            'files': profiles,
            'dirs': <Map<String, dynamic>>[],
            'page_index': pageIndex,
            'page_size': pageSize,
          };
        } catch (e, st) {
          _log.warning('NanoDLP _fetchProfiles failed', e, st);
          return {
            'files': <Map<String, dynamic>>[],
            'dirs': <Map<String, dynamic>>[],
            'page_index': pageIndex,
            'page_size': pageSize,
          };
        }
      }

      final plates = await _fetchPlates();
      // Filter out calibration plate (ID 0) before mapping to file entries
      final files = plates
          .where((p) => p.plateId != 0)
          .map((p) => p.toOdysseyFileEntry())
          .toList();
      _log.info('listItems: mapped ${files.length} files from NanoDLP payload');
      return {
        'files': files,
        'dirs': <Map<String, dynamic>>[],
        'page_index': pageIndex,
        'page_size': pageSize,
      };
    } catch (e, st) {
      _log.warning('NanoDLP listItems failed', e, st);
      return {
        'files': <Map<String, dynamic>>[],
        'dirs': <Map<String, dynamic>>[],
        'page_index': pageIndex,
        'page_size': pageSize,
      };
    }
  }

  /// Scrape the NanoDLP /profiles HTML page to extract profile names and ids.
  /// Returns a list of maps compatible with the ResinsProvider expectations.
  Future<List<Map<String, dynamic>>> _fetchProfiles() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/json/db/profiles.json');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning('NanoDLP profiles JSON returned ${resp.statusCode}');
        return [];
      }

      dynamic decoded;
      try {
        decoded = json.decode(resp.body);
      } catch (e, st) {
        _log.warning('Failed to decode profiles JSON', e, st);
        return [];
      }

      final parsed = NanoProfile.parseFromJson(decoded);
      return parsed.map((p) => p.toMap()).toList(growable: false);
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> move(double height) async {
    // NanoDLP's /z-axis/move endpoint expects a relative micron distance.
    // Our callers may pass an absolute target (Odyssey contract) or a
    // relative delta. We'll behave as follows:
    // - If we can read current Z from /status, treat `height` as an absolute
    //   target and compute delta = height - currentZ (mm).
    // - If we cannot read status, treat `height` as a relative delta (mm).
    // Always read current Z from /status. If we cannot read status,
    // fail the move so callers can surface the error. We must compute
    // a delta against the true device position.
    double currentZ = 0.0;
    try {
      final statusMap = await getStatus();
      final phys = statusMap['physical_state'];
      if (phys is Map && phys['z'] != null) {
        final zVal = phys['z'];
        if (zVal is num) {
          currentZ = zVal.toDouble();
        }
      }
    } catch (e, st) {
      _log.warning('Failed to read NanoDLP status; cannot compute move', e, st);
      throw Exception('Failed to read NanoDLP status: $e');
    }

    // Compute delta in mm: callers provide an absolute target; compute
    // delta = target - currentZ
    final deltaMm = (height - currentZ);

    // Convert to microns (NanoDLP expects integer micron distances). Use
    // rounding to nearest micron. If the resulting delta is zero, no-op.
    final deltaMicrons = deltaMm == 0.0 ? 0 : (deltaMm * 1000).round();
    if (deltaMicrons == 0) {
      return NanoManualResult(ok: true, message: 'no-op').toMap();
    }

    final direction = deltaMicrons > 0 ? 'up' : 'down';
    final distanceMicrons = deltaMicrons.abs();
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
        '$baseNoSlash/z-axis/move/$direction/micron/$distanceMicrons');
    _log.info(
        'NanoDLP relative move request: $uri (deltaMm=$deltaMm currentZ=$currentZ)');

    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning('NanoDLP move failed: ${resp.statusCode} ${resp.body}');
        throw Exception('NanoDLP move failed: ${resp.statusCode}');
      }
      try {
        final decoded = json.decode(resp.body);
        final nm = NanoManualResult.fromDynamic(decoded);
        return nm.toMap();
      } catch (_) {
        return NanoManualResult(ok: true).toMap();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> moveDelta(double deltaMm) async {
    // Send a dumb relative move command in microns (NanoDLP expects an
    // integer micron distance). Positive = up, negative = down.
    final deltaMicrons = (deltaMm * 1000).round();
    if (deltaMicrons == 0) {
      return NanoManualResult(ok: true, message: 'no-op').toMap();
    }

    final direction = deltaMicrons > 0 ? 'up' : 'down';
    final distance = deltaMicrons.abs();
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri =
        Uri.parse('$baseNoSlash/z-axis/move/$direction/micron/$distance');
    _log.info('NanoDLP relative moveDelta request: $uri (deltaMm=$deltaMm)');

    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP moveDelta failed: ${resp.statusCode} ${resp.body}');
        throw Exception('NanoDLP moveDelta failed: ${resp.statusCode}');
      }
      try {
        final decoded = json.decode(resp.body);
        final nm = NanoManualResult.fromDynamic(decoded);
        return nm.toMap();
      } catch (_) {
        return NanoManualResult(ok: true).toMap();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> canMoveToTop() async {
    // Best-effort: check /status to see if device exposes z-axis controls
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/status');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) return false;
        // If status contains physical_state or similar keys, assume support.
        final decoded = json.decode(resp.body) as Map<String, dynamic>;
        return decoded.containsKey('CurrentHeight') ||
            decoded.containsKey('physical_state');
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> moveToTop() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/z-axis/top');
    _log.info('NanoDLP moveToTop request: $uri');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP moveToTop failed: ${resp.statusCode} ${resp.body}');
        throw Exception('NanoDLP moveToTop failed: ${resp.statusCode}');
      }
      try {
        final decoded = json.decode(resp.body);
        final nm = NanoManualResult.fromDynamic(decoded);
        return nm.toMap();
      } catch (_) {
        return NanoManualResult(ok: true).toMap();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<bool> canMoveToFloor() async {
    // Best-effort: check /status to see if device exposes z-axis controls
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/status');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) return false;
        // If status contains physical_state or similar keys, assume support.
        final decoded = json.decode(resp.body) as Map<String, dynamic>;
        return decoded.containsKey('CurrentHeight') ||
            decoded.containsKey('physical_state');
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> moveToFloor() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/z-axis/bottom');
    _log.info('NanoDLP moveToFloor request: $uri');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP moveToFloor failed: ${resp.statusCode} ${resp.body}');
        throw Exception('NanoDLP moveToFloor failed: ${resp.statusCode}');
      }
      try {
        final decoded = json.decode(resp.body);
        final nm = NanoManualResult.fromDynamic(decoded);
        return nm.toMap();
      } catch (_) {
        return NanoManualResult(ok: true).toMap();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> manualCommand(String command) async {
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/gcode');
      _log.info('NanoDLP manualCommand($command) request -> POST /gcode: $uri');
      final client = _createClient();
      try {
        final resp = await client.post(uri, body: {'gcode': command});
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP manualCommand($command) failed: ${resp.statusCode} ${resp.body}');
          throw Exception(
              'NanoDLP manualCommand($command) failed: ${resp.statusCode}');
        }
        try {
          final decoded = json.decode(resp.body);
          final nm = NanoManualResult.fromDynamic(decoded);
          return nm.toMap();
        } catch (_) {
          return NanoManualResult(ok: true).toMap();
        }
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP manualCommand($command) error', e, st);
      throw Exception('NanoDLP manualCommand($command) failed: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> manualCure(bool cure) async {
    try {
      final action = cure ? 'on' : 'blank';
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/projector/$action');
      _log.info(
          'NanoDLP manualCure($cure) request -> /projector/$action: $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP manualCure($cure) failed: ${resp.statusCode} ${resp.body}');
          throw Exception(
              'NanoDLP manualCure($cure) failed: ${resp.statusCode}');
        }
        try {
          final decoded = json.decode(resp.body);
          final nm = NanoManualResult.fromDynamic(decoded);
          return nm.toMap();
        } catch (_) {
          return NanoManualResult(ok: true).toMap();
        }
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP manualCure($cure) error', e, st);
      throw Exception('NanoDLP manualCure($cure) failed: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> emergencyStop() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/printer/force-stop');
    _log.info('NanoDLP emergencyStop commanded: $uri');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP emergencyStop failed as expected: ${resp.statusCode} ${resp.body}');
        // throw Exception('NanoDLP emergencyStop failed: ${resp.statusCode}');
        client.close();
        return NanoManualResult(ok: true)
            .toMap(); // treat non-200 as success, emergency stop should have occurred.
      }
      try {
        final decoded = json.decode(resp.body);
        final nm = NanoManualResult.fromDynamic(decoded);
        return nm.toMap();
      } catch (_) {
        return NanoManualResult(ok: true).toMap();
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> manualHome() async => () async {
        final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
        final uri = Uri.parse('$baseNoSlash/z-axis/calibrate');
        final client = _createClient();
        try {
          final resp = await client.get(uri);
          if (resp.statusCode != 200) {
            _log.warning(
                'NanoDLP manualHome failed: ${resp.statusCode} ${resp.body}');
            throw Exception('NanoDLP manualHome failed: ${resp.statusCode}');
          }
          try {
            final decoded = json.decode(resp.body);
            final nm = NanoManualResult.fromDynamic(decoded);
            return nm.toMap();
          } catch (_) {
            // Some NanoDLP installs return empty body; treat 200 as success.
            return NanoManualResult(ok: true).toMap();
          }
        } finally {
          client.close();
        }
      }();

  @override
  Future<void> disableNotification(int timestamp) async {
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/notification/disable/$timestamp');
      _log.info('NanoDLP disableNotification: $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP disableNotification returned ${resp.statusCode}: ${resp.body}');
          throw Exception(
              'NanoDLP disableNotification failed: ${resp.statusCode}');
        }
        return;
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP disableNotification error', e, st);
      rethrow;
    }
  }

  @override
  Future<void> pausePrint() async {
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/printer/pause');
      _log.info('NanoDLP pausePrint request: $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP pausePrint failed: ${resp.statusCode} ${resp.body}');
          throw Exception('NanoDLP pausePrint failed: ${resp.statusCode}');
        }
        // Some installs return JSON or plain text; ignore body and treat 200 as success
        return;
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP pausePrint error', e, st);
      rethrow;
    }
  }

  @override
  Future<void> resumePrint() async {
    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/printer/unpause');
      _log.info('NanoDLP resumePrint request: $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP resumePrint failed: ${resp.statusCode} ${resp.body}');
          throw Exception('NanoDLP resumePrint failed: ${resp.statusCode}');
        }
        // Some installs return JSON or plain text; ignore body and treat 200 as success
        return;
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP resumePrint error', e, st);
      rethrow;
    }
  }

  @override
  @override
  Future<void> startPrint(String location, String filePath) async {
    try {
      // Resolve the plate ID. `filePath` may be a path or already a plateId.
      String? plateId;
      try {
        final plate = await _findPlateForPath(filePath);
        if (plate != null && plate.plateId != null) {
          plateId = plate.plateId!.toString();
        }
      } catch (_) {
        // ignore and try treating filePath as an ID
      }

      final idToUse = plateId ?? filePath;
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse('$baseNoSlash/printer/start/$idToUse');
      _log.info('NanoDLP startPrint request: $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP startPrint failed: ${resp.statusCode} ${resp.body}');
          throw Exception('NanoDLP startPrint failed: ${resp.statusCode}');
        }
        // Some installs return JSON or plain text; ignore body and treat 200 as success
        // Kick off a background plates prefetch so the server-side plate list
        // is refreshed and thumbnails / file metadata become available faster
        // for the UI immediately after a start request.
        Future(() async {
          try {
            final plates = await _fetchPlates(forceRefresh: true);
            // If we already resolved a plate id for this path, prefer that.
            if (plateId != null) {
              final found = plates.firstWhere(
                  (p) => p.plateId != null && p.plateId!.toString() == plateId,
                  orElse: () => const NanoFile());
              if (found.plateId != null) {
                _resolvedPlateId = found.plateId;
                _resolvedPlateFile = found;
                _resolvedPlateTime = DateTime.now();
                _log.fine(
                    'Prefetched and resolved PlateID $plateId -> ${found.name}');
              }
            } else {
              // Try to match by path/name in case caller passed a path.
              final normalized = filePath.replaceAll(RegExp(r'^/+'), '');
              final found = plates.firstWhere(
                  (p) =>
                      _matchesPath(p.resolvedPath, normalized) ||
                      (p.name != null && _matchesPath(p.name, normalized)),
                  orElse: () => const NanoFile());
              if (found.plateId != null) {
                _resolvedPlateId = found.plateId;
                _resolvedPlateFile = found;
                _resolvedPlateTime = DateTime.now();
                _log.fine(
                    'Prefetched and resolved path $filePath -> ${found.name}');
              }
            }
          } catch (e, st) {
            _log.fine('Prefetch plates after startPrint failed', e, st);
          }
        });

        return;
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP startPrint error', e, st);
      rethrow;
    }
  }

  @override
  Future<void> displayTest(String test) async {
    // Map test names to real NanoDLP test endpoints.
    const Map<String, String> testMappings = {
      'Grid': '/projector/generate/calibration',
      // So far Athena is the only printer with NanoDLP that we support
      'Logo': '/projector/display/general***athena.png',
      'Measure': '/projector/generate/boundaries',
      'White': '/projector/generate/white',
    };

    try {
      final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
      // Resolve mapped command; fall back to legacy /display/test/<test> if unknown.
      final mapped = testMappings[test];
      final command = mapped ?? '/display/test/$test';
      final cmdWithSlash = command.startsWith('/') ? command : '/$command';
      final uri = Uri.parse('$baseNoSlash$cmdWithSlash');

      _log.info('NanoDLP displayTest request for "$test": $uri');
      final client = _createClient();
      try {
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.warning(
              'NanoDLP displayTest failed: ${resp.statusCode} ${resp.body}');
          throw Exception('NanoDLP displayTest failed: ${resp.statusCode}');
        }
        // Some installs return JSON or plain text; ignore body and treat 200 as success
        return;
      } finally {
        client.close();
      }
    } catch (e, st) {
      _log.warning('NanoDLP displayTest error', e, st);
      rethrow;
    }
  }

  bool _matchesPath(String? lhs, String rhs) {
    if (lhs == null) return false;
    return lhs.trim().toLowerCase() == rhs.trim().toLowerCase();
  }

  String _thumbnailCacheKey(String identifier, int width, int height) =>
      '$identifier|$width|$height';

  String _thumbnailCacheKeyForPlate(
      NanoFile plate, String fallbackPath, int width, int height) {
    // PlateID can change when files are deleted/replaced on the device.
    // NanoDLP allows multiple files with the same name, so we need to
    // cross-reference multiple properties from the file model to create
    // a unique cache key that survives plateId reuse and duplicate names.
    // Include: path, lastModified, fileSize, layerCount, usedMaterial,
    // printTime, and layerHeight to maximize uniqueness.
    final resolvedPath = plate.resolvedPath.isNotEmpty
        ? plate.resolvedPath.toLowerCase()
        : fallbackPath;
    final lm = plate.lastModified ?? 0;
    final fs = plate.fileSize ?? 0;
    final lc = plate.layerCount ?? 0;
    final um = plate.usedMaterial?.toStringAsFixed(2) ?? '0.00';
    final pt = plate.printTime?.toStringAsFixed(1) ?? '0.0';
    final lh = plate.layerHeight?.toStringAsFixed(3) ?? '0.000';

    final identifier =
        'path:$resolvedPath|lm:$lm|fs:$fs|lc:$lc|um:$um|pt:$pt|lh:$lh';
    return _thumbnailCacheKey(identifier, width, height);
  }

  Uint8List? _getCachedThumbnail(String cacheKey) {
    final entry = _thumbnailCache[cacheKey];
    if (entry == null) return null;
    final ttl =
        entry.placeholder ? _thumbnailPlaceholderCacheTtl : _thumbnailCacheTtl;
    if (DateTime.now().difference(entry.timestamp) >= ttl) {
      _thumbnailCache.remove(cacheKey);
      return null;
    }
    return entry.bytes;
  }

  void _storeThumbnail(String cacheKey, Uint8List bytes,
      {required bool placeholder}) {
    _storeThumbnailEntry(
        cacheKey, _ThumbnailCacheEntry(bytes, DateTime.now(), placeholder));
  }

  void _storeThumbnailEntry(String cacheKey, _ThumbnailCacheEntry entry) {
    _thumbnailCache[cacheKey] = entry;
  }

  Future<_ThumbnailCacheEntry> _downloadThumbnail(
      Uri uri, String debugLabel) async {
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        // Return raw bytes from server. Decoding/resizing will be done by the
        // caller in a background isolate (e.g. via compute) to avoid jank.
        return _ThumbnailCacheEntry(resp.bodyBytes, DateTime.now(), false);
      }
      _log.fine(
          'NanoDLP preview request returned ${resp.statusCode} for $debugLabel; returning empty bytes to let caller generate placeholder.');
      return _ThumbnailCacheEntry(Uint8List(0), DateTime.now(), true);
    } catch (e, st) {
      _log.warning('NanoDLP preview request error for $debugLabel', e, st);
      return _ThumbnailCacheEntry(Uint8List(0), DateTime.now(), true);
    } finally {
      client.close();
    }
  }

  /// Fetch a 2D layer PNG for a given plate and layer index. This will
  /// return a canonical large-sized PNG (800x480) by force-resizing the
  /// downloaded image. On error, a generated placeholder is returned.
  @override
  Future<Uint8List> getPlateLayerImage(int plateId, int layer) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/static/plates/$plateId/$layer.png');
    final entry = await _downloadThumbnail(uri, 'plate $plateId layer $layer');
    if (entry.bytes.isNotEmpty) {
      // Return raw bytes; let the UI handle resizing via ResizeImage to avoid
      // expensive Dart-based image decoding/resizing on the CPU.
      return entry.bytes;
    }
    return NanoDlpThumbnailGenerator.generatePlaceholder(
        NanoDlpThumbnailGenerator.largeWidth,
        NanoDlpThumbnailGenerator.largeHeight);
  }

  Future<List<NanoFile>> _fetchPlates({bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _platesCacheData;
      final cachedTime = _platesCacheTime;
      if (cached != null &&
          cachedTime != null &&
          DateTime.now().difference(cachedTime) < _platesCacheTtl) {
        return Future.value(cached);
      }
      final inflight = _platesCacheFuture;
      if (inflight != null) {
        return inflight;
      }
    } else {
      _platesCacheData = null;
      _platesCacheTime = null;
    }

    final future = _loadPlatesFromNetwork();
    _platesCacheFuture = future;
    return future.then((plates) {
      if (identical(_platesCacheFuture, future)) {
        _platesCacheFuture = null;
        _platesCacheData = plates;
        _platesCacheTime = DateTime.now();
      }
      return plates;
    }).catchError((error, stack) {
      if (identical(_platesCacheFuture, future)) {
        _platesCacheFuture = null;
      }
      throw error;
    });
  }

  Future<List<NanoFile>> _loadPlatesFromNetwork() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/plates/list/json');
    // _log.fine('Requesting NanoDLP plates list (no query params): $uri'); // commented out to reduce noise

    final client = _createClient();
    try {
      http.Response resp;
      try {
        resp = await client.get(uri);
      } catch (e, st) {
        _log.warning('NanoDLP plates list request failed', e, st);
        return const <NanoFile>[];
      }
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP plates list call failed: ${resp.statusCode} ${resp.body}');
        return const <NanoFile>[];
      }

      dynamic decoded;
      try {
        decoded = json.decode(resp.body);
      } catch (e) {
        _log.warning('Failed to decode plates/list/json response', e);
        return const <NanoFile>[];
      }

      final rawEntries = _extractPlateEntries(decoded);
      final plates = <NanoFile>[];
      for (final entry in rawEntries) {
        if (entry == null) continue;
        if (entry is Map<String, dynamic>) {
          try {
            plates.add(NanoFile.fromJson(entry));
          } catch (e, st) {
            _log.warning('Failed to parse NanoDLP plate entry', e, st);
          }
          continue;
        }
        if (entry is Map) {
          try {
            plates.add(NanoFile.fromJson(Map<String, dynamic>.from(entry)));
          } catch (e, st) {
            _log.warning(
                'Failed to parse NanoDLP plate entry (Map cast)', e, st);
          }
        }
      }
      return plates;
    } finally {
      client.close();
    }
  }

  List<dynamic> _extractPlateEntries(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in ['plates', 'files', 'data']) {
        final value = decoded[key];
        if (value is List) return value;
      }
      final values = decoded.values.whereType<Map>().toList();
      if (values.isNotEmpty) return values;
      return [decoded];
    }
    _log.fine(
        'plates/list/json returned unexpected type: ${decoded.runtimeType}');
    return const [];
  }

  Future<NanoFile?> _findPlateForPath(String filePath) async {
    final normalized = filePath.replaceAll(RegExp(r'^/+'), '');
    final plates = await _fetchPlates();
    for (final plate in plates) {
      final platePath = plate.resolvedPath;
      final plateName = plate.name ?? '';
      if (_matchesPath(platePath, filePath) ||
          _matchesPath(platePath, normalized) ||
          _matchesPath('/$platePath', filePath) ||
          (plateName.isNotEmpty &&
              (_matchesPath(plateName, filePath) ||
                  _matchesPath(plateName, normalized)))) {
        return plate;
      }
    }
    return null;
  }

  (int, int) _thumbnailDimensions(String size) {
    switch (size) {
      case 'Large':
        return (800, 480);
      case 'Small':
      default:
        return (400, 400);
    }
  }

  @override
  Future tareForceSensor() async {
    try {
      manualCommand('[[PressureWrite 1]]');
    } catch (e, st) {
      _log.warning('NanoDLP tareForceSensor error', e, st);
      rethrow;
    }
  }

  @override
  Future updateBackend() async {
    try {
      manualCommand('[[Exec /home/pi/athena-start-update.sh]]');
    } catch (e, st) {
      _log.warning('NanoDLP updateBackend error', e, st);
      rethrow;
    }
  }

  @override
  Future setChamberTemperature(double temperature) async {
    try {
      manualCommand('SET_CHAMBER_HEATER TARGET=$temperature');
    } catch (e, st) {
      _log.warning('NanoDLP setChamberTemperature error', e, st);
      rethrow;
    }
  }

  @override
  Future setVatTemperature(double temperature) async {
    try {
      manualCommand('SET_VAT_HEATER TARGET=$temperature');
    } catch (e, st) {
      _log.warning('NanoDLP setVatTemperature error', e, st);
      rethrow;
    }
  }

  @override
  Future<bool> isChamberTemperatureControlEnabled() async {
    try {
      final val = await getAnalyticValue(23);
      if (val is num) return val > 0;
      final parsed = double.tryParse(val?.toString() ?? '');
      if (parsed != null) return parsed > 0;
      return false;
    } catch (e, st) {
      _log.warning('NanoDLP isChamberTemperatureControlEnabled error', e, st);
      // Do not throw; absence of analytics should be treated as "disabled"
      return false;
    }
  }

  @override
  Future<bool> isVatTemperatureControlEnabled() async {
    try {
      final val = await getAnalyticValue(12);
      if (val is num) return val > 0;
      final parsed = double.tryParse(val?.toString() ?? '');
      if (parsed != null) return parsed > 0;
      return false;
    } catch (e, st) {
      _log.warning('NanoDLP isVatTemperatureControlEnabled error', e, st);
      // Do not throw; treat missing data as disabled
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getMachine() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/json/db/machine.json');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.fine('NanoDLP machine.json returned ${resp.statusCode}');
        return {};
      }
      dynamic decoded;
      try {
        decoded = json.decode(resp.body);
      } catch (e, st) {
        _log.fine('Failed to decode machine.json', e, st);
        return {};
      }
      try {
        final nm = NanoMachine.fromDecoded(decoded);
        final out = nm.toJson();
        // include raw payload for backward compatibility
        out['raw'] = nm.raw;
        return out;
      } catch (e, st) {
        _log.fine('Failed to parse machine.json into NanoMachine', e, st);
        if (decoded is Map<String, dynamic>) return decoded;
        return {};
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<int?> getDefaultProfileId() async {
    try {
      final machine = await getMachine();
      final cand = machine['DefaultProfile'] ??
          machine['defaultProfileId'] ??
          machine['defaultProfile'] ??
          machine['DefaultProfileID'];
      if (cand == null) return null;
      return int.tryParse('$cand');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setDefaultProfileId(int id) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/profile/default/$id');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP setDefaultProfile returned ${resp.statusCode} ${resp.body}');
        throw Exception('Failed to set default profile: ${resp.statusCode}');
      }
      return;
    } catch (e, st) {
      _log.warning('NanoDLP setDefaultProfile error', e, st);
      rethrow;
    } finally {
      client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> getProfileJson(int id) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final candidates = [
      Uri.parse('$baseNoSlash/profile/json/$id'),
      Uri.parse('$baseNoSlash/profile/json/$id.json'),
      Uri.parse('$baseNoSlash/json/db/profile/$id'),
      Uri.parse('$baseNoSlash/json/db/profile_$id.json'),
      Uri.parse('$baseNoSlash/json/db/profiles.json'),
      Uri.parse('$baseNoSlash/json/db/profiles'),
    ];

    for (final uri in candidates) {
      final client = _createClient();
      try {
        _log.fine('getProfileJson: trying $uri');
        final resp = await client.get(uri);
        if (resp.statusCode != 200) {
          _log.fine('getProfileJson: $uri returned ${resp.statusCode}');
          continue;
        }

        dynamic decoded;
        try {
          decoded = json.decode(resp.body);
        } catch (e) {
          _log.fine('getProfileJson: failed to decode JSON from $uri: $e');
          continue;
        }

        // If it's a map that looks like a profile, return it.
        if (decoded is Map<String, dynamic>) {
          // If this map contains profiles/data list, try extracting the
          // matching entry.
          for (final listKey in ['profiles', 'data', 'items']) {
            final maybeList = decoded[listKey];
            if (maybeList is List) {
              for (final e in maybeList) {
                if (e is Map) {
                  final cand = e['ProfileID'] ?? e['ProfileId'] ?? e['id'];
                  if (cand != null && int.tryParse('$cand') == id) {
                    return Map<String, dynamic>.from(e);
                  }
                }
              }
            }
          }

          // Heuristic: if the map itself looks like a profile (has ProfileID)
          final cand =
              decoded['ProfileID'] ?? decoded['ProfileId'] ?? decoded['id'];
          if (cand != null) {
            _log.fine('getProfileJson: found profile at $uri (id=$id)');
            return Map<String, dynamic>.from(decoded);
          }

          // Otherwise continue to next candidate
          continue;
        }

        // If it's a list, search for matching entry.
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              final cand = e['ProfileID'] ?? e['ProfileId'] ?? e['id'];
              if (cand != null && int.tryParse('$cand') == id) {
                _log.fine(
                    'getProfileJson: found profile inside list at $uri (id=$id)');
                return Map<String, dynamic>.from(e);
              }
            }
          }
        }
      } catch (e, st) {
        _log.fine('getProfileJson: request to $uri failed', e, st);
        // ignore and try next
      } finally {
        try {
          client.close();
        } catch (_) {}
      }
    }

    // As a final fallback, try fetching the profiles JSON via the helper
    // used by listItems and locate the original raw entry.
    try {
      final uri = Uri.parse('$baseNoSlash/json/db/profiles.json');
      _log.fine('getProfileJson: fallback fetch $uri');
      final client = _createClient();
      final resp = await client.get(uri);
      client.close();
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        // decoded may be a map or list; reuse parsing logic from above
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) {
              final cand = e['ProfileID'] ?? e['ProfileId'] ?? e['id'];
              if (cand != null && int.tryParse('$cand') == id) {
                _log.fine(
                    'getProfileJson: found profile in fallback at $uri (id=$id)');
                return Map<String, dynamic>.from(e);
              }
            }
          }
        } else if (decoded is Map) {
          for (final listKey in ['profiles', 'data', 'items']) {
            final maybeList = decoded[listKey];
            if (maybeList is List) {
              for (final e in maybeList) {
                if (e is Map) {
                  final cand = e['ProfileID'] ?? e['ProfileId'] ?? e['id'];
                  if (cand != null && int.tryParse('$cand') == id) {
                    return Map<String, dynamic>.from(e);
                  }
                }
              }
            }
          }
        }
      }
    } catch (e, st) {
      _log.fine('getProfileJson: fallback fetch failed', e, st);
    }

    _log.fine('getProfileJson: no profile JSON found for id=$id');
    return {};
  }

  @override
  Future<Map<String, dynamic>> editProfile(
      int id, Map<String, dynamic> fields) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    return _postProfileForm(
      Uri.parse('$baseNoSlash/profile/edit/simple/$id'),
      fields,
      'editProfile',
    );
  }

  /// Clone [sourceId] into a brand new profile with [fields] applied on top
  /// of the source profile's form values.
  ///
  /// `GET /profile/clone/<id>` only renders the edit form, and the server
  /// copies nothing from the source, so the whole form has to be echoed back
  /// on the POST (see [NanoFormControls]). [fields] uses NanoDLP field names
  /// and overrides individual controls — at minimum `Title`, which is how the
  /// copy gets its name.
  @override
  Future<Map<String, dynamic>> cloneProfile(
      int sourceId, Map<String, dynamic> fields) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/profile/clone/$sourceId');
    final existingIds = await _profileIds();

    final client = _createClient();
    try {
      final form = await client.get(uri);
      if (form.statusCode != 200) {
        throw Exception(
            'cloneProfile failed to load clone form: ${form.statusCode}');
      }
      final body = NanoFormControls.parse(form.body);
      if (body.isEmpty) {
        _log.warning('cloneProfile found no form controls at $uri');
        throw Exception(
            'cloneProfile found no form controls for profile $sourceId');
      }
      fields.forEach((key, value) {
        if (value == null) return;
        body[key] = '$value';
      });
      _log.info('NanoDLP cloneProfile -> $uri '
          'overrides=${fields.keys.toList()} controls=${body.length}');

      await _postProfileForm(uri, body, 'cloneProfile');
    } finally {
      client.close();
    }

    // NanoDLP assigns the new id server-side, so resolve it by diffing the
    // profile list rather than guessing max+1.
    final created = await _findCreatedProfile(existingIds);
    if (created.isEmpty) {
      _log.warning('cloneProfile: new profile not found in profiles.json');
    } else {
      _log.info('NanoDLP cloneProfile created profile '
          'id=${created['ProfileID']} title=${created['Title']}');
    }
    return created;
  }

  /// POSTs a NanoDLP profile form and maps its redirect-on-success behaviour
  /// onto a result map. Throws on HTTP or auth failures.
  Future<Map<String, dynamic>> _postProfileForm(
      Uri uri, Map<String, dynamic> fields, String operation) async {
    _log.info('NanoDLP $operation POST -> $uri '
        'fields=${fields.keys.toList()}');
    final client = _createClient();
    try {
      // Build application/x-www-form-urlencoded body.
      // Convert all field values to strings as expected by NanoDLP.
      final body = <String, String>{};
      fields.forEach((key, value) {
        if (value == null) return;
        body[key] = '$value';
      });

      final resp = await client.post(uri, body: body);
      final status = resp.statusCode;

      // NanoDLP commonly replies to successful form POSTs with a redirect
      // (302/303) back to the profile page. Treat non-auth redirects as
      // success, similar to import/delete flows.
      if (status >= 300 && status < 400) {
        final locationRaw = (resp.headers['location'] ?? '').trim();
        final location = locationRaw.toLowerCase();
        final looksLikeAuthRedirect = location.contains('login') ||
            location.contains('signin') ||
            location.contains('auth');

        if (looksLikeAuthRedirect) {
          _log.warning(
              '$operation failed auth redirect: $status location=$locationRaw');
          throw Exception('$operation failed: $status (auth redirect)');
        }

        _log.info(
            '$operation redirect treated as success: $status location=$locationRaw');
        return {
          'status': status,
          if (locationRaw.isNotEmpty) 'location': locationRaw,
        };
      }

      if (status != 200 && status != 201 && status != 204) {
        _log.warning('$operation failed: $status ${resp.body}');
        throw Exception('$operation failed: $status');
      }

      if (resp.body.trim().isEmpty) return {};
      try {
        final decoded = json.decode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {};
      } catch (_) {
        return {};
      }
    } finally {
      client.close();
    }
  }

  /// Profile ids currently known to the backend (empty when unreadable).
  Future<Set<int>> _profileIds() async {
    final profiles = await _rawProfiles();
    return profiles.map(_profileId).whereType<int>().toSet();
  }

  /// The profile created after [existingIds] was captured. NanoDLP assigns
  /// the highest id to the newest profile.
  Future<Map<String, dynamic>> _findCreatedProfile(Set<int> existingIds) async {
    final profiles = await _rawProfiles();
    Map<String, dynamic>? newest;
    int? newestId;
    for (final profile in profiles) {
      final id = _profileId(profile);
      if (id == null || existingIds.contains(id)) continue;
      if (newestId == null || id > newestId) {
        newestId = id;
        newest = profile;
      }
    }
    return newest == null ? const {} : Map<String, dynamic>.from(newest);
  }

  static int? _profileId(Map<String, dynamic> profile) {
    for (final key in const ['ProfileID', 'ProfileId', 'profileId', 'id']) {
      final value = profile[key];
      if (value == null) continue;
      final parsed = int.tryParse('$value');
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Raw entries from `/json/db/profiles.json`, unlike the provider-shaped
  /// mapping returned by [listItems].
  Future<List<Map<String, dynamic>>> _rawProfiles() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$baseNoSlash/json/db/profiles.json');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning('NanoDLP profiles JSON returned ${resp.statusCode}');
        return const [];
      }
      final decoded = json.decode(resp.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
    } catch (e, st) {
      _log.warning('Failed to read NanoDLP profiles JSON', e, st);
      return const [];
    } finally {
      client.close();
    }
  }

  @override
  Future getChamberTemperature() async {
    try {
      final val = await getAnalyticValue(23);
      return val;
    } catch (e, st) {
      _log.warning('NanoDLP getChamberTemperature error', e, st);
      // Do not throw; treat missing data as disabled
      return 0;
    }
  }

  @override
  Future getVatTemperature() async {
    try {
      final val = await getAnalyticValue(12);
      return val;
    } catch (e, st) {
      _log.warning('NanoDLP getVatTemperature error', e, st);
      // Do not throw; treat missing data as disabled
      return 0;
    }
  }

  @override
  Future<void> preheatAndMix(double temperature) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
        '$baseNoSlash/athena-iot/control/preheat_and_mix?temperature=${temperature.toStringAsFixed(1)}');
    _log.info('NanoDLP preheatAndMix request: $uri');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP preheatAndMix failed: ${resp.statusCode} ${resp.body}');
        throw Exception('NanoDLP preheatAndMix failed: ${resp.statusCode}');
      }
      return;
    } finally {
      client.close();
    }
  }

  @override
  Future<void> preheatAndMixStandalone() async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    final uri =
        Uri.parse('$baseNoSlash/athena-iot/control/preheat_and_mix_standalone');
    _log.info('NanoDLP preheatAndMixStandalone request: $uri');
    final client = _createClient();
    try {
      final resp = await client.get(uri);
      if (resp.statusCode != 200) {
        _log.warning(
            'NanoDLP preheatAndMixStandalone failed: ${resp.statusCode} ${resp.body}');
        throw Exception(
            'NanoDLP preheatAndMixStandalone failed: ${resp.statusCode}');
      }
      return;
    } finally {
      client.close();
    }
  }

  @override
  Future<String?> getCalibrationImageUrl(int modelId) async {
    final baseNoSlash = apiUrl.replaceAll(RegExp(r'/+$'), '');
    return '$baseNoSlash/static/shots/calibration-images/$modelId.png';
  }

  @override
  Future<List<Map<String, dynamic>>> getCalibrationModels() async {
    final url = '$apiUrl/static/config/calibrationConfig.json';
    final client = _createClient();
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return data.cast<Map<String, dynamic>>();
        }
      }
      _log.warning(
          'Failed to fetch calibration models: ${response.statusCode}');
      return [];
    } catch (e) {
      _log.warning('Error fetching calibration models: $e');
      return [];
    }
  }

  @override
  Future<bool> startCalibrationPrint({
    required int calibrationModelId,
    required List<double> exposureTimes,
    required int profileId,
  }) async {
    final url = '$apiUrl/api/v1/athena/calibration/add/$calibrationModelId';
    final client = _createClient();

    final curetimes = exposureTimes.map((e) => e.toStringAsFixed(1)).join(',');

    try {
      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'curetimes': curetimes,
          'ProfileID': profileId.toString(),
        },
      );

      if (response.statusCode == 200) {
        _log.info('Calibration print job submitted successfully');
        return true;
      } else {
        _log.warning(
            'Failed to submit calibration print: ${response.statusCode}');
        return false;
      }
    } on TimeoutException catch (e) {
      _log.warning(
          'Calibration submission timed out: $e - job may still have started');
      // Return true on timeout since the job might have started
      // The caller will poll for progress to verify
      return true;
    } catch (e) {
      _log.severe('Error submitting calibration print: $e');
      return false;
    }
  }

  @override
  Future<double?> getSlicerProgress() async {
    final url = '$apiUrl/slicer';
    final client = _createClient();

    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final percentage = data['percentage'];

        // NanoDLP returns percentage as a string, not a number
        if (percentage != null) {
          final percentValue = percentage is num
              ? percentage.toDouble()
              : double.tryParse(percentage.toString());

          if (percentValue != null) {
            _log.fine('Slicer progress: $percentValue%');
            return percentValue / 100.0; // Convert to 0.0-1.0
          }
        }
      }
      return null;
    } catch (e) {
      _log.warning('Error fetching slicer progress: $e');
      return null;
    }
  }

  @override
  Future<bool?> isCalibrationPlateProcessed() async {
    final url = '$apiUrl/json/db/plates.json';
    final client = _createClient();

    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final plates = json.decode(response.body) as List;
        final calibrationPlate = plates.firstWhere(
          (plate) => plate['PlateID'] == 0,
          orElse: () => null,
        );
        if (calibrationPlate != null) {
          return calibrationPlate['Processed'] == true;
        }
      }
      return null;
    } catch (e) {
      _log.warning('Error checking calibration plate status: $e');
      return null;
    }
  }

  @override
  Future<bool> resetZOffset() {
    manualCommand('CLEAR_Z_OFFSET');
    return Future.value(true);
  }

  @override
  Future<bool> setZOffset(double offset) {
    manualCommand(
      'APPLY_AND_SAVE_Z_OFFSET OFFSET=${offset.toStringAsFixed(2)}',
    );
    return Future.value(true);
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
      // Intentionally do not log per-request timeouts here. The higher-level
      // StatusProvider already reports backend connectivity issues and
      // repeated per-request timeout warnings spam the logs during an outage.
      throw TimeoutException(msg);
    });
  }

  @override
  void close() {
    _inner.close();
  }
}

class _ThumbnailCacheEntry {
  _ThumbnailCacheEntry(this.bytes, this.timestamp, this.placeholder);

  final Uint8List bytes;
  final DateTime timestamp;
  final bool placeholder;
}
