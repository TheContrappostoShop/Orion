import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';

part 'nano_profiles.g.dart';

@JsonSerializable(explicitToJson: true)
class NanoProfile {
  // Logger is kept for future debugging; suppress unused-field analyzer
  // warning when it's not referenced in some build configurations.
  // ignore: unused_field
  static final _log = Logger('NanoProfile');
  @JsonKey(name: 'ProfileID')
  final int? profileId;

  @JsonKey(name: 'Title')
  final String? title;

  // Preserve the raw payload for callers that need vendor-specific fields
  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String, dynamic> raw = {};

  NanoProfile({this.profileId, this.title, Map<String, dynamic>? raw}) {
    if (raw != null) this.raw = raw;
  }

  /// Returns true when this profile is considered "locked" by NanoDLP.
  ///
  /// NanoDLP commonly uses short uppercase bracket prefixes like "[AFP]"
  /// to indicate vendor-locked profiles. We treat short (2-5 uppercase
  /// chars) bracket tokens as a lock. Backends may also provide an explicit
  /// signal in the raw map — prefer that when present. NanoDLP's
  /// `profiles.json` marks manufacturer profiles with
  /// `ManufacturerLock: true`.
  bool get locked {
    try {
      final lm = raw['locked'];
      if (lm is bool) return lm;
      final ml = raw['ManufacturerLock'];
      if (ml is bool) return ml;
      if (ml is num) return ml != 0;
      if (ml is String) {
        final v = ml.trim().toLowerCase();
        if (v == 'true' || v == '1') return true;
        if (v == 'false' || v == '0') return false;
      }
    } catch (_) {}

    final name = (title ?? '').trim();
    final re = RegExp(r'^\[([A-Z]{2,5})\]\s*');
    return re.hasMatch(name);
  }

  factory NanoProfile.fromJson(Map<String, dynamic> json) =>
      _$NanoProfileFromJson(json);

  Map<String, dynamic> toJson() => _$NanoProfileToJson(this);

  /// Convenience wrapper that accepts decoded dynamic JSON (list or map)
  /// and returns a list of parsed profiles.
  static List<NanoProfile> parseFromJson(dynamic decoded) {
    if (decoded == null) return <NanoProfile>[];

    List<dynamic> entries = [];
    if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map) {
      for (final k in ['profiles', 'data', 'items']) {
        final v = decoded[k];
        if (v is List) {
          entries = v;
          break;
        }
      }
      if (entries.isEmpty) {
        entries = decoded.values.where((v) => v is Map || v is List).toList();
      }
    }

    final results = <NanoProfile>[];
    for (final e in entries) {
      if (e == null) continue;
      if (e is Map) {
        final profile = NanoProfile.fromJson(Map<String, dynamic>.from(e));
        profile.raw = Map<String, dynamic>.from(e);
        // validate
        final id = profile.profileId ?? 0;
        final t = (profile.title ?? '').trim();
        if (id == 0 || t.isEmpty) continue;
        results.add(profile);
      }
    }

