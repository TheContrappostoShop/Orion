/*
* Glasser - Status Screen
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

// dart:io not needed once thumbnails are rendered from memory

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:orion/backend_service/providers/manual_provider.dart';
import 'package:orion/materials/post_calibration_overlay.dart';
import 'package:orion/materials/calibration_context_provider.dart';
import 'package:orion/materials/calibration_progress_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'package:orion/files/grid_files_screen.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/settings/settings_screen.dart';
import 'package:orion/util/hold_button.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/util/status_card.dart';
import 'package:orion/backend_service/providers/status_provider.dart';
import 'package:orion/backend_service/odyssey/models/status_models.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/util/layer_preview_cache.dart';
import 'package:orion/backend_service/nanodlp/helpers/nano_thumbnail_generator.dart';
import 'package:orion/util/widgets/system_status_widget.dart';
import 'package:orion/backend_service/providers/analytics_provider.dart';
import 'package:orion/home/home_screen.dart';
import 'package:orion/widgets/orion_app_bar.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

const int _forceSensorMiniWindowSize = 300;

class StatusScreen extends StatefulWidget {
  final bool newPrint;
  final Uint8List? initialThumbnailBytes;
  final String? initialFilePath;
  final int? initialPlateId;
  final VoidCallback? onReturnHome;

  const StatusScreen({
    super.key,
    required this.newPrint,
    this.initialThumbnailBytes,
    this.initialFilePath,
    this.initialPlateId,
    this.onReturnHome,
  });

  @override
  StatusScreenState createState() => StatusScreenState();
}

class StatusScreenState extends State<StatusScreen> {
  static const double _thumbBaseWidth = 800.0;
  static const double _thumbBaseHeight = 480.0;
  // While starting a new print we suppress rendering of any stale provider
  // status until after we've issued a reset in a post-frame callback. This
  // avoids calling notifyListeners during the same build frame that mounted
  // this widget (which previously caused a FlutterError) while still ensuring
  // a clean spinner instead of flashing the prior job.
  bool _suppressOldStatus = false;
  String? _frozenFileName;
  // View toggle state - false = main status view, true = analytics view
  bool _showAnalytics = false;
  // Presentation-local state (derived values computed per build instead of storing)
  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  // Duration formatting moved to StatusModel.formattedElapsedPrintTime

  @override
  void initState() {
    super.initState();

    _log.info('StatusScreen opened - newPrint: ${widget.newPrint}');

    // Mark status screen as open so we can block notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<StatusProvider>().setStatusScreenOpen(true);
      }
    });

    // Mark calibration overlay as hidden so it doesn't reappear
    CalibrationProgressOverlay.markAsHidden();

    if (widget.newPrint) {
      _suppressOldStatus = true; // force spinner for fresh print session
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<StatusProvider>().resetStatus(
              initialThumbnailBytes: widget.initialThumbnailBytes,
              initialFilePath: widget.initialFilePath,
              initialPlateId: widget.initialPlateId,
            );
        setState(() => _suppressOldStatus = false);
      });
    }

    // Set up analytics provider listener for force sensor updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final analyticsProv = context.read<AnalyticsProvider>();
        analyticsProv.refresh();
        _analyticsListener = () {
          if (mounted && _showAnalytics) setState(() {});
        };
        analyticsProv.addListener(_analyticsListener!);
      } catch (_) {
        // Analytics provider not available
      }
    });

    // Listen for status provider changes so we can detect when a finished
    // print is replaced by a new print without leaving the StatusScreen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final sp = context.read<StatusProvider>();
        _statusProviderListener = () {
          if (!mounted) return;
          final provider = context.read<StatusProvider>();
          final status = provider.status;
          final currentPath = status?.printData?.fileData?.path;
          final currentFinished =
              status?.isIdle == true && status?.layer != null;

          // If we were previously showing a finished snapshot (final state)
          // mark the status screen as stale so that subsequent starts will
          // either reset the UI or respawn the screen entirely.
          if (currentFinished) {
            _statusScreenStale = true;
          }

          // If a new active job begins (printing/paused) after a finished
          // snapshot we should present a fresh StatusScreen experience.
          if (_wasFinishedSnapshot &&
              (status?.isPrinting == true || status?.isPaused == true)) {
            if (_statusScreenStale) {
              // Respawn the StatusScreen route so the entire UI is rebuilt
              // just like when opening a new print from elsewhere. Use a
              // post-frame callback to avoid navigating during provider
              // notifications.
              _statusScreenStale = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                try {
                  final initialThumb = provider.thumbnailBytes;
                  final initialPath =
                      provider.status?.printData?.fileData?.path;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (ctx) => StatusScreen(
                        newPrint: true,
                        initialThumbnailBytes: initialThumb,
                        initialFilePath: initialPath,
                        initialPlateId: null,
                      ),
                    ),
                  );
                } catch (_) {}
              });
            } else {
              provider.resetStatus();
              setState(() {
                _frozenFileName = null;
                _showLayer2D = false;
                _layer2DBytes = null;
                _prefetched = false;
                _lastPrefetchedLayer = null;
                _resolvedFilePathForPrefetch = null;
                _resolvedPlateIdForPrefetch = null;
              });
            }
          }

          _wasFinishedSnapshot = currentFinished;
          _lastSeenFilePath = currentPath ?? _lastSeenFilePath;
        };
        sp.addListener(_statusProviderListener!);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    try {
      if (mounted) {
        context.read<StatusProvider>().setStatusScreenOpen(false);
      } else {
        // Use the context directly even if unmounted because we need to clear the flag
        Provider.of<StatusProvider>(context, listen: false)
            .setStatusScreenOpen(false);
      }
    } catch (_) {
      // Provider might be disposed or unavailable
    }

    if (_analyticsListener != null) {
      try {
        context.read<AnalyticsProvider>().removeListener(_analyticsListener!);
      } catch (_) {
        // Provider already disposed
      }
    }
    if (_statusProviderListener != null) {
      try {
        context.read<StatusProvider>().removeListener(_statusProviderListener!);
      } catch (_) {}
    }
    super.dispose();
  }

  // Local UI state for toggling 2D layer preview
  bool _showLayer2D = false;
  Uint8List? _layer2DBytes;
  bool _layer2DLoading = false;
  DateTime? _lastLayerToggleTime;
  bool _prefetched = false;
  int? _lastPrefetchedLayer;
  int? _resolvedPlateIdForPrefetch;
  String? _resolvedFilePathForPrefetch;
  // Track last observed file path and finished state to detect new-print
  // transitions while the StatusScreen is still mounted.
  String? _lastSeenFilePath;
  bool _wasFinishedSnapshot = false;
  bool _statusScreenStale = false;
  VoidCallback? _statusProviderListener;
  final Logger _log = Logger('StatusScreen');
  // null = unknown, true = this finished/canceled print is a calibration print
  bool? _isCalibrationPrint;
  VoidCallback? _analyticsListener;
  // Throttle 2D layer prefetch/precache work during printing. We only
  // prefetch on every Nth layer to reduce CPU usage when NanoDLP polls
  // status frequently.
  static const int _layerPrefetchStride = 3;
  final GlobalKey _analyticsLeftStackMeasureKey = GlobalKey();
  double? _analyticsLeftStackHeight;

  void _updateAnalyticsLeftStackHeight() {
    final ctx = _analyticsLeftStackMeasureKey.currentContext;
    final h = ctx?.size?.height;
    if (h == null || !h.isFinite || h <= 0) return;
    final prev = _analyticsLeftStackHeight;
    if (prev == null || (prev - h).abs() > 0.5) {
      if (!mounted) return;
      setState(() {
        _analyticsLeftStackHeight = h;
      });
    }
  }

  /// Check if current print is a calibration print and show post-calibration overlay
  Future<void> _checkAndShowCalibrationOverlay() async {
    try {
      final provider = context.read<StatusProvider>();
      final status = provider.status;
      final fileData = status?.printData?.fileData;
      final calibrationProvider = context.read<CalibrationContextProvider>();
      final calibrationContext = calibrationProvider.context;
      int? plateId;

      if (fileData != null) {
        try {
          final meta = await BackendService()
              .getFileMetadata(
                  fileData.locationCategory ?? 'Local', fileData.path)
              .timeout(const Duration(seconds: 2));
          plateId = meta['plate_id'] as int?;
        } catch (e) {
          _log.fine('Failed to resolve plate id for calibration check: $e');
        }
      }

      // PlateID 0 is calibration print in NanoDLP. Fall back to the UI
      // detection signal combined with stored context when metadata is unavailable.
      // Require either plateId == 0 OR the UI flag + context to avoid false positives.
      final isCalibrationPrint = (plateId == 0) ||
          (_isCalibrationPrint == true && calibrationContext != null);

      if (isCalibrationPrint) {
        _log.info(
            'Detected calibration print completion, showing post-calibration overlay');

        if (!mounted) return;
        final nav = Navigator.of(context);

        // Navigate home first (use isFirst to avoid named route mismatch)
        nav.popUntil((route) => route.isFirst);

        // Show post-calibration overlay if we have context
        if (calibrationContext != null) {
          nav.push(
            PageRouteBuilder(
              opaque: false,
              barrierDismissible: false,
              transitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              pageBuilder: (context, _, __) => PostCalibrationOverlay(
                calibrationModelName: calibrationContext.calibrationModelName,
                resinProfileName: calibrationContext.resinProfileName,
                startExposure: calibrationContext.startExposure,
                exposureIncrement: calibrationContext.exposureIncrement,
                profileId: calibrationContext.profileId,
                calibrationModelId: calibrationContext.calibrationModelId,
                evaluationGuideUrl: calibrationContext.evaluationGuideUrl,
                onComplete: () {
                  // Pop everything: overlay, StatusScreen, CalibrationScreen, progress overlay
                  nav.popUntil((route) => route.isFirst);
                  // Clear context after evaluation is complete
                  calibrationProvider.clearContext();
                },
              ),
            ),
          );
        } else {
          _log.warning('Calibration print detected but no context available. '
              'This may indicate the context was lost after idle time. '
              'Returning to home.');
        }

        // Reset status after navigation settles
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            context.read<StatusProvider>().resetStatus();
          } catch (_) {
            // Provider no longer in tree
          }
        });

        return;
      }
    } catch (e) {
      _log.warning('Error checking for calibration print: $e');
    }

    // Not a calibration print, proceed with normal home navigation
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<StatusProvider>().resetStatus();
      } catch (_) {
        // Provider no longer in tree
      }
    });
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.lengthInBytes != b.lengthInBytes) return false;
    for (int i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // Format force sensor readings: use grams below 1000 g, switch to kg above
  String _formatForceValue(double v) {
    final absV = v.abs();
    if (absV >= 1000.0) {
      final kg = v / 1000.0;
      return '${kg.toStringAsFixed(2)} kg';
    }
    return '${v.toStringAsFixed(1)} g';
  }

  List<double> _forceValuesInVisibleMiniWindow(
      List<Map<String, dynamic>> series) {
    final int last = series.length;
    final int start = last - _forceSensorMiniWindowSize < 0
        ? 0
        : last - _forceSensorMiniWindowSize;
    final window = series.sublist(start, last);

    return window
        .map((m) {
          final vRaw = m['v'];
          if (vRaw is num) return vRaw.toDouble();
          return double.tryParse(vRaw?.toString() ?? '');
        })
        .where((v) => v != null)
        .cast<double>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StatusProvider>(
      builder: (context, provider, _) {
        final StatusModel? status = provider.status;
        final awaiting = provider.awaitingNewPrintData;
        final newPrintReady = provider.newPrintReady;

        // If we're awaiting a new print session, clear any previously
        // frozen filename so the next job can set it when available.
        if (awaiting) {
          _frozenFileName = null;
        }

        // it does not change mid-print if backend later updates metadata.
        if (_frozenFileName == null &&
            status?.printData?.fileData?.name != null) {
          final name = status!.printData!.fileData!.name;
          // Only freeze when a job is active (printing or paused) so we
          // don't persist names for idle snapshots.
          if (status.isPrinting || status.isPaused) {
            _frozenFileName = name;
          }
        }
        // We do not expose elapsed awaiting time (private); could add later via provider getter.
        const int waitMillis = 0;
        // Provider handles polling, transitional flags (pause/cancel), thumbnail caching, and
        // exposes a typed StatusModel. The screen now focuses solely on presentation.

        // Show global loading while provider indicates loading, we have no status yet,
        // or while the thumbnail is still being prepared. For new prints we
        // continue to wait until the provider signals the print is ready
        // (we have active job+file metadata+thumbnail). For auto-open (newPrint
        // == false) we also show a spinner while the provider is still fetching
        // the thumbnail so the UI doesn't immediately render a stale/placeholder
        // preview. However, if the backend reports the job has already finished
        // (idle with layer data) or is canceled we should not remain in a
        // spinner indefinitely — render the final status instead.
        final bool finishedSnapshot =
            status?.isIdle == true && status?.layer != null;
        final bool canceledSnapshot = status?.isCanceled == true;

        final bool thumbnailLoadingForAutoOpen =
            !widget.newPrint && // only apply to auto-open path
                status != null &&
                (status.isPrinting || status.isPaused) &&
                !provider.thumbnailReady &&
                !finishedSnapshot &&
                !canceledSnapshot;

        if (_suppressOldStatus ||
            provider.isLoading ||
            provider.minSpinnerActive ||
            status == null ||
            thumbnailLoadingForAutoOpen ||
            // If this screen was opened as a new print, wait until the
            // provider reports the job is ready to display. But allow
            // finished/canceled snapshots through so the UI doesn't lock up.
            // If opened as a new print, wait until provider signals readiness
            // (active job + file metadata + thumbnail). Additionally, ensure
            // we have at least the file name (or have frozen it) before
            // dismissing the global spinner. Some backends report the job
            // active before file metadata arrives; keep showing the spinner
            // until the UI can display a stable filename.
            ((widget.newPrint &&
                    (awaiting ||
                        ((status.printData?.fileData?.name == null) &&
                            _frozenFileName == null))) &&
                !newPrintReady &&
                !finishedSnapshot &&
                !canceledSnapshot)) {
          return GlassApp(
            child: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (awaiting && waitMillis > 5000)
                      Padding(
                        padding: EdgeInsets.only(top: 16.0),
                        child: Text(
                          FlutterI18n.translate(context, 'status.waiting'),
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        if (provider.error != null) {
          return GlassApp(
            child: Scaffold(
              appBar: AppBar(
                  title: Text(FlutterI18n.translate(context, 'status.error'))),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${FlutterI18n.translate(context, 'status.error')}\n\n'
                      '${FlutterI18n.translate(context, 'status.errorContactSupport')}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // No active or last print data (only show when not in awaiting transitional phase)
        if (!awaiting && status.printData == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text(FlutterI18n.translate(context, 'status.noPrintData')),
            ),
            body: Center(
              child: GlassButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GridFilesScreen(),
                    ),
                  );
                },
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    FlutterI18n.translate(context, 'status.goToFiles'),
                    style: TextStyle(fontSize: 26),
                  ),
                ),
              ),
            ),
          );
        }

        final elapsedStr = status.formattedElapsedPrintTime;
        // Trigger a one-time prefetch of 3D and current 2D layer thumbnails
        // when we first observe a valid status with file metadata.
        if (!_prefetched && status.printData?.fileData != null) {
          _prefetched = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _prefetchThumbnails(status);
          });
        }

        // Proactively preload next layers when the reported layer changes.
        // Use a post-frame callback to perform async work outside build.
        if (status.layer != null &&
            status.printData?.fileData != null &&
            status.printData?.fileData?.path != _resolvedFilePathForPrefetch) {
          // File changed; clear previously-resolved plate id so we'll re-resolve.
          _resolvedFilePathForPrefetch = status.printData?.fileData?.path;
          _resolvedPlateIdForPrefetch = null;
          _lastPrefetchedLayer = null;
        }

        if (status.layer != null && status.layer != _lastPrefetchedLayer) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybePreloadNextLayers(status);
          });
        }
        // If the job has finished (or canceled) determine whether it's
        // a calibration print so we can surface a different return label.
        final isFinished = finishedSnapshot;
        if ((isFinished || canceledSnapshot) && _isCalibrationPrint == null) {
          // Defer async metadata check to after build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _detectCalibrationPrint(status);
          });
        }
        final fileName =
            _frozenFileName ?? status.printData?.fileData?.name ?? '';

        return GlassApp(
          child: Scaffold(
            appBar: OrionAppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight,
              // Use the live clock on the simple/main view, but when the
              // advanced (analytics) view is active show the overall print
              // percentage in the same leading slot so the top-left remains
              // informative.
              leadingWidget: Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: SizedBox(
                    // Ensure the leading slot keeps consistent size by
                    // rendering the clock (possibly hidden) and overlaying
                    // the percentage when analytics view is active.
                    height: 36,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Keep both the clock and percentage in the tree to
                        // preserve layout; toggle visibility via Opacity to
                        // avoid any shift when switching views.
                        Opacity(
                          opacity: _showAnalytics ? 0.0 : 1.0,
                          // Use Baseline alignment so the clock and percent
                          // share the same alphabetic baseline even though
                          // they are rendered in a Stack. This avoids tiny
                          // vertical shifts introduced by differing text
                          // metrics while preserving the overlay behavior.
                          child: const Baseline(
                            baseline: 22.0,
                            baselineType: TextBaseline.alphabetic,
                            child: LiveClock(),
                          ),
                        ),
                        // Percentage is always built but its opacity is toggled.
                        Opacity(
                          opacity: _showAnalytics ? 1.0 : 0.0,
                          child: Builder(builder: (ctx) {
                            final pct =
                                (provider.progress * 100).clamp(0.0, 100.0);
                            final pctInt = pct.toInt().clamp(0, 100);
                            final pctIntStr = pctInt.toString();
                            final pctStr = pctIntStr.padLeft(3, '0');
                            final greyCount =
                                (3 - pctIntStr.length).clamp(0, 3);
                            final greyPart = pctStr.substring(0, greyCount);
                            final normalPart = pctStr.substring(greyCount);
                            final baseStyle = Theme.of(ctx)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontSize: 28, fontWeight: FontWeight.bold);
                            final lowOpacityColor =
                                baseStyle?.color?.withValues(alpha: 0.45) ??
                                    Theme.of(ctx)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.45);
                            final normalColor = baseStyle?.color ??
                                Theme.of(ctx).colorScheme.onSurface;

                            return Baseline(
                              baseline: 22.0,
                              baselineType: TextBaseline.alphabetic,
                              child: RichText(
                                text: TextSpan(
                                  style: baseStyle,
                                  children: [
                                    if (greyPart.isNotEmpty)
                                      TextSpan(
                                        text: greyPart,
                                        style: baseStyle?.copyWith(
                                            color: lowOpacityColor),
                                      ),
                                    TextSpan(
                                      text: '$normalPart%',
                                      style: baseStyle?.copyWith(
                                          color: normalColor),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: const [SystemStatusWidget()],
              // Center the main status/title column using centerWidget so the
              // visual balance matches other screens (e.g. Details screen).
              title: const Text(''),
              centerWidget: Builder(builder: (context) {
                final deviceMsg = provider.deviceStatusMessage;
                final statusText =
                    (deviceMsg != null && deviceMsg.trim().isNotEmpty)
                        ? deviceMsg
                        : provider.displayStatus;
                // Use a single base font size for both title lines so they appear
                // visually consistent. If the AppBar theme provides a title
                // fontSize, use that as the base; otherwise default to 14 and
                // reduce slightly.
                final baseFontSize =
                    (Theme.of(context).appBarTheme.titleTextStyle?.fontSize ??
                            14) -
                        10;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName.isNotEmpty
                          ? fileName
                          : FlutterI18n.translate(context, 'status.noFile'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .appBarTheme
                          .titleTextStyle
                          ?.copyWith(
                            fontSize: baseFontSize,
                            fontWeight: FontWeight.normal,
                            color: Theme.of(context)
                                .appBarTheme
                                .titleTextStyle
                                ?.color
                                ?.withValues(alpha: 0.95),
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                              .appBarTheme
                              .titleTextStyle
                              ?.merge(TextStyle(
                                fontWeight: FontWeight.normal,
                                fontSize: baseFontSize,
                              ))
                              .copyWith(
                                // Make status less visually dominant by lowering
                                // its alpha relative to the AppBar title color.
                                color: Theme.of(context)
                                    .appBarTheme
                                    .titleTextStyle
                                    ?.color
                                    ?.withValues(alpha: 0.65),
                              ) ??
                          TextStyle(
                            fontSize: baseFontSize,
                            fontWeight: FontWeight.normal,
                            color: Theme.of(context)
                                .appBarTheme
                                .titleTextStyle
                                ?.color
                                ?.withValues(alpha: 0.65),
                          ),
                    ),
                  ],
                );
              }),
            ),
            body: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Show analytics view or main status view based on toggle
                  if (_showAnalytics) {
                    return Padding(
                      padding:
                          OrionSpacing.screenPaddingNoTop.copyWith(bottom: 20),
                      child: _buildAnalyticsView(context, provider, status),
                    );
                  }

                  return _isLandscape
                      ? Padding(
                          padding: OrionSpacing.screenPaddingNoTop
                              .copyWith(bottom: 20),
                          child: _buildLandscapeLayout(
                            context,
                            provider,
                            status,
                            elapsedStr,
                            fileName,
                          ),
                        )
                      : Padding(
                          padding: OrionSpacing.screenPaddingNoTop
                              .copyWith(bottom: 20),
                          child: _buildPortraitLayout(
                            context,
                            provider,
                            status,
                            elapsedStr,
                            fileName,
                          ),
                        );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPortraitLayout(BuildContext context, StatusProvider provider,
      StatusModel? status, String elapsedStr, String fileName) {
    final statusModel = status;
    final layerCurrent = statusModel?.layer;
    final layerTotal = statusModel?.printData?.layerCount;
    final usedMaterial = statusModel?.printData?.usedMaterial;
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                children: [
                  _buildThumbnailView(context, provider, statusModel),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: _buildInfoCard(
                        FlutterI18n.translate(context, 'status.currentZ'),
                        '${statusModel?.physicalState.z.toStringAsFixed(3) ?? '-'} mm',
                      ),
                    ),
                    Expanded(
                      child: _buildInfoCard(
                        FlutterI18n.translate(context, 'status.printLayers'),
                        layerCurrent == null || layerTotal == null
                            ? '- / -'
                            : '$layerCurrent / $layerTotal',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  _buildInfoCard(
                      FlutterI18n.translate(context, 'status.estimatedTime'),
                      elapsedStr),
                  const SizedBox(height: 5),
                  _buildInfoCard(
                    FlutterI18n.translate(context, 'status.estimatedVolume'),
                    usedMaterial == null
                        ? '-'
                        : '${usedMaterial.toStringAsFixed(2)} mL',
                  ),
                  const Spacer(),
                  _buildButtons(provider, statusModel),
                ],
              ),
            ),
          ],
        ),
      )
    ]);
  }

  Widget _buildLandscapeLayout(BuildContext context, StatusProvider provider,
      StatusModel? status, String elapsedStr, String fileName) {
    final statusModel = status;
    final layerCurrent = statusModel?.layer;
    final layerTotal = statusModel?.printData?.layerCount;
    final usedMaterial = statusModel?.printData?.usedMaterial;
    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 1,
            child: Column(children: [
              Spacer(),
              _buildInfoCard(
                FlutterI18n.translate(context, 'status.currentZ'),
                '${statusModel?.physicalState.z.toStringAsFixed(3) ?? '-'} mm',
              ),
              _buildInfoCard(
                FlutterI18n.translate(context, 'status.printLayers'),
                layerCurrent == null || layerTotal == null
                    ? '- / -'
                    : '$layerCurrent / $layerTotal',
              ),
              _buildInfoCard(
                  FlutterI18n.translate(context, 'status.estimatedTime'),
                  elapsedStr),
              _buildInfoCard(
                FlutterI18n.translate(context, 'status.estimatedVolume'),
                usedMaterial == null
                    ? '-'
                    : '${usedMaterial.toStringAsFixed(2)} mL',
              ),
              Spacer(),
            ]),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            flex: 2,
            child: _buildThumbnailView(context, provider, statusModel),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: EdgeInsets.zero,
        child: _buildButtons(provider, statusModel),
      ),
    ]);
  }

  // temperature is optional; default to 0.0 when not provided
  Widget _buildInfoCard(String title, String subtitle,
      [double temperature = 0.0]) {
    Provider.of<ThemeProvider>(context); // theming
    return GlassCard(
      outlined: true,
      elevation: 1.0,
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      // If temperature is NaN treat as unspecified; otherwise choose an
      // accent color based on the value.
      accentColor: temperature == 0 ? null : _colorForTemperature(temperature),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _buildThumbnailView(
      BuildContext context, StatusProvider provider, StatusModel? status) {
    // Prefer provider's thumbnail bytes. If none yet, consider the
    // initialThumbnailBytes passed from the Details screen — but do not
    // show a generated placeholder as the initial preview while the
    // provider is still probing for a real preview. In that case show the
    // spinner until provider provides a non-placeholder or finishes.
    Uint8List? thumbnail;
    if (provider.thumbnailBytes != null) {
      thumbnail = provider.thumbnailBytes;
    } else if (widget.initialThumbnailBytes != null) {
      // Detect whether the provided initial bytes are the NanoDLP generated
      // placeholder. If so and provider isn't ready yet, prefer spinner.
      final placeholder = NanoDlpThumbnailGenerator.generatePlaceholder(
          NanoDlpThumbnailGenerator.largeWidth,
          NanoDlpThumbnailGenerator.largeHeight);
      bool isPlaceholder =
          widget.initialThumbnailBytes!.length == placeholder.length &&
              _bytesEqual(widget.initialThumbnailBytes!, placeholder);
      if (isPlaceholder && !provider.thumbnailReady) {
        thumbnail = null;
      } else {
        thumbnail = widget.initialThumbnailBytes;
      }
    } else {
      thumbnail = null;
    }
    final themeProvider = Provider.of<ThemeProvider>(context);
    final progress = provider.progress;
    final statusColor = provider.statusColor(context);
    final statusModel = provider.status;
    final finishedSnapshot =
        statusModel?.isIdle == true && statusModel?.layer != null;
    // Prefer canonical 'finished' hint from the parsed model.
    final effectivelyFinished = statusModel?.finished == true;
    final effectiveStatusColor = (finishedSnapshot && !effectivelyFinished)
        ? Theme.of(context).colorScheme.error
        : statusColor;
    return Center(
      child: GestureDetector(
        onTap: () {
          // Debounce toggles: ignore taps that occur within 500ms of the
          // previous toggle, and ignore while a layer load is in progress.
          final now = DateTime.now();
          if (_layer2DLoading) return;
          if (_lastLayerToggleTime != null &&
              now.difference(_lastLayerToggleTime!) <
                  const Duration(milliseconds: 500)) {
            return;
          }

          // Toggle 2D layer preview. If enabling, trigger fetch.
          final providerState =
              Provider.of<StatusProvider>(context, listen: false);
          setState(() {
            _showLayer2D = !_showLayer2D;
            _lastLayerToggleTime = now;
          });
          if (_showLayer2D) {
            _fetchLayer2D(providerState, statusModel);
          }
        },
        child: Stack(
          children: [
            GlassCard(
              outlined: true,
              elevation: 1.0,
              child: Padding(
                padding: const EdgeInsets.all(4.5),
                child: ClipRRect(
                  borderRadius: themeProvider.isGlassTheme
                      ? BorderRadius.circular(12.5)
                      : BorderRadius.circular(7.75),
                  child: Stack(children: [
                    // Base thumbnail / spinner
                    ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0, // grayscale matrix
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                      child: thumbnail != null && thumbnail.isNotEmpty
                          ? Image.memory(
                              thumbnail,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.none,
                              gaplessPlayback: true,
                              cacheWidth: _statusThumbnailCacheWidth(),
                              cacheHeight: _statusThumbnailCacheHeight(),
                            )
                          : Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    effectiveStatusColor),
                              ),
                            ),
                    ),

                    // Dim overlay
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),

                    // Progress wipe
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: progress,
                            child: thumbnail != null && thumbnail.isNotEmpty
                                ? Image.memory(
                                    thumbnail,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.none,
                                    gaplessPlayback: true,
                                    cacheWidth: _statusThumbnailCacheWidth(),
                                    cacheHeight: _statusThumbnailCacheHeight(),
                                  )
                                : Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          effectiveStatusColor),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),

                    // 2D layer overlay (covers base thumbnail and status card when active)
                    if (_showLayer2D)
                      Positioned.fill(
                        child: _layer2DLoading
                            ? Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      effectiveStatusColor),
                                ),
                              )
                            : (_layer2DBytes != null &&
                                    _layer2DBytes!.isNotEmpty
                                ? ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: Image(
                                        image: _layerPreviewProvider(
                                          _layer2DBytes!,
                                        ),
                                        gaplessPlayback: true,
                                        fit: BoxFit.contain,
                                        filterQuality: FilterQuality.none,
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Text(FlutterI18n.translate(
                                        context, 'status.previewUnavailable')),
                                  )),
                      ),
                  ]),
                ),
              ),
            ),
            Positioned.fill(
              right: 15,
              child: Center(
                child: StatusCard(
                  isCanceling: provider.isCanceling,
                  isPausing: provider.isPausing,
                  progress: progress,
                  statusColor: effectiveStatusColor,
                  status: status,
                  showPercentage: !_showLayer2D,
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Builder(builder: (context) {
                  final isGlassTheme = themeProvider.isGlassTheme;
                  return GlassCard(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topRight: isGlassTheme
                            ? const Radius.circular(14.0)
                            : const Radius.circular(9.75),
                        bottomRight: isGlassTheme
                            ? const Radius.circular(14.0)
                            : const Radius.circular(9.75),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2.5),
                      child: ClipRRect(
                        borderRadius: BorderRadius.only(
                          topRight: isGlassTheme
                              ? const Radius.circular(11.5)
                              : const Radius.circular(7.75),
                          bottomRight: isGlassTheme
                              ? const Radius.circular(11.5)
                              : const Radius.circular(7.75),
                        ),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: LinearProgressIndicator(
                            minHeight: 15,
                            color: effectiveStatusColor,
                            value: progress,
                            backgroundColor: isGlassTheme
                                ? effectiveStatusColor.withValues(alpha: 0.1)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider _layerPreviewProvider(Uint8List bytes, {Size? logicalSize}) {
    final dpr = _safeDevicePixelRatio();
    final size = _safeLogicalSize(
      logicalSize,
      fallback: _estimatedLayerPreviewLogicalSize(),
    );

    // Decode near display resolution (downsampling) instead of decoding full
    // source and downscaling every frame.
    final targetWidth = max(1, min(1600, (size.width * dpr).round()));

    return ResizeImage(
      MemoryImage(bytes),
      width: targetWidth,
      allowUpscaling: false,
    );
  }

  int _statusThumbnailCacheWidth() {
    final dpr = _safeDevicePixelRatio();
    return (_thumbBaseWidth * dpr).clamp(1.0, 1800.0).round();
  }

  int _statusThumbnailCacheHeight() {
    final dpr = _safeDevicePixelRatio();
    return (_thumbBaseHeight * dpr).clamp(1.0, 1200.0).round();
  }

  Size _estimatedLayerPreviewLogicalSize() {
    final screen = MediaQuery.sizeOf(context);
    if (_isLandscape) {
      return Size(screen.width * 0.44, screen.height * 0.60);
    }
    return Size(screen.width - 48, screen.height * 0.40);
  }

  double _safeDevicePixelRatio() {
    final raw = MediaQuery.devicePixelRatioOf(context);
    if (!raw.isFinite || raw <= 0) return 1.0;
    return raw;
  }

  Size _safeLogicalSize(Size? logicalSize, {required Size fallback}) {
    final w = logicalSize?.width;
    final h = logicalSize?.height;

    final safeW = (w != null && w.isFinite && w > 0) ? w : fallback.width;
    final safeH = (h != null && h.isFinite && h > 0) ? h : fallback.height;

    return Size(safeW, safeH);
  }

  Future<void> _precacheLayerPreview(Uint8List bytes, {Size? logicalSize}) {
    return precacheImage(
      _layerPreviewProvider(bytes, logicalSize: logicalSize),
      context,
    );
  }

  Future<void> _fetchLayer2D(
      StatusProvider provider, StatusModel? status) async {
    if (status == null) return;
    final fileData = status.printData?.fileData;
    int? plateId;
    final layerIndex = status.layer;
    if (layerIndex == null) return;

    try {
      if (fileData != null) {
        final meta = await BackendService().getFileMetadata(
            fileData.locationCategory ?? 'Local', fileData.path);
        if (meta['plate_id'] != null) {
          plateId = meta['plate_id'] as int?;
        }
      }
    } catch (_) {
      plateId = widget.initialPlateId;
    }
    if (plateId == null) return;
    final isCalibrationPlate = plateId == 0;

    final filePath = status.printData?.fileData?.path ?? widget.initialFilePath;
    if (!isCalibrationPlate) {
      final cached = LayerPreviewCache.instance
          .get(plateId, layerIndex, filePath: filePath);
      if (cached != null) {
        setState(() {
          _layer2DBytes = cached;
          _showLayer2D = true;
        });
        LayerPreviewCache.instance.preload(
            BackendService(), plateId, layerIndex,
            count: 1, filePath: filePath);
        return;
      }
    }

    setState(() {
      _layer2DLoading = true;
    });
    try {
      final bytes = isCalibrationPlate
          ? await BackendService().getPlateLayerImage(plateId, layerIndex)
          : await LayerPreviewCache.instance.fetchAndCache(
              BackendService(), plateId, layerIndex,
              filePath: filePath);
      if (bytes.isNotEmpty) {
        // Start precaching but don't await it — decoding can be expensive
        // and awaiting here can cause UI jank. Fire-and-forget instead.
        _precacheLayerPreview(bytes).catchError((_) {});
        setState(() {
          _layer2DBytes = bytes;
          _showLayer2D = true;
        });
        if (!isCalibrationPlate) {
          LayerPreviewCache.instance.preload(
              BackendService(), plateId, layerIndex,
              count: 1, filePath: filePath);
        }
      }
    } catch (_) {
      // ignore
    } finally {
      setState(() {
        _layer2DLoading = false;
      });
    }
  }

  Future<void> _prefetchThumbnails(StatusModel status) async {
    // Prefetch the 3D thumbnail for the current file (Large) and the
    // current 2D layer (and preload next layers). Best-effort; ignore
    // any failures.
    try {
      final fileData = status.printData?.fileData;
      if (fileData != null) {
        // Prefetch 3D thumbnail (Large size) — fetch bytes and precache so
        // Flutter's image cache holds a decoded image for instant display.
        BackendService()
            .getFileThumbnail(
                fileData.locationCategory ?? 'Local', fileData.path, 'Large')
            .then((bytes) async {
          final ctx = context;
          if (!ctx.mounted) return;
          try {
            if (bytes.isNotEmpty) {
              await precacheImage(MemoryImage(bytes), ctx);
            }
          } catch (_) {
            // ignore precache failures
          }
        }, onError: (_) {});
      }
    } catch (_) {
      // ignore
    }

    // If 2D preview is not shown, skip fetching layer images to save CPU/Network
    if (!_showLayer2D) return;

    // Prefetch current layer via LayerPreviewCache.fetchAndCache and
    // then preload n+1/n+2 layers.
    try {
      final layerIndex = status.layer;
      if (layerIndex == null) return;

      int? plateId;
      try {
        final fileData = status.printData?.fileData;
        if (fileData != null) {
          final meta = await BackendService().getFileMetadata(
              fileData.locationCategory ?? 'Local', fileData.path);
          if (meta['plate_id'] != null) {
            plateId = meta['plate_id'] as int?;
          }
        }
      } catch (_) {
        plateId = widget.initialPlateId;
      }
      if (plateId == null) return;
      if (plateId == 0) return;

      // Use fetchAndCache to dedupe concurrent fetches.
      try {
        final filePath =
            status.printData?.fileData?.path ?? widget.initialFilePath;
        final bytes = await LayerPreviewCache.instance.fetchAndCache(
            BackendService(), plateId, layerIndex,
            filePath: filePath);
        if (bytes.isNotEmpty) {
          // If user already enabled 2D preview, immediately display the
          // prefetched current layer so the preview reflects the active
          // layer without requiring a manual toggle.
          if (mounted && _showLayer2D) {
            if (!(_layer2DBytes != null &&
                _bytesEqual(_layer2DBytes!, bytes))) {
              setState(() {
                _layer2DBytes = bytes;
              });
            }
          }
          // Fire off preloads for the next layer in parallel; do not
          // await to avoid blocking the UI thread.
          for (int i = 1; i <= 1; i++) {
            final target = layerIndex + i;
            LayerPreviewCache.instance
                .fetchAndCache(BackendService(), plateId, target,
                    filePath: filePath)
                .then((nextBytes) {
              if (nextBytes.isNotEmpty) {
                _precacheLayerPreview(nextBytes).catchError((_) {});
              }
            }).catchError((_) {});
          }
        }
      } catch (_) {
        // ignore
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _maybePreloadNextLayers(StatusModel status) async {
    // If the 2D preview is hidden, don't waste resources fetching/decoding layers
    if (!_showLayer2D) return;

    final layerIndex = status.layer;
    if (layerIndex == null) return;
    // Throttle prefetching to every Nth layer to reduce CPU load.
    if (_layerPrefetchStride > 1 && (layerIndex % _layerPrefetchStride) != 0) {
      return;
    }

    // Resolve plate id if not already resolved for current file path.
    int? plateId = _resolvedPlateIdForPrefetch;
    if (plateId == null) {
      try {
        final fileData = status.printData?.fileData;
        if (fileData != null) {
          final meta = await BackendService().getFileMetadata(
              fileData.locationCategory ?? 'Local', fileData.path);
          if (meta['plate_id'] != null) {
            plateId = meta['plate_id'] as int?;
            _resolvedPlateIdForPrefetch = plateId;
          }
        }
      } catch (_) {
        plateId = widget.initialPlateId;
        _resolvedPlateIdForPrefetch = plateId;
      }
    }
    if (plateId == null) return;
    if (plateId == 0) return;

    try {
      // Ensure current layer is cached (deduped) then fetch+precache next two.
      // Fetch current layer (deduped) but don't block on any decoding.
      LayerPreviewCache.instance
          .fetchAndCache(BackendService(), plateId, layerIndex,
              filePath: _resolvedFilePathForPrefetch)
          .then((curBytes) {
        if (curBytes.isNotEmpty) {
          // Precache decoded image for faster rendering (fire-and-forget).
          _precacheLayerPreview(curBytes).catchError((_) {});
          // If the user currently has the 2D preview visible, immediately
          // update the displayed image so the preview follows the layer.
          if (mounted && _showLayer2D) {
            // Avoid re-setting if the bytes are identical.
            if (!(_layer2DBytes != null &&
                _bytesEqual(_layer2DBytes!, curBytes))) {
              setState(() {
                _layer2DBytes = curBytes;
              });
            }
          }
        }
      }).catchError((_) {});

      // Launch preloads for the next layer in parallel.
      for (int i = 1; i <= 1; i++) {
        final target = layerIndex + i;
        LayerPreviewCache.instance
            .fetchAndCache(BackendService(), plateId, target,
                filePath: _resolvedFilePathForPrefetch)
            .then((nextBytes) {
          if (nextBytes.isNotEmpty) {
            _precacheLayerPreview(nextBytes).catchError((_) {});
          }
        }).catchError((_) {});
      }
      _lastPrefetchedLayer = layerIndex;
    } catch (_) {
      // ignore
    }
  }

  Widget _buildButtons(StatusProvider provider, StatusModel? status) {
    final s = status;
    final isFinished = s != null && s.isIdle && s.layer != null;
    final isCanceled = s?.isCanceled ?? false;
    final canShowOptions =
        s != null && !isFinished && !isCanceled && s.layer != null;
    // Primary action button should be enabled in these cases:
    // * Active print (to allow pause/resume)
    // * Finished print (return home)
    // * Canceled print (return home)
    // Disabled when status not yet loaded, during cancel transition, or
    // while a pause is latched (provider.isPausing) and we're not already
    // in the paused state (i.e., disable the Pause action while it's
    // latched). Resume should still be enabled when paused.
    final isPaused = s?.isPaused ?? false;
    final pauseResumeEnabled = s != null &&
        !provider.isCanceling &&
        !(provider.isPausing && !isPaused);

    // If the print has finished successfully, present two equal-width
    // actions: Raise Plate (left) and Finish/Return (right).
    if (isFinished && !isCanceled) {
      return Row(children: [
        Expanded(
          flex: 1,
          child: GlassButton(
            tint: GlassButtonTint.positive,
            onPressed: () async {
              try {
                final manual = ManualProvider();
                await manual.moveToTop();
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 65),
              maximumSize: const Size(120, 65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: Text(FlutterI18n.translate(context, 'status.raisePlate'),
                style: TextStyle(fontSize: 24)),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 1,
          child: GlassButton(
            tint: GlassButtonTint.neutral,
            onPressed: () {
              // Keep original return behavior but use a clearer label
              if (widget.onReturnHome != null) {
                widget.onReturnHome!();
                return;
              }
              _checkAndShowCalibrationOverlay();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 65),
              maximumSize: const Size(120, 65),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: AutoSizeText(
              minFontSize: 16,
              maxLines: 1,
              _isCalibrationPrint == true
                  ? FlutterI18n.translate(context, 'status.finalizeCalibration')
                  : FlutterI18n.translate(context, 'status.returnToMenu'),
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ),
      ]);
    }

    return Row(children: [
      Expanded(
        flex: 1,
        child: GlassButton(
          tint: GlassButtonTint.neutral,
          onPressed: (!canShowOptions || provider.isCanceling)
              ? null
              : () {
                  showDialog(
                    context: context,
                    builder: (ctx) {
                      Provider.of<ThemeProvider>(ctx);
                      final buttonStyle = ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 65),
                        maximumSize: const Size(120, 65),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      );
                      return GlassDialog(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                FlutterI18n.translate(
                                    context, 'status.options'),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: OrionSpacing.settingsScreenPaddingNoTop,
                              child: SizedBox(
                                height: 65,
                                width: 450,
                                child: GlassButton(
                                  tint: GlassButtonTint.neutral,
                                  style: buttonStyle,
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const SettingsScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    FlutterI18n.translate(
                                        context, 'status.settings'),
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: OrionSpacing.settingsScreenPaddingNoTop,
                              child: SizedBox(
                                height: 65,
                                width: 450,
                                child: HoldButton(
                                  tint: GlassButtonTint.negative,
                                  style: buttonStyle,
                                  duration: const Duration(seconds: 2),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    provider.cancel();
                                  },
                                  child: Text(
                                    FlutterI18n.translate(
                                        context, 'status.cancelPrint'),
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: OrionSpacing.settingsScreenPaddingNoTop,
                              child: SizedBox(
                                height: 65,
                                width: 450,
                                child: HoldButton(
                                  tint: GlassButtonTint.negative,
                                  style: buttonStyle,
                                  duration: const Duration(seconds: 2),
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    final manualProvider = ManualProvider();
                                    await manualProvider.emergencyStop();
                                  },
                                  child: Text(
                                    FlutterI18n.translate(
                                        context, 'status.forceStop'),
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  );
                },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 65),
            maximumSize: const Size(120, 65),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: Text(FlutterI18n.translate(context, 'status.options'),
              style: TextStyle(fontSize: 24)),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        flex: 1,
        child: GlassButton(
          tint: GlassButtonTint.neutral,
          onPressed: () {
            setState(() {
              _showAnalytics = !_showAnalytics;
            });
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 65),
            maximumSize: const Size(120, 65),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: Text(
            _showAnalytics
                ? FlutterI18n.translate(context, 'status.simple')
                : FlutterI18n.translate(context, 'status.advanced'),
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        flex: 1,
        child: GlassButton(
          tint: isCanceled || isFinished
              ? GlassButtonTint.neutral
              : isPaused
                  ? GlassButtonTint.positive
                  : GlassButtonTint.warn,
          onPressed: !pauseResumeEnabled
              ? null
              : () {
                  if (isCanceled || isFinished) {
                    // If onReturnHome callback is provided (e.g., for calibration),
                    // call it instead of navigating home
                    if (widget.onReturnHome != null) {
                      widget.onReturnHome!();
                      return;
                    }

                    // Check if this was a calibration print and show post-calibration overlay
                    _checkAndShowCalibrationOverlay();
                    return;
                  }
                  if (s.isIdle && s.layer == null) {
                    Navigator.pop(context);
                    return;
                  }
                  provider.pauseOrResume();
                },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 65),
            maximumSize: const Size(120, 65),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          child: AutoSizeText(
            minFontSize: 16,
            maxLines: 1,
            (isCanceled || isFinished)
                ? (_isCalibrationPrint == true
                    ? FlutterI18n.translate(
                        context, 'status.finalizeCalibration')
                    : FlutterI18n.translate(context, 'status.returnToHome'))
                : isPaused
                    ? FlutterI18n.translate(context, 'status.resume')
                    : FlutterI18n.translate(context, 'status.pause'),
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    ]);
  }

  Future<void> _detectCalibrationPrint(StatusModel? status) async {
    try {
      if (status?.printData?.fileData == null) {
        setState(() => _isCalibrationPrint = false);
        return;
      }
      final fileData = status!.printData!.fileData!;
      final meta = await BackendService()
          .getFileMetadata(fileData.locationCategory ?? 'Local', fileData.path);
      final plateId = meta['plate_id'] as int?;
      setState(() {
        _isCalibrationPrint = (plateId == 0);
      });
    } catch (e) {
      _log.fine('Failed to detect calibration print: $e');
      if (mounted) setState(() => _isCalibrationPrint = false);
    }
  }

  Widget _buildAnalyticsView(
      BuildContext context, StatusProvider provider, StatusModel? status) {
    if (status == null) {
      return Center(
          child: Text(FlutterI18n.translate(context, 'status.noPrintData')));
    }

    final layerCurrent = status.layer;
    final layerTotal = status.printData?.layerCount;

    return _isLandscape
        ? _buildAnalyticsLandscape(
            context, provider, status, layerCurrent, layerTotal)
        : _buildAnalyticsPortrait(
            context, provider, status, layerCurrent, layerTotal);
  }

  Widget _buildAnalyticsPortrait(BuildContext context, StatusProvider provider,
      StatusModel status, int? layerCurrent, int? layerTotal) {
    // Build stats for force sensor to display in the second column bottom row
    final analyticsProv = Provider.of<AnalyticsProvider>(context);
    final series = analyticsProv.pressureSeries.isNotEmpty
        ? analyticsProv.pressureSeries
        : analyticsProv.getSeriesForKey('Pressure');

    List<double> values = [];
    try {
      values = _forceValuesInVisibleMiniWindow(series);
    } catch (_) {
      values = [];
    }

    final hasData = values.isNotEmpty;
    final currentVal = hasData ? values.last : 0.0;
    final maxVal = hasData ? values.reduce(max) : 0.0;
    final minVal = hasData ? values.reduce(min) : 0.0;

    // Use class helper to format force values (g vs kg)

    Widget statsCard() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                  child: _buildStatItem(
                      context,
                      FlutterI18n.translate(context, 'status.statMin'),
                      _formatForceValue(minVal))),
              Container(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                  child: _buildStatItem(
                      context,
                      FlutterI18n.translate(context, 'status.statCurrent'),
                      _formatForceValue(currentVal),
                      isLarge: true)),
              Container(width: 1, color: Theme.of(context).dividerColor),
              Expanded(
                  child: _buildStatItem(
                      context,
                      FlutterI18n.translate(context, 'status.statMax'),
                      _formatForceValue(maxVal))),
            ],
          ),
        ),
      );
    }

    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                children: [
                  // Top half: two-column layout where left column is the
                  // force sensor spanning the full height and the right column
                  // has three rows; the bottom row displays current/min/max.
                  Expanded(
                    child: Row(
                      children: [
                        // Left column: force sensor (spans all three rows)
                        Expanded(
                          child: _buildPlaceholderCard(
                            context,
                            'Force Sensor',
                            Icons.compress,
                          ),
                        ),
                        const SizedBox(width: 5),
                        // Right column: three vertical rows, last one shows stats
                        Expanded(
                          child: Column(
                            children: [
                              const Expanded(child: SizedBox()),
                              const SizedBox(height: 8),
                              const Expanded(child: SizedBox()),
                              const SizedBox(height: 8),
                              // Bottom row: stats
                              Expanded(child: statsCard()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom info cards
                  Row(children: [
                    Expanded(
                      child: _buildInfoCard(
                        FlutterI18n.translate(context, 'status.printProgress'),
                        layerCurrent == null || layerTotal == null
                            ? '- / -'
                            : '$layerCurrent / $layerTotal',
                      ),
                    ),
                    Expanded(
                      child: _buildInfoCard(
                        FlutterI18n.translate(context, 'status.cpuTemp'),
                        provider.cpuTemperature != null
                            ? '${provider.cpuTemperature!.toStringAsFixed(1)}°C'
                            : 'N/A',
                        provider.cpuTemperature ?? 0.0,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 5),
                  Row(children: [
                    Expanded(
                      child: _buildInfoCard(
                        FlutterI18n.translate(context, 'status.vatTemp'),
                        provider.resinTemperature != null
                            ? '${provider.resinTemperature}°C'
                            : 'N/A',
                      ),
                    ),
                    Expanded(
                      child: _buildInfoCard(
                        FlutterI18n.translate(context, 'status.resinName'),
                        'N/A', // TODO: Connect to resin profile data
                      ),
                    ),
                  ]),
                  const Spacer(),
                  _buildButtons(provider, status),
                ],
              ),
            ),
          ],
        ),
      )
    ]);
  }

  Widget _buildAnalyticsLandscape(BuildContext context, StatusProvider provider,
      StatusModel status, int? layerCurrent, int? layerTotal) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateAnalyticsLeftStackHeight();
    });

    return Column(children: [
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 1,
            child: Column(children: [
              Spacer(),
              Column(
                key: _analyticsLeftStackMeasureKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInfoCard(
                    FlutterI18n.translate(context, 'status.printProgress'),
                    layerCurrent == null || layerTotal == null
                        ? '- / -'
                        : '$layerCurrent / $layerTotal',
                  ),
                  _buildInfoCard(
                    FlutterI18n.translate(context, 'status.lastLayerTime'),
                    // Prefer live analytics LayerTime (currentLayerSeconds), then
                    // the provider-parsed PrevLayerTime (provider.prevLayerSeconds),
                    // finally fall back to the model field when present.
                    (provider.currentLayerSeconds ??
                                provider.prevLayerSeconds ??
                                status.prevLayerSeconds) !=
                            null
                        ?
                        // display whichever value we picked
                        '${(provider.currentLayerSeconds ?? provider.prevLayerSeconds ?? status.prevLayerSeconds)!.toStringAsFixed(1)} s'
                        : 'N/A',
                  ),
                  _buildInfoCard(
                      FlutterI18n.translate(context, 'status.resinTemp'),
                      provider.resinTemperature != null
                          ? '${provider.resinTemperature}°C'
                          : 'N/A', // TODO: Connect to actual data
                      provider.resinTemperature!.toDouble()),
                  // UV LED Temp is provided via analytics (TemperatureOutside)
                  Builder(builder: (ctx) {
                    final analyticsProv = Provider.of<AnalyticsProvider>(ctx);
                    final dynamic uvRaw =
                        analyticsProv.getLatestForKey('TemperatureOutside');
                    final String uvText = uvRaw != null ? '$uvRaw°C' : 'N/A';
                    final double uvVal = uvRaw is num
                        ? uvRaw.toDouble()
                        : (double.tryParse(uvRaw?.toString() ?? '') ?? 0.0);
                    return _buildInfoCard(
                        FlutterI18n.translate(context, 'status.uvLedTemp'),
                        uvText,
                        uvVal);
                  }),
                ],
              ),
              Spacer(),
            ]),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            flex: 1,
            child: Column(children: [
              Spacer(),
              Builder(builder: (ctx) {
                final analyticsProv =
                    Provider.of<AnalyticsProvider>(ctx, listen: false);
                final dynamic waitRaw =
                    analyticsProv.getLatestForKey('DynamicWait');
                String waitText;
                if (waitRaw == null) {
                  waitText = 'N/A';
                } else if (waitRaw is num) {
                  waitText = '${waitRaw.toStringAsFixed(2)} s';
                } else {
                  final parsed = double.tryParse(waitRaw.toString());
                  if (parsed != null) {
                    waitText = '${parsed.toStringAsFixed(2)} s';
                  } else {
                    waitText = waitRaw.toString();
                  }
                }
                return _buildInfoCard(
                    FlutterI18n.translate(context, 'status.lastWaitTime'),
                    waitText);
              }),
              Builder(builder: (ctx) {
                final analyticsProv =
                    Provider.of<AnalyticsProvider>(ctx, listen: false);
                final dynamic liftRaw =
                    analyticsProv.getLatestForKey('LiftHeight');
                String liftText;
                if (liftRaw == null) {
                  liftText = 'N/A';
                } else if (liftRaw is num) {
                  liftText = '${liftRaw.toStringAsFixed(2)} mm';
                } else {
                  final parsed = double.tryParse(liftRaw.toString());
                  if (parsed != null) {
                    liftText = '${parsed.toStringAsFixed(2)} mm';
                  } else {
                    liftText = liftRaw.toString();
                  }
                }
                return _buildInfoCard(
                    FlutterI18n.translate(context, 'status.lastLiftHeight'),
                    liftText);
              }),
              Builder(builder: (ctx) {
                final analyticsProv = Provider.of<AnalyticsProvider>(ctx);
                final dynamic mcuRaw =
                    analyticsProv.getLatestForKey('TemperatureMCU');
                final String mcuText = mcuRaw != null ? '$mcuRaw°C' : 'N/A';
                final double mcuVal = mcuRaw is num
                    ? mcuRaw.toDouble()
                    : (double.tryParse(mcuRaw?.toString() ?? '') ?? 0.0);
                return _buildInfoCard(
                    FlutterI18n.translate(context, 'status.mcuTemp'),
                    mcuText,
                    mcuVal);
              }),
              _buildInfoCard(
                  FlutterI18n.translate(context, 'status.cpuTemp'),
                  provider.cpuTemperature != null
                      ? '${provider.cpuTemperature!.toStringAsFixed(1)}°C'
                      : 'N/A',
                  provider.cpuTemperature ?? 0.0),
              Spacer(),
            ]),
          ),
          const SizedBox(width: 12.0),
          // Right column: force sensor and stats (temperature graph removed)
          Expanded(
            flex: 2,
            child: LayoutBuilder(builder: (lbCtx, lbConstraints) {
              // Constrain right column to the actual rendered height of the
              // left info-card stack so both columns share identical vertical
              // bounds regardless of font/theme/card metric changes.
              final double availH = lbConstraints.maxHeight;
              final double infoContentH = (_analyticsLeftStackHeight ?? 320.0)
                  .clamp(0.0, availH)
                  .toDouble();
              final double topPad =
                  ((availH - infoContentH) / 2).clamp(0.0, availH);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: topPad),
                  SizedBox(
                    height: infoContentH,
                    child: Column(
                      children: [
                        Expanded(
                          flex: 7,
                          child: _buildPlaceholderCard(
                            lbCtx,
                            'Force Sensor',
                            Icons.compress,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Builder(builder: (ctx) {
                            final analyticsProv =
                                Provider.of<AnalyticsProvider>(ctx);
                            final series =
                                analyticsProv.pressureSeries.isNotEmpty
                                    ? analyticsProv.pressureSeries
                                    : analyticsProv.getSeriesForKey('Pressure');

                            List<double> values = [];
                            try {
                              values = _forceValuesInVisibleMiniWindow(series);
                            } catch (_) {
                              values = [];
                            }

                            final hasData = values.isNotEmpty;
                            final currentVal = hasData ? values.last : 0.0;
                            final maxVal = hasData ? values.reduce(max) : 0.0;
                            final minVal = hasData ? values.reduce(min) : 0.0;

                            return GlassCard(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 0, vertical: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: _buildStatItem(
                                            ctx,
                                            FlutterI18n.translate(
                                                context, 'status.statMin'),
                                            _formatForceValue(minVal)),
                                      ),
                                    ),
                                    Container(
                                        width: 1,
                                        color: Theme.of(context).dividerColor),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: _buildStatItem(
                                            ctx,
                                            FlutterI18n.translate(
                                                context, 'status.statCurrent'),
                                            _formatForceValue(currentVal),
                                            isLarge: true),
                                      ),
                                    ),
                                    Container(
                                        width: 1,
                                        color: Theme.of(context).dividerColor),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: _buildStatItem(
                                            ctx,
                                            FlutterI18n.translate(
                                                context, 'status.statMax'),
                                            _formatForceValue(maxVal)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: topPad),
                ],
              );
            }),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Padding(
        padding: EdgeInsets.zero,
        child: _buildButtons(provider, status),
      ),
    ]);
  }

  Widget _buildPlaceholderCard(
      BuildContext context, String title, IconData icon) {
    Provider.of<ThemeProvider>(context); // theming

    // Special handling for Force Sensor card
    if (title == 'Force Sensor') {
      return _buildForceSensorCard(context);
    }

    return GlassCard(
      margin: EdgeInsets.zero,
      outlined: true,
      elevation: 1.0,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildForceSensorCard(BuildContext context) {
    try {
      final analyticsProv =
          Provider.of<AnalyticsProvider>(context, listen: false);
      final series = analyticsProv.pressureSeries.isNotEmpty
          ? analyticsProv.pressureSeries
          : analyticsProv.getSeriesForKey('Pressure');

      return GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        outlined: true,
        elevation: 1.0,
        child: series.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.compress,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      FlutterI18n.translate(context, 'tools.forceSensor'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      FlutterI18n.translate(context, 'force.noData'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                          ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: IgnorePointer(
                  child: _ForceSensorMiniChart(series: series),
                ),
              ),
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              FlutterI18n.translate(context, 'force.loadError'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildStatItem(BuildContext context, String label, String value,
      {bool isLarge = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: isLarge ? 20 : 18,
                color: isLarge ? Theme.of(context).colorScheme.primary : null,
              ),
        ),
      ],
    );
  }

  // Produce a smooth, visually-pleasing MaterialColor for a given
  // temperature. We interpolate between a set of warm color stops
  // and synthesize a MaterialColor swatch so the result can be used
  // anywhere a MaterialColor is expected.
  MaterialColor _colorForTemperature(double temperature) {
    // Clamp to range 20..70
    final tClamped = temperature.clamp(20.0, 70.0);

    // Stops for a warm gradient (pale yellow -> amber -> orange -> deepOrange -> red)
    final stops = <double>[20.0, 30.0, 40.0, 55.0, 70.0];
    final colors = <Color>[
      const Color(0xFFFDF3BF), // pale butter
      const Color(0xFFFCD34D), // amber-300
      const Color(0xFFFB923C), // orange-400
      const Color(0xFFF97316), // deep orange-500
      const Color(0xFFEF4444), // red-500
    ];

    // Find segment and local interpolation factor
    Color base;
    if (tClamped <= stops.first) {
      base = colors.first;
    } else if (tClamped >= stops.last) {
      base = colors.last;
    } else {
      int idx = 0;
      for (int i = 0; i < stops.length - 1; i++) {
        if (tClamped >= stops[i] && tClamped <= stops[i + 1]) {
          idx = i;
          break;
        }
      }
      final localT = (tClamped - stops[idx]) / (stops[idx + 1] - stops[idx]);
      base = Color.lerp(colors[idx], colors[idx + 1], localT) ?? colors[idx];
    }

    return _createMaterialColor(base);
  }

  // Create a MaterialColor swatch from a single Color. This is the
  // common utility pattern used to synthesize a swatch for theming.
  MaterialColor _createMaterialColor(Color color) {
    final strengths = <double>[.05];
    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    final swatch = <int, Color>{};
    final int r = (color.r * 255.0).round().clamp(0, 255);
    final int g = (color.g * 255.0).round().clamp(0, 255);
    final int b = (color.b * 255.0).round().clamp(0, 255);
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    // Map typical MaterialColor keys (50..900) to the generated strengths
    final mapped = <int, Color>{
      50: swatch[50]!,
      100: swatch[100]!,
      200: swatch[200]!,
      300: swatch[300]!,
      400: swatch[400]!,
      500: swatch[500]!,
      600: swatch[600]!,
      700: swatch[700]!,
      800: swatch[800]!,
      900: swatch[900]!,
    };
    return MaterialColor(color.toARGB32(), mapped);
  }
}

// Chart widget for force sensor dialog (replicates force_screen.dart chart logic)
class _ForceSensorDialogChart extends StatefulWidget {
  final List<Map<String, dynamic>> series;
  const _ForceSensorDialogChart({required this.series});

  @override
  State<_ForceSensorDialogChart> createState() =>
      _ForceSensorDialogChartState();
}

class _ForceSensorDialogChartState extends State<_ForceSensorDialogChart> {
  static const int _windowSize = 900;
  double? _displayMin;
  double? _displayMax;
  double _windowMaxX = 0.0;
  final Map<Object, double> _idToX = {};
  double _lastX = -1.0;

  List<FlSpot> _toSpots(List<Map<String, dynamic>> serie) {
    final last = serie.length;
    final start = last - _windowSize < 0 ? 0 : last - _windowSize;
    final window = serie.sublist(start, last);
    final spots = <FlSpot>[];
    final currentIds = <Object>{};

    for (var i = 0; i < window.length; i++) {
      final item = window[i];
      final idRaw = item['id'] ?? i;
      final key = idRaw is Object ? idRaw : idRaw.toString();
      currentIds.add(key);

      final vRaw = item['v'];
      final v = vRaw is num
          ? vRaw.toDouble()
          : double.tryParse(vRaw?.toString() ?? '');
      if (v == null) continue;

      double x;
      if (_idToX.containsKey(key)) {
        x = _idToX[key]!;
      } else {
        _lastX = _lastX + 1.0;
        x = _lastX;
        _idToX[key] = x;
      }
      spots.add(FlSpot(x, v));
    }

    final toRemove = <Object>[];
    _idToX.forEach((k, v) {
      if (!currentIds.contains(k)) toRemove.add(k);
    });
    for (final k in toRemove) {
      _idToX.remove(k);
    }

    _windowMaxX = _lastX <= 0 ? (_windowSize - 1).toDouble() : _lastX;
    final windowStart = _windowMaxX <= 0
        ? 0.0
        : max(0.0, _windowMaxX - (_windowSize - 1).toDouble());

    final remapped = spots
        .map((s) => FlSpot(s.x - windowStart, s.y))
        .toList(growable: false);
    return remapped;
  }

  void _updateDisplayRange(List<FlSpot> spots) {
    if (spots.isEmpty) return;
    final minY = spots.map((s) => s.y).reduce(min);
    final maxY = spots.map((s) => s.y).reduce(max);
    final span = maxY - minY;
    final pad = span == 0 ? (maxY.abs() * 0.05 + 1.0) : (span * 0.05);

    double targetMin;
    double targetMax;
    const double hardLimit = 60000.0;

    if (minY >= -100.0 && maxY <= 100.0) {
      targetMin = -100.0;
      targetMax = 100.0;
    } else {
      targetMin = max(minY - pad, -hardLimit);
      targetMax = min(maxY + pad, hardLimit);
      if (targetMin > 0) targetMin = 0;
      if (targetMax < 0) targetMax = 0;
    }

    const double immediateFraction = 0.25;
    const double immediateAbs = 200.0;
    const double smoothAlpha = 0.6;

    if (_displayMin == null || _displayMax == null) {
      _displayMin = targetMin;
      _displayMax = targetMax;
    } else {
      final curSpan = (_displayMax! - _displayMin!).abs();
      final needImmediate = (minY <
              _displayMin! - max(immediateAbs, curSpan * immediateFraction)) ||
          (maxY >
              _displayMax! + max(immediateAbs, curSpan * immediateFraction));

      if (needImmediate) {
        _displayMin = targetMin;
        _displayMax = targetMax;
      } else {
        _displayMin = _displayMin! + (targetMin - _displayMin!) * smoothAlpha;
        _displayMax = _displayMax! + (targetMax - _displayMax!) * smoothAlpha;
      }
    }
  }

  @override
  void didUpdateWidget(covariant _ForceSensorDialogChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final spots = _toSpots(widget.series);
    _updateDisplayRange(spots);
  }

  @override
  Widget build(BuildContext context) {
    final spots = _toSpots(widget.series);
    if (spots.isEmpty) {
      return Center(
          child: Text(FlutterI18n.translate(context, 'status.noData')));
    }

    _updateDisplayRange(spots);
    final displayMin = _displayMin ?? spots.map((s) => s.y).reduce(min) - 1.0;
    final displayMax = _displayMax ?? spots.map((s) => s.y).reduce(max) + 1.0;

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        borderData: FlBorderData(
          border: Border.all(color: Colors.transparent),
        ),
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        minY: displayMin,
        maxY: displayMax,
        maxX: (_windowSize + 10.0).toDouble(),
        minX: -10.0,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            gradient: LinearGradient(
              colors: [
                Colors.greenAccent,
                Colors.redAccent,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            isCurved: true,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            color: Theme.of(context).colorScheme.primary,
            barWidth: 1.5,
          )
        ],
      ),
    );
  }
}

// Mini force sensor chart widget for analytics view
class _ForceSensorMiniChart extends StatefulWidget {
  final List<Map<String, dynamic>> series;
  const _ForceSensorMiniChart({required this.series});

  @override
  State<_ForceSensorMiniChart> createState() => _ForceSensorMiniChartState();
}

class _ForceSensorMiniChartState extends State<_ForceSensorMiniChart> {
  static const int _windowSize =
      _forceSensorMiniWindowSize; // Smaller window for mini chart
  double? _displayMin;
  double? _displayMax;
  final Map<Object, double> _idToX = {};
  double _lastX = -1.0;

  List<FlSpot> _toSpots(List<Map<String, dynamic>> serie) {
    final last = serie.length;
    final start = last - _windowSize < 0 ? 0 : last - _windowSize;
    final window = serie.sublist(start, last);
    final spots = <FlSpot>[];
    final currentIds = <Object>{};

    for (var i = 0; i < window.length; i++) {
      final item = window[i];
      final idRaw = item['id'] ?? i;
      final key = idRaw is Object ? idRaw : idRaw.toString();
      currentIds.add(key);

      final vRaw = item['v'];
      final v = vRaw is num
          ? vRaw.toDouble()
          : double.tryParse(vRaw?.toString() ?? '');
      if (v == null) continue;

      double x;
      if (_idToX.containsKey(key)) {
        x = _idToX[key]!;
      } else {
        _lastX = _lastX + 1.0;
        x = _lastX;
        _idToX[key] = x;
      }
      spots.add(FlSpot(x, v));
    }

    // Clean up old mappings
    final toRemove = <Object>[];
    _idToX.forEach((k, v) {
      if (!currentIds.contains(k)) toRemove.add(k);
    });
    for (final k in toRemove) {
      _idToX.remove(k);
    }

    final windowMaxX = _lastX <= 0 ? (_windowSize - 1).toDouble() : _lastX;
    final windowStart =
        windowMaxX <= 0 ? 0.0 : max(0.0, windowMaxX - (_windowSize - 1));

    return spots
        .map((s) => FlSpot(s.x - windowStart, s.y))
        .toList(growable: false);
  }

  void _updateDisplayRange(List<FlSpot> spots) {
    if (spots.isEmpty) return;
    final minY = spots.map((s) => s.y).reduce(min);
    final maxY = spots.map((s) => s.y).reduce(max);
    final span = maxY - minY;
    final pad = span == 0 ? (maxY.abs() * 0.05 + 1.0) : (span * 0.05);

    double targetMin;
    double targetMax;

    if (minY >= -100.0 && maxY <= 100.0) {
      targetMin = -100.0;
      targetMax = 100.0;
    } else {
      targetMin = max(minY - pad, -60000.0);
      targetMax = min(maxY + pad, 60000.0);
      if (targetMin > 0) targetMin = 0;
      if (targetMax < 0) targetMax = 0;
    }

    if (_displayMin == null || _displayMax == null) {
      _displayMin = targetMin;
      _displayMax = targetMax;
    } else {
      const smoothAlpha = 0.6;
      _displayMin = _displayMin! + (targetMin - _displayMin!) * smoothAlpha;
      _displayMax = _displayMax! + (targetMax - _displayMax!) * smoothAlpha;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spots = _toSpots(widget.series);
    if (spots.isEmpty) {
      return Center(
          child: Text(FlutterI18n.translate(context, 'status.noData')));
    }

    _updateDisplayRange(spots);
    final displayMin = _displayMin ?? -100.0;
    final displayMax = _displayMax ?? 100.0;

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        borderData: FlBorderData(border: Border.all(color: Colors.transparent)),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
            strokeWidth: 0.5,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        minY: displayMin,
        maxY: displayMax,
        maxX: (_windowSize + 10.0).toDouble(),
        minX: -10.0,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            gradient: LinearGradient(
              colors: [Colors.greenAccent, Colors.redAccent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            isCurved: true,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            barWidth: 2.0,
          )
        ],
      ),
    );
  }
}
