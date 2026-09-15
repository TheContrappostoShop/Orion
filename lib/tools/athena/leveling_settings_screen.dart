/*
* Orion - Leveling Settings Screen
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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:orion/backend_service/providers/manual_provider.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/error_handling/error_dialog.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/tools/athena/leveling_configs.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/util/widgets/system_status_widget.dart';
import 'package:orion/widgets/orion_app_bar.dart';
import 'package:orion/widgets/zoom_value_editor_dialog.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

/// Leveling settings — currently the applied Z offset, editable via a
/// slider that is limited to ±20% of the current value so it can only be
/// nudged, not wildly changed.
class LevelingSettingsScreen extends StatefulWidget {
  const LevelingSettingsScreen({super.key});

  @override
  State<LevelingSettingsScreen> createState() => _LevelingSettingsScreenState();
}

class _LevelingSettingsScreenState extends State<LevelingSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch the current kinematic status so the Z offset is up to date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<StatusProvider>(context, listen: false)
            .refreshKinematicStatus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isGlass =
        Provider.of<ThemeProvider>(context, listen: false).isGlassTheme;

    return GlassApp(
      child: Scaffold(
        backgroundColor: isGlass
            ? Colors.transparent
            : Theme.of(context).colorScheme.surface,
        appBar: OrionAppBar(
          title: Text(
            FlutterI18n.translate(context, 'leveling.settingsTitle'),
          ),
          toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight,
          actions: const [SystemStatusWidget()],
        ),
        body: SafeArea(
          child: Padding(
            padding: OrionSpacing.screenPaddingWithBottomNav,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildZOffsetSection(context),
                  const SizedBox(height: OrionSpacing.listGap),
                  _buildArmSection(context),
                  const SizedBox(height: OrionSpacing.listGap),
                  _buildScreenTypeSection(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZOffsetSection(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final config = OrionConfig();
    final base = config.getBaseZOffset();
    final double? offset = base != null
        ? base + config.getZOffsetOverride()
        : Provider.of<StatusProvider>(context).kinematicStatus?.offset;

    return GlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: OrionSpacing.cardPadding,
        child: Row(
          children: [
            PhosphorIcon(PhosphorIcons.arrowsVertical(),
                size: 30, color: primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FlutterI18n.translate(context, 'leveling.settingsZOffset'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    offset != null ? '${offset.toStringAsFixed(3)} mm' : '--',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FlutterI18n.translate(
                        context, 'leveling.settingsZOffsetHint'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: _editOffset,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(110, 55),
              ),
              child: Text(
                FlutterI18n.translate(context, 'common.change'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editOffset() async {
    final config = OrionConfig();
    final statusProvider =
        Provider.of<StatusProvider>(context, listen: false);
    var base = config.getBaseZOffset();
    if (base == null) {
      // No leveling base recorded yet — capture the current backend offset
      // as the reference so the ±20% range doesn't drift across edits.
      base = statusProvider.kinematicStatus?.offset ?? 0.0;
      config.setBaseZOffset(base);
    }
    final current = base + config.getZOffsetOverride();
    // Limit the slider to ±20% of the base offset (0.1 mm floor so it stays
    // usable when the base is at or near zero).  Anchoring to the base —
    // not the current effective offset — keeps the range from walking every
    // time a new offset is saved.
    final delta = max(base.abs() * 0.2, 0.1);
    final result = await ZoomValueEditorDialog.show(
      context,
      title: FlutterI18n.translate(context, 'leveling.settingsZOffset'),
      description: FlutterI18n.translate(
          context, 'leveling.settingsZOffsetDialogDesc'),
      currentValue: current,
      min: base - delta,
      max: base + delta,
      suffix: 'mm',
      decimals: 3,
      step: 0.01,
    );
    if (result == null || !mounted) return;

    final ok = await Provider.of<ManualProvider>(context, listen: false)
        .setZOffset(result);
    if (!ok) {
      if (mounted) showErrorDialog(context, 'GOLDEN-APE');
      return;
    }
    // Persist the override relative to the fixed base, rounded to the
    // slider's precision so it doesn't accumulate float noise.
    config.setZOffsetOverride(double.parse((result - base).toStringAsFixed(3)));
    await statusProvider.refreshKinematicStatus();
    if (mounted) setState(() {});
  }

  Widget _buildArmSection(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final variantId = OrionConfig().getLevelingVariant();
    final label = variantId == 'pro'
        ? FlutterI18n.translate(context, 'leveling.proArm')
        : variantId == 'regular'
            ? FlutterI18n.translate(context, 'leveling.standardArm')
            : FlutterI18n.translate(context, 'leveling.notSet');
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: OrionSpacing.cardPadding,
        child: Row(
          children: [
            PhosphorIcon(PhosphorIcons.wrench(), size: 28, color: primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FlutterI18n.translate(context, 'leveling.settingsArmTitle'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FlutterI18n.translate(context, 'leveling.settingsArmHint'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: _changeArm,
              style: ElevatedButton.styleFrom(minimumSize: const Size(110, 55)),
              child: Text(
                FlutterI18n.translate(context, 'common.change'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenTypeSection(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final screenId = OrionConfig().getScreenType();
    final screenType = LevelingScreenType.fromId(screenId.isNotEmpty ? screenId : null);
    final label = screenType != null
        ? FlutterI18n.translate(context, screenType.labelKey)
        : FlutterI18n.translate(context, 'leveling.notSet');
    return GlassCard(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: OrionSpacing.cardPadding,
        child: Row(
          children: [
            PhosphorIcon(PhosphorIcons.monitor(), size: 28, color: primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FlutterI18n.translate(context, 'leveling.settingsScreenTypeTitle'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    FlutterI18n.translate(context, 'leveling.settingsScreenTypeHint'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: _changeScreenType,
              style: ElevatedButton.styleFrom(minimumSize: const Size(110, 55)),
              child: Text(
                FlutterI18n.translate(context, 'common.change'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeArm() async {
    final current = OrionConfig().getLevelingVariant();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        title: Text(
          FlutterI18n.translate(context, 'leveling.settingsArmDialogTitle'),
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in const ['pro', 'regular'])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: GlassButton(
                    tint: current == v ? GlassButtonTint.positive : GlassButtonTint.neutral,
                    onPressed: () => Navigator.of(ctx).pop(v),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                    child: Text(
                      v == 'pro'
                          ? FlutterI18n.translate(context, 'leveling.proArm')
                          : FlutterI18n.translate(context, 'leveling.standardArm'),
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
            child: Text(FlutterI18n.translate(context, 'common.cancel')),
          ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      OrionConfig().setLevelingVariant(selected);
      setState(() {});
    }
  }

  Future<void> _changeScreenType() async {
    final current = OrionConfig().getScreenType();
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => GlassAlertDialog(
        title: Text(
          FlutterI18n.translate(context, 'leveling.settingsScreenTypeDialogTitle'),
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in LevelingScreenType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: GlassButton(
                    tint: current == t.id ? GlassButtonTint.positive : GlassButtonTint.neutral,
                    onPressed: () => Navigator.of(ctx).pop(t.id),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 60)),
                    child: Text(
                      FlutterI18n.translate(context, t.labelKey),
                    ),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 60)),
            child: Text(FlutterI18n.translate(context, 'common.cancel')),
          ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      OrionConfig().setScreenType(selected);
      setState(() {});
    }
  }

}
