/*
* Orion - Calibration Screen
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
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:orion/backend_service/providers/resins_provider.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:provider/provider.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/materials/calibration_progress_overlay.dart';
import 'package:orion/materials/calibration_context_provider.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/widgets/selection_screens.dart';
import 'package:orion/widgets/zoom_value_editor_dialog.dart';
import 'package:orion/util/orion_config.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  CalibrationScreenState createState() => CalibrationScreenState();
}

class CalibrationScreenState extends State<CalibrationScreen> {
  final _log = Logger('CalibrationScreen');

  CalibrationModel? _selectedModel;
  ResinProfile? _selectedResin;
  int? _lastImageFetchRequestModelId;
  double _startingExposure = 1.0; // seconds
  double _exposureIncrement = 0.2; // seconds

  int _currentTestPiecesCount() {
    final count =
        _selectedModel?.testPiecesCount ?? _selectedModel?.models ?? 6;
    return count > 0 ? count : 6;
  }

  @override
  void initState() {
    super.initState();
    // Initialize from cache immediately; refresh in background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resinsProvider =
          Provider.of<ResinsProvider>(context, listen: false);

      // Prefer cached/provider-selected model immediately.
      final providerModel = resinsProvider.selectedCalibrationModel;
      if (mounted && _selectedModel == null && providerModel != null) {
        setState(() {
          _selectedModel = providerModel;
          _selectedResin = resinsProvider.getRecommendedResin(_selectedModel);
        });
        _lastImageFetchRequestModelId = providerModel.id;
        unawaited(resinsProvider.ensureCalibrationImage(providerModel.id));
      }

      // Refresh latest data without blocking first paint.
      unawaited(resinsProvider.refresh().then((_) {
        if (!mounted) return;
        final refreshedModel = resinsProvider.selectedCalibrationModel;
        if (_selectedModel == null && refreshedModel != null) {
          setState(() {
            _selectedModel = refreshedModel;
            _selectedResin = resinsProvider.getRecommendedResin(_selectedModel);
          });
          _lastImageFetchRequestModelId = refreshedModel.id;
          unawaited(resinsProvider.ensureCalibrationImage(refreshedModel.id));
        }
      }));
    });
  }

  void _resetValues(ResinsProvider provider) {
    setState(() {
      _selectedModel = provider.selectedCalibrationModel;
      _selectedResin = null;
      _startingExposure = 1.0;
      _exposureIncrement = 0.2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resinsProvider = Provider.of<ResinsProvider>(context);
    // Use provider's user-visible resin list so locked/vendor profiles
    // (e.g. NanoDLP AFP templates) are hidden from calibration flows.
    final resins = resinsProvider.userResins;
    final hasResins = resins.isNotEmpty;
    final hasModels = resinsProvider.calibrationModels.isNotEmpty;
    final isResinsLoading = resinsProvider.isLoading && !hasResins;
    final isModelsLoading = resinsProvider.isLoading && !hasModels;

    // If the selected model has no cached image, force-fetch it immediately.
    final selectedId = _selectedModel?.id;
    if (selectedId != null) {
      final selectedImage = resinsProvider.calibrationImageUrl(selectedId);
      final shouldRequest = (selectedImage == null || selectedImage.isEmpty) &&
          _lastImageFetchRequestModelId != selectedId;
      if (shouldRequest) {
        _lastImageFetchRequestModelId = selectedId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(resinsProvider.ensureCalibrationImage(selectedId));
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.only(
          left: OrionSpacing.screenHorizontal - 4.0,
          right: OrionSpacing.screenHorizontal - 4.0,
          top: OrionSpacing.settingsScreenPaddingTightTop.top,
          bottom: OrionSpacing.screenBottomNavClearance,
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left side: Parameter cards
                  Expanded(
                    flex: 9,
                    child: Column(
                      children: [
                        // Resin Profile
                        Expanded(
                          child: _buildCompactCard(
                            title: FlutterI18n.translate(
                                context, 'calibration.resinProfile'),
                            value: isResinsLoading
                                ? 'Loading...'
                                : (_selectedResin?.name ??
                                    FlutterI18n.translate(
                                        context, 'calibration.selectResin')),
                            onTap: isResinsLoading
                                ? () {}
                                : () => _selectResinProfile(resins),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Starting Exposure
                        Expanded(
                          child: _buildCompactCard(
                            title: FlutterI18n.translate(
                                context, 'calibration.startingExposure'),
                            value: '${_startingExposure.toStringAsFixed(2)} s',
                            onTap: () => _editValue(
                              title: FlutterI18n.translate(
                                  context, 'calibration.startingExposure'),
                              description: FlutterI18n.translate(
                                  context, 'calibration.exposureDesc'),
                              currentValue: _startingExposure,
                              min: 0.5,
                              max: 10,
                              suffix: ' sec',
                              decimals: 1,
                              step: 0.1,
                              onSave: (v) =>
                                  setState(() => _startingExposure = v),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Exposure Increment
                        Expanded(
                          child: _buildCompactCard(
                            title: FlutterI18n.translate(
                                context, 'calibration.exposureIncrement'),
                            value: '${_exposureIncrement.toStringAsFixed(2)} s',
                            onTap: () => _editValue(
                              title: FlutterI18n.translate(
                                  context, 'calibration.exposureIncrement'),
                              description: FlutterI18n.translate(
                                  context, 'calibration.incrementDesc'),
                              currentValue: _exposureIncrement,
                              min: 0.1,
                              max: 2,
                              suffix: ' s',
                              decimals: 2,
                              step: 0.1,
                              onSave: (v) =>
                                  setState(() => _exposureIncrement = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right side: Model selector with large thumbnail
                  Expanded(
                    flex: 11,
                    child: _buildLargeModelSelectorCard(
                      model: _selectedModel,
                      isLoading: isModelsLoading,
                      imageUrl: _selectedModel != null
                          ? resinsProvider
                              .calibrationImageUrl(_selectedModel!.id)
                          : null,
                      onTap: isModelsLoading
                          ? () {}
                          : () => _selectCalibrationModel(
                              resinsProvider.calibrationModels),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Bottom Buttons: Reset | Start
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 9,
                    child: GlassButton(
                      tint: GlassButtonTint.negative,
                      onPressed: () => _resetValues(resinsProvider),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 65),
                      ),
                      child: Text(
                          FlutterI18n.translate(context, 'calibration.reset'),
                          style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 11,
                    child: GlassButton(
                      tint: GlassButtonTint.positive,
                      onPressed:
                          _selectedResin == null ? null : _startCalibration,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 65),
                      ),
                      child: Text(
                          FlutterI18n.translate(context, 'calibration.start'),
                          style: TextStyle(fontSize: 22)),
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

  Widget _buildCompactCard({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      outlined: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Spacer(),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 19,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pollSlicerProgress(
    ValueNotifier<double> progressNotifier,
    ValueNotifier<String> messageNotifier,
  ) async {
    messageNotifier.value =
        FlutterI18n.translate(context, 'calibration.slicing');

    final startTime = DateTime.now();
    const timeout = Duration(minutes: 10); // 10 minute timeout for slicing

    // Poll every 1 second
    while (mounted) {
      // Get slicer progress for UI display
      final progress = await BackendService().getSlicerProgress();
      if (!mounted) return;

      if (progress != null) {
        // Treat 93% as complete (show as 100% on progress bar)
        if (progress >= 0.93) {
          progressNotifier.value = 1.0;
        } else {
          // Scale 0-93% to 0-100% for display
          progressNotifier.value = progress / 0.93;
        }
      }

      // Calibration prints don't report percentage correctly in /slicer endpoint
      // so we check plates.json directly for plate 0's Processed flag
      final isProcessed = await BackendService().isCalibrationPlateProcessed();
      if (!mounted) return;

      // Break at 93% or when processed flag is set (print starts at 99%)
      if (isProcessed == true || (progress != null && progress >= 0.93)) {
        messageNotifier.value =
            FlutterI18n.translate(context, 'calibration.slicingComplete');
        progressNotifier.value = 1.0;
        _log.info('Calibration preparation complete');
        break;
      }

      // Check timeout
      if (DateTime.now().difference(startTime) > timeout) {
        _log.warning(
            'Slicer progress polling timed out after ${timeout.inMinutes} minutes');
        throw Exception('Slicing operation timed out');
      }

      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Widget _buildLargeModelSelectorCard({
    required CalibrationModel? model,
    required VoidCallback onTap,
    required bool isLoading,
    String? imageUrl,
  }) {
    return GlassCard(
      outlined: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isLoading) ...[
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            FlutterI18n.translate(
                                context, 'calibration.loadingModels'),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else if (model != null) ...[
                // Large preview image
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Icon(Icons.image,
                                      size: 64, color: Colors.grey),
                                ),
                              );
                            },
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science,
                              size: 64, color: Colors.grey.shade600),
                          const SizedBox(height: 12),
                          Text(
                            FlutterI18n.translate(
                                context, 'calibration.noModel'),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (model != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        model.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: Colors.grey.shade400, size: 28),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editValue({
    required String title,
    String? description,
    required double currentValue,
    required double min,
    required double max,
    required String suffix,
    required int decimals,
    double? step,
    required ValueChanged<double> onSave,
  }) async {
    final result = await ZoomValueEditorDialog.show(
      context,
      title: title,
      description: description,
      currentValue: currentValue,
      min: min,
      max: max,
      suffix: suffix,
      decimals: decimals,
      step: step,
    );
    if (result != null) onSave(result);
  }

  Future<void> _selectCalibrationModel(List<CalibrationModel> models) async {
    if (models.isEmpty) {
      return;
    }

    final selected = await Navigator.of(context).push<CalibrationModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _CalibrationModelPickerScreen(
          models: models,
          selectedModel: _selectedModel,
        ),
      ),
    );

    if (selected == null || !mounted) return;
    final resinsProvider = Provider.of<ResinsProvider>(context, listen: false);
    setState(() {
      _selectedModel = selected;
    });
    resinsProvider.setSelectedCalibrationModelId(selected.id);
    _lastImageFetchRequestModelId = selected.id;
    unawaited(resinsProvider.ensureCalibrationImage(selected.id));
  }

  Future<void> _selectResinProfile(List<ResinProfile> resins) async {
    if (resins.isEmpty) {
      return;
    }

    final selected = await Navigator.of(context).push<ResinProfile>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _ResinProfilePickerScreen(
          title: FlutterI18n.translate(context, 'calibration.selectResin'),
          resins: resins,
          selectedResin: _selectedResin,
        ),
      ),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _selectedResin = selected;
    });
  }

  void _startCalibration() async {
    _log.info(
        'Starting calibration: model=${_selectedModel?.name} (id=${_selectedModel?.id}), resin=${_selectedResin?.name}, start=$_startingExposure, increment=$_exposureIncrement');

    final testPiecesCount = _currentTestPiecesCount();

    // Build a human-readable sequence of exposures for the selected model's piece count
    // Show unified pre-calibration overlay with info and checklist
    final confirmed = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        pageBuilder: (context, _, __) => _PreCalibrationOverlay(
          calibrationModelName: _selectedModel!.name,
          resinProfileName: _selectedResin?.name,
          startingExposure: _startingExposure,
          exposureIncrement: _exposureIncrement,
          calibrationModelId: _selectedModel!.id,
          testPiecesCount: testPiecesCount,
        ),
      ),
    );

    if (confirmed == true) {
      _log.info('Checklist confirmed, starting calibration...');

      // Show progress overlay
      final progressNotifier = ValueNotifier<double>(0.0);
      final messageNotifier = ValueNotifier<String>('');
      final showReadyNotifier = ValueNotifier<bool>(false);

      if (!mounted) return;

      // Reset overlay state for new calibration
      CalibrationProgressOverlay.reset();

      // Show overlay as a route
      Navigator.of(context).push(
        PageRouteBuilder(
          settings: const RouteSettings(name: 'calibration_progress_overlay'),
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          pageBuilder: (context, _, __) => CalibrationProgressOverlay(
            progress: progressNotifier,
            message: messageNotifier,
            showReady: showReadyNotifier,
          ),
        ),
      );

      // Calculate exposure times
      final exposureTimes = List.generate(
        testPiecesCount,
        (i) => _startingExposure + (_exposureIncrement * i),
      );

      try {
        // Prefer the provider helper for consistent resolution logic.
        final resolvedProfileId =
            ResinsProvider.resolveProfileIdFromMeta(_selectedResin?.meta) ?? 0;

        // Store calibration context for post-print evaluation
        if (mounted) {
          context.read<CalibrationContextProvider>().setContext(
                CalibrationContext(
                  calibrationModelName: _selectedModel!.name,
                  resinProfileName: _selectedResin?.name,
                  startExposure: _startingExposure,
                  exposureIncrement: _exposureIncrement,
                  profileId: resolvedProfileId,
                  calibrationModelId: _selectedModel!.id,
                  evaluationGuideUrl: _selectedModel!.evaluationGuideUrl,
                ),
              );
        }

        // Show progress
        messageNotifier.value =
            FlutterI18n.translate(context, 'calibration.submittingJob');
        progressNotifier.value = 0.1;

        final reuseCalibrationPlate = OrionConfig()
            .getFlag('reuseCalibrationPlate', category: 'developer');
        if (reuseCalibrationPlate) {
          _log.info(
              'Developer mode: reusing existing calibration plate, skipping slicer');
          messageNotifier.value =
              'Starting existing calibration plate (debug)...';
          progressNotifier.value = 0.6;
          await BackendService().startPrint('Local', '0');
          showReadyNotifier.value = true;
          _log.info('Calibration print started (reuse mode)');
          return;
        }

        // Submit calibration job to backend
        final success = await BackendService().startCalibrationPrint(
          calibrationModelId: _selectedModel!.id,
          exposureTimes: exposureTimes,
          profileId: resolvedProfileId,
        );

        if (!success) {
          _log.warning('Calibration submission did not receive acknowledgment, '
              'but job may have started. Proceeding with progress polling...');
        }

        // Poll slicer progress regardless of ack
        // (the job may have started even if we timed out waiting for response)
        await _pollSlicerProgress(progressNotifier, messageNotifier);

        _log.info('Calibration preparation complete');

        // Show ready state with green flask
        showReadyNotifier.value = true;

        // StatusScreen will automatically open when print starts
        // and will dismiss overlay + pop CalibrationScreen
        _log.info('Waiting for StatusScreen to open...');
      } catch (e) {
        _log.severe('Error starting calibration: $e');
        messageNotifier.value = 'Error: $e';
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }
}

class _CalibrationModelPickerScreen extends StatelessWidget {
  final List<CalibrationModel> models;
  final CalibrationModel? selectedModel;

  const _CalibrationModelPickerScreen({
    required this.models,
    required this.selectedModel,
  });

  Widget _buildModelTile({
    required BuildContext context,
    required CalibrationModel model,
    required bool isSelected,
    required String? imageUrl,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return GlassCard(
      elevation: isSelected ? 2.0 : 1.0,
      outlined: false,
      color: isSelected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.3)
          : null,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(model),
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.black.withValues(alpha: 0.12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey.shade800,
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 36,
                                    color: Colors.grey,
                                  ),
                                );
                              },
                            )
                          : Container(
                              color: Colors.grey.shade800,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.name,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? primary : null,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.view_module_outlined,
                                          size: 12,
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.color,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${model.models} ${model.models == 1 ? 'piece' : 'pieces'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (model.resinRequired != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? primary.withValues(alpha: 0.2)
                                            : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.35),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.water_drop_outlined,
                                            size: 12,
                                            color: isSelected
                                                ? primary
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.color,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${model.resinRequired} ml',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? primary
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resinsProvider = Provider.of<ResinsProvider>(context, listen: false);

    return DetailedSelectionScreen(
      title: FlutterI18n.translate(context, 'calibration.selectModel'),
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 10.0;
          final columns = constraints.maxWidth < 560 ? 1 : 2;
          const sizingRows = 2;
          final tileWidth =
              (constraints.maxWidth - ((columns - 1) * spacing)) / columns;
          final tileHeight =
              (constraints.maxHeight - ((sizingRows - 1) * spacing)) /
                  sizingRows;
          final lockedAspectRatio = tileWidth / tileHeight;
          final fitWithoutScroll = models.length <= 4;

          final delegate = SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: lockedAspectRatio,
          );

          return GridView.builder(
            physics: fitWithoutScroll
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            itemCount: models.length,
            gridDelegate: delegate,
            itemBuilder: (context, index) {
              final model = models[index];
              final isSelected = selectedModel?.id == model.id;
              final imageUrl = resinsProvider.calibrationImageUrl(model.id);

              return _buildModelTile(
                context: context,
                model: model,
                isSelected: isSelected,
                imageUrl: imageUrl,
              );
            },
          );
        },
      ),
    );
  }
}

class _ResinProfilePickerScreen extends StatelessWidget {
  final String title;
  final List<ResinProfile> resins;
  final ResinProfile? selectedResin;

  const _ResinProfilePickerScreen({
    required this.title,
    required this.resins,
    required this.selectedResin,
  });

  @override
  Widget build(BuildContext context) {
    return ResinProfileSelectionScreen(
      title: title,
      resins: resins,
      selectedResinKey: selectedResin?.path ?? selectedResin?.name,
      onSelected: (resin) {
        Navigator.of(context).pop(resin);
      },
    );
  }
}

/// Compact pre-calibration overlay
/// Shows info and checklist in single screen
class _PreCalibrationOverlay extends StatelessWidget {
  final String calibrationModelName;
  final String? resinProfileName;
  final double startingExposure;
  final double exposureIncrement;
  final int calibrationModelId;
  final int testPiecesCount;

  const _PreCalibrationOverlay({
    required this.calibrationModelName,
    this.resinProfileName,
    required this.startingExposure,
    required this.exposureIncrement,
    required this.calibrationModelId,
    required this.testPiecesCount,
  });

  @override
  Widget build(BuildContext context) {
    final isGlass =
        Provider.of<ThemeProvider>(context, listen: false).isGlassTheme;
    final primary = Theme.of(context).colorScheme.primary;

    return GlassApp(
      child: Scaffold(
        backgroundColor: isGlass
            ? Colors.transparent
            : Theme.of(context).colorScheme.surface,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(PhosphorIconsFill.flask, size: 24, color: primary),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      calibrationModelName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (resinProfileName != null) ...[
                const SizedBox(height: 6),
                Text(
                  resinProfileName!,
                  style: TextStyle(
                    fontSize: 16,
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

              const SizedBox(height: 20),

              // ── Body ─────────────────────────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left – What's happening
                    Expanded(
                      child: GlassCard(
                        outlined: true,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Text(
                                FlutterI18n.translate(
                                        context, 'calibration.whatWillHappen')
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.55),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '$testPiecesCount ${FlutterI18n.translate(context, 'calibration.testPiecesExplanation')}',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.75),
                                  height: 1.55,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildStatRow(
                                context,
                                icon: Icon(PhosphorIcons.timer()),
                                label: FlutterI18n.translate(
                                    context, 'calibration.startingExposure'),
                                value:
                                    '${startingExposure.toStringAsFixed(1)} s',
                                primary: primary,
                              ),
                              const SizedBox(height: 10),
                              _buildStatRow(
                                context,
                                icon: Icon(PhosphorIcons.arrowRight()),
                                label: FlutterI18n.translate(
                                    context, 'calibration.stepBetween'),
                                value:
                                    '+${exposureIncrement.toStringAsFixed(1)} s',
                                primary: primary,
                              ),
                              const SizedBox(height: 10),
                              _buildStatRow(
                                context,
                                icon: Icon(PhosphorIcons.arrowLineRight()),
                                label: FlutterI18n.translate(
                                    context, 'calibration.finalExposure'),
                                value:
                                    '${(startingExposure + exposureIncrement * (testPiecesCount - 1)).toStringAsFixed(1)} s',
                                primary: primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Right – Pre-flight checklist
                    Expanded(
                      child: GlassCard(
                        outlined: true,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Text(
                                FlutterI18n.translate(
                                        context, 'calibration.preFlightCheck')
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.55),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildChecklistItem(
                                        context,
                                        FlutterI18n.translate(
                                            context, 'calibration.checkResin')),
                                    _buildChecklistItem(
                                        context,
                                        FlutterI18n.translate(
                                            context, 'calibration.checkPlate')),
                                    _buildChecklistItem(
                                        context,
                                        FlutterI18n.translate(
                                            context, 'calibration.checkVat')),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Action buttons ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      tint: GlassButtonTint.negative,
                      onPressed: () => Navigator.of(context).pop(false),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 65),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIcons.x(), size: 20),
                          const SizedBox(width: 10),
                          Text(FlutterI18n.translate(context, 'common.cancel'),
                              style: TextStyle(fontSize: 20)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GlassButton(
                      tint: GlassButtonTint.positive,
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 65),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              FlutterI18n.translate(
                                  context, 'calibration.startPrint'),
                              style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Icon(PhosphorIcons.play(), size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context, {
    required Widget icon,
    required String label,
    required String value,
    required Color primary,
  }) {
    return Row(
      children: [
        IconTheme(
          data: IconThemeData(
            size: 18,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          child: icon,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistItem(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsFill.checkCircle,
            size: 20,
            color: Colors.green.shade400,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.85),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
