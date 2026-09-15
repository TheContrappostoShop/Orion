import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/settings/update_progress.dart';
import 'package:orion/util/providers/athena_update_provider.dart';
import 'package:orion/util/providers/orion_update_provider.dart';
import 'package:orion/util/orion_config.dart';

/// Which update component(s) to clear pending flags for.
enum UpdateComponent { orion, athena }

class UpdateManager extends ChangeNotifier {
  final OrionUpdateProvider orionProvider;
  final AthenaUpdateProvider athenaProvider;
  final OrionConfig _config = OrionConfig();
  Timer? _timer;
  Timer? _debounceTimer;
  bool _suppressNotifications = false;
  bool _promptAcknowledgedThisSession = false;
  static const String _remindLaterKeyField = 'remindLaterKey';

  UpdateManager(this.orionProvider, this.athenaProvider,
      {bool enableAutoChecks = true}) {
    if (enableAutoChecks) {
      _startTimer();
    }
    OrionConfig.addChangeListener(_onConfigChanged);
  }

  set suppressNotifications(bool value) {
    if (_suppressNotifications != value) {
      _suppressNotifications = value;
      notifyListeners();
    }
  }

  bool get suppressNotifications => _suppressNotifications;

  /// Mark that a user has acknowledged an update prompt for this app session.
  /// Prevents further update dialogs until Orion is restarted.
  void acknowledgeUpdatePrompt() {
    if (_promptAcknowledgedThisSession) return;
    _promptAcknowledgedThisSession = true;
    notifyListeners();
  }

  void _startTimer() {
    // Initial check after a short delay to allow app to settle
    Future.delayed(const Duration(seconds: 5), () => checkForUpdates());

    // Periodic check every 20 minutes
    _timer =
        Timer.periodic(const Duration(minutes: 20), (_) => checkForUpdates());
  }

  void _onConfigChanged() {
    // Debounce config changes to avoid rapid re-checks or loops
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      checkForUpdates();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounceTimer?.cancel();
    OrionConfig.removeChangeListener(_onConfigChanged);
    super.dispose();
  }

  Future<void> checkForUpdates() async {
    await Future.wait([
      orionProvider.checkForUpdates(),
      athenaProvider.checkForUpdates(),
    ]);

    final available =
        orionProvider.isUpdateAvailable || athenaProvider.shouldNotify;
    _config.setFlag('available', available, category: 'updates');

    if (available) {
      // Persist version details so we can show the dialog immediately on restart
      if (orionProvider.isUpdateAvailable) {
        _config.setString('orion.current', orionProvider.currentVersion,
            category: 'updates');
        _config.setString('orion.latest', orionProvider.latestVersion,
            category: 'updates');
        _config.setString('orion.release', orionProvider.release,
            category: 'updates');
      }
      if (athenaProvider.shouldNotify) {
        _config.setString('athena.current', athenaProvider.currentVersion,
            category: 'updates');
        _config.setString('athena.latest', athenaProvider.latestVersion,
            category: 'updates');
        _config.setString('athena.channel', athenaProvider.channel,
            category: 'updates');
      }
    }

    notifyListeners();
  }

  void remindLater() {
    final remindTime = DateTime.now().add(const Duration(hours: 24));
    _config.setString('remindLater', remindTime.toIso8601String(),
        category: 'updates');
    _config.setString(_remindLaterKeyField, _currentUpdateNotificationKey(),
        category: 'updates');
    notifyListeners();
  }

