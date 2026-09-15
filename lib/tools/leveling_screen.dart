/*
* Orion - Leveling Screen
* Copyright (C) 2026 Open Resin Alliance
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
import 'package:orion/backend_service/backend_registry.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/tools/athena/c3d_athena2_wizard.dart';
import 'package:orion/tools/athena/leveling_configs.dart';
import 'package:orion/tools/athena/leveling_settings_screen.dart';
import 'package:orion/tools/athena/verify_leveling_screen.dart'
    show VerifyLevelingScreen, isPrinterLeveled;
import 'package:orion/tools/manual_leveling_screen.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class LevelingScreen extends StatelessWidget {
  const LevelingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final config = OrionConfig();
    final levelingConfig = getLevelingConfigForMachine(
      config.getMachineModelName(),
    );
    final backend = BackendService();
    // Assisted leveling is available for Athena2-class machines that have a
    // force sensor.  Older vendor.cfg files may not include the `levelingMode`
    // key; when the machine model already matched the Athena2 prefix we treat
    // a missing/empty key as "athena2".  An explicit "manual" still opts out.
    final levelingMode = config.getLevelingMode();
    // Explicit "athena2" in vendor.cfg is a deliberate opt-in — skip
    // the hasForceSensor gate (older hardware may not have the flag).
    final explicitAthena2 = levelingMode == 'athena2';
    final assistedEnabled = levelingConfig != null &&
        (explicitAthena2 || config.hasForceSensor()) &&
        (explicitAthena2 || levelingMode.isEmpty) &&
        backend.supportsCapability(BackendCapabilities.supportsForceLeveling);

    return SafeArea(
      child: Padding(
        padding: OrionSpacing.screenPaddingWithBottomNav,
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildLargeButton(
                      context,
                      icon: PhosphorIcons.magicWand(),
                      label:
                          FlutterI18n.translate(context, 'leveling.assisted'),
                      description: FlutterI18n.translate(
                          context, 'leveling.assistedDesc'),
                      enabled: assistedEnabled,
                      tint: GlassButtonTint.positive,
                      badgeLabel: assistedEnabled
                          ? null
                          : FlutterI18n.translate(
                              context, 'leveling.notAvailable'),
                      onPressed: assistedEnabled
                          ? () => Navigator.of(context).push(
                                _buildOverlayRoute(
                                  Athena2LevelingWizard(
                                      config: levelingConfig),
                                ),
                              )
                          : null,
                    ),
                  ),
                  const SizedBox(width: OrionSpacing.controlGap),
                  Expanded(
                    child: _buildLargeButton(
                      context,
                      icon: PhosphorIcons.checkCircle(),
                      label:
                          FlutterI18n.translate(context, 'leveling.verify'),
                      description: FlutterI18n.translate(
                          context, 'leveling.verifyDesc'),
                      enabled: isPrinterLeveled(),
                      tint: GlassButtonTint.neutral,
                      onPressed: () => Navigator.of(context).push(
                        _buildOverlayRoute(const VerifyLevelingScreen()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: OrionSpacing.controlGap),
            Row(
              children: [
                Expanded(
                  child: _buildManualButton(context, assistedEnabled),
                ),
                const SizedBox(width: OrionSpacing.controlGap),
                Expanded(child: _buildSettingsButton(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Large self-explaining button matching the home screen dashboard style.
  Widget _buildLargeButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? description,
    bool enabled = true,
    String? badgeLabel,
    GlassButtonTint tint = GlassButtonTint.none,
    VoidCallback? onPressed,
  }) {
    final theme = Theme.of(context).copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.resolveWith<OutlinedBorder?>(
            (Set<WidgetState> states) {
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              );
            },
          ),
          minimumSize: WidgetStateProperty.resolveWith<Size?>(
            (Set<WidgetState> states) {
              return const Size(double.infinity, double.infinity);
            },
          ),
        ),
      ),
    );

    return GlassButton(
      tint: enabled ? tint : GlassButtonTint.none,
      style: theme.elevatedButtonTheme.style,
      onPressed: enabled ? onPressed : null,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(icon, size: 48),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(fontSize: 22),
                  textAlign: TextAlign.center,
                ),
                if (description != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.25,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (badgeLabel != null)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.15),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildManualButton(BuildContext context, bool assistedEnabled) {
    return GlassButton(
      tint: GlassButtonTint.negative,
      onPressed: () async {
        if (assistedEnabled) {
          final proceed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => GlassAlertDialog(
              title: Row(
                children: [
                  PhosphorIcon(PhosphorIcons.warning(),
                      color: Colors.orangeAccent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      FlutterI18n.translate(context, 'leveling.manual'),
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                FlutterI18n.translate(
                    context, 'leveling.manualAdvancedWarning'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w500),
              ),
              actions: [
                GlassButton(
                  tint: GlassButtonTint.neutral,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(false),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 55),
                  ),
                  child: Text(FlutterI18n.translate(
                      context, 'leveling.cancel')),
                ),
                GlassButton(
                  tint: GlassButtonTint.warn,
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 55),
                  ),
                  child: Text(FlutterI18n.translate(
                      context, 'leveling.manualMode')),
                ),
              ],
            ),
          );
          if (proceed != true) return;
        }
        if (!context.mounted) return;
        Navigator.of(context).push(
          _buildOverlayRoute(const ManualLevelingScreen()),
        );
      },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(PhosphorIconsFill.wrench, size: 22),
          const SizedBox(width: 10),
          Text(
            FlutterI18n.translate(context, 'leveling.manual'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return GlassButton(
      tint: GlassButtonTint.neutral,
      onPressed: () {
        Navigator.of(context).push(
          _buildOverlayRoute(const LevelingSettingsScreen()),
        );
      },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(PhosphorIconsFill.gear, size: 22),
          const SizedBox(width: 10),
          Text(
            FlutterI18n.translate(context, 'leveling.settings'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

PageRouteBuilder<T> _buildOverlayRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => child,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
