/*
* Orion - Connection Error Dialog
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

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'package:logging/logging.dart';
import 'package:orion/backend_service/backend_registry.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/util/orion_config.dart';

/// Show a connection dialog that displays current attempt counts and a
/// countdown to the next scheduled retry. The dialog listens to the
/// [StatusProvider] for values and updates every second while visible.
Future<void> showConnectionErrorDialog(BuildContext context) async {
  final completer = Completer<void>();
  final log = Logger('ConnectionErrorDialog');

  Future<void> attemptShow(int triesLeft) async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check for Navigator and MaterialLocalizations availability before
      // attempting to show the dialog. If either is missing, delay and
      // retry to avoid synchronous exceptions.
      final hasNavigator = Navigator.maybeOf(context) != null;
      final hasMaterialLocs = Localizations.of<MaterialLocalizations>(
              context, MaterialLocalizations) !=
          null;
      if (!hasNavigator || !hasMaterialLocs) {
        log.info(
            'showConnectionErrorDialog: context not ready (navigator=$hasNavigator, materialLocs=$hasMaterialLocs), triesLeft=$triesLeft');
        if (triesLeft > 0) {
          Future.delayed(const Duration(milliseconds: 300),
              () => attemptShow(triesLeft - 1));
        } else {
          if (!completer.isCompleted) completer.complete();
        }
        return;
      }

      try {
        log.info(
            'showConnectionErrorDialog: attempting to show dialog (triesLeft=$triesLeft)');
        showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (BuildContext ctx) {
            return _ConnectionErrorDialogContent();
          },
        ).then((_) {
          if (!completer.isCompleted) completer.complete();
        }).catchError((err, st) {
          log.warning('showConnectionErrorDialog: showDialog failed', err, st);
          if (!completer.isCompleted) completer.complete();
        });
      } catch (e, st) {
        log.warning(
            'showConnectionErrorDialog: synchronous showDialog threw', e, st);
        if (triesLeft > 0) {
          Future.delayed(const Duration(milliseconds: 300),
              () => attemptShow(triesLeft - 1));
        } else {
          if (!completer.isCompleted) completer.complete();
        }
      }
    });
  }

  // Try a few times to avoid calling showDialog before Navigator/Localizations
  attemptShow(5);
  return completer.future;
}

class _ConnectionErrorDialogContent extends StatefulWidget {
  @override
  State<_ConnectionErrorDialogContent> createState() =>
      _ConnectionErrorDialogContentState();
}

class _ConnectionErrorDialogContentState
    extends State<_ConnectionErrorDialogContent> {
  Timer? _tick;

  Widget _buildDialogActions({
    required VoidCallback retryNow,
  }) {
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.warn,
            onPressed: retryNow,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 60),
            ),
            child: Text(FlutterI18n.translate(context, 'connection.retryNow')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 60),
            ),
            child: Text(FlutterI18n.translate(context, 'common.close')),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    // Update UI each second while dialog is visible so countdown updates.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _formatCountdown(DateTime? at) {
    if (at == null) return '—';
    final now = DateTime.now();
    if (at.isBefore(now)) {
      return FlutterI18n.translate(context, 'connection.sec0');
    }
    final diff = at.difference(now);
    final s = diff.inSeconds;
    if (s < 60) {
      return FlutterI18n.translate(context, 'connection.sec')
          .replaceAll('%s', '$s');
    }
    final m = diff.inMinutes;
    final sec = s % 60;
    return FlutterI18n.translate(context, 'connection.minSec')
        .replaceAll('%s', '$m')
        .replaceAll('%s', '$sec');
  }

  @override
  Widget build(BuildContext context) {
    final statusProv = Provider.of<StatusProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final pollAttempts = statusProv.pollAttemptCount;
    final sseAttempts = statusProv.sseAttemptCount;
    final next = statusProv.nextRetryAt;
    final sseSupported = statusProv.sseSupported;
    final devMode =
        OrionConfig().getFlag('developerMode', category: 'advanced');

    void retryNow() {
      // Close dialog and trigger an immediate refresh
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      try {
        statusProv.refresh();
      } catch (_) {}
    }

    if (devMode) {
      // Compute backend and target URI for developer display
      String backendName = '';
      String targetUri = '';
      try {
        final cfg = OrionConfig();
        final configuredBackend =
            cfg.getString('backend', category: 'advanced');
        final backendId =
            configuredBackend.isEmpty ? BackendIds.odyssey : configuredBackend;
        backendName = configuredBackend;
        final registry = BackendRegistry();
        final supportsAthena = registry.supportsCapability(
                backendId, BackendCapabilities.supportsAthena) ??
            false;
        if (supportsAthena) {
          final base = cfg.getString('nanodlp.base_url', category: 'advanced');
          final useCustom = cfg.getFlag('useCustomUrl', category: 'advanced');
          final custom = cfg.getString('customUrl', category: 'advanced');
          if (base.isNotEmpty) {
            targetUri = base;
          } else if (useCustom && custom.isNotEmpty) {
            targetUri = custom;
          } else {
            targetUri = 'http://localhost';
          }
          if (backendName.isEmpty) backendName = backendId;
        } else {
          final custom = cfg.getString('customUrl', category: 'advanced');
          final useCustom = cfg.getFlag('useCustomUrl', category: 'advanced');
          targetUri = (useCustom && custom.isNotEmpty)
              ? custom
              : 'http://localhost:12357';
          if (backendName.isEmpty) backendName = backendId;
        }
      } catch (_) {
        // best-effort: leave strings empty if config read fails
      }

      return GlassAlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.wifi_off,
              color: scheme.primary,
              size: 26,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FlutterI18n.translate(context, 'connection.connectionLost'),
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sseSupported == false
                        ? FlutterI18n.translate(
                            context, 'connection.pollingOnly')
                        : FlutterI18n.translate(
                            context, 'connection.attemptingReconnect'),
                    style: TextStyle(
                      fontSize: 16,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Developer info: backend and target URI in a compact two-column row
            if (backendName.isNotEmpty || targetUri.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            FlutterI18n.translate(
                                context, 'connection.backend'),
                            style:
                                TextStyle(fontSize: 14, color: Colors.white70)),
                        const SizedBox(height: 4),
                        Text(
                          backendName.isNotEmpty ? backendName : 'unknown',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            FlutterI18n.translate(context, 'connection.target'),
                            style:
                                TextStyle(fontSize: 14, color: Colors.white70)),
                        const SizedBox(height: 4),
                        Text(
                          targetUri.isNotEmpty ? targetUri : 'unknown',
                          style: const TextStyle(
                              fontSize: 18,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
                FlutterI18n.translate(
                    context, 'connection.attemptingReconnect'),
                style: TextStyle(fontSize: 14, color: Colors.white70)),
            const SizedBox(height: 6),
            Text(
              _formatCountdown(next),
              style: const TextStyle(
                  fontSize: 22, height: 1.1, fontWeight: FontWeight.w600),
              textAlign: TextAlign.left,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          FlutterI18n.translate(
                              context, 'connection.pollAttempts'),
                          style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('$pollAttempts',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          FlutterI18n.translate(
                              context, 'connection.sseAttempts'),
                          style: TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('$sseAttempts',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _buildDialogActions(retryNow: retryNow),
        ],
      );
    }

    // Production (non-developer) compact dialog
    return GlassAlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.wifi_off,
            color: scheme.primary,
            size: 26,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        FlutterI18n.translate(
                            context, 'connection.connectionLost'),
                        style: const TextStyle(
                            fontSize: 25, fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Show attempt counter next to title in production mode
                    Builder(builder: (ctx) {
                      final attempts = statusProv.pollAttemptCount;
                      final maxAttempts = statusProv.maxReconnectAttempts;
                      if (attempts > 0) {
                        return Text('($attempts/$maxAttempts)',
                            style: TextStyle(
                                fontSize: 16,
                                color:
                                    scheme.onSurface.withValues(alpha: 0.72)));
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Text(FlutterI18n.translate(context, 'connection.attemptingReconnect'),
              style: TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            _formatCountdown(next),
            style: const TextStyle(
                fontSize: 32, height: 1.1, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
      actions: [
        _buildDialogActions(retryNow: retryNow),
      ],
    );
  }
}
