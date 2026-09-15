/*
* Orion - Verify Leveling Screen
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
import 'package:orion/glasser/glasser.dart';
import 'package:orion/tools/athena/c3d_athena2_wizard.dart';
import 'package:orion/tools/athena/leveling_configs.dart';
import 'package:orion/tools/athena/leveling_verification_record.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/util/widgets/system_status_widget.dart';
import 'package:orion/widgets/orion_app_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

/// Whether the printer is marked as leveled, i.e. whether there is leveling
/// state to inspect.
///
/// State lives in `orion.cfg` (`leveling.isLeveled`) and survives updates, so
/// this is the hint that verification is available.  The corner record is only
/// needed to render the measured numbers — a printer that is leveled but has
/// no record left (an update before the record was persisted cleared it) is
/// still verifiable, it just has nothing to show yet.
bool isPrinterLeveled() => OrionConfig().isLeveled();

class VerifyLevelingScreen extends StatefulWidget {
  const VerifyLevelingScreen({super.key});

  @override
  State<VerifyLevelingScreen> createState() => _VerifyLevelingScreenState();
}

class _VerifyLevelingScreenState extends State<VerifyLevelingScreen> {
  LevelingVerificationRecord? _session;

  @override
  void initState() {
    super.initState();
    _refreshSession();
  }

  void _refreshSession() {
    final session = LevelingVerificationRecord.load();
    if (mounted) setState(() => _session = session);
  }

  @override
  Widget build(BuildContext context) {
    final isGlass =
        Provider.of<ThemeProvider>(context, listen: false).isGlassTheme;
    final primary = Theme.of(context).colorScheme.primary;
    final session = _session;
    final leveled = OrionConfig().isLeveled();

    return GlassApp(
      child: Scaffold(
        backgroundColor: isGlass
            ? Colors.transparent
            : Theme.of(context).colorScheme.surface,
        appBar: OrionAppBar(
          title: Text(
            FlutterI18n.translate(context, 'leveling.verify'),
          ),
          toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight,
          actions: const [SystemStatusWidget()],
        ),
        body: SafeArea(
          child: Padding(
            padding: OrionSpacing.screenPaddingWithBottomNav,
            child: !leveled
                ? _buildNoDataView(context, primary)
                : session != null
                    ? _buildSessionView(context, session, primary)
                    : _buildNoRecordView(context, primary),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionView(
      BuildContext context, LevelingVerificationRecord s, Color primary) {
    final theme = Theme.of(context);
    final frontGap = s.frontBackGapMm;
    // Compact timestamp: drop seconds
    final compactTs =
        s.timestamp.length >= 16 ? s.timestamp.substring(0, 16) : s.timestamp;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: OrionSpacing.screenHorizontal),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Deviation
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Δ',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          s.deviationMm.toStringAsFixed(3),
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      'mm',
                      style: TextStyle(
                        fontSize: 18,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '/ 0.100 mm',
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (s.deviationMm / 0.100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
              ),
              const SizedBox(height: 32),
              // Corner Z row
              Row(
                children: [
                  for (final label in const ['FL', 'FR', 'BR', 'BL']) ...[
                    if (label != 'FL')
                      Container(
                        width: 1,
                        height: 24,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.12),
                      ),
                    Expanded(
                      child: _compactCorner(
                          context, label, s.cornerZs[label], primary),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 32),
              // Stat chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statChip(theme, PhosphorIcons.clock(), compactTs),
                  _statChip(theme, PhosphorIcons.cube(), s.variant),
                  _statChip(theme, PhosphorIcons.arrowsCounterClockwise(),
                      '${s.totalChecks} checks'),
                  if (frontGap != null)
                    _statChip(theme, PhosphorIcons.arrowsVertical(),
                        '${frontGap.toStringAsFixed(3)} mm'),
                  if (s.rangeMm != null)
                    _statChip(theme, PhosphorIcons.arrowsHorizontal(),
                        '${s.rangeMm!.toStringAsFixed(3)} mm'),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
        ),
        _buildRecheckButton(context),
      ],
    );
  }

  /// Bottom-aligned "Re-Check Leveling" button, shared by the recorded and
  /// record-less views.
  Widget _buildRecheckButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          OrionSpacing.screenHorizontal, 4,
          OrionSpacing.screenHorizontal, OrionSpacing.controlGap),
      child: SizedBox(
        width: double.infinity,
        child: GlassButton(
          tint: GlassButtonTint.positive,
          onPressed: () async {
            // Verify Leveling clears the current Z offset (the wizard
            // runs probe_prepare before the first probe), so the
            // existing leveling data is no longer valid until this
            // verification completes successfully.  Warn the user and
            // mark the printer as unleveled so they follow through.
            final confirmed = await showDialog<bool>(
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
                        FlutterI18n.translate(
                            context, 'leveling.verifyClearOffsetTitle'),
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
                      context, 'leveling.verifyClearOffsetMsg'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w500),
                ),
                actions: [
                  GlassButton(
                    tint: GlassButtonTint.neutral,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 55)),
                    child:
                        Text(FlutterI18n.translate(context, 'common.cancel')),
                  ),
                  GlassButton(
                    tint: GlassButtonTint.warn,
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 55)),
                    child:
                        Text(FlutterI18n.translate(context, 'common.confirm')),
                  ),
                ],
              ),
            );
            if (confirmed != true || !mounted || !context.mounted) return;

            // The offset will be cleared when the recheck wizard starts
            // probing — the printer is no longer leveled until the
            // verification completes successfully.
            OrionConfig().setLeveled(false);

            final config = OrionConfig();
            final levelingConfig = getLevelingConfigForMachine(
              config.getMachineModelName(),
            );
            if (levelingConfig == null) return;

            await Navigator.of(context).push(
              PageRouteBuilder<void>(
                opaque: false,
                barrierDismissible: false,
                barrierColor: Colors.black.withValues(alpha: 0.35),
                transitionDuration: const Duration(milliseconds: 300),
                reverseTransitionDuration: const Duration(milliseconds: 250),
                pageBuilder: (_, __, ___) => Athena2LevelingWizard(
                  config: levelingConfig,
                  recheck: true,
                ),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(
                    opacity:
                        CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    child: child,
                  );
                },
              ),
            );
            if (mounted) _refreshSession();
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 65),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIcons.arrowsCounterClockwise(), size: 20),
              const SizedBox(width: 8),
              Text(
                FlutterI18n.translate(context, 'leveling.recheckLeveling'),
                style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Leveled, but the recorded measurements are gone — show the state we do
  /// have and let the user measure again.
  Widget _buildNoRecordView(BuildContext context, Color primary) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(PhosphorIcons.checkCircle(),
                        size: 32, color: primary.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    FlutterI18n.translate(
                        context, 'leveling.verifyRecordMissing'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: OrionSpacing.screenHorizontal),
                    child: Text(
                      FlutterI18n.translate(
                          context, 'leveling.verifyRecordMissingHint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _buildRecheckButton(context),
      ],
    );
  }

  Widget _statChip(ThemeData theme, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactCorner(
      BuildContext context, String label, double? z, Color primary) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: primary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          z != null ? z.toStringAsFixed(2) : '--',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildNoDataView(BuildContext context, Color primary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.12),
            ),
            child: Icon(PhosphorIcons.info(),
                size: 32, color: primary.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          Text(
            FlutterI18n.translate(context, 'leveling.verifyNoData'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            FlutterI18n.translate(context, 'leveling.verifyNoDataHint'),
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