  String _currentUpdateNotificationKey() {
    final parts = <String>[];

    // Orion component
    var orionCurrent = orionProvider.currentVersion.trim();
    var orionLatest = orionProvider.latestVersion.trim();
    var orionRelease = orionProvider.release.trim();
    final persistedOrionCurrent =
        _config.getString('orion.current', category: 'updates').trim();
    final persistedOrionLatest =
        _config.getString('orion.latest', category: 'updates').trim();
    final persistedOrionRelease =
        _config.getString('orion.release', category: 'updates').trim();

    final shouldIncludeOrion = orionProvider.isUpdateAvailable ||
        (orionCurrent.isEmpty &&
            orionLatest.isEmpty &&
            persistedOrionCurrent.isNotEmpty &&
            persistedOrionLatest.isNotEmpty);

    if (shouldIncludeOrion) {
      if (orionCurrent.isEmpty) orionCurrent = persistedOrionCurrent;
      if (orionLatest.isEmpty) orionLatest = persistedOrionLatest;
      if (orionRelease.isEmpty) orionRelease = persistedOrionRelease;
      parts.add(
          'orion:${orionRelease.isNotEmpty ? orionRelease : '-'}:${orionCurrent.isNotEmpty ? orionCurrent : '-'}>${orionLatest.isNotEmpty ? orionLatest : '-'}');
    }

    // Athena component
    var athenaCurrent = athenaProvider.currentVersion.trim();
    var athenaLatest = athenaProvider.latestVersion.trim();
    var athenaChannel = athenaProvider.channel.trim();
    final persistedAthenaCurrent =
        _config.getString('athena.current', category: 'updates').trim();
    final persistedAthenaLatest =
        _config.getString('athena.latest', category: 'updates').trim();
    final persistedAthenaChannel =
        _config.getString('athena.channel', category: 'updates').trim();

    final shouldIncludeAthena = athenaProvider.shouldNotify ||
        (athenaCurrent.isEmpty &&
            athenaLatest.isEmpty &&
            persistedAthenaCurrent.isNotEmpty &&
            persistedAthenaLatest.isNotEmpty);

    if (shouldIncludeAthena) {
      if (athenaCurrent.isEmpty) athenaCurrent = persistedAthenaCurrent;
      if (athenaLatest.isEmpty) athenaLatest = persistedAthenaLatest;
      if (athenaChannel.isEmpty) athenaChannel = persistedAthenaChannel;
      parts.add(
          'athena:${athenaChannel.isNotEmpty ? athenaChannel : '-'}:${athenaCurrent.isNotEmpty ? athenaCurrent : '-'}>${athenaLatest.isNotEmpty ? athenaLatest : '-'}');
    }

    if (parts.isEmpty) return 'none';
    return parts.join('|');
  }

  /// Clear pending update flags and suppress notifications.
  /// Call this before starting an update to ensure stale notifications
  /// don't resurface if the app restarts during the update process.
  ///
  /// [components] specifies which component(s) to clear. Defaults to all.
  void clearPendingUpdates(
      {Set<UpdateComponent> components = const {
        UpdateComponent.orion,
        UpdateComponent.athena
      }}) {
    suppressNotifications = true;

    if (components.contains(UpdateComponent.orion)) {
      _config.setString('orion.current', '', category: 'updates');
      _config.setString('orion.latest', '', category: 'updates');
      _config.setString('orion.release', '', category: 'updates');
    }

    if (components.contains(UpdateComponent.athena)) {
      _config.setString('athena.current', '', category: 'updates');
      _config.setString('athena.latest', '', category: 'updates');
      _config.setString('athena.channel', '', category: 'updates');
    }

    // Only clear 'available' flag if both are being cleared
    if (components.contains(UpdateComponent.orion) &&
        components.contains(UpdateComponent.athena)) {
      _config.setFlag('available', false, category: 'updates');
      _config.setString('remindLater', '', category: 'updates');
      _config.setString(_remindLaterKeyField, '', category: 'updates');
    }

    notifyListeners();
  }

  void setIgnoreUpdates(bool value) {
    _config.setFlag('ignoreUpdates', value, category: 'updates');
    notifyListeners();
  }

  bool get isUpdateIgnored {
    return _config.getFlag('ignoreUpdates', category: 'updates');
  }

  /// Returns true if an update is available, regardless of whether the user
  /// has snoozed notifications.
  bool get isUpdateAvailable {
    // Check live providers first (shouldNotify excludes master branch)
    if (orionProvider.isUpdateAvailable || athenaProvider.shouldNotify) {
      return true;
    }
    // Fallback to config (useful for startup before check completes)
    return _config.getFlag('available', category: 'updates');
  }

  /// Returns true if an update is available AND the user has not snoozed
  /// notifications (or the snooze period has expired).
  /// This respects the [suppressNotifications] flag.
  bool get shouldShowNotification {
    if (_suppressNotifications) return false;
    if (_promptAcknowledgedThisSession) return false;
    return hasPendingUpdateNotification;
  }

  /// Returns true if an update is available AND the user has not snoozed
  /// notifications, ignoring the [suppressNotifications] flag.
  bool get hasPendingUpdateNotification {
    if (!isUpdateAvailable) return false;

    if (_config.getFlag('ignoreUpdates', category: 'updates')) {
      return false;
    }

    final remindStr = _config.getString('remindLater', category: 'updates');
    if (remindStr.isNotEmpty) {
      final remindTime = DateTime.tryParse(remindStr);
      if (remindTime != null && DateTime.now().isBefore(remindTime)) {
        final remindKey =
            _config.getString(_remindLaterKeyField, category: 'updates');
        // If the key matches, this is the same update bundle and snooze applies.
        if (remindKey == _currentUpdateNotificationKey()) {
          return false;
        }
      }
    }
    return true;
  }

