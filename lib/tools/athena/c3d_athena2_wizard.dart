/*
* Orion - Athena 2 Leveling Wizard
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
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:orion/backend_service/athena_iot/models/force_leveling_workflow.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/backend_service/providers/analytics_provider.dart';
import 'package:orion/backend_service/providers/manual_provider.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/tools/athena/screw_calibration_store.dart';
import 'package:orion/tools/athena/screw_controller.dart';
import 'package:orion/tools/athena/leveling_configs.dart';
import 'package:orion/tools/athena/screen_type_visual.dart';
import 'package:orion/tools/athena/leveling_log_entry.dart';
import 'package:orion/tools/athena/leveling_log_service.dart';
import 'package:orion/tools/athena/svg_cache.dart';
import 'package:orion/tools/athena/leveling_workflow_engine.dart';
import 'package:orion/tools/athena/uv_safety_timer.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/safe_home.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum _WizardPhase {
  variant,
  screenType,
  introAndChecklist,
  workflow,
  adjustment,
}

enum _AdjustmentStep {
  intro,
  hexShortEnd,
  preparing,
  puckPlacement,
  probing,
  feedback,
  belowResolution,
  mechanicalSkew,
}

/// A screw command anchored into the gauge's force frame: the
/// controller's command plus the re-probed corner force it was anchored
/// to and the resulting absolute force target shown to the user.
class _PendingScrewCommand {
  const _PendingScrewCommand(
    this.cmd, {
    required this.anchorForceGf,
    required this.targetForceGf,
  });

  final ScrewCommand cmd;
  final double anchorForceGf;
  final double targetForceGf;
}

class Athena2LevelingWizard extends StatefulWidget {
  const Athena2LevelingWizard({
    super.key,
    required this.config,
    this.recheck = false,
  });

  final LevelingConfig config;
  final bool recheck;

  @override
  State<Athena2LevelingWizard> createState() => _Athena2LevelingWizardState();
}

class _Athena2LevelingWizardState extends State<Athena2LevelingWizard> {
  late final LevelingWorkflowEngine _engine;
  _WizardPhase _phase = _WizardPhase.variant;
  bool _busyStop = false;
  static const _minRunningDuration = Duration(milliseconds: 1500);

  // Pre-flight step-through: -1 = intro view, 0..N-1 = individual steps
  int _preFlightIndex = -1;

  // Minimum running display duration
  DateTime? _runningSince;
  bool _holdingRunning = false;
  bool _waitingForSettle = false;

  // Suppresses the brief idle-step flash between auto-advance and auto-run
  bool _autoAdvancing = false;

  // Intermediate screen flags
  bool _loosenScrewsDone = false;
  bool _tightenScrewsDone = false;
  bool _alignDone = false;
  bool _hexLongEndDone = false;

  // Prevents the home-after-leveling command from firing more than once
  bool _homeAfterCompleteFired = false;

  // Leveling log session tracking
  String? _levelingSessionId;
  int _recheckNumber = 0;
  bool _probeConfigCaptured = false;

  // Screen type selected during the wizard (tempered glass vs. wave
  // release film).  Null until chosen (or loaded from config in recheck).
  LevelingScreenType? _screenType;
  LevelingScreenType? get screenType => _screenType;

  // Adaptive force→Z coupling, one controller per physical screw
  // (0=FL, 1=FR, 2=shared back).  Coupling is a property of each
  // screw's lever geometry and must not cross-mix.  Each controller
  // snapshots its commanded force delta so the recheck can measure
  // what was actually achieved.  See ScrewController for the sign
  // conventions and the estimator design.
  //
  // Baseline seeds are field-derived: the first instrumented printer
  // measured back −1.37e-4 / fronts −2.0e-4, with ~1.5× sensitivity
  // margin so a softer unit undershoots one cycle rather than
  // oscillating.  The per-machine calibration file and/or the first
  // measured sample replace these outright.
  static const double _frontBaselineSeed = -3.0e-4;
  static const double _backBaselineSeed = -2.0e-4;

  /// If the suggested screw adjustment exceeds this force delta (gf), the
  /// arm itself is mechanically skewed — no screw turn can physically apply
  /// that much.  Surface an error instead of sending the user to the gauge.
  /// Threshold is 2500 gf (gauge ceiling) — only triggers when the command
  /// would clamp. Gap gate + two-strike debounce (see _enterAdjustmentMode
  /// / _runAdjustmentProbe) keep single noisy probes from surfacing.
  static const double _maxSuggestedForceDeltaGf = 2500;
  static const double _mechanicalSkewGapThresholdMm = 0.50;
  static Map<int, ScrewController> _freshControllers() => {
        0: ScrewController(seedCouplingMmPerGf: _frontBaselineSeed),
        1: ScrewController(seedCouplingMmPerGf: _frontBaselineSeed),
        2: ScrewController(
          seedCouplingMmPerGf: _backBaselineSeed,
          targetBiasMm: ScrewController.backLeapfrogBiasMm,
        ),
      };

  Map<int, ScrewController> _screwControllers = _freshControllers();
  int? _lastAdjustedCorner;
  int? _puckPlacedCorner; // corner that still has the puck from adjustment
  bool _adjustmentIntroShown = false;
  Future<bool>? _recheckHomeFuture; // home started during preflight
  _PendingScrewCommand? _pendingCommand;
  double?
      _lastAchievedForceGf; // what the live gauge read when the user stopped
  double?
      _preAdjustmentDeviation; // snapshot before adjustment for divergence detection
  int _consecutiveBackAdjustments = 0; // detect maxed-out back screw
  int _consecutiveSkewHits =
      0; // debounce mechanical-skew: needs 2 consecutive hits + gap gate

  // Persisted per-screw coupling calibration — coupling is a physical
  // property of the plate, so sessions start from the previous
  // session's measurements instead of the generic seed.
  final ScrewCalibrationStore _calibrationStore = ScrewCalibrationStore();
  static const _screwStoreKeys = {0: 'fl', 1: 'fr', 2: 'back'};

  /// Seed the (fresh) controllers from the stored calibration.
  Future<void> _loadScrewCalibration() async {
    final stored = await _calibrationStore.load();
    if (!mounted) return;
    for (final entry in _screwStoreKeys.entries) {
      final coupling = stored[entry.value];
      if (coupling != null) {
        _screwControllers[entry.key]!.adoptSeed(coupling);
      }
    }
  }

  /// The controller for the screw that drives [cornerIndex]
  /// (both back corners share one screw).  Cross-seeds an unmeasured
  /// controller from a sibling with a measured coupling — the screws
  /// on one plate share similar geometry, and this saves the
  /// half-effective relearning cycle each screw otherwise pays on its
  /// first adjustment (session 27e976fe: FR and FL first commands
  /// moved only 46% / 35% of target from the generic seed while the
  /// back screw already knew the plate's coupling).
  ScrewController _controllerForCorner(int cornerIndex) {
    final controller = _screwControllers[cornerIndex >= 2 ? 2 : cornerIndex]!;
    if (!controller.hasMeasuredSample) {
      for (final sibling in _screwControllers.values) {
        if (sibling.hasMeasuredSample) {
          controller.adoptSeed(sibling.coupling);
          break;
        }
      }
    }
    return controller;
  }

  // Prediction summary — shown to the user before they turn the screw
  String? _predictionDirection; // e.g. "Tighten"
  String? _predictionScrew; // e.g. "Back Screw"
  double? _predictionZMm; // expected Z change magnitude
  int? _predictionRechecks; // estimated rechecks remaining to pass

  // Corner measurements from probe steps.
  // Indexed by cornerLabel, not probe order — slots are:
  // 0=Front Left, 1=Front Right, 2=Back Right, 3=Back Left.
  final List<ForceLevelingWorkflowResponse?> _cornerResults =
      List.filled(4, null);

  // Per-corner Z samples keyed by the step id that produced them.
  // Keying by step id keeps retries idempotent, and [_cornerZ]
  // averages the values — so a future multi-probe check is a
  // config-only change.
  final List<Map<String, double>> _cornerZByStep =
      List.generate(4, (_) => <String, double>{});

  /// Averaged probed Z for a corner (mm), or null if never probed.
  double? _cornerZ(int i) {
    final samples = _cornerZByStep[i].values;
    if (samples.isEmpty) {
      return _cornerResults[i]?.measurements?.secondStageTriggerZ;
    }
    return samples.reduce((a, b) => a + b) / samples.length;
  }

  static const _cornerLabelToIndex = {
    'Front Left': 0,
    'Front Right': 1,
    'Back Right': 2,
    'Back Left': 3,
  };

  // Adjustment mode state
  int? _adjustingCornerIndex;
  bool _adjustmentBusy = false;
  String? _adjustmentError;
  bool _wizardDisposed = false;
  _AdjustmentStep _adjustmentStep = _AdjustmentStep.preparing;
  // Safety net for the projector's UV special screens: any screen that is
  // shown auto-shuts off 30s later unless the wizard proceeds first.
  late final UvSafetyTimer _uvSafetyTimer;
  static const _cornerLocations = [
    'front-left',
    'front-right',
    'back-right',
    'back-left',
  ];

  @override
  void initState() {
    super.initState();
    _engine = LevelingWorkflowEngine()..addListener(_handleEngineUpdate);
    _uvSafetyTimer = UvSafetyTimer(() {
      BackendService().turnOffSpecialScreens().then((_) {}).catchError((_) {});
    });

    // Prevent standby from activating while the leveling wizard is open.
    // Defer to avoid notifyListeners() during the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<StatusProvider>(context, listen: false)
            .setLevelingWorkflowActive(true);
      }
    });

    // Warm SVG cache so pictograms appear instantly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) LevelingSvgCache.precache(context);
    });

    if (widget.recheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRecheckMode();
      });
    } else {
      // If arm and screen were already chosen, skip those panes on
      // subsequent runs — user can change them in Leveling Settings.
      // Do it synchronously so the first frame is already the correct
      // phase (no flash of the variant selector).
      final savedVariantId = OrionConfig().getLevelingVariant();
      if (savedVariantId.isNotEmpty) {
        LevelingVariant? savedVariant;
        for (final v in widget.config.variants) {
          if (v.id == savedVariantId) {
            savedVariant = v;
            break;
          }
        }
        if (savedVariant != null) {
          _engine.selectVariant(savedVariant);
          _resetCornerResults();
          _alignDone = savedVariant.id == 'regular';
          _hexLongEndDone = false;
          _levelingSessionId = _uuid4();
          _recheckNumber = 0;
          _probeConfigCaptured = false;
          _screwControllers = _freshControllers();
          _pendingCommand = null;
          _lastAchievedForceGf = null;
          _lastAdjustedCorner = null;
          _consecutiveSkewHits = 0;
          _consecutiveBackAdjustments = 0;
          _loadScrewCalibration();
          final savedScreenId = OrionConfig().getScreenType();
          final savedScreen = LevelingScreenType.fromId(
              savedScreenId.isNotEmpty ? savedScreenId : null);
          if (savedScreen != null) {
            _screenType = savedScreen;
            _engine.setScreenType(savedScreen);
            _phase = _WizardPhase.introAndChecklist;
            _preFlightIndex = -1;
          } else {
            _phase = _WizardPhase.screenType;
            _preFlightIndex = -1;
          }
        }
      }
    }
  }

  void _startRecheckMode() {
    // Auto-select the Pro variant, skip loosen/tighten screens, but
    // still show the pre-flight checklist before probing begins.
    final proVariant = widget.config.variants.firstWhere(
      (v) => v.id == 'pro',
      orElse: () => widget.config.variants.first,
    );
    _engine.selectVariant(proVariant);
    _loosenScrewsDone = true;
    _tightenScrewsDone = true;
    _levelingSessionId = _uuid4();
    _recheckNumber = 0;
    _probeConfigCaptured = false;
    _screwControllers = _freshControllers();
    _pendingCommand = null;
    _lastAchievedForceGf = null;
    _lastAdjustedCorner = null;
    _consecutiveSkewHits = 0;
    _consecutiveBackAdjustments = 0;
    _resetCornerResults();
    _loadScrewCalibration();
    // Recheck doesn't re-ask the screen type — reuse the persisted one.
    _screenType = LevelingScreenType.fromId(OrionConfig().getScreenType());
    _engine.setScreenType(_screenType);

    // Start at pre-flight so the user sees the safety checklist first.
    setState(() {
      _phase = _WizardPhase.introAndChecklist;
      _preFlightIndex = 0;
    });

    // Prepare the machine while the user reads the checklist.  The
    // recheck flow skips the Stage-1 `probe_prepare` step, which is what
    // clears the previous session's Z offset before probing.  A bare
    // manual home does NOT clear that offset — with it still applied, the
    // first probe move's target falls outside the axis limits and Klipper
    // aborts with "move out of range" at ~10 mm.  Running `probe_prepare`
    // up front puts the machine in the same clean state a fresh leveling
    // session starts from.
    _recheckHomeFuture = _prepareForRecheck(context);
  }

  /// Runs the backend `probe_prepare` workflow step — the same
  /// preparation the normal flow performs as Stage-1 step 0 — then waits
  /// for the axis to physically settle.  This clears the previous
  /// session's Z offset and homes the axis so the first corner probe
  /// starts from a known, clean state.
  ///
  /// Returns false (without throwing) if the backend call failed, so the
  /// recheck can still attempt to proceed — `probe_screen` may recover.
  Future<bool> _prepareForRecheck(BuildContext context) async {
    try {
      final response = await BackendService().runForceLevelingWorkflow(
        'probe_prepare',
        requestTimeout: const Duration(seconds: 90),
      );
      if (!response.result) return false;
    } catch (_) {
      return false;
    }
    if (!context.mounted) return true;
    return safeHomePoll(context);
  }

  @override
  void dispose() {
    _wizardDisposed = true;
    // Deliberately NOT disarming _uvSafetyTimer: a special screen may still
    // be projected when the wizard closes (cancel/back), and the timer is
    // the guarantee that the UV shuts off within the safety window. Its
    // callback touches no widget state, so firing after dispose is safe.
    _engine.removeListener(_handleEngineUpdate);
    _engine.dispose();
    // Re-allow standby now that the wizard is closed
    if (context.mounted) {
      Provider.of<StatusProvider>(context, listen: false)
          .setLevelingWorkflowActive(false);
    }
    super.dispose();
  }

  void _handleEngineUpdate() {
    if (!mounted || _wizardDisposed) return;
    if (_engine.isRunning) {
      _autoAdvancing = false;
      _runningSince ??= DateTime.now();
      _holdingRunning = false;
      _loosenScrewsDone = false;
      _tightenScrewsDone = false;
      // Standard arm is rigidly fixed — the plate can't be misaligned,
      // so the align-plate intermediate screen is never needed for it.
      _alignDone = _engine.variant?.id == 'regular';
      _hexLongEndDone = false;
    } else if (_engine.status == LevelingWorkflowStatus.stepComplete) {
      final step = _engine.currentStep;
      if (step != null) {
        // Save measurements from probe steps, keyed by cornerLabel so
        // retries and back-navigation can't misalign the slot mapping.
        if (step.cornerLabel != null && _engine.lastResponse != null) {
          final idx = _cornerLabelToIndex[step.cornerLabel!];
          if (idx != null && idx >= 0 && idx < 4) {
            _cornerResults[idx] = _engine.lastResponse;
            // Record the corner's Z sample keyed by step id (a retried
            // step overwrites its own sample instead of duplicating it).
            final z = _engine.lastResponse!.measurements?.secondStageTriggerZ;
            if (z != null) {
              _cornerZByStep[idx][step.id] = z;
            }
            // Capture probe config from the first corner response that has it
            if (!_probeConfigCaptured &&
                _engine.lastResponse!.measurements != null) {
              _probeConfigCaptured = true;
            }
          }
        }

        // Fire special screens
        if (step.specialScreen != null) {
          if (step.specialScreen == 'center') {
            BackendService()
                .showSpecialScreenCenter()
                .then((_) {})
                .catchError((_) {});
            _uvSafetyTimer.arm();
          } else if (step.specialScreen!.startsWith('corner-')) {
            final cornerIdx =
                int.tryParse(step.specialScreen!.split('-')[1]) ?? 0;
            if (cornerIdx >= 0 && cornerIdx < 4) {
              // The puck is already at this corner from the prior
              // adjustment — no pattern needed, and the step auto-advances
              // into probing right after.
              if (cornerIdx != _puckPlacedCorner) {
                BackendService()
                    .showSpecialScreenCorner(_cornerLocations[cornerIdx])
                    .then((_) {})
                    .catchError((_) {});
                _uvSafetyTimer.arm();
              }
            }
          }
        }

        // Standard arm: floor the Z to seat the plate before tightening.
        if (step.intermediateScreen == 'tighten' &&
            step.skipBackend &&
            _engine.variant?.id == 'regular') {
          safeFloor(context).then((_) {}).catchError((_) {});
        }

        // While showing the remove-puck prompt, run the prepare endpoint
        // in the background so the plate moves up for easy puck removal.
        if (step.intermediateScreen == 'removePuck') {
          BackendService()
              .runForceLevelingWorkflow('probe_corner_prepare',
                  requestTimeout: const Duration(seconds: 90))
              .then((_) {})
              .catchError((_) {});
        }

        // After a prepare step (home / move-to-position), wait for the
        // axis to physically settle before showing any intermediate
        // screen.  Klipper reports homed=true early.
        if (step.kind == LevelingWorkflowStepKind.prepare) {
          _waitingForSettle = true;
          safeHomePoll(context).then((_) {
            if (mounted) setState(() => _waitingForSettle = false);
          });
        }

        // Log corner check results when all 4 corners are measured.
        if (step.intermediateScreen == 'allCorners' &&
            _levelingSessionId != null) {
          _logCornerCheck();
          // Puck is at the last probed corner (BL, index 3) after a full sweep.
          _puckPlacedCorner = 3;
        }

        // Auto-advance through steps that don't need user interaction
        if (step.autoAdvance) {
          _engine.advanceAfterSuccessfulStep();
          // Also auto-run the next step if it's a prepare move, final offset,
          // or a skipBackend/intermediate step (e.g. corner results).
          // (but only if the workflow isn't complete)
          if (!_engine.isComplete) {
            final nextStep = _engine.currentStep;
            if (nextStep != null &&
                (nextStep.kind == LevelingWorkflowStepKind.finalOffset ||
                    nextStep.kind == LevelingWorkflowStepKind.prepare ||
                    nextStep.skipBackend)) {
              _autoAdvancing = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _engine.runCurrentStep();
              });
            }
          }
        }
      }

      // In recheck mode, probe_screen just calibrated the sensor.
      // Now jump to corner probing — skip loosen/tighten intermediates.
      if (widget.recheck &&
          step != null &&
          step.id == 'probe_screen' &&
          _engine.status == LevelingWorkflowStatus.stepComplete) {
        _tightenScrewsDone = true; // suppress tighten screen on next rebuild
        _engine.jumpToFirstStepId('fine_prepare_');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _engine.canRunCurrentStep) {
            _engine.runCurrentStep();
          }
        });
      }
    }

    // ── Puck-location skip ──
    // If the puck is already at this corner from a prior adjustment,
    // auto-advance past the placement screen straight to probing.
    if (_puckPlacedCorner != null &&
        _engine.status == LevelingWorkflowStatus.stepComplete) {
      final step = _engine.currentStep;
      if (step != null &&
          step.kind == LevelingWorkflowStepKind.prepare &&
          step.id.startsWith('fine_prepare_')) {
        final cornerNum =
            int.tryParse(step.id.replaceFirst('fine_prepare_', '')) ?? 0;
        final cornerIndex = cornerNum - 1; // fine_prepare_1 → corner 0
        if (cornerIndex == _puckPlacedCorner) {
          _puckPlacedCorner = null;
          _engine.advanceAfterSuccessfulStep();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _engine.canRunCurrentStep) {
              _engine.runCurrentStep();
            }
          });
        } else {
          // Puck was at a different corner — the first prepare didn't
          // match, so clear the stale location.  The optimization only
          // fires once per sweep.
          _puckPlacedCorner = null;
        }
      }
    }

    // Home the machine once when the leveling workflow completes
    if (_engine.status == LevelingWorkflowStatus.complete &&
        !_homeAfterCompleteFired) {
      _homeAfterCompleteFired = true;
      // The workflow applied a fresh Z offset, so the printer is leveled
      // again.  (A Verify Leveling run resets this to false at start.)
      OrionConfig().setLeveled(true);
      // Re-anchor the leveling-settings edit range to the newly applied
      // offset and clear any manual override so it doesn't compound.
      final applied = _engine.zOffsetApplied;
      if (applied != null) {
        OrionConfig().setBaseZOffset(applied);
        OrionConfig().setZOffsetOverride(0);
      }
      Provider.of<ManualProvider>(context, listen: false)
          .moveToTop()
          .then((_) {})
          .catchError((_) {});
    }

    // Minimum running duration — always checked, independent of status
    if (!_engine.isRunning && _runningSince != null && !_holdingRunning) {
      final elapsed = DateTime.now().difference(_runningSince!);
      if (elapsed < _minRunningDuration) {
        _holdingRunning = true;
        Future.delayed(_minRunningDuration - elapsed, () {
          if (mounted) setState(() => _holdingRunning = false);
        });
      }
      _runningSince = null;
    }
    if (mounted) setState(() {});
  }

  bool get _effectivelyRunning =>
      _engine.isRunning ||
      _holdingRunning ||
      _autoAdvancing ||
      _waitingForSettle;

  void _goBack() {
    switch (_phase) {
      case _WizardPhase.variant:
        Navigator.of(context).pop();
        return;
      case _WizardPhase.screenType:
        setState(() {
          _phase = _WizardPhase.variant;
          _preFlightIndex = -1;
        });
        return;
      case _WizardPhase.introAndChecklist:
        if (_preFlightIndex >= 0) {
          setState(() => _preFlightIndex -= 1);
        } else {
          setState(() {
            _phase = _WizardPhase.screenType;
            _preFlightIndex = -1;
          });
        }
        return;
      case _WizardPhase.workflow:
        if (_engine.canGoBack) {
          _engine.previousStep();
        } else {
          setState(() {
            _phase = _WizardPhase.introAndChecklist;
            _preFlightIndex = -1;
          });
          _resetCornerResults();
        }
        return;
      case _WizardPhase.adjustment:
        // Back from adjustment → cancel
        _cancelLeveling();
        return;
    }
  }

  /// Generate a simple UUID v4 string without depending on the `uuid` package.
  static String _uuid4() {
    final r = Random();
    final hex = List.generate(32, (_) => r.nextInt(16).toRadixString(16));
    // Insert dashes at positions 8, 13, 18, 23 and set version/variant bits
    hex[12] = '4'; // version 4
    hex[16] = (8 + r.nextInt(4)).toRadixString(16); // variant 8–b
    return '${hex.sublist(0, 8).join()}-${hex.sublist(8, 12).join()}-${hex.sublist(12, 16).join()}-${hex.sublist(16, 20).join()}-${hex.sublist(20).join()}';
  }

  void _resetCornerResults() {
    for (int i = 0; i < _cornerResults.length; i++) {
      _cornerResults[i] = null;
      _cornerZByStep[i].clear();
    }
    _homeAfterCompleteFired = false;
  }

  // Cantilever compensation constants (currently disabled).
  // Geometry: plate 234×134mm, corners at (±117,±67) from center.
  // Cantilever attaches at rear linear rail 160mm behind center → Y=−160.
  // A simple cantilever beam model gives stiffness ∝ 1/d² at each corner,
  // so Z (probe deflection at trigger) ∝ d².  Back corners serve as the
  // stiff reference row.
  //
  //   FL/FR d² = 117² + (67+160)² = 65218
  //   BL/BR d² = 117² + (160−67)² = 22338
  //   front compensation factor = 22338 / 65218 ≈ 0.34244
  // static const _kCantileverD2Front = 65218.0;
  // static const _kCantileverD2Back = 22338.0;
  // static const _kCantileverFrontComp = _kCantileverD2Back / _kCantileverD2Front;

  /// Return the 4 raw Z values (cantilever compensation disabled).
  /// Corner order: 0=FL, 1=FR, 2=BR, 3=BL.
  List<double> _compensatedCorners(List<double?> rawZ) {
    if (rawZ.length < 4) return [];
    return [
      if (rawZ[0] != null) rawZ[0]!,
      if (rawZ[1] != null) rawZ[1]!,
      if (rawZ[2] != null) rawZ[2]!,
      if (rawZ[3] != null) rawZ[3]!,
    ];
  }

  /// The four averaged corner Z values in corner order (0=FL, 1=FR,
  /// 2=BR, 3=BL), for [_compensatedCorners].
  List<double?> get _rawCornerZs =>
      [_cornerZ(0), _cornerZ(1), _cornerZ(2), _cornerZ(3)];

  double get _cornerDeviation {
    final zValues = _compensatedCorners(_rawCornerZs);
    if (zValues.isEmpty) return 0.0;
    final min = zValues.reduce((a, b) => a < b ? a : b);
    final max = zValues.reduce((a, b) => a > b ? a : b);
    return max - min;
  }

  bool get _isCornerCheckPassed => _cornerDeviation <= 0.100;
  bool get _isBorderline =>
      _cornerDeviation > 0.100 && _cornerDeviation <= 0.200;

  Future<void> _skipAdjustment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GlassAlertDialog(
        title: Row(
          children: [
            Icon(PhosphorIcons.warning(), size: 26, color: Colors.orangeAccent),
            const SizedBox(width: 14),
            Text(
              FlutterI18n.translate(context, 'leveling.wizardSkipTitle'),
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
          ],
        ),
        content: Text(
          FlutterI18n.translate(context, 'leveling.wizardSkipMsg'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        actions: [
          GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 55),
            ),
            child: Text(FlutterI18n.translate(context, 'leveling.cancel')),
          ),
          GlassButton(
            tint: GlassButtonTint.warn,
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 55),
            ),
            child: Text(FlutterI18n.translate(context, 'leveling.wizardSkip')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Jump to the remove-puck step so the user still sees the prompt
    // and the plate lifts for safe puck removal before final offset.
    final removePuckIdx = _engine.steps.indexWhere(
      (s) => s.intermediateScreen == 'removePuck',
    );
    if (removePuckIdx >= 0) {
      _engine.jumpToStep(removePuckIdx);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _engine.canRunCurrentStep) {
          _engine.runCurrentStep();
        }
      });
    }
  }

  void _enterAdjustmentMode() {
    // Developer debug hook: force the mechanical-skew error screen for
    // testing without a physically skewed arm.  Enable via the
    // `forceMechanicalSkew` flag under the `developer` config category.
    if (OrionConfig().getFlag('forceMechanicalSkew', category: 'developer')) {
      _adjustingCornerIndex = null;
      _adjustmentError = null;
      _adjustmentBusy = false;
      setState(() {
        _phase = _WizardPhase.adjustment;
        _adjustmentStep = _AdjustmentStep.mechanicalSkew;
      });
      return;
    }
    // The build arm has 3 screws (2 front, 1 back) defining a plane.
    // With all screws already snug, we need PAIRED adjustments
    // (loosen one, tighten another) to maintain torque balance.
    //
    // Two independent axes:
    //   Front-to-back: both front screws vs back screw
    //   Left-to-right: FL screw vs FR screw
    //
    // Corner indexing: 0=FL, 1=FR, 2=BR, 3=BL
    // Screw mapping:   corners 0-1 → respective front screw
    //                  corners 2-3 → center back screw
    final zValues = _compensatedCorners(_rawCornerZs);
    if (zValues.length < 4) return;

    // Legacy leapfrog pick order (see rankAdjustmentCandidates):
    // front-back tilt → back screw (worst outlier), else the lower
    // corner of the worst diagonal.  Take the first candidate whose
    // command is an executable TIGHTEN: at least the 100 gf execution
    // floor (below it the ±20 gf green zone plus live-force noise make
    // a human turn uncontrolled — field session f2c9f74d recheck #2),
    // and never a loosen (preload policy).
    int? probeCorner;
    ScrewCommand? probeCommand;
    for (final corner in rankAdjustmentCandidates(zValues)) {
      final cmd = _controllerForCorner(corner)
          .command(zGapMm: adjustmentGapMm(corner, zValues));
      if (cmd.forceDeltaGf <= -ScrewController.minCommandDeltaGf) {
        probeCorner = corner;
        probeCommand = cmd;
        break;
      }
    }

    if (probeCorner == null) {
      _consecutiveSkewHits = 0;
      // Every candidate is below the execution floor: the remaining
      // deviation is within measurement/adjustment resolution.  Don't
      // send the user to a screw — offer a recheck instead.
      _adjustingCornerIndex = null;
      _adjustmentError = null;
      _adjustmentBusy = false;
      // No adjustment will happen, so the next recheck must not run
      // divergence detection against a stale baseline.
      _preAdjustmentDeviation = null;
      setState(() {
        _phase = _WizardPhase.adjustment;
        _adjustmentStep = _AdjustmentStep.belowResolution;
      });
      return;
    }

    // A suggested delta larger than the screws can physically apply means
    // the arm itself is mechanically skewed — no screw turn will fix it.
    // Two-strike debounce + gap gate: require |forceDelta| >= 3000,
    // |gap| >= 0.90 mm, and two consecutive hits (pre-gauge + re-probe
    // or two adjustment cycles) to filter single noisy probes.
    if (probeCommand != null &&
        probeCommand.forceDeltaGf.abs() >= _maxSuggestedForceDeltaGf) {
      final gapMm = adjustmentGapMm(probeCorner!, zValues);
      final gapExceeds = gapMm.abs() >= _mechanicalSkewGapThresholdMm;
      if (gapExceeds) {
        _consecutiveSkewHits++;
        if (_consecutiveSkewHits >= 2) {
          _adjustingCornerIndex = null;
          _adjustmentError = null;
          _adjustmentBusy = false;
          setState(() {
            _phase = _WizardPhase.adjustment;
            _adjustmentStep = _AdjustmentStep.mechanicalSkew;
          });
          return;
        }
        // Single hit — defer, let the re-probe confirmation decide.
      } else {
        _consecutiveSkewHits = 0;
      }
    } else {
      _consecutiveSkewHits = 0;
    }

    _adjustingCornerIndex = probeCorner;
    _adjustmentError = null;
    _preAdjustmentDeviation = _cornerDeviation;

    // Track consecutive back-screw picks to detect mechanical limits.
    if (probeCorner >= 2) {
      _consecutiveBackAdjustments++;
    } else {
      _consecutiveBackAdjustments = 0;
    }

    if (!_adjustmentIntroShown) {
      _adjustmentIntroShown = true;
      setState(() {
        _phase = _WizardPhase.adjustment;
        _adjustmentStep = _AdjustmentStep.intro;
      });
      return;
    }

    _adjustmentBusy = true;
    setState(() {
      _phase = _WizardPhase.adjustment;
      _adjustmentStep = _AdjustmentStep.preparing;
    });

    _runAdjustmentPrepare();
  }

  Future<void> _runAdjustmentPrepare() async {
    if (_adjustingCornerIndex == null) return;
    _adjustmentBusy = true;
    if (mounted) setState(() {});

    final puckAlreadyPlaced = _puckPlacedCorner == _adjustingCornerIndex;
    if (puckAlreadyPlaced) {
      _puckPlacedCorner = null;
    }

    try {
      if (puckAlreadyPlaced) {
        // Puck is already at this corner from the last probe — just
        // lift the plate a small amount for hand clearance instead of
        // the full probe_corner_prepare cycle (park then lower).  The
        // rapid up-then-down is a safety hazard when hands may be near
        // the plate and a re-probe is about to start anyway.
        final moved = await Provider.of<ManualProvider>(context, listen: false)
            .moveDelta(10.0);
        if (!mounted) return;
        if (!moved) {
          _adjustmentError =
              FlutterI18n.translate(context, 'leveling.wizardPrepareFailed');
          _adjustmentBusy = false;
          if (mounted) setState(() {});
          return;
        }
      } else {
        // First visit to this corner: the plate sits at probe height
        // from the recheck. Lift for hand/puck access FIRST — showing
        // the puck screen after probe_corner_prepare leaves the plate
        // back down at ~10 mm with no room to place the puck
        // (prepare parks high but lowers again before returning).
        // The move result is advisory: the plate may already be high,
        // and prepare re-parks anyway once the puck is down.
        await Provider.of<ManualProvider>(context, listen: false)
            .moveDelta(50.0);
        if (!mounted) return;
      }

      // Fire the special screen for this corner so the projector shows the position
      final cornerIdx = _adjustingCornerIndex!;
      if (cornerIdx >= 0 && cornerIdx < 4) {
        BackendService()
            .showSpecialScreenCorner(_cornerLocations[cornerIdx])
            .then((_) {})
            .catchError((_) {});
        _uvSafetyTimer.arm();
      }
    } catch (e) {
      _adjustmentError = e.toString();
      _adjustmentBusy = false;
      if (mounted) setState(() {});
      return;
    }

    _adjustmentBusy = false;
    if (puckAlreadyPlaced) {
      _adjustmentStep = _AdjustmentStep.hexShortEnd;
      if (mounted) setState(() {});
      return;
    }
    _adjustmentStep = _AdjustmentStep.puckPlacement;
    if (mounted) setState(() {});
  }

  /// Runs `probe_corner_prepare` after the user confirms puck placement,
  /// then advances to the hex-key prompt. Split out of
  /// [_runAdjustmentPrepare] so the puck is placed at lift height —
  /// prepare parks high but lowers again, and running it first left the
  /// plate at ~10 mm with no room for the puck.
  Future<void> _runPrepareAfterPuck() async {
    _adjustmentBusy = true;
    setState(() {
      _adjustmentStep = _AdjustmentStep.preparing;
    });
    try {
      await BackendService().runForceLevelingWorkflow(
        'probe_corner_prepare',
        requestTimeout: const Duration(seconds: 90),
      );
      if (!mounted) return;
    } catch (e) {
      _adjustmentError = e.toString();
      _adjustmentBusy = false;
      if (mounted) setState(() {});
      return;
    }
    _adjustmentBusy = false;
    setState(() {
      _adjustmentStep = _AdjustmentStep.hexShortEnd;
    });
  }

  Future<void> _runAdjustmentProbe() async {
    if (_adjustingCornerIndex == null) return;

    // The puck is placed — hide the projector pattern before probing.
    _uvSafetyTimer.disarm();
    BackendService().turnOffSpecialScreens().then((_) {}).catchError((_) {});

    _adjustmentBusy = true;
    _adjustmentStep = _AdjustmentStep.probing;
    if (mounted) setState(() {});

    try {
      final response = await BackendService().runForceLevelingWorkflow(
        'probe_corner',
        requestTimeout: const Duration(seconds: 90),
      );
      if (!mounted) return;

      if (!response.result) {
        _adjustmentError = response.error.isNotEmpty
            ? response.error
            : FlutterI18n.translate(context, 'leveling.wizardProbeFailed');
        _adjustmentBusy = false;
        if (mounted) setState(() {});
        return;
      }

      final probedIdx = _adjustingCornerIndex!;
      // The re-probe supersedes this corner's check sample.
      _cornerZByStep[probedIdx].clear();
      final z = response.measurements?.secondStageTriggerZ;
      if (z != null) _cornerZByStep[probedIdx]['adjust_probe'] = z;
      _cornerResults[probedIdx] = response;
    } catch (e) {
      _adjustmentError = e.toString();
      _adjustmentBusy = false;
      if (mounted) setState(() {});
      return;
    }

    // ── Compute the screw command once, anchored to this re-probe ──
    // Done here (not in build) so the target is deterministic across
    // rebuilds and the gauge, the command, and the coupling estimator
    // all share the same force reference frame.
    final idx = _adjustingCornerIndex!;
    _pendingCommand = null;
    _lastAchievedForceGf = null; // fresh adjustment → fresh gauge snapshot
    {
      final zValues = _compensatedCorners(_rawCornerZs);
      final anchorForce =
          _cornerResults[idx]?.measurements?.firstStagePeakForce;
      if (zValues.length >= 4 && anchorForce != null) {
        // Positive gap → adjusted corner too low → tighten.  The
        // adjusted corner's Z comes from the fresh re-probe (its
        // sample was just replaced); the reference corners keep
        // their corner-check values.
        final zGapMm = adjustmentGapMm(idx, zValues);
        final controller = _controllerForCorner(idx);
        final cmd = controller.command(zGapMm: zGapMm);
        // The re-probe may have shrunk the gap below the execution
        // floor — or flipped its sign, which under the tighten-only
        // policy must never turn into a loosen command.
        if (cmd.forceDeltaGf > -ScrewController.minCommandDeltaGf) {
          _consecutiveSkewHits = 0;
          _adjustmentBusy = false;
          _adjustmentStep = _AdjustmentStep.belowResolution;
          // No adjustment will happen — see _enterAdjustmentMode.
          _preAdjustmentDeviation = null;
          if (mounted) setState(() {});
          return;
        }
        // Re-probe may still land on a mechanically skewed suggestion —
        // need two consecutive clamped hits with large gap to surface
        // (debounces single noisy probe). First hit defers to the gauge.
        if (cmd.forceDeltaGf.abs() >= _maxSuggestedForceDeltaGf) {
          final gapExceeds = zGapMm.abs() >= _mechanicalSkewGapThresholdMm;
          if (gapExceeds) {
            _consecutiveSkewHits++;
            if (_consecutiveSkewHits >= 2) {
              _adjustmentBusy = false;
              _adjustmentStep = _AdjustmentStep.mechanicalSkew;
              _preAdjustmentDeviation = null;
              if (mounted) setState(() {});
              return;
            }
            // Single hit — fall through to gauge, let next cycle confirm.
          } else {
            _consecutiveSkewHits = 0;
          }
        } else {
          _consecutiveSkewHits = 0;
        }
        _lastAdjustedCorner = idx;
        _pendingCommand = _PendingScrewCommand(
          cmd,
          anchorForceGf: anchorForce,
          targetForceGf: anchorForce + cmd.forceDeltaGf,
        );
      }
    }

    _adjustmentBusy = false;
    _adjustmentStep = _AdjustmentStep.feedback;
    if (mounted) setState(() {});
  }

  void _logCornerCheck() {
    if (_levelingSessionId == null) return;

    // ── Update the adaptive coupling estimate from the recheck ──
    // Routed to the controller of whichever screw was adjusted; if no
    // adjustment preceded this check there is no pending command and
    // nothing updates.
    CouplingUpdateResult? update;
    ScrewController? adjusted;
    if (_lastAdjustedCorner != null) {
      adjusted = _controllerForCorner(_lastAdjustedCorner!);
      final zValues = _compensatedCorners(_rawCornerZs);
      if (zValues.length >= 4) {
        // Give the estimator the force delta the user ACTUALLY applied
        // (live gauge reading minus the anchor) so a user who ignores
        // the gauge cannot corrupt the learned coupling; null when no
        // live reading was captured (falls back to the commanded
        // delta).
        final anchor = _pendingCommand?.anchorForceGf;
        final achieved = _lastAchievedForceGf;
        final achievedDelta =
            (anchor != null && achieved != null) ? achieved - anchor : null;
        update = adjusted.onRecheck(
          newGapMm: adjustmentGapMm(_lastAdjustedCorner!, zValues),
          achievedDeltaGf: achievedDelta,
        );
      } else {
        // Missing data — never let a stale command pair with a later,
        // unrelated recheck.
        adjusted.abandonPending();
      }
    }
    // Snapshot before clearing the per-adjustment state.
    final savedAdjustedCorner = _lastAdjustedCorner;
    final targetForceGf = _pendingCommand?.targetForceGf;
    final anchorForceGf = _pendingCommand?.anchorForceGf;
    final achievedGf = _lastAchievedForceGf;
    final telemetrySource = adjusted ?? _controllerForCorner(2);
    _lastAdjustedCorner = null;
    _lastAchievedForceGf = null;
    _pendingCommand = null;

    // Persist the updated coupling — a physical plate property that
    // survives session restarts — so the next session starts
    // calibrated instead of relearning from the seed.
    if (update?.accepted == true && savedAdjustedCorner != null) {
      final storeKey =
          _screwStoreKeys[savedAdjustedCorner >= 2 ? 2 : savedAdjustedCorner];
      if (storeKey != null) {
        // Best-effort — the coupling is saved again on the next
        // accepted sample.
        _calibrationStore.save(storeKey, adjusted!.coupling);
      }
    }

    // Which screw the telemetry below refers to.  Fall back to the
    // back controller for checks with no preceding adjustment.
    final screwLabels = ['FL', 'FR', 'BACK', 'BACK'];
    final adjustedScrew =
        savedAdjustedCorner != null ? screwLabels[savedAdjustedCorner] : null;

    final variant = _engine.variant?.id ?? 'unknown';
    final cornerLabels = ['FL', 'FR', 'BR', 'BL'];
    final corners = <String, CornerLogData>{};
    for (int i = 0; i < 4; i++) {
      final m = _cornerResults[i]?.measurements;
      // finalZ comes from the sample accumulator — the value the
      // wizard actually leveled with.
      corners[cornerLabels[i]] = CornerLogData(
        finalZ: _cornerZ(i),
        firstStagePeakForce: m?.firstStagePeakForce,
        secondStagePeakForce: m?.secondStagePeakForce,
        firstStageOvershoot: m?.firstStageOvershoot,
        secondStageOvershoot: m?.secondStageOvershoot,
      );
    }
    // Snapshot probe config from the first corner that has it
    ProbeConfigSnapshot? probeConfig;
    for (final r in _cornerResults) {
      if (r?.measurements != null) {
        final c = ProbeConfigSnapshot.fromMeasurements(r!.measurements);
        // Only include if at least one config field is present
        if (c.firstStageSpeed != null ||
            c.secondStageSpeed != null ||
            c.firstStageLiftHeight != null ||
            c.secondStageLiftHeight != null ||
            c.firstStageThreshold != null ||
            c.secondStageThreshold != null ||
            c.probeStartDistance != null ||
            c.probeRetractDistance != null) {
          probeConfig = c;
          break;
        }
      }
    }
    final entry = LevelingLogEntry(
      sessionId: _levelingSessionId!,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      variant: variant,
      screenType: _screenType?.id,
      recheckNumber: _recheckNumber,
      corners: corners,
      totalDeviationMm: _cornerDeviation,
      passed: _isCornerCheckPassed,
      probeConfig: probeConfig,
      estimatedCoupling: telemetrySource.coupling,
      couplingIsSeed: !telemetrySource.hasMeasuredSample,
      preAdjustmentDeviation: _preAdjustmentDeviation,
      adjustedScrew: adjustedScrew,
      commandedDeltaGf: update?.commandedDeltaGf,
      gapAtCommandMm: update?.gapAtCommandMm,
      measuredGapMoveMm: update?.measuredGapMoveMm,
      couplingSample: update?.sample,
      sampleOutcome: update?.outcome.name,
      stictionEscalations: telemetrySource.stictionEscalations,
      anchorForceGf: anchorForceGf,
      targetForceGf: targetForceGf,
      achievedForceGf: achievedGf,
    );
    LevelingLogService.logCornerCheck(entry);
  }

  void _runRecheckCorners() {
    _recheckNumber++;
    _resetCornerResults();
    _probeConfigCaptured = false;
    // If the user just adjusted a screw, the puck is still at that corner.
    // Skip the "place puck" prompt for the first corner of the re-check.
    _puckPlacedCorner = _lastAdjustedCorner;
    _engine.jumpToFirstStepId('fine_prepare_');
    setState(() => _phase = _WizardPhase.workflow);
    // Auto-run the corner prepare step so the probe positions itself before
    // showing the puck placement screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _engine.canRunCurrentStep) {
        _engine.runCurrentStep();
      }
    });
  }

  void _advancePreFlight() {
    final keys = widget.config.checklistKeys;
    if (_preFlightIndex < keys.length - 1) {
      setState(() => _preFlightIndex += 1);
    } else {
      // All pre-flight steps done → start workflow
      setState(() {
        _phase = _WizardPhase.workflow;
        _preFlightIndex = -1;
      });
      // In recheck mode, run probe_screen first to calibrate the force
      // sensor, then jump to corner probing.  The loosen/tighten
      // intermediate screens are skipped via flags.
      if (widget.recheck) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          // Home was already started during the preflight — wait for it.
          if (_recheckHomeFuture != null) {
            await _recheckHomeFuture;
            _recheckHomeFuture = null;
          }
          if (!mounted) return;
          // Jump to probe_screen (step 1) — calibrates screen position
          // and force sensor limits before probing corners.
          _engine.jumpToStep(1);
          if (_engine.canRunCurrentStep) {
            _engine.runCurrentStep();
          }
        });
        return; // skip the non-recheck auto-run below
      }
      // Auto-run the current step
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _engine.canRunCurrentStep) {
          _engine.runCurrentStep();
        }
      });
    }
  }

  Future<void> _emergencyStop() async {
    if (_busyStop) return;
    setState(() => _busyStop = true);
    try {
      final manual = Provider.of<ManualProvider>(context, listen: false);
      await manual.emergencyStop();
      if (!mounted) return;
      final status = Provider.of<StatusProvider>(context, listen: false);
      status.clearHomedStatus();
      await status.refreshKinematicStatus();
      OrionConfig().setLeveled(false);
      if (!mounted) return;
      // Explain that the procedure was aborted with no offset applied.
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => GlassAlertDialog(
          title: Row(
            children: [
              Icon(PhosphorIcons.warningCircle(),
                  size: 26, color: Colors.redAccent),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  FlutterI18n.translate(context, 'leveling.emergencyStopTitle'),
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            FlutterI18n.translate(context, 'leveling.emergencyStopMsg'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          actions: [
            GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 60),
              ),
              child: Text(FlutterI18n.translate(context, 'common.ok')),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) setState(() => _busyStop = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGlass =
        Provider.of<ThemeProvider>(context, listen: false).isGlassTheme;
    final primary = Theme.of(context).colorScheme.primary;

    final showAppBar = _phase == _WizardPhase.adjustment &&
        _adjustmentStep == _AdjustmentStep.intro;

    return GlassApp(
      child: Scaffold(
        backgroundColor: isGlass
            ? Colors.transparent
            : Theme.of(context).colorScheme.surface,
        appBar: showAppBar
            ? AppBar(
                backgroundColor: isGlass
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.surface,
                elevation: 0,
                automaticallyImplyLeading: false,
                centerTitle: true,
                title: Text(
                  FlutterI18n.translate(
                      context, 'leveling.adjustmentIntroTitle'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              )
            : null,
        body: SafeArea(
          child: Padding(
            padding: OrionSpacing.screenPaddingWithBottomNav,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _buildPhaseContent(context, primary),
                  ),
                ),
                const SizedBox(height: 16),
                _buildActions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseContent(BuildContext context, Color primary) {
    switch (_phase) {
      case _WizardPhase.variant:
        return Column(
          key: const ValueKey('variant-phase'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(PhosphorIcons.magicWand(), color: primary),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'leveling.assisted'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: OrionSpacing.listGap),
            Expanded(child: _buildPhaseBody(context)),
          ],
        );
      case _WizardPhase.screenType:
        return Column(
          key: const ValueKey('screen-type-phase'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(PhosphorIcons.monitor(), color: primary),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'leveling.screenTypeTitle'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: OrionSpacing.listGap),
            Expanded(child: _buildPhaseBody(context)),
          ],
        );
      case _WizardPhase.adjustment:
        return _buildAdjustmentPhase(context, primary);
      default:
        return _buildPhaseBody(context);
    }
  }

  Widget _buildPhaseBody(BuildContext context) {
    switch (_phase) {
      case _WizardPhase.introAndChecklist:
        if (_preFlightIndex < 0) {
          return const _PreLevelingPane(key: ValueKey('intro'));
        }
        return _PreFlightGuidePane(
          key: ValueKey('preflight-$_preFlightIndex'),
          config: widget.config,
          stepIndex: _preFlightIndex,
        );
      case _WizardPhase.variant:
        return _VariantSelectionPane(
          key: const ValueKey('variant'),
          config: widget.config,
          onVariantSelected: (variant) {
            _engine.selectVariant(variant);
            OrionConfig().setLevelingVariant(variant.id);
            _resetCornerResults();
            // Standard arm is forcibly aligned — skip the align plate screen.
            _alignDone = variant.id == 'regular';
            _hexLongEndDone = false;
            // Generate a new session ID for each leveling attempt
            _levelingSessionId = _uuid4();
            _recheckNumber = 0;
            _probeConfigCaptured = false;
            // Fresh coupling state — the estimates are per-printer
            // properties but must not leak across re-selected sessions.
            _screwControllers = _freshControllers();
            _pendingCommand = null;
            _lastAchievedForceGf = null;
            _lastAdjustedCorner = null;
            _consecutiveSkewHits = 0;
            _consecutiveBackAdjustments = 0;
            // per-screw calibration (fire-and-forget; adjustments
            // happen much later in the flow).
            _loadScrewCalibration();
            setState(() {
              _phase = _WizardPhase.screenType;
              _preFlightIndex = -1;
            });
          },
        );
      case _WizardPhase.screenType:
        return _ScreenTypeSelectionPane(
          key: const ValueKey('screenType'),
          onScreenTypeSelected: (screenType) {
            setState(() {
              _screenType = screenType;
              // The final offset steps (probe_standardarm / probe_offset)
              // take the screen type so the probe accounts for the surface.
              _engine.setScreenType(screenType);
              // Persist the machine's screen type so later rechecks and
              // sessions can reuse it without asking again.
              OrionConfig().setScreenType(screenType.id);
              _phase = _WizardPhase.introAndChecklist;
              _preFlightIndex = -1;
            });
          },
        );
      case _WizardPhase.workflow:
        return _WorkflowPane(
          key: const ValueKey('workflow'),
          engine: _engine,
          effectivelyRunning: _effectivelyRunning,
          autoAdvancing: _autoAdvancing,
          loosenScrewsDone: _loosenScrewsDone,
          tightenScrewsDone: _tightenScrewsDone,
          alignDone: _alignDone,
          hexLongEndDone: _hexLongEndDone,
          cornerResults: _cornerResults,
          cornerZs: _rawCornerZs,
          preAdjustmentDeviation: _preAdjustmentDeviation,
        );
      case _WizardPhase.adjustment:
        // Handled in _buildPhaseContent
        return const SizedBox.shrink();
    }
  }

  Widget _buildActions(BuildContext context) {
    if (_phase == _WizardPhase.workflow) {
      return _buildWorkflowActions(context);
    }

    if (_phase == _WizardPhase.adjustment) {
      return _buildAdjustmentActions(context);
    }

    if (_phase == _WizardPhase.introAndChecklist && _preFlightIndex >= 0) {
      // Pre-flight step: (Back or Cancel) | Next/Done
      final isLast = _preFlightIndex >= widget.config.checklistKeys.length - 1;
      final isFirstRecheck = widget.recheck && _preFlightIndex == 0;
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: isFirstRecheck
                  ? GlassButtonTint.negative
                  : GlassButtonTint.neutral,
              onPressed: isFirstRecheck ? _cancelLeveling : _goBack,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isFirstRecheck
                        ? PhosphorIcons.x()
                        : PhosphorIcons.arrowLeft(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isFirstRecheck
                        ? FlutterI18n.translate(context, 'leveling.cancel')
                        : FlutterI18n.translate(context, 'common.back'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: _advancePreFlight,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isLast
                        ? FlutterI18n.translate(context, 'common.done')
                        : FlutterI18n.translate(context, 'leveling.next'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isLast ? PhosphorIcons.check() : PhosphorIcons.arrowRight(),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Variant / screen-type selection: Cancel only
    if (_phase == _WizardPhase.variant || _phase == _WizardPhase.screenType) {
      return Center(
        child: SizedBox(
          width: 260,
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: _cancelLeveling,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.x(), size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'common.cancel'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Intro view: Cancel | Start Pre-Flight
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: _cancelLeveling,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.x(), size: 20),
                const SizedBox(width: 10),
                Text(
                  FlutterI18n.translate(context, 'common.cancel'),
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: OrionSpacing.controlGap),
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.positive,
            onPressed: () => setState(() => _preFlightIndex = 0),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  FlutterI18n.translate(
                      context, 'leveling.wizardStartPreFlight'),
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 10),
                Icon(PhosphorIcons.arrowRight(), size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowActions(BuildContext context) {
    final status = _engine.status;
    final isLast = _engine.currentStepIndex >= _engine.steps.length - 1;
    final isAllCornersMeasured =
        status == LevelingWorkflowStatus.stepComplete &&
            _engine.currentStep?.intermediateScreen == 'allCorners';

    // Completion: single Done button
    if (status == LevelingWorkflowStatus.complete) {
      return Center(
        child: SizedBox(
          width: 320,
          child: GlassButton(
            tint: GlassButtonTint.positive,
            onPressed: () => widget.recheck
                ? Navigator.of(context).pop()
                : Navigator.of(context).popUntil((route) => route.isFirst),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.check(), size: 20),
                const SizedBox(width: 10),
                Text(
                  FlutterI18n.translate(context, 'common.done'),
                  style: const TextStyle(fontSize: 20),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Running: Emergency Stop only
    if (_effectivelyRunning || _busyStop) {
      return Center(
        child: SizedBox(
          width: 320,
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: _busyStop ? null : _emergencyStop,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _busyStop
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(PhosphorIconsFill.stop, size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'moveZ.emergencyStop'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loosen-screws prompt: Cancel | Done
    if (status == LevelingWorkflowStatus.stepComplete &&
        _engine.currentStep?.intermediateScreen == 'loosen' &&
        !_loosenScrewsDone) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () {
                _loosenScrewsDone = true;
                _engine.advanceAfterSuccessfulStep();
                // Auto-run the initial leveling step
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _engine.canRunCurrentStep) {
                    _engine.runCurrentStep();
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.check(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.done'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Align-plate prompt (shown before tighten): Cancel | Done
    if (status == LevelingWorkflowStatus.stepComplete &&
        _engine.currentStep?.intermediateScreen == 'tighten' &&
        !_alignDone) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () => setState(() => _alignDone = true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.check(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.done'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Hex long-end prompt (between Align and Tighten): Cancel | Done
    if (status == LevelingWorkflowStatus.stepComplete &&
        _engine.currentStep?.intermediateScreen == 'tighten' &&
        _alignDone &&
        !_hexLongEndDone) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () => setState(() => _hexLongEndDone = true),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.check(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.done'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Tighten-screws prompt (after alignment): Cancel | Done → auto-run offset
    if (status == LevelingWorkflowStatus.stepComplete &&
        _engine.currentStep?.intermediateScreen == 'tighten' &&
        _alignDone &&
        _hexLongEndDone) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => GlassAlertDialog(
                    title: Row(
                      children: [
                        Icon(PhosphorIcons.warning(),
                            size: 26, color: Colors.orangeAccent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            FlutterI18n.translate(
                                context, 'leveling.tightenConfirmTitle'),
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
                          context, 'leveling.tightenConfirmMsg'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w500),
                    ),
                    actions: [
                      GlassButton(
                        tint: GlassButtonTint.neutral,
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 60),
                        ),
                        child: Text(
                          FlutterI18n.translate(
                              context, 'leveling.tightenConfirmNo'),
                        ),
                      ),
                      GlassButton(
                        tint: GlassButtonTint.positive,
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 60),
                        ),
                        child: Text(
                          FlutterI18n.translate(
                              context, 'leveling.tightenConfirmYes'),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                _engine.advanceAfterSuccessfulStep();
                // Auto-run the calibrating offset step
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _engine.canRunCurrentStep) {
                    _engine.runCurrentStep();
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.check(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.done'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Remove puck prompt: Cancel | Done → advance + auto-run final prepare
    if (status == LevelingWorkflowStatus.stepComplete &&
        _engine.currentStep?.intermediateScreen == 'removePuck') {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () {
                // Arm is already up from background probe_corner_prepare.
                // Skip final_prepare — jump straight to final calibration.
                final finalIdx = _engine.steps.lastIndexWhere(
                  (s) => s.kind == LevelingWorkflowStepKind.finalOffset,
                );
                if (finalIdx >= 0) {
                  _engine.jumpToStep(finalIdx);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _engine.canRunCurrentStep) {
                      _engine.runCurrentStep();
                    }
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.check(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.done'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Not running, not complete: Cancel + action button
    final bool needsAdjustment = isAllCornersMeasured && !_isCornerCheckPassed;
    final bool canSkip = isAllCornersMeasured && _isBorderline;
    final bool isCornerPrepare =
        status == LevelingWorkflowStatus.stepComplete &&
            _engine.currentStep?.kind == LevelingWorkflowStepKind.prepare &&
            (_engine.currentStep?.id.startsWith('fine_prepare_') ?? false);
    final primaryLabel = switch (status) {
      LevelingWorkflowStatus.idle =>
        FlutterI18n.translate(context, 'leveling.wizardProceed'),
      LevelingWorkflowStatus.stepComplete => isAllCornersMeasured
          ? (needsAdjustment
              ? FlutterI18n.translate(
                  context,
                  _recheckNumber == 0
                      ? 'leveling.wizardBeginAdjustment'
                      : 'leveling.wizardAdjust')
              : FlutterI18n.translate(context, 'leveling.wizardContinue'))
          : isCornerPrepare
              ? FlutterI18n.translate(context, 'leveling.next')
              : isLast
                  ? FlutterI18n.translate(context, 'common.done')
                  : FlutterI18n.translate(context, 'leveling.next'),
      LevelingWorkflowStatus.failed =>
        FlutterI18n.translate(context, 'common.retry'),
      _ => '',
    };

    final primaryIcon = switch (status) {
      LevelingWorkflowStatus.idle => PhosphorIcons.arrowRight(),
      LevelingWorkflowStatus.stepComplete => isAllCornersMeasured
          ? (needsAdjustment
              ? PhosphorIcons.wrench()
              : PhosphorIcons.arrowRight())
          : PhosphorIcons.arrowRight(),
      LevelingWorkflowStatus.failed => PhosphorIcons.arrowRight(),
      _ => PhosphorIcons.arrowRight(),
    };

    final primaryTint = needsAdjustment
        ? GlassButtonTint.warn
        : status == LevelingWorkflowStatus.failed
            ? GlassButtonTint.warn
            : GlassButtonTint.positive;

    VoidCallback? onPrimary() {
      if (_engine.isRunning) return null;
      if (isAllCornersMeasured && needsAdjustment) {
        return () => _enterAdjustmentMode();
      }
      return switch (status) {
        LevelingWorkflowStatus.idle => () => _engine.runCurrentStep(),
        LevelingWorkflowStatus.failed => () => _engine.runCurrentStep(),
        LevelingWorkflowStatus.stepComplete => () {
            // Proceeding from the puck-placement step — hide the projector
            // pattern before probing.
            _uvSafetyTimer.disarm();
            BackendService()
                .turnOffSpecialScreens()
                .then((_) {})
                .catchError((_) {});
            _engine.advanceAfterSuccessfulStep();
            // Auto-run the next step if advancing from a corner prepare,
            // or if it's a skipBackend intermediate screen (e.g. remove
            // puck) so the user sees the real view immediately.
            if (isCornerPrepare) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _engine.canRunCurrentStep) {
                  _engine.runCurrentStep();
                }
              });
            }
            final next = _engine.currentStep;
            if (next?.skipBackend == true && next?.intermediateScreen != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _engine.canRunCurrentStep) {
                  _engine.runCurrentStep();
                }
              });
            }
          },
        LevelingWorkflowStatus.complete => () =>
            Navigator.of(context).popUntil((route) => route.isFirst),
        LevelingWorkflowStatus.running => null,
      };
    }

    return Row(
      children: [
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: _cancelLeveling,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.x(), size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'common.cancel'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        if (canSkip) ...[
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: _skipAdjustment,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.fastForward(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'leveling.wizardSkip'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (isAllCornersMeasured && !needsAdjustment) ...[
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: () => _enterAdjustmentMode(),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.wrench(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(
                        context, 'leveling.wizardAdjustAgain'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(width: OrionSpacing.controlGap),
        Expanded(
          child: GlassButton(
            tint: primaryTint,
            onPressed: onPrimary(),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(primaryIcon, size: 20),
                const SizedBox(width: 8),
                Text(
                  primaryLabel,
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cancelLeveling() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => GlassAlertDialog(
        title: Row(
          children: [
            Icon(PhosphorIcons.warning(), size: 26, color: Colors.orangeAccent),
            const SizedBox(width: 14),
            Text(
              FlutterI18n.translate(context, 'leveling.wizardCancelTitle'),
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
          ],
        ),
        content: Text(
          FlutterI18n.translate(context, 'leveling.wizardCancelMsg'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        actions: [
          GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 60),
            ),
            child: Text(
              FlutterI18n.translate(context, 'levelingWorkflow.yes'),
            ),
          ),
          GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 60),
            ),
            child: Text(
              FlutterI18n.translate(context, 'levelingWorkflow.no'),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      OrionConfig().setLeveled(false);
      // Hide any projector pattern immediately — otherwise it stays up
      // until the 30s UV safety timer fires.
      _uvSafetyTimer.disarm();
      BackendService()
          .turnOffSpecialScreens()
          .then((_) {})
          .catchError((_) {});
      // Move to top before cancelling so the arm is in a safe position
      Provider.of<ManualProvider>(context, listen: false)
          .moveToTop()
          .then((_) {})
          .catchError((_) {});
      Navigator.of(context).pop();
    }
  }

  Widget _buildAdjustmentActions(BuildContext context) {
    final isPuckStep = _adjustmentStep == _AdjustmentStep.puckPlacement;

    // Mechanical skew: single close button — nothing to adjust, direct
    // the user to support.
    if (_adjustmentStep == _AdjustmentStep.mechanicalSkew) {
      return Center(
        child: SizedBox(
          width: 320,
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: () {
              _uvSafetyTimer.disarm();
              BackendService()
                  .turnOffSpecialScreens()
                  .then((_) {})
                  .catchError((_) {});
              Provider.of<ManualProvider>(context, listen: false)
                  .moveToTop()
                  .then((_) {})
                  .catchError((_) {});
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.x(), size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'common.close'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Busy (preparing / probing): emergency stop with status label
    if (_adjustmentBusy) {
      return Center(
        child: SizedBox(
          width: 320,
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: _busyStop ? null : _emergencyStop,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(PhosphorIconsFill.stop, size: 20),
                const SizedBox(width: 8),
                Text(
                  _adjustmentStep == _AdjustmentStep.probing
                      ? FlutterI18n.translate(
                          context, 'leveling.wizardProbingBtn')
                      : FlutterI18n.translate(
                          context, 'leveling.wizardPreparingBtn'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Adjustment intro: single "Start" button
    if (_adjustmentStep == _AdjustmentStep.intro) {
      return Center(
        child: SizedBox(
          width: 320,
          child: GlassButton(
            tint: GlassButtonTint.positive,
            onPressed: () {
              setState(() => _adjustmentStep = _AdjustmentStep.preparing);
              _runAdjustmentPrepare();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.arrowRight(), size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'leveling.startFineTuning'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Hex short-end prompt after intro (reuses long-end visuals, short text)
    if (_adjustmentStep == _AdjustmentStep.hexShortEnd) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () {
                setState(() => _adjustmentStep = _AdjustmentStep.probing);
                _runAdjustmentProbe();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.check(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.done'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Puck placement: Cancel | Proceed
    if (isPuckStep) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: _runPrepareAfterPuck,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.arrowRight(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'leveling.next'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Below resolution + borderline: restore the corner-check Skip escape
    // (that screen's canSkip never fires once pushed into adjustment).
    // Cancel | Skip | Re-check.
    if (_adjustmentStep == _AdjustmentStep.belowResolution && _isBorderline) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: _cancelLeveling,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.x(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'common.cancel'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: _skipAdjustment,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.fastForward(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'leveling.wizardSkip'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: OrionSpacing.controlGap),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: _runRecheckCorners,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIcons.arrowClockwise(), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    FlutterI18n.translate(context, 'leveling.wizardRecheckAll'),
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Feedback / error: Cancel | Re-check
    return Row(
      children: [
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.negative,
            onPressed: _cancelLeveling,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.x(), size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'common.cancel'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: OrionSpacing.controlGap),
        Expanded(
          child: GlassButton(
            tint: GlassButtonTint.positive,
            onPressed: _runRecheckCorners,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 65),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIcons.arrowClockwise(), size: 20),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, 'leveling.wizardRecheckAll'),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentPhase(BuildContext context, Color primary) {
    Widget content;
    if (_adjustmentError != null) {
      content = _buildAdjustmentError(context, primary);
    } else if (_adjustmentStep == _AdjustmentStep.belowResolution) {
      content = _buildBelowResolutionView(context, primary);
    } else if (_adjustmentStep == _AdjustmentStep.mechanicalSkew) {
      content = _buildMechanicalSkewView(context, primary);
    } else if (_adjustingCornerIndex == null) {
      content = const SizedBox.shrink();
    } else {
      switch (_adjustmentStep) {
        case _AdjustmentStep.intro:
          content = _buildAdjustmentIntroView(context, primary);
          break;
        case _AdjustmentStep.hexShortEnd:
          content = _buildHexShortEndView(context, primary);
          break;
        case _AdjustmentStep.preparing:
        case _AdjustmentStep.probing:
          content = _buildAdjustmentWarning(context, primary);
          break;
        case _AdjustmentStep.puckPlacement:
          content = _buildPuckPlacementView(context, primary);
          break;
        case _AdjustmentStep.belowResolution:
          content = _buildBelowResolutionView(context, primary);
          break;
        case _AdjustmentStep.mechanicalSkew:
          content = _buildMechanicalSkewView(context, primary);
          break;
        case _AdjustmentStep.feedback:
          // Corner indexing: 0=FL, 1=FR, 2=BR, 3=BL
          // The gauge target is anchored to the adjusted corner's
          // re-probed first-stage peak force plus the controller's
          // commanded delta (see _runAdjustmentProbe).
          final allForces = _cornerResults
              .map((r) => r?.measurements?.firstStagePeakForce)
              .toList();
          final idx = _adjustingCornerIndex!;

          if (allForces.length < 4 ||
              allForces[0] == null ||
              allForces[1] == null ||
              allForces[2] == null ||
              allForces[3] == null) {
            return const SizedBox.shrink();
          }

          // ── Unified screw command (front and back) ──
          // The command was computed once when the re-probe completed
          // (see _runAdjustmentProbe) and is only rendered here, so
          // rebuilds can't shift the target.  Direction comes from the
          // Z gap, magnitude from the per-screw learned coupling —
          // never from raw force differences, whose ±300–500 gf noise
          // can point the gauge the wrong way (e.g. session b9ef2b8f
          // recheck #1: FR's force sat ABOVE its diagonal reference
          // even though FR was the highest corner).
          if (_pendingCommand == null) {
            return const SizedBox.shrink();
          }
          final double targetForce = _pendingCommand!.targetForceGf;

          final double cornerForce = allForces[idx]!;
          final double forceDeltaGf = cornerForce - targetForce;
          // Positive → corner more compressed than reference → TIGHTEN.
          // Negative → corner less compressed than reference → LOOSEN.
          final bool needsTighten = forceDeltaGf > 20;
          final bool needsLoosen = forceDeltaGf < -20;

          // ── Prediction summary ──
          // Compute what the user should expect from this adjustment so
          // they can see whether they're on track.
          {
            final screwNames = [
              FlutterI18n.translate(context, 'leveling.wizardScrewFL'),
              FlutterI18n.translate(context, 'leveling.wizardScrewFR'),
              FlutterI18n.translate(context, 'leveling.wizardScrewBack'),
              FlutterI18n.translate(context, 'leveling.wizardScrewBack'),
            ];
            _predictionScrew = screwNames[idx];
            _predictionDirection = needsTighten
                ? FlutterI18n.translate(context, 'leveling.wizardTighten')
                : needsLoosen
                    ? FlutterI18n.translate(context, 'leveling.wizardLoosen')
                    : FlutterI18n.translate(context, 'leveling.wizardAtTarget');

            // The command carries its own damped target and a
            // clamp-aware recheck estimate.
            _predictionZMm = _pendingCommand!.cmd.targetZMm.abs();
            _predictionRechecks = _pendingCommand!.cmd.predictedRechecks;
          }

          content = _AdjustmentFeedbackScreen(
            key: const ValueKey('adjustment-feedback'),
            cornerIndex: _adjustingCornerIndex!,
            cornerForce: cornerForce,
            targetForce: targetForce,
            allCornerForces: allForces.whereType<double>().toList(),
            forceDelta: forceDeltaGf,
            needsTighten: needsTighten,
            needsLoosen: needsLoosen,
            predictionDirection: _predictionDirection,
            predictionScrew: _predictionScrew,
            predictionZMm: _predictionZMm,
            predictionRechecks: _predictionRechecks,
            consecutiveBackAdjustments: _consecutiveBackAdjustments,
            // Track where the user actually leaves the gauge so the
            // recheck log can compare it against the suggested target.
            onAchievedForce: (force) => _lastAchievedForceGf = force,
          );
          break;
      }
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(_adjustmentStep),
        child: content,
      ),
    );
  }

  Widget _buildAdjustmentIntroView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              FlutterI18n.translate(context, 'leveling.adjustmentIntroBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.orangeAccent.withValues(alpha: 0.10),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIcons.warning(),
                      size: 22, color: Colors.orangeAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      FlutterI18n.translate(
                          context, 'leveling.adjustmentIntroCaveat'),
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.4,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHexShortEndView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final title = Text(
      FlutterI18n.translate(context, 'leveling.hexShortEndTitle'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
    final rawInstruction =
        FlutterI18n.translate(context, 'leveling.hexShortEndInstruction');
    final instruction = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _buildHighlightedInstruction(
        context,
        rawInstruction,
        'short',
        TextStyle(
          fontSize: 20,
          height: 1.4,
          color: onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              title,
              const SizedBox(height: OrionSpacing.compactListGap),
              instruction,
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = min(
                min((constraints.maxWidth - 24) / 886,
                    (constraints.maxHeight - 16) / 207),
                1.35,
              );
              return Center(
                child: SizedBox(
                  width: 886 * scale,
                  height: 207 * scale,
                  child: const FittedBox(
                    fit: BoxFit.contain,
                    child: _HexKeyShortEndDiagram(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentWarning(BuildContext context, Color primary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _IsoMovementWarning(),
          const SizedBox(height: 32),
          Text(
            FlutterI18n.translate(context, 'leveling.wizardKeepHandsClear'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              FlutterI18n.translate(context, 'leveling.wizardMovingToProbe'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown when the corner check failed but every screw's correction
  /// would be below the execution floor — the remaining deviation is
  /// within measurement/adjustment resolution, so turning a screw
  /// against the gauge would be noise-driven.  Footer offers
  /// Cancel | Re-check (same as feedback).
  Widget _buildBelowResolutionView(BuildContext context, Color primary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary.withValues(alpha: 0.15),
                  ),
                ),
                Icon(
                  PhosphorIcons.equals(),
                  size: 56,
                  color: primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            FlutterI18n.translate(
                context, 'leveling.wizardBelowResolutionTitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              FlutterI18n.translate(
                  context, 'leveling.wizardBelowResolutionBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Support URL encoded into the QR code on the mechanical-skew screen.
  static const String _proArmLevelFailSupportUrl =
      'https://concepts3d.ca/proarmlevelfail';

  /// Shown when the suggested screw adjustment exceeds what the leveling
  /// screws can physically apply — the Pro Arm itself is mechanically
  /// skewed and no screw turn will fix it.  Mirrors the post-calibration
  /// overlay's evaluation layout: two 1:1 cards, explanation left and a
  /// QR code right.
  Widget _buildMechanicalSkewView(BuildContext context, Color primary) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final qrSize = ((constraints.maxWidth / 2) - 40).clamp(80.0, 260.0);
          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: OrionSpacing.screenHorizontal),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left column: warning + explanation.
                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FlutterI18n.translate(
                            context, 'leveling.wizardSkewTitle'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        FlutterI18n.translate(
                            context, 'leveling.wizardSkewBody'),
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.5,
                          color: onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Right column: QR code to the support page.
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: QrImageView(
                      data: _proArmLevelFailSupportUrl,
                      version: QrVersions.auto,
                      size: qrSize,
                      gapless: true,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      eyeStyle: QrEyeStyle(color: onSurface),
                      dataModuleStyle: QrDataModuleStyle(
                        color: onSurface,
                        dataModuleShape: QrDataModuleShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPuckPlacementView(BuildContext context, Color primary) {
    final labels = ['Front Left', 'Front Right', 'Back Right', 'Back Left'];
    final screwHints = ['', '', ' (center screw)', ' (center screw)'];
    final idx = _adjustingCornerIndex ?? 0;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = Text(
      FlutterI18n.translate(context, 'leveling.wizardPlacePuck'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
    );
    final instruction = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        FlutterI18n.translate(context, 'leveling.wizardPuckInstruction',
            translationParams: {
              'corner': labels[idx],
              'hint': screwHints[idx],
            }),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          height: 1.4,
          color: onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              title,
              const SizedBox(height: 8),
              instruction,
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableH = constraints.maxHeight;
              final availableW = constraints.maxWidth;
              const diagramAspect = 794 / 320;
              double h = availableH - 16;
              double w = h * diagramAspect;
              if (w > availableW - 24) {
                w = availableW - 24;
                h = w / diagramAspect;
              }
              final cappedScale = (w / 794).clamp(0.0, 1.6);
              w = 794 * cappedScale;
              h = 421 * cappedScale;
              return Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: _SpacerPlacementDiagram(cornerIndex: idx),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentError(BuildContext context, Color primary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.warning(), size: 64, color: Colors.orangeAccent),
          const SizedBox(height: 20),
          Text(
            FlutterI18n.translate(context, 'leveling.wizardAdjustFailed'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.orangeAccent,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _adjustmentError ??
                  FlutterI18n.translate(context, 'leveling.wizardUnknownError'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================================================================================================================================================
// Phase: Intro (simplified — calibration-overlay style)
// ================================================================================================================================================================================================

class _PreLevelingPane extends StatelessWidget {
  const _PreLevelingPane({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Center(
      key: const ValueKey('intro'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.12),
            ),
            child: Icon(
              PhosphorIcons.magicWand(),
              size: 52,
              color: primary,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              FlutterI18n.translate(context, 'leveling.wizardIntroMsg'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              FlutterI18n.translate(context, 'leveling.wizardIntroDetail'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                height: 1.4,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================================================================================================================================================
// Pre-Flight Step-through Guide
// ================================================================================================================================================================================================

class _PreFlightGuidePane extends StatelessWidget {
  const _PreFlightGuidePane({
    super.key,
    required this.config,
    required this.stepIndex,
  });

  final LevelingConfig config;
  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final keys = config.checklistKeys;
    final label = FlutterI18n.translate(context, keys[stepIndex]);
    final total = keys.length;

    return Center(
      key: ValueKey('preflight-$stepIndex'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.12),
            ),
            child: Icon(
              PhosphorIcons.listChecks(),
              size: 52,
              color: primary,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Progress dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(total, (i) {
              final isActive = i <= stepIndex;
              return Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.15),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ================================================================================================================================================================================================
// Phase: Variant Selection (kept similar but updated styling)
// ================================================================================================================================================================================================

class _VariantSelectionPane extends StatelessWidget {
  const _VariantSelectionPane({
    super.key,
    required this.config,
    required this.onVariantSelected,
  });

  final LevelingConfig config;
  final ValueChanged<LevelingVariant> onVariantSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('variant'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < config.variants.length; i++) ...[
                if (i > 0) const SizedBox(width: OrionSpacing.controlGap),
                Expanded(
                  child: _VariantCard(
                    variant: config.variants[i],
                    onPressed: () => onVariantSelected(config.variants[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.onPressed,
  });

  final LevelingVariant variant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      outlined: true,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(glassCornerRadius),
        onTap: onPressed,
        child: Padding(
          padding: OrionSpacing.cardPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: _VariantAsset(variant: variant)),
              const SizedBox(height: OrionSpacing.listGap),
              Text(
                variant.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: OrionSpacing.compactListGap),
              Text(
                variant.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantAsset extends StatelessWidget {
  const _VariantAsset({required this.variant});

  final LevelingVariant variant;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final asset = variant.assetPath;
    if (asset == null) {
      return Icon(
        variant.icon ?? PhosphorIconsFill.cube,
        size: 64,
        color: accent,
      );
    }

    return SizedBox(
      height: 120,
      child: asset.endsWith('.svg')
          ? SvgPicture.asset(
              asset,
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
            )
          : Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

/// Pro-Arm top view with the three leveling screws numbered in the
/// recommended loosening sequence (top → bottom-right → bottom-left).
/// Base line art is derived from the a2_pro_arm_solo top-view drawing
/// and tinted with the theme accent like [_VariantAsset]; the dashed
/// sequence arrows and number badges are painted on top so they follow
/// the active theme colors.
class _HexKeyLongEndDiagram extends StatelessWidget {
  const _HexKeyLongEndDiagram();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final lineArt = onSurface.withValues(alpha: 0.45);
    return SizedBox(
      width: 395,
      height: 411,
      child: Stack(
        children: [
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
                stops: [0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/a2_hex_key_arm_long_end_top_layer1.svg',
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(lineArt, BlendMode.srcIn),
            ),
          ),
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
                stops: [0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/a2_hex_key_arm_long_end_top_layer2.svg',
              fit: BoxFit.contain,
              colorFilter:
                  const ColorFilter.mode(Color(0xFF69F0AE), BlendMode.srcIn),
            ),
          ),
        ],
      ),
    );
  }
}

class _HexKeyShortEndDiagram extends StatelessWidget {
  const _HexKeyShortEndDiagram();

  @override
  Widget build(BuildContext context) {
    final lineArt =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    // Layer 1: regular lineArt with bottom fade; Layer 2: cancel red (instead of green) for the short-end highlight.
    return SizedBox(
      width: 886,
      height: 207,
      child: Stack(
        children: [
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
                stops: [0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/a2_hex_key_arm_short_end_top_layer1.svg',
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(lineArt, BlendMode.srcIn),
            ),
          ),
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
                stops: [0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/a2_hex_key_arm_short_end_top_layer2.svg',
              fit: BoxFit.contain,
              colorFilter:
                  const ColorFilter.mode(Colors.redAccent, BlendMode.srcIn),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildHighlightedInstruction(
  BuildContext context,
  String text,
  String keyword,
  TextStyle baseStyle,
) {
  final lower = text.toLowerCase();
  final kwLower = keyword.toLowerCase();
  final idx = lower.indexOf(kwLower);
  if (idx == -1) {
    return Text(text, textAlign: TextAlign.center, style: baseStyle);
  }
  final before = text.substring(0, idx);
  final match = text.substring(idx, idx + keyword.length);
  final after = text.substring(idx + keyword.length);
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: before, style: baseStyle),
        TextSpan(
          text: match,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: baseStyle.color,
            decorationThickness: 1.5,
          ),
        ),
        TextSpan(text: after, style: baseStyle),
      ],
    ),
    textAlign: TextAlign.center,
  );
}

class _ScrewSequenceDiagram extends StatelessWidget {
  const _ScrewSequenceDiagram({this.clockwise = false});

  final bool clockwise;

  /// Screw centres as fractions of the 254×192 SVG viewBox (top 5/6
  /// crop), in loosening order: 1 top-centre, 2 bottom-right, 3
  /// bottom-left.
  static const _screwFractions = [
    Offset(0.499, 0.267),
    Offset(0.673, 0.665),
    Offset(0.326, 0.665),
  ];

  @override
  Widget build(BuildContext context) {
    // Line art is dimmed so the sequence arrows and number badges
    // (full primary) read as the foreground layer. Fade at the bottom
    // softens the hard crop of the top 5/6 view.
    final lineArt =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.32);
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 254,
      height: 192,
      child: Stack(
        children: [
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
                stops: [0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/'
              'a2_pro_arm_solo_leveling_screws_top.svg',
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(lineArt, BlendMode.srcIn),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _ScrewSequencePainter(
                primary: primary,
                onPrimary: Theme.of(context).colorScheme.onPrimary,
                clockwise: clockwise,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the loosening sequence on top of the Pro-Arm line art:
/// dashed straight arrows from screw to screw (1→2→3), a
/// Paints the loosening/tightening sequence on top of the Pro-Arm line
/// art: dashed straight arrows from screw to screw (1→2→3), a rotation
/// arc around each screw, and the numbered badges. All overlay
/// elements run at full primary so they read as the foreground against
/// the dimmed line art.
class _ScrewSequencePainter extends CustomPainter {
  _ScrewSequencePainter(
      {required this.primary, required this.onPrimary, this.clockwise = false});

  final Color primary;
  final Color onPrimary;
  final bool clockwise;

  static const _badgeRadius = 12.0;
  static const _badgeOffset = 36.0;

  /// Teardrop tip stops this short of the circle edge so it points at
  /// the screw head without touching the rotation arc.
  static const _badgeTipClearance = 6.0;

  /// Radius of the rotation indicator around a screw head.
  static const _rotationRadius = 15.0;

  /// Straight arrows start/end well outside the rotation arcs — room
  /// for the 7px arrowhead plus a visible gap so the sequence arrows
  /// and the CCW indicators read as separate layers.
  static const _arrowClearance = _rotationRadius + 17.0;

  @override
  void paint(Canvas canvas, Size size) {
    final screws = [
      for (final f in _ScrewSequenceDiagram._screwFractions)
        Offset(f.dx * size.width, f.dy * size.height),
    ];
    final centroid = (screws[0] + screws[1] + screws[2]) / 3;

    // Dark backdrop so the orange pops on washed-out light screens and
    // stays crisp on dark. Blurred and slightly wider than the arrow.
    final shadowStroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final shadowFill = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    for (int i = 0; i < screws.length; i++) {
      final a = screws[i];
      final b = screws[(i + 1) % screws.length];

      // Dashed straight guide arrow to the next screw in sequence.
      final dir = (b - a) / (b - a).distance;
      final line = Path()
        ..moveTo((a + dir * _arrowClearance).dx, (a + dir * _arrowClearance).dy)
        ..lineTo(
            (b - dir * _arrowClearance).dx, (b - dir * _arrowClearance).dy);
      final linePaint = Paint()
        ..color = primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      _strokeDashed(canvas, line, linePaint);
      _drawArrowhead(canvas, b - dir * _arrowClearance, dir, shadowFill);
      _drawArrowhead(
          canvas,
          b - dir * _arrowClearance,
          dir,
          Paint()
            ..color = primary
            ..style = PaintingStyle.fill);

      // Rotation arc, opening toward the badge so the arrowhead lands
      // beside its screw number. Direction is CCW for loosen, CW for
      // tighten (mirrored sweep/start and tangent).
      final out = (a - centroid) / (a - centroid).distance;
      final badgeAngle = atan2(out.dy, out.dx);
      final sweep = clockwise ? 250 * pi / 180 : -250 * pi / 180;
      final startAngle =
          clockwise ? badgeAngle + 55 * pi / 180 : badgeAngle - 55 * pi / 180;
      final arc = Path()
        ..arcTo(Rect.fromCircle(center: a, radius: _rotationRadius), startAngle,
            sweep, false);
      _strokeDashed(canvas, arc, shadowStroke);
      final arcStart = a +
          Offset(cos(startAngle) * _rotationRadius,
              sin(startAngle) * _rotationRadius);
      final arcEnd = a +
          Offset(cos(startAngle + sweep) * _rotationRadius,
              sin(startAngle + sweep) * _rotationRadius);
      final arcGradient = ui.Gradient.linear(
          arcStart,
          arcEnd,
          clockwise
              ? const [Color(0xFFFF8C00), Color(0xFFE65100)]
              : const [Color(0xFF2E7D32), Color(0xFF81C784)]);
      final arcPaint = Paint()
        ..shader = arcGradient
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      _strokeDashed(canvas, arc, arcPaint);
      final endAngle = startAngle + sweep;
      final direction = clockwise
          ? Offset(-sin(endAngle), cos(endAngle))
          : Offset(sin(endAngle), -cos(endAngle));
      final arcTip = a +
          Offset(
              _rotationRadius * cos(endAngle), _rotationRadius * sin(endAngle));
      _drawArrowhead(canvas, arcTip, direction, shadowFill);
      _drawArrowhead(
          canvas,
          arcTip,
          direction,
          Paint()
            ..color =
                clockwise ? const Color(0xFFE65100) : const Color(0xFF81C784)
            ..style = PaintingStyle.fill);

      // Teardrop number badge: circle pushed outward from the plate
      // centre, with a point aimed at its screw head.
      final badgeCenter = a + out * _badgeOffset;
      final tip = a + out * (_badgeOffset - _badgeRadius - _badgeTipClearance);
      final badgePerp = Offset(-out.dy, out.dx) * _badgeRadius * 0.55;
      final badgeFill = Paint()..color = primary;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(badgeCenter.dx + badgePerp.dx, badgeCenter.dy + badgePerp.dy)
          ..lineTo(badgeCenter.dx - badgePerp.dx, badgeCenter.dy - badgePerp.dy)
          ..close(),
        badgeFill,
      );
      canvas.drawCircle(badgeCenter, _badgeRadius, badgeFill);
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: onPrimary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, badgeCenter - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _strokeDashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      double pos = 0;
      while (pos < m.length) {
        canvas.drawPath(m.extractPath(pos, min(pos + 5, m.length)), paint);
        pos += 9;
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset at, Offset direction, Paint paint) {
    final tip = at + direction * 9;
    final perp = Offset(-direction.dy, direction.dx) * 6;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(at.dx + perp.dx, at.dy + perp.dy)
        ..lineTo(at.dx - perp.dx, at.dy - perp.dy)
        ..close(),
      paint..style = PaintingStyle.fill,
    );
    paint.style = PaintingStyle.stroke;
  }

  @override
  bool shouldRepaint(covariant _ScrewSequencePainter old) =>
      old.primary != primary ||
      old.onPrimary != onPrimary ||
      old.clockwise != clockwise;
}

/// ISO 7010 W024 "hand crushing" warning pictogram for machine-movement
/// screens. Rendered in its standard colours (yellow triangle, black
/// symbol) — deliberately never tinted, so it stays compliant with the
/// real-world safety sign. Pulses gently to draw the eye.
class _IsoMovementWarning extends StatefulWidget {
  const _IsoMovementWarning();

  @override
  State<_IsoMovementWarning> createState() => _IsoMovementWarningState();
}

class _IsoMovementWarningState extends State<_IsoMovementWarning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SvgPicture.asset(
        'assets/images/ISO_7010_W024.svg',
        width: 140,
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Top view of the LCD with the Pro Arm, highlighting the two front
/// edges that must be made parallel. Base line art is the cropped
/// a2_lcd_pro_arm top view, dimmed via ColorFilter; the two edge
/// guides are painted on top (primary for the build plate, green for
/// the LCD) so they read as the foreground.
class _AlignPlateDiagram extends StatelessWidget {
  const _AlignPlateDiagram();

  @override
  Widget build(BuildContext context) {
    final lineArt =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return SizedBox(
      width: 786,
      height: 280,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
            stops: [0.0, 0.22],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: Stack(
          children: [
            SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/a2_lcd_pro_arm_align_plate_bottom.svg',
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(lineArt, BlendMode.srcIn),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _AlignPlatePainter(
                  plateColor: Theme.of(context).colorScheme.primary,
                  lcdColor: const Color(0xFF57F0A4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Corner-focused LCD top view for the "Place Leveling Spacer" step.
/// Uses the single base `a2_lcd_ui_top_view.svg` and dynamically crops
/// to the requested corner (mirrors the loosen/tighten top-5/6 and align
/// bottom-half pattern, but without pre-cropped assets).
/// Mapping per spec: FL = bottom + left 2/3, FR = bottom + right 2/3,
/// BR = top + right 2/3, BL = top + left 2/3.
const _lcdSanitizedBody =
    r'''<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2468 2296H7688"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6111 6102H4045"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2114 2630V2589"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3791 1810 3755 1789"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3790.507 1850.5C3783.183 1863.1854 3769.648 1871 3755 1871"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2114 5181V5140"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7924.5 5695C7924.5 5747.191 7882.191 5789.5 7830 5789.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M1830 6011H1842"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113.507 5139.5C8120.831 5152.1857 8120.831 5167.8146 8113.507 5180.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 1789 6365 1810"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7688 5294H2468"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3956 6000V5837"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M1830 1854H1842"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2468 5294V2296"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 6041 6436 6020"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7688 2296V5294"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3909 5790C3934.9573 5790 3956 5811.0427 3956 5837"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2114 2589 2078 2569"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6200 6000V5837"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8326 6011V1854"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6247 5790H7830"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6206 6007V5843"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2326 5789.5C2273.809 5789.5 2231.5 5747.191 2231.5 5695"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2067 6247H8090"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8090 6247V6235"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7924 5695V2131"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2326 2037H7830"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M1842 6011V1854"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2232 2131V5695"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365 1850 6401 1871"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2326 5790H3909"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042 5140V5181"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436 1810 6401 1789"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M1842.5 1854C1842.5 1730.0121 1943.0121 1629.5 2067 1629.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2067 1629V1617"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 2569 8042 2589"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6106 6095H4051"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436 5980 6401 5959"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8090 1629.5C8213.988 1629.5 8314.5 1730.0121 8314.5 1854"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2226 2125V5701"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113 2630V2589"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2114 5140 2078 5119"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3720 1850 3755 1871"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2043 5181 2078 5201"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113 2589 8078 2569"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436 6020V5980"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6253 5796H7836"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3950 6007V5843"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M4045 6101.5C3992.809 6101.5 3950.5 6059.191 3950.5 6007"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3720 5980V6020"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042 5181 8078 5201"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 2650 2114 2630"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365 6020 6401 6041"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2067 6247C1936.6608 6247 1831 6141.3395 1831 6011"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 6041 3791 6020"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436 1850V1810"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2043 5140V5181"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3719.493 6020.5C3712.169 6007.8146 3712.169 5992.1857 3719.493 5979.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365 5980V6020"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7830 2036.5C7882.191 2036.5 7924.5 2078.809 7924.5 2131"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 5959 6365 5980"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 6041C3740.352 6041 3726.817 6033.1857 3719.493 6020.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2043 2630 2078 2650"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2321 5796H3903"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7836 2030.5C7888.191 2030.5 7930.5 2072.809 7930.5 2125"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2043 2589V2630"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2113.507 2588.5C2120.831 2601.1856 2120.831 2616.8145 2113.507 2629.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 1871 3791 1850"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 2569 2043 2589"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8090 6235H2067"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2067 6247V6235"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 6041C6386.352 6041 6372.817 6033.1857 6365.493 6020.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2067 1629H8090"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8090 1629V1617"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8090 1617H2067"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8314 1854V6011"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3720 1810V1850"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8314 6011H8326"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8314 1854H8326"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2321 2031H7836"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3719.493 5979.5C3726.817 5966.8146 3740.352 5959 3755 5959"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7930 5701V2125"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 1871 6436 1850"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M1830 1854V6011"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3720 6020 3755 6041"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3791 5980 3755 5959"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3791 6020V5980"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 5959 3720 5980"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3791 1850V1810"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 1789 3720 1810"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113 5140 8078 5119"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042 2630 8078 2650"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 2650 8113 2630"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042 2589V2630"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113 5181V5140"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 5119 8042 5140"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 5201 8113 5181"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 5201 2114 5181"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 5119 2043 5140"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365 1810V1850"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M4051 6094.5C3998.809 6094.5 3956.5 6052.191 3956.5 6000"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6205.5 6007C6205.5 6059.191 6163.191 6101.5 6111 6101.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365.493 1850.5C6358.169 1837.8146 6358.169 1822.1854 6365.493 1809.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6200.5 6000C6200.5 6052.191 6158.191 6094.5 6106 6094.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2231.5 2131C2231.5 2078.809 2273.809 2036.5 2326 2036.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6200 5837C6200 5811.0427 6221.0427 5790 6247 5790"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 2650C8063.352 2650 8049.817 2642.1856 8042.493 2629.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 5119C2092.648 5119 2106.183 5126.8146 2113.507 5139.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 5959C6415.648 5959 6429.183 5966.8146 6436.507 5979.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 2650C2063.352 2650 2049.817 2642.1856 2042.4929 2629.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436.507 5979.5C6443.831 5992.1857 6443.831 6007.8146 6436.507 6020.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365.493 6020.5C6358.169 6007.8146 6358.169 5992.1857 6365.493 5979.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365.493 5979.5C6372.817 5966.8146 6386.352 5959 6401 5959"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436.507 6020.5C6429.183 6033.1857 6415.648 6041 6401 6041"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2067 6235.5C1943.0121 6235.5 1842.5 6134.988 1842.5 6011"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2113.507 2629.5C2106.183 2642.1856 2092.648 2650 2078 2650"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2042.4929 2629.5C2035.1691 2616.8145 2035.1691 2601.1856 2042.4929 2588.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M7930.5 5701C7930.5 5753.191 7888.191 5795.5 7836 5795.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 2568C2092.648 2568 2106.183 2575.8145 2113.507 2588.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2042.4929 2588.5C2049.817 2575.8145 2063.352 2568 2078 2568"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2226.5 2125C2226.5 2072.809 2268.809 2030.5 2321 2030.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3903 5796C3928.9573 5796 3950 5817.0427 3950 5843"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8314.5 6011C8314.5 6134.988 8213.988 6235.5 8090 6235.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2321 5795.5C2268.809 5795.5 2226.5 5753.191 2226.5 5701"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6206 5843C6206 5817.0427 6227.0427 5796 6253 5796"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8090 1618C8220.339 1618 8326 1723.6608 8326 1854"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8326 6011C8326 6141.3395 8220.339 6247 8090 6247"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M1831 1854C1831 1723.6608 1936.6608 1618 2067 1618"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3719.493 1850.5C3712.169 1837.8146 3712.169 1822.1854 3719.493 1809.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 5959C3769.648 5959 3783.183 5966.8146 3790.507 5979.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3790.507 5979.5C3797.831 5992.1857 3797.831 6007.8146 3790.507 6020.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3790.507 6020.5C3783.183 6033.1857 3769.648 6041 3755 6041"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3790.507 1809.5C3797.831 1822.1854 3797.831 1837.8146 3790.507 1850.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 1871C3740.352 1871 3726.817 1863.1854 3719.493 1850.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3719.493 1809.5C3726.817 1796.8146 3740.352 1789 3755 1789"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3755 1789C3769.648 1789 3783.183 1796.8146 3790.507 1809.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113.507 2588.5C8120.831 2601.1856 8120.831 2616.8145 8113.507 2629.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 2568C8092.648 2568 8106.183 2575.8145 8113.507 2588.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042.493 2588.5C8049.817 2575.8145 8063.352 2568 8078 2568"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113.507 2629.5C8106.183 2642.1856 8092.648 2650 8078 2650"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042.493 2629.5C8035.169 2616.8145 8035.169 2601.1856 8042.493 2588.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042.493 5180.5C8035.169 5167.8146 8035.169 5152.1857 8042.493 5139.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 5201C8063.352 5201 8049.817 5193.1857 8042.493 5180.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8078 5119C8092.648 5119 8106.183 5126.8146 8113.507 5139.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8042.493 5139.5C8049.817 5126.8146 8063.352 5119 8078 5119"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8113.507 5180.5C8106.183 5193.1857 8092.648 5201 8078 5201"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2078 5201C2063.352 5201 2049.817 5193.1857 2042.4929 5180.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2113.507 5139.5C2120.831 5152.1857 2120.831 5167.8146 2113.507 5180.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2042.4929 5180.5C2035.1691 5167.8146 2035.1691 5152.1857 2042.4929 5139.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2113.507 5180.5C2106.183 5193.1857 2092.648 5201 2078 5201"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2042.4929 5139.5C2049.817 5126.8146 2063.352 5119 2078 5119"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436.507 1809.5C6443.831 1822.1854 6443.831 1837.8146 6436.507 1850.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6365.493 1809.5C6372.817 1796.8146 6386.352 1789 6401 1789"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 1871C6386.352 1871 6372.817 1863.1854 6365.493 1850.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6401 1789C6415.648 1789 6429.183 1796.8146 6436.507 1809.5"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6436.507 1850.5C6429.183 1863.1854 6415.648 1871 6401 1871"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6519 6000C6519 5934.8308 6466.1696 5882 6401 5882 6335.8308 5882 6283 5934.8308 6283 6000 6283 6065.1696 6335.8308 6118 6401 6118 6466.1696 6118 6519 6065.1696 6519 6000"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2196 2609C2196 2543.8304 2143.1697 2491 2078 2491 2012.8305 2491 1960 2543.8304 1960 2609 1960 2674.1697 2012.8305 2727 2078 2727 2143.1697 2727 2196 2674.1697 2196 2609"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8202 5160C8202 5091.5168 8146.4836 5036 8078 5036 8009.5168 5036 7954 5091.5168 7954 5160 7954 5228.4836 8009.5168 5284 8078 5284 8146.4836 5284 8202 5228.4836 8202 5160"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6525 6000C6525 5931.5168 6469.4836 5876 6401 5876 6332.5168 5876 6277 5931.5168 6277 6000 6277 6068.4836 6332.5168 6124 6401 6124 6469.4836 6124 6525 6068.4836 6525 6000"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2105 5621C2105 5580.131 2071.8692 5547 2031 5547 1990.1309 5547 1957 5580.131 1957 5621 1957 5661.869 1990.1309 5695 2031 5695 2071.8692 5695 2105 5661.869 2105 5621"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2116.5 5621C2116.5 5573.78 2078.2205 5535.5 2031 5535.5 1983.7797 5535.5 1945.5 5573.78 1945.5 5621 1945.5 5668.22 1983.7797 5706.5 2031 5706.5 2078.2205 5706.5 2116.5 5668.22 2116.5 5621"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8199 2243C8199 2202.1309 8165.869 2169 8125 2169 8084.131 2169 8051 2202.1309 8051 2243 8051 2283.8692 8084.131 2317 8125 2317 8165.869 2317 8199 2283.8692 8199 2243"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8210.5 2243C8210.5 2195.7796 8172.22 2157.5 8125 2157.5 8077.78 2157.5 8039.5 2195.7796 8039.5 2243 8039.5 2290.2205 8077.78 2328.5 8125 2328.5 8172.22 2328.5 8210.5 2290.2205 8210.5 2243"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3879 6000C3879 5931.5168 3823.4835 5876 3755 5876 3686.5167 5876 3631 5931.5168 3631 6000 3631 6068.4836 3686.5167 6124 3755 6124 3823.4835 6124 3879 6068.4836 3879 6000"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8199 5621C8199 5580.131 8165.869 5547 8125 5547 8084.131 5547 8051 5580.131 8051 5621 8051 5661.869 8084.131 5695 8125 5695 8165.869 5695 8199 5661.869 8199 5621"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8210.5 5621C8210.5 5573.78 8172.22 5535.5 8125 5535.5 8077.78 5535.5 8039.5 5573.78 8039.5 5621 8039.5 5668.22 8077.78 5706.5 8125 5706.5 8172.22 5706.5 8210.5 5668.22 8210.5 5621"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2105 2243C2105 2202.1309 2071.8692 2169 2031 2169 1990.1309 2169 1957 2202.1309 1957 2243 1957 2283.8692 1990.1309 2317 2031 2317 2071.8692 2317 2105 2283.8692 2105 2243"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2116.5 2243C2116.5 2195.7796 2078.2205 2157.5 2031 2157.5 1983.7797 2157.5 1945.5 2195.7796 1945.5 2243 1945.5 2290.2205 1983.7797 2328.5 2031 2328.5 2078.2205 2328.5 2116.5 2290.2205 2116.5 2243"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8202 2609C8202 2540.5167 8146.4836 2485 8078 2485 8009.5168 2485 7954 2540.5167 7954 2609 7954 2677.4835 8009.5168 2733 8078 2733 8146.4836 2733 8202 2677.4835 8202 2609"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6525 1830C6525 1761.5167 6469.4836 1706 6401 1706 6332.5168 1706 6277 1761.5167 6277 1830 6277 1898.4833 6332.5168 1954 6401 1954 6469.4836 1954 6525 1898.4833 6525 1830"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3879 1830C3879 1761.5167 3823.4835 1706 3755 1706 3686.5167 1706 3631 1761.5167 3631 1830 3631 1898.4833 3686.5167 1954 3755 1954 3823.4835 1954 3879 1898.4833 3879 1830"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2202 2609C2202 2540.5167 2146.4835 2485 2078 2485 2009.5167 2485 1954 2540.5167 1954 2609 1954 2677.4835 2009.5167 2733 2078 2733 2146.4835 2733 2202 2677.4835 2202 2609"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2202 5160C2202 5091.5168 2146.4835 5036 2078 5036 2009.5167 5036 1954 5091.5168 1954 5160 1954 5228.4836 2009.5167 5284 2078 5284 2146.4835 5284 2202 5228.4836 2202 5160"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3873 6000C3873 5934.8308 3820.1697 5882 3755 5882 3689.8304 5882 3637 5934.8308 3637 6000 3637 6065.1696 3689.8304 6118 3755 6118 3820.1697 6118 3873 6065.1696 3873 6000"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M3873 1830C3873 1764.8305 3820.1697 1712 3755 1712 3689.8304 1712 3637 1764.8305 3637 1830 3637 1895.1696 3689.8304 1948 3755 1948 3820.1697 1948 3873 1895.1696 3873 1830"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8196 2609C8196 2543.8304 8143.1696 2491 8078 2491 8012.8308 2491 7960 2543.8304 7960 2609 7960 2674.1697 8012.8308 2727 8078 2727 8143.1696 2727 8196 2674.1697 8196 2609"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M8196 5160C8196 5094.8308 8143.1696 5042 8078 5042 8012.8308 5042 7960 5094.8308 7960 5160 7960 5225.1696 8012.8308 5278 8078 5278 8143.1696 5278 8196 5225.1696 8196 5160"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M2196 5160C2196 5094.8308 2143.1697 5042 2078 5042 2012.8305 5042 1960 5094.8308 1960 5160 1960 5225.1696 2012.8305 5278 2078 5278 2143.1697 5278 2196 5225.1696 2196 5160"/>
<path transform="matrix(.12,0,0,-.12,0,842)" stroke-width="9" stroke-linecap="round" stroke-linejoin="round" fill="none" stroke="#000000" d="M6519 1830C6519 1764.8305 6466.1696 1712 6401 1712 6335.8308 1712 6283 1764.8305 6283 1830 6283 1895.1696 6335.8308 1948 6401 1948 6466.1696 1948 6519 1895.1696 6519 1830"/>''';
const _spacerSanitizedBody =
    '<g transform="matrix(.12,0,0,-.12,0,842)"><path d="M5668.5 3932C5668.5 3605.8758 5404.124 3341.5 5078 3341.5 4751.876 3341.5 4487.5 3605.8758 4487.5 3932 4487.5 4258.124 4751.876 4522.5 5078 4522.5 5404.124 4522.5 5668.5 4258.124 5668.5 3932" stroke="#FF8C00" stroke-width="14" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M5692 3932C5692 3592.8973 5417.103 3318 5078 3318 4738.897 3318 4464 3592.8973 4464 3932 4464 4271.103 4738.897 4546 5078 4546 5417.103 4546 5692 4271.103 5692 3932" stroke="#FF8C00" stroke-width="14" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M5904.5 3932C5904.5 3475.5367 5534.4636 3105.5 5078 3105.5 4621.5368 3105.5 4251.5 3475.5367 4251.5 3932 4251.5 4388.4636 4621.5368 4758.5 5078 4758.5 5534.4636 4758.5 5904.5 4388.4636 5904.5 3932" stroke="#FF8C00" stroke-width="14" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>';

class _SpacerPlacementDiagram extends StatelessWidget {
  const _SpacerPlacementDiagram({required this.cornerIndex});

  final int cornerIndex;

  @override
  Widget build(BuildContext context) {
    final lineArt =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    final idx = cornerIndex.clamp(0, 3);
    const viewBoxes = [
      '0 360 794 320',
      '397 360 794 320',
      '397 90 794 320',
      '0 90 794 320',
    ];
    final vb = viewBoxes[idx];
    final isBottom = idx == 0 || idx == 1;
    final isLeft = idx == 0 || idx == 3;
    final svg = SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="794" height="320" viewBox="$vb">$_lcdSanitizedBody</svg>',
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(lineArt, BlendMode.srcIn),
    );
    Widget child = SizedBox(width: 794, height: 320, child: svg);
    child = ShaderMask(
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
        end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        colors: const [Colors.transparent, Colors.black],
        stops: const [0.0, 0.32],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: child,
    );
    child = ShaderMask(
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: isBottom ? Alignment.topCenter : Alignment.bottomCenter,
        end: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
        colors: const [Colors.transparent, Colors.black],
        stops: const [0.0, 0.42],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: child,
    );
    // Spacer puck inside the inner LCD rect, near its corner
    final vbParts2 = vb.split(' ').map(double.parse).toList();
    final vx2 = vbParts2[0],
        vy2 = vbParts2[1],
        vw2 = vbParts2[2],
        vh2 = vbParts2[3];
    double sx2(double x) => (x - vx2) / vw2;
    double sy2(double y) => (y - vy2) / vh2;
    const ix2 = 220.0, iy2 = 190.0, iw2 = 751.0, ih2 = 462.0;
    final isBottom2 = idx == 0 || idx == 1;
    final isLeft2 = idx == 0 || idx == 3;
    final cx2 = isLeft2 ? ix2 : ix2 + iw2;
    final cy2 = isBottom2 ? iy2 + ih2 : iy2;
    // Puck 30% larger vs 44px outer -> 57px, keep inside with small pad
    const puckOuter = 57.0;
    const puckInner = 42.0;
    // Per-corner pads: Front Left is reference (82/92); other corners need less due to viewBox cropping
    final double edgePadX = isLeft2 ? 82.0 : 52.0;
    final double edgePadY = isBottom2 ? 92.0 : 22.0;
    final px2 =
        isLeft2 ? cx2 + puckOuter + edgePadX : cx2 - puckOuter - edgePadX;
    final py2 =
        isBottom2 ? cy2 - puckOuter - edgePadY : cy2 + puckOuter + edgePadY;
    // Two SVGs sharing the same 794x320 viewBox so puck locks to screen, but only LCD is muted
    final lcdSvg = SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="794" height="320" viewBox="$vb">$_lcdSanitizedBody</svg>',
      fit: BoxFit.contain,
      colorFilter:
          ColorFilter.mode(lineArt.withValues(alpha: 0.35), BlendMode.srcIn),
    );
    final puckSvgStr =
        '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="794" height="320" viewBox="$vb"><circle cx="$px2" cy="$py2" r="$puckOuter" fill="#FF8C00" fill-opacity="0.14" stroke="#FF8C00" stroke-width="3.8"/><circle cx="$px2" cy="$py2" r="$puckInner" fill="#FF8C00" fill-opacity="0.10" stroke="#FF8C00" stroke-width="3"/></svg>';
    final puckSvg2 = SvgPicture.string(puckSvgStr, fit: BoxFit.contain);
    Widget lcdBox = SizedBox(width: 794, height: 320, child: lcdSvg);
    lcdBox = ShaderMask(
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
        end: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        colors: const [Colors.transparent, Colors.black],
        stops: const [0.0, 0.32],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: lcdBox,
    );
    lcdBox = ShaderMask(
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: isBottom ? Alignment.topCenter : Alignment.bottomCenter,
        end: isBottom ? Alignment.bottomCenter : Alignment.topCenter,
        colors: const [Colors.transparent, Colors.black],
        stops: const [0.0, 0.42],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: lcdBox,
    );
    final puckBox = SizedBox(width: 794, height: 320, child: puckSvg2);
    // Apply the same fades to the puck box? No, keep puck solid — but keep position locked via same viewBox
    return Stack(children: [lcdBox, puckBox]);
  }
}

class _AlignPlatePainter extends CustomPainter {
  _AlignPlatePainter({required this.plateColor, required this.lcdColor});

  final Color plateColor;
  final Color lcdColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Second and third horizontal lines from the bottom of the
    // 786×280 viewBox (bottom half crop) — front edges that must be
    // parallel. Fractions recomputed for the cropped height.
    const plateY = 0.744;
    const lcdY = 0.814;
    const left = 0.07;
    const right = 0.93;
    final platePaint = Paint()
      ..color = plateColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final lcdPaint = Paint()
      ..color = lcdColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(left * size.width, plateY * size.height),
      Offset(right * size.width, plateY * size.height),
      platePaint,
    );
    canvas.drawLine(
      Offset(left * size.width, lcdY * size.height),
      Offset(right * size.width, lcdY * size.height),
      lcdPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AlignPlatePainter old) =>
      old.plateColor != plateColor || old.lcdColor != lcdColor;
}

// ================================================================================================================================================================================================
// Phase: Screen Type Selection (recycles the select-arm UX)
// ================================================================================================================================================================================================

class _ScreenTypeSelectionPane extends StatelessWidget {
  const _ScreenTypeSelectionPane({
    super.key,
    required this.onScreenTypeSelected,
  });

  final ValueChanged<LevelingScreenType> onScreenTypeSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('screenType'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < LevelingScreenType.values.length; i++) ...[
                if (i > 0) const SizedBox(width: OrionSpacing.controlGap),
                Expanded(
                  child: _ScreenTypeCard(
                    screenType: LevelingScreenType.values[i],
                    onPressed: () =>
                        onScreenTypeSelected(LevelingScreenType.values[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ScreenTypeCard extends StatelessWidget {
  const _ScreenTypeCard({
    required this.screenType,
    required this.onPressed,
  });

  final LevelingScreenType screenType;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      outlined: true,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(glassCornerRadius),
        onTap: onPressed,
        child: Padding(
          padding: OrionSpacing.cardPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.85,
                    child: AspectRatio(
                      // Screen-like proportions, not a square.
                      aspectRatio: 16 / 10,
                      child: ScreenTypeVisual(
                        screenType: screenType,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: OrionSpacing.listGap),
              Text(
                FlutterI18n.translate(context, screenType.labelKey),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: OrionSpacing.compactListGap),
              Text(
                FlutterI18n.translate(context, screenType.descriptionKey),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================================================================================================================================================
// Phase: Workflow Execution (calibration progress overlay style)
// ================================================================================================================================================================================================

class _WorkflowPane extends StatelessWidget {
  static const _cornerLabels = [
    'Front Left',
    'Front Right',
    'Back Right',
    'Back Left',
  ];

  /// Pass through raw corner Z values (cantilever compensation disabled).
  static List<double?> _compensatedZ(List<double?> raw) {
    return raw;
  }

  const _WorkflowPane({
    super.key,
    required this.engine,
    required this.effectivelyRunning,
    required this.autoAdvancing,
    required this.loosenScrewsDone,
    required this.tightenScrewsDone,
    required this.alignDone,
    required this.hexLongEndDone,
    required this.cornerResults,
    required this.cornerZs,
    this.preAdjustmentDeviation,
  });
  final LevelingWorkflowEngine engine;
  final bool effectivelyRunning;
  final bool autoAdvancing;
  final bool loosenScrewsDone;
  final bool tightenScrewsDone;
  final bool alignDone;
  final bool hexLongEndDone;
  final List<ForceLevelingWorkflowResponse?> cornerResults;

  /// values the wizard actually levels with; the results view must
  /// display the same numbers.
  final List<double?> cornerZs;
  final double? preAdjustmentDeviation;

  @override
  Widget build(BuildContext context) {
    if (engine.isComplete) {
      return _CompletionPane(engine: engine);
    }

    final step = engine.currentStep;
    if (step == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    // Intermediate screens from step metadata (only on stepComplete)
    final isComplete = engine.status == LevelingWorkflowStatus.stepComplete;
    final String? intermediate = step.intermediateScreen;
    final isLoosenScrews =
        isComplete && intermediate == 'loosen' && !loosenScrewsDone;
    final isAlignPlate = isComplete && intermediate == 'tighten' && !alignDone;
    final isHexLongEnd =
        isComplete && intermediate == 'tighten' && alignDone && !hexLongEndDone;
    final isTightenScrews = isComplete &&
        intermediate == 'tighten' &&
        alignDone &&
        hexLongEndDone &&
        !tightenScrewsDone;
    final isAllCornersMeasured = isComplete && intermediate == 'allCorners';
    final isRemovePuck = isComplete && intermediate == 'removePuck';

    // Suppress the one-frame empty-step flash before a skipBackend/autoAdvance
    // target is run. Once the target reaches stepComplete its intermediate
    // (allCorners/removePuck etc.) must be shown, so don't hide after.
    if (autoAdvancing &&
        step.skipBackend &&
        step.intermediateScreen != null &&
        engine.status != LevelingWorkflowStatus.stepComplete) {
      return const Center(child: SizedBox.shrink());
    }
    final content = effectivelyRunning
        ? _buildRunningView(context, primary, step)
        : isLoosenScrews
            ? _buildLoosenScrewsView(context, primary)
            : isAlignPlate
                ? _buildAlignPlateView(context, primary)
                : isHexLongEnd
                    ? _buildHexLongEndView(context, primary)
                    : isTightenScrews
                        ? _buildTightenScrewsView(context, primary)
                        : isAllCornersMeasured
                            ? _buildAllCornersMeasuredView(context, primary)
                            : isRemovePuck
                                ? _buildRemovePuckView(context, primary)
                                : _buildStepView(context, theme, primary, step);
    // Unique key per pictogram so Loosen->Align->HexLong->Tighten cross-fades
    // even when they share the same underlying step id (all depend on status==stepComplete).
    final String viewId;
    if (isLoosenScrews) {
      viewId = 'loosen';
    } else if (isAlignPlate) {
      viewId = 'align';
    } else if (isHexLongEnd) {
      viewId = 'hexLong';
    } else if (isTightenScrews) {
      viewId = 'tighten';
    } else if (isAllCornersMeasured) {
      viewId = 'allCorners';
    } else if (isRemovePuck) {
      viewId = 'removePuck';
    } else {
      // Idle step view (Place Spacer) vs running Keep Clear for same step.id
      // must cross-fade: prefix with run/idle so same index still animates.
      viewId = '${effectivelyRunning ? 'run-' : 'idle-'}${step.id}';
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild
        ],
      ),
      child: Center(
        key: ValueKey(
            'workflow-${engine.currentStepIndex}-${engine.status.name}-${effectivelyRunning ? 'run' : 'idle'}-$viewId'),
        child: content,
      ),
    );
  }

  Widget _buildLoosenScrewsView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    // The 3-screw sequence diagram is Pro-Arm-specific; the standard
    // arm's screw layout differs, so it keeps the icon-only screen.
    final showDiagram = engine.variant?.id == 'pro';
    final title = Text(
      FlutterI18n.translate(context, 'leveling.loosenTitle'),
      textAlign: TextAlign.center,
      // Matches the wizard's AppBar title convention.
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
    final instruction = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        FlutterI18n.translate(context, 'leveling.loosenInstruction'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          height: 1.4,
          color: onSurface.withValues(alpha: 0.72),
        ),
      ),
    );

    // Pictogram layout: title and subtitle sit in the app-bar header
    // position; the diagram scales up into the remaining space.
    if (showDiagram) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              children: [
                title,
                const SizedBox(height: OrionSpacing.compactListGap),
                instruction,
              ],
            ),
          ),
          // FittedBox under loose constraints would render at the
          // diagram's natural 254×192 size, so compute the scale here
          // and hand it a tight box instead. Capped for a slight bump.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = min(
                  (constraints.maxWidth - 24) / 254,
                  (constraints.maxHeight - 16) / 192,
                ).clamp(1.0, 1.35);
                return Center(
                  child: SizedBox(
                    width: 254 * scale,
                    height: 192 * scale,
                    child: const FittedBox(
                      fit: BoxFit.contain,
                      child: _ScrewSequenceDiagram(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.12),
          ),
          child: Icon(
            PhosphorIcons.wrench(),
            size: 52,
            color: primary,
          ),
        ),
        const SizedBox(height: 20),
        title,
        const SizedBox(height: 8),
        instruction,
      ],
    );
  }

  Widget _buildRunningView(
    BuildContext context,
    Color primary,
    LevelingWorkflowStep step,
  ) {
    // Definitive movement state per step, so the subtitle names where
    // the machine is actually going instead of a generic label.
    final title = step.runningTitle ??
        switch (step.kind) {
          LevelingWorkflowStepKind.finalOffset =>
            FlutterI18n.translate(context, 'leveling.wizardSavingOffset'),
          LevelingWorkflowStepKind.prepare
              when step.endpoint == 'probe_prepare' =>
            FlutterI18n.translate(context, 'leveling.wizardMovingHome'),
          LevelingWorkflowStepKind.prepare
              when step.endpoint == 'probe_corner_prepare' =>
            FlutterI18n.translate(context, 'leveling.wizardMovingPark'),
          _ => switch (step.endpoint) {
              'probe_screen' ||
              'probe_levelcheck' ||
              'probe_standardarm' =>
                FlutterI18n.translate(context, 'leveling.wizardMovingToScreen'),
              'probe_corner' =>
                FlutterI18n.translate(context, 'leveling.wizardMovingCorner'),
              _ => FlutterI18n.translate(
                  context, 'leveling.wizardPreparingMachine'),
            },
        };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _IsoMovementWarning(),
        const SizedBox(height: 32),
        Text(
          FlutterI18n.translate(context, 'leveling.wizardKeepHandsClear'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              height: 1.4,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlignPlateView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final title = Text(
      FlutterI18n.translate(context, 'leveling.wizardAlignTitle'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
    final instruction = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        FlutterI18n.translate(context, 'leveling.wizardAlignInstr'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          height: 1.4,
          color: onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              title,
              const SizedBox(height: OrionSpacing.compactListGap),
              instruction,
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = min(
                min((constraints.maxWidth - 24) / 786,
                    (constraints.maxHeight - 16) / 280),
                1.35,
              );
              return Center(
                child: SizedBox(
                  width: 786 * scale,
                  height: 280 * scale,
                  child: const FittedBox(
                    fit: BoxFit.contain,
                    child: _AlignPlateDiagram(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHexLongEndView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final title = Text(
      FlutterI18n.translate(context, 'leveling.hexLongEndTitle'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
    final rawInstruction =
        FlutterI18n.translate(context, 'leveling.hexLongEndInstruction');
    final instruction = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: _buildHighlightedInstruction(
        context,
        rawInstruction,
        'long',
        TextStyle(
          fontSize: 20,
          height: 1.4,
          color: onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              title,
              const SizedBox(height: OrionSpacing.compactListGap),
              instruction,
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = min(
                min((constraints.maxWidth - 24) / 886,
                    (constraints.maxHeight - 16) / 324),
                1.35,
              );
              return Center(
                child: SizedBox(
                  width: 886 * scale,
                  height: 324 * scale,
                  child: const FittedBox(
                    fit: BoxFit.contain,
                    child: _HexKeyLongEndDiagram(),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTightenScrewsView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    // Same 3-screw diagram as loosen, but tightening is clockwise.
    final showDiagram = engine.variant?.id == 'pro';
    final title = Text(
      FlutterI18n.translate(context, 'leveling.tightenTitle'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.primary,
      ),
    );
    final instruction = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        engine.variant?.id == 'pro'
            ? FlutterI18n.translate(context, 'leveling.tightenInstructionPro')
            : FlutterI18n.translate(
                context, 'leveling.tightenInstructionStandard'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          height: 1.4,
          color: onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
    if (showDiagram) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              children: [
                title,
                const SizedBox(height: OrionSpacing.compactListGap),
                instruction,
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = min(
                  min((constraints.maxWidth - 24) / 254,
                      (constraints.maxHeight - 16) / 192),
                  1.35,
                );
                return Center(
                  child: SizedBox(
                    width: 254 * scale,
                    height: 192 * scale,
                    child: const FittedBox(
                      fit: BoxFit.contain,
                      child: _ScrewSequenceDiagram(clockwise: true),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.12),
          ),
          child: Icon(
            PhosphorIcons.clockClockwise(),
            size: 52,
            color: primary,
          ),
        ),
        const SizedBox(height: 20),
        title,
        const SizedBox(height: 8),
        instruction,
      ],
    );
  }

  Widget _buildRemovePuckView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.12),
          ),
          child: Icon(
            PhosphorIconsFill.hand,
            size: 52,
            color: primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          FlutterI18n.translate(context, 'leveling.wizardRemovePuck'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            FlutterI18n.translate(context, 'leveling.wizardRemovePuckInstr'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              height: 1.4,
              color: onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAllCornersMeasuredView(BuildContext context, Color primary) {
    final theme = Theme.of(context);
    final rawZ = cornerZs;

    // Front-corner Z values are displayed raw (cantilever compensation disabled).
    final compZ = _compensatedZ(rawZ);
    final validZ = compZ.whereType<double>().toList();
    final minZ = validZ.isEmpty ? 0.0 : validZ.reduce((a, b) => a < b ? a : b);
    final maxZ = validZ.isEmpty ? 0.0 : validZ.reduce((a, b) => a > b ? a : b);
    final deviation = maxZ - minZ;
    final withinTolerance = deviation <= 0.100;
    final statusColor = withinTolerance ? Colors.greenAccent : Colors.redAccent;

    // Use raw values for display (cantilever compensation disabled).
    final dispZ = compZ;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              withinTolerance
                  ? PhosphorIconsFill.checkCircle
                  : PhosphorIcons.warning(),
              size: 24,
              color: statusColor,
            ),
            const SizedBox(width: 10),
            Text(
              FlutterI18n.translate(context, 'leveling.wizardCornerResults'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: statusColor.withValues(alpha: 0.15),
              ),
              child: Text(
                withinTolerance
                    ? FlutterI18n.translate(context, 'leveling.wizardPass')
                    : FlutterI18n.translate(context, 'leveling.wizardFail'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Divergence warning: recheck is worse than the pre-adjustment check.
        // Gate 0.15 mm — leapfrog overshoot plus probe noise is expected
        // growth, not divergence.
        if (preAdjustmentDeviation != null &&
            deviation > preAdjustmentDeviation! + 0.15)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.orangeAccent.withValues(alpha: 0.15),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.warningOctagon(),
                    size: 20, color: Colors.orangeAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    FlutterI18n.translate(
                        context, 'leveling.wizardDivergedWarning'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orangeAccent,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Corner measurements - fill remaining space
        Expanded(
          child: GlassCard(
            outlined: true,
            margin: EdgeInsets.zero,
            child: Stack(
              children: [
                // Back Left — top-left (back of printer, facing away)
                Positioned(
                  top: OrionSpacing.cardPadding.top,
                  left: OrionSpacing.cardPadding.left,
                  child: _cornerValueCard(
                    theme,
                    _cornerLabels[3],
                    dispZ[3],
                    validZ,
                    minZ,
                    maxZ,
                  ),
                ),
                // Back Right — top-right
                Positioned(
                  top: OrionSpacing.cardPadding.top,
                  right: OrionSpacing.cardPadding.right,
                  child: _cornerValueCard(
                    theme,
                    _cornerLabels[2],
                    dispZ[2],
                    validZ,
                    minZ,
                    maxZ,
                  ),
                ),
                // Front Right — bottom-right (front of printer, facing us)
                Positioned(
                  bottom: OrionSpacing.cardPadding.bottom,
                  right: OrionSpacing.cardPadding.right,
                  child: _cornerValueCard(
                    theme,
                    _cornerLabels[1],
                    dispZ[1],
                    validZ,
                    minZ,
                    maxZ,
                  ),
                ),
                // Front Left — bottom-left
                Positioned(
                  bottom: OrionSpacing.cardPadding.bottom,
                  left: OrionSpacing.cardPadding.left,
                  child: _cornerValueCard(
                    theme,
                    _cornerLabels[0],
                    dispZ[0],
                    validZ,
                    minZ,
                    maxZ,
                  ),
                ),
                // Total deviation — dead center
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        FlutterI18n.translate(
                            context, 'leveling.wizardTotalDeviation'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            deviation.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              height: 1,
                            ),
                          ),
                          Text(
                            FlutterI18n.translate(
                                context, 'leveling.wizardDeviationLimit'),
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: statusColor.withValues(alpha: 0.12),
                        ),
                        child: Text(
                          withinTolerance
                              ? FlutterI18n.translate(
                                  context, 'leveling.wizardWithinTolerance')
                              : FlutterI18n.translate(
                                  context, 'leveling.wizardNeedsAdjust'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cornerValueCard(
    ThemeData theme,
    String label,
    double? z,
    List<double> validZ,
    double minZ,
    double maxZ,
  ) {
    final isLowest = validZ.isNotEmpty && z == minZ;
    final isHighest = validZ.isNotEmpty && z == maxZ;
    final dotColor = isHighest
        ? Colors.greenAccent
        : isLowest
            ? Colors.orangeAccent
            : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isHighest)
                Icon(PhosphorIcons.caretDoubleUp(), size: 14, color: dotColor),
              if (isLowest)
                Icon(PhosphorIcons.caretDoubleDown(),
                    size: 14, color: dotColor),
              if (!isHighest && !isLowest)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            z != null ? '${(z - maxZ).toStringAsFixed(2)} mm' : '--',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: dotColor,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepView(
    BuildContext context,
    ThemeData theme,
    Color primary,
    LevelingWorkflowStep step,
  ) {
    final titleStr =
        step.stepTitle ?? FlutterI18n.translate(context, step.titleKey);
    final instructionStr = step.stepInstruction ??
        FlutterI18n.translate(context, step.instructionKey);

    // "Place Leveling Spacer" steps get a corner-focused pictogram:
    // bottom half + left 2/3 = FL, bottom+right = FR, top+right = BR,
    // top+left = BL — per spec, using a2_lcd_ui_top_view crops.
    if (step.id.startsWith('fine_prepare_')) {
      final cornerNum =
          int.tryParse(step.id.replaceFirst('fine_prepare_', '')) ?? 1;
      final cornerIndex = (cornerNum - 1).clamp(0, 3);
      final onSurface = theme.colorScheme.onSurface;
      final title = Text(
        titleStr,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      );
      final instruction = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          instructionStr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            height: 1.4,
            color: onSurface.withValues(alpha: 0.72),
          ),
        ),
      );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              children: [
                title,
                const SizedBox(height: 8),
                instruction,
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Fill the vertical space, whole width - make the pictogram as tall as possible
                final availableH = constraints.maxHeight;
                final availableW = constraints.maxWidth;
                // Use the diagram's aspect to compute size that fills height first
                const diagramAspect = 794 / 320;
                double h = availableH - 16;
                double w = h * diagramAspect;
                if (w > availableW - 24) {
                  w = availableW - 24;
                  h = w / diagramAspect;
                }
                // Cap like other diagrams
                final cappedScale = (w / 794).clamp(0.0, 1.6);
                w = 794 * cappedScale;
                h = 421 * cappedScale;
                return Center(
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: _SpacerPlacementDiagram(
                      cornerIndex: cornerIndex,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ====== Icon ======
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary.withValues(alpha: 0.10),
          ),
          child: Icon(
            step.icon,
            key: const ValueKey('icon'),
            size: 52,
            color: primary,
          ),
        ),
        const SizedBox(height: 20),
        // ====== Title ======
        Text(
          titleStr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: primary,
          ),
        ),
        const SizedBox(height: 8),
        // ====== Instruction ======
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            instructionStr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              height: 1.4,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================================================================================================================================================
// Adjustment Feedback — live force gauge
// ================================================================================================================================================================================================

class _AdjustmentFeedbackScreen extends StatefulWidget {
  const _AdjustmentFeedbackScreen({
    super.key,
    required this.cornerIndex,
    this.cornerForce,
    this.targetForce,
    this.allCornerForces = const [],
    this.forceDelta,
    this.needsTighten = false,
    this.needsLoosen = false,
    this.predictionDirection,
    this.predictionScrew,
    this.predictionZMm,
    this.predictionRechecks,
    this.consecutiveBackAdjustments = 0,
    this.onAchievedForce,
  });

  final int cornerIndex;
  final double? cornerForce;
  final double? targetForce;
  final List<double> allCornerForces;
  final double? forceDelta;
  final bool needsTighten;
  final bool needsLoosen;
  final String? predictionDirection;
  final String? predictionScrew;
  final double? predictionZMm;
  final int? predictionRechecks;
  final int consecutiveBackAdjustments;

  /// Reports the smoothed live force mapped back into the PROBE frame
  /// (live EMA minus the probe→live offset) on every gauge tick.  The
  /// wizard keeps the last value so the recheck log can record where
  /// the user actually stopped relative to the suggested target.
  final ValueChanged<double>? onAchievedForce;

  @override
  State<_AdjustmentFeedbackScreen> createState() =>
      _AdjustmentFeedbackScreenState();
}

class _AdjustmentFeedbackScreenState extends State<_AdjustmentFeedbackScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  AnalyticsProvider? _analytics;
  VoidCallback? _analyticsListener;
  bool _analyticsDisposed = false;

  // Live force EMA — everything in gram-force.
  double? _emaForce;
  static const double _emaAlpha = 0.25;

  // Probe→live frame anchor.  The gauge target is expressed in the
  // probe's force frame (first-stage peak); live analytics readings sit
  // in a different frame.  The offset is the mean of the first few RAW
  // live samples minus the probe force, captured before the user starts
  // turning.  (An earlier revision computed the offset from the EMA —
  // which was still initialized to the probe force at that moment — so
  // the offset was always 0 and the needle slowly drifted from the
  // probe frame into the live frame while the user was chasing it.)
  static const int _anchorSampleCount = 5;
  final List<double> _anchorSamples = [];
  double? _liveOffset;

  double? get _smoothedForce => _emaForce;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_analytics != null) return;
    _analytics = Provider.of<AnalyticsProvider>(context, listen: false);
    _analyticsListener = () {
      if (_analyticsDisposed) return;
      final series = _analytics!.pressureSeries;
      if (series.isEmpty) return;
      final raw = (series.last['v'] as num?)?.toDouble();
      if (raw == null) return;
      // Anchor the probe→live offset on the first few raw samples.
      if (_anchorSamples.length < _anchorSampleCount &&
          widget.cornerForce != null) {
        _anchorSamples.add(raw);
        final mean =
            _anchorSamples.reduce((a, b) => a + b) / _anchorSamples.length;
        _liveOffset = mean - widget.cornerForce!;
      }
      // EMA runs purely in the live frame; until the first sample
      // arrives the gauge falls back to the static probe-frame delta.
      if (_emaForce == null) {
        _emaForce = raw;
      } else {
        _emaForce = _emaAlpha * raw + (1.0 - _emaAlpha) * _emaForce!;
      }
      // Report the achieved force in the probe frame so the wizard can
      // log where the user actually stopped vs the suggested target.
      if (_liveOffset != null && _emaForce != null) {
        widget.onAchievedForce?.call(_emaForce! - _liveOffset!);
      }
      setState(() {});
    };
    _analytics!.addListener(_analyticsListener!);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _analyticsDisposed = true;
    if (_analytics != null && _analyticsListener != null) {
      _analytics!.removeListener(_analyticsListener!);
    }
    super.dispose();
  }

  String get _adjustmentTitle {
    if (widget.cornerIndex <= 1) {
      return widget.cornerIndex == 0
          ? FlutterI18n.translate(context, 'leveling.wizardAdjustFL')
          : FlutterI18n.translate(context, 'leveling.wizardAdjustFR');
    }
    return FlutterI18n.translate(context, 'leveling.wizardAdjustRear');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    // Live force vs target, both in the live-analytics reference frame.
    // The controller's target is shifted into the live frame via the
    // probe→live offset anchored on the first raw analytics samples.
    //
    // live − target: positive → corner lower than target → TIGHTEN.
    // live − target: negative → corner higher than target → LOOSEN.
    final double? forceDelta;
    if (_smoothedForce != null &&
        widget.targetForce != null &&
        _liveOffset != null) {
      final liveTarget = widget.targetForce! + _liveOffset!;
      forceDelta = _smoothedForce! - liveTarget;
    } else {
      forceDelta = widget.forceDelta; // fallback to static value
    }

    // Gauge scale: ±2000 gf maps to the full range (~ ±20 N).
    const forceScale = 2000.0;
    final position =
        forceDelta != null ? (forceDelta / forceScale).clamp(-1.0, 1.0) : 0.0;
    // Live direction from actual force delta with ±20 gf green zone.
    // Uses the live force delta so the label, accent, and rotation
    // update in real time as the user tightens or loosens the screw.
    final liveNeedsTighten = forceDelta != null && forceDelta > 20;
    final liveNeedsLoosen = forceDelta != null && forceDelta < -20;
    final directionLabel = liveNeedsTighten
        ? FlutterI18n.translate(context, 'leveling.wizardTighten')
        : liveNeedsLoosen
            ? FlutterI18n.translate(context, 'leveling.wizardLoosen')
            : FlutterI18n.translate(context, 'leveling.wizardAtTarget');
    final accent = liveNeedsLoosen
        ? const Color(0xFFFF6B6B)
        : liveNeedsTighten
            ? const Color(0xFFFFC16D)
            : const Color(0xFF57F0A4);
    // Rotation direction: -1 = CCW (loosen), 1 = CW (tighten), 0 = at target
    final rotationDirection = liveNeedsTighten
        ? 1
        : liveNeedsLoosen
            ? -1
            : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _adjustmentTitle,
              style: TextStyle(
                color: accent,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ====== Left: screw diagram + title ======
                        Expanded(
                          flex: 1,
                          child: Container(
                            height: 280,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 18,
                            ),
                            decoration: BoxDecoration(
                              color: onSurface.withValues(alpha: 0.035),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: onSurface.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Center(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Center(
                                            child: AnimatedBuilder(
                                              animation: Listenable.merge([
                                                _pulseController,
                                                _rotationController
                                              ]),
                                              builder: (context, _) =>
                                                  _AdjustScrewPictogram(
                                                cornerIndex: widget.cornerIndex,
                                                accent: accent,
                                                onSurface: onSurface,
                                                pulse: _pulseController.value,
                                                rotationValue:
                                                    _rotationController.value,
                                                rotationDirection:
                                                    rotationDirection,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Text(
                                            directionLabel,
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        // ====== Right: force readout + gauge ======
                        Expanded(
                          flex: 1,
                          child: Container(
                            height: 280,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 18,
                            ),
                            decoration: BoxDecoration(
                              color: onSurface.withValues(alpha: 0.035),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: onSurface.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Stack(
                              children: [
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Text(
                                    FlutterI18n.translate(
                                        context, 'leveling.wizardZDeviation'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: onSurface.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Center(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Force value
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          top: 13,
                                          bottom: 47,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 24),
                                                child: SizedBox(
                                                  width: 220,
                                                  child: Text(
                                                    forceDelta != null
                                                        ? forceDelta
                                                            .toStringAsFixed(1)
                                                        : '--',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 49,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontFeatures: const [
                                                        FontFeature
                                                            .tabularFigures(),
                                                      ],
                                                      height: 1,
                                                      color: accent,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 7),
                                              Text(
                                                'gf',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                  color: accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Gauge
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 260,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  height: 28,
                                                  child: LayoutBuilder(
                                                    builder: (_, trackBox) {
                                                      final w =
                                                          trackBox.maxWidth;
                                                      // Dot moves toward the direction to turn:
                                                      // right → tighten (CW), left → loosen (CCW).
                                                      // position > 0 → tighten → dot goes right
                                                      // position < 0 → loosen → dot goes left
                                                      final dotFrac =
                                                          ((1.0 + position) /
                                                                  2.0)
                                                              .clamp(0.0, 1.0);
                                                      final centerX = w / 2;
                                                      final dotCenter =
                                                          dotFrac * w;
                                                      final fillLeft =
                                                          dotCenter < centerX
                                                              ? dotCenter
                                                              : centerX;
                                                      final fillWidth =
                                                          (dotCenter - centerX)
                                                              .abs();
                                                      return Stack(
                                                        clipBehavior: Clip.none,
                                                        children: [
                                                          ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        14),
                                                            child: Container(
                                                              color: onSurface
                                                                  .withValues(
                                                                      alpha:
                                                                          0.08),
                                                            ),
                                                          ),
                                                          Positioned(
                                                            left: centerX - 1,
                                                            top: 0,
                                                            bottom: 0,
                                                            child: Container(
                                                              width: 2,
                                                              color: onSurface
                                                                  .withValues(
                                                                      alpha:
                                                                          0.15),
                                                            ),
                                                          ),
                                                          if (fillWidth > 0)
                                                            Positioned(
                                                              left: fillLeft,
                                                              top: 0,
                                                              bottom: 0,
                                                              width: fillWidth,
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            14),
                                                                child:
                                                                    Container(
                                                                  color: accent
                                                                      .withValues(
                                                                          alpha:
                                                                              0.50),
                                                                ),
                                                              ),
                                                            ),
                                                          Positioned(
                                                            left:
                                                                dotCenter - 14,
                                                            top: 0,
                                                            child: Container(
                                                              width: 28,
                                                              height: 28,
                                                              decoration:
                                                                  BoxDecoration(
                                                                shape: BoxShape
                                                                    .circle,
                                                                color: accent,
                                                                border: Border.all(
                                                                    color: Colors
                                                                        .white,
                                                                    width: 3),
                                                                boxShadow: [
                                                                  BoxShadow(
                                                                    color: accent
                                                                        .withValues(
                                                                            alpha:
                                                                                0.35),
                                                                    blurRadius:
                                                                        6,
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
                                                const SizedBox(height: 6),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      FlutterI18n.translate(
                                                          context,
                                                          'leveling.wizardLooser'),
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: onSurface
                                                              .withValues(
                                                                  alpha: 0.3)),
                                                    ),
                                                    Text(
                                                      FlutterI18n.translate(
                                                          context,
                                                          'leveling.wizardTighter'),
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: onSurface
                                                              .withValues(
                                                                  alpha: 0.3)),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ================================================================================================================================================================================================
// Equilateral Screw Triangle
// ================================================================================================================================================================================================

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({
    required this.accent,
    required this.onSurface,
    required this.fillBack,
    required this.fillFl,
    required this.fillFr,
    this.pulse = 0.0,
    this.rotationValue = 0.0,
    this.rotationDirection = 0,
  });

  final Color accent;
  final Color onSurface;
  final bool fillBack;
  final bool fillFl;
  final bool fillFr;
  final double pulse;
  final double rotationValue;
  final int rotationDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Equilateral triangle arrangement (just the dots, no lines).
    const spacing = 62.0;
    final triH = spacing * 0.866; // spacing * sqrt(3)/2

    final backX = cx;
    final backY = cy - triH / 2;
    final flX = cx - spacing / 2;
    final flY = cy + triH / 2;
    final frX = cx + spacing / 2;
    final frY = cy + triH / 2;

    const r = 13.0;
    _drawDot(canvas, backX, backY, r, fillBack);
    _drawDot(canvas, flX, flY, r, fillFl);
    _drawDot(canvas, frX, frY, r, fillFr);

    // Rotating arc around the highlighted dot
    if (fillFl || fillFr || fillBack) {
      final dotX = fillBack ? backX : (fillFl ? flX : frX);
      final dotY = fillBack ? backY : (fillFl ? flY : frY);
      _drawRotatingArc(canvas, dotX, dotY, r + 10);
    }
  }

  void _drawRotatingArc(Canvas canvas, double cx, double cy, double radius) {
    final arcPaint = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Continuously rotate: CW for tighten (direction=1), CCW for loosen (direction=-1)
    final angle = rotationValue * 2 * 3.14159265 * rotationDirection;
    const arcSpan = 3.0;

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      angle - arcSpan / 2,
      arcSpan,
      false,
      arcPaint,
    );

    // Bold dot at the leading tip (opposite end for CCW)
    final tipAngle =
        angle + (rotationDirection >= 0 ? arcSpan / 2 : -arcSpan / 2);
    final tipX = cx + radius * cos(tipAngle);
    final tipY = cy + radius * sin(tipAngle);

    canvas.drawCircle(
        Offset(tipX, tipY),
        4.0,
        Paint()
          ..color = accent.withValues(alpha: 0.9)
          ..style = PaintingStyle.fill);
  }

  void _drawDot(Canvas canvas, double cx, double cy, double r, bool filled) {
    final paint = Paint()
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 2.5;
    if (filled) {
      // Pulse opacity: 0.5 \u2192 1.0 \u2192 0.5
      paint.color = accent.withValues(alpha: 0.5 + pulse * 0.5);
      // Bump radius so filled dot visually matches the outlined one
      canvas.drawCircle(Offset(cx, cy), r + 1.5, paint);
    } else {
      paint.color = accent;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.fillBack != fillBack ||
      oldDelegate.fillFl != fillFl ||
      oldDelegate.fillFr != fillFr ||
      oldDelegate.pulse != pulse ||
      oldDelegate.rotationValue != rotationValue ||
      oldDelegate.rotationDirection != rotationDirection;
}

/// Pictogram for the adjust-X screen: reuses the Pro-Arm top-view SVG
/// with the three screws at their real positions. Highlights the screw
/// that the gauge wants the user to turn, with a pulsing dot and a
/// continuously rotating direction arc.
class _AdjustScrewPictogram extends StatelessWidget {
  const _AdjustScrewPictogram({
    required this.cornerIndex,
    required this.accent,
    required this.onSurface,
    required this.rotationDirection,
    required this.pulse,
    required this.rotationValue,
  });

  final int cornerIndex;
  final Color accent;
  final Color onSurface;
  final int rotationDirection;
  final double pulse;
  final double rotationValue;

  @override
  Widget build(BuildContext context) {
    final lineArt = onSurface.withValues(alpha: 0.35);
    return SizedBox(
      width: 254,
      height: 192,
      child: Stack(
        children: [
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.transparent],
                stops: [0.78, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SvgPicture.asset(
              'assets/images/concepts_3d/levelingsystem/a2_pro_arm_solo_leveling_screws_top.svg',
              fit: BoxFit.contain,
              colorFilter: ColorFilter.mode(lineArt, BlendMode.srcIn),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _AdjustScrewPictogramPainter(
                accent: accent,
                onSurface: onSurface,
                screwIndex: cornerIndex == 0
                    ? 2
                    : cornerIndex == 1
                        ? 1
                        : 0,
                pulse: pulse,
                rotationValue: rotationValue,
                rotationDirection: rotationDirection,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdjustScrewPictogramPainter extends CustomPainter {
  _AdjustScrewPictogramPainter({
    required this.accent,
    required this.onSurface,
    required this.screwIndex,
    required this.pulse,
    required this.rotationValue,
    required this.rotationDirection,
  });

  final Color accent;
  final Color onSurface;
  final int screwIndex;
  final double pulse;
  final double rotationValue;
  final int rotationDirection;

  static const _screwFractions = [
    Offset(0.499, 0.267), // 0 top / BACK
    Offset(0.673, 0.665), // 1 FR / bottom-right
    Offset(0.326, 0.665), // 2 FL / bottom-left
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 3; i++) {
      final pos = Offset(
        _screwFractions[i].dx * size.width,
        _screwFractions[i].dy * size.height,
      );
      final isActive = i == screwIndex;
      if (isActive) {
        canvas.drawCircle(
          pos,
          5.0,
          Paint()
            ..color = onSurface.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          pos,
          5.0,
          Paint()
            ..color = onSurface.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        if (rotationDirection != 0) {
          final shadowStroke = Paint()
            ..color = Colors.black.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
          final shadowFill = Paint()
            ..color = Colors.black.withValues(alpha: 0.6)
            ..style = PaintingStyle.fill
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
          final angle = rotationValue * 2 * pi * rotationDirection;
          const sweep = 250 * pi / 180;
          final arc = Path()
            ..arcTo(Rect.fromCircle(center: pos, radius: 23), angle,
                rotationDirection >= 0 ? sweep : -sweep, false);
          _strokeDashed(canvas, arc, shadowStroke);
          final arcStart = pos + Offset(cos(angle) * 23, sin(angle) * 23);
          final arcEnd = pos +
              Offset(
                  cos(angle + (rotationDirection >= 0 ? sweep : -sweep)) * 23,
                  sin(angle + (rotationDirection >= 0 ? sweep : -sweep)) * 23);
          final isTighten = rotationDirection >= 0;
          final arcGradient = ui.Gradient.linear(
              arcStart,
              arcEnd,
              isTighten
                  ? const [Color(0xFFFF8C00), Color(0xFFE65100)]
                  : const [Color(0xFF2E7D32), Color(0xFF81C784)]);
          final arcPaint = Paint()
            ..shader = arcGradient
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round;
          _strokeDashed(canvas, arc, arcPaint);
          final endAngle = angle + (rotationDirection >= 0 ? sweep : -sweep);
          final tip = pos + Offset(cos(endAngle) * 23, sin(endAngle) * 23);
          final direction = rotationDirection >= 0
              ? Offset(-sin(endAngle), cos(endAngle))
              : Offset(sin(endAngle), -cos(endAngle));
          _drawArrowhead(canvas, tip, direction, shadowFill);
          _drawArrowhead(
              canvas,
              tip,
              direction,
              Paint()
                ..color = isTighten
                    ? const Color(0xFFE65100)
                    : const Color(0xFF81C784)
                ..style = PaintingStyle.fill);
        }
      } else {
        canvas.drawCircle(
          pos,
          5.0,
          Paint()
            ..color = onSurface.withValues(alpha: 0.25)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          pos,
          5.0,
          Paint()
            ..color = onSurface.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
  }

  void _strokeDashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      double pos = 0;
      while (pos < m.length) {
        canvas.drawPath(m.extractPath(pos, min(pos + 5, m.length)), paint);
        pos += 9;
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset at, Offset direction, Paint paint) {
    final tip = at + direction * 9;
    final perp = Offset(-direction.dy, direction.dx) * 6;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(at.dx + perp.dx, at.dy + perp.dy)
        ..lineTo(at.dx - perp.dx, at.dy - perp.dy)
        ..close(),
      paint..style = PaintingStyle.fill,
    );
    paint.style = PaintingStyle.stroke;
  }

  @override
  bool shouldRepaint(covariant _AdjustScrewPictogramPainter old) =>
      old.accent != accent ||
      old.onSurface != onSurface ||
      old.screwIndex != screwIndex ||
      old.pulse != pulse ||
      old.rotationValue != rotationValue ||
      old.rotationDirection != rotationDirection;
}

// ================================================================================================================================================================================================
// Completion Pane (calibration-overlay style)
// ================================================================================================================================================================================================

class _CompletionPane extends StatelessWidget {
  const _CompletionPane({required this.engine});

  final LevelingWorkflowEngine engine;

  @override
  Widget build(BuildContext context) {
    final variant = engine.variant;
    final theme = Theme.of(context);

    return Center(
      key: const ValueKey('complete'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withValues(alpha: 0.15),
            ),
            child: const Icon(
              PhosphorIconsFill.checkCircle,
              size: 56,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            FlutterI18n.translate(context, 'levelingWorkflow.complete'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.greenAccent,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              FlutterI18n.translate(
                context,
                variant?.successKey ?? 'levelingWorkflow.offsetSuccess',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
