/*
* Orion - Modern WiFi Backend (nmcli)
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

import 'dart:io';

import 'package:logging/logging.dart';

import 'wifi_backend.dart';

/// Modern WiFi backend using nmcli (NetworkManager Command Line Interface)
/// Supports scanning, connecting, and disconnecting from WiFi networks
/// via the NetworkManager service (standard on modern Linux systems).
class ModernWiFiBackend extends WiFiBackend {
  final Logger _log = Logger('ModernWiFiBackend');

  // These will be provided by the WiFiProvider parent
  late Function(String?, int?, bool, String)
      updateState; // ssid, signal, connected, connectionType
  late Function(String?) updateIp;
  late Function(String?) updateIfaceName;

  @override
  Future<void> fetchWiFiStatus() async {
    try {
      // Get active connection
      final result = await Process.run(
        'nmcli',
        ['-t', '-f', 'active,ssid,signal', 'dev', 'wifi'],
      );

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final activeLine = lines.firstWhere(
          (line) => line.startsWith('yes:'),
          orElse: () => '',
        );

        if (activeLine.isNotEmpty) {
          final parts = activeLine.split(':');
          if (parts.length >= 3) {
            updateState(parts[1], int.tryParse(parts[2]) ?? 0, true, 'wifi');
            await fetchIPAddress();
          } else {
            updateState(null, null, false, 'none');
          }
        } else {
          updateState(null, null, false, 'none');
        }
      } else {
        updateState(null, null, false, 'none');
      }
    } catch (e) {
      _log.fine('Error fetching Linux WiFi status: $e');
      updateState(null, null, false, 'none');
    }

    // If not connected via WiFi, check for Ethernet connectivity (nmcli)
    if (!await _isConnectedWiFi()) {
      await _checkEthernetConnection();
    }
  }

  Future<bool> _isConnectedWiFi() async {
    try {
      final result = await Process.run(
        'nmcli',
        ['-t', '-f', 'active,ssid', 'dev', 'wifi'],
      );
      if (result.exitCode == 0) {
        return result.stdout.toString().contains('yes:');
      }
    } catch (_) {}
    return false;
  }

  Future<void> _checkEthernetConnection() async {
    try {
      final result = await Process.run(
        'nmcli',
        ['-t', '-f', 'TYPE,STATE,DEVICE', 'device'],
      );
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.startsWith('ethernet:')) {
            final parts = line.split(':');
            if (parts.length >= 3 && parts[1] == 'connected') {
              final dev = parts[2];
              updateState(null, null, true, 'ethernet');
              updateIfaceName(dev);
              try {
                final interfaces =
                    await NetworkInterface.list(type: InternetAddressType.IPv4);
                NetworkInterface? matching;
                for (final i in interfaces) {
                  if (i.name == dev) {
                    matching = i;
                    break;
                  }
                }
                matching ??= interfaces.isNotEmpty ? interfaces.first : null;
                if (matching != null && matching.addresses.isNotEmpty) {
                  updateIp(matching.addresses.first.address);
                }
              } catch (e) {
                _log.fine('Failed to resolve IP for $dev: $e');
              }
              await fetchNetworkDetails(dev);
              break;
            }
          }
        }
      }
    } catch (e) {
      _log.fine('Ethernet check failed: $e');
    }
  }

  Future<void> fetchIPAddress() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      if (interfaces.isNotEmpty) {
        final iface = interfaces.first;
        updateIfaceName(iface.name);
        updateIp(iface.addresses.first.address);
        await fetchNetworkDetails(iface.name);
      }
    } catch (e) {
      _log.fine('Error fetching IP address: $e');
    }
  }

  @override
  Future<List<Map<String, String>>> scanNetworks() async {
    try {
      await Process.run('sudo', ['nmcli', 'device', 'wifi', 'rescan']);
      _log.info('Rescanning Wi-Fi networks');
      final result = await Process.run('nmcli', ['device', 'wifi', 'list']);

      if (result.exitCode == 0) {
        final networks = <Map<String, String>>[];
        final lines = result.stdout.toString().split('\n');
        final pattern = RegExp(
          r"(?:(\*)\s+)?([0-9A-Fa-f:]{17})\s+(.*?)\s+(Infra)\s+(\d+)\s+([\d\sMbit/s]+)\s+(\d+)\s+([\w▂▄▆█_]+)\s+(.*)",
          multiLine: true,
        );

        for (int i = 2; i < lines.length; i++) {
          final match = pattern.firstMatch(lines[i]);
          if (match != null) {
            networks.add({
              'SSID': match.group(3) ?? '',
              'SIGNAL': match.group(7) ?? '',
              'SECURITY': match.group(9) ?? '',
            });
          }
        }

        return _mergeNetworks(networks);
      } else {
        _log.severe('Failed to get Wi-Fi networks: ${result.stderr}');
        return [];
      }
    } catch (e, st) {
      _log.severe('Error scanning WiFi networks', e, st);
      return [];
    }
  }

  List<Map<String, String>> _mergeNetworks(List<Map<String, String>> networks) {
    final merged = <String, Map<String, String>>{};

    for (var network in networks) {
      final ssid = network['SSID'];
      if (ssid == null || ssid.isEmpty) continue;

      if (merged.containsKey(ssid)) {
        final existingSignal = int.parse(merged[ssid]!['SIGNAL']!);
        final newSignal = int.parse(network['SIGNAL']!);
        if (newSignal > existingSignal) {
          merged[ssid] = network;
        }
      } else {
        merged[ssid] = network;
      }
    }

    return merged.values.toList();
  }

  @override
  Future<bool> connectToNetwork(String ssid, String password) async {
    try {
      final result = await Process.run(
        'sudo',
        ['nmcli', 'dev', 'wifi', 'connect', ssid, 'password', password],
      );

      if (result.exitCode == 0) {
        _log.info('Connected to $ssid');
        await fetchWiFiStatus();
        return true;
      } else {
        _log.warning('Failed to connect to $ssid: ${result.stderr}');
        return false;
      }
    } catch (e, st) {
      _log.warning('Failed to connect to WiFi network', e, st);
      return false;
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      _log.info('Disconnecting Wi-Fi');
      final iface = 'wlan0'; // fallback or could pass from parent
      final result = await Process.run(
        'sudo',
        ['nmcli', 'device', 'disconnect', iface],
      );

      if (result.exitCode == 0) {
        updateState(null, null, false, 'none');
        return true;
      } else {
        _log.warning('Failed to disconnect: ${result.stderr}');
        return false;
      }
    } catch (e, st) {
      _log.warning('Failed to disconnect Wi-Fi', e, st);
      return false;
    }
  }

  @override
  Future<void> fetchNetworkDetails(String iface) async {
    // MAC address from sysfs
    try {
      final macFile = File('/sys/class/net/$iface/address');
      if (await macFile.exists()) {
        // This would update MAC in the WiFiProvider
      }
    } catch (e) {
      _log.fine('Failed reading MAC from sysfs: $e');
    }

    // Speed from sysfs (ethernet only — skip known-broken interfaces)
    if (!_brokenSpeedInterfaces.contains(iface)) {
      try {
        final speedFile = File('/sys/class/net/$iface/speed');
        if (await speedFile.exists()) {
          final val = (await speedFile.readAsString()).trim();
          if (val.isNotEmpty && val != '-1') {
            // This would update link speed in the WiFiProvider
          }
        }
      } catch (e) {
        _log.fine('Failed reading speed from sysfs: $e');
        _brokenSpeedInterfaces.add(iface);
      }
    }
  }

  /// Tracks interfaces where /sys/class/net/`<iface>`/speed is known to fail
  /// (e.g. WiFi interfaces) so we don't retry on every poll cycle.
  final Set<String> _brokenSpeedInterfaces = {};
}
