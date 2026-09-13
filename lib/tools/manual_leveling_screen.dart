/*
* Orion - Manual Leveling Screen
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

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:logging/logging.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:provider/provider.dart';
import 'package:orion/backend_service/providers/config_provider.dart';
import 'package:orion/backend_service/providers/manual_provider.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/error_handling/error_dialog.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/safe_home.dart';
import 'package:orion/util/providers/theme_provider.dart';

class ManualLevelingScreen extends StatefulWidget {
  const ManualLevelingScreen({super.key});

  @override
  ManualLevelingScreenState createState() => ManualLevelingScreenState();
}

class ManualLevelingScreenState extends State<ManualLevelingScreen> {
  final _logger = Logger('ManualLevelingScreen');
  // Use ConfigProvider for config data; ManualProvider for actions

  double maxZ = 0.0;
  double step = 0.1;
  double currentZ = 0.0;

  bool _apiErrorState = false;
  Map<String, dynamic>? status;

  // Track an optimistic offset value so UI shows immediate feedback when
  // the user sets the Z offset. Cleared when backend confirms the value.
  double? _optimisticOffset;

  void _setOptimisticOffset(double value) {
    setState(() => _optimisticOffset = value);
  }

  void _clearOptimisticOffset() {
    if (_optimisticOffset != null) setState(() => _optimisticOffset = null);
  }

  bool _offsetsMatch(double? optimistic, double? backend, {double tol = 0.01}) {
    if (optimistic == null || backend == null) return true;
    return (optimistic - backend).abs() < tol;
  }

  // Safe helper to show error dialogs without using a stale BuildContext.
  // If a BuildContext is provided (usually from a builder), verify the
  // Element is still mounted before showing the dialog. If omitted, use
  // the State's context guarded by `mounted`.
  void _safeShowError(String message, [BuildContext? maybeCtx]) {
    if (maybeCtx != null) {
      if (maybeCtx is Element) {
        if (!maybeCtx.mounted) return;
      }
      showErrorDialog(maybeCtx, message);
    } else {
      if (!context.mounted) return;
      showErrorDialog(context, message);
    }
  }

  Future<bool> _showConfirmationDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required IconData icon,
    required Color accentColor,
    required GlassButtonTint confirmTint,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => GlassAlertDialog(
        title: Row(
          children: [
            PhosphorIcon(
              icon,
              color: accentColor,
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        actions: [
          GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 65),
            ),
            child:
                Text(FlutterI18n.translate(context, 'manualLeveling.cancel')),
          ),
          GlassButton(
            tint: confirmTint,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 65),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _confirmAndResetZOffset() async {
    final confirmed = await _showConfirmationDialog(
      title: FlutterI18n.translate(context, 'manualLeveling.resetOffset'),
      message: FlutterI18n.translate(context, 'manualLeveling.resetConfirm'),
      confirmLabel:
          FlutterI18n.translate(context, 'manualLeveling.resetOffset'),
      icon: PhosphorIcons.warning(),
      accentColor: Colors.redAccent,
      confirmTint: GlassButtonTint.negative,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final manual = Provider.of<ManualProvider>(context, listen: false);
    _logger.info('Reset Z offset button pressed');
    _setOptimisticOffset(0.0);
    final nav = Navigator.of(context);

    final ok = await manual.resetZOffset();
    if (!ok) {
      final navCtx = nav.context;
      if (!navCtx.mounted) return;
      showErrorDialog(navCtx, 'GOLDEN-APE');
    }
    if (!mounted) return;

    final statusProvider = Provider.of<StatusProvider>(context, listen: false);
    await statusProvider.refreshKinematicStatus();
    final backendOffset = statusProvider.kinematicStatus?.offset;
    if (_offsetsMatch(_optimisticOffset, backendOffset)) {
      _clearOptimisticOffset();
    }
  }

  Future<void> _confirmAndSetCurrentAsZZero(double currentZ) async {
    final confirmed = await _showConfirmationDialog(
      title: FlutterI18n.translate(context, 'manualLeveling.setZZero'),
      message: FlutterI18n.translate(context, 'manualLeveling.setZConfirm',
          translationParams: {'z': currentZ.toStringAsFixed(2)}),
      confirmLabel: FlutterI18n.translate(context, 'manualLeveling.setOffset'),
      icon: PhosphorIcons.warning(),
      accentColor: Colors.orangeAccent,
      confirmTint: GlassButtonTint.warn,
    );
    if (!confirmed) return;
    if (!mounted) return;

    final manual = Provider.of<ManualProvider>(context, listen: false);
    _logger.info('Set Z offset button pressed (Z=$currentZ)');
    _setOptimisticOffset(currentZ);
    final nav = Navigator.of(context);

    final ok = await manual.setZOffset(currentZ);
    if (!ok) {
      final navCtx = nav.context;
      if (!navCtx.mounted) return;
      showErrorDialog(navCtx, 'GOLDEN-APE');
    }
    if (!mounted) return;

    final statusProvider = Provider.of<StatusProvider>(context, listen: false);
    await statusProvider.refreshKinematicStatus();
    final backendOffset = statusProvider.kinematicStatus?.offset;
    if (_offsetsMatch(_optimisticOffset, backendOffset)) {
      _clearOptimisticOffset();
    }
  }

  Future<void> moveZ(double distance) async {
    try {
      _logger.info('Moving Z by $distance');
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);
      final curZ = statusProvider.status?.physicalState.z ?? currentZ;

      final newZ = (curZ + distance).clamp(0.0, maxZ).toDouble();
      final manual = Provider.of<ManualProvider>(context, listen: false);
      final ok = await manual.move(newZ);
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _apiErrorState = true;
        });
        _safeShowError(
            FlutterI18n.translate(context, 'manualLeveling.failedMoveZ'));
      }
    } catch (e) {
      _logger.severe('Failed to move Z: $e');
      if (!mounted) return;
      setState(() {
        _apiErrorState = true;
      });
      _safeShowError(
          FlutterI18n.translate(context, 'manualLeveling.failedMoveZ'));
    }
  }

  void getMaxZ() async {
    try {
      final provider = Provider.of<ConfigProvider>(context, listen: false);
      if (provider.config != null) {
        setState(() {
          maxZ = provider.config?.machine?['printer']?['max_z'] ?? maxZ;
        });
      } else {
        try {
          await provider.refresh();
          if (!mounted) return;
          if (provider.config != null) {
            // Safe to update state here because we're already async and not
            // in the middle of a build.
            setState(() {
              maxZ = provider.config?.machine?['printer']?['max_z'] ?? maxZ;
            });
          }
        } catch (e) {
          // Provider rethrows on error; surface a dialog from the screen
          // instead of letting the provider call notifyListeners during
          // widget build.
          if (!mounted) return;
          setState(() {
            _apiErrorState = true;
          });
          _safeShowError('BLUE-BANANA');
          _logger.severe('Failed to refresh config: $e');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _apiErrorState = true;
      });
      _safeShowError('BLUE-BANANA');
      _logger.severe('Failed to get max Z: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Defer config refresh work until after the first frame so that any
    // notifyListeners() from providers won't run during the widget build
    // phase and cause 'setState() or markNeedsBuild() called during build'.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      getMaxZ();
      // Fetch initial kinematic status for the status bar
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);
      await statusProvider.refreshKinematicStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isGlass =
        Provider.of<ThemeProvider>(context, listen: false).isGlassTheme;
    final accent = Theme.of(context).colorScheme.primary;

    return GlassApp(
      child: Scaffold(
        backgroundColor: isGlass
            ? Colors.transparent
            : Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: isGlass
              ? Colors.transparent
              : Theme.of(context).colorScheme.surface,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIconsFill.wrench,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text(
                FlutterI18n.translate(context, 'manualLeveling.title'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: OrionSpacing.screenPaddingWithBottomNav,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(child: buildMoveButtons(context)),
                                  const SizedBox(width: 30),
                                  Expanded(child: buildChoiceCards(context)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 30),
                      Expanded(child: buildControlButtons(context)),
                    ],
                  ),
                ),
                const SizedBox(height: 85),
              ],
            ),
          ),
        ),
        floatingActionButton: Padding(
          padding: OrionSpacing.screenPaddingNoTop,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate widths to match the body columns exactly.
              // Body Layout:
              // LeftCol = (W - 30) / 2
              // MoveCol = (LeftCol - 30) / 2 = (W - 90) / 4
              // ChoiceCol = MoveCol
              // ControlCol = LeftCol = (W - 30) / 2
              //
              // Target Back Width = MoveCol
              // Target Status Width = ChoiceCol + 30 + ControlCol
              //                     = (W - 90)/4 + 30 + (W - 30)/2
              //                     = (3W - 30) / 4
              final w = constraints.maxWidth;
              final backWidth = (w - 90) / 4;
              final statusWidth = (3 * w - 30) / 4;

              return Row(
                children: [
                  SizedBox(
                    width: backWidth,
                    child: GlassFloatingActionButton.extended(
                      heroTag: 'manual-back',
                      tint: GlassButtonTint.neutral,
                      icon: Icon(PhosphorIcons.arrowLeft()),
                      iconAfterLabel: false,
                      scale: 1.3,
                      label:
                          FlutterI18n.translate(context, 'manualLeveling.back'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 30),
                  SizedBox(
                    width: statusWidth,
                    child: _buildStatusCard(context),
                  ),
                ],
              );
            },
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget buildChoiceCards(BuildContext context) {
    final values = [0.01, 0.1, 1.0, 5.0];
    return Column(
      children: [
        for (int index = 0; index < values.length; index++) ...[
          Expanded(
            child: Builder(builder: (context) {
              final value = values[index];
              final label = value < 1.0
                  ? '${(value * 1000).round()} µm'
                  : '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)} mm';

              return GlassChoiceChip(
                label: SizedBox(
                  width: double.infinity,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                selected: step == value,
                onSelected: _apiErrorState
                    ? null
                    : (selected) {
                        if (selected) {
                          setState(() {
                            step = value;
                          });
                        }
                      },
              );
            }),
          ),
          if (index < values.length - 1)
            const SizedBox(height: OrionSpacing.controlGap),
        ],
      ],
    );
  }

  Widget buildMoveButtons(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: Consumer<ManualProvider>(
            builder: (context, manual, _) {
              return GlassButton(
                onPressed: _apiErrorState || manual.busy
                    ? null
                    : () async {
                        final manual =
                            Provider.of<ManualProvider>(context, listen: false);
                        await manual.moveDelta(step);
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, double.infinity),
                ),
                child: PhosphorIcon(PhosphorIcons.arrowUp(), size: 50),
              );
            },
          ),
        ),
        const SizedBox(height: 30),
        Expanded(
          child: Consumer<ManualProvider>(
            builder: (context, manual, _) {
              return GlassButton(
                onPressed: _apiErrorState || manual.busy
                    ? null
                    : () async {
                        final manual =
                            Provider.of<ManualProvider>(context, listen: false);
                        await manual.moveDelta(-step);
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, double.infinity),
                ),
                child: PhosphorIcon(PhosphorIcons.arrowDown(), size: 50),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return Consumer<StatusProvider>(
      builder: (context, statusProvider, _) {
        // Prefer the regular status 'physicalState.z' (currentHeight) for
        // the displayed Z value because it's the most reliable source for
        // the device-reported current height. Fall back to kinematic
        // position if physicalState is unavailable.
        final backendZ = statusProvider.status?.physicalState.z;
        final z = backendZ ?? statusProvider.kinematicStatus?.position ?? 0.0;
        final backendOffset = statusProvider.kinematicStatus?.offset;
        final offset = _optimisticOffset ?? backendOffset ?? 0.0;
        final isHomed = statusProvider.kinematicStatus?.homed ?? false;

        final offsetMismatch = !_offsetsMatch(_optimisticOffset, backendOffset);
        final mismatchColor = Colors.red.shade200;
        final normalColor =
            Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
        final offsetColor = offsetMismatch ? mismatchColor : normalColor;

        return GlassCard(
          child: Padding(
            // Match FAB padding (16*1.3 ≈ 21, 12*1.3 ≈ 16)
            padding:
                const EdgeInsets.symmetric(horizontal: 21.0, vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Z Position
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(PhosphorIcons.ruler(),
                        size: 24, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Text(
                      '${z.toStringAsFixed(2)} mm',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: normalColor),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
                // Offset
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(PhosphorIcons.arrowsVertical(),
                        size: 24,
                        color: offsetMismatch
                            ? mismatchColor.withValues(alpha: 0.7)
                            : Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Text(
                      '${offset.toStringAsFixed(2)} mm',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: offsetColor),
                    ),
                  ],
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
                // Homed Status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      isHomed
                          ? PhosphorIcons.checkCircle()
                          : PhosphorIcons.warning(),
                      size: 24,
                      color: isHomed ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isHomed
                          ? FlutterI18n.translate(
                              context, 'manualLeveling.homed')
                          : FlutterI18n.translate(
                              context, 'manualLeveling.notHomed'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color:
                            isHomed ? Colors.greenAccent : Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildControlButtons(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        // Row 1: Home | Floor
        Expanded(
          child: Consumer<ManualProvider>(
            builder: (context, manual, _) {
              return FutureBuilder<bool>(
                future: manual.canMoveToTop(),
                builder: (ctx, snap) {
                  final supportsTop = snap.data == true;
                  final floorEnabled = !_apiErrorState &&
                      !manual.busy &&
                      (maxZ > 0.0 || supportsTop);

                  return Row(
                    children: [
                      // Home button
                      Expanded(
                        child: GlassButton(
                          onPressed: _apiErrorState || manual.busy
                              ? null
                              : () async {
                                  _logger.info('Moving to home position');
                                  final ok = await safeHome(context);
                                  if (!ok) {
                                    if (!mounted) return;
                                    _safeShowError('GOLDEN-APE');
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            minimumSize:
                                const Size(double.infinity, double.infinity),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 12),
                              PhosphorIcon(PhosphorIconsFill.house, size: 26),
                              Expanded(
                                child: AutoSizeText(
                                  FlutterI18n.translate(context, 'moveZ.home'),
                                  style: TextStyle(fontSize: 24),
                                  minFontSize: 16,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Floor button
                      Expanded(
                        child: GlassButton(
                          onPressed: !floorEnabled
                              ? null
                              : () async {
                                  try {
                                    final cfg = OrionConfig();
                                    if (cfg.isHomePositionUp()) {
                                      _logger.info(
                                          'Moving to Floor via moveToFloor()');
                                      final ok = await manual.moveToFloor();
                                      if (!ok) {
                                        if (!mounted) return;
                                        _safeShowError('GOLDEN-APE');
                                      }
                                    } else if (supportsTop) {
                                      _logger.info(
                                          'Moving to device Top via moveToTop()');
                                      final ok = await manual.moveToTop();
                                      if (!ok) {
                                        if (!mounted) return;
                                        _safeShowError('GOLDEN-APE');
                                      }
                                    } else {
                                      _logger
                                          .info('Moving to ZMAX (maxZ=$maxZ)');
                                      final ok = await manual.move(maxZ);
                                      if (!ok) {
                                        if (!mounted) return;
                                        _safeShowError('GOLDEN-APE');
                                      }
                                    }
                                    if (!context.mounted) return;
                                    final statusProvider =
                                        Provider.of<StatusProvider>(context,
                                            listen: false);
                                    await statusProvider
                                        .refreshKinematicStatus();
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    _safeShowError('GOLDEN-APE');
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            minimumSize:
                                const Size(double.infinity, double.infinity),
                          ),
                          child: Builder(builder: (ctx) {
                            final cfg = OrionConfig();
                            final icon = cfg.isHomePositionUp()
                                ? PhosphorIcon(PhosphorIcons.arrowDown(),
                                    size: 26)
                                : PhosphorIcon(PhosphorIcons.arrowUp(),
                                    size: 26);
                            return Row(
                              children: [
                                const SizedBox(width: 12),
                                icon,
                                Expanded(
                                  child: AutoSizeText(
                                    cfg.isHomePositionUp()
                                        ? FlutterI18n.translate(
                                            context, 'moveZ.floor')
                                        : FlutterI18n.translate(
                                            context, 'moveZ.top'),
                                    style: const TextStyle(fontSize: 24),
                                    minFontSize: 16,
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 25),
        // Row 2: Reset | Z = 0
        Expanded(
          child: Consumer2<ManualProvider, StatusProvider>(
            builder: (context, manual, status, _) {
              final currentZ = status.status?.physicalState.z ??
                  status.kinematicStatus?.position ??
                  0.0;
              final canRun = !_apiErrorState && !manual.busy;
              return Row(
                children: [
                  // Reset button
                  Expanded(
                    child: GlassButton(
                      onPressed: canRun ? _confirmAndResetZOffset : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize:
                            const Size(double.infinity, double.infinity),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          PhosphorIcon(PhosphorIcons.arrowCounterClockwise(),
                              size: 26),
                          Expanded(
                            child: AutoSizeText(
                              FlutterI18n.translate(
                                  context, 'manualLeveling.resetOffset'),
                              style: TextStyle(fontSize: 24),
                              minFontSize: 16,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Z = 0 button (sets current Z position as the offset)
                  Expanded(
                    child: GlassButton(
                      onPressed: canRun
                          ? () => _confirmAndSetCurrentAsZZero(currentZ)
                          : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize:
                            const Size(double.infinity, double.infinity),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          PhosphorIcon(PhosphorIcons.crosshair(), size: 26),
                          Expanded(
                            child: AutoSizeText(
                              FlutterI18n.translate(
                                  context, 'manualLeveling.setZZero'),
                              style: TextStyle(fontSize: 24),
                              minFontSize: 16,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 25),
        // Row 3: Emergency Stop
        Expanded(
          child: Consumer<ManualProvider>(
            builder: (context, manual, _) {
              return GlassButton(
                onPressed: _apiErrorState || manual.busy
                    ? null
                    : () async {
                        _logger.severe('EMERGENCY STOP');
                        final ok = await manual.emergencyStop();
                        if (!ok) {
                          if (!mounted) return;
                          _safeShowError('CRITICAL');
                        }
                        if (!context.mounted) return;
                        final statusProvider =
                            Provider.of<StatusProvider>(context, listen: false);
                        statusProvider.clearHomedStatus();
                        await statusProvider.refreshKinematicStatus();
                      },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, double.infinity),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    PhosphorIcon(PhosphorIconsFill.stop,
                        size: 30,
                        color: _apiErrorState
                            ? null
                            : Theme.of(context).colorScheme.error),
                    Expanded(
                      child: AutoSizeText(
                        FlutterI18n.translate(context, 'moveZ.emergencyStop'),
                        style: TextStyle(
                          fontSize: 24,
                          color: _apiErrorState
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                        maxLines: 1,
                        minFontSize: 20,
                        overflowReplacement: Padding(
                          padding: EdgeInsets.only(right: 20.0),
                          child: Center(
                            child: Text(
                              FlutterI18n.translate(context, 'moveZ.stop'),
                              style: TextStyle(
                                fontSize: 24,
                                color: _apiErrorState
                                    ? null
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
