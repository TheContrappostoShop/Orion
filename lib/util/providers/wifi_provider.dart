/*
* Orion - WiFi Provider
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
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:orion/util/orion_config.dart';

import 'wifi_backends/wifi_backend.dart';
import 'wifi_backends/modern_wifi_backend.dart';
import 'wifi_backends/legacy_wifi_backend.dart';

/// Provides comprehensive WiFi management including status, scanning, and connection.
/// Supports both modern (nmcli-based) and legacy (iwlist+wpa_supplicant) backends
/// based on the configured wifiMode setting.
class WiFiProvider with ChangeNotifier {
  final Logger _log = Logger('WiFiProvider');
  late WiFiBackend _backend;

  String? _currentSSID;
  int? _signalStrength; // 0-100 for Linux, negative dBm for macOS
  bool _isConnected = false;
  String _connectionType = 'none'; // 'wifi' | 'ethernet' | 'none'
  String _platform = 'unknown';
  String? _ipAddress;
  String? _ifaceName;
  String? _macAddress;
  String? _linkSpeed;
  List<Map<String, String>> _availableNetworks = [];
  bool _isConnecting = false;
  bool _isScanning = false;

  String? get currentSSID => _currentSSID;
  int? get signalStrength => _signalStrength;
  bool get isConnected => _isConnected;
  bool get isEthernet => _connectionType == 'ethernet';
  bool get isWiFi => _connectionType == 'wifi';
  String get connectionType => _connectionType;
  String get platform => _platform;
  String? get ipAddress => _ipAddress;
  String? get ifaceName => _ifaceName;
  String? get macAddress => _macAddress;
  String? get linkSpeed => _linkSpeed;
  List<Map<String, String>> get availableNetworks =>
      List.unmodifiable(_availableNetworks);
  bool get isConnecting => _isConnecting;
  bool get isScanning => _isScanning;

  Timer? _pollTimer;
  bool _disposed = false;
  bool _unsupportedWarningShown = false;
  static const Duration _pollInterval = Duration(seconds: 5);

  WiFiProvider({bool startPolling = true}) {
    _detectPlatform();
    // Initialize backend asynchronously - don't block constructor
    _initializeBackend().then((_) {
      if (startPolling) {
        _startPolling();
      }
    });
  }

  /// Check if modern backend (nmcli) is available on the system
  Future<bool> _isModernBackendAvailable() async {
    try {
      final result = await Process.run('which', ['nmcli']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Check if legacy backend tools are available on the system
  Future<bool> _isLegacyBackendAvailable() async {
    try {
      final iwlistResult = await Process.run('which', ['iwlist']);
      final iwconfigResult = await Process.run('which', ['iwconfig']);
      return iwlistResult.exitCode == 0 && iwconfigResult.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Initialize the appropriate WiFi backend based on configuration
  /// with automatic fallback from modern to legacy if modern is unavailable
  Future<void> _initializeBackend() async {
    try {
      final config = OrionConfig();
      final wifiMode = config.getString('wifiMode', category: 'advanced');

      if (wifiMode == 'legacy') {
        // User explicitly requested legacy mode
        _backend = LegacyWiFiBackend();
        _log.info(
            'Using legacy WiFi backend (iwlist + wpa_supplicant) - explicitly configured');
      } else {
        // Default to modern, or user explicitly set 'modern'
        // Try modern backend first
        final modernAvailable = await _isModernBackendAvailable();

        if (modernAvailable) {
          _backend = ModernWiFiBackend();
          _log.info('Using modern WiFi backend (nmcli)');
        } else {
          // Modern not available, attempt fallback to legacy
          _log.warning(
              'nmcli not found, attempting fallback to legacy WiFi backend');
          final legacyAvailable = await _isLegacyBackendAvailable();

          if (legacyAvailable) {
            _backend = LegacyWiFiBackend();
            _log.info(
                'Successfully fell back to legacy WiFi backend (iwlist + wpa_supplicant)');
          } else {
            // Neither available, default to modern (will fail gracefully)
            _log.warning(
                'No WiFi backend tools found (nmcli, iwlist, or iwconfig missing), using modern backend with limited functionality');
            _backend = ModernWiFiBackend();
          }
        }
      }

      // Inject state update callbacks into backend
      _connectBackendCallbacks();
    } catch (e) {
      _log.warning('Failed to initialize backend: $e, defaulting to modern');
      _backend = ModernWiFiBackend();
      _connectBackendCallbacks();
    }
  }

  /// Connect the backend's state callbacks to the provider's state fields
  void _connectBackendCallbacks() {
    // For Modern backend
    if (_backend is ModernWiFiBackend) {
      final modern = _backend as ModernWiFiBackend;
      modern.updateState = (ssid, signal, connected, connectionType) {
        _currentSSID = ssid;
        _signalStrength = signal;
        _isConnected = connected;
        _connectionType = connectionType;
      };
      modern.updateIp = (ip) {
        _ipAddress = ip;
      };
      modern.updateIfaceName = (name) {
        _ifaceName = name;
      };
    }
    // For Legacy backend
    else if (_backend is LegacyWiFiBackend) {
      final legacy = _backend as LegacyWiFiBackend;
      legacy.updateState = (ssid, signal, connected, connectionType) {
        _currentSSID = ssid;
        _signalStrength = signal;
        _isConnected = connected;
        _connectionType = connectionType;
      };
      legacy.updateIp = (ip) {
        _ipAddress = ip;
      };
      legacy.updateIfaceName = (name) {
        _ifaceName = name;
      };
    }
  }

  void _detectPlatform() {
    if (Platform.isLinux) {
      _platform = 'linux';
    } else if (Platform.isMacOS) {
      _platform = 'macos';
    } else {
      _platform = 'other';
    }
  }

  void _startPolling() {
    if (_disposed) return;

    // Initial fetch
    _fetchWiFiStatus();

    // Set up periodic polling
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_disposed) {
        _fetchWiFiStatus();
      }
    });
  }

  Future<void> _fetchWiFiStatus() async {
    if (_disposed) return;
    // Snapshot previous state so we only notify listeners when meaningful
    // values change. This reduces noisy notifications that cause UI flicker.
    final prevCurrentSSID = _currentSSID;
    final prevSignalStrength = _signalStrength;
    final prevIsConnected = _isConnected;
    final prevConnectionType = _connectionType;
    final prevIpAddress = _ipAddress;
    final prevIfaceName = _ifaceName;
    final prevMacAddress = _macAddress;
    final prevLinkSpeed = _linkSpeed;

    if (!Platform.isLinux && !Platform.isMacOS) {
      if (!_unsupportedWarningShown) {
        _log.warning('WiFi status fetching is not supported on this platform');
        _unsupportedWarningShown = true;
      }
      _currentSSID = null;
      _signalStrength = null;
      _isConnected = false;
      _connectionType = 'none';
      _ipAddress = null;
      _ifaceName = null;
      _macAddress = null;
      _linkSpeed = null;

      final changed = (prevCurrentSSID != _currentSSID) ||
          (prevSignalStrength != _signalStrength) ||
          (prevIsConnected != _isConnected) ||
          (prevConnectionType != _connectionType) ||
          (prevIpAddress != _ipAddress) ||
          (prevIfaceName != _ifaceName) ||
          (prevMacAddress != _macAddress) ||
          (prevLinkSpeed != _linkSpeed);

      if (changed && !_disposed) notifyListeners();
      return;
    }
    try {
      // Delegate to backend implementation
      if (!Platform.isMacOS) {
        await _backend.fetchWiFiStatus(); // This only works on Linux.
      } else {
        // For macOS, we fake the WiFi status for development purposes
        _currentSSID = 'MockNetwork';
        _signalStrength = -50; // Good signal
        _isConnected = true;
        _connectionType = 'wifi';
        _ipAddress = '';
      }

      // Determine if any of the observed fields changed
      final changed = (prevCurrentSSID != _currentSSID) ||
          (prevSignalStrength != _signalStrength) ||
          (prevIsConnected != _isConnected) ||
          (prevConnectionType != _connectionType) ||
          (prevIpAddress != _ipAddress) ||
          (prevIfaceName != _ifaceName) ||
          (prevMacAddress != _macAddress) ||
          (prevLinkSpeed != _linkSpeed);

      if (changed && !_disposed) notifyListeners();
    } catch (e, st) {
      _log.fine('Failed to fetch WiFi status', e, st);
      _isConnected = false;
      _currentSSID = null;
      _signalStrength = null;
      _ipAddress = null;
      _connectionType = 'none';

      final changed = (prevCurrentSSID != _currentSSID) ||
          (prevSignalStrength != _signalStrength) ||
          (prevIsConnected != _isConnected) ||
          (prevConnectionType != _connectionType) ||
          (prevIpAddress != _ipAddress) ||
          (prevIfaceName != _ifaceName) ||
          (prevMacAddress != _macAddress) ||
          (prevLinkSpeed != _linkSpeed);

      if (changed && !_disposed) notifyListeners();
    }
  }

  /// Scan for available WiFi networks
  Future<List<Map<String, String>>> scanNetworks() async {
    if (_platform == 'other') {
      _log.warning('WiFi scanning not supported on this platform');
      return [];
    }

    _isScanning = true;
    notifyListeners();

    try {
      if (_platform == 'macos') {
        // Return mock networks for macOS (for development)
        final networks = List.generate(10, (i) {
          int rand = Random().nextInt(100);
          return {
            'SSID': 'Network $rand',
            'SIGNAL': '${-30 - i * 5}',
            'SECURITY': '(WPA2)'
          };
        });
        _availableNetworks = networks;
      } else {
        // Delegate to backend
        final networks = await _backend.scanNetworks();
        _availableNetworks = networks;
      }
    } catch (e, st) {
      _log.severe('Error scanning WiFi networks', e, st);
      _availableNetworks = [];
    } finally {
      _isScanning = false;
      notifyListeners();
    }

    return _availableNetworks;
  }

  /// Connect to a WiFi network
  Future<bool> connectToNetwork(String ssid, String password) async {
    _isConnecting = true;
    notifyListeners();

    try {
      if (_platform == 'macos') {
        // Fake connection for macOS development
        await Future.delayed(const Duration(seconds: 2));
        _log.info('Fake connected to $ssid (macOS dev mode)');
        _currentSSID = ssid;
        _isConnected = true;
        _signalStrength = -45; // Good signal
        await scanNetworks();
        return true;
      } else if (_platform == 'linux') {
        final result = await _backend.connectToNetwork(ssid, password);
        if (result) {
          await scanNetworks();
        }
        return result;
      } else {
        _log.warning('WiFi connection not supported on this platform');
        return false;
      }
    } catch (e, st) {
      _log.warning('Failed to connect to WiFi network', e, st);
      return false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  /// Disconnect from current WiFi network
  Future<bool> disconnect() async {
    try {
      _log.info('Disconnecting Wi-Fi');

      if (_platform == 'macos') {
        // Fake disconnection for macOS development
        await Future.delayed(const Duration(seconds: 1));
        _currentSSID = null;
        _signalStrength = null;
        _isConnected = false;
        _ipAddress = null;
        _ifaceName = null;
        _macAddress = null;
        _linkSpeed = null;
        await scanNetworks();
        notifyListeners();
        _log.info('Fake disconnected (macOS dev mode)');
        return true;
      } else if (_platform == 'linux') {
        final result = await _backend.disconnect();
        if (result) {
          _currentSSID = null;
          _signalStrength = null;
          _isConnected = false;
          _ipAddress = null;
          _ifaceName = null;
          _macAddress = null;
          _linkSpeed = null;
          await scanNetworks();
          notifyListeners();
        }
        return result;
      } else {
        _log.warning('WiFi disconnection not supported on this platform');
        return false;
      }
    } catch (e, st) {
      _log.warning('Failed to disconnect Wi-Fi', e, st);
      return false;
    }
  }

  /// Get signal strength quality label
  String getSignalQuality(int? signal) {
    if (signal == null) return 'Unknown';

    if (_platform == 'linux') {
      // Linux uses 0-100 percentage
      if (signal >= 80) return 'Excellent';
      if (signal >= 60) return 'Good';
      if (signal >= 40) return 'Fair';
      return 'Poor';
    } else {
      // macOS uses negative dBm
      if (signal >= -50) return 'Excellent';
      if (signal >= -60) return 'Good';
      if (signal >= -70) return 'Fair';
      return 'Poor';
    }
  }

  /// Manually refresh WiFi status
  Future<void> refresh() async {
    await _fetchWiFiStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
