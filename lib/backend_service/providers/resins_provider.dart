import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:orion/backend_service/backend_service.dart';

class ResinProfile {
  final String name;
  final String? path;
  final Map<String, dynamic> meta;
  final bool locked;

  ResinProfile(this.name,
      {this.path, this.meta = const {}, this.locked = false});
}

class CalibrationModel {
  final int id;
  final String name;
  final int models;
  final int testPiecesCount;
  final int? resinRequired;
  final int? height;
  final String? evaluationGuideUrl;

  CalibrationModel({
    required this.id,
    required this.name,
    required this.models,
    required this.testPiecesCount,
    this.resinRequired,
    this.height,
    this.evaluationGuideUrl,
  });

  factory CalibrationModel.fromJson(Map<String, dynamic> json) {
    final info = json['info'] as Map<String, dynamic>?;

    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    final parsedModels = toInt(json['models']) ?? 0;
    final parsedTestPieces =
        toInt(json['testPiecesCount']) ?? toInt(info?['testPiecesCount']);

    // Fallback chain: explicit testPiecesCount -> models -> legacy default (6).
    final effectiveTestPieces = (parsedTestPieces ?? parsedModels) > 0
        ? (parsedTestPieces ?? parsedModels)
        : 6;

    return CalibrationModel(
      id: toInt(json['id']) ?? 0,
      name: json['name'] as String,
      models: parsedModels,
      testPiecesCount: effectiveTestPieces,
      resinRequired: info?['resinRequired'] as int?,
      height: info?['height'] as int?,
      evaluationGuideUrl: info?['evaluationGuideUrl'] as String?,
    );
  }
}

class ResinsProvider extends ChangeNotifier {
  final _log = Logger('ResinsProvider');
  final BackendService _service;

  bool _loading = true;
  bool get isLoading => _loading;

  Object? _error;
  Object? get error => _error;

  List<ResinProfile> _resins = [];
  List<ResinProfile> get resins => List.unmodifiable(_resins);

  // In-memory cache of last fetched resins. Used to show cached data
  // immediately on startup without a loading spinner.
  static List<ResinProfile>? _cachedResins;
  static int? _cachedActiveProfileId;
  static String? _cachedActiveResinKey;

  // In-memory cache of calibration models and their image URLs
  static List<CalibrationModel>? _cachedCalibrationModels;
  static Map<int, String?>? _cachedCalibrationImageUrls;
  static int? _cachedSelectedCalibrationModelId;

  /// Convenience getter that returns only user-visible resins.
  ///
  /// Some backends (for example NanoDLP) expose "locked" or vendor
  /// profiles which are not intended to be selectable by end users
  /// during workflows like calibration. The provider detects such
  /// profiles via [detectLocked] and exposes this filtered list so UI
  /// code can consistently hide locked profiles without duplicating
  /// heuristics.
  List<ResinProfile> get userResins =>
      List.unmodifiable(_resins.where((r) => r.locked == false).toList());

  // Calibration models available for this backend
  List<CalibrationModel> _calibrationModels = [];
  List<CalibrationModel> get calibrationModels =>
      List.unmodifiable(_calibrationModels);

  // Cached calibration model images keyed by model id. We prefetch
  // these during refresh so UI can display thumbnails without issuing
  // additional backend calls.
  final Map<int, String?> _calibrationImageUrls = {};
  final Map<int, Future<void>> _inFlightCalibrationImageFetches = {};

  /// Returns the prefetched calibration image URL for [modelId], or null
  /// if not available yet or the backend didn't provide one.
  String? calibrationImageUrl(int modelId) => _calibrationImageUrls[modelId];

  /// Ensures an image URL exists for [modelId]. If not cached, fetch it now.
  ///
  /// This method deduplicates concurrent fetches per model id.
  Future<void> ensureCalibrationImage(
    int modelId, {
    bool notify = true,
  }) async {
    final existing = _calibrationImageUrls[modelId];
    if (existing != null && existing.isNotEmpty) return;

    final inFlight = _inFlightCalibrationImageFetches[modelId];
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = (() async {
      try {
        final url = await _service
            .getCalibrationImageUrl(modelId)
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
        if (url != null && url.isNotEmpty) {
          _calibrationImageUrls[modelId] = url;
          _cachedCalibrationImageUrls = Map.from(_calibrationImageUrls);
          if (notify) notifyListeners();
        }
      } catch (_) {
        // Keep graceful fallback when backend image endpoint fails.
      } finally {
        _inFlightCalibrationImageFetches.remove(modelId);
      }
    })();

    _inFlightCalibrationImageFetches[modelId] = future;
    await future;
  }