    return results;
  }

  Map<String, dynamic> toMap() => {
        'name': _cleanTitle(),
        'display_name': _cleanTitle(),
        'label': _cleanTitle(),
        'title': _cleanTitle(),
        'path': '/profile/edit/simple/${profileId ?? 0}',
        'id': profileId ?? 0,
        // Expose a merged meta map that overlays NanoDLP's `CustomValues`
        // onto the top-level payload. This makes callers (UI/providers)
        // able to read vendor-specific keys without scanning multiple
        // places.
        'meta': mergedMeta(),
        'locked': locked,
      };

  String _cleanTitle() {
    final t = (title ?? '').trim();
    return t;
  }

  /// Return a merged metadata map where keys from `CustomValues` (if
  /// present) overlay top-level keys. This preserves the original `raw`
  /// payload while providing a convenient single map for UI consumers.
  Map<String, dynamic> mergedMeta() {
    final out = <String, dynamic>{};
    try {
      out.addAll(raw);
      final cv = raw['CustomValues'];
      if (cv is Map<String, dynamic>) {
        // Overlay custom values so they are directly reachable via common
        // key lookups (e.g. `meta['burn_in_cure_time']`).
        out.addAll(cv);
      }
    } catch (_) {
      // If anything goes wrong, fall back to raw map.
      return Map<String, dynamic>.from(raw);
    }

    return out;
  }

  /// Convenience helper that, given either a renderer-provided metadata map
  /// or a full decoded profile payload fetched from the backend, produces a
  /// single merged meta map (top-level + CustomValues overlay) and a
  /// canonical normalized map used by the Edit UI. This keeps NanoDLP
  /// specific merging/normalization inside the model layer so UI/providers
  /// remain backend-agnostic.
  static Future<Map<String, dynamic>> getResinProfileDetails(
      Map<String, dynamic> providedMeta, dynamic fetcher) async {
    // `fetcher` is expected to implement a `getProfileJson(int)` method
    // (BackendService or test doubles). We intentionally accept `dynamic`
    // to avoid importing service layers into the model's file.
    final out = <String, dynamic>{};

    // Try to detect a numeric profile id from the provided meta first.
    int? pid;
    try {
      for (final k in ['ProfileID', 'ProfileId', 'profileId', 'id', 'ID']) {
        final v = providedMeta[k];
        if (v == null) continue;
        final p = int.tryParse('$v');
        if (p != null) {
          pid = p;
          break;
        }
      }
    } catch (_) {
      pid = null;
    }

    Map<String, dynamic> fetched = {};
    if (pid != null) {
      try {
        // call getProfileJson on the fetcher if available
        final raw = await fetcher.getProfileJson(pid);
        if (raw is Map && raw.isNotEmpty) {
          fetched = Map<String, dynamic>.from(raw);
        }
      } catch (_) {
        // ignore fetch errors and fall back to provided meta
        fetched = {};
      }
    }

    // Produce a merged meta: prefer fetched payload when available,
    // otherwise use the provided meta. Always overlay CustomValues.
    final merged = <String, dynamic>{};
    if (fetched.isNotEmpty) {
      merged.addAll(fetched);
      try {
        final cv = fetched['CustomValues'];
        if (cv is Map<String, dynamic>) merged.addAll(cv);
      } catch (_) {}
    } else {
      merged.addAll(providedMeta);
      try {
        final cv = providedMeta['CustomValues'];
        if (cv is Map<String, dynamic>) merged.addAll(cv);
      } catch (_) {}
    }

    final normalized = normalizeForEdit(merged);
    out['meta'] = merged;
    out['normalized'] = normalized;
    try {
      //_log.fine('getResinProfileDetails pid=$pid mergedPreview=${merged.toString().substring(0, merged.toString().length.clamp(0, 800))} normalized=$normalized');
    } catch (_) {}
    return out;
  }

  /// Convert normalized canonical field names back to backend-specific field
  /// names for posting edits. This is the inverse of normalizeForEdit.
  static Map<String, dynamic> denormalizeForBackend(
      Map<String, dynamic> normalized) {
    final out = <String, dynamic>{};

    if (normalized.containsKey('burn_in_cure_time')) {
      final v = (normalized['burn_in_cure_time'] as num?)?.toDouble();
      if (v != null) out['SupportCureTime'] = v;
    }

    if (normalized.containsKey('normal_cure_time')) {
      final v = (normalized['normal_cure_time'] as num?)?.toDouble();
      if (v != null) out['CureTime'] = v;
    }

    if (normalized.containsKey('lift_after_print')) {
      final v = (normalized['lift_after_print'] as num?)?.toDouble();
      if (v != null) out['WaitHeight'] = v;
    }

    if (normalized.containsKey('burn_in_count')) {
      final v = (normalized['burn_in_count'] as num?)?.toInt();
      if (v != null) out['SupportLayerNumber'] = v;
    }

    if (normalized.containsKey('wait_after_cure')) {
      final v = (normalized['wait_after_cure'] as num?)?.toDouble();
      if (v != null) out['WaitAfterPrint'] = v;
    }

    if (normalized.containsKey('wait_after_life')) {
      final v = (normalized['wait_after_life'] as num?)?.toDouble();
      if (v != null) out['TopWait'] = v;
    }

    return out;
  }

  /// Normalize common resin edit fields into a canonical map used by the
  /// Edit UI. This overlays `CustomValues` and then maps a variety of
  /// NanoDLP key names into normalized keys consumers can rely on.
  static Map<String, dynamic> normalizeForEdit(Map<String, dynamic> meta) {
    final out = <String, dynamic>{};
    try {
      // Start with merged meta so CustomValues are included.
      final merged = <String, dynamic>{};
      merged.addAll(meta);
      try {
        final cv = meta['CustomValues'];
        if (cv is Map<String, dynamic>) merged.addAll(cv);
      } catch (_) {}

      dynamic pick(List<String> candidates) {
        for (final k in candidates) {
          if (!merged.containsKey(k)) continue;
          final v = merged[k];
          if (v == null) continue;
          return v;
        }
        return null;
      }

      int toInt(dynamic v, int fallback) {
        if (v == null) return fallback;
        if (v is int) return v;
        if (v is double) return v.round();
        final p = int.tryParse('$v');
        if (p != null) return p;
        final pd = double.tryParse('$v');
        if (pd != null) return pd.round();
        return fallback;
      }

      double toDouble(dynamic v, double fallback) {
        if (v == null) return fallback;
        if (v is double) return v;
        if (v is int) return v.toDouble();
        final pd = double.tryParse('$v');
        return pd ?? fallback;
      }

      // Normal (per-layer) cure time — preserve fractional seconds when present
      out['normal_cure_time'] =
          toDouble(pick(['normal_cure_time', 'CureTime']), 8.0);

      // Burn-in layer cure time — preserve fractional seconds when present
      out['burn_in_cure_time'] =
          toDouble(pick(['burn_in_cure_time', 'SupportCureTime']), 10.0);

      // Lift distance after normal layers (mm). NanoDLP/Athena store this in
      // `WaitHeight` ("Lift After Print", "Normal Lift Distance"). It is not
      // `PdPeelMinLiftDistance`, which is the floor of the peel-detection
      // lift, and not `ZLiftDistance`, which is a runtime gcode placeholder
      // that never appears in a stored profile.
      out['lift_after_print'] =
          toDouble(pick(['lift_after_print', 'WaitHeight']), 5.0);

      // Burn-in count (number of burn-in layers). `TransitionalLayer` is a
      // 0/1 enable flag, not a count, so it must not be used here.
      out['burn_in_count'] =
          toInt(pick(['burn_in_count', 'SupportLayerNumber']), 3);

      // Wait after cure (seconds) — NanoDLP's `WaitAfterPrint`, the pause
      // after layer exposure and before the lift.
      out['wait_after_cure'] =
          toDouble(pick(['wait_after_cure', 'WaitAfterPrint']), 2.0);

      // Wait after lift (seconds) — NanoDLP's `TopWait`, the pause after the
      // normal-layer lift that lets resin flow back.
      out['wait_after_life'] =
          toDouble(pick(['wait_after_life', 'TopWait']), 2.0);
    } catch (_) {
      // On any failure return reasonable defaults
      return {
        'normal_cure_time': 8.0,
        'burn_in_cure_time': 10.0,
        'lift_after_print': 5.0,
        'burn_in_count': 3,
        'wait_after_cure': 2.0,
        'wait_after_life': 2.0,
      };
    }
    return out;
  }
}
