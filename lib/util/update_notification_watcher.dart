import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:orion/util/update_manager.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:go_router/go_router.dart';
import 'package:orion/widgets/version_comparison.dart';

class UpdateNotificationWatcher {
  final BuildContext context;
  bool _isDialogShown = false;
  Timer? _cooldownTimer;

  UpdateNotificationWatcher._(this.context) {
    // Get the current providers and add listeners
    final updateManager = Provider.of<UpdateManager>(context, listen: false);
    final statusProvider = Provider.of<StatusProvider>(context, listen: false);

    updateManager.addListener(_check);
    statusProvider.addListener(_check);
  }

  void dispose() {
    try {
      final updateManager = Provider.of<UpdateManager>(context, listen: false);
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);
      updateManager.removeListener(_check);
      statusProvider.removeListener(_check);
    } catch (e) {
      // Providers might not be available during cleanup
    }
    _cooldownTimer?.cancel();
  }

  bool _isOnStatusScreen() {
    // Check the authoritative flag from StatusProvider first
    // Note: We avoid checking GoRouter location string directly because during
    // navigation transitions (e.g. popping the Status screen) the router check
    // might still return '/status' while the screen is actually disposing,
    // causing a race condition where the notification remains blocked.
    // Relying on the provider flag (managed by StatusScreen state) is safer.
    try {
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);
      return statusProvider.isStatusScreenOpen;
    } catch (e) {
      return false;
    }
  }

  void _check() {
    // Safety check: don't proceed if the widget is disposed
    if (!context.mounted) return;
    if (_isDialogShown) return;

    try {
      final updateManager = Provider.of<UpdateManager>(context, listen: false);
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);

      if (updateManager.shouldShowNotification) {
        final isPrinting = statusProvider.status?.isPrinting ?? false;
        final isPaused = statusProvider.status?.isPaused ?? false;
        final isStatusScreen = _isOnStatusScreen();

        if (!isPrinting && !isPaused && !isStatusScreen) {
          // If a timer is already running, let it finish (don't reset it)
          if (_cooldownTimer?.isActive ?? false) return;

          // Start a cooldown before showing the dialog
          _cooldownTimer = Timer(const Duration(seconds: 3), () {
            if (_isDialogShown) return;
            // Re-check conditions as they might have changed during delay
            if (!context.mounted) return;

            try {
              if (Provider.of<UpdateManager>(context, listen: false)
                  .shouldShowNotification) {
                final curIsPrinting =
                    Provider.of<StatusProvider>(context, listen: false)
                            .status
                            ?.isPrinting ??
                        false;
                final curIsPaused =
                    Provider.of<StatusProvider>(context, listen: false)
                            .status
                            ?.isPaused ??
                        false;
                final curIsStatusScreen = _isOnStatusScreen();

                if (!curIsPrinting && !curIsPaused && !curIsStatusScreen) {
                  _showDialog();
                }
              }
            } catch (e) {
              // Providers might not be available
            }
          });
        } else {
          // If we started printing/paused, cancel any pending notification
          _cooldownTimer?.cancel();
          _cooldownTimer = null;
        }
      } else {
        _cooldownTimer?.cancel();
        _cooldownTimer = null;
      }
    } catch (e) {
      // Providers not available, skip this check
    }
  }

  void _showDialog() {
    try {
      final updateManager = Provider.of<UpdateManager>(context, listen: false);
      _isDialogShown = true;
      final orion = updateManager.orionProvider;
      final athena = updateManager.athenaProvider;

      showDialog(
        context: context,
        builder: (ctx) => GlassAlertDialog(
          title: Text(
            FlutterI18n.translate(context, 'updateNotification.title'),
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (orion.isUpdateAvailable)
                  VersionComparison(
                    title: FlutterI18n.translate(
                        context, 'updateNotification.orion'),
                    branch: orion.release,
                    currentVersion: orion.currentVersion,
                    newVersion: orion.latestVersion,
                  ),
                if (orion.isUpdateAvailable && athena.updateAvailable)
                  const SizedBox(height: 12),
                if (athena.updateAvailable)
                  VersionComparison(
                    title: FlutterI18n.translate(
                        context, 'updateNotification.athenaOs'),
                    branch: athena.channel,
                    currentVersion: athena.currentVersion,
                    newVersion: athena.latestVersion,
                  ),
                const SizedBox(height: 16),
                Text(
                  FlutterI18n.translate(
                      context, 'updateNotification.wouldYouLike'),
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.grey.shade400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            GlassButton(
              tint: GlassButtonTint.neutral,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(140, 60),
              ),
              onPressed: () {
                updateManager.acknowledgeUpdatePrompt();
                updateManager.remindLater();
                Navigator.of(ctx).pop();
              },
              child: Text(FlutterI18n.translate(
                  context, 'updateNotification.remindLater')),
            ),
            GlassButton(
              tint: GlassButtonTint.positive,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(140, 60),
              ),
              onPressed: () {
                updateManager.acknowledgeUpdatePrompt();
                Navigator.of(ctx).pop();
                context.go('/updates');
              },
              child: Text(FlutterI18n.translate(
                  context, 'updateNotification.updateNow')),
            ),
          ],
        ),
      ).then((_) {
        _isDialogShown = false;
        // If the dialog was dismissed without pressing a button (barrier/back),
        // still acknowledge so we don't spam the user in this session.
        try {
          updateManager.acknowledgeUpdatePrompt();
        } catch (e) {
          // Provider might not be available during cleanup
        }
      });
    } catch (e) {
      _isDialogShown = false;
    }
  }

  static UpdateNotificationWatcher? install(BuildContext context) {
    // Try to get the providers - if they're not available in this context,
    // return null rather than throwing an error
    try {
      Provider.of<UpdateManager>(context, listen: false);
      Provider.of<StatusProvider>(context, listen: false);
      return UpdateNotificationWatcher._(context);
    } catch (e) {
      // Providers not available in this context
      return null;
    }
  }
}
