/*
* Orion - Standby Overlay
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

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/backend_service/providers/lighting_provider.dart';
import 'package:orion/backend_service/providers/standby_settings_provider.dart';
import 'package:orion/util/orion_config.dart';
import 'package:logging/logging.dart';
import 'dart:ui' as ui;

final Logger _log = Logger('StandbyOverlay');

/// A fullscreen standby overlay that appears after a period of inactivity.
/// Shows a bold clock in the accent color on a black background.
class StandbyOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Duration inactivityDuration;

  const StandbyOverlay({
    super.key,
    required this.child,
    this.enabled = true,
    this.inactivityDuration = const Duration(minutes: 2, seconds: 30),
  });

  @override
  State<StandbyOverlay> createState() => _StandbyOverlayState();
}

class _StandbyOverlayState extends State<StandbyOverlay>
    with TickerProviderStateMixin {
  Timer? _inactivityTimer;
  bool _isStandbyActive = false;
  bool _standbyThrottled = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _clockUpdateTimer;
  String _currentTime = '';

  // DVD-logo bounce state
  Ticker? _bounceTicker;
  double _logoX = 0;
  double _logoY = 0;
  double _logoDx = 0.6; // pixels per frame at ~60fps
  double _logoDy = 0.45;
  bool _bounceInitialized = false;
  static const double _logoSize = 180;
  Color _logoTint = Colors.white;
  late String _logoAssetPath;
  // Throttle bounce redraws: only setState when the logo is actually
  // visible, and only at ~15fps (every 4th vsync tick).
  bool _bounceIsLogoMode = false;
  int _bounceTick = 0;

  // Dimming variables
  late AnimationController _dimmingController;
  late Animation<double> _dimmingAnimation;
  int _originalBrightness = 255;
  int _dimmingStartBrightness = 255;
  static const int _minBrightness = 13; // 5% of 255
  bool _isExitingStandby = false;
  bool _blockRgbInStandby = false;

  // Finished celebration state
  bool _celebrationActive = false;
  bool _celebrationCompleted = false;
  bool _wasPrinting = false;
  bool _wasPrintingOrPaused = false;
  bool _celebrationStartScheduled = false;
  Timer? _celebrationTimer;
  late AnimationController _fireworksController;
  late AnimationController _checkmarkController;
  late Animation<double> _checkmarkScale;
  late Animation<double> _checkmarkFade;
  final List<_FireworkBurst> _fireworkBursts = [];

  // Canceled state
  bool _canceledActive = false;
  bool _canceledCompleted = false;
  bool _canceledStartScheduled = false;
  Timer? _canceledTimer;
  late AnimationController _cancelIconController;
  late Animation<double> _cancelIconScale;
  late Animation<double> _cancelIconFade;
  late AnimationController _cancelShakeController;
  late AnimationController _cancelResinController;
  List<_BloodDrip> _bloodDrips = [];
  late AnimationController _cancelBrickController;
  List<_LayerBrick> _layerBricks = [];

  // Paused pulse
  late AnimationController _pausePulseController;

  // Track previous settings to detect changes
  bool? _prevStandbyEnabled;
  int? _prevDurationSeconds;
  bool _wakeOnPrintStartScheduled = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Dimming animation controller (3 seconds for smooth dim)
    _dimmingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _dimmingAnimation = CurvedAnimation(
      parent: _dimmingController,
      curve: Curves.easeInOut,
    );
    _dimmingAnimation.addListener(_handleDimmingTick);

    _fireworksController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _checkmarkController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _checkmarkScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _checkmarkController, curve: Curves.elasticOut),
    );
    _checkmarkFade = CurvedAnimation(
      parent: _checkmarkController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _initFireworks();

    // Canceled icon entrance
    _cancelIconController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _cancelIconScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _cancelIconController, curve: Curves.elasticOut),
    );
    _cancelIconFade = CurvedAnimation(
      parent: _cancelIconController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    // Subtle shake
    _cancelShakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    // Resin drip animation (single forward pass over total display time)
    _cancelResinController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    _initBloodDrips();
    // Brick wall crumble animation
    _cancelBrickController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );
    _initLayerBricks();

    // Pause pulse
    _pausePulseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    _updateTime();
    _resetInactivityTimer();
    _resolveLogoAsset();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _clockUpdateTimer?.cancel();
    _bounceTicker?.dispose();
    _celebrationTimer?.cancel();
    _canceledTimer?.cancel();
    _fadeController.dispose();
    _dimmingController.dispose();
    _fireworksController.dispose();
    _checkmarkController.dispose();
    _cancelIconController.dispose();
    _cancelShakeController.dispose();
    _cancelResinController.dispose();
    _cancelBrickController.dispose();
    _pausePulseController.dispose();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    // Get current settings from provider if available
    if (context.mounted) {
      final standbySettings =
          Provider.of<StandbySettingsProvider>(context, listen: false);
      if (standbySettings.standbyEnabled) {
        _inactivityTimer = Timer(
            Duration(seconds: standbySettings.durationSeconds),
            _activateStandby);
      }
    }
  }

  void _activateStandby() {
    if (!context.mounted) return;

    final standbySettings =
        Provider.of<StandbySettingsProvider>(context, listen: false);

    if (!_isStandbyActive && widget.enabled && standbySettings.standbyEnabled) {
      // Don't activate standby while a leveling workflow is in progress
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);
      if (statusProvider.isLevelingWorkflowActive) return;

      // Block RGB commands if there's been print activity since the last
      // explicit wake — otherwise we'd disrupt the printer's internal LED
      // control during/after a print.
      final isActiveJob = (statusProvider.status?.isPrinting ?? false) ||
          (statusProvider.status?.isPaused ?? false) ||
          statusProvider.isPausing ||
          statusProvider.isCanceling;
      if (isActiveJob || _wasPrintingOrPaused) {
        _blockRgbInStandby = true;
      }

      setState(() {
        _isStandbyActive = true;
        _isExitingStandby = false;
      });
      _fadeController.forward();
      _startClockUpdate();
      _startBounce();
      _startDimming(); // Will check dimming config internally
      // Throttle background status polling while in standby if not printing.
      final isPrinting = statusProvider.status?.isPrinting ?? false;
      _syncStandbyThrottling(statusProvider, isPrinting);
    }
  }

  void _deactivateStandby() {
    if (_isStandbyActive) {
      _isExitingStandby = true;
      // User explicitly woke the printer — RGB is safe to use next standby.
      _blockRgbInStandby = false;
      // Restore brightness immediately so screen and UI return together.
      _stopDimming();
      // Speed up the fade-out (return to app) significantly
      _fadeController
          .animateTo(
        0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      )
          .then((_) {
        if (mounted) {
          setState(() {
            _isStandbyActive = false;
            _isExitingStandby = false;
          });
        }
        _resetCelebrationState(resetCompleted: true);
        _resetCanceledState(resetCompleted: true);
      });
      _stopClockUpdate();
      _stopBounce();
      // Resume status polling when leaving standby.
      final statusProvider =
          Provider.of<StatusProvider>(context, listen: false);
      _syncStandbyThrottling(statusProvider, false, forceResume: true);
      _resetInactivityTimer();
    }
  }

  void _syncStandbyThrottling(StatusProvider statusProvider, bool isActiveJob,
      {bool forceResume = false}) {
    if (!_isStandbyActive || forceResume) {
      if (_standbyThrottled) {
        statusProvider.exitStandbyMode();
        _standbyThrottled = false;
      }
      return;
    }

    // When idle in standby, switch to slow polling so we still detect
    // remotely-started prints.
    if (!isActiveJob && !_standbyThrottled) {
      statusProvider.enterStandbyMode();
      _standbyThrottled = true;
    } else if (isActiveJob && _standbyThrottled) {
      // Active job detected — restore full-speed polling / SSE.
      statusProvider.exitStandbyMode();
      _standbyThrottled = false;
    }
  }

  void _handleUserInteraction() {
    if (_isStandbyActive) {
      _deactivateStandby();
    } else {
      _resetInactivityTimer();
    }
  }

  void _scheduleWakeFromPrintStart() {
    if (_wakeOnPrintStartScheduled) return;
    _wakeOnPrintStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wakeOnPrintStartScheduled = false;
      if (!mounted) return;
      if (_isStandbyActive) {
        _deactivateStandby();
      }
    });
  }

  void _startClockUpdate() {
    _updateTime();
    // Update once per second to flip immediately at minute boundaries
    _clockUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTime();
    });
  }

  void _stopClockUpdate() {
    _clockUpdateTimer?.cancel();
    _clockUpdateTimer = null;
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        // Show hours and minutes only
        _currentTime = DateFormat('HH:mm').format(DateTime.now());
      });
    }
  }

  void _handleDimmingTick() {
    if (!_isStandbyActive || _isExitingStandby) {
      return;
    }

    final progress = _dimmingAnimation.value;
    final currentBrightness =
        (_dimmingStartBrightness * (1 - progress) + _minBrightness * progress)
            .toInt();
    _writeBrightness(currentBrightness);
    unawaited(_applyStandbyLedProgress(progress));
  }

  Future<void> _applyStandbyLedProgress(double progress) async {
    if (!context.mounted || !_isStandbyActive || _isExitingStandby) return;
    if (_blockRgbInStandby) return;

    final lighting = Provider.of<LightingProvider>(context, listen: false);
    await lighting.applyStandbyProgress(progress);
  }

  String _getBacklightDevice() {
    if (context.mounted) {
      final standbySettings =
          Provider.of<StandbySettingsProvider>(context, listen: false);
      return standbySettings.backlightDevice;
    }
    return '';
  }

  String _getBrightnessPath() {
    final device = _getBacklightDevice();
    if (device.isEmpty) return '';
    return '/sys/class/backlight/$device/brightness';
  }

  Future<int> _readBrightness() async {
    try {
      final path = _getBrightnessPath();
      if (path.isEmpty) return 255;

      final file = File(path);
      if (!await file.exists()) return 255;

      final contents = await file.readAsString();
      return int.tryParse(contents.trim()) ?? 255;
    } catch (e) {
      _log.severe('Error reading brightness: $e');
      return 255;
    }
  }

  Future<void> _writeBrightness(int level) async {
    try {
      final path = _getBrightnessPath();
      if (path.isEmpty) return;

      // Try writing directly first (in case permissions are already set)
      try {
        final file = File(path);
        await file.writeAsString(level.toString());
        return;
      } catch (_) {
        // Direct write failed, try with sudo
      }

      // Fall back to sudo method
      try {
        final process = await Process.start('sudo', ['tee', path]);
        process.stdin.writeln(level.toString());
        await process.stdin.close();
        await process.exitCode;
        // Don't treat non-zero exit code as error - some systems may have issues
        // but we still want to continue dimming
      } catch (e) {
        _log.warning('Brightness write skipped: $e');
      }
    } catch (e) {
      _log.severe('Error writing brightness: $e');
    }
  }

  Future<void> _startDimming() async {
    try {
      if (!context.mounted) return;

      final standbySettings =
          Provider.of<StandbySettingsProvider>(context, listen: false);
      if (!standbySettings.dimmingEnabled) {
        // Screen dimming disabled: still apply standby LED behavior.
        await _applyStandbyLedProgress(1.0);
        return;
      }

      // Read current brightness for this dimming pass
      _dimmingStartBrightness = await _readBrightness();
      // Start the dimming animation
      await _dimmingController.forward(from: 0.0);
    } catch (e) {
      _log.severe('Error starting dimming: $e');
    }
  }

  Future<void> _stopDimming() async {
    try {
      // Stop animation
      _dimmingController.stop();
      _dimmingController.reset();

      // Instantly restore brightness
      _originalBrightness = 255;
      await _writeBrightness(_originalBrightness);

      if (!mounted) return;
      if (!_blockRgbInStandby) {
        final lighting = Provider.of<LightingProvider>(context, listen: false);
        await lighting.setFullBrightness();
      }
    } catch (e) {
      _log.severe('Error stopping dimming: $e');
    }
  }

  void _pauseDimmingForCelebration() {
    _dimmingController.stop();
    _dimmingController.reset();
  }

  Future<void> _boostBrightnessForCelebration() async {
    try {
      _pauseDimmingForCelebration();
      await _writeBrightness(255);
      if (!mounted) return;
      if (!_blockRgbInStandby) {
        final lighting = Provider.of<LightingProvider>(context, listen: false);
        await lighting.setFullBrightness();
      }
    } catch (e) {
      _log.severe('Error boosting brightness: $e');
    }
  }

  void _initFireworks() {
    _fireworkBursts.clear();
    final rand = math.Random();

    // Rich palette — warm golds, cool cyans, greens, pinks, with varied
    // saturation so it doesn't look flat.
    final palettes = <List<Color>>[
      [
        const Color(0xFF00E676),
        const Color(0xFF69F0AE),
        const Color(0xFFB9F6CA)
      ],
      [
        const Color(0xFF00BCD4),
        const Color(0xFF84FFFF),
        const Color(0xFFE0F7FA)
      ],
      [
        const Color(0xFFFFD740),
        const Color(0xFFFFAB40),
        const Color(0xFFFFF8E1)
      ],
      [
        const Color(0xFFFF4081),
        const Color(0xFFFF80AB),
        const Color(0xFFFCE4EC)
      ],
      [
        const Color(0xFF7C4DFF),
        const Color(0xFFB388FF),
        const Color(0xFFEDE7F6)
      ],
      [
        const Color(0xFF00E5FF),
        const Color(0xFF18FFFF),
        const Color(0xFFE0F7FA)
      ],
    ];

    // 10 bursts spread across the full screen, with staggered delays
    for (var i = 0; i < 10; i++) {
      // Place bursts using a scattered grid so they cover the display
      // fractional x: 0.1..0.9, fractional y: 0.15..0.85
      final fx = 0.1 + rand.nextDouble() * 0.8;
      final fy = 0.15 + rand.nextDouble() * 0.7;
      final palette = palettes[rand.nextInt(palettes.length)];

      // Stagger burst timing across the 0..1 animation cycle
      final delay = (i / 10) * 0.55 + rand.nextDouble() * 0.15;

      // 28-40 particles per burst for density
      final count = 28 + rand.nextInt(13);
      final particles = List.generate(count, (_) {
        final angle = rand.nextDouble() * 2 * math.pi;
        final speed = 0.6 + rand.nextDouble() * 0.8; // varied speeds
        final radius = 80.0 + rand.nextDouble() * 140.0;
        final size = 2.0 + rand.nextDouble() * 5.0;
        final color = palette[rand.nextInt(palette.length)];
        // Individual fade jitter so particles don't all vanish at once
        final fadeStart = 0.3 + rand.nextDouble() * 0.35;
        return _FireworkParticle(
          angle: angle,
          radius: radius,
          color: color,
          speed: speed,
          size: size,
          fadeStart: fadeStart,
          gravity: 40.0 + rand.nextDouble() * 60.0,
        );
      });

      _fireworkBursts.add(_FireworkBurst(
        fractionalX: fx,
        fractionalY: fy,
        particles: particles,
        delay: delay,
      ));
    }
  }

  void _scheduleCelebrationStart() {
    if (_celebrationStartScheduled || _celebrationActive) return;
    _celebrationStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _celebrationStartScheduled = false;
      if (!_celebrationActive) _startCelebration();
    });
  }

  void _startCelebration() {
    if (!mounted) return;
    _initFireworks(); // re-randomise each time
    setState(() {
      _celebrationActive = true;
      _celebrationCompleted = false;
    });
    _celebrationTimer?.cancel();
    _checkmarkController.forward(from: 0.0);
    _fireworksController.repeat(period: const Duration(seconds: 3));
    _boostBrightnessForCelebration();
    _celebrationTimer = Timer(const Duration(seconds: 20), _endCelebration);
  }

  void _endCelebration() {
    if (!mounted) return;
    _fireworksController.stop();
    setState(() {
      _celebrationActive = false;
      _celebrationCompleted = true;
    });

    if (context.mounted) {
      final standbySettings =
          Provider.of<StandbySettingsProvider>(context, listen: false);
      if (_isStandbyActive && standbySettings.dimmingEnabled) {
        _startDimming();
      }
    }
  }

  void _resetCelebrationState({bool resetCompleted = false}) {
    _celebrationTimer?.cancel();
    _fireworksController.stop();
    _checkmarkController.reset();
    _celebrationStartScheduled = false;
    if (!mounted) return;
    setState(() {
      _celebrationActive = false;
      if (resetCompleted) {
        _celebrationCompleted = false;
      }
    });
  }

  // --- Canceled state helpers ---

  void _scheduleCanceledStart() {
    if (_canceledStartScheduled || _canceledActive) return;
    _canceledStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _canceledStartScheduled = false;
      if (!_canceledActive) _startCanceled();
    });
  }

  void _startCanceled() {
    if (!mounted) return;
    final funMode = OrionConfig().getFlag('funMode', category: 'ui');
    if (funMode) {
      _initBloodDrips(); // re-randomise each time
    } else {
      _initLayerBricks(); // generate brick wall
    }
    setState(() {
      _canceledActive = true;
      _canceledCompleted = false;
    });
    _canceledTimer?.cancel();
    _cancelIconController.forward(from: 0.0);
    _cancelShakeController.forward(from: 0.0);
    if (funMode) {
      _cancelResinController.forward(from: 0.0);
    } else {
      _cancelBrickController.forward(from: 0.0);
    }
    _boostBrightnessForCelebration();
    // Show for 10 seconds then crossfade to clock
    _canceledTimer = Timer(const Duration(seconds: 10), _endCanceled);
  }

  void _endCanceled() {
    if (!mounted) return;
    setState(() {
      _canceledActive = false;
      _canceledCompleted = true;
    });

    if (context.mounted) {
      final standbySettings =
          Provider.of<StandbySettingsProvider>(context, listen: false);
      if (_isStandbyActive && standbySettings.dimmingEnabled) {
        _startDimming();
      }
    }
  }

  void _resetCanceledState({bool resetCompleted = false}) {
    _canceledTimer?.cancel();
    _cancelIconController.reset();
    _cancelShakeController.reset();
    _cancelResinController.stop();
    _cancelResinController.reset();
    _cancelBrickController.stop();
    _cancelBrickController.reset();
    _canceledStartScheduled = false;
    if (!mounted) return;
    setState(() {
      _canceledActive = false;
      if (resetCompleted) {
        _canceledCompleted = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Consume StatusProvider to check if a print is active
    // Also consume StandbySettingsProvider to react to setting changes
    return Consumer2<StatusProvider, StandbySettingsProvider>(
      builder: (ctx, statusProvider, standbySettings, child) {
        // Check if standby settings have changed, and only reset timer if so
        if (_prevStandbyEnabled != standbySettings.standbyEnabled ||
            _prevDurationSeconds != standbySettings.durationSeconds) {
          _prevStandbyEnabled = standbySettings.standbyEnabled;
          _prevDurationSeconds = standbySettings.durationSeconds;

          // Reset timer on next frame when settings change
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resetInactivityTimer();
          });
        }

        final isPrinting = statusProvider.status?.isPrinting ?? false;
        final isPaused = statusProvider.status?.isPaused ?? false;
        final isPausing = statusProvider.isPausing;
        final isCancelingTransition = statusProvider.isCanceling;
        final status = statusProvider.status;
        // A print was canceled if either the model's isCanceled flag is set
        // (layer == null after a job) OR the cancel_latched hint from the
        // state handler is present (cancel mid-print where layer data remains).
        final isCanceled =
            (status?.isCanceled ?? false) || (status?.cancelLatched == true);
        final isFinished = status != null &&
            status.isIdle &&
            status.layer != null &&
            !isCanceled;
        final progress = statusProvider.status?.progress ?? 0.0;
        // Treat transitional states as active for throttling purposes.
        final isActiveJob =
            isPrinting || isPaused || isPausing || isCancelingTransition;
        // Block RGB commands from the moment any print activity is detected
        // until the user explicitly wakes the printer.
        if (isActiveJob) {
          _blockRgbInStandby = true;
        }
        _syncStandbyThrottling(statusProvider, isActiveJob);

        final startedActivePrint =
            (isPrinting || isPaused) && !_wasPrintingOrPaused;
        if (_isStandbyActive && startedActivePrint) {
          _scheduleWakeFromPrintStart();
        }

        // Manage pause pulse animation
        if ((isPaused || isPausing) && _isStandbyActive) {
          if (!_pausePulseController.isAnimating) {
            _pausePulseController.repeat(reverse: true);
          }
        } else {
          if (_pausePulseController.isAnimating) {
            _pausePulseController.stop();
            _pausePulseController.reset();
          }
        }

        if (_isStandbyActive) {
          // A new print started — reset any celebration/canceled overlays.
          if (isPrinting &&
              (_celebrationActive ||
                  _celebrationCompleted ||
                  _canceledActive ||
                  _canceledCompleted)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _resetCelebrationState(resetCompleted: true);
                _resetCanceledState(resetCompleted: true);
              }
            });
          }
          // Detect print finished (was printing → now finished).
          else if (!_celebrationActive &&
              !_celebrationCompleted &&
              _wasPrinting &&
              isFinished) {
            _scheduleCelebrationStart();
          }
          // Detect canceled (was printing/paused → now canceled).
          else if (!_canceledActive &&
              !_canceledCompleted &&
              !_celebrationActive &&
              _wasPrintingOrPaused &&
              isCanceled) {
            _scheduleCanceledStart();
          }
        }
        _wasPrinting = isPrinting;
        _wasPrintingOrPaused =
            isPrinting || isPaused || isPausing || isCancelingTransition;

        final Widget standbyContent;
        if (_celebrationActive) {
          standbyContent = _buildFinishedCelebration(ctx);
        } else if (_canceledActive) {
          standbyContent = _buildCanceledDisplay(ctx);
        } else if (_celebrationCompleted || _canceledCompleted) {
          standbyContent = Center(child: _buildClockDisplay(ctx));
        } else if (isPaused || isPausing) {
          standbyContent = Center(child: _buildPausedIndicator(ctx, progress));
        } else if (isPrinting) {
          standbyContent =
              Center(child: _buildProgressIndicator(ctx, progress));
        } else if (isCancelingTransition) {
          // During cancel transition, keep showing the progress ring
          // so the UI doesn't flash the clock before the canceled overlay.
          standbyContent =
              Center(child: _buildProgressIndicator(ctx, progress));
        } else {
          standbyContent = standbySettings.standbyMode == 'logo'
              ? _buildLogoDisplay(ctx)
              : Center(child: _buildClockDisplay(ctx));
        }

        // Track whether the logo is currently on screen so the bounce ticker
        // knows whether to schedule redraws. Assign directly — no setState
        // needed since this only affects the ticker, not the build output.
        _bounceIsLogoMode = _isStandbyActive &&
            !_celebrationActive &&
            !_canceledActive &&
            !_celebrationCompleted &&
            !_canceledCompleted &&
            !(isPaused || isPausing) &&
            !isPrinting &&
            !isCancelingTransition &&
            standbySettings.standbyMode == 'logo';

        return Listener(
          onPointerDown: (_) => _handleUserInteraction(),
          onPointerMove: (_) => _handleUserInteraction(),
          onPointerUp: (_) => _handleUserInteraction(),
          child: Stack(
            children: [
              widget.child,
              if (_isStandbyActive)
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: GestureDetector(
                    onTap: _deactivateStandby,
                    child: Container(
                      color: Colors.black,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: KeyedSubtree(
                          key: ValueKey<String>(
                            _celebrationActive
                                ? 'celebration'
                                : _canceledActive
                                    ? 'canceled'
                                    : (_celebrationCompleted ||
                                            _canceledCompleted)
                                        ? 'state-complete'
                                        : (isPaused || isPausing)
                                            ? 'paused'
                                            : (isPrinting ||
                                                    isCancelingTransition)
                                                ? 'printing'
                                                : standbySettings.standbyMode,
                          ),
                          child: standbyContent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _resolveLogoAsset() {
    try {
      final config = OrionConfig();
      final vendorLogo = config
          .getString('vendorLogo', category: 'vendor')
          .toLowerCase()
          .trim();
      switch (vendorLogo) {
        case 'c3d':
          _logoAssetPath = 'assets/images/concepts_3d/c3d.svg';
          break;
        case 'athena':
          _logoAssetPath = 'assets/images/concepts_3d/athena_logo.svg';
          break;
        case 'ora':
        default:
          _logoAssetPath =
              'assets/images/ora/open_resin_alliance_logo_darkmode.png';
      }
    } catch (_) {
      _logoAssetPath =
          'assets/images/ora/open_resin_alliance_logo_darkmode.png';
    }
  }

  void _startBounce() {
    _bounceInitialized = false;
    _bounceTicker?.dispose();
    _bounceTicker = createTicker(_onBounceTick)..start();
  }

  void _stopBounce() {
    _bounceTicker?.stop();
    _bounceTicker?.dispose();
    _bounceTicker = null;
    _bounceInitialized = false;
  }

  Color _randomAccentColor() {
    final rand = math.Random();
    // Softer pastel colors: lower saturation, higher lightness
    final hue = rand.nextDouble() * 360;
    return HSLColor.fromAHSL(1.0, hue, 0.45, 0.78).toColor();
  }

  void _onBounceTick(Duration elapsed) {
    if (!mounted) return;

    final size = MediaQuery.of(context).size;
    final maxX = size.width - _logoSize;
    final maxY = size.height - _logoSize;

    if (!_bounceInitialized) {
      // Start from a random position
      final rand = math.Random();
      _logoX = rand.nextDouble() * maxX.clamp(0, double.infinity);
      _logoY = rand.nextDouble() * maxY.clamp(0, double.infinity);
      _logoTint = _randomAccentColor();
      _bounceInitialized = true;
    }

    // Always update position every tick so bounce detection is correct
    // and motion is smooth the moment the mode switches to logo.
    _logoX += _logoDx;
    _logoY += _logoDy;

    bool bounced = false;
    if (_logoX <= 0) {
      _logoX = 0;
      _logoDx = _logoDx.abs();
      bounced = true;
    } else if (_logoX >= maxX) {
      _logoX = maxX;
      _logoDx = -_logoDx.abs();
      bounced = true;
    }

    if (_logoY <= 0) {
      _logoY = 0;
      _logoDy = _logoDy.abs();
      bounced = true;
    } else if (_logoY >= maxY) {
      _logoY = maxY;
      _logoDy = -_logoDy.abs();
      bounced = true;
    }

    if (bounced) {
      _logoTint = _randomAccentColor();
    }

    // Only schedule a rebuild when the logo is actually on screen.
    // In clock / progress / paused modes there is nothing to animate here —
    // the clock ticks via its own 1 Hz timer and the progress ring is static
    // (driven by status provider updates), so we avoid a 60 fps setState.
    // For the logo screensaver, throttle to ~15 fps — the bouncing icon
    // looks fine at that rate and cuts GPU work to ¼ of 60 fps.
    if (!_bounceIsLogoMode) return;
    _bounceTick++;
    if (_bounceTick % 4 != 0) return; // ~15 fps at 60 Hz vsync
    setState(() {});
  }

  Widget _buildLogoDisplay(BuildContext context) {
    final logoWidget = _logoAssetPath.endsWith('.svg')
        ? SvgPicture.asset(
            _logoAssetPath,
            width: _logoSize,
            height: _logoSize,
            colorFilter: ColorFilter.mode(_logoTint, BlendMode.srcIn),
          )
        : Image.asset(
            _logoAssetPath,
            width: _logoSize,
            height: _logoSize,
            color: _logoTint,
          );

    return Stack(
      children: [
        Positioned(
          left: _logoX,
          top: _logoY,
          child: SizedBox(
            width: _logoSize,
            height: _logoSize,
            child: logoWidget,
          ),
        ),
      ],
    );
  }

  Widget _buildClockDisplay(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;

    return Transform(
      alignment: Alignment.center,
      // Barlow Condensed is already tall; add a gentle extra vertical stretch
      transform: Matrix4.diagonal3Values(1.0, 1.25, 1.0),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(accentColor, Colors.white, 0.35)!,
              accentColor,
              Color.lerp(accentColor, Colors.black, 0.4)!,
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(bounds);
        },
        child: Text(
          _currentTime,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 150,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            letterSpacing: 2,
            decoration: TextDecoration.none,
            // Use tabular figures so digits/colon align nicely
            fontFeatures: const [ui.FontFeature.tabularFigures()],
            // Subtle glow/shadow for readability on pure black
            shadows: [
              Shadow(
                blurRadius: 8,
                color: Colors.black.withAlpha((0.5 * 255).toInt()),
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context, double progress) {
    final percentage = (progress * 100).toStringAsFixed(0);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 340,
          height: 340,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 14,
            strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            backgroundColor: Color.lerp(primaryColor, Colors.black, 0.9)!,
          ),
        ),
        Text(
          '$percentage%',
          style: TextStyle(
            fontFamily: 'AtkinsonHyperlegible',
            fontSize: 100,
            fontWeight: FontWeight.w500,
            color: primaryColor,
            decoration: TextDecoration.none,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
            shadows: [
              Shadow(
                blurRadius: 8,
                color: Colors.black.withAlpha((0.5 * 255).toInt()),
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPausedIndicator(BuildContext context, double progress) {
    final percentage = (progress * 100).toStringAsFixed(0);
    const pauseColor = Colors.orange;

    return AnimatedBuilder(
      animation: _pausePulseController,
      builder: (context, child) {
        // Gentle pulse: icon opacity oscillates 0.55 ↔ 1.0
        final pulse = 0.55 + 0.45 * _pausePulseController.value;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing pause icon
            Opacity(
              opacity: pulse,
              child: const Icon(
                Icons.pause_circle_filled,
                size: 160,
                color: pauseColor,
              ),
            ),
            const SizedBox(height: 28),
            // Percentage below the icon
            Text(
              '$percentage%',
              style: TextStyle(
                fontFamily: 'AtkinsonHyperlegible',
                fontSize: 48,
                fontWeight: FontWeight.w500,
                color: pauseColor.withValues(alpha: 0.7),
                decoration: TextDecoration.none,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }

  void _initBloodDrips() {
    final rand = math.Random();

    // 14-20 drips spread across the screen, varied sizes and speeds.
    final count = 14 + rand.nextInt(7);
    _bloodDrips = List.generate(count, (i) {
      final fx = 0.03 + rand.nextDouble() * 0.94;

      // Varied speed: some drips rush, some creep
      final speed = 0.4 + rand.nextDouble() * 0.8;

      // Width at origin (narrow) and max spread width
      final startWidth = 4.0 + rand.nextDouble() * 10.0;
      final maxWidth = startWidth + 6.0 + rand.nextDouble() * 20.0;

      // Stagger start (0..0.35 of animation)
      final delay = rand.nextDouble() * 0.35;

      // Slight horizontal drift
      final drift = (rand.nextDouble() - 0.5) * 15.0;

      // Asymmetry: left and right sides aren't equal
      // 0.3..0.7 means 30-70% of width goes to the left side
      final asymmetry = 0.3 + rand.nextDouble() * 0.4;

      // Edge wobble: per-drip waviness amplitude
      final wobble = 0.5 + rand.nextDouble() * 2.0;

      return _BloodDrip(
        fractionalX: fx,
        speed: speed,
        startWidth: startWidth,
        maxWidth: maxWidth,
        delay: delay,
        drift: drift,
        asymmetry: asymmetry,
        wobble: wobble,
      );
    });
  }

  /// Generate a grid of layer bricks arranged like a brick wall.
  /// Each brick knows which side of the crack it's on and gets per-brick
  /// randomised rotation, fall speed, and drift.
  void _initLayerBricks() {
    final rand = math.Random();
    _layerBricks = [];

    // We build a virtual wall that will be rendered relative to screen size.
    // Using fractional coordinates (0..1) for both x and y.
    const rows = 12;
    const cols = 8;
    const brickH = 1.0 / rows;
    const brickW = 1.0 / cols;
    // Brick-wall offset: every other row is shifted by half a brick
    for (var r = 0; r < rows; r++) {
      final rowOffset = (r.isOdd) ? brickW * 0.5 : 0.0;
      for (var c = -1; c <= cols; c++) {
        final fx = c * brickW + rowOffset;
        final fy = r * brickH;

        // Skip bricks fully outside screen
        if (fx + brickW < -0.01 || fx > 1.01) continue;

        // Which side of center? Left half falls left, right half falls right.
        // Bricks straddling the center crack get split visually by the painter.
        final centerX = fx + brickW / 2;
        final isLeft = centerX < 0.5;

        // Per-brick randomness for organic breakup
        final fallDelay = 0.05 + rand.nextDouble() * 0.25;
        // Bricks near the crack start moving first
        final distFromCrack = (centerX - 0.5).abs();
        final crackDelay = distFromCrack * 0.3;
        final totalDelay = (fallDelay + crackDelay).clamp(0.0, 0.5);

        final rotationSpeed = 0.5 + rand.nextDouble() * 2.0;
        final fallSpeed = 0.8 + rand.nextDouble() * 0.6;
        // Drift away from center
        final driftDir = isLeft ? -1.0 : 1.0;
        final drift = driftDir * (0.02 + rand.nextDouble() * 0.08);

        // Slight size and position jitter for organic feel
        final jitterX = (rand.nextDouble() - 0.5) * 0.003;
        final jitterY = (rand.nextDouble() - 0.5) * 0.003;

        _layerBricks.add(_LayerBrick(
          fx: fx + jitterX,
          fy: fy + jitterY,
          fw: brickW,
          fh: brickH,
          isLeft: isLeft,
          delay: totalDelay,
          fallSpeed: fallSpeed,
          rotationSpeed: rotationSpeed,
          drift: drift,
          // Colour variation: alternating warm greys like cured resin layers
          shade: 0.25 + rand.nextDouble() * 0.15 + (r.isEven ? 0.05 : 0.0),
        ));
      }
    }
  }

  Widget _buildCanceledDisplay(BuildContext context) {
    final funMode = OrionConfig().getFlag('funMode', category: 'ui');
    return Stack(
      children: [
        if (funMode)
          // Blood drips smearing down the screen (fun mode)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _cancelResinController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _BloodDripPainter(
                    animation: _cancelResinController,
                    drips: _bloodDrips,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          )
        else
          // Layer bricks cracking and falling apart
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _cancelBrickController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _BrickWallPainter(
                    animation: _cancelBrickController,
                    bricks: _layerBricks,
                  ),
                  size: Size.infinite,
                );
              },
            ),
          ),
        // Cancel icon with shake
        AnimatedBuilder(
          animation: _cancelShakeController,
          builder: (context, child) {
            final shakeT = _cancelShakeController.value;
            final shake =
                math.sin(shakeT * math.pi * 6) * 12.0 * (1.0 - shakeT);

            return Center(
              child: Transform.translate(
                offset: Offset(shake, 0),
                child: FadeTransition(
                  opacity: _cancelIconFade,
                  child: ScaleTransition(
                    scale: _cancelIconScale,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cancel,
                        size: 180,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFinishedCelebration(BuildContext context) {
    // Fireworks behind, then checkmark, then a second fireworks layer clipped
    // to avoid the centre so particles never render on top of the icon.
    return Stack(
      children: [
        // Background fireworks layer
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _fireworksController,
            builder: (context, child) {
              return CustomPaint(
                painter: _FireworksPainter(
                  animation: _fireworksController,
                  bursts: _fireworkBursts,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
        // Black vignette behind the checkmark so nearby particles fade out
        // rather than abruptly clipping.
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.black,
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        // Checkmark icon
        Center(
          child: FadeTransition(
            opacity: _checkmarkFade,
            child: ScaleTransition(
              scale: _checkmarkScale,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 180,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FireworkParticle {
  final double angle;
  final double radius;
  final Color color;
  final double speed;
  final double size;
  final double fadeStart;
  final double gravity;

  const _FireworkParticle({
    required this.angle,
    required this.radius,
    required this.color,
    this.speed = 1.0,
    this.size = 4.0,
    this.fadeStart = 0.5,
    this.gravity = 50.0,
  });
}

class _FireworkBurst {
  /// Position as a fraction of screen size (0..1).
  final double fractionalX;
  final double fractionalY;
  final List<_FireworkParticle> particles;

  /// Delay (0..1) within a single animation cycle before the burst fires.
  final double delay;

  const _FireworkBurst({
    required this.fractionalX,
    required this.fractionalY,
    required this.particles,
    this.delay = 0.0,
  });
}

class _BloodDrip {
  final double fractionalX;
  final double speed;
  final double startWidth;
  final double maxWidth;
  final double delay;
  final double drift;

  /// 0..1 — fraction of width on the left side (0.5 = symmetric)
  final double asymmetry;

  /// Amplitude of organic edge waviness
  final double wobble;

  const _BloodDrip({
    required this.fractionalX,
    required this.speed,
    required this.startWidth,
    required this.maxWidth,
    required this.delay,
    this.drift = 0.0,
    this.asymmetry = 0.5,
    this.wobble = 1.5,
  });
}

class _BloodDripPainter extends CustomPainter {
  final Animation<double> animation;
  final List<_BloodDrip> drips;

  static const _bloodDark = Color(0xFF3D0000);
  static const _bloodMid = Color(0xFF6B0000);
  static const _bloodBright = Color(0xFF8B0000);

  _BloodDripPainter({required this.animation, required this.drips})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0.0) return;

    // --- 1. Draw individual drip smears ---
    for (final drip in drips) {
      if (t < drip.delay) continue;
      final localT = ((t - drip.delay) / (1.0 - drip.delay)).clamp(0.0, 1.0);

      // Viscous ease: slow start, accelerates
      final flowT = localT * localT * drip.speed;

      // Tip position (leading edge)
      final tipY = (size.height + 40) * flowT.clamp(0.0, 3.0);
      if (tipY < 1) continue;
      final visibleTipY = tipY.clamp(0.0, size.height + 60.0);

      final baseX = size.width * drip.fractionalX;
      final driftX = drip.drift * localT;
      final x = baseX + driftX;

      // Widths: narrow streak at top, widens gradually, rounded bulb at bottom
      final maxW = drip.startWidth +
          (drip.maxWidth - drip.startWidth) *
              (visibleTipY / size.height).clamp(0.0, 1.0);

      final topLeftW = drip.startWidth * drip.asymmetry;
      final topRightW = drip.startWidth * (1.0 - drip.asymmetry);
      final maxLeftW = maxW * drip.asymmetry;
      final maxRightW = maxW * (1.0 - drip.asymmetry);

      // The bottom of the drip is at visibleTipY.
      // The bulb occupies roughly the bottom 25-35% of the drip length.
      final bulbH = maxW * 0.8; // bulb height proportional to width
      final bulbTopY = visibleTipY - bulbH;

      // Build teardrop: narrow streak top → gradually widens →
      // rounded bulb at bottom
      final smearPath = ui.Path();
      smearPath.moveTo(x - topLeftW, -2);

      // --- Left edge: narrow streak widens smoothly into the bulb ---
      final wL1 = drip.wobble * math.sin(localT * 7 + drip.fractionalX * 20);
      final wL2 = drip.wobble * math.sin(localT * 11 + drip.fractionalX * 30);
      // Streak portion: top → where bulb starts, gradually widening
      smearPath.cubicTo(
        x - topLeftW + wL1,
        bulbTopY * 0.3,
        x - topLeftW - (maxLeftW - topLeftW) * 0.4 + wL2,
        bulbTopY * 0.7,
        x - maxLeftW,
        bulbTopY,
      );

      // --- Left side of bulb: continues outward slightly, then curves
      //     around the bottom ---
      smearPath.cubicTo(
        x - maxLeftW * 1.05,
        bulbTopY + bulbH * 0.3,
        x - maxLeftW * 1.05,
        bulbTopY + bulbH * 0.7,
        x - maxLeftW * 0.5,
        visibleTipY,
      );

      // --- Bottom curve: rounded across the bottom of the bulb ---
      smearPath.cubicTo(
        x - maxLeftW * 0.15,
        visibleTipY + bulbH * 0.15,
        x + maxRightW * 0.15,
        visibleTipY + bulbH * 0.15,
        x + maxRightW * 0.5,
        visibleTipY,
      );

      // --- Right side of bulb: curves back up ---
      final wR1 = drip.wobble * math.sin(localT * 9 + drip.fractionalX * 25);
      smearPath.cubicTo(
        x + maxRightW * 1.05,
        bulbTopY + bulbH * 0.7,
        x + maxRightW * 1.05,
        bulbTopY + bulbH * 0.3,
        x + maxRightW,
        bulbTopY,
      );

      // --- Right edge: bulb top back up to narrow streak ---
      final wR2 = drip.wobble * math.sin(localT * 6 + drip.fractionalX * 15);
      smearPath.cubicTo(
        x + topRightW + (maxRightW - topRightW) * 0.4 + wR1,
        bulbTopY * 0.7,
        x + topRightW + wR2,
        bulbTopY * 0.3,
        x + topRightW,
        -2,
      );

      smearPath.close();

      // Vertical gradient: darker at top, brighter near the tip
      final smearPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, 0),
          Offset(x, visibleTipY.clamp(1.0, size.height)),
          [
            _bloodDark.withValues(alpha: 0.7),
            _bloodMid.withValues(alpha: 0.8),
            _bloodBright.withValues(alpha: 0.85),
          ],
          [0.0, 0.6, 1.0],
        )
        ..style = PaintingStyle.fill;
      canvas.drawPath(smearPath, smearPaint);

      // Subtle wet highlight: off-center, asymmetric
      final hlOffsetX = (drip.asymmetry - 0.5) * maxW * 0.3;
      final highlightHalfW = drip.startWidth * 0.15;
      final hlPath = ui.Path();
      hlPath.moveTo(x + hlOffsetX - highlightHalfW, 2);
      hlPath.lineTo(x + hlOffsetX - highlightHalfW, visibleTipY * 0.7);
      hlPath.lineTo(x + hlOffsetX + highlightHalfW, visibleTipY * 0.7);
      hlPath.lineTo(x + hlOffsetX + highlightHalfW, 2);
      hlPath.close();
      final hlPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill;
      canvas.drawPath(hlPath, hlPaint);
    }

    // --- 2. Pooling at the bottom ---
    // Pool grows continuously as drips reach the bottom.
    double poolCoverage = 0;
    for (final drip in drips) {
      if (t < drip.delay) continue;
      final localT = ((t - drip.delay) / (1.0 - drip.delay)).clamp(0.0, 1.0);
      final flowT = localT * localT * drip.speed;
      final overshoot = (flowT - 0.85).clamp(0.0, 2.0);
      poolCoverage += overshoot * drip.maxWidth / size.width * 0.6;
    }
    poolCoverage = poolCoverage.clamp(0.0, 0.55);

    if (poolCoverage > 0.001) {
      final poolHeight = size.height * poolCoverage;
      final poolTop = size.height - poolHeight;

      final poolPath = ui.Path();
      poolPath.moveTo(0, size.height);
      poolPath.lineTo(size.width, size.height);
      poolPath.lineTo(size.width, poolTop);

      // Gentle sine wave along the pool surface
      const waveSegs = 24;
      final segW = size.width / waveSegs;
      final waveAmp = 2.0 + poolCoverage * 6.0;
      for (var i = waveSegs; i >= 0; i--) {
        final px = i * segW;
        final waveY = poolTop +
            math.sin(t * math.pi * 4 + i * 0.6) * waveAmp * 0.5 +
            math.sin(t * math.pi * 2.5 + i * 1.1) * waveAmp * 0.3;
        poolPath.lineTo(px, waveY);
      }
      poolPath.close();

      final poolPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, poolTop),
          Offset(0, size.height),
          [
            _bloodBright.withValues(alpha: 0.9),
            _bloodMid,
            _bloodDark,
          ],
          [0.0, 0.3, 1.0],
        )
        ..style = PaintingStyle.fill;
      canvas.drawPath(poolPath, poolPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BloodDripPainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
//  Layer-brick wall crack animation (non-fun-mode cancel)
// ---------------------------------------------------------------------------

class _LayerBrick {
  final double fx; // fractional x (0..1)
  final double fy; // fractional y (0..1)
  final double fw; // fractional width
  final double fh; // fractional height
  final bool isLeft; // which side of the crack
  final double delay; // animation delay (0..~0.5)
  final double fallSpeed; // gravity multiplier
  final double rotationSpeed; // tumble rate
  final double drift; // horizontal drift (negative = left)
  final double shade; // 0..1 brightness for the brick colour

  const _LayerBrick({
    required this.fx,
    required this.fy,
    required this.fw,
    required this.fh,
    required this.isLeft,
    required this.delay,
    required this.fallSpeed,
    required this.rotationSpeed,
    required this.drift,
    required this.shade,
  });
}

class _BrickWallPainter extends CustomPainter {
  final Animation<double> animation;
  final List<_LayerBrick> bricks;

  _BrickWallPainter({required this.animation, required this.bricks})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;

    // Phase 0..0.12: wall is static, crack line appears
    // Phase 0.12..1.0: bricks separate and fall
    final crackT = (t / 0.12).clamp(0.0, 1.0);
    final fallT = ((t - 0.12) / 0.88).clamp(0.0, 1.0);

    // Draw the crack line — fades out as bricks start falling
    if (crackT > 0.0 && fallT < 0.5) {
      final crackFade = (1.0 - fallT * 2.0).clamp(0.0, 1.0);
      _drawCrackLine(canvas, size, crackT, crackFade);
    }

    // Gap between bricks (pixels)
    const gap = 1.5;

    for (final brick in bricks) {
      final bx = brick.fx * size.width;
      final by = brick.fy * size.height;
      final bw = brick.fw * size.width - gap;
      final bh = brick.fh * size.height - gap;

      if (bw <= 0 || bh <= 0) continue;

      // Per-brick animation progress (accounts for delay)
      final brickFallT =
          ((fallT - brick.delay) / (1.0 - brick.delay)).clamp(0.0, 1.0);

      // Eased fall with gravity (quadratic ease-in)
      final gravity = brickFallT * brickFallT;

      // Horizontal drift away from centre crack
      final dx = brick.drift * size.width * gravity;
      // Vertical fall — 1.5x screen height so every brick clears the bottom
      final dy = gravity * brick.fallSpeed * size.height * 1.5;
      // Rotation: tumble increases as brick falls
      final rotation =
          gravity * brick.rotationSpeed * (brick.isLeft ? -1.0 : 1.0);

      // Slight separation at the crack even before full fall begins
      final crackGap = crackT * (brick.isLeft ? -2.0 : 2.0);

      // Final position
      final finalX = bx + dx + crackGap;
      final finalY = by + dy;

      // Fade out near the bottom of the screen
      final fadeStart = size.height * 0.7;
      final opacity = finalY < fadeStart
          ? 1.0
          : (1.0 - ((finalY - fadeStart) / (size.height * 0.5)).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
      if (opacity <= 0.0) continue;

      canvas.save();

      // Translate to brick centre, rotate, then draw
      final cx = finalX + bw / 2;
      final cy = finalY + bh / 2;
      canvas.translate(cx, cy);
      canvas.rotate(rotation);

      // Brick colour — very dim dark red, subtle background effect
      final base = (brick.shade * 255).round().clamp(0, 255);
      final brickColor = Color.fromARGB(
        (opacity * 180).round(), // reduced overall opacity
        (base * 0.35 + 30).round().clamp(0, 255), // dim red
        (base * 0.08).round().clamp(0, 255), // very muted green
        (base * 0.06).round().clamp(0, 255), // very muted blue
      );

      final paint = Paint()
        ..color = brickColor
        ..style = PaintingStyle.fill;

      // Rounded rect for each brick piece
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: bw, height: bh),
        const Radius.circular(2.0),
      );
      canvas.drawRRect(rrect, paint);

      // Subtle edge highlight on top of each brick for depth
      final edgePaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.05 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawRRect(rrect, edgePaint);

      canvas.restore();
    }
  }

  /// Draw a jagged crack line down the vertical centre of the screen.
  void _drawCrackLine(
      Canvas canvas, Size size, double crackProgress, double fade) {
    final crackPath = ui.Path();
    final centerX = size.width / 2;
    final rand = math.Random(42); // deterministic seed for consistent crack

    // Crack grows from top to bottom
    final crackBottom = size.height * crackProgress;

    crackPath.moveTo(centerX, 0);
    const segments = 30;
    final segH = size.height / segments;
    for (var i = 1; i <= segments; i++) {
      final sy = i * segH;
      if (sy > crackBottom) break;
      final jag = (rand.nextDouble() - 0.5) * 16.0;
      crackPath.lineTo(centerX + jag, sy);
    }

    final crackPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.35 * crackProgress * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(crackPath, crackPaint);

    // Faint glow around the crack
    final glowPaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.1 * crackProgress * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(crackPath, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _BrickWallPainter oldDelegate) => true;
}

class _FireworksPainter extends CustomPainter {
  final Animation<double> animation;
  final List<_FireworkBurst> bursts;

  _FireworksPainter({required this.animation, required this.bursts})
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = size.center(Offset.zero);
    // Exclusion zone around the checkmark so particles never overlap it.
    const exclusionRadius = 130.0;

    for (final burst in bursts) {
      // Each burst has a staggered delay within the cycle.
      final localT = ((t - burst.delay) % 1.0).clamp(0.0, 1.0);
      // Burst is invisible before its delay fires within the cycle.
      if (t < burst.delay && t + 1.0 - burst.delay > 1.0) continue;

      final origin = Offset(
        size.width * burst.fractionalX,
        size.height * burst.fractionalY,
      );

      for (final p in burst.particles) {
        final pt = (localT * p.speed).clamp(0.0, 1.0);
        // Ease-out so particles decelerate naturally
        final eased = 1.0 - math.pow(1.0 - pt, 2.5);

        final distance = p.radius * eased;
        final dx = math.cos(p.angle) * distance;
        // Gravity pulls particles down over time
        final dy = math.sin(p.angle) * distance + p.gravity * pt * pt;

        final pos = origin + Offset(dx, dy);

        // Skip particles that would land inside the checkmark exclusion zone.
        if ((pos - center).distance < exclusionRadius) continue;

        // Per-particle fade: fully visible until fadeStart, then fade out
        final fadeProgress = pt < p.fadeStart
            ? 1.0
            : 1.0 - ((pt - p.fadeStart) / (1.0 - p.fadeStart));
        final alpha = fadeProgress.clamp(0.0, 1.0);
        if (alpha <= 0.01) continue;

        // --- Glow layer (large, soft, translucent) ---
        final glowPaint = Paint()
          ..color = p.color.withValues(alpha: 0.18 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(pos, p.size * 3.0, glowPaint);

        // --- Core particle ---
        final corePaint = Paint()
          ..color = Color.lerp(Colors.white, p.color, 0.4 + 0.6 * pt)!
              .withValues(alpha: alpha)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, p.size * (1.0 - 0.3 * pt), corePaint);

        // --- Sparkle trail (fading dots along the path) ---
        const trailSteps = 5;
        for (var s = 1; s <= trailSteps; s++) {
          final trailT = (pt - s * 0.04).clamp(0.0, 1.0);
          if (trailT <= 0.0) continue;
          final trailEased = 1.0 - math.pow(1.0 - trailT, 2.5);
          final td = p.radius * trailEased;
          final tdx = math.cos(p.angle) * td;
          final tdy = math.sin(p.angle) * td + p.gravity * trailT * trailT;
          final tpos = origin + Offset(tdx, tdy);
          final trailAlpha = alpha * (1.0 - s / (trailSteps + 1));
          final trailPaint = Paint()
            ..color = p.color.withValues(alpha: 0.45 * trailAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
          canvas.drawCircle(tpos, p.size * 0.5, trailPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter oldDelegate) => true;
}
