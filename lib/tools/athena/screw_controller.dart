/*
* Orion - Leveling Screw Controller
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

import 'dart:math' as math;

/// Corner indexing used throughout leveling: 0=FL, 1=FR, 2=BR, 3=BL.
/// Screw mapping: corners 0/1 → the respective front screw, corners
/// 2/3 → the single shared back screw on the centerline.
///
/// LEGACY LEAPFROG POLICY (restored from the pre-rework wizard, which
/// converged faster and was more predictable in the field):
///
///   1. Pure front-to-back tilt (all front corners on one side of all
///      back corners) → BACK screw, shown at the back corner furthest
///      from the front-plane average.  The back target deliberately
///      overshoots the front plane by [ScrewController.backLeapfrogBiasMm]
///      so the back edge LEADS...
///   2. Otherwise → the worst diagonal pair (FL↔BR vs FR↔BL), and the
///      LOWER corner of that pair is tightened — a front corner via
///      its own screw, a back corner via the shared back screw.
///
///   ...then the front screws catch up to the leading back edge on
///   subsequent cycles.  The plate ratchets upward until level, which
///   keeps every command a TIGHTEN (loosening bleeds off the baseline
///   preload the screws were seated with; absolute height drift is
///   re-zeroed by the final Z-offset calibration).
///
/// When the tilt branch fires but the back already leads (its command
/// would be a loosen or below the execution floor), the list falls
/// back to the diagonal pick so a low FRONT corner is tightened
/// instead — the wizard filters the list to the first candidate whose
/// command is an executable tighten.
///
/// Returns candidate corner indices in preference order.
List<int> rankAdjustmentCandidates(List<double> z) {
  assert(z.length >= 4);
  final z0 = z[0], z1 = z[1], z2 = z[2], z3 = z[3];
  final allFrontHigher = z0 > z2 && z0 > z3 && z1 > z2 && z1 > z3;
  final allBackHigher = z2 > z0 && z2 > z1 && z3 > z0 && z3 > z1;

  // Diagonal pick: the LOWER corner of the worst diagonal pair.
  final diagFLBR = (z0 - z2).abs();
  final diagFRBL = (z1 - z3).abs();
  final int diagCorner;
  if (diagFLBR >= diagFRBL) {
    diagCorner = z0 < z2 ? 0 : 2;
  } else {
    diagCorner = z1 < z3 ? 1 : 3;
  }

  if (allFrontHigher || allBackHigher) {
    // Back screw is single and centered — always show Back Left
    // per product decision (BR/BL distinction doesn't matter).
    const backOutlier = 3;
    return [
      backOutlier,
      // Fallback for when the back already leads: tighten the low
      // front corner of the worst diagonal instead.
      if (diagCorner <= 1) diagCorner,
    ];
  }
  // Map any back corner (BR→BL) so the UI always says Back Left
  final backMapped = diagCorner == 2 ? 3 : diagCorner;
  return [backMapped];
}

/// The preferred single-screw pick for the given corner Z values.
int selectAdjustmentCorner(List<double> z) =>
    rankAdjustmentCandidates(z).first;

/// Signed gap the screw for [cornerIndex] should close (mm).
/// Positive → the adjusted corner is LOW relative to its reference →
/// tighten; negative → high.  (The wizard enforces tighten-only: a
/// candidate whose command is not an executable tighten is skipped.)
///
/// * Front screws: the full diagonal spread (BR−FL for the FL screw,
///   BL−FR for the FR screw).  Tightening moves BOTH ends of the
///   diagonal (corner up, opposite rear corner down), and the
///   two-corner spread doubles the signal relative to per-corner
///   probe noise.
/// * Back screw (2/3): front-plane average minus the PICKED corner's Z
///   (legacy behavior — for a tilt this is the worst outlier, for a
///   low back corner in a diagonal it is that corner).  The back
///   controller adds [ScrewController.backLeapfrogBiasMm] on top.
double adjustmentGapMm(int cornerIndex, List<double> z) {
  assert(z.length >= 4);
  switch (cornerIndex) {
    case 0:
      return z[2] - z[0]; // FL low → positive
    case 1:
      return z[3] - z[1]; // FR low → positive
    default:
      return (z[0] + z[1]) / 2 - z[cornerIndex];
  }
}

/// Adaptive force→Z coupling controller for ONE leveling screw.
/// Instantiate one per screw (FL, FR, back) — coupling is a physical
/// property of each screw's lever geometry and must not cross-mix.
///
/// SIGN CONVENTIONS (fixed by the hardware, documented once here):
///   * Probe forces are compressive and NEGATIVE (gram-force).
///   * Tightening a screw makes its corner force MORE negative
///     (ΔF < 0) and raises the corner relative to its reference plane.
///   * The gap is defined as `referenceZ − cornerZ` (see
///     [adjustmentGapMm]): positive → adjusted corner too low.
///   * Tightening therefore SHRINKS a positive gap, so the coupling
///     (relative Z movement per gram-force) is ALWAYS negative.
///
/// The controller works entirely in GAP space, not raw corner Z.
/// Adjusting a screw pivots the plate, so the reference corners move
/// opposite to the adjusted corner — the gap responds 2–3× more than
/// the raw corner Z.  Measuring coupling on raw Z (as earlier
/// revisions did) systematically underestimates sensitivity and
/// commands 2–3× too much force.  The gap also cancels the
/// common-mode Z frame drift between rechecks (±0.05 mm and more).
///
/// The coupling sample denominator is the COMMANDED force delta: the
/// live gauge is anchored to the same re-probe the command was computed
/// from and the user drives it into a ±20 gf green zone, so the
/// commanded delta is exact by construction.  (Earlier revisions
/// differenced two probe force readings, whose ±300–500 gf noise is the
/// same order as the delta itself and could even flip its sign.)
class ScrewController {
  /// Per-screw controller tuning:
  /// * [seedCouplingMmPerGf] — first-cycle coupling before any measured
  ///   sample arrives.  The class default (−5e-4) is a conservative
  ///   generic guess; the wizard passes per-screw values derived from
  ///   fleet telemetry (back −2e-4, fronts −3e-4 — 1.5× sensitivity
  ///   margin from the first instrumented printer's measurements).
  /// * [dampingRatio] — fraction of the gap corrected per cycle.
  ///   Default 0.7: partial steps are safe with the fixed estimator
  ///   and keep gauge targets comfortable on moderate-to-soft plates.
  /// * [targetBiasMm] — added to every correction target.  The back
  ///   screw uses [backLeapfrogBiasMm], a small overshoot past the
  ///   front plane, to keep follow-up front corrections tighten-only
  ///   while avoiding bias-dominated gauge targets.
  ScrewController({
    this.seedCouplingMmPerGf = -5e-4,
    this.dampingRatio = 0.7,
    this.targetBiasMm = 0.0,
  }) : _coupling = seedCouplingMmPerGf;

  final double seedCouplingMmPerGf;
  final double dampingRatio;
  final double targetBiasMm;

  /// Leapfrog overshoot for the back screw (mm): tighten the back edge
  /// this far PAST the front plane so the fronts always catch up by
  /// tightening.  Reduced from the legacy 0.1 mm after field session
  /// 363b3a57 — the bias component dominated back commands on soft-
  /// coupling plates and the tighten-only fallback now provides a
  /// structural backstop that the original policy coded in this knob.
  static const double backLeapfrogBiasMm = 0.02;

  /// Absolute force delta ceiling shown on the gauge (gf).
  static const double maxForceDeltaGf = 3000.0;

  /// Commands smaller than this are never used to update the estimate:
  /// the numerator SNR would be dominated by the ±0.06 mm gap noise,
  /// and deltas this small only occur when the gap is nearly closed.
  /// Lowered from 150 after repeat below-resolution reports; 100 keeps
  /// margin above the ±20 gf gauge green zone.
  static const double minCommandDeltaGf = 100.0;

  /// Gap movement below this is treated as "the plate did not move"
  /// (stiction / thread backlash) rather than a measurable response.
  /// This is below the worst-case gap noise, but any commanded back
  /// adjustment targets ≥ 0.075 mm of motion, so the gate only has to
  /// distinguish "moved" from "didn't".
  static const double minMeasurableMoveMm = 0.02;

  /// Plausibility band for accepted coupling samples (mm/gf).  Brackets
  /// the observed field range [−7.5e-4, −2.5e-5] with margin.
  static const double couplingMostSensitive = -8e-4;
  static const double couplingStiffest = -2e-5;

  /// Smoothing for samples after the first (the first measured sample
  /// replaces the seed outright — the seed carries no printer info).
  static const double emaAlpha = 0.5;

  /// On a stiction cycle the coupling estimate is multiplied by this,
  /// tripling the next commanded force until movement is measurable.
  static const double stictionFactor = 1.0 / 3.0;

  /// Stiction escalations allowed per session — bounds the damage when
  /// "no movement" is really a user not turning the screw.
  static const int maxStictionEscalations = 4;

  /// Corner-check pass threshold (mm), used for recheck prediction.
  static const double passGapMm = 0.100;
  static const int maxPredictedRechecks = 20;

  double _coupling;
  bool _hasMeasuredSample = false;
  int _stictionEscalations = 0;
  double? _pendingGapMm;
  double? _pendingDeltaGf;

  /// Current coupling estimate (mm/gf, always negative).
  double get coupling => _coupling;

  /// Whether [coupling] is backed by at least one accepted measurement
  /// (false → it is still the seed, possibly stiction-scaled).
  bool get hasMeasuredSample => _hasMeasuredSample;

  int get stictionEscalations => _stictionEscalations;

  bool get hasPendingCommand => _pendingDeltaGf != null;

  /// Adopt [coupling] from another screw's measured sample as a better
  /// starting point than the generic seed — materially different from a
  /// first-cycle blind guess because all screws on the same plate share
  /// similar coupling geometry (within ~2× in the field).  No-op when a
  /// measured sample already exists.
  void adoptSeed(double couplingFromSibling) {
    if (_hasMeasuredSample) return;
    _coupling = couplingFromSibling
        .clamp(couplingMostSensitive, couplingStiffest)
        .toDouble();
  }

  /// Compute the force command for the current gap.  Pure — does not
  /// change controller state; call [recordCommand] once the command is
  /// actually shown to the user.
  ScrewCommand command({required double zGapMm}) {
    final targetZMm = zGapMm * dampingRatio + targetBiasMm;
    final rawDelta = targetZMm / _coupling;
    final forceDeltaGf =
        rawDelta.clamp(-maxForceDeltaGf, maxForceDeltaGf).toDouble();
    final clamped = rawDelta.abs() > maxForceDeltaGf;

    // Clamp-aware recheck prediction: per cycle the gap shrinks by the
    // damped target or by the most the force ceiling can move it,
    // whichever is smaller.  (The leapfrog bias is intentionally left
    // out — it shifts the resting point, not the convergence rate.)
    var g = zGapMm.abs();
    var rechecks = 0;
    final maxMovePerCycle = _coupling.abs() * maxForceDeltaGf;
    while (g > passGapMm && rechecks < maxPredictedRechecks) {
      g -= math.min(g * dampingRatio, maxMovePerCycle);
      rechecks++;
    }

    return ScrewCommand(
      zGapMm: zGapMm,
      targetZMm: targetZMm,
      forceDeltaGf: forceDeltaGf,
      clamped: clamped,
      couplingUsedMmPerGf: _coupling,
      predictedGapAfterMm: zGapMm - _coupling * forceDeltaGf,
      predictedRechecks: rechecks,
    );
  }

  /// Snapshot a command that was shown to the user, so the next
  /// [onRecheck] can measure what it achieved.  A repeated call
  /// overwrites the previous pending command.
  void recordCommand(ScrewCommand cmd) {
    _pendingGapMm = cmd.zGapMm;
    _pendingDeltaGf = cmd.forceDeltaGf;
  }

  /// Discard the pending command without updating the estimate (e.g.
  /// when the recheck is missing the data needed to measure it).
  void abandonPending() {
    _pendingGapMm = null;
    _pendingDeltaGf = null;
  }

  /// Update the coupling estimate from a completed recheck.
  ///
  /// [achievedDeltaGf] is the force delta the user ACTUALLY applied
  /// (live gauge reading minus the anchor, in the probe frame).  When
  /// available it is the sample denominator — physics responds to
  /// what was applied, not what was asked — so a user who ignores the
  /// gauge (stops early, overshoots) cannot corrupt the estimate.
  /// Falls back to the commanded delta when no live reading exists.
  CouplingUpdateResult onRecheck({
    required double newGapMm,
    double? achievedDeltaGf,
  }) {
    final pendingGap = _pendingGapMm;
    final pendingDelta = _pendingDeltaGf;
    _pendingGapMm = null;
    _pendingDeltaGf = null;

    if (pendingGap == null || pendingDelta == null) {
      return CouplingUpdateResult._(
        outcome: CouplingUpdateOutcome.noPendingCommand,
        couplingAfterMmPerGf: _coupling,
      );
    }

    // The force delta that was actually applied to the screw.
    final appliedDelta = achievedDeltaGf ?? pendingDelta;

    // Relative movement of the adjusted corner toward its reference:
    // positive when the gap shrank in the commanded sense.
    final gapMove = pendingGap - newGapMm;

    if (appliedDelta.abs() < minCommandDeltaGf) {
      // Too little force applied to yield a usable sample.  With a
      // live gauge reading this also covers "the user skipped the
      // turn" — which must NOT escalate as stiction (the plate was
      // never pushed).
      return CouplingUpdateResult._(
        outcome: CouplingUpdateOutcome.rejectedSmallDelta,
        commandedDeltaGf: pendingDelta,
        gapAtCommandMm: pendingGap,
        measuredGapMoveMm: gapMove,
        couplingAfterMmPerGf: _coupling,
      );
    }

    if (gapMove.abs() < minMeasurableMoveMm) {
      // Substantial force genuinely applied but the plate did not
      // measurably move: stiction or thread backlash.  Assume the
      // printer is stiffer than estimated and triple the next command.
      if (_stictionEscalations < maxStictionEscalations) {
        _stictionEscalations++;
        final escalated = _coupling * stictionFactor;
        _coupling = escalated.abs() < couplingStiffest.abs()
            ? couplingStiffest
            : escalated;
      }
      return CouplingUpdateResult._(
        outcome: CouplingUpdateOutcome.stictionEscalated,
        commandedDeltaGf: pendingDelta,
        gapAtCommandMm: pendingGap,
        measuredGapMoveMm: gapMove,
        couplingAfterMmPerGf: _coupling,
      );
    }

    final sample = gapMove / appliedDelta;
    if (sample >= 0) {
      // Physically impossible sign (tighten must shrink the gap):
      // measurement noise or the screw was turned the wrong way.
      // Keep the prior estimate.
      return CouplingUpdateResult._(
        outcome: CouplingUpdateOutcome.rejectedPositiveSample,
        commandedDeltaGf: pendingDelta,
        gapAtCommandMm: pendingGap,
        measuredGapMoveMm: gapMove,
        sample: sample,
        couplingAfterMmPerGf: _coupling,
      );
    }

    final clampedSample = sample
        .clamp(couplingMostSensitive, couplingStiffest)
        .toDouble();
    final wasClamped = clampedSample != sample;

    if (_hasMeasuredSample) {
      _coupling = _coupling * (1.0 - emaAlpha) + clampedSample * emaAlpha;
    } else {
      // First real measurement replaces the seed outright — averaging
      // against a value that carries no printer information would just
      // slow convergence (a 20×-off stiff printer would need ~4 cycles
      // to shake off the seed).
      _coupling = clampedSample;
      _hasMeasuredSample = true;
    }

    return CouplingUpdateResult._(
      outcome: wasClamped
          ? CouplingUpdateOutcome.acceptedClamped
          : CouplingUpdateOutcome.accepted,
      commandedDeltaGf: pendingDelta,
      gapAtCommandMm: pendingGap,
      measuredGapMoveMm: gapMove,
      sample: sample,
      couplingAfterMmPerGf: _coupling,
    );
  }
}

/// A force command for a leveling screw, expressed both as the desired
/// relative Z correction and the gauge force delta that should achieve it.
class ScrewCommand {
  const ScrewCommand({
    required this.zGapMm,
    required this.targetZMm,
    required this.forceDeltaGf,
    required this.clamped,
    required this.couplingUsedMmPerGf,
    required this.predictedGapAfterMm,
    required this.predictedRechecks,
  });

  /// Gap (see [adjustmentGapMm]) the command was computed from.
  final double zGapMm;

  /// Damped correction target (signed, gap-mm).
  final double targetZMm;

  /// Signed force delta for the gauge; negative = tighten.
  final double forceDeltaGf;

  /// Whether [forceDeltaGf] hit the ±[ScrewController.maxForceDeltaGf]
  /// ceiling.
  final bool clamped;

  /// Coupling estimate used to compute this command (mm/gf).
  final double couplingUsedMmPerGf;

  /// Gap expected after the user reaches the force target.
  final double predictedGapAfterMm;

  /// Estimated rechecks (including the upcoming one) until the gap is
  /// within [ScrewController.passGapMm].
  final int predictedRechecks;
}

enum CouplingUpdateOutcome {
  accepted,
  acceptedClamped,
  rejectedPositiveSample,
  rejectedSmallDelta,
  stictionEscalated,
  noPendingCommand,
}

/// Outcome of measuring a completed adjustment cycle, for telemetry.
class CouplingUpdateResult {
  const CouplingUpdateResult._({
    required this.outcome,
    required this.couplingAfterMmPerGf,
    this.commandedDeltaGf,
    this.gapAtCommandMm,
    this.measuredGapMoveMm,
    this.sample,
  });

  final CouplingUpdateOutcome outcome;
  final double? commandedDeltaGf;
  final double? gapAtCommandMm;

  /// Relative back-vs-front movement achieved (gapAtCommand − newGap).
  final double? measuredGapMoveMm;

  /// Raw coupling sample before clamping (mm/gf), when computable.
  final double? sample;

  final double couplingAfterMmPerGf;

  bool get accepted =>
      outcome == CouplingUpdateOutcome.accepted ||
      outcome == CouplingUpdateOutcome.acceptedClamped;
}
