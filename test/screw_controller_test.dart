/*
* Orion - Back Screw Controller Tests
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

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/tools/athena/screw_controller.dart';

/// Drive one closed-loop cycle against a simulated printer with true
/// coupling [trueC]: command → user reaches force target → plate moves
/// by trueC · delta → recheck.  Returns the new gap.
double _cycle(ScrewController ctrl, double gap, double trueC,
    {double noise = 0.0}) {
  final cmd = ctrl.command(zGapMm: gap);
  ctrl.recordCommand(cmd);
  final newGap = gap - trueC * cmd.forceDeltaGf;
  ctrl.onRecheck(newGapMm: newGap + noise);
  return newGap;
}

/// Build a controller escalated down to the stiffness floor via
/// repeated zero-movement rechecks.
ScrewController _flooredController() {
  final ctrl = ScrewController();
  for (int i = 0; i < 3; i++) {
    final cmd = ctrl.command(zGapMm: 0.25);
    ctrl.recordCommand(cmd);
    ctrl.onRecheck(newGapMm: 0.25); // no movement at all
  }
  return ctrl;
}

/// Emulate the wizard's candidate filter: the first ranked candidate
/// whose command is an executable tighten (≤ −100 gf), using the
/// leapfrog-biased controller for back corners.
(int, ScrewCommand)? _wizardPick(List<double> z) {
  for (final corner in rankAdjustmentCandidates(z)) {
    final ctrl = corner >= 2
        ? ScrewController(targetBiasMm: ScrewController.backLeapfrogBiasMm)
        : ScrewController();
    final cmd = ctrl.command(zGapMm: adjustmentGapMm(corner, z));
    if (cmd.forceDeltaGf <= -ScrewController.minCommandDeltaGf) {
      return (corner, cmd);
    }
  }
  return null;
}

void main() {
  group('legacy leapfrog corner selection (field-session regressions)', () {
    // Z order: FL, FR, BR, BL.
    // Policy: front-back tilt → back screw with a +0.1 mm leapfrog
    // overshoot; otherwise tighten the LOWER corner of the worst
    // diagonal.  All commands are tightens; a back candidate whose
    // command would be a loosen falls back to a low front corner.
    test('fc965bd2 #1: pure tilt → tighten back (never loosen a front)',
        () {
      // The direction-agnostic ranking here chose "loosen FL" (best
      // single move) — forbidden.  Legacy: all fronts above all backs
      // → back screw, shown at the worst outlier BR.
      const z = [0.80, 0.71, 0.40, 0.56];
      expect(rankAdjustmentCandidates(z), [2]);
      final pick = _wizardPick(z)!;
      expect(pick.$1, 2);
      // gap = frontAvg − BR = 0.355, damped 0.7, plus the 0.02 leapfrog.
      expect(pick.$2.targetZMm, closeTo(0.2685, 1e-9));
      expect(pick.$2.forceDeltaGf, lessThan(0)); // tighten
    });

    test('any executed command is a tighten, for any plate state', () {
      // Sweep a grid of corner states; the wizard-filtered pick must
      // always be a tighten of a genuinely low corner (or no pick at
      // all → the below-resolution screen).
      const levels = [0.0, 0.1, 0.25, 0.4];
      for (final fl in levels) {
        for (final fr in levels) {
          for (final br in levels) {
            for (final bl in levels) {
              final z = [fl, fr, br, bl];
              final pick = _wizardPick(z);
              if (pick == null) continue;
              expect(pick.$2.forceDeltaGf, lessThan(0),
                  reason: 'z=$z corner=${pick.$1} must be a tighten');
              if (pick.$1 <= 1) {
                expect(adjustmentGapMm(pick.$1, z), greaterThan(0),
                    reason: 'z=$z front pick must be a low corner');
              }
            }
          }
        }
      }
    });

    test('b9ef2b8f #0: pure front-back tilt → back screw at BL outlier',
        () {
      const z = [0.88, 0.99, 0.47, 0.44]; // both fronts above both backs
      expect(selectAdjustmentCorner(z), 3); // BL is the worst outlier
      // Legacy corner-specific gap: frontAvg − BL = 0.495.
      expect(adjustmentGapMm(3, z), closeTo(0.495, 1e-9));
    });

    test('b9ef2b8f #1: low BL in the worst diagonal → tighten back', () {
      // Mixed state (not a full tilt): worst diagonal FR↔BL (0.19),
      // lower corner BL → the shared back screw raises it.  Target is
      // 0.7·0.11 + 0.02 leapfrog = 0.097.
      const z = [0.63, 0.79, 0.68, 0.60];
      expect(rankAdjustmentCandidates(z), [3]);
      final pick = _wizardPick(z)!;
      expect(pick.$1, 3);
      expect(pick.$2.targetZMm, closeTo(0.097, 1e-9));
      expect(pick.$2.forceDeltaGf, lessThan(0)); // tighten
    });

    test('b9ef2b8f #2: back leads → falls back to tightening low FL', () {
      // All backs above all fronts → back screw is primary, but its
      // command would be a LOOSEN (gap −0.235 + 0.1 bias < 0) — the
      // preload policy forbids it, so the wizard falls back to the
      // low front corner of the worst diagonal: tighten FL.
      const z = [0.51, 0.68, 0.83, 0.74];
      expect(rankAdjustmentCandidates(z), [2, 0]);
      final pick = _wizardPick(z)!;
      expect(pick.$1, 0);
      expect(adjustmentGapMm(0, z), closeTo(0.32, 1e-9)); // BR − FL
      expect(pick.$2.forceDeltaGf, lessThan(0)); // tighten FL
    });

    test('f2c9f74d #1: back leads by a hair → tighten low FR, not back',
        () {
      // All backs (barely) above all fronts, but the back's command
      // (gap −0.11 + 0.1 bias ≈ 0) is not an executable tighten →
      // fall back to FR, the low corner of the worst diagonal.
      const z = [0.60, 0.58, 0.62, 0.70];
      expect(rankAdjustmentCandidates(z), [3, 1]);
      final pick = _wizardPick(z)!;
      expect(pick.$1, 1);
      expect(adjustmentGapMm(1, z), closeTo(0.12, 1e-9)); // BL − FR
      expect(pick.$2.forceDeltaGf, lessThan(0)); // tighten
    });

    test('FL↔BR diagonal with FL low routes to FL', () {
      const z = [0.45, 0.68, 0.83, 0.60]; // FL low, BR high
      expect(selectAdjustmentCorner(z), 0);
      // BR − FL = 0.38 → FL low → tighten
      expect(adjustmentGapMm(0, z), closeTo(0.38, 1e-9));
    });

    test('tilt with both backs low → back screw at the worse corner', () {
      const z = [0.50, 0.50, 0.20, 0.30];
      expect(selectAdjustmentCorner(z), 2); // BR shown for puck placement
      // Legacy corner-specific gap: frontAvg − BR = 0.30.
      expect(adjustmentGapMm(2, z), closeTo(0.30, 1e-9));
    });

    test('pure roll: legacy picks the low corner of the worst diagonal',
        () {
      // FL/BL high, FR/BR low.  diagFLBR wins the >= tie; its lower
      // corner is BR → back screw tighten (the plate then ratchets
      // level over subsequent front picks).
      const z = [0.60, 0.40, 0.40, 0.60];
      expect(selectAdjustmentCorner(z), 2);
      expect(adjustmentGapMm(2, z), closeTo(0.10, 1e-9)); // frontAvg − BR
    });
  });

  group('ScrewController command', () {
    test('seed command with damping 0.7 and no bias', () {
      final ctrl = ScrewController();
      final cmd = ctrl.command(zGapMm: 0.18);
      expect(cmd.targetZMm, closeTo(0.126, 1e-9)); // 0.7 damping, no bias
      expect(cmd.forceDeltaGf, closeTo(-252.0, 1e-6)); // 0.126 / -5e-4
      expect(cmd.clamped, isFalse);
      expect(cmd.predictedGapAfterMm, closeTo(0.054, 1e-9)); // 30% left
    });

    test('command with leapfrog bias shifts the target', () {
      final ctrl = ScrewController(
          targetBiasMm: ScrewController.backLeapfrogBiasMm);
      final cmd = ctrl.command(zGapMm: 0.18);
      expect(cmd.targetZMm, closeTo(0.146, 1e-9)); // 0.7·0.18 + 0.02 bias
      expect(cmd.forceDeltaGf, closeTo(-292.0, 1e-6)); // 0.146 / -5e-4
      expect(cmd.predictedGapAfterMm, closeTo(0.034, 1e-9));
    });

    test('per-screw baseline seed sizes the first command', () {
      // Field-derived baselines shipped by the wizard: back −2e-4,
      // fronts −3e-4.  On the reference printer (back true ≈ −1.4e-4)
      // the first command moves ~68% of target instead of the ~26%
      // the generic −5e-4 seed produced.
      final back = ScrewController(
        seedCouplingMmPerGf: -2.0e-4,
        targetBiasMm: ScrewController.backLeapfrogBiasMm,
      );
      final cmd = back.command(zGapMm: 0.384); // session ca9df37b #0
      expect(cmd.targetZMm, closeTo(0.7 * 0.384 + 0.02, 1e-9));
      expect(cmd.forceDeltaGf, closeTo((0.7 * 0.384 + 0.02) / -2.0e-4, 1e-6));
      // True coupling −1.32e-4 → moves 66% of target (vs 26% at −5e-4).
      final moved = -1.32e-4 * cmd.forceDeltaGf;
      expect(moved / cmd.targetZMm, closeTo(0.66, 0.01));
    });

    test('force delta clamps at ±3000 gf with clamp-aware prediction', () {
      final ctrl = _flooredController();
      expect(ctrl.coupling, closeTo(-2e-5, 1e-12));

      final cmd = ctrl.command(zGapMm: 0.25);
      expect(cmd.forceDeltaGf, -3000.0);
      expect(cmd.clamped, isTrue);
      // ±3000 gf at −2e-5 mm/gf moves at most 0.06 mm per cycle.
      expect(cmd.predictedGapAfterMm, closeTo(0.19, 1e-9));
      expect(cmd.predictedRechecks, 3); // 0.25 → 0.19 → 0.13 → 0.07
    });
  });

  group('ScrewController estimator', () {
    test('rejects physically-impossible positive samples', () {
      // Field-log regression: gap got WORSE by drift/noise after a
      // tighten command.  The old estimator fed this into the EMA and
      // reversed the gauge direction on the next cycle.
      final ctrl = ScrewController();
      final cmd = ctrl.command(zGapMm: 0.18);
      ctrl.recordCommand(cmd);
      final r = ctrl.onRecheck(newGapMm: 0.21); // moved the wrong way
      expect(r.outcome, CouplingUpdateOutcome.rejectedPositiveSample);
      expect(r.sample, greaterThan(0));
      expect(ctrl.coupling, ctrl.seedCouplingMmPerGf);
      expect(ctrl.hasMeasuredSample, isFalse);
    });

    test('coupling stays negative and in band under adversarial rechecks',
        () {
      // Replay the field failure pattern: overshoots, drift reversals
      // and normal moves interleaved across 7 cycles.
      final ctrl = ScrewController();
      const cycles = <(double, double)>[
        (0.154, -0.139), // overshoot past zero (session 347417ed #0→#1)
        (-0.139, -0.099), // partial correction
        (-0.099, -0.198), // adversarial: drift made it worse
        (-0.198, 0.121), // overshoot back
        (0.121, 0.089), // undershoot
        (0.166, 0.111), // small move (session 88448afd #0→#1)
        (0.107, -0.250), // big overshoot (session 7e7ff88a #0→#1)
      ];
      for (final (gap, newGap) in cycles) {
        final cmd = ctrl.command(zGapMm: gap);
        // Command must always point at closing the gap.
        expect(cmd.forceDeltaGf.sign, -gap.sign,
            reason: 'gap $gap must command ${gap > 0 ? "tighten" : "loosen"}');
        ctrl.recordCommand(cmd);
        ctrl.onRecheck(newGapMm: newGap);
        expect(ctrl.coupling, lessThan(0));
        expect(
            ctrl.coupling,
            inInclusiveRange(ScrewController.couplingMostSensitive,
                ScrewController.couplingStiffest));
      }
    });

    test('overshoot self-corrects: first sample replaces the seed', () {
      final ctrl = ScrewController();
      const trueC = -7.5e-4; // most sensitive printer seen in the field

      final cmd = ctrl.command(zGapMm: 0.25);
      expect(cmd.forceDeltaGf, closeTo(-350.0, 1e-6));
      ctrl.recordCommand(cmd);
      final newGap = 0.25 - trueC * cmd.forceDeltaGf; // -0.125 (flipped)
      final r = ctrl.onRecheck(newGapMm: newGap);
      expect(r.outcome, CouplingUpdateOutcome.accepted);
      expect(ctrl.coupling, closeTo(trueC, 1e-9)); // replaced, not averaged
      expect(ctrl.hasMeasuredSample, isTrue);

      // With the corrected coupling the next command is far smaller
      // and would land the gap on zero.
      final next = ctrl.command(zGapMm: newGap);
      expect(next.forceDeltaGf.abs(), lessThan(cmd.forceDeltaGf.abs() / 2));
      expect(next.predictedGapAfterMm.abs(), lessThan(0.01));
    });

    test('subsequent samples are EMA-smoothed', () {
      final ctrl = ScrewController();
      var gap = _cycle(ctrl, 0.25, -2.0e-4); // first sample replaces seed
      expect(ctrl.coupling, closeTo(-2.0e-4, 1e-9));
      _cycle(ctrl, gap, -1.0e-4); // second sample EMA 50/50
      expect(ctrl.coupling, closeTo(-1.5e-4, 1e-8));
    });

    test('stiction escalation triples force until movement is measurable',
        () {
      final ctrl = ScrewController();
      const trueC = -2.5e-5; // stiffest printer seen in the field

      // Cycle 1: seed command moves the plate < 0.02 mm → escalate.
      final cmd1 = ctrl.command(zGapMm: 0.25);
      ctrl.recordCommand(cmd1);
      var gap = 0.25 - trueC * cmd1.forceDeltaGf; // 0.2406
      final r1 = ctrl.onRecheck(newGapMm: gap);
      expect(r1.outcome, CouplingUpdateOutcome.stictionEscalated);
      expect(ctrl.stictionEscalations, 1);
      expect(ctrl.coupling, closeTo(-5e-4 / 3, 1e-9));

      // Cycle 2: ~3× the force → measurable move → true coupling captured.
      final cmd2 = ctrl.command(zGapMm: gap);
      expect(cmd2.forceDeltaGf.abs(),
          greaterThan(cmd1.forceDeltaGf.abs() * 2.5));
      ctrl.recordCommand(cmd2);
      gap = gap - trueC * cmd2.forceDeltaGf;
      final r2 = ctrl.onRecheck(newGapMm: gap);
      expect(r2.outcome, CouplingUpdateOutcome.accepted);
      expect(ctrl.coupling, closeTo(trueC, 1e-9));
    });

    test('stiction escalation floors at the stiffness bound and caps', () {
      final ctrl = ScrewController();
      for (int i = 0; i < 8; i++) {
        final cmd = ctrl.command(zGapMm: 0.25);
        expect(cmd.forceDeltaGf.abs(), lessThanOrEqualTo(3000.0));
        ctrl.recordCommand(cmd);
        ctrl.onRecheck(newGapMm: 0.25); // never moves
      }
      expect(ctrl.coupling, closeTo(-2e-5, 1e-12));
      expect(ctrl.stictionEscalations,
          ScrewController.maxStictionEscalations);
    });

    test('small commands are skipped without escalation', () {
      final ctrl = ScrewController();
      final cmd = ctrl.command(zGapMm: 0.07); // delta = 98 gf < 100
      expect(cmd.forceDeltaGf.abs(), lessThan(100));
      ctrl.recordCommand(cmd);
      final r = ctrl.onRecheck(newGapMm: 0.07); // no movement either
      expect(r.outcome, CouplingUpdateOutcome.rejectedSmallDelta);
      expect(ctrl.stictionEscalations, 0);
      expect(ctrl.coupling, ctrl.seedCouplingMmPerGf);
    });

    test('out-of-band samples are clamped, not rejected', () {
      // Too sensitive: 0.45 mm move on a -500 gf command → -9e-4.
      final soft = ScrewController();
      final cmdS = soft.command(zGapMm: 0.25);
      soft.recordCommand(cmdS);
      final rS = soft.onRecheck(newGapMm: 0.25 - 0.45);
      expect(rS.outcome, CouplingUpdateOutcome.acceptedClamped);
      expect(soft.coupling, ScrewController.couplingMostSensitive);

      // Too stiff: 0.05 mm move on a -3000 gf command → -1.67e-5.
      final stiff = ScrewController();
      final cmdT = stiff.command(zGapMm: 2.5); // saturates at -3000 gf
      expect(cmdT.forceDeltaGf, -3000.0);
      stiff.recordCommand(cmdT);
      final rT = stiff.onRecheck(newGapMm: 2.5 - 0.05);
      expect(rT.outcome, CouplingUpdateOutcome.acceptedClamped);
      expect(stiff.coupling, ScrewController.couplingStiffest);
    });
  });

  group('ScrewController cross-seeding', () {
    test('an unmeasured controller adopts a sibling coupling', () {
      final back = ScrewController();
      _cycle(back, 0.4, -1.7e-4); // back learns the plate's coupling
      expect(back.hasMeasuredSample, isTrue);

      final fr = ScrewController();
      fr.adoptSeed(back.coupling);
      expect(fr.coupling, closeTo(-1.7e-4, 1e-9));
      expect(fr.hasMeasuredSample, isFalse); // adopted, not measured
      // First FR command is now plate-scaled instead of seed-scaled:
      // session 27e976fe's FR first move was only 46% of target off
      // the generic seed.
      expect(fr.command(zGapMm: 0.3).forceDeltaGf,
          closeTo(0.7 * 0.3 / -1.7e-4, 1.0));
    });

    test('adoptSeed never overwrites a measured coupling', () {
      final ctrl = ScrewController();
      _cycle(ctrl, 0.4, -2.4e-4);
      expect(ctrl.coupling, closeTo(-2.4e-4, 1e-9));
      ctrl.adoptSeed(-1.0e-4);
      expect(ctrl.coupling, closeTo(-2.4e-4, 1e-9)); // unchanged
    });

    test('adopted seeds are clamped into the plausible band', () {
      final ctrl = ScrewController();
      ctrl.adoptSeed(-5e-3); // absurdly sensitive
      expect(ctrl.coupling, ScrewController.couplingMostSensitive);
      ctrl.adoptSeed(-1e-6); // absurdly stiff
      expect(ctrl.coupling, ScrewController.couplingStiffest);
    });
  });

  group('ScrewController gauge-compliance protection', () {
    test('partial compliance learns the TRUE coupling via achieved delta',
        () {
      // User told to apply -700 gf but stops halfway at -350.  The
      // plate responds to what was applied; dividing by the commanded
      // delta would make the plate look 2x stiffer than it is.
      final ctrl = ScrewController();
      const trueC = -2.0e-4;
      final cmd = ctrl.command(zGapMm: 0.5); // -700 gf commanded
      ctrl.recordCommand(cmd);
      const achieved = -350.0; // user stopped halfway
      final newGap = 0.5 - trueC * achieved; // plate moved per achieved
      final r = ctrl.onRecheck(newGapMm: newGap, achievedDeltaGf: achieved);
      expect(r.accepted, isTrue);
      expect(ctrl.coupling, closeTo(trueC, 1e-9)); // truth, not 2x-stiff
    });

    test('a skipped turn is rejected, not escalated as stiction', () {
      // User never touches the screw: no movement AND no applied
      // force.  Before achieved-delta gating this misfired as
      // stiction and tripled the next command.
      final ctrl = ScrewController();
      final cmd = ctrl.command(zGapMm: 0.5);
      ctrl.recordCommand(cmd);
      final r = ctrl.onRecheck(newGapMm: 0.5, achievedDeltaGf: -10.0);
      expect(r.outcome, CouplingUpdateOutcome.rejectedSmallDelta);
      expect(ctrl.stictionEscalations, 0);
      expect(ctrl.coupling, ctrl.seedCouplingMmPerGf);
    });

    test('genuine stiction (force applied, no movement) still escalates',
        () {
      final ctrl = ScrewController();
      final cmd = ctrl.command(zGapMm: 0.5);
      ctrl.recordCommand(cmd);
      // Full commanded force applied, plate did not move.
      final r = ctrl.onRecheck(
          newGapMm: 0.5, achievedDeltaGf: cmd.forceDeltaGf);
      expect(r.outcome, CouplingUpdateOutcome.stictionEscalated);
      expect(ctrl.stictionEscalations, 1);
    });

    test('no live reading falls back to the commanded delta', () {
      final ctrl = ScrewController();
      const trueC = -2.0e-4;
      final gap = _cycle(ctrl, 0.5, trueC); // helper passes no achieved
      expect(ctrl.coupling, closeTo(trueC, 1e-9));
      expect(gap, lessThan(0.5));
    });
  });

  group('ScrewController pending lifecycle', () {
    test('recheck without a pending command is a no-op', () {
      final ctrl = ScrewController();
      final r = ctrl.onRecheck(newGapMm: 0.1);
      expect(r.outcome, CouplingUpdateOutcome.noPendingCommand);
      expect(ctrl.coupling, ctrl.seedCouplingMmPerGf);
    });

    test('recording a second command overwrites the first', () {
      final ctrl = ScrewController();
      ctrl.recordCommand(ctrl.command(zGapMm: 0.25));
      final cmd2 = ctrl.command(zGapMm: 0.30);
      ctrl.recordCommand(cmd2);
      final r = ctrl.onRecheck(newGapMm: 0.10);
      expect(r.gapAtCommandMm, 0.30);
      expect(r.commandedDeltaGf, cmd2.forceDeltaGf);
      expect(r.outcome, CouplingUpdateOutcome.accepted);
    });

    test('abandonPending discards the snapshot', () {
      final ctrl = ScrewController();
      ctrl.recordCommand(ctrl.command(zGapMm: 0.25));
      expect(ctrl.hasPendingCommand, isTrue);
      ctrl.abandonPending();
      expect(ctrl.hasPendingCommand, isFalse);
      final r = ctrl.onRecheck(newGapMm: 0.1);
      expect(r.outcome, CouplingUpdateOutcome.noPendingCommand);
    });

    test('pending is consumed by a recheck', () {
      final ctrl = ScrewController();
      ctrl.recordCommand(ctrl.command(zGapMm: 0.25));
      ctrl.onRecheck(newGapMm: 0.10);
      expect(ctrl.hasPendingCommand, isFalse);
      expect(ctrl.onRecheck(newGapMm: 0.05).outcome,
          CouplingUpdateOutcome.noPendingCommand);
    });
  });

  group('ScrewController convergence', () {
    const fieldRange = [-2.5e-5, -5e-5, -1e-4, -2.5e-4, -5e-4, -7.5e-4];

    test('noise-free: passes within 4 rechecks across the field range', () {
      for (final trueC in fieldRange) {
        final ctrl = ScrewController();
        var gap = 0.25;
        var rechecks = 0;
        while (gap.abs() > ScrewController.passGapMm && rechecks < 10) {
          gap = _cycle(ctrl, gap, trueC);
          rechecks++;
        }
        expect(rechecks, lessThanOrEqualTo(4),
            reason: 'trueC=$trueC took $rechecks rechecks');
      }
    });

    test('with ±0.03 mm recheck noise: never diverges, coupling in band',
        () {
      final rand = Random(42);
      for (final trueC in fieldRange) {
        final ctrl = ScrewController();
        var gap = 0.25;
        for (int i = 0; i < 12; i++) {
          final noise = (rand.nextDouble() * 2 - 1) * 0.03;
          gap = _cycle(ctrl, gap, trueC, noise: noise);
          expect(gap.abs(), lessThan(0.35),
              reason: 'trueC=$trueC diverged to $gap at cycle $i');
          expect(
              ctrl.coupling,
              inInclusiveRange(ScrewController.couplingMostSensitive,
                  ScrewController.couplingStiffest));
        }
      }
    });
  });
}
