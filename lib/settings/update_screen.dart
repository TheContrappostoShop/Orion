/*
* Orion - Update Screen
* Copyright (C) 2024 TheContrappostoShop
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:orion/pubspec.dart';
import 'package:orion/util/markdown_screen.dart';
import 'package:orion/util/orion_config.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  UpdateScreenState createState() => UpdateScreenState();
}

class UpdateScreenState extends State<UpdateScreen> {
  bool _isLoading = true;
  bool _isUpdateAvailable = false;
  bool _isFirmwareSpoofingEnabled = false;
  bool _betaUpdatesOverride = false;
  bool _rateLimitExceeded = false;

  String _latestVersion = '';
  String _commitDate = '';
  String _releaseNotes = '';
  String _currentVersion = '';
  String _branch = 'dev';
  String _assetUrl = '';

  final Logger _logger = Logger('UpdateScreen');
  final OrionConfig _config = OrionConfig();

  @override
  void initState() {
    super.initState();
    _initUpdateCheck();
    _isFirmwareSpoofingEnabled =
        _config.getFlag('overrideUpdateCheck', category: 'developer');
    _betaUpdatesOverride =
        _config.getFlag('betaOverride', category: 'developer');
    _branch = _config.getString('overrideBranch', category: 'developer');
    _logger.info('Firmware spoofing enabled: $_isFirmwareSpoofingEnabled');
    _logger.info('Beta updates override enabled: $_betaUpdatesOverride');
    _logger.info('Branch override: $_branch');
  }

  Future<void> _initUpdateCheck() async {
    await _getCurrentAppVersion();
    await _checkForUpdates(_branch);
  }

  Future<void> _getCurrentAppVersion() async {
    try {
      setState(() {
        _currentVersion = Pubspec.versionFull;
        _logger.info('Current version: $_currentVersion');
      });
    } catch (e) {
      setState(() {
        _logger.warning('Failed to get current app version');
      });
    }
  }

  Future<void> _checkForUpdates(String branch) async {
    if (_betaUpdatesOverride) {
      await _checkForBERUpdates(branch);
    } else {
      const String url =
          'https://api.github.com/repos/thecontrappostoshop/orion/releases/latest';
      int retryCount = 0;
      const int maxRetries = 3;
      const int initialDelay = 750;
      while (retryCount < maxRetries) {
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            final jsonResponse = json.decode(response.body);
            final String latestVersion = jsonResponse['tag_name']
                .replaceAll('v', ''); // Remove 'v' prefix if present
            final String releaseNotes = jsonResponse['body'];
            _logger.info('Latest version: $latestVersion');
            if (_isNewerVersion(latestVersion, _currentVersion)) {
              // Find the asset URL for orion_aarch64.tar.gz
              final asset = jsonResponse['assets'].firstWhere(
                  (asset) => asset['name'] == 'orion_aarch64.tar.gz',
                  orElse: () => null);
              final String assetUrl =
                  asset != null ? asset['browser_download_url'] : '';
              setState(() {
                _latestVersion = latestVersion;
                _releaseNotes = releaseNotes;
                _isLoading = false;
                _isUpdateAvailable = true;
                _assetUrl = assetUrl; // Set the asset URL
              });
            } else {
              setState(() {
                _isLoading = false;
                _isUpdateAvailable = false;
              });
            }
            return; // Exit the function after successful fetch
          } else if (response.statusCode == 403 &&
              response.headers['x-ratelimit-remaining'] == '0') {
            _logger.warning('Rate limit exceeded, retrying...');
            setState(() {
              _rateLimitExceeded = true;
            });
            await Future.delayed(Duration(
                milliseconds: initialDelay * pow(2, retryCount).toInt()));
            retryCount++;
          } else {
            setState(() {
              _logger.warning('Failed to fetch updates');
              _isLoading = false;
            });
            return; // Exit the function after failure
          }
        } catch (e) {
          _logger.warning(e.toString());
          setState(() {
            _isLoading = false;
          });
          return; // Exit the function after failure
        }
      }
    }
  }

  Future<void> _checkForBERUpdates(String branch) async {
    if (branch.isEmpty) {
      _logger.warning('Branch name is empty');
      branch = 'dev';
    }
    String url =
        'https://api.github.com/repos/thecontrappostoshop/orion/releases';
    int retryCount = 0;
    const int maxRetries = 3;
    const int initialDelay = 750; // Initial delay in milliseconds
    while (retryCount < maxRetries) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body) as List;
          final preRelease = jsonResponse.firstWhere(
              (release) =>
                  release['prerelease'] == true &&
                  release['tag_name'].contains(branch),
              orElse: () => null);
          if (preRelease != null) {
            final String latestVersion = preRelease['tag_name'];
            final String commitSha = preRelease['target_commitish'];
            final commitUrl =
                'https://api.github.com/repos/thecontrappostoshop/orion/commits/$commitSha';
            final commitResponse = await http.get(Uri.parse(commitUrl));
            if (commitResponse.statusCode == 200) {
              final commitJson = json.decode(commitResponse.body);
              final String shortCommitSha =
                  commitJson['sha'].substring(0, 7); // Get short commit SHA
              final String commitMessage = commitJson['commit']['message'];
              final String commitDate = commitJson['commit']['committer']
                  ['date']; // Fetch commit date

              // Find the asset URL for orion_aarch64.tar.gz
              final asset = preRelease['assets'].firstWhere(
                  (asset) => asset['name'] == 'orion_aarch64.tar.gz',
                  orElse: () => null);
              final String assetUrl =
                  asset != null ? asset['browser_download_url'] : '';

              _logger.info('Latest pre-release version: $latestVersion');
              setState(() {
                _latestVersion =
                    '$shortCommitSha (BRANCH_$branch)'; // Append branch name
                _releaseNotes = commitMessage;
                _commitDate = commitDate; // Store commit date
                _isLoading = false;
                _isUpdateAvailable = true;
                _rateLimitExceeded = false;
                _assetUrl = assetUrl; // Set the asset URL
              });
              return; // Exit the function after successful fetch
            } else {
              _logger.warning(
                  'Failed to fetch commit details, status code: ${commitResponse.statusCode}');
              setState(() {
                _isLoading = false;
                _rateLimitExceeded = false;
              });
              return; // Exit the function after failure
            }
          } else {
            _logger.warning('No pre-release found for branch: $branch');
            setState(() {
              _isLoading = false;
              _rateLimitExceeded = false;
            });
            return; // Exit the function after no pre-release found
          }
        } else if (response.statusCode == 403 &&
            response.headers['x-ratelimit-remaining'] == '0') {
          _logger.warning('Rate limit exceeded, retrying...');
          setState(() {
            _rateLimitExceeded = true;
          });
          await Future.delayed(Duration(
              milliseconds: initialDelay * pow(2, retryCount).toInt()));
          retryCount++;
        } else {
          _logger.warning(
              'Failed to fetch updates, status code: ${response.statusCode}');
          setState(() {
            _isLoading = false;
            _rateLimitExceeded = false;
          });
          return; // Exit the function after failure
        }
      } catch (e) {
        _logger.warning(e.toString());
        setState(() {
          _isLoading = false;
          _rateLimitExceeded = false;
        });
        return; // Exit the function after failure
      }
    }
  }

  bool _isNewerVersion(String latestVersion, String currentVersion) {
    _logger.info('Firmware spoofing enabled: $_isFirmwareSpoofingEnabled');
    if (_isFirmwareSpoofingEnabled) return true;
    // Split the version and build numbers
    List<String> latestVersionParts = latestVersion.split('+')[0].split('.');
    List<String> currentVersionParts = currentVersion.split('+')[0].split('.');

    // Convert version parts to integers for comparison
    List<int> latestNumbers = latestVersionParts.map(int.parse).toList();
    List<int> currentNumbers = currentVersionParts.map(int.parse).toList();

    // Compare major, minor, and patch numbers
    for (int i = 0; i < min(latestNumbers.length, currentNumbers.length); i++) {
      if (latestNumbers[i] > currentNumbers[i]) {
        return true;
      } else if (latestNumbers[i] < currentNumbers[i]) {
        return false;
      }
    }

    // If versions are equal, compare build numbers if present
    if (latestVersion.contains('+') && currentVersion.contains('+')) {
      String latestBuild = latestVersion;
      String currentBuild = currentVersion.split('+')[1];
      // Attempt to compare build numbers as integers if possible
      try {
        int latestBuildNumber = int.parse(latestBuild);
        int currentBuildNumber = int.parse(currentBuild);
        return latestBuildNumber > currentBuildNumber;
      } catch (e) {
        // If build numbers are not integers, compare them as strings
        return latestBuild.compareTo(currentBuild) > 0;
      }
    }

    // Versions are equal and no build number to compare
    return false;
  }

  void _viewChangelog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MarkdownScreen(changelog: _releaseNotes),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(
            left: 16.0, right: 16.0, bottom: 16.0, top: 5.0),
        children: [
          Card.outlined(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_rateLimitExceeded) ...[
                    const Row(
                      children: [
                        Icon(Icons.error, color: Colors.red, size: 30),
                        SizedBox(width: 10),
                        Text('Rate Limit Exceeded!',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(),
                    const Text('Please try again later.',
                        style: TextStyle(fontSize: 20)),
                  ] else if (_isLoading) ...[
                    const Center(child: CircularProgressIndicator()),
                  ] else if (_isUpdateAvailable) ...[
                    Row(
                      children: [
                        _betaUpdatesOverride
                            ? PhosphorIcon(PhosphorIcons.knife())
                            : Icon(Icons.system_update,
                                color: Theme.of(context).colorScheme.primary,
                                size: 30),
                        const SizedBox(width: 10),
                        Text(
                            _betaUpdatesOverride
                                ? 'Bleeding Edge Available!'
                                : 'UI Update Available!',
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(),
                    Text(
                        _betaUpdatesOverride
                            ? 'Latest Commit: $_latestVersion'
                            : 'Latest Version: ${_latestVersion.split('+')[0]}',
                        style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 10),
                    Text(
                      _betaUpdatesOverride
                          ? 'Commit Date: ${_commitDate.split('T')[0]}' // Display commit date if beta updates are enabled
                          : 'Release Date: ${_getFormattedDate()}',
                      style: const TextStyle(fontSize: 20, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              elevation: 3,
                              minimumSize:
                                  const Size.fromHeight(65), // Set height to 65
                            ),
                            onPressed: _viewChangelog,
                            icon: const Icon(Icons.article),
                            label: const Text('View Changelog',
                                style: TextStyle(fontSize: 24)),
                          ),
                        ),
                        const SizedBox(
                            width: 10), // Add some space between the buttons
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              elevation: 3,
                              minimumSize:
                                  const Size.fromHeight(65), // Set height to 65
                            ),
                            onPressed: _performUpdate,
                            icon: const Icon(Icons.download),
                            label: const Text('Download Update',
                                style: TextStyle(fontSize: 24)),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 30),
                        SizedBox(width: 10),
                        Text('Orion is up to date!',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(),
                    Text('Current Version: ${_currentVersion.split('+')[0]}',
                        style: const TextStyle(fontSize: 20)),
                  ],
                ],
              ),
            ),
          ),
          // Placeholder for Odyssey updater - pending API changes
          const Card.outlined(
            elevation: 1,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Odyssey Updater', style: TextStyle(fontSize: 24)),
                  SizedBox(height: 10),
                  // Dummy content, replace with actual data when available
                  Text('Coming soon...', style: TextStyle(fontSize: 20)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getFormattedDate() {
    // Placeholder function to return a formatted date
    return '2023-10-01';
  }

  Future<void> _performUpdate() async {
    const String upgradeFolder = '/home/pi/orion/upgrade/';
    const String upgradeScript = '/home/pi/orion/upgrade.sh';
    const String downloadPath = '$upgradeFolder/orion_aarch64.tar.gz';

    if (_assetUrl.isEmpty) {
      _logger.warning('Asset URL is empty');
      return;
    }

    _logger.info('Downloading from $_assetUrl');

    try {
      // Purge and recreate the upgrade folder
      final upgradeDir = Directory(upgradeFolder);
      if (await upgradeDir.exists()) {
        try {
          await upgradeDir.delete(recursive: true);
        } catch (e) {
          _logger.warning('Could not purge upgrade directory');
        }
      }
      await upgradeDir.create(recursive: true);

      // Download the update file
      final response = await http.get(Uri.parse(_assetUrl));
      if (response.statusCode == 200) {
        final file = File(downloadPath);
        await file.writeAsBytes(response.bodyBytes);

        // Execute the upgrade script
        final result = await Process.run(upgradeScript, []);
        if (result.exitCode == 0) {
          _logger.info('Update script executed successfully');
        } else {
          _logger.warning('Update script failed: ${result.stderr}');
        }
      } else {
        _logger.warning('Failed to download update file');
      }
    } catch (e) {
      _logger.warning('Update failed: $e');
    }
  }
}
