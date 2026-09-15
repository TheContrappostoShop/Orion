/*
* Orion - Config
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

// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:orion/util/install_locator.dart';

class OrionConfig {
  final _logger = Logger('OrionConfig');
  late final String _configPath;
  // Cache the detected config path so repeated instantiations (common in
  // providers during app startup) don't repeatedly probe the filesystem and
  // spam the logs. This is safe because config path is global for a running
  // runtime instance and is inexpensive to validate if needed.
  static String? _cachedConfigPath;
  // Simple change listener registry so other services can react when
  // `orion.cfg` is updated via _writeConfig(). Listeners should be
  // lightweight and avoid throwing.
  static final List<VoidCallback> _changeListeners = [];

  /// The directory containing `orion.cfg`, or null if not yet resolved.
  /// Resolved on first [OrionConfig] instantiation (happens early in startup).
  static String? get configDirectory => _cachedConfigPath;

  /// Register a callback to be invoked after `orion.cfg` is written.
  static void addChangeListener(VoidCallback cb) {
    if (!_changeListeners.contains(cb)) _changeListeners.add(cb);
  }

  /// Remove a previously-registered change listener.
  static void removeChangeListener(VoidCallback cb) {
    _changeListeners.remove(cb);
  }

  OrionConfig() {
    // If we've already detected the config path in a previous instance,
    // reuse it to avoid repeated filesystem probes and logging spam.
    if (_cachedConfigPath != null) {
      _configPath = _cachedConfigPath!;
      return;
    }
    // Try a more deterministic approach first: locate the directory that
    // contains the application shared-object / engine binary (e.g. app.so,
    // libapp.so, or the packaged `orion` binary). This is more reliable
    // than relying solely on the flutter-pi runtime CWD because installers
    // typically place the engine and packaged vendor files next to each
    // other.
    try {
      final engineDir = findEngineDir();
      if (engineDir != null && engineDir.isNotEmpty) {
        // If the engine dir looks promising, prefer it, but only return
        // immediately when we can confirm a config file is located either
        // in that directory or adjacent (one level up) or as a root-level
        // file like /opt/orion.cfg. Many installers place shared files in
        // the parent of the engine dir (for example engineDir=="/opt/orion"
        // while config is "/opt/orion.cfg"). Attempt those checks first
        // to avoid prematurely returning a directory that doesn't contain
        // our config files.
        final engineConfig = path.join(engineDir, 'orion.cfg');
        final engineVendor = path.join(engineDir, 'vendor.cfg');
        final parentDir = path.dirname(engineDir);
        final parentConfig = path.join(parentDir, 'orion.cfg');
        final parentVendor = path.join(parentDir, 'vendor.cfg');
        final rootCandidateConfig = path.join('/opt', 'orion.cfg');
        final rootCandidateVendor = path.join('/opt', 'vendor.cfg');

        if (File(engineConfig).existsSync() ||
            File(engineVendor).existsSync()) {
          _configPath = engineDir;
          _cachedConfigPath = _configPath;
          _logger.fine('OrionConfig: located engine dir -> $_configPath');
          return;
        }

        if (File(parentConfig).existsSync() ||
            File(parentVendor).existsSync()) {
          _configPath = parentDir;
          _cachedConfigPath = _configPath;
          _logger.fine(
              'OrionConfig: found config adjacent to engine -> $_configPath');
          return;
        }

        if (File(rootCandidateConfig).existsSync() ||
            File(rootCandidateVendor).existsSync()) {
          _configPath = '/opt';
          _cachedConfigPath = _configPath;
          _logger.fine('OrionConfig: found /opt config file; using /opt');
          return;
        }

        // If none of the above config files exist, fall through to the
        // autodetection logic below but keep the engineDir as a candidate
        // to be searched later.
        _logger.fine('OrionConfig: engine dir probe found $engineDir; '
            'no adjacent config file, will continue autodetection');
        // add engineDir as a candidate by setting a temporary variable that
        // will be used below when building candidates list
        // (we'll re-call _findEngineDir indirectly by using execDir below).
      }
    } catch (e) {
      _logger.fine('OrionConfig: engine dir probe failed: $e');
    }
    // Attempt to determine the correct on-disk location for orion.cfg/vendor.cfg
    // Priority:
    // 1. ORION_CFG env var (can be a directory or a full path to a .cfg file)
    // 2. Look for common install/config locations relative to the executable,
    //    script, HOME, and known install prefixes like /opt and /home/pi
    // 3. Fallback to current working directory
    String? envPath = Platform.environment['ORION_CFG'];
    if (envPath != null && envPath.isNotEmpty) {
      try {
        // If user provided a full path to a config file, use its directory
        if (envPath.endsWith('.cfg') && File(envPath).existsSync()) {
          _configPath = path.dirname(envPath);
          _cachedConfigPath = _configPath;
          return;
        }
        // Otherwise assume it's a directory
        _configPath = envPath;
        return;
      } catch (_) {
        // Ignore and fall through to autodetection
      }
    }

    // Candidate directories to search for orion.cfg
    final candidates = <String>[];

    // If engine dir probe produced nothing earlier, we still want to add a
    // second-chance engine-dir candidate using resolvedExecutable's parent
    // so later vendor.cfg/orion.cfg checks can find packaged files.
    try {
      final execDir = path.dirname(Platform.resolvedExecutable);
      if (execDir.isNotEmpty && !candidates.contains(execDir)) {
        candidates.add(execDir);
      }
    } catch (_) {}

    try {
      // Current working directory
      candidates.add(Directory.current.path);
    } catch (_) {}

    try {
      // Directory containing the running executable (useful for packaged installs)

      final execDir = path.dirname(Platform.resolvedExecutable);
      if (execDir.isNotEmpty) {
        candidates.add(execDir);
      }
    } catch (_) {}

    try {
      // Directory containing the script (Dart VM)
      final scriptDir = path.dirname(Platform.script.toFilePath());
      if (scriptDir.isNotEmpty) {
        candidates.add(scriptDir);
      }
    } catch (_) {}

    // Common system locations
    candidates.add('/opt');
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(home);
    }
    candidates.add('/home/pi');

    // Also consider some absolute config file locations that are commonly used
    final candidateFiles = <String>[];
    for (final d in candidates) {
      candidateFiles.add(path.join(d, 'orion.cfg'));
    }
    // Also check root-level installer locations like /opt/orion.cfg and /home/pi/orion.cfg
    candidateFiles.add('/opt/orion.cfg');
    if (home != null && home.isNotEmpty) {
      candidateFiles.add(path.join(home, 'orion.cfg'));
    }
    candidateFiles.add('/home/pi/orion.cfg');

    for (final f in candidateFiles) {
      try {
        if (File(f).existsSync()) {
          _configPath = path.dirname(f);
          _cachedConfigPath = _configPath;
          _logger
              .fine('OrionConfig: found orion.cfg at $f; using $_configPath');
          return;
        }
      } catch (_) {}
    }

    // If we didn't find an orion.cfg, try to locate a vendor.cfg and use
    // its directory. Some installations ship only vendor.cfg alongside the
    // runtime and expect the app to pick it up (e.g. /opt/vendor.cfg).
    final vendorCandidateFiles = <String>[];
    for (final d in candidates) {
      vendorCandidateFiles.add(path.join(d, 'vendor.cfg'));
    }
    vendorCandidateFiles.add('/opt/vendor.cfg');
    if (home != null && home.isNotEmpty) {
      vendorCandidateFiles.add(path.join(home, 'vendor.cfg'));
    }
    vendorCandidateFiles.add('/home/pi/vendor.cfg');

    for (final f in vendorCandidateFiles) {
      try {
        if (File(f).existsSync()) {
          _configPath = path.dirname(f);
          _cachedConfigPath = _configPath;
          _logger
              .fine('OrionConfig: found vendor.cfg at $f; using $_configPath');
          return;
        }
      } catch (_) {}
    }

    // Fallback to current working directory if nothing found
    try {
      _configPath = Directory.current.path;
      _configPath = Directory.current.path;
      _cachedConfigPath = _configPath;
      _logger.fine(
          'OrionConfig: no config found; falling back to CWD=$_configPath');
    } catch (_) {
      _configPath = '.';
      _cachedConfigPath = _configPath;
    }
  }

  /// Return the resolved configuration directory path used by this
  /// OrionConfig instance. This is a stable, runtime-detected directory
  /// where packaged config files (orion.cfg/vendor.cfg) are located and
  /// can be useful for locating other install-adjacent resources.
  String getConfigPath() => _configPath;

  ThemeMode getThemeMode() {
    var config = _getConfig();
    var themeMode = config['general']?['themeMode'] ?? 'light';
    return themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  void setThemeMode(ThemeMode themeMode) {
    var config = _getConfig();
    config['general'] ??= {};
    config['general']['themeMode'] =
        themeMode == ThemeMode.dark ? 'dark' : 'light';
    _writeConfig(config);
  }

  void setFlag(String flagName, bool value, {String category = 'general'}) {
    var config = _getConfig();
    config[category] ??= {};

    // Optimization: Only write if value actually changed
    if (config[category][flagName] == value) return;

    config[category][flagName] = value;
    _logger.config('setFlag: $flagName to $value');

    _writeConfig(config);
  }

  void setString(String key, String value, {String category = 'general'}) {
    var config = _getConfig();
    config[category] ??= {};

    // Optimization: Only write if value actually changed
    if (config[category][key] == value) return;

    config[category][key] = value;

    if (value == '') {
      _logger.config('setString: cleared $key');
    } else {
      _logger.config('setString: $key to ${value == '' ? 'NULL' : value}');
    }

    // NOTE: we intentionally do not write other flags here. Use explicit
    // configuration management to keep side-effects visible.

    _writeConfig(config);
  }

  bool getFlag(String flagName, {String category = 'general'}) {
    var config = _getConfig();
    return config[category]?[flagName] ?? false;
  }

  /// Read a nested object stored at `category.key`, or null when absent or
  /// not an object.  Used for records that have more than one field (e.g. the
  /// persisted leveling verification record).
  Map<String, dynamic>? getJson(String key, {String category = 'general'}) {
    final config = _getConfig();
    try {
      final categoryMap = config[category];
      if (categoryMap is Map && categoryMap[key] is Map) {
        return Map<String, dynamic>.from(categoryMap[key] as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Persist [value] as a nested object at `category.key`.  Passing null
  /// removes the key.  No-op when the stored value is already identical.
  void setJson(String key, Map<String, dynamic>? value,
      {String category = 'general'}) {
    var config = _getConfig();
    config[category] ??= {};

    final existing = config[category][key];
    if (value == null) {
      if (existing == null) return;
      config[category].remove(key);
      _logger.config('setJson: cleared $key');
    } else {
      if (existing is Map && jsonEncode(existing) == jsonEncode(value)) return;
      config[category][key] = value;
      _logger.config('setJson: $key updated');
    }

    _writeConfig(config);
  }

  String getString(String key, {String category = 'general'}) {
    var config = _getConfig();
    try {
      final categoryMap = config[category];
      if (categoryMap is Map && categoryMap.containsKey(key)) {
        final v = categoryMap[key];
        return v is String ? v : v?.toString() ?? '';
      }

      // Support dotted keys and nested vendor maps. E.g. 'nanodlp.base_url'
      // may be represented in config as:
      // advanced: { 'nanodlp.base_url': 'http://...' }
      // or
      // advanced: { 'nanodlp': { 'base_url': 'http://...' } }
      if (key.contains('.') && categoryMap is Map) {
        final parts = key.split('.');
        dynamic node = categoryMap;
        for (var part in parts) {
          if (node is Map && node.containsKey(part)) {
            node = node[part];
            continue;
          }
          // Try snake_case -> camelCase fallback (base_url -> baseUrl)
          final camel = _snakeToCamel(part);
          if (node is Map && node.containsKey(camel)) {
            node = node[camel];
            continue;
          }
          // Try lowercase variant
          final lower = part.toLowerCase();
          if (node is Map && node.containsKey(lower)) {
            node = node[lower];
            continue;
          }
          node = null;
          break;
        }
        if (node != null) return node is String ? node : node?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  String _snakeToCamel(String s) {
    if (!s.contains('_')) return s;
    final parts = s.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((p) =>
                p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}')
            .join();
  }

  void toggleFlag(String flagName, {String category = 'general'}) {
    bool currentValue = getFlag(flagName, category: category);
    setFlag(flagName, !currentValue, category: category);
  }

  Color getThemeSeed(String type) {
    var config = _getConfig();

    var seedHex = '#00000000';

    if (type == 'vendor') {
      seedHex = config['vendor']?['vendorThemeSeed'] ?? '#00000000';
    } else if (type == 'primary') {
      seedHex = config['general']?['themeSeed'] ?? '#00000000';
    }
    // Remove the '#' and parse the hex color
    return Color(int.parse(seedHex.replaceAll('#', ''), radix: 16));
  }

  /// Get gradient colors for glass theme mode
  List<Color> getThemeGradient(String type) {
    var config = _getConfig();

    List<String>? gradientHex;

    if (type == 'vendor') {
      gradientHex = config['vendor']?['vendorThemeGradient']?.cast<String>();
    } else if (type == 'primary') {
      gradientHex = config['general']?['themeGradient']?.cast<String>();
    }

    // If no gradient is defined, return empty list (will auto-generate)
    if (gradientHex == null || gradientHex.isEmpty) {
      return [];
    }

    // Convert hex strings to Color objects
    return gradientHex.map((hex) {
      return Color(int.parse(hex.replaceAll('#', ''), radix: 16));
    }).toList();
  }

  /// Set gradient colors for glass theme mode
  void setThemeGradient(List<Color> gradient, {String category = 'general'}) {
    var config = _getConfig();
    config[category] ??= {};

    if (gradient.isEmpty) {
      // Remove the gradient key completely when clearing
      config[category].remove('themeGradient');
    } else {
      // Convert colors to hex strings using toArgb()
      final gradientHex = gradient.map((color) {
        final alpha = ((color.a * 255.0).round() & 0xff)
            .toRadixString(16)
            .padLeft(2, '0');
        final red = ((color.r * 255.0).round() & 0xff)
            .toRadixString(16)
            .padLeft(2, '0');
        final green = ((color.g * 255.0).round() & 0xff)
            .toRadixString(16)
            .padLeft(2, '0');
        final blue = ((color.b * 255.0).round() & 0xff)
            .toRadixString(16)
            .padLeft(2, '0');
        return '#$alpha$red$green$blue';
      }).toList();

      config[category]['themeGradient'] = gradientHex;
    }

    _writeConfig(config);
  }

  Map<String, dynamic> _getVendorConfig() {
    var fullPath = path.join(_configPath, 'vendor.cfg');
    var vendorFile = File(fullPath);

    if (!vendorFile.existsSync() || vendorFile.readAsStringSync().isEmpty) {
      return {};
    }

    try {
      final base =
          Map<String, dynamic>.from(json.decode(vendorFile.readAsStringSync()));
      // Apply any vendor overrides if present
      final overrides = _getVendorOverrideConfig();
      if (overrides.isNotEmpty) {
        return _mergeConfigs(base, overrides);
      }
      return base;
    } catch (e) {
      _logger.warning('Failed to parse vendor.cfg: $e');
      return {};
    }
  }

  Map<String, dynamic> _getVendorOverrideConfig() {
    var fullPath = path.join(_configPath, 'vendor_overrides.cfg');
    var file = File(fullPath);
    if (!file.existsSync() || file.readAsStringSync().isEmpty) return {};
    try {
      return Map<String, dynamic>.from(json.decode(file.readAsStringSync()));
    } catch (e) {
      _logger.warning('Failed to parse vendor_overrides.cfg: $e');
      return {};
    }
  }

  /// Read only the packaged vendor.cfg (do not include runtime vendor overrides).
  /// This ensures display names and vendor-provided metadata come from the
  /// vendor's packaged configuration rather than any runtime override file.
  Map<String, dynamic> _getVendorBaseConfig() {
    var fullPath = path.join(_configPath, 'vendor.cfg');
    var vendorFile = File(fullPath);

    if (!vendorFile.existsSync() || vendorFile.readAsStringSync().isEmpty) {
      return {};
    }

    try {
      return Map<String, dynamic>.from(
          json.decode(vendorFile.readAsStringSync()));
    } catch (e) {
      _logger.warning('Failed to parse vendor.cfg (base): $e');
      return {};
    }
  }

  // --- User-managed feature overrides ---
  /// Set a single user feature flag which takes precedence over Athena and vendor flags.
  void setUserFeatureFlag(String key, bool value) {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var file = File(fullPath);
    Map<String, dynamic> userConfig = {};
    if (file.existsSync() && file.readAsStringSync().isNotEmpty) {
      try {
        userConfig =
            Map<String, dynamic>.from(json.decode(file.readAsStringSync()));
      } catch (_) {
        userConfig = {};
      }
    }

    userConfig['userFeatureFlags'] ??= {};
    final uff = Map<String, dynamic>.from(userConfig['userFeatureFlags']);
    uff[key] = value;
    userConfig['userFeatureFlags'] = uff;

    try {
      final encoder = const JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(userConfig));
    } catch (e) {
      _logger.warning(
          'Failed to write orion.cfg while setting user feature flag: $e');
    }
  }

  /// Set a hardware feature under userFeatureFlags.hardwareFeatures
  void setUserHardwareFeature(String key, bool value) {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var file = File(fullPath);
    Map<String, dynamic> userConfig = {};
    if (file.existsSync() && file.readAsStringSync().isNotEmpty) {
      try {
        userConfig =
            Map<String, dynamic>.from(json.decode(file.readAsStringSync()));
      } catch (_) {
        userConfig = {};
      }
    }

    userConfig['userFeatureFlags'] ??= {};
    final uff = Map<String, dynamic>.from(userConfig['userFeatureFlags']);
    uff['hardwareFeatures'] ??= {};
    final hw = Map<String, dynamic>.from(uff['hardwareFeatures']);
    hw[key] = value;
    uff['hardwareFeatures'] = hw;
    userConfig['userFeatureFlags'] = uff;

    try {
      final encoder = const JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(userConfig));
    } catch (e) {
      _logger.warning(
          'Failed to write orion.cfg while setting user hardware feature: $e');
    }
  }

  /// Clear all user-managed feature overrides
  void clearUserFeatureOverrides() {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var file = File(fullPath);
    Map<String, dynamic> userConfig = {};
    if (file.existsSync() && file.readAsStringSync().isNotEmpty) {
      try {
        userConfig =
            Map<String, dynamic>.from(json.decode(file.readAsStringSync()));
      } catch (_) {
        userConfig = {};
      }
    }

    if (userConfig.containsKey('userFeatureFlags')) {
      userConfig.remove('userFeatureFlags');
      try {
        final encoder = const JsonEncoder.withIndent('  ');
        file.writeAsStringSync(encoder.convert(userConfig));
      } catch (e) {
        _logger.warning(
            'Failed to write orion.cfg while clearing user feature overrides: $e');
      }
    }
  }

  /// Persist vendor overrides which are merged on top of `vendor.cfg` at runtime.
  /// Persist vendor overrides. Instead of keeping a separate file, merge the
  /// provided overrides into `orion.cfg` under the `vendor` section.
  ///
  /// Passing an empty map will remove any previously-applied vendor override
  /// keys we manage (featureFlags and vendorMachineName) from `orion.cfg`.
  void setVendorOverrides(Map<String, dynamic> overrides) {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var file = File(fullPath);

    Map<String, dynamic> userConfig = {};
    if (file.existsSync() && file.readAsStringSync().isNotEmpty) {
      try {
        userConfig =
            Map<String, dynamic>.from(json.decode(file.readAsStringSync()));
      } catch (e) {
        _logger.warning(
            'Failed to parse existing orion.cfg while applying overrides: $e');
        // Fall back to empty config so we don't crash.
        userConfig = {};
      }
    }

    // We no longer write overrides into the `vendor` section. Instead, apply
    // overrides into the primary (top-level) `featureFlags` block so they are
    // visible and portable with `orion.cfg`. This keeps vendor.* untouched.
    if (overrides.isEmpty) {
      // No-op when empty to avoid accidentally removing user values.
      _logger.fine(
          'setVendorOverrides called with empty overrides; no changes made');
      return;
    }

    if (overrides.containsKey('featureFlags')) {
      final newFF = Map<String, dynamic>.from(overrides['featureFlags'] ?? {});
      final existingTopFF =
          Map<String, dynamic>.from(userConfig['featureFlags'] ?? {});
      userConfig['featureFlags'] = _mergeConfigs(existingTopFF, newFF);
    }

    // We intentionally ignore overrides['vendor'] here; if callers need to
    // update other vendor-specific keys (like vendorMachineName) they should
    // use the explicit public helpers (setString / setFlag) so changes are
    // visible in the main config sections.

    // If overrides contains a 'vendor' section we do NOT create a
    // vendor_overrides.cfg. Instead, copy vendor-provided display-name
    // mappings (featureNames) and canonical machineModelName into the
    // top-level orion.cfg so they are portable and do not require a
    // separate runtime vendor file.
    if (overrides.containsKey('vendor')) {
      try {
        final newVendor = Map<String, dynamic>.from(overrides['vendor'] ?? {});

        // If vendor provided friendly names for features, merge them into
        // top-level `featureNames` in orion.cfg so getFeatureDisplayName
        // will pick them up.
        if (newVendor.containsKey('featureNames')) {
          userConfig['featureNames'] ??= {};
          final existingNames =
              Map<String, dynamic>.from(userConfig['featureNames'] ?? {});
          final incomingNames =
              Map<String, dynamic>.from(newVendor['featureNames'] ?? {});
          userConfig['featureNames'] =
              _mergeConfigs(existingNames, incomingNames);
        }

        // If vendor provided a canonical machine model name, write it into
        // the canonical `machine.machineModelName` slot of orion.cfg.
        if (newVendor.containsKey('machineModelName')) {
          userConfig['machine'] ??= {};
          userConfig['machine']['machineModelName'] =
              newVendor['machineModelName'];
        }
      } catch (e) {
        _logger.warning('Failed to merge vendor overrides into orion.cfg: $e');
      }
    }

    // Persist the modified orion.cfg (we may have updated featureNames or
    // machine.machineModelName above).
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      file.writeAsStringSync(encoder.convert(userConfig));
    } catch (e) {
      _logger.warning('Failed to write orion.cfg while applying overrides: $e');
    }
  }

  /// Return the vendor-declared machine model name.
  String getMachineModelName() {
    // Prefer the canonical machine section in orion.cfg when present
    try {
      final cfg = _getConfig();
      final machine = cfg['machine'];
      if (machine is Map &&
          machine['machineModelName'] is String &&
          (machine['machineModelName'] as String).isNotEmpty) {
        return machine['machineModelName'] as String;
      }
    } catch (_) {}

    var vendor = _getVendorConfig();
    return vendor['machineModelName'] ??
        vendor['vendor']?['machineModelName'] ??
        vendor['vendor']?['vendorMachineName'] ??
        '3D Printer';
  }

  /// Read the vendor `homePosition` setting. Expected values: 'up'|'down'.
  /// Defaults to 'down' when absent or unrecognized.
  String getHomePosition() {
    final vendor = _getVendorConfig();
    final hp = vendor['homePosition'] ?? vendor['vendor']?['homePosition'];
    if (hp is String) {
      final v = hp.toLowerCase();
      if (v == 'up' || v == 'down') return v;
    }
    return 'down';
  }

  /// Convenience boolean: true when configured 'up'
  bool isHomePositionUp() => getHomePosition() == 'up';

  /// Read the vendor `levelingMode` setting (e.g. "athena2", "manual", "").
  /// Checks top-level `levelingMode` first, then `vendor.levelingMode`.
  /// Returns empty string when absent (meaning no assisted leveling available).
  String getLevelingMode() {
    final vendor = _getVendorConfig();
    if (vendor['levelingMode'] is String) {
      return (vendor['levelingMode'] as String).trim().toLowerCase();
    }
    if (vendor['vendor'] is Map) {
      final v = vendor['vendor']['levelingMode'];
      if (v is String) return v.trim().toLowerCase();
    }
    return '';
  }

  /// Whether the printer is currently considered leveled — i.e. a leveling
  /// session has completed successfully and its Z offset is still valid.
  ///
  /// Persisted in `orion.cfg` under the `leveling` section.  Starts false;
  /// set true when a leveling session completes successfully, and reset to
  /// false when a Verify Leveling run starts (which clears the Z offset).
  bool isLeveled() => getFlag('isLeveled', category: 'leveling');

  /// Set whether the printer is currently considered leveled.
  void setLeveled(bool value) =>
      setFlag('isLeveled', value, category: 'leveling');

  /// Summary of the last leveling check that passed, or null when none has.
  /// Written by the wizard and read by the Verify Leveling screen; kept in
  /// `orion.cfg` alongside [isLeveled] so the verification state stays with
  /// the machine state instead of with the human-readable log.
  Map<String, dynamic>? getLastPassedLevelingSession() =>
      getJson('lastPassedSession', category: 'leveling');

  /// Persist the summary of the last passed leveling check.
  void setLastPassedLevelingSession(Map<String, dynamic>? session) =>
      setJson('lastPassedSession', session, category: 'leveling');

  /// The persisted leveling screen type id (e.g. `'tempered_glass'`,
  /// `'wave_release_film'`), or empty when not configured.
  String getScreenType() => getString('screenType', category: 'leveling');

  /// Persist the leveling screen type id.
  void setScreenType(String id) =>
      setString('screenType', id, category: 'leveling');

  /// The persisted leveling variant/arm id (e.g. `'pro'`, `'regular'`), or
  /// empty when not configured.
  String getLevelingVariant() => getString('variant', category: 'leveling');

  /// Persist the leveling variant/arm id.
  void setLevelingVariant(String id) =>
      setString('variant', id, category: 'leveling');

  /// The Z offset applied by the last leveling session (mm), or null when
  /// not recorded.  Manual adjustments are stored separately as an override
  /// so the leveling-settings edit range stays anchored to this original.
  double? getBaseZOffset() {
    final s = getString('baseZOffset', category: 'leveling');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  void setBaseZOffset(double value) =>
      setString('baseZOffset', value.toString(), category: 'leveling');

  /// Manual Z-offset adjustment (mm) added on top of [getBaseZOffset].
  /// The effective offset is `base + override`.
  double getZOffsetOverride() {
    final s = getString('zOffsetOverride', category: 'leveling');
    return double.tryParse(s) ?? 0.0;
  }

  void setZOffsetOverride(double value) =>
      setString('zOffsetOverride', value.toString(), category: 'leveling');

  /// Query a boolean feature flag from the vendor `featureFlags` section.
  /// Returns [defaultValue] when not present.
  bool getFeatureFlag(String key, {bool defaultValue = false}) {
    // Priority: userFeatureFlags (manual overrides) -> top-level featureFlags
    // (including Athena-applied overrides) -> vendor.featureFlags -> default
    try {
      final cfg = _getConfig();
      final userFF = cfg['userFeatureFlags'];
      if (userFF is Map && userFF.containsKey(key)) return userFF[key] == true;

      final topFF = cfg['featureFlags'];
      if (topFF is Map && topFF.containsKey(key)) return topFF[key] == true;
    } catch (_) {}

    var vendor = _getVendorConfig();
    final flags = vendor['featureFlags'];
    if (flags is Map && flags.containsKey(key)) {
      return flags[key] == true;
    }
    return defaultValue;
  }

  // --- Convenience accessors for known vendor feature flags ---
  bool enableBetaFeatures() => getFeatureFlag('enableBetaFeatures');
  bool enableDeveloperSettings() => getFeatureFlag('enableDeveloperSettings');
  bool enableAdvancedSettings() => getFeatureFlag('enableAdvancedSettings');
  bool enableExperimentalFeatures() =>
      getFeatureFlag('enableExperimentalFeatures');
  bool enableResinProfiles() => getFeatureFlag('enableResinProfiles');
  bool enableCustomName() => getFeatureFlag('enableCustomName');
  bool enablePowerControl() => getFeatureFlag('enablePowerControl');

  /// Return nested `hardwareFeatures` map (may be empty)
  Map<String, dynamic> getHardwareFeatures() {
    // Merge priority: userFeatureFlags.hardwareFeatures -> top-level
    // featureFlags.hardwareFeatures -> vendor.featureFlags.hardwareFeatures
    final merged = <String, dynamic>{};
    try {
      final cfg = _getConfig();
      final userFF = cfg['userFeatureFlags'];
      if (userFF is Map && userFF['hardwareFeatures'] is Map) {
        merged.addAll(Map<String, dynamic>.from(userFF['hardwareFeatures']));
      }
      final topFF = cfg['featureFlags'];
      if (topFF is Map && topFF['hardwareFeatures'] is Map) {
        // Only add keys not already present from userFF
        final topHw = Map<String, dynamic>.from(topFF['hardwareFeatures']);
        topHw.forEach((k, v) {
          if (!merged.containsKey(k)) merged[k] = v;
        });
      }
    } catch (_) {}

    var vendor = _getVendorConfig();
    final flags = vendor['featureFlags'];
    if (flags is Map && flags['hardwareFeatures'] is Map<String, dynamic>) {
      final vendHw = Map<String, dynamic>.from(flags['hardwareFeatures']);
      vendHw.forEach((k, v) {
        if (!merged.containsKey(k)) merged[k] = v;
      });
    }

    return merged;
  }

  /// Generic helper to read a hardware feature boolean from
  /// `featureFlags.hardwareFeatures`.
  bool getHardwareFeature(String key, {bool defaultValue = false}) {
    final hw = getHardwareFeatures();
    if (hw.containsKey(key)) return hw[key] == true;
    return defaultValue;
  }

  // --- Convenience accessors for common hardware features ---
  bool hasHeatedChamber() => getHardwareFeature('hasHeatedChamber');
  bool hasHeatedVat() => getHardwareFeature('hasHeatedVat');
  bool hasCamera() => getHardwareFeature('hasCamera');
  bool hasAirFilter() => getHardwareFeature('hasAirFilter');
  bool hasForceSensor() => getHardwareFeature('hasForceSensor');

  /// Return the full featureFlags map (may be empty)
  Map<String, dynamic> getFeatureFlags() {
    // Merge userFeatureFlags (highest) -> top-level featureFlags -> vendor
    final merged = <String, dynamic>{};
    try {
      final cfg = _getConfig();
      final userFF = cfg['userFeatureFlags'];
      if (userFF is Map<String, dynamic>) {
        merged.addAll(Map<String, dynamic>.from(userFF));
      }
      final topFF = cfg['featureFlags'];
      if (topFF is Map<String, dynamic>) {
        topFF.forEach((k, v) {
          if (!merged.containsKey(k)) merged[k] = v;
        });
      }
    } catch (_) {}

    final vendor = _getVendorConfig();
    final vflags = vendor['featureFlags'];
    if (vflags is Map<String, dynamic>) {
      vflags.forEach((k, v) {
        if (!merged.containsKey(k)) merged[k] = v;
      });
    }

    return merged;
  }

  /// Read the internalConfig section (vendor-specified internal config)
  Map<String, dynamic> getInternalConfig() {
    var vendor = _getVendorConfig();
    final internal = vendor['internalConfig'];
    if (internal is Map<String, dynamic>) {
      return Map<String, dynamic>.from(internal);
    }
    return {};
  }

  /// Convenience for string-backed internalConfig values.
  String getInternalConfigString(String key, {String defaultValue = ''}) {
    final internal = getInternalConfig();
    return internal[key]?.toString() ?? defaultValue;
  }

  /// Return a human-friendly display name for a feature flag.
  ///
  /// Resolution order:
  /// 1. userFeatureNames in `orion.cfg` (allows local user renames)
  /// 2. top-level featureNames in `orion.cfg` (populated by remote vendor
  ///    overrides when appropriate)
  /// 3. vendor-provided featureNames (from `vendor.cfg`)
  /// 4. the provided [defaultName]
  String getFeatureDisplayName(String key, {String defaultName = ''}) {
    try {
      final cfg = _getConfig();
      final userNames = cfg['userFeatureNames'];
      if (userNames is Map &&
          userNames[key] is String &&
          (userNames[key] as String).isNotEmpty) {
        return userNames[key] as String;
      }

      final topNames = cfg['featureNames'];
      if (topNames is Map &&
          topNames[key] is String &&
          (topNames[key] as String).isNotEmpty) {
        return topNames[key] as String;
      }
    } catch (_) {}

    final vendor = _getVendorBaseConfig();
    final vnames = vendor['featureNames'] ?? vendor['vendor']?['featureNames'];
    if (vnames is Map &&
        vnames[key] is String &&
        (vnames[key] as String).isNotEmpty) {
      return vnames[key] as String;
    }

    return defaultName;
  }

  /// Return the configured backend id from `advanced.backend`.
  ///
  /// This keeps config access backend-agnostic; callers should avoid
  /// backend-name-specific checks and instead use backend capabilities.
  String getConfiguredBackendId({String fallback = 'odyssey'}) {
    try {
      final backend = getString('backend', category: 'advanced').trim();
      if (backend.isEmpty) return fallback;
      return backend.toLowerCase();
    } catch (_) {
      return fallback;
    }
  }

  Map<String, dynamic> _getConfig() {
    var fullPath = path.join(_configPath, 'orion.cfg');
    var configFile = File(fullPath);
    var vendorConfig = _getVendorConfig();

    // Get vendor machine name if available
    var defaultMachineName =
        vendorConfig['vendor']?['vendorMachineName'] ?? '3D Printer';

    var defaultConfig = {
      'general': {
        'themeMode': 'dark',
      },
      'advanced': {},
      'machine': {
        'machineName': defaultMachineName,
        'firstRun': true,
      },
    };

    if (!configFile.existsSync() || configFile.readAsStringSync().isEmpty) {
      // When creating the initial orion.cfg, write a merged view that
      // includes vendor-provided defaults so runtime immediately sees
      // backend, featureFlags and hardwareFeatures without waiting for
      // a later write from onboarding. Vendor preferences should override
      // the app defaults for initial setup.
      var mergedInit = _mergeConfigs(defaultConfig, vendorConfig);

      try {
        final vendorBlock = vendorConfig['vendor'];
        if (vendorBlock is Map<String, dynamic>) {
          final vThemeMode = vendorBlock['themeMode'];
          if (vThemeMode is String && vThemeMode.isNotEmpty) {
            mergedInit['general'] ??= {};
            mergedInit['general']['themeMode'] = vThemeMode;
          }

          final vSeed = vendorBlock['vendorThemeSeed'];
          if (vSeed is String && vSeed.isNotEmpty) {
            mergedInit['general'] ??= {};
            mergedInit['general']['colorSeed'] = 'vendor';
          }
        }
      } catch (e) {
        _logger.fine('Failed to apply vendor initial theme defaults: $e');
      }

      _writeConfig(mergedInit);
      // Return the merged view for reading
      return mergedInit;
    }

    var userConfig =
        Map<String, dynamic>.from(json.decode(configFile.readAsStringSync()));

    // Build merged view for reading
    var merged =
        _mergeConfigs(_mergeConfigs(defaultConfig, vendorConfig), userConfig);

    // If the user did not explicitly set theme/color preferences but the
    // vendor provides them (for example 'glass' and a vendorThemeSeed),
    // prefer the vendor values in the runtime merged view so the UI
    // reflects the packaged vendor theme. Do not persist this change to
    // disk here; it's only a runtime preference override unless the user
    // writes settings.
    try {
      final vendorBlock = vendorConfig['vendor'];
      if (vendorBlock is Map<String, dynamic>) {
        final vThemeMode = vendorBlock['themeMode'];
        final vSeed = vendorBlock['vendorThemeSeed'];

        final userHasTheme = userConfig['general'] is Map &&
            userConfig['general'].containsKey('themeMode') &&
            (userConfig['general']['themeMode'] as String).isNotEmpty;

        final userHasSeed = userConfig['general'] is Map &&
            userConfig['general'].containsKey('colorSeed') &&
            (userConfig['general']['colorSeed'] as String).isNotEmpty;

        // Apply themeMode only when the user hasn't set one and vendor
        // provides a non-empty value. We also guard to only override the
        // default 'dark' so we don't accidentally clobber intentional
        // merged values.
        if (!userHasTheme && vThemeMode is String && vThemeMode.isNotEmpty) {
          if ((merged['general']?['themeMode'] as String?) == 'dark') {
            merged['general'] ??= {};
            merged['general']['themeMode'] = vThemeMode;
          }
        }

        // If user hasn't selected a colorSeed but vendor provided a
        // vendorThemeSeed, set the runtime colorSeed to the special value
        // 'vendor' so ThemeProvider will pick up the vendor color.
        if (!userHasSeed && vSeed is String && vSeed.isNotEmpty) {
          final currentSeed = merged['general']?['colorSeed'] as String?;
          if (currentSeed == null || currentSeed.isEmpty) {
            merged['general'] ??= {};
            merged['general']['colorSeed'] = 'vendor';
          }
        }
      }
    } catch (e) {
      _logger.fine('Failed to apply vendor theme/color to merged view: $e');
    }

    return merged;
  }

  void _writeConfig(Map<String, dynamic> config) {
    // Remove any vendor section before writing to orion.cfg
    var configToWrite = Map<String, dynamic>.from(config);
    // If vendor provides internalConfig.backend or internalConfig.defaultLanguage,
    // copy them into the 'advanced' section so they persist in orion.cfg.
    final vendor = _getVendorConfig();
    final internal = vendor['internalConfig'];
    if (internal is Map<String, dynamic>) {
      configToWrite['advanced'] ??= {};
      if (internal.containsKey('backend') &&
          (configToWrite['advanced']['backend'] == null ||
              configToWrite['advanced']['backend'] == '')) {
        configToWrite['advanced']['backend'] = internal['backend'];
      }
      if (internal.containsKey('defaultLanguage') &&
          (configToWrite['advanced']['defaultLanguage'] == null ||
              configToWrite['advanced']['defaultLanguage'] == '')) {
        configToWrite['advanced']['defaultLanguage'] =
            internal['defaultLanguage'];
      }
    }
    // Allow vendor to preconfigure a theme mode or use the vendor color seed
    // as the default. If vendor provides 'vendor.themeMode' or
    // 'vendor.vendorThemeSeed' prefer those values when orion.cfg has no
    // explicit setting.
    try {
      final vendorBlock = vendor['vendor'];
      if (vendorBlock is Map<String, dynamic>) {
        // Vendor-provided theme mode (e.g. 'glass')
        final vThemeMode = vendorBlock['themeMode'];
        if (vThemeMode is String) {
          configToWrite['general'] ??= {};
          if (configToWrite['general']['themeMode'] == null ||
              (configToWrite['general']['themeMode'] as String).isEmpty) {
            configToWrite['general']['themeMode'] = vThemeMode;
          }
        }

        // If vendor has a theme seed, default to using the vendor seed
        // by setting colorSeed to the special value 'vendor' unless the
        // user has already chosen a seed.
        final vSeed = vendorBlock['vendorThemeSeed'];
        if (vSeed is String && vSeed.isNotEmpty) {
          configToWrite['general'] ??= {};
          if (configToWrite['general']['colorSeed'] == null ||
              (configToWrite['general']['colorSeed'] as String).isEmpty) {
            configToWrite['general']['colorSeed'] = 'vendor';
          }
        }
      }
    } catch (e) {
      _logger.fine('Failed to copy vendor theme defaults: $e');
    }

    configToWrite.remove('vendor');

    var fullPath = path.join(_configPath, 'orion.cfg');
    var configFile = File(fullPath);
    final isNewConfigFile = !configFile.existsSync();

    // If we're creating the initial orion.cfg (file didn't exist), allow
    // vendor themeMode to be applied even when a default is present. This
    // ensures packaged vendor preferences (like 'glass') are respected on
    // first-run instead of being masked by the hard-coded app default.
    if (isNewConfigFile) {
      try {
        final vendorBlock = vendor['vendor'];
        if (vendorBlock is Map<String, dynamic>) {
          final vThemeMode = vendorBlock['themeMode'];
          if (vThemeMode is String && vThemeMode.isNotEmpty) {
            configToWrite['general'] ??= {};
            configToWrite['general']['themeMode'] = vThemeMode;
          }
        }
      } catch (e) {
        _logger
            .fine('Failed to copy vendor theme defaults on initial write: $e');
      }
    }

    var encoder = const JsonEncoder.withIndent('  ');
    configFile.writeAsStringSync(encoder.convert(configToWrite));
    // Notify any registered listeners that the on-disk config has changed.
    for (final cb in _changeListeners) {
      try {
        cb();
      } catch (e) {
        _logger.warning('Config change listener threw: $e');
      }
    }
  }

  void blowUp(BuildContext context, String imagePath) {
    _logger.severe('Blowing up the app');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return FutureBuilder(
          future: Future.delayed(const Duration(seconds: 4)),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SafeArea(
                child: Dialog(
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  insetPadding: EdgeInsets.zero,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: const Center(
                    child: SizedBox(
                      height: 75,
                      width: 75,
                      child: CircularProgressIndicator(
                        strokeWidth: 6,
                      ),
                    ),
                  ),
                ),
              );
            } else {
              Future.delayed(const Duration(seconds: 10), () {
                Navigator.of(context).pop(true);
              });
              return SafeArea(
                child: Dialog(
                  insetPadding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.fill,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  Map<String, dynamic> _mergeConfigs(
      Map<String, dynamic> base, Map<String, dynamic> overlay) {
    var result = Map<String, dynamic>.from(base);

    overlay.forEach((key, value) {
      if (value is Map) {
        result[key] = result.containsKey(key)
            ? _mergeConfigs(Map<String, dynamic>.from(result[key] ?? {}),
                Map<String, dynamic>.from(value))
            : Map<String, dynamic>.from(value);
      } else {
        result[key] = value;
      }
    });

    return result;
  }
}
