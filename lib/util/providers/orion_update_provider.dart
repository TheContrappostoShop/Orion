/*
* Orion - Orion Update Provider
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

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:orion/settings/update_progress.dart';
import 'package:orion/tools/athena/leveling_log_service.dart';
import 'package:orion/tools/athena/screw_calibration_store.dart';
import 'package:orion/util/install_locator.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/pubspec.dart';

/// Provider that encapsulates the Orion update flow.
///
/// Exposes [progress] and [message] ValueNotifiers that the UI can listen to
/// and a single [performUpdate] method to run the update flow. The provider
/// will show a modal update overlay while an update is in progress.

class OrionUpdateProvider extends ChangeNotifier {
  final Logger _logger = Logger('OrionUpdateProvider');
  final OrionConfig _config = OrionConfig();

  /// Files Orion keeps next to `orion.cfg` that hold user/machine state.
  ///
  /// The update script replaces the whole install directory — which is also
  /// the config directory on most installs — so every one of these has to be
  /// copied back from the backup. Anything missing here is destroyed by an
  /// update (a lost leveling log reads back as "printer not leveled").
  static const List<String> persistedStateFiles = <String>[
    'orion.cfg',
    LevelingLogService.fileName,
    ScrewCalibrationStore.fileName,
  ];

  final ValueNotifier<double> progress = ValueNotifier<double>(0.0);
  final ValueNotifier<String> message = ValueNotifier<String>('');
  bool _isDialogOpen = false;

  // Update check state
  bool isChecking = false;
  bool isUpdateAvailable = false;
  bool rateLimitExceeded = false;
  bool preRelease = false;
  bool betaUpdatesOverride = false;
  String latestVersion = '';
  String currentVersion = '';
  String releaseNotes = '';
  String releaseDate = '';
  String commitDate = '';
  String assetUrl = '';
  String releaseChannel = 'main';

  bool get isLoading => isChecking;
  String get release => releaseChannel;

  OrionUpdateProvider() {
    _loadPersistedState();
  }

  void _loadPersistedState() {
    if (_config.getFlag('available', category: 'updates')) {
      final current = _config.getString('orion.current', category: 'updates');
      final latest = _config.getString('orion.latest', category: 'updates');
      final rel = _config.getString('orion.release', category: 'updates');

      if (current.isNotEmpty && latest.isNotEmpty) {
        // Check if we've already updated since the last check
        final actualCurrent = Pubspec.versionFull;
        if (_isNewerVersion(latest, actualCurrent)) {
          currentVersion = actualCurrent;
          latestVersion = latest;
          releaseChannel = rel.isNotEmpty ? rel : 'BRANCH_dev';
          isUpdateAvailable = true;
          notifyListeners();
        }
      }
    }
  }

  Future<void> checkForUpdates() async {
    isChecking = true;
    notifyListeners();

    try {
      currentVersion = Pubspec.versionFull;
      _logger.info('Current version: $currentVersion');

      final isFirmwareSpoofingEnabled =
          _config.getFlag('overrideUpdateCheck', category: 'developer');
      betaUpdatesOverride =
          _config.getFlag('releaseOverride', category: 'developer');
      releaseChannel =
          _config.getString('overrideRelease', category: 'developer');
      final repoOverride =
          _config.getString('overrideRepo', category: 'developer');
      final repo = repoOverride.trim().isNotEmpty
          ? repoOverride.trim()
          : 'Open-Resin-Alliance';

      if (isFirmwareSpoofingEnabled) {
        if (releaseChannel.isNotEmpty && releaseChannel != 'BRANCH_dev') {
          await _checkForBERUpdates(repo, releaseChannel, force: true);
        } else {
          // Default latest release check with force
          await _checkGitHubLatest(repo, force: true);
        }
      } else if (betaUpdatesOverride) {
        await _checkForBERUpdates(repo, releaseChannel);
      } else {
        await _checkGitHubLatest(repo);
      }
    } catch (e) {
      _logger.warning('Update check failed: $e');
      // Do not clear isUpdateAvailable on error; preserve persisted state
    } finally {
      isChecking = false;
      notifyListeners();
    }
  }

  Future<void> _checkGitHubLatest(String repo, {bool force = false}) async {
    final String url =
        'https://api.github.com/repos/$repo/orion/releases/latest';
    int retryCount = 0;
    const int maxRetries = 3;
    const int initialDelay = 750;

    while (retryCount < maxRetries) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body);
          final String tag = jsonResponse['tag_name'].replaceAll('v', '');

          if (force || _isNewerVersion(tag, currentVersion)) {
            final asset = jsonResponse['assets'].firstWhere(
                (asset) => asset['name'] == 'orion_armv7.tar.gz',
                orElse: () => null);

            latestVersion = tag;
            releaseNotes = jsonResponse['body'];
            releaseDate = jsonResponse['published_at'];
            assetUrl = asset != null ? asset['browser_download_url'] : '';
            isUpdateAvailable = true;
            rateLimitExceeded = false;
          } else {
            isUpdateAvailable = false;
          }
          return;
        } else if (response.statusCode == 403 &&
            response.headers['x-ratelimit-remaining'] == '0') {
          _logger.warning('Rate limit exceeded, retrying...');
          rateLimitExceeded = true;
          notifyListeners();
          await Future.delayed(Duration(
              milliseconds: initialDelay * pow(2, retryCount).toInt()));
          retryCount++;
        } else {
          _logger.warning('Failed to fetch updates: ${response.statusCode}');
          return;
        }
      } catch (e) {
        _logger.warning(e.toString());
        return;
      }
    }
  }

  Future<void> _checkForBERUpdates(String repo, String release,
      {bool force = false}) async {
    if (release.isEmpty) release = 'BRANCH_dev';
    String url = 'https://api.github.com/repos/$repo/orion/releases';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body) as List;
        final releaseItem = jsonResponse.firstWhere(
            (item) => item['tag_name'] == release,
            orElse: () => null);

        if (releaseItem != null) {
          final String commitSha = releaseItem['target_commitish'];
          final commitUrl =
              'https://api.github.com/repos/$repo/orion/commits/$commitSha';
          final commitResponse = await http.get(Uri.parse(commitUrl));

          if (commitResponse.statusCode == 200) {
            final commitJson = json.decode(commitResponse.body);
            final String shortSha = commitJson['sha'].substring(0, 7);
            final String msg = commitJson['commit']['message'];
            final String date = commitJson['commit']['committer']['date'];

            if (!force && _isCurrentCommitUpToDate(shortSha)) {
              isUpdateAvailable = false;
              return;
            }

            // Try to fetch pubspec.yaml to get the actual version
            String version = '';
            try {
              final pubspecUrl =
                  'https://raw.githubusercontent.com/$repo/orion/$commitSha/pubspec.yaml';
              final pubspecResp = await http.get(Uri.parse(pubspecUrl));
              if (pubspecResp.statusCode == 200) {
                final content = pubspecResp.body;
                final match =
                    RegExp(r'version:\s*([^\s]+)').firstMatch(content);
                if (match != null) {
                  version = match.group(1) ?? '';
                  // Remove any existing build metadata from the fetched version
                  // so we can append the commit SHA cleanly
                  if (version.contains('+')) {
                    version = version.split('+')[0];
                  }
                }
              }
            } catch (e) {
              _logger.warning('Failed to fetch pubspec version: $e');
            }

            final asset = releaseItem['assets'].firstWhere(
                (asset) => asset['name'] == 'orion_armv7.tar.gz',
                orElse: () => null);

            latestVersion = version.isNotEmpty
                ? '$version+$shortSha'
                : '$shortSha ($release)';
            releaseNotes =
                releaseItem['prerelease'] ? msg : releaseItem['body'];
            commitDate = date;
            assetUrl = asset != null ? asset['browser_download_url'] : '';
            preRelease = releaseItem['prerelease'];
            isUpdateAvailable = true;
            rateLimitExceeded = false;
          }
        }
      }
    } catch (e) {
      _logger.warning('BER update check failed: $e');
    }
  }

  bool _isCurrentCommitUpToDate(String commitSha) {
    final parts = currentVersion.split('+');
    final currentCommit = parts.length > 1 ? parts[1] : '';
    return commitSha == currentCommit;
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      // Split the version and build numbers
      List<String> latestVersionParts = latest.split('+')[0].split('.');
      List<String> currentVersionParts = current.split('+')[0].split('.');

      // Convert version parts to integers for comparison
      // Use max length to handle strict semver (1.2 < 1.2.1)
      int len = max(latestVersionParts.length, currentVersionParts.length);

      for (int i = 0; i < len; i++) {
        int l = 0;
        int c = 0;
        if (i < latestVersionParts.length) {
          l = int.tryParse(latestVersionParts[i]) ?? 0;
        }
        if (i < currentVersionParts.length) {
          c = int.tryParse(currentVersionParts[i]) ?? 0;
        }

        if (l > c) {
          return true;
        } else if (l < c) {
          return false;
        }
      }

      if (latest.contains('+') && current.contains('+')) {
        String latestBuild = latest.split('+')[1];
        String currentBuild = current.split('+')[1];
        try {
          int latestBuildNumber = int.parse(latestBuild);
          int currentBuildNumber = int.parse(currentBuild);
          return latestBuildNumber > currentBuildNumber;
        } catch (e) {
          return latestBuild.compareTo(currentBuild) > 0;
        }
      }
    } catch (e) {
      _logger.warning('Error comparing versions: $e');
    }

    return false;
  }

  void _openUpdateDialog(NavigatorState navigator, String initialMessage) {
    message.value = initialMessage;
    if (_isDialogOpen) return;
    _isDialogOpen = true;
    progress.value = 0.0;

    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return UpdateProgressOverlay(
          progress: progress,
          message: message,
          icon: PhosphorIcons.warningDiamond(),
        );
      },
    ).then((_) {
      _isDialogOpen = false;
      progress.value = 0.0;
      message.value = '';
    });
  }

  /// Locate the Orion installation root. Public for testing.
  String findOrionRoot() {
    final String localUser = Platform.environment['USER'] ?? 'pi';
    final String envRoot = Platform.environment['ORION_ROOT'] ?? '';
    if (envRoot.isNotEmpty) {
      _logger.info('ORION_ROOT environment variable set -> $envRoot');
      return envRoot;
    }

    // Attempt to locate the engine/install directory first. Prefer configs
    // adjacent to the detected engine dir (engineDir/orion.cfg,
    // parent/orion.cfg, or /opt/orion.cfg). Doing this before walking the
    // current working directory ancestors avoids false positives when the
    // process CWD is `/` or other non-install roots.
    try {
      final engineDir = findEngineDir();
      if (engineDir != null && engineDir.isNotEmpty) {
        final engineConfig = '$engineDir/orion.cfg';
        final engineVendor = '$engineDir/vendor.cfg';
        final parentDir = Directory(engineDir).parent.path;
        final parentConfig = '$parentDir/orion.cfg';
        final parentVendor = '$parentDir/vendor.cfg';
        final optConfig = '/opt/orion.cfg';
        final optVendor = '/opt/vendor.cfg';

        if (File(engineConfig).existsSync() ||
            File(engineVendor).existsSync()) {
          _logger.info('Found config inside engine dir -> $engineDir');
          return engineDir;
        }
        if (File(parentConfig).existsSync() ||
            File(parentVendor).existsSync()) {
          _logger.info('Found config adjacent to engine dir -> $parentDir');
          return parentDir;
        }
        if (File(optConfig).existsSync() || File(optVendor).existsSync()) {
          _logger.info('Found /opt config file; using /opt');
          return '/opt';
        }

        // If no config was found adjacent to the engine dir, don't return
        // immediately — continue with other heuristics but prefer engineDir
        // later by adding it to well-known candidate checks (handled below).
        _logger.fine(
            'Engine dir probe found $engineDir; no adjacent config, will continue heuristics');
      }
    } catch (_) {}

    // Check current working directory and its ancestors (pwd)
    try {
      Directory dir = Directory.current;
      while (true) {
        final candidate = dir.path;
        final hasCfg = File('$candidate/orion.cfg').existsSync();
        final hasOrionDir = Directory('$candidate/orion').existsSync();
        final endsWithOrion = candidate.endsWith('/orion');
        if (hasCfg || hasOrionDir || endsWithOrion) {
          final reason = hasCfg
              ? 'orion.cfg present'
              : hasOrionDir
                  ? 'orion subdirectory present'
                  : 'path ends with /orion';
          _logger.fine(
              'Found orion root candidate in CWD ancestors: $candidate ($reason)');
          return candidate;
        }
        if (dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    } catch (_) {}

    // Check ancestors of the running executable (helps packaged installs)
    try {
      final exe = Platform.resolvedExecutable;
      final exeDir = Directory(exe).parent;
      Directory dir = exeDir;
      while (true) {
        final candidate = dir.path;
        if (File('$candidate/orion.cfg').existsSync() ||
            Directory('$candidate/orion').existsSync() ||
            candidate.endsWith('/orion')) {
          _logger.fine(
              'Found orion root candidate in executable ancestors: $candidate');
          return candidate;
        }
        if (dir.parent.path == dir.path) break; // reached root
        dir = dir.parent;
      }
    } catch (_) {
      // ignore
    }

    // (engine dir probe handled earlier)

    // Check a few common locations without preferring any single one
    final candidates = [
      '/usr/local/share/orion',
      '/usr/share/orion',
      '/var/lib/orion',
      '/opt/orion',
      '${Platform.environment['HOME'] ?? '/home/$localUser'}/orion'
    ];
    for (final c in candidates) {
      try {
        if (Directory(c).existsSync() || File('$c/orion.cfg').existsSync()) {
          _logger.fine(
              'Found orion install candidate in well-known locations: $c');
          return c;
        }
      } catch (_) {}
    }

    // Last resort: user's home
    final fallback =
        '${Platform.environment['HOME'] ?? '/home/$localUser'}/orion';
    _logger.fine('No install root discovered; falling back to $fallback');
    return fallback;
  }

  void _dismissUpdateDialog(NavigatorState navigator) {
    if (_isDialogOpen && navigator.canPop()) {
      navigator.pop();
      _isDialogOpen = false;
      progress.value = 0.0;
      message.value = '';
    }
  }

  void _updateProgressAndText(String msg, {double step = 0.25}) {
    message.value = msg;
    if (_isDialogOpen) {
      progress.value = min(1.0, progress.value + step);
    }
  }

  Future<void> performUpdate(BuildContext context, String assetUrl) async {
    // Capture the navigator eagerly so all async gaps below can safely
    // show/dismiss the update progress dialog without a stale context.
    final NavigatorState nav = Navigator.of(context);

    // Safety: if Force Update override is enabled, disable it as soon as
    // the Orion update sequence is initiated so we don't force-prompt again
    // on every boot after this run.
    if (_config.getFlag('overrideUpdateCheck', category: 'developer')) {
      _config.setFlag('overrideUpdateCheck', false, category: 'developer');
    }

    final String localUser = Platform.environment['USER'] ?? 'pi';

    final String orionRoot = findOrionRoot();
    _logger.info('Detected Orion root: $orionRoot');

    // Use a temp upgrade workspace to download & extract; this avoids
    // writing into system install directories directly and is safer when
    // the install root is read-only.
    final tempDir = await Directory.systemTemp.createTemp('orion_upgrade_');
    final String upgradeFolder = '${tempDir.path}/';
    final String downloadPath = '$upgradeFolder/orion_armv7.tar.gz';
    final String orionFolder =
        orionRoot.endsWith('/') ? orionRoot : '$orionRoot/';
    final String newOrionFolder = '${upgradeFolder}orion_new/';
    final String backupFolder = '${upgradeFolder}orion_backup/';
    final String scriptPath = '$upgradeFolder/update_orion.sh';

    _logger.info('Upgrade temporary workspace: $upgradeFolder');
    _logger.info('Download target path: $downloadPath');
    _logger.fine('New Orion staging folder: $newOrionFolder');
    _logger.fine('Backup folder: $backupFolder');
    _logger.fine('Update script path: $scriptPath');

    if (assetUrl.isEmpty) {
      _logger.warning('Asset URL is empty');
      return;
    }

    _logger.info('Downloading from $assetUrl');

    // macOS dev simulation
    if (Platform.isMacOS) {
      _openUpdateDialog(nav, 'Starting update...');
      final simSteps = [
        'Downloading update file...',
        'Extracting update file...',
        'Executing update script...',
        'Finalizing update...'
      ];

      final int remaining = simSteps.length - 1;
      final double perStep = remaining > 0 ? (1.0 / remaining) : 1.0;

      for (var i = 0; i < simSteps.length; i++) {
        final m = simSteps[i];
        final step = i == 0 ? 0.0 : perStep;
        _updateProgressAndText(m, step: step);
        await Future.delayed(const Duration(seconds: 3));
      }

      progress.value = 1.0;
      await Future.delayed(const Duration(seconds: 1));
      _dismissUpdateDialog(nav);
      return;
    }

    // Normal flow: open dialog and perform streamed download, extract and run
    _openUpdateDialog(nav, 'Starting update...');

    try {
      final upgradeDir = Directory(upgradeFolder);
      if (await upgradeDir.exists()) {
        try {
          await upgradeDir.delete(recursive: true);
        } catch (e) {
          _logger.warning('Could not purge upgrade directory');
        }
      }
      await upgradeDir.create(recursive: true);

      final newDir = Directory(newOrionFolder);
      if (await newDir.exists()) {
        try {
          await newDir.delete(recursive: true);
        } catch (e) {
          _logger.warning('Could not purge new Orion directory');
        }
      }
      await newDir.create(recursive: true);

      _updateProgressAndText('Downloading update file...', step: 0.0);
      await Future.delayed(const Duration(seconds: 1));

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(assetUrl));
        final streamedResp = await client.send(req);
        if (streamedResp.statusCode == 200) {
          final int contentLength = streamedResp.contentLength ?? -1;
          final file = File(downloadPath);
          final sink = file.openWrite();
          int bytesReceived = 0;

          if (contentLength > 0) {
            message.value = 'Downloading update file...';
            progress.value = 0.0;
            await for (final chunk in streamedResp.stream) {
              sink.add(chunk);
              bytesReceived += chunk.length;
              final double raw = bytesReceived / contentLength;
              progress.value = min(1.0, raw * 0.25);
            }
          } else {
            message.value = 'Downloading update file...';
            await for (final chunk in streamedResp.stream) {
              sink.add(chunk);
            }
          }

          await sink.flush();
          await sink.close();

          progress.value = max(progress.value, 0.25);

          _updateProgressAndText('Extracting update file...', step: 0.25);
          await Future.delayed(const Duration(seconds: 1));
        } else {
          _logger.warning(
              'Failed to download update file, status: ${streamedResp.statusCode}');
        }
      } finally {
        client.close();
      }

      final extractResult = await Process.run('sudo',
          ['tar', '--overwrite', '-xzf', downloadPath, '-C', newOrionFolder]);
      if (extractResult.exitCode != 0) {
        _logger
            .warning('Failed to extract update file: ${extractResult.stderr}');
        _dismissUpdateDialog(nav);
        return;
      }

      // Normalize the target install directory to ensure we operate on an
      // `orion` subfolder rather than a user's home directory.
      String installDir;
      if (orionFolder.endsWith('/orion') || orionFolder.endsWith('/orion/')) {
        installDir = orionFolder.endsWith('/') ? orionFolder : '$orionFolder/';
      } else {
        installDir = '${orionFolder}orion/';
      }
      // Ensure trailing slash
      if (!installDir.endsWith('/')) installDir = '$installDir/';

      // Safety checks: never operate directly on the user's home, root, or
      // other obvious dangerous targets.
      final dangerous = [
        '/',
        '/home',
        '/home/',
        '/home/$localUser',
        '/home/$localUser/',
        '/root',
        '/root/'
      ];
      if (dangerous.contains(installDir) || installDir.trim().isEmpty) {
        _logger.severe(
            'Refusing to run update: computed installDir looks unsafe: $installDir');
        _dismissUpdateDialog(nav);
        return;
      }

      // Verify the install directory actually exists and looks like an Orion
      // install (contains orion.cfg or a directory structure). If it doesn't,
      // abort to avoid operating at a higher level.
      try {
        final checkDir = Directory(installDir);
        final hasCfg = File('${installDir}orion.cfg').existsSync();
        final hasDir = checkDir.existsSync();
        if (!hasCfg && !hasDir) {
          _logger.severe(
              'Refusing to run update: installDir does not look like an Orion install: $installDir');
          _dismissUpdateDialog(nav);
          return;
        }
      } catch (e) {
        _logger.severe('Error while verifying installDir: $e');
        _dismissUpdateDialog(nav);
        return;
      }

      // Use the safe installDir in the script so we never rm -R the user's
      // home directory by accident.
      final scriptContent = '''#!/bin/bash

# Variables
local_user=$localUser
orion_folder=$installDir
new_orion_folder=$newOrionFolder
upgrade_folder=$upgradeFolder
backup_folder=$backupFolder

# If previous backup exists, delete it
if [ -d \$backup_folder ]; then
  sudo rm -R \$backup_folder
fi

# Backup the current Orion directory (safe-targeted)
if [ -d "\$orion_folder" ]; then
  sudo cp -R "\$orion_folder" "\$backup_folder"
else
  # Fallback: try to copy orion subdir
  if [ -d "${installDir}orion" ]; then
    sudo cp -R "${installDir}orion" "\$backup_folder"
    orion_folder="${installDir}orion"
  fi
fi

# Remove the old Orion directory (targeted)
if [ -d "\$orion_folder" ]; then
  sudo rm -R "\$orion_folder"
fi

# Restore persistent state files (orion.cfg plus the leveling state that
# lives beside it).  They were in the directory that was just replaced, so
# only the backup copy exists now.
if [ -d "\$new_orion_folder" ]; then
  for state_file in ${persistedStateFiles.join(' ')}; do
    if [ -f "\$backup_folder/\$state_file" ]; then
      sudo cp "\$backup_folder/\$state_file" "\$new_orion_folder"
    fi
  done
fi

# Move the new Orion directory to the original location
if [ -d "\$new_orion_folder" ]; then
  sudo mv "\$new_orion_folder" "\$orion_folder"
fi

# Delete the upgrade and new folder
if [ -d "\$upgrade_folder" ]; then
  sudo rm -R "\$upgrade_folder"
fi

# Fix permissions
if [ -d "\$orion_folder" ]; then
  sudo chown -R "\$local_user":"\$local_user" "\$orion_folder"
fi

# Restart the Orion service if available
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart orion.service || true
  # Try nanodlp-dsi as an alternative
  sudo systemctl restart nanodlp-dsi.service || true
fi
''';

      final scriptFile = File(scriptPath);
      await scriptFile.writeAsString(scriptContent);
      await Process.run('chmod', ['+x', scriptPath]);

      _updateProgressAndText('Executing update script...', step: 0.25);

      // Mark complete after executing script
      progress.value = 1.0;
      await Future.delayed(const Duration(seconds: 2));

      final result = await Process.run('nohup', ['sudo', scriptPath]);
      if (result.exitCode == 0) {
        _logger.info('Update script executed successfully');
      } else {
        _logger.warning('Failed to execute update script: ${result.stderr}');
      }
    } catch (e) {
      _logger.warning('Update failed: $e');
    } finally {
      _dismissUpdateDialog(nav);
    }
  }
}
