import 'package:flutter_test/flutter_test.dart';
import 'package:orion/backend_service/athena_iot/models/force_leveling_workflow.dart';
import 'package:orion/tools/athena/leveling_configs.dart';
import 'package:orion/tools/athena/leveling_workflow_engine.dart';

void main() {
  group('ForceLevelingWorkflowResponse', () {
    test('parses successful two-stage probe response', () {
      final response = ForceLevelingWorkflowResponse.fromJson({
        'result': true,
        'error': '',
        'machine_homed': true,
        'measurements': {
          'first_stage_trigger_z': 12.34,
          'first_stage_trigger_force': -1050.0,
          'first_stage_peak_force': -1120.0,
          'second_stage_trigger_z': 12.30,
          'second_stage_trigger_force': -1010.0,
          'second_stage_peak_force': -1080.0,
          'first_stage_overshoot': 120.0,
          'second_stage_overshoot': 80.0,
        },
      });

      expect(response.result, isTrue);
      expect(response.machineHomed, isTrue);
      expect(response.measurements?.firstStageTriggerZ, 12.34);
      expect(response.measurements?.secondStagePeakForce, -1080.0);
    });

    test('parses prepare response', () {
      final response = ForceLevelingWorkflowResponse.fromJson({
        'result': true,
        'error': '',
        'cleared_offset': true,
        'machine_homed': true,
      });

      expect(response.result, isTrue);
      expect(response.clearedOffset, isTrue);
      expect(response.machineHomed, isTrue);
      expect(response.measurements, isNull);
    });

    test('parses final offset response', () {
      final response = ForceLevelingWorkflowResponse.fromJson({
        'result': true,
        'error': '',
        'machine_homed': true,
        'z_offset_applied': 12.45,
        'measurements': {
          'second_stage_trigger_z': 12.30,
        },
      });

      expect(response.result, isTrue);
      expect(response.zOffsetApplied, 12.45);
      expect(response.measurements?.secondStageTriggerZ, 12.30);
    });

    test('parses failure with null measurements', () {
      final response = ForceLevelingWorkflowResponse.fromJson({
        'result': false,
        'error': 'probe failed',
        'machine_homed': true,
        'measurements': {
          'first_stage_trigger_z': null,
          'second_stage_trigger_z': null,
        },
      });

      expect(response.result, isFalse);
      expect(response.error, 'probe failed');
      expect(response.measurements?.firstStageTriggerZ, isNull);
    });

    test('maps busy and sensor unavailable HTTP failures', () {
      final busy = ForceLevelingWorkflowResponse.httpFailure(
        statusCode: 409,
        message: 'busy',
        body: {'result': false, 'error': 'workflow busy', 'busy': true},
      );
      final unavailable = ForceLevelingWorkflowResponse.httpFailure(
        statusCode: 503,
        message: 'unavailable',
      );

      expect(busy.busy, isTrue);
      expect(busy.error, 'workflow busy');
      expect(unavailable.sensorUnavailable, isTrue);
    });
  });

  group('leveling config', () {
    test('resolves Athena2 config and final endpoints', () {
      final config = getLevelingConfigForMachine('Athena2-16K');

      expect(config, isNotNull);
      final regular = config!.variants.firstWhere((v) => v.id == 'regular');
      final pro = config.variants.firstWhere((v) => v.id == 'pro');

      expect(regular.finalEndpoint, 'probe_standardarm');
      expect(pro.finalEndpoint, 'probe_offset');
      final regularSteps = regular.buildSteps();
      expect(regularSteps.map((s) => s.endpoint), contains('probe_prepare'));
      expect(regularSteps.last.endpoint, 'probe_standardarm');
    });
  });

  group('LevelingWorkflowEngine', () {
    test('progresses through successful steps and stores applied offset',
        () async {
      final calls = <String>[];
      final engine = LevelingWorkflowEngine(
        runner: (endpoint, {screenType}) async {
          calls.add(endpoint);
          return ForceLevelingWorkflowResponse.fromJson({
            'result': true,
            'error': '',
            if (endpoint == 'probe_standardarm') 'z_offset_applied': 12.45,
          });
        },
      );
      final variant = getLevelingConfigForMachine('Athena2')!
          .variants
          .firstWhere((v) => v.id == 'regular');

      engine.selectVariant(variant);
      while (!engine.isComplete) {
        await engine.runCurrentStep();
        engine.advanceAfterSuccessfulStep();
      }

      // The standard arm skips the probe_screen stage — its initial
      // leveling step uses probe_standardarm directly (skipBackend), and
      // the final offset re-probes it.
      expect(calls, [
        'probe_prepare',
        'probe_standardarm',
      ]);
      expect(engine.zOffsetApplied, 12.45);
    });

    test('keeps failed step retryable after busy response', () async {
      var attempts = 0;
      final engine = LevelingWorkflowEngine(
        runner: (_, {screenType}) async {
          attempts++;
          if (attempts == 1) {
            return ForceLevelingWorkflowResponse.httpFailure(
              statusCode: 409,
              message: 'busy',
              body: {'result': false, 'error': 'workflow busy', 'busy': true},
            );
          }
          return ForceLevelingWorkflowResponse.fromJson({
            'result': true,
            'error': '',
          });
        },
      );
      final variant = getLevelingConfigForMachine('Athena2')!
          .variants
          .firstWhere((v) => v.id == 'pro');

      engine.selectVariant(variant);
      await engine.runCurrentStep();

      expect(engine.isFailed, isTrue);
      expect(engine.errorMessage, 'levelingWorkflow.errorBusy');
      expect(engine.currentStepIndex, 0);

      await engine.runCurrentStep();
      expect(engine.status, LevelingWorkflowStatus.stepComplete);
      expect(engine.currentStepIndex, 0);
    });

    test('maps thrown connection failures to localized retry state', () async {
      final engine = LevelingWorkflowEngine(
        runner: (_, {screenType}) async => throw Exception(
          'ClientException with SocketException: The remote computer refused',
        ),
      );
      final variant = getLevelingConfigForMachine('Athena2')!
          .variants
          .firstWhere((v) => v.id == 'pro');

      engine.selectVariant(variant);
      await engine.runCurrentStep();

      expect(engine.isFailed, isTrue);
      expect(engine.errorMessage, 'levelingWorkflow.errorConnectionFailed');
      expect(engine.currentStepIndex, 0);
    });

    test('records offset from the single final recalibration', () async {
      // The Pro variant only calls probe_offset once — as the final
      // recalibration after corner leveling. The initial calibration
      // was removed because it is always redone after corners.
      int probeOffsetCalls = 0;
      final engine = LevelingWorkflowEngine(
        runner: (endpoint, {screenType}) async {
          if (endpoint == 'probe_offset') {
            probeOffsetCalls++;
            return ForceLevelingWorkflowResponse.fromJson({
              'result': true,
              'error': '',
              'z_offset_applied': 2.45,
            });
          }
          return ForceLevelingWorkflowResponse.fromJson({
            'result': true,
            'error': '',
          });
        },
      );
      final variant = getLevelingConfigForMachine('Athena2')!
          .variants
          .firstWhere((v) => v.id == 'pro');

      engine.selectVariant(variant);

      while (!engine.isComplete) {
        await engine.runCurrentStep();
        if (engine.isFailed) {
          break;
        }
        engine.advanceAfterSuccessfulStep();
      }

      // probe_offset is called exactly once (the final step).
      expect(probeOffsetCalls, 1);
      expect(engine.zOffsetApplied, 2.45);
    });
  });
}
