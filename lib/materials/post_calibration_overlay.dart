/*
* Orion - Post Calibration Overlay
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

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:provider/provider.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/materials/materials_screen.dart';
import 'package:orion/util/orion_config.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Overlay shown after a calibration print completes
/// Guides user through evaluation and saving optimal exposure settings
class PostCalibrationOverlay extends StatefulWidget {
  final String calibrationModelName;
  final String? resinProfileName;
  final double startExposure;
  final double exposureIncrement;
  final int profileId;
  final int calibrationModelId;
  final String? evaluationGuideUrl;
  final VoidCallback onComplete;

  const PostCalibrationOverlay({
    super.key,
    required this.calibrationModelName,
    this.resinProfileName,
    required this.startExposure,
    required this.exposureIncrement,
    required this.profileId,
    required this.calibrationModelId,
    this.evaluationGuideUrl,
    required this.onComplete,
  });

  @override
  State<PostCalibrationOverlay> createState() => _PostCalibrationOverlayState();
}

class _PostCalibrationOverlayState extends State<PostCalibrationOverlay> {
  final _logger = Logger('PostCalibrationOverlay');
  final _backendService = BackendService();
  final _config = OrionConfig();
  int _currentStep = 0; // 0 = QR code, 1 = evaluation
  // Allow up to two selected pieces for fine-tuning
  final List<int> _selectedPieces = [];
  bool _doNotShowAgain = false;

  @override
  void initState() {
    super.initState();
    try {
      _doNotShowAgain = _config.getFlag(
        'skip_calibration_${widget.calibrationModelId}',
        category: 'calibration',
      );
      // If user previously opted to skip the guide for this model, go
      // straight to the evaluation step.
      if (_doNotShowAgain) {
        _currentStep = 1;
      }
    } catch (e) {
      _logger.fine('Failed to read skip flag: $e');
      _doNotShowAgain = false;
    }
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
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: _currentStep == 0
                ? _buildStep0Content(context)
                : _buildStep1Content(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStep0Content(BuildContext context) {
    return Column(
      key: const ValueKey('step0'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.checkCircle(),
              size: 24,
              color: Colors.green.shade400,
            ),
            const SizedBox(width: 10),
            Text(
              FlutterI18n.translate(context, 'postCal.complete'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade400,
              ),
            ),
          ],
        ),
        if (widget.resinProfileName != null) ...[
          const SizedBox(height: 4),
          Text(
            '',
            style: TextStyle(
              fontSize: 4,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        const SizedBox(height: 12),

        // ── Body ─────────────────────────────────────────────────
        Expanded(
          child: _buildQrCodeView(),
        ),

        const SizedBox(height: 16),

        // ── Action buttons ────────────────────────────────────────
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildStep1Content(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      key: const ValueKey('step1'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsFill.magnifyingGlass,
              size: 24,
              color: primary,
            ),
            const SizedBox(width: 10),
            Text(
              FlutterI18n.translate(context, 'postCal.evaluateTest'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ],
        ),
        if (widget.resinProfileName != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.resinProfileName!,
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        const SizedBox(height: 12),

        // ── Body ─────────────────────────────────────────────────
        Expanded(
          child: _buildEvaluationView(),
        ),

        const SizedBox(height: 16),

        // ── Action buttons ────────────────────────────────────────
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    if (_currentStep == 0) {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: () {
                final newValue = !_doNotShowAgain;
                try {
                  _config.setFlag(
                    'skip_calibration_${widget.calibrationModelId}',
                    newValue,
                    category: 'calibration',
                  );
                } catch (e) {
                  _logger.warning('Failed to persist skip flag: $e');
                }
                setState(() {
                  _doNotShowAgain = newValue;
                  if (_doNotShowAgain) _currentStep = 1;
                });
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _doNotShowAgain
                        ? PhosphorIcons.checkSquare()
                        : PhosphorIcons.square(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(FlutterI18n.translate(context, 'postCal.skipGuide'),
                      style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.positive,
              onPressed: () => setState(() => _currentStep = 1),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(FlutterI18n.translate(context, 'postCal.next'),
                      style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Icon(PhosphorIcons.caretRight(), size: 20),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.neutral,
              onPressed: () => setState(() => _currentStep = 0),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _doNotShowAgain
                        ? PhosphorIcons.info()
                        : PhosphorIcons.caretLeft(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _doNotShowAgain ? 'Guide' : 'Back',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassButton(
              tint: GlassButtonTint.negative,
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        const MaterialsScreen(initialIndex: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 65),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIconsFill.arrowCounterClockwise, size: 20),
                  const SizedBox(width: 8),
                  Text(FlutterI18n.translate(context, 'postCal.reconfigure'),
                      style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_selectedPieces.length == 2)
            Expanded(
              child: GlassButton(
                tint: GlassButtonTint.positive,
                onPressed: _showFineTuneDialog,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 65),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(FlutterI18n.translate(context, 'postCal.fineTune'),
                        style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Icon(PhosphorIcons.slidersHorizontal(), size: 20),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: GlassButton(
                tint: GlassButtonTint.positive,
                onPressed:
                    _selectedPieces.length != 1 ? null : _saveOptimalExposure,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 65),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(FlutterI18n.translate(context, 'postCal.save'),
                        style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Icon(PhosphorIcons.check(), size: 20),
                  ],
                ),
              ),
            ),
        ],
      );
    }
  }

  Widget _buildQrCodeView() {
    // Hardcoded evaluation guide URLs for NanoDLP calibration models
    // TODO: Make these configurable via backend when support is added
    String evaluationGuideUrl;
    switch (widget.calibrationModelId) {
      case 1:
        evaluationGuideUrl =
            'https://docs.google.com/document/d/1aoMSE6GBGMcoYXNGfPP9s_Jg8vr1wQmmZuvqP3suago/edit?tab=t.0#heading=h.bvm0ca3vxmwr';
        break;
      case 2:
        evaluationGuideUrl =
            'https://docs.google.com/document/d/1aoMSE6GBGMcoYXNGfPP9s_Jg8vr1wQmmZuvqP3suago/edit?tab=t.0#heading=h.bj4wz2wzngny';
        break;
      default:
        // Fallback URL if calibration model ID is unknown
        evaluationGuideUrl = widget.evaluationGuideUrl ??
            'https://docs.openresin.org/calibration/${widget.calibrationModelName.toLowerCase().replaceAll(' ', '-')}';
    }

    return LayoutBuilder(
      key: const ValueKey('qr'),
      builder: (context, constraints) {
        final qrSize = ((constraints.maxWidth / 2) - 40).clamp(80.0, 260.0);
        final onSurface = Theme.of(context).colorScheme.onSurface;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GlassCard(
                elevation: 1.0,
                outlined: true,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          FlutterI18n.translate(
                              context, 'postCal.evaluationGuide'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: onSurface.withValues(alpha: 0.55),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          FlutterI18n.translate(context, 'postCal.guideDesc'),
                          style: TextStyle(
                            fontSize: 18,
                            color: onSurface.withValues(alpha: 0.75),
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildGuideItem(
                          context,
                          FlutterI18n.translate(context, 'postCal.scanQr'),
                        ),
                        const SizedBox(height: 10),
                        _buildGuideItem(
                          context,
                          FlutterI18n.translate(context, 'postCal.readGuide'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Right: QR code
            Expanded(
              child: GlassCard(
                elevation: 1.0,
                outlined: true,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: QrImageView(
                      data: evaluationGuideUrl,
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
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuideItem(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        height: 1.55,
      ),
    );
  }

  Widget _buildEvaluationView() {
    Widget pieceButton(int index) {
      final pieceNumber = index + 1;
      final exposure =
          widget.startExposure + (widget.exposureIncrement * index);
      final isSelected = _selectedPieces.contains(pieceNumber);

      return Expanded(
        child: GlassButton(
          tint: isSelected ? GlassButtonTint.positive : GlassButtonTint.neutral,
          onPressed: () {
            setState(() {
              if (isSelected) {
                _selectedPieces.remove(pieceNumber);
                return;
              }

              if (_selectedPieces.isEmpty) {
                _selectedPieces.add(pieceNumber);
                return;
              }

              if (_selectedPieces.length == 1) {
                final existing = _selectedPieces.first;
                if ((existing - pieceNumber).abs() == 1) {
                  _selectedPieces.add(pieceNumber);
                } else {
                  _selectedPieces.clear();
                  _selectedPieces.add(pieceNumber);
                }
                return;
              }

              _selectedPieces.removeAt(0);
              _selectedPieces.add(pieceNumber);
              final a = _selectedPieces[0];
              final b = _selectedPieces[1];
              if ((a - b).abs() != 1) {
                _selectedPieces.clear();
                _selectedPieces.add(pieceNumber);
              }
            });
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, double.infinity),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '#$pieceNumber',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${exposure.toStringAsFixed(1)}s',
                style: TextStyle(fontSize: 20, color: Colors.grey.shade300),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      key: const ValueKey('evaluation'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: pieces 1–3
          Expanded(
            child: Row(
              children: [
                pieceButton(0),
                const SizedBox(width: 10),
                pieceButton(1),
                const SizedBox(width: 10),
                pieceButton(2),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Row 2: pieces 4–6
          Expanded(
            child: Row(
              children: [
                pieceButton(3),
                const SizedBox(width: 10),
                pieceButton(4),
                const SizedBox(width: 10),
                pieceButton(5),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            FlutterI18n.translate(context, 'postCal.selectPieceGuide'),
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _saveOptimalExposure() async {
    if (_selectedPieces.isEmpty) return;
    final nav = Navigator.of(context);

    // Guard against unresolved profile ID — same as edit resin screen.
    if (widget.profileId == 0) {
      _logger.warning('Cannot save exposure: profileId is 0 (unresolved)');
      widget.onComplete();
      return;
    }

    final pieceNumber = _selectedPieces.first;
    final optimalExposure =
        widget.startExposure + (widget.exposureIncrement * (pieceNumber - 1));

    // Fetch current profile to get the actual previous exposure time
    // and build a full settings merge so we can use saveResinSettings
    // (the same reliable path the edit resin screen uses).
    double previousExposure = widget.startExposure;
    bool saved = false;
    try {
      final settings = await _backendService.getResinSettings(widget.profileId);
      if (settings != null) {
        previousExposure = settings.normalCureTime;
        await _backendService.saveResinSettings(
          widget.profileId,
          ResinSettings(
            burnInCureTime: settings.burnInCureTime,
            normalCureTime: optimalExposure,
            liftAfterPrint: settings.liftAfterPrint,
            burnInCount: settings.burnInCount,
            waitAfterCure: settings.waitAfterCure,
            waitAfterLife: settings.waitAfterLife,
          ),
        );
        saved = true;
        _logger.info('Successfully saved optimal exposure to profile');
      } else {
        // Fallback: try the single-field convenience method.
        await _backendService.saveResinExposure(
            widget.profileId, optimalExposure);
        saved = true;
        _logger.info('Saved via saveResinExposure fallback');
      }
    } catch (e) {
      _logger.warning('Failed to save optimal exposure to profile: $e');
    }

    final navCtx = nav.context;
    if (!navCtx.mounted) return;

    if (!saved) {
      showDialog(
        context: navCtx,
        builder: (context) => GlassAlertDialog(
          title: Text(FlutterI18n.translate(context, 'common.error'),
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          content: Text(
            'Could not save exposure to profile.\n'
            'Please set it manually in Materials → Edit Resin.',
            style: const TextStyle(fontSize: 20),
          ),
          actions: [
            GlassButton(
              tint: GlassButtonTint.positive,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(120, 65),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onComplete();
              },
              child: Text(FlutterI18n.translate(context, 'common.done')),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: navCtx,
      builder: (context) => GlassAlertDialog(
        title: Text(FlutterI18n.translate(context, 'postCal.complete'),
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.resinProfileName ??
                  FlutterI18n.translate(context, 'calibration.resinProfile'),
              style: TextStyle(
                fontSize: 22,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      FlutterI18n.translate(context, 'postCal.previous'),
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${previousExposure.toStringAsFixed(1)}s',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(
                    Icons.arrow_forward,
                    color: Theme.of(context).colorScheme.primary,
                    size: 40,
                  ),
                ),
                Column(
                  children: [
                    Text(
                      FlutterI18n.translate(context, 'postCal.optimal'),
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${optimalExposure.toStringAsFixed(1)}s',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              FlutterI18n.translate(context, 'postCal.layerExposureUpdated'),
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        actions: [
          GlassButton(
            tint: GlassButtonTint.positive,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 65),
            ),
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              widget.onComplete(); // Close overlay
            },
            child: Text(FlutterI18n.translate(context, 'common.done')),
          ),
        ],
      ),
    );
  }

  void _showFineTuneDialog() {
    if (_selectedPieces.length != 2) return;

    final p1 = _selectedPieces[0];
    final p2 = _selectedPieces[1];
    final e1 = widget.startExposure + (widget.exposureIncrement * (p1 - 1));
    final e2 = widget.startExposure + (widget.exposureIncrement * (p2 - 1));
    final minExp = e1 < e2 ? e1 : e2;
    final maxExp = e1 < e2 ? e2 : e1;

    double value = minExp;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          final range = (maxExp - minExp).abs();
          final divisions =
              range <= 0.0001 ? 1 : ((range / 0.05).round()).clamp(1, 1000);

          return GlassAlertDialog(
            title: Text(
                FlutterI18n.translate(context, 'postCal.fineTuneExposure'),
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${FlutterI18n.translate(context, 'postCal.selectValueBetween')} ${minExp.toStringAsFixed(2)} - ${maxExp.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 16),
                Text(
                  '${value.toStringAsFixed(2)}s',
                  style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary),
                ),
                Slider(
                  value: value,
                  min: minExp,
                  max: maxExp,
                  divisions: divisions,
                  onChanged: (v) {
                    // Snap to 0.05s steps for cleanliness
                    final snapped = (v / 0.05).round() * 0.05;
                    setStateDialog(() {
                      value = double.parse(snapped.toStringAsFixed(2));
                    });
                  },
                ),
              ],
            ),
            actions: [
              GlassButton(
                tint: GlassButtonTint.neutral,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 65),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(FlutterI18n.translate(context, 'common.cancel')),
              ),
              GlassButton(
                tint: GlassButtonTint.positive,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 65),
                ),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  nav.pop();

                  // Guard against unresolved profile ID.
                  if (widget.profileId == 0) {
                    _logger.warning(
                        'Cannot save fine-tuned exposure: profileId is 0');
                    widget.onComplete();
                    return;
                  }

                  // Fetch current profile and save via saveResinSettings
                  // (the same reliable path the edit resin screen uses).
                  double previousExposure = widget.startExposure;
                  bool saved = false;
                  try {
                    final settings = await _backendService
                        .getResinSettings(widget.profileId);
                    if (settings != null) {
                      previousExposure = settings.normalCureTime;
                      await _backendService.saveResinSettings(
                        widget.profileId,
                        ResinSettings(
                          burnInCureTime: settings.burnInCureTime,
                          normalCureTime: value,
                          liftAfterPrint: settings.liftAfterPrint,
                          burnInCount: settings.burnInCount,
                          waitAfterCure: settings.waitAfterCure,
                          waitAfterLife: settings.waitAfterLife,
                        ),
                      );
                      saved = true;
                    } else {
                      await _backendService.saveResinExposure(
                          widget.profileId, value);
                      saved = true;
                    }
                  } catch (e) {
                    _logger.warning('Failed to save fine-tuned exposure: $e');
                  }
                  final fineTuneCtx = nav.context;
                  if (!fineTuneCtx.mounted) return;

                  if (!saved) {
                    showDialog(
                      context: fineTuneCtx,
                      builder: (context) => GlassAlertDialog(
                        title: Text(
                            FlutterI18n.translate(context, 'common.error'),
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                        content: const Text(
                          'Could not save exposure to profile.\n'
                          'Please set it manually in Materials → Edit Resin.',
                          style: TextStyle(fontSize: 20),
                        ),
                        actions: [
                          GlassButton(
                            tint: GlassButtonTint.positive,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(120, 65),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onComplete();
                            },
                            child: Text(FlutterI18n.translate(
                                context, 'common.done')),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  showDialog(
                    context: fineTuneCtx,
                    builder: (context) => GlassAlertDialog(
                      title: Text(
                          FlutterI18n.translate(context, 'postCal.complete'),
                          style: TextStyle(
                              fontSize: 25, fontWeight: FontWeight.bold)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.resinProfileName ??
                                FlutterI18n.translate(
                                    context, 'calibration.resinProfile'),
                            style: TextStyle(
                              fontSize: 22,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    FlutterI18n.translate(
                                        context, 'postCal.previous'),
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${previousExposure.toStringAsFixed(1)}s',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade600,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Icon(
                                  Icons.arrow_forward,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 40,
                                ),
                              ),
                              Column(
                                children: [
                                  Text(
                                    FlutterI18n.translate(
                                        context, 'calibration.fineTuned'),
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${value.toStringAsFixed(2)}s',
                                    style: TextStyle(
                                      fontSize: 42,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            FlutterI18n.translate(
                                context, 'calibration.layerExposureUpdated'),
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        GlassButton(
                          tint: GlassButtonTint.positive,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(120, 65),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onComplete();
                          },
                          child: Text(
                              FlutterI18n.translate(context, 'common.done')),
                        ),
                      ],
                    ),
                  );
                },
                child: Text(FlutterI18n.translate(context, 'postCal.save')),
              ),
            ],
          );
        });
      },
    );
  }
}