  String get updateMessage {
    if (orionProvider.isUpdateAvailable && athenaProvider.shouldNotify) {
      return 'Updates Available';
    } else if (orionProvider.isUpdateAvailable) {
      return 'Orion Update Available';
    } else if (athenaProvider.shouldNotify) {
      return 'AthenaOS Update Available';
    }
    // If we only have the config flag but not the specific provider details yet,
    // return a generic message.
    if (isUpdateAvailable) {
      return 'Update Available';
    }
    return '';
  }

  /// Start an Orion update directly with a confirmation dialog, then perform
  /// the update. Call this from the startup overlay instead of navigating to
  /// the full UpdateScreen.
  Future<void> startOrionUpdate(BuildContext context) async {
    final shouldUpdate = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => GlassAlertDialog(
            title: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.download(),
                  color: Theme.of(ctx).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  FlutterI18n.translate(ctx, 'update.updateOrion'),
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
              ],
            ),
            content: Text(FlutterI18n.translate(ctx, 'update.updateOrionMsg')),
            actions: [
              GlassButton(
                tint: GlassButtonTint.negative,
                onPressed: () => Navigator.of(ctx).pop(false),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'common.dismiss')),
              ),
              GlassButton(
                tint: GlassButtonTint.positive,
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'update.updateNow')),
              ),
            ],
          ),
        ) ??
        false;

    if (shouldUpdate && context.mounted) {
      clearPendingUpdates(components: {UpdateComponent.orion});
      await orionProvider.performUpdate(context, orionProvider.assetUrl);
    }
  }

  /// Start an AthenaOS update directly with the appropriate confirmation
  /// flow, then trigger the backend update. Call this from the startup overlay
  /// instead of navigating to the full UpdateScreen.
  ///
  /// When both Orion and AthenaOS updates are available, prefer this method
  /// since an AthenaOS update also updates Orion.
  Future<void> startAthenaUpdate(BuildContext context) async {
    final isMasterBranch = athenaProvider.channel == 'master';

    bool confirmed = false;

    if (isMasterBranch) {
      // Triple confirmation for development firmware
      if (!await _showAthenaDevWarning(context)) {
        await _offerAthenaResetChannel(context);
        return;
      }
      if (!await _showAthenaSecondWarning(context)) {
        await _offerAthenaResetChannel(context);
        return;
      }
      if (!await _showAthenaFinalWarning(context)) {
        await _offerAthenaResetChannel(context);
        return;
      }
      confirmed = true;
    } else {
      // Regular confirmation for stable/beta channels
      confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dctx) => GlassAlertDialog(
              title: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIcons.download(),
                    color: Theme.of(context).colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    FlutterI18n.translate(context, 'update.updateAthena'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              content: Text(
                  FlutterI18n.translate(context, 'update.updateAthenaMsg')),
              actions: [
                GlassButton(
                  tint: GlassButtonTint.negative,
                  onPressed: () => Navigator.of(dctx).pop(false),
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                  child: Text(FlutterI18n.translate(context, 'common.dismiss')),
                ),
                GlassButton(
                  tint: GlassButtonTint.positive,
                  onPressed: () => Navigator.of(dctx).pop(true),
                  style:
                      ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                  child:
                      Text(FlutterI18n.translate(context, 'update.updateNow')),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (!confirmed) return;
    if (!context.mounted) return;

    // Clear pending updates (both Orion and Athena, as AthenaOS may update both)
    clearPendingUpdates(
        components: {UpdateComponent.orion, UpdateComponent.athena});

    // Pause polling to prevent connection error dialogs during update/reboot
    final statusProvider = Provider.of<StatusProvider>(context, listen: false);
    statusProvider.pausePolling();

    // Create notifiers for the progress overlay (indeterminate progress)
    final progressNotifier = ValueNotifier<double>(-1.0); // -1 = indeterminate
    final messageNotifier = ValueNotifier<String>(
        FlutterI18n.translate(context, 'update.triggeringAthena'));

    // Navigate to the update progress overlay
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UpdateProgressOverlay(
          progress: progressNotifier,
          message: messageNotifier,
          icon: PhosphorIcons.warningDiamond(),
        ),
      ),
    );

    // Trigger the update in the background
    // The system will reboot, so we don't need to dismiss the overlay
    try {
      final backend = BackendService();
      await backend.updateBackend();
      messageNotifier.value =
          FlutterI18n.translate(context, 'update.athenaUpdateInitiated');
    } catch (e) {
      messageNotifier.value =
          FlutterI18n.translate(context, 'update.athenaUpdateReboot');
    }
  }

  // -- Private helpers for AthenaOS master-branch confirmation dialogs --

  Future<bool> _showAthenaDevWarning(BuildContext ctx) async {
    return await showDialog<bool>(
          context: ctx,
          barrierDismissible: false,
          barrierColor: Colors.red.withValues(alpha: 0.15),
          builder: (dctx) => GlassAlertDialog(
            title: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.warning(),
                  color: Colors.redAccent,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    FlutterI18n.translate(ctx, 'update.devFirmware'),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              FlutterI18n.translate(ctx, 'update.devWarningDetailed'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            actions: [
              GlassButton(
                tint: GlassButtonTint.negative,
                onPressed: () => Navigator.of(dctx).pop(true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'update.iAccept')),
              ),
              GlassButton(
                tint: GlassButtonTint.positive,
                onPressed: () => Navigator.of(dctx).pop(false),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'common.cancel')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showAthenaSecondWarning(BuildContext ctx) async {
    return await showDialog<bool>(
          context: ctx,
          barrierDismissible: false,
          barrierColor: Colors.red.withValues(alpha: 0.15),
          builder: (dctx) => GlassAlertDialog(
            title: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.warning(),
                  color: Colors.redAccent,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  FlutterI18n.translate(ctx, 'update.confirmUpdate'),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              FlutterI18n.translate(ctx, 'update.confirmDevMsg'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            actions: [
              GlassButton(
                tint: GlassButtonTint.positive,
                onPressed: () => Navigator.of(dctx).pop(false),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'common.cancel')),
              ),
              GlassButton(
                tint: GlassButtonTint.negative,
                onPressed: () => Navigator.of(dctx).pop(true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'common.continue_')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showAthenaFinalWarning(BuildContext ctx) async {
    return await showDialog<bool>(
          context: ctx,
          barrierDismissible: false,
          barrierColor: Colors.red.withValues(alpha: 0.15),
          builder: (dctx) => GlassAlertDialog(
            title: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.warning(),
                  color: Colors.redAccent,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  FlutterI18n.translate(ctx, 'update.finalWarning'),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              FlutterI18n.translate(ctx, 'update.finalWarningMsgDetailed'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            actions: [
              GlassButton(
                tint: GlassButtonTint.negative,
                onPressed: () => Navigator.of(dctx).pop(true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'update.updateNow')),
              ),
              GlassButton(
                tint: GlassButtonTint.positive,
                onPressed: () => Navigator.of(dctx).pop(false),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'common.cancel')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _offerAthenaResetChannel(BuildContext ctx) async {
    final resetConfirmed = await showDialog<bool>(
          context: ctx,
          barrierDismissible: false,
          builder: (dctx) => GlassAlertDialog(
            title: Row(
              children: [
                PhosphorIcon(
                  PhosphorIcons.arrowClockwise(),
                  color: Colors.greenAccent,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    FlutterI18n.translate(ctx, 'update.resetChannel'),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              FlutterI18n.translate(ctx, 'update.resetChannelMsg'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            actions: [
              GlassButton(
                tint: GlassButtonTint.neutral,
                onPressed: () => Navigator.of(dctx).pop(false),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'update.keepDev')),
              ),
              GlassButton(
                tint: GlassButtonTint.positive,
                onPressed: () => Navigator.of(dctx).pop(true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
                child: Text(FlutterI18n.translate(ctx, 'update.resetToStable')),
              ),
            ],
          ),
        ) ??
        false;

    if (resetConfirmed) {
      try {
        final backend = BackendService();
        await backend
            .manualCommand('[[Exec echo "stable" > /home/pi/channel]]');
        // Refresh AthenaOS update status to reflect the new channel
        if (ctx.mounted) {
          final athenaProv =
              Provider.of<AthenaUpdateProvider>(ctx, listen: false);
          await athenaProv.checkForUpdates();
        }
      } catch (_) {
        // Channel reset failed silently; the user can try again
      }
    }
  }
}
