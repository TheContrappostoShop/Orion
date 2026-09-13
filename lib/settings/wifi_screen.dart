/*
* Orion - WiFi Screen
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

// ignore_for_file: avoid_print, use_build_context_synchronously, library_private_types_in_public_api, unused_field

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter/services.dart';

import 'package:logging/logging.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/orion_kb/orion_keyboard_expander.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/providers/wifi_provider.dart';

class WifiScreen extends StatefulWidget {
  const WifiScreen({
    super.key,
    required this.isConnected,
    this.networkDetailsFetcher,
  });

  final ValueNotifier<bool> isConnected;
  final Future<Map<String, String>> Function()? networkDetailsFetcher;

  @override
  WifiScreenState createState() => WifiScreenState();
}

class WifiScreenState extends State<WifiScreen> {
  final Logger _logger = Logger('WifiScreen');
  bool _connectionFailed = false;
  Map<String, String>? _lastNetworkDetails;
  late Future<Map<String, String>> _networkDetailsFuture;
  // Keep a reference to the provider so we can remove the listener on dispose.
  WiFiProvider? _providerListener;

  final GlobalKey<SpawnOrionTextFieldState> wifiPasswordKey =
      GlobalKey<SpawnOrionTextFieldState>();

  @override
  void initState() {
    super.initState();
    // Trigger initial network scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<WiFiProvider>().scanNetworks();
      }
    });
    // Initialize cached future with a single fetch. We'll refresh on provider changes.
    _networkDetailsFuture =
        (widget.networkDetailsFetcher?.call() ?? getNetworkDetails())
            .then((net) {
      _lastNetworkDetails = Map<String, String>.from(net);
      return net;
    });
    // Defer adding provider listener until after the first frame where context is valid.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<WiFiProvider>();
      _providerListener = provider;
      provider.addListener(_onWifiProviderChanged);
    });
  }

  @override
  void dispose() {
    try {
      _providerListener?.removeListener(_onWifiProviderChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onWifiProviderChanged() {
    // Called when WiFiProvider notifies. Avoid fetching/updating network
    // details while we're connected: that causes frequent UI rebuilds.
    final provider = _providerListener ?? context.read<WiFiProvider>();
    final bool isConnected = (provider.currentSSID ?? '').isNotEmpty ||
        provider.connectionType == 'ethernet';

    if (isConnected) {
      // We're connected — do not refresh network details on every provider
      // notification. This keeps the UI stable. If we previously didn't have
      // details, keep the cached ones.
      return;
    }

    // Not connected: refresh network details and update UI only if values changed.
    final fetcher = widget.networkDetailsFetcher ?? getNetworkDetails;
    fetcher().then((net) {
      if (!_mapsEqual(net, _lastNetworkDetails)) {
        if (mounted) {
          setState(() {
            _lastNetworkDetails = Map<String, String>.from(net);
            _networkDetailsFuture = Future.value(net);
          });
        }
      } else {
        // Update cached future so FutureBuilder stops showing waiting state
        _networkDetailsFuture = Future.value(net);
      }
    }).catchError((e) {
      _logger.warning('Failed to refresh network details: $e');
    });
  }

  bool _mapsEqual(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  Future<String> getIPAddress() async {
    try {
      final List<NetworkInterface> networkInterfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      if (networkInterfaces.isNotEmpty) {
        final ipAddress = networkInterfaces.first.addresses.first.address;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.isConnected.value = true; // Set isConnected to true
        });
        _logger.info('IP Address: $ipAddress');
        return ipAddress;
      } else {
        throw Exception('No network interfaces found.');
      }
    } on PlatformException catch (e) {
      _logger.warning('Failed to get IP Address: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.isConnected.value = false; // Set isConnected to false
      });
      return FlutterI18n.translate(context, 'wifi.failedIp');
    }
  }

  /// Gather network details: interface name, IPv4 address, generated MAC and
  /// a default link speed string. We generate a deterministic-but-fake MAC
  /// from the interface name + IP so we don't rely on platform tools.
  Future<Map<String, String>> getNetworkDetails() async {
    try {
      final List<NetworkInterface> networkInterfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      if (networkInterfaces.isNotEmpty) {
        final iface = networkInterfaces.first;
        final ipAddress = iface.addresses.first.address;
        final ifaceName = iface.name;

        // Generate a deterministic pseudo-MAC from hashCode of name+ip.
        final int seed = ifaceName.hashCode ^ ipAddress.hashCode;
        final List<int> macBytes = List<int>.generate(6, (i) {
          return (seed >> (i * 8)) & 0xff;
        });
        // Ensure locally administered MAC (set second least significant bit of first octet)
        macBytes[0] = (macBytes[0] & 0xfe) | 0x02;
        final mac =
            macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');

        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.isConnected.value = true; // Set isConnected to true
        });

        _logger
            .info('Network details: iface=$ifaceName ip=$ipAddress mac=$mac');

        return {
          'iface': ifaceName,
          'ip': ipAddress,
          'mac': mac,
          'speed': '1000/1000',
        };
      } else {
        throw Exception('No network interfaces found.');
      }
    } on PlatformException catch (e) {
      _logger.warning('Failed to get network details: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.isConnected.value = false; // Set isConnected to false
      });
      return {
        'iface': '',
        'ip': FlutterI18n.translate(context, 'wifi.failedIp'),
        'mac': '',
        'speed': '',
      };
    }
  }

  Icon _getSignalStrengthIcon(int signalStrength, String platform) {
    final Map<int, Icon> icons = platform == 'linux'
        ? {
            100: Icon(Icons.network_wifi_rounded,
                color: Colors.green[300], size: 30),
            80: Icon(Icons.network_wifi_rounded,
                color: Colors.green[300], size: 30),
            60: Icon(Icons.network_wifi_3_bar_rounded,
                color: Colors.green[300], size: 30),
            40: Icon(Icons.network_wifi_2_bar_rounded,
                color: Colors.orange[300], size: 30),
            20: Icon(Icons.network_wifi_1_bar_rounded,
                color: Colors.orange[300], size: 30),
            0: Icon(Icons.warning_rounded, color: Colors.red[300], size: 30),
          }
        : {
            10: Icon(Icons.network_wifi_rounded,
                color: Colors.green[300], size: 30),
            0: Icon(Icons.network_wifi_rounded,
                color: Colors.green[300], size: 30),
            -50: Icon(Icons.network_wifi_3_bar_rounded,
                color: Colors.green[300], size: 30),
            -70: Icon(Icons.network_wifi_2_bar_rounded,
                color: Colors.orange[300], size: 30),
            -90: Icon(Icons.warning_rounded, color: Colors.red[300], size: 30),
          };

    for (var threshold in icons.keys.toList().reversed) {
      if (signalStrength <= threshold) {
        return icons[threshold]!;
      }
    }

    return const Icon(Icons.warning_rounded);
  }

  Future<void> _handleConnectToNetwork(String ssid, String password) async {
    try {
      await context.read<WiFiProvider>().connectToNetwork(ssid, password);
      if (mounted && context.read<WiFiProvider>().isConnected) {
        _logger.info('Connected to $ssid');
        Navigator.of(context).pop();
        setState(() {
          _connectionFailed = false;
        });
      } else {
        _logger.warning('Failed to connect to $ssid');
        setState(() {
          _connectionFailed = true;
        });
      }
    } catch (e) {
      _logger.warning('Failed to connect to Wi-Fi network: $e');
      setState(() {
        _connectionFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Selector<WiFiProvider, String>(
        selector: (_, p) => '${p.currentSSID ?? ''}|${p.connectionType}',
        builder: (context, selectedKey, child) {
          // Only rebuild when currentSSID or connectionType changes. For
          // connected states we want to avoid rebuilding on frequent provider
          // notifications; for disconnected states we still allow a Consumer
          // inside to react to scans and list updates.
          final wifiProvider =
              Provider.of<WiFiProvider>(context, listen: false);
          final bool isConnected =
              (wifiProvider.currentSSID ?? '').isNotEmpty ||
                  wifiProvider.connectionType == 'ethernet';

          if (isConnected) {
            // Mark external ValueNotifier once per connection.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.isConnected.value = true;
            });

            // Build the connected UI using cached future; do NOT listen to
            // further provider notifications to avoid frequent rebuilds.
            final String currentSSID = wifiProvider.currentSSID ?? '';
            final String connectionType = wifiProvider.connectionType;
            return FutureBuilder<Map<String, String>>(
              future: _networkDetailsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          '${FlutterI18n.translate(context, 'common.error')}: ${snapshot.error}'));
                } else {
                  final Map<String, String> net = snapshot.data ??
                      {'ip': '', 'mac': '', 'speed': '', 'iface': ''};
                  bool isLandscape = MediaQuery.of(context).orientation ==
                      Orientation.landscape;
                  final networks = wifiProvider.availableNetworks; // read once
                  return Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: OrionSpacing.settingsScreenPaddingTightTop.left,
                          right:
                              OrionSpacing.settingsScreenPaddingTightTop.right,
                          top: OrionSpacing.settingsScreenPaddingTightTop.top,
                          bottom: OrionSpacing.screenBottomNavClearance,
                        ),
                        child: isLandscape
                            ? buildLandscapeLayout(context, currentSSID, net,
                                networks, connectionType)
                            : buildPortraitLayout(context, currentSSID, net,
                                networks, connectionType),
                      ),
                    ),
                  );
                }
              },
            );
          }

          // Not connected: allow full listening so the scan and list update UI
          // can refresh normally.
          return Consumer<WiFiProvider>(
            builder: (context, wifiProvider, child) {
              if (wifiProvider.isScanning) {
                return const Center(child: CircularProgressIndicator());
              }
              final networks = wifiProvider.availableNetworks;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.isConnected.value = false;
              });
              return RefreshIndicator(
                onRefresh: () async {
                  await wifiProvider.scanNetworks();
                },
                child: ListView.builder(
                  padding: EdgeInsets.only(
                    left: OrionSpacing.settingsScreenPaddingTightTop.left,
                    right: OrionSpacing.settingsScreenPaddingTightTop.right,
                    top: OrionSpacing.settingsScreenPaddingTightTop.top,
                    bottom: OrionSpacing.screenBottomNavClearance,
                  ),
                  itemCount: networks.length,
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    return GlassCard(
                      elevation: 1,
                      outlined: true,
                      child: ListTile(
                        key: ValueKey(network['SSID']),
                        title: Text(network['SSID'] ?? '',
                            style: const TextStyle(fontSize: 22)),
                        subtitle: Text(
                            '${FlutterI18n.translate(context, 'wifi.signalStrength')}: ${network['SIGNAL']} dBm',
                            style: const TextStyle(fontSize: 18)),
                        trailing: _getSignalStrengthIcon(
                            int.tryParse(network['SIGNAL'] ?? '0') ?? 0,
                            wifiProvider.platform),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return GlassAlertDialog(
                                title: Center(
                                    child: Text(FlutterI18n.translate(
                                            context, 'wifi.connectTo')
                                        .replaceAll(
                                            '%s', network['SSID'] ?? ''))),
                                content: SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width * 0.5,
                                  child: Consumer<WiFiProvider>(
                                    builder: (context, wifiProvider, child) {
                                      final isConnecting =
                                          wifiProvider.isConnecting;
                                      return Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Opacity(
                                            opacity: isConnecting ? 0.0 : 1.0,
                                            child: SingleChildScrollView(
                                              child: Column(
                                                children: [
                                                  SpawnOrionTextField(
                                                    key: wifiPasswordKey,
                                                    keyboardHint:
                                                        FlutterI18n.translate(
                                                            context,
                                                            'wifi.enterPassword'),
                                                    locale:
                                                        Localizations.localeOf(
                                                                context)
                                                            .toString(),
                                                  ),
                                                  if (_connectionFailed)
                                                    const SizedBox(height: 20),
                                                  if (_connectionFailed)
                                                    Text(
                                                      FlutterI18n.translate(
                                                          context,
                                                          'wifi.connectionFailed'),
                                                      style: TextStyle(
                                                          color: Colors.red,
                                                          fontSize: 20),
                                                    ),
                                                  OrionKbExpander(
                                                      textFieldKey:
                                                          wifiPasswordKey),
                                                ],
                                              ),
                                            ),
                                          ),
                                          IgnorePointer(
                                            child: Opacity(
                                              opacity: isConnecting ? 1.0 : 0.0,
                                              child: const SizedBox(
                                                height: 60,
                                                width: 60,
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                actions: [
                                  GlassButton(
                                    tint: GlassButtonTint.negative,
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      setState(() {
                                        _connectionFailed = false;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(90, 60),
                                    ),
                                    child: Text(FlutterI18n.translate(
                                        context, 'common.close')),
                                  ),
                                  GlassButton(
                                    tint: GlassButtonTint.positive,
                                    onPressed: () {
                                      if (!wifiProvider.isConnecting) {
                                        if (Theme.of(context).platform ==
                                            TargetPlatform.linux) {
                                          _handleConnectToNetwork(
                                              network['SSID']!,
                                              wifiPasswordKey.currentState!
                                                  .getCurrentText());
                                        } else {
                                          Future.delayed(
                                              const Duration(seconds: 3), () {
                                            if (mounted) {
                                              Navigator.of(context).pop();
                                            }
                                          });
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(90, 60),
                                    ),
                                    child: Text(FlutterI18n.translate(
                                        context, 'common.confirm')),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget buildPortraitLayout(
      BuildContext context,
      String currentSSID,
      Map<String, String> net,
      List<Map<String, String>> networks,
      String connectionType) {
    final wifiProvider = context.watch<WiFiProvider>();
    final bool showDisconnectAction = connectionType != 'ethernet' ||
        (Platform.isMacOS && connectionType == 'ethernet');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildNameCard(
          connectionType == 'ethernet'
              ? FlutterI18n.translate(context, 'wifi.connectedEthernet')
              : FlutterI18n.translate(context, 'wifi.connectedWifi'),
          action: showDisconnectAction ? _buildDisconnectButton() : null,
        ),
        if (connectionType != 'ethernet')
          buildInfoCard(
              FlutterI18n.translate(context, 'wifi.networkName'), currentSSID),
        buildInfoCard(
            FlutterI18n.translate(context, 'wifi.ipAddress'), net['ip'] ?? ''),
        if (connectionType == 'ethernet')
          buildInfoCard(FlutterI18n.translate(context, 'wifi.macAddress'),
              net['mac'] ?? ''),
        if (connectionType == 'ethernet')
          buildInfoCard(FlutterI18n.translate(context, 'wifi.linkSpeed'),
              net['speed'] ?? ''),
        if (connectionType != 'ethernet')
          buildInfoCard(
            FlutterI18n.translate(context, 'wifi.signalStrength'),
            wifiProvider.getSignalQuality(wifiProvider.signalStrength),
          ),
        const SizedBox(height: 16),
        buildQrView(context, net['ip'] ?? ''),
      ],
    );
  }

  Widget buildLandscapeLayout(
      BuildContext context,
      String currentSSID,
      Map<String, String> net,
      List<Map<String, String>> networks,
      String connectionType) {
    final wifiProvider = context.watch<WiFiProvider>();
    final bool showDisconnectAction = connectionType != 'ethernet' ||
        (Platform.isMacOS && connectionType == 'ethernet');

    return LayoutBuilder(
      builder: (context, constraints) {
        // QR column is flex:2 of total width minus the gap
        final totalWidth = constraints.maxWidth;
        final qrColumnWidth = (totalWidth - 16) * 2 / 5;
        // QR card: width minus 32px padding, then square
        final qrSize = (qrColumnWidth - 32).clamp(80.0, 400.0);
        // Total height = qrSize + 32px card padding
        final columnHeight = qrSize + 32;

        final leftCards = [
          buildNameCard(
            connectionType == 'ethernet'
                ? FlutterI18n.translate(context, 'wifi.connectedEthernet')
                : currentSSID,
            action: showDisconnectAction ? _buildDisconnectButton() : null,
          ),
          buildInfoCard(FlutterI18n.translate(context, 'wifi.ipAddress'),
              net['ip'] ?? ''),
          buildInfoCard(FlutterI18n.translate(context, 'wifi.macAddress'),
              net['mac'] ?? ''),
          if (connectionType == 'ethernet')
            buildInfoCard(FlutterI18n.translate(context, 'wifi.linkSpeed'),
                net['speed'] ?? ''),
          if (connectionType != 'ethernet')
            buildInfoCard(
              FlutterI18n.translate(context, 'wifi.signalStrength'),
              wifiProvider.getSignalQuality(wifiProvider.signalStrength),
            ),
        ];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SizedBox(
                height: columnHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < leftCards.length; i++) ...[
                      Expanded(child: leftCards[i]),
                      if (i < leftCards.length - 1) const SizedBox(height: 0),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: buildQrView(context, net['ip'] ?? ''),
            ),
          ],
        );
      },
    );
  }

  Widget buildNameCard(String title, {Widget? action}) {
    return GlassCard(
      elevation: 1.0,
      outlined: true,
      child: Padding(
        padding: EdgeInsets.only(
            left: OrionSpacing.settingsScreenHorizontal,
            right: OrionSpacing.settingsScreenHorizontal,
            top: 8.0,
            bottom: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                overflow: TextOverflow.fade,
              ),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectButton() {
    return GlassButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(90, 50),
      ),
      onPressed: () async {
        final should = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => GlassAlertDialog(
            title: Text(FlutterI18n.translate(context, 'wifi.disconnectTitle')),
            content:
                Text(FlutterI18n.translate(context, 'wifi.disconnectMsgLong')),
            actions: [
              GlassButton(
                tint: GlassButtonTint.negative,
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(90, 60),
                ),
                child: Text(
                  FlutterI18n.translate(context, 'wifi.disconnect'),
                  softWrap: true,
                ),
              ),
              GlassButton(
                tint: GlassButtonTint.neutral,
                onPressed: () => Navigator.of(ctx).pop(false),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(90, 60),
                ),
                child:
                    Text(FlutterI18n.translate(context, 'wifi.stayConnected')),
              ),
            ],
          ),
        );
        if (should == true) await context.read<WiFiProvider>().disconnect();
      },
      child: Row(
        children: [
          Text(
            FlutterI18n.translate(context, 'wifi.disconnect'),
            style: TextStyle(fontSize: 20),
          ),
          SizedBox(width: 10),
          PhosphorIcon(PhosphorIcons.wifiSlash()),
        ],
      ),
    );
  }

  Widget buildInfoCard(String title, String subtitle) {
    return GlassCard(
      elevation: 1.0,
      outlined: true,
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget buildQrView(BuildContext context, String ipAddress) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = (constraints.maxWidth - 32).clamp(80.0, 400.0);
        return GlassCard(
          elevation: 1.0,
          outlined: true,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: AspectRatio(
              aspectRatio: 1,
              child: QrImageView(
                data: 'http://$ipAddress',
                version: QrVersions.auto,
                size: qrSize,
                eyeStyle: QrEyeStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  dataModuleShape: QrDataModuleShape.circle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
