/*
* Orion - Athena 2 Leveling Config
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

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:orion/tools/athena/leveling_configs.dart';

const athena2BaseWorkflowSteps = [
  LevelingWorkflowStep(
    id: 'probe_prepare',
    endpoint: 'probe_prepare',
    titleKey: 'levelingWorkflow.prepareTitle',
    instructionKey: 'levelingWorkflow.prepareInstruction',
    icon: PhosphorIconsFill.house,
    kind: LevelingWorkflowStepKind.prepare,
  ),
  LevelingWorkflowStep(
    id: 'probe_screen',
    endpoint: 'probe_screen',
    titleKey: 'levelingWorkflow.screenTitle',
    instructionKey: 'levelingWorkflow.screenInstruction',
    icon: PhosphorIconsFill.crosshair,
  ),
  LevelingWorkflowStep(
    id: 'probe_corner_prepare',
    endpoint: 'probe_corner_prepare',
    titleKey: 'levelingWorkflow.cornerPrepareTitle',
    instructionKey: 'levelingWorkflow.cornerPrepareInstruction',
    icon: PhosphorIconsFill.house,
    kind: LevelingWorkflowStepKind.prepare,
  ),
  LevelingWorkflowStep(
    id: 'probe_corner',
    endpoint: 'probe_corner',
    titleKey: 'levelingWorkflow.cornerTitle',
    instructionKey: 'levelingWorkflow.cornerInstruction',
    icon: PhosphorIconsFill.crosshair,
  ),
  LevelingWorkflowStep(
    id: 'probe_levelcheck',
    endpoint: 'probe_levelcheck',
    titleKey: 'levelingWorkflow.levelCheckTitle',
    instructionKey: 'levelingWorkflow.levelCheckInstruction',
    icon: PhosphorIconsFill.checkCircle,
  ),
];

const athena2LevelingConfig = LevelingConfig(
  machineIdPrefix: 'Athena2',
  checklistKeys: [
    'leveling.removeVat',
    'leveling.checkHexKeys',
    'leveling.checkInstallPlate',
    'leveling.checkLcdClean',
  ],
  variants: [
    LevelingVariant(
      id: 'regular',
      label: 'Standard Build Arm',
      description: 'Athena 2 standard build arm.',
      assetPath: 'assets/images/concepts_3d/a2_standard_arm.svg',
      icon: PhosphorIconsFill.wrench,
      finalEndpoint: 'probe_standardarm',
      successKey: 'levelingWorkflow.standardArmSuccess',
    ),
    LevelingVariant(
      id: 'pro',
      label: 'Pro Build Arm',
      description: 'Improved leveling & latching mechanism.',
      assetPath: 'assets/images/concepts_3d/a2_pro_arm.svg',
      icon: PhosphorIconsFill.star,
      finalEndpoint: 'probe_offset',
      successKey: 'levelingWorkflow.offsetSuccess',
    ),
  ],
);
