/*
* Orion - Leveling Configs
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
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:orion/tools/athena/c3d_athena2_wizard_config.dart';

enum LevelingWorkflowStepKind {
  prepare,
  probe,
  finalOffset,
}

class LevelingWorkflowStep {
  final String id;
  final String endpoint;
  final String titleKey;
  final String instructionKey;
  final String? imagePath;
  final IconData icon;
  final LevelingWorkflowStepKind kind;

  /// Custom running title shown during execution (null = default per kind)
  final String? runningTitle;

  /// Custom step title override (null = use titleKey i18n)
  final String? stepTitle;

  /// Custom instruction override (null = use instructionKey i18n)
  final String? stepInstruction;

  /// Intermediate screen to show after completion:
  /// null = none, 'loosen', 'tighten', 'allCorners'
  final String? intermediateScreen;

  /// Special screen to fire on each completion:
  /// null = none, 'center', 'corner-0'..'corner-3'
  final String? specialScreen;

  /// If true, auto-advance to next step after completion
  final bool autoAdvance;

  /// Display label for corner steps (e.g. 'Front Left')
  final String? cornerLabel;

  /// If true, skip the backend endpoint call and mark the step as
  /// complete immediately (for informational/intermediate screens).
  final bool skipBackend;

  const LevelingWorkflowStep({
    required this.id,
    required this.endpoint,
    required this.titleKey,
    required this.instructionKey,
    required this.icon,
    this.imagePath,
    this.kind = LevelingWorkflowStepKind.probe,
    this.runningTitle,
    this.stepTitle,
    this.stepInstruction,
    this.intermediateScreen,
    this.specialScreen,
    this.autoAdvance = false,
    this.cornerLabel,
    this.skipBackend = false,
  });

  /// Create a copy with selected fields overridden.
  LevelingWorkflowStep copyWith({
    String? endpoint,
    String? runningTitle,
    String? stepTitle,
    String? stepInstruction,
    String? intermediateScreen,
    String? specialScreen,
    bool? autoAdvance,
    String? cornerLabel,
    bool? skipBackend,
  }) {
    return LevelingWorkflowStep(
      id: id,
      endpoint: endpoint ?? this.endpoint,
      titleKey: titleKey,
      instructionKey: instructionKey,
      icon: icon,
      imagePath: imagePath,
      kind: kind,
      runningTitle: runningTitle ?? this.runningTitle,
      stepTitle: stepTitle ?? this.stepTitle,
      stepInstruction: stepInstruction ?? this.stepInstruction,
      intermediateScreen: intermediateScreen ?? this.intermediateScreen,
      specialScreen: specialScreen ?? this.specialScreen,
      autoAdvance: autoAdvance ?? this.autoAdvance,
      cornerLabel: cornerLabel ?? this.cornerLabel,
      skipBackend: skipBackend ?? this.skipBackend,
    );
  }
}

class LevelingVariant {
  final String id;
  final String label;
  final String description;
  final String? assetPath;
  final IconData? icon;
  final String finalEndpoint;
  final String successKey;

  const LevelingVariant({
    required this.id,
    required this.label,
    required this.description,
    required this.finalEndpoint,
    required this.successKey,
    this.assetPath,
    this.icon,
  });

  List<LevelingWorkflowStep> buildSteps() {
    // Stage 1 (initial seating) — common to all variants.
    // The initial offset calibration is only included for non-pro;
    // pro redoes it as the final step after corner leveling anyway.
    final stage1 = <LevelingWorkflowStep>[
      // 0: Prepare — shows loosen intermediate
      athena2BaseWorkflowSteps[0].copyWith(
        intermediateScreen: 'loosen',
      ),
      // 1: Initial leveling — shows tighten intermediate.
      // Standard arm floors the Z to seat the plate instead of probing,
      // since the arm can shift when screws are loose.
      athena2BaseWorkflowSteps[1].copyWith(
        endpoint: id != 'pro' ? 'probe_standardarm' : null,
        skipBackend: id != 'pro' ? true : null,
        stepTitle: 'Initial Leveling',
        stepInstruction: 'The plate will move towards the build plate.',
        intermediateScreen: 'tighten',
      ),
    ];

    // Regular build arm: add offset calibration and finish.
    if (id != 'pro') {
      return <LevelingWorkflowStep>[
        ...stage1,
        LevelingWorkflowStep(
          id: finalEndpoint,
          endpoint: finalEndpoint,
          titleKey: 'levelingWorkflow.finalOffsetTitle',
          instructionKey: finalEndpoint == 'probe_standardarm'
              ? 'levelingWorkflow.standardArmInstruction'
              : 'levelingWorkflow.offsetInstruction',
          icon: PhosphorIcons.crosshair(),
          kind: LevelingWorkflowStepKind.finalOffset,
          stepTitle: 'Calibrating Offset',
          stepInstruction: 'Saving the calibrated Z offset.',
          runningTitle: 'Calibrating Offset',
          autoAdvance: true,
        ),
      ];
    }

    // Pro build arm: Stage 2 adds 4-corner fine leveling
    final cornerDefs = [
      ('Front Left', 'front-left'),
      ('Front Right', 'front-right'),
      ('Back Right', 'back-right'),
      ('Back Left', 'back-left'),
    ];
    return <LevelingWorkflowStep>[
      ...stage1,
      // ── Stage 2: 4-corner fine leveling ──
      for (int i = 0; i < 4; i++) ...[
        LevelingWorkflowStep(
          id: 'fine_prepare_${i + 1}',
          endpoint: 'probe_corner_prepare',
          titleKey: 'levelingWorkflow.cornerPrepareTitle',
          instructionKey: 'levelingWorkflow.cornerPrepareInstruction',
          icon: [
            PhosphorIcons.arrowDownLeft(),
            PhosphorIcons.arrowDownRight(),
            PhosphorIcons.arrowUpRight(),
            PhosphorIcons.arrowUpLeft(),
          ][i],
          kind: LevelingWorkflowStepKind.prepare,
          stepTitle: 'Place Leveling Spacer',
          stepInstruction:
              'Please place the Leveling Spacer in the ${cornerDefs[i].$1} corner',
          specialScreen: 'corner-$i',
        ),
        LevelingWorkflowStep(
            id: 'fine_corner_${i + 1}',
            endpoint: 'probe_corner',
            titleKey: 'levelingWorkflow.cornerTitle',
            instructionKey: 'levelingWorkflow.cornerInstruction',
            icon: PhosphorIconsFill.crosshair,
            kind: LevelingWorkflowStepKind.probe,
            stepTitle: 'Corner: ${cornerDefs[i].$1}',
            stepInstruction: 'Please put the Leveling Spacer at the position '
                'indicated on the screen.',
            runningTitle: 'Probing ${cornerDefs[i].$1} Corner',
            cornerLabel: cornerDefs[i].$1,
            autoAdvance: true),
      ],
      // ── Stage 3: Corner results, remove puck, re-calibrate offset ──
      LevelingWorkflowStep(
        id: 'corner_results',
        endpoint: '',
        titleKey: '',
        instructionKey: '',
        icon: PhosphorIconsFill.checkCircle,
        kind: LevelingWorkflowStepKind.probe,
        skipBackend: true,
        intermediateScreen: 'allCorners',
      ),
      LevelingWorkflowStep(
        id: 'remove_puck',
        endpoint: '',
        titleKey: '',
        instructionKey: '',
        icon: PhosphorIconsFill.hand,
        kind: LevelingWorkflowStepKind.prepare,
        skipBackend: true,
        intermediateScreen: 'removePuck',
      ),
      LevelingWorkflowStep(
        id: 'final_prepare',
        endpoint: 'probe_prepare',
        titleKey: 'levelingWorkflow.prepareTitle',
        instructionKey: 'levelingWorkflow.prepareInstruction',
        icon: PhosphorIconsFill.house,
        kind: LevelingWorkflowStepKind.prepare,
        autoAdvance: true,
      ),
      LevelingWorkflowStep(
        id: '${finalEndpoint}_final',
        endpoint: finalEndpoint,
        titleKey: 'levelingWorkflow.finalOffsetTitle',
        instructionKey: 'levelingWorkflow.offsetInstruction',
        icon: PhosphorIcons.crosshair(),
        kind: LevelingWorkflowStepKind.finalOffset,
        stepTitle: 'Final Calibration',
        stepInstruction: 'Re-calibrating the Z offset.',
        runningTitle: 'Final Calibration',
        autoAdvance: true,
      ),
    ];
  }
}

class LevelingConfig {
  final String machineIdPrefix;
  final List<String> checklistKeys;
  final List<LevelingVariant> variants;

  const LevelingConfig({
    required this.machineIdPrefix,
    required this.checklistKeys,
    required this.variants,
  });
}

const List<LevelingConfig> levelingConfigs = [
  athena2LevelingConfig,
];

LevelingConfig? getLevelingConfigForMachine(String machineModel) {
  try {
    return levelingConfigs.firstWhere(
      (config) => machineModel.startsWith(config.machineIdPrefix),
    );
  } catch (_) {
    return null;
  }
}

/// The type of screen surface the printer probes during leveling.
///
/// A rigid tempered-glass screen reads a firm contact, while a wave
/// release film is flexible and compresses slightly under the probe —
/// the two can require different leveling behaviour.  The selection is
/// persisted in config and recorded in the leveling log.
enum LevelingScreenType {
  temperedGlass(
    id: 'tempered_glass',
    labelKey: 'leveling.screenTypeTemperedGlass',
    descriptionKey: 'leveling.screenTypeTemperedGlassDesc',
  ),
  waveReleaseFilm(
    id: 'wave_release_film',
    labelKey: 'leveling.screenTypeWaveReleaseFilm',
    descriptionKey: 'leveling.screenTypeWaveReleaseFilmDesc',
  );

  const LevelingScreenType({
    required this.id,
    required this.labelKey,
    required this.descriptionKey,
  });

  /// Stable identifier persisted in `orion.cfg` (e.g. `'tempered_glass'`).
  final String id;
  final String labelKey;
  final String descriptionKey;

  /// Resolve from a persisted [id]; null when unknown/empty.
  static LevelingScreenType? fromId(String? id) {
    if (id == null) return null;
    for (final t in values) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Backend query-param value for the `screentype` argument accepted by
  /// the `probe_standardarm` / `probe_offset` workflow endpoints.
  String get screentypeParam => switch (this) {
        LevelingScreenType.temperedGlass => 'glass',
        LevelingScreenType.waveReleaseFilm => 'waverelease',
      };
}