  int? _selectedCalibrationModelId;

  /// The currently-selected calibration model as determined by the
  /// provider. If not set, this will return the first available model
  /// or null when none are loaded.
  CalibrationModel? get selectedCalibrationModel {
    if (_selectedCalibrationModelId != null) {
      try {
        return _calibrationModels
            .firstWhere((m) => m.id == _selectedCalibrationModelId);
      } catch (_) {
        return null;
      }
    }
    return _calibrationModels.isNotEmpty ? _calibrationModels.first : null;
  }

  /// Explicitly set the provider's selected calibration model id.
  void setSelectedCalibrationModelId(int? id) {
    _selectedCalibrationModelId = id;
    _cachedSelectedCalibrationModelId = id;
    notifyListeners();
  }

  /// Return a recommended resin profile for calibration.
  ///
  /// Heuristic (in order):
  /// 1. If the backend reports an active/default profile id and it maps to a
  ///    non-locked resin, return that.
  /// 2. If [model] specifies a `resinRequired` id, try to match that profile id.
  /// 3. Return the first user-visible resin (non-locked), or null if none.
  ResinProfile? getRecommendedResin([CalibrationModel? model]) {
    try {
      // 1) Active/default profile
      if (_activeProfileId != null) {
        for (final r in _resins) {
          if (r.locked) continue;
          final meta = r.meta;
          final candidates = [
            meta['ProfileID'],
            meta['ProfileId'],
            meta['profileId'],
            meta['id'],
            meta['ID']
          ];
          for (final c in candidates) {
            if (c == null) continue;
            final parsed = int.tryParse('$c');
            if (parsed != null && parsed == _activeProfileId) {
              return r;
            }
          }
        }
      }

      // 2) Model-specified resin requirement
      if (model != null && model.resinRequired != null) {
        final req = model.resinRequired!;
        for (final r in _resins) {
          if (r.locked) continue;
          final meta = r.meta;
          final candidates = [
            meta['ProfileID'],
            meta['ProfileId'],
            meta['profileId'],
            meta['id'],
            meta['ID']
          ];
          for (final c in candidates) {
            if (c == null) continue;
            final parsed = int.tryParse('$c');
            if (parsed != null && parsed == req) {
              return r;
            }
          }
        }
      }

      // 3) Fallback to first user-visible resin
      for (final r in _resins) {
        if (!r.locked) return r;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int? _activeProfileId;
  int? get activeProfileId => _activeProfileId;

  String? _activeResinKey;
  String? get activeResinKey => _activeResinKey;

  ResinsProvider({BackendService? service})
      : _service = service ?? BackendService() {
    // Load cached data immediately if available (no loading spinner)
    if (_cachedResins != null && _cachedResins!.isNotEmpty) {
      _resins = List.from(_cachedResins!);
      _activeProfileId = _cachedActiveProfileId;
      _activeResinKey = _cachedActiveResinKey;
      _loading = false;
    }

    // Load cached calibration models and images
    if (_cachedCalibrationModels != null &&
        _cachedCalibrationModels!.isNotEmpty) {
      _calibrationModels = List.from(_cachedCalibrationModels!);
      if (_cachedCalibrationImageUrls != null) {
        _calibrationImageUrls.addAll(_cachedCalibrationImageUrls!);
      }
      if (_cachedSelectedCalibrationModelId != null) {
        _selectedCalibrationModelId = _cachedSelectedCalibrationModelId;
      }
      _loading = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_loading) {
        // Only notify if we had to show loading spinner
        notifyListeners();
      } else {
        // Cached data available, notify listeners and refresh in background
        notifyListeners();
        refresh();
      }
    });

    // If no cache, fetch immediately
    if ((_cachedResins == null || _cachedResins!.isEmpty) &&
        (_cachedCalibrationModels == null ||
            _cachedCalibrationModels!.isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
    }
  }

  /// Try to extract a numeric profile id from a resin metadata map.
  ///
  /// This centralizes the common heuristics used across the app so callers
  /// can reliably resolve ProfileID/ProfileId/profileId/id/ID values that
  /// may be strings or ints depending on the backend.
  static int? resolveProfileIdFromMeta(Map<String, dynamic>? meta) {
    if (meta == null) return null;
    try {
      final candidates = [
        meta['id'],
        meta['ProfileID'],
        meta['ProfileId'],
        meta['profileId'],
        meta['ID']
      ];
      for (final c in candidates) {
        if (c == null) continue;
        if (c is int) return c;
        final p = int.tryParse('$c');
        if (p != null) return p;
      }
    } catch (_) {}
    return null;
  }

  void _prefetchCalibrationImagesInBackground(
    List<CalibrationModel> models,
  ) {
    unawaited(() async {
      final missing = models.where((m) {
        final v = _calibrationImageUrls[m.id];
        return v == null || v.isEmpty;
      }).toList(growable: false);
      if (missing.isEmpty) return;

      // Run all missing-image fetches concurrently for faster fill-in.
      await Future.wait(
        missing.map((m) => ensureCalibrationImage(m.id, notify: false)),
      );

      _cachedCalibrationImageUrls = Map.from(_calibrationImageUrls);
      notifyListeners();
    }());
  }

  Future<void> refresh() async {
    _log.info('Refreshing resin profiles');
    // Only show loading spinner if we don't have cached data
    if (_cachedResins == null || _cachedResins!.isEmpty) {
      _loading = true;
      _error = null;
      notifyListeners();
    }

    try {
      // Fetch calibration models from backend
      final calibrationData = await _service.getCalibrationModels();
      _calibrationModels = calibrationData
          .map((json) => CalibrationModel.fromJson(json))
          .toList();
      _log.info('Loaded ${_calibrationModels.length} calibration models');

      // Ensure there's always a selected calibration model (default to first)
      if (_selectedCalibrationModelId == null &&
          _calibrationModels.isNotEmpty) {
        _selectedCalibrationModelId = _calibrationModels.first.id;
      }

      // Validate that the currently selected model still exists in the new list.
      // If not (e.g., due to backend changes), reset to first model or null.
      if (_selectedCalibrationModelId != null &&
          _calibrationModels.isNotEmpty) {
        final selectedExists =
            _calibrationModels.any((m) => m.id == _selectedCalibrationModelId);
        if (!selectedExists) {
          _selectedCalibrationModelId = _calibrationModels.first.id;
        }
      }

      // Cache calibration model metadata immediately so UI can render fast.
      _cachedCalibrationModels = List.from(_calibrationModels);
      _cachedSelectedCalibrationModelId = _selectedCalibrationModelId;

      // If selected/current model image is missing, force an immediate fetch.
      final selectedId = _selectedCalibrationModelId;
      if (selectedId != null) {
        final selectedImage = _calibrationImageUrls[selectedId];
        if (selectedImage == null || selectedImage.isEmpty) {
          await ensureCalibrationImage(selectedId, notify: false);
        }
      }

      // Start image prefetch in background (non-blocking).
      _prefetchCalibrationImagesInBackground(_calibrationModels);

      // Try common locations the backend might expose.
      final resp = await _service.listItems('Resins', 100, 0, '');

      List<Map<String, dynamic>> items = [];
      if (resp.containsKey('resins') && resp['resins'] is List) {
        items =
            (resp['resins'] as List).whereType<Map<String, dynamic>>().toList();
      } else if (resp.containsKey('files') && resp['files'] is List) {
        items =
            (resp['files'] as List).whereType<Map<String, dynamic>>().toList();
      }

      String friendlyName(Map<String, dynamic> m) {
        // Prefer explicit display fields provided by the backend.
        final candidates = [
          m['display_name'],
          m['label'],
          m['title'],
          m['name'],
        ];

        for (final c in candidates) {
          if (c is String && c.trim().isNotEmpty) return c.trim();
        }

        // Fallback to path basename if available
        final path = m['path'] as String?;
        if (path != null && path.isNotEmpty) {
          final parts = path.split('/');
          var base = parts.isNotEmpty ? parts.last : path;
          // strip extension
          final dot = base.lastIndexOf('.');
          if (dot > 0) base = base.substring(0, dot);
          base = base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
          if (base.isNotEmpty) return base;
        }

        return 'Unknown';
      }

      bool detectLocked(String name, Map<String, dynamic> meta) {
        // Prefer explicit backend signals if provided. NanoDLP's
        // profiles.json marks manufacturer profiles with
        // `ManufacturerLock: true`, which may sit top-level or inside the
        // nested merged meta map.
        try {
          final lockedMeta = meta['locked'];
          if (lockedMeta is bool) return lockedMeta;
          final candidates = <dynamic>[meta['ManufacturerLock']];
          final nested = meta['meta'];
          if (nested is Map<String, dynamic>) {
            candidates.add(nested['ManufacturerLock']);
          }
          for (final c in candidates) {
            if (c is bool) return c;
            if (c is num) return c != 0;
            if (c is String) {
              final v = c.trim().toLowerCase();
              if (v == 'true' || v == '1') return true;
              if (v == 'false' || v == '0') return false;
            }
          }
        } catch (_) {}

        // Heuristic: NanoDLP-style locked profiles often use short
        // uppercase bracket prefixes like "[AFP] Name". We treat
        // names with a short uppercase token in brackets (2-5 chars)
        // as locked. This avoids matching longer labels like
        // "[Template]" which are not intended to indicate a lock.
        final re = RegExp(r'^\[([A-Z]{2,5})\]\s*');
        return re.hasMatch(name);
      }

      _resins = items.map((m) {
        final name = friendlyName(m);
        final locked = detectLocked(name, m);
        return ResinProfile(name,
            path: m['path'] as String?, meta: m, locked: locked);
      }).toList(growable: false);

      // Cache the fetched resins for next app startup
      _cachedResins = List.from(_resins);

      // Ask the backend for its notion of the current default profile id.
      try {
        _activeProfileId = await _service.getDefaultProfileId();
      } catch (_) {
        _activeProfileId = null;
      }

      // If we have a default profile id, try to map it to a resin key from
      // the fetched resins list. We check common metadata keys used by
      // various backends (ProfileID, profileId, id, etc.). This keeps the
      // mapping logic centralized in the provider rather than in UI code.
      _activeResinKey = null;
      try {
        final did = _activeProfileId;
        if (did != null) {
          for (final r in _resins) {
            final meta = r.meta;
            final candidates = [
              meta['ProfileID'],
              meta['ProfileId'],
              meta['profileId'],
              meta['id'],
              meta['ID']
            ];
            for (final c in candidates) {
              if (c == null) continue;
              final parsed = int.tryParse('$c');
              if (parsed != null && parsed == did) {
                _activeResinKey = r.path ?? r.name;
                break;
              }
            }
            if (_activeResinKey != null) break;
          }
        }
      } catch (_) {
        _activeResinKey = null;
      }

      // Cache the active profile for next app startup
      _cachedActiveProfileId = _activeProfileId;
      _cachedActiveResinKey = _activeResinKey;

      _loading = false;
      _error = null;
    } catch (e, st) {
      _log.severe('Failed to fetch resins', e, st);
      _error = e;
      // Only clear resins if we don't have cached data
      if (_cachedResins == null || _cachedResins!.isEmpty) {
        _resins = [];
      }
      _loading = false;
    } finally {
      notifyListeners();
    }
  }

  /// Selects the given resin as the backend's default profile when possible.
  /// This will attempt to extract a numeric profile id from the resin's
  /// metadata (common keys: ProfileID, profileId, id, ID) and call the
  /// backend to persist the default profile. On success the provider's
  /// activeProfileId / activeResinKey are updated and listeners notified.
  Future<void> selectResin(ResinProfile resin) async {
    int? did;
    try {
      final meta = resin.meta;
      final candidates = [
        meta['ProfileID'],
        meta['ProfileId'],
        meta['profileId'],
        meta['id'],
        meta['ID']
      ];
      for (final c in candidates) {
        if (c == null) continue;
        final parsed = int.tryParse('$c');
        if (parsed != null) {
          did = parsed;
          break;
        }
      }
    } catch (_) {
      did = null;
    }

    if (did == null) {
      throw Exception('Resin does not contain a numeric ProfileID');
    }

    _log.info('Setting default profile id to $did');
    await _service.setDefaultProfileId(did);
    _activeProfileId = did;
    _activeResinKey = resin.path ?? resin.name;
    // Cache the new active profile for next app startup
    _cachedActiveProfileId = did;
    _cachedActiveResinKey = resin.path ?? resin.name;
    notifyListeners();
  }
}
