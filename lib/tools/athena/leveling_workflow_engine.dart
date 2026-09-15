/*
* Orion - Leveling Workflow Engine
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

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:orion/backend_service/athena_iot/models/force_leveling_workflow.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/tools/athena/leveling_configs.dart';

typedef ForceLevelingRunner = Future<ForceLevelingWorkflowResponse> Function(
  String endpoint, {
  String? screenType,
});

enum LevelingWorkflowStatus {
  idle,
  running,
  stepComplete,
  failed,
  complete,
}

class LevelingWorkflowEngine extends ChangeNotifier {
  LevelingWorkflowEngine({
    ForceLevelingRunner? runner,
  }) : _runner = runner ??
            ((endpoint, {screenType}) =>
                BackendService().runForceLevelingWorkflow(
                  endpoint,
                  screenType: screenType,
                  requestTimeout: const Duration(seconds: 90),
                ));

  final ForceLevelingRunner _runner;
  final _log = Logger('LevelingWorkflowEngine');

  /// Selected screen type (tempered glass vs. wave release film).  Passed
  /// to the `probe_standardarm` / `probe_offset` endpoints as `screentype`.
  LevelingScreenType? _screenType;

  void setScreenType(LevelingScreenType? screenType) {
    _screenType = screenType;
  }

  LevelingVariant? _variant;
  List<LevelingWorkflowStep> _steps = const [];
  int _currentStepIndex = 0;
  LevelingWorkflowStatus _status = LevelingWorkflowStatus.idle;
  ForceLevelingWorkflowResponse? _lastResponse;
  String? _errorMessage;
  double? _zOffsetApplied;

  LevelingVariant? get variant => _variant;
  List<LevelingWorkflowStep> get steps => _steps;
  int get currentStepIndex => _currentStepIndex;
  LevelingWorkflowStatus get status => _status;
  ForceLevelingWorkflowResponse? get lastResponse => _lastResponse;
  String? get errorMessage => _errorMessage;
  double? get zOffsetApplied => _zOffsetApplied;

  bool get hasVariant => _variant != null;
  bool get isRunning => _status == LevelingWorkflowStatus.running;
  bool get isComplete => _status == LevelingWorkflowStatus.complete;
  bool get isFailed => _status == LevelingWorkflowStatus.failed;
  bool get canGoBack => _currentStepIndex > 0 && !isRunning;
  bool get canRunCurrentStep =>
      hasVariant &&
      !isRunning &&
      _currentStepIndex >= 0 &&
      _currentStepIndex < _steps.length;

  LevelingWorkflowStep? get currentStep {
    if (_currentStepIndex < 0 || _currentStepIndex >= _steps.length) {
      return null;
    }
    return _steps[_currentStepIndex];
  }

  void selectVariant(LevelingVariant variant) {
    _variant = variant;
    _steps = variant.buildSteps();
    _currentStepIndex = 0;
    _status = LevelingWorkflowStatus.idle;
    _lastResponse = null;
    _errorMessage = null;
    _zOffsetApplied = null;
    // A fresh session re-selects the screen type; the caller sets it again
    // (wizard) or reuses the persisted value (recheck).
    _screenType = null;
    _log.info(
      'Selected leveling variant: id=${variant.id} '
      'finalEndpoint=${variant.finalEndpoint} steps=${_steps.map((s) => s.endpoint).join(",")}',
    );
    notifyListeners();
  }

  void previousStep() {
    if (!canGoBack) return;
    _currentStepIndex -= 1;
    _status = LevelingWorkflowStatus.idle;
    _errorMessage = null;
    _lastResponse = null;
    notifyListeners();
  }

  /// Reset the current step back to idle so it can be re-run.
  /// Used for multi-cycle steps like corner probing.
  void resetToIdle() {
    if (isRunning) return;
    _status = LevelingWorkflowStatus.idle;
    _errorMessage = null;
    _lastResponse = null;
    notifyListeners();
  }

  void advanceAfterSuccessfulStep() {
    if (isRunning || _status != LevelingWorkflowStatus.stepComplete) return;
    if (_currentStepIndex >= _steps.length - 1) {
      _status = LevelingWorkflowStatus.complete;
    } else {
      _currentStepIndex += 1;
      _status = LevelingWorkflowStatus.idle;
      _errorMessage = null;
      _lastResponse = null;
    }
    notifyListeners();
  }

  /// Jump to a specific step index (e.g. to re-run a phase).
  void jumpToStep(int index) {
    if (isRunning) return;
    if (index < 0 || index >= _steps.length) return;
    _currentStepIndex = index;
    _status = LevelingWorkflowStatus.idle;
    _errorMessage = null;
    _lastResponse = null;
    notifyListeners();
  }

  /// Jump to the first step whose [id] starts with [prefix].
  /// Does nothing if no matching step is found.
  void jumpToFirstStepId(String prefix) {
    if (isRunning) return;
    final idx = _steps.indexWhere((s) => s.id.startsWith(prefix));
    if (idx < 0) return;
    _currentStepIndex = idx;
    _status = LevelingWorkflowStatus.idle;
    _errorMessage = null;
    _lastResponse = null;
    notifyListeners();
  }

  Future<void> runCurrentStep() async {
    final step = currentStep;
    if (step == null || isRunning) return;

    _log.info(
      'Running leveling step ${_currentStepIndex + 1}/${_steps.length}: '
      'id=${step.id} endpoint=${step.endpoint} kind=${step.kind.name}',
    );
    _status = LevelingWorkflowStatus.running;
    _errorMessage = null;
    notifyListeners();

    // Skip backend call for informational/intermediate-only steps
    if (step.skipBackend) {
      _status = LevelingWorkflowStatus.stepComplete;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    late final ForceLevelingWorkflowResponse response;
    try {
      response =
          await _runner(step.endpoint, screenType: _screenType?.screentypeParam);
    } catch (e) {
      _log.warning(
        'Leveling step threw before returning response: endpoint=${step.endpoint}',
        e,
      );
      response = ForceLevelingWorkflowResponse(
        result: false,
        error: e.toString(),
        connectionFailed: true,
      );
    }
    _lastResponse = response;

    if (response.result) {
      if (response.zOffsetApplied != null) {
        // Only update the stored offset when the backend reports a
        // meaningful correction.  A second call (e.g. final recalibration
        // after corner leveling on the Pro variant) often returns 0.0
        // because the offset was already applied on the first pass —
        // blindly overwriting would lose the real offset.  A genuine
        // recalibration that returns a non-zero value will still update.
        final value = response.zOffsetApplied!;
        if (value > 0.001 || _zOffsetApplied == null) {
          _zOffsetApplied = value;
        }
      }
      _status = LevelingWorkflowStatus.stepComplete;
      _errorMessage = null;
      _log.info(
        'Leveling step complete: endpoint=${step.endpoint} '
        'homed=${response.machineHomed} offset=${response.zOffsetApplied} '
        'measurements=${response.measurements?.toJson()}',
      );
    } else {
      _status = LevelingWorkflowStatus.failed;
      _errorMessage = _messageForFailure(response);
      _log.warning(
        'Leveling step failed: endpoint=${step.endpoint} '
        'busy=${response.busy} sensorUnavailable=${response.sensorUnavailable} '
        'connectionFailed=${response.connectionFailed} status=${response.statusCode} '
        'uiMessage=$_errorMessage rawError="${response.error}"',
      );
    }

    notifyListeners();
  }

  String _messageForFailure(ForceLevelingWorkflowResponse response) {
    if (response.connectionFailed) {
      return 'levelingWorkflow.errorConnectionFailed';
    }
    if (response.busy) return 'levelingWorkflow.errorBusy';
    if (response.sensorUnavailable) {
      return 'levelingWorkflow.errorSensorUnavailable';
    }
    if (response.error.trim().isNotEmpty) return response.error;
    return 'levelingWorkflow.errorGeneric';
  }

  /// Force-complete the current step with fabricated success data.
  /// Used for dev testing with simulated backends.
  void forceCompleteStep({ForceProbeMeasurements? measurements}) {
    if (isRunning) return;
    final step = currentStep;
    if (step == null) return;

    final fabZOffset = step.kind.name == 'finalOffset' ? 0.5 : null;
    _lastResponse = ForceLevelingWorkflowResponse(
      result: true,
      error: '',
      machineHomed: true,
      measurements: measurements ??
          ForceProbeMeasurements(
            firstStageTriggerZ: 10.0,
            firstStageTriggerForce: -15.0,
            firstStagePeakForce: -18.0,
            secondStageTriggerZ: 5.0,
            secondStageTriggerForce: -20.0,
            secondStagePeakForce: -22.0,
          ),
      zOffsetApplied: fabZOffset,
      parkHeightMm: 150.0,
    );
    // Apply the fabricated offset the same way runCurrentStep does so the
    // completion screen actually displays it.
    if (fabZOffset != null && (fabZOffset > 0.001 || _zOffsetApplied == null)) {
      _zOffsetApplied = fabZOffset;
    }
    _log.info('Force-completing step: id=${step.id} endpoint=${step.endpoint}');
    _status = LevelingWorkflowStatus.stepComplete;
    notifyListeners();
  }
}
