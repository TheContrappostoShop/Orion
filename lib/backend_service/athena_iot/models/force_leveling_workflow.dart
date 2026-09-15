/*
* Orion - Force Leveling Workflow Models
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

class ForceProbeMeasurements {
  const ForceProbeMeasurements({
    this.firstStageTriggerZ,
    this.firstStageTriggerForce,
    this.firstStagePeakForce,
    this.secondStageTriggerZ,
    this.secondStageTriggerForce,
    this.secondStagePeakForce,
    this.firstStageOvershoot,
    this.secondStageOvershoot,
    this.firstStageSpeed,
    this.secondStageSpeed,
    this.firstStageLiftHeight,
    this.secondStageLiftHeight,
    this.firstStageThreshold,
    this.secondStageThreshold,
    this.probeStartDistance,
    this.probeRetractDistance,
  });

  final double? firstStageTriggerZ;
  final double? firstStageTriggerForce;
  final double? firstStagePeakForce;
  final double? secondStageTriggerZ;
  final double? secondStageTriggerForce;
  final double? secondStagePeakForce;
  final double? firstStageOvershoot;
  final double? secondStageOvershoot;

  /// Probe configuration fields (optional — backend may not send these yet).
  final double? firstStageSpeed;
  final double? secondStageSpeed;
  final double? firstStageLiftHeight;
  final double? secondStageLiftHeight;
  final double? firstStageThreshold;
  final double? secondStageThreshold;
  final double? probeStartDistance;
  final double? probeRetractDistance;

  factory ForceProbeMeasurements.fromJson(Map<String, dynamic>? json) {
    double? toDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    final data = json ?? const <String, dynamic>{};
    return ForceProbeMeasurements(
      firstStageTriggerZ: toDouble(data['first_stage_trigger_z']),
      firstStageTriggerForce: toDouble(data['first_stage_trigger_force']),
      firstStagePeakForce: toDouble(data['first_stage_peak_force']),
      secondStageTriggerZ: toDouble(data['second_stage_trigger_z']),
      secondStageTriggerForce: toDouble(data['second_stage_trigger_force']),
      secondStagePeakForce: toDouble(data['second_stage_peak_force']),
      firstStageOvershoot: toDouble(data['first_stage_overshoot']),
      secondStageOvershoot: toDouble(data['second_stage_overshoot']),
      firstStageSpeed: toDouble(data['first_stage_speed']),
      secondStageSpeed: toDouble(data['second_stage_speed']),
      firstStageLiftHeight: toDouble(data['first_stage_lift_height']),
      secondStageLiftHeight: toDouble(data['second_stage_lift_height']),
      firstStageThreshold: toDouble(data['first_stage_threshold']),
      secondStageThreshold: toDouble(data['second_stage_threshold']),
      probeStartDistance: toDouble(data['probe_start_distance']),
      probeRetractDistance: toDouble(data['probe_retract_distance']),
    );
  }

  Map<String, dynamic> toJson() => {
        'first_stage_trigger_z': firstStageTriggerZ,
        'first_stage_trigger_force': firstStageTriggerForce,
        'first_stage_peak_force': firstStagePeakForce,
        'second_stage_trigger_z': secondStageTriggerZ,
        'second_stage_trigger_force': secondStageTriggerForce,
        'second_stage_peak_force': secondStagePeakForce,
        'first_stage_overshoot': firstStageOvershoot,
        'second_stage_overshoot': secondStageOvershoot,
        'first_stage_speed': firstStageSpeed,
        'second_stage_speed': secondStageSpeed,
        'first_stage_lift_height': firstStageLiftHeight,
        'second_stage_lift_height': secondStageLiftHeight,
        'first_stage_threshold': firstStageThreshold,
        'second_stage_threshold': secondStageThreshold,
        'probe_start_distance': probeStartDistance,
        'probe_retract_distance': probeRetractDistance,
      };
}

class ForceLevelingWorkflowResponse {
  const ForceLevelingWorkflowResponse({
    required this.result,
    required this.error,
    this.machineHomed,
    this.measurements,
    this.zOffsetApplied,
    this.clearedOffset,
    this.parkHeightMm,
    this.busy = false,
    this.sensorUnavailable = false,
    this.connectionFailed = false,
    this.statusCode,
  });

  final bool result;
  final String error;
  final bool? machineHomed;
  final ForceProbeMeasurements? measurements;
  final double? zOffsetApplied;
  final bool? clearedOffset;
  final double? parkHeightMm;
  final bool busy;
  final bool sensorUnavailable;
  final bool connectionFailed;
  final int? statusCode;

  bool get hasMeasurements => measurements != null;

  factory ForceLevelingWorkflowResponse.fromJson(
    Map<String, dynamic> json, {
    int? statusCode,
  }) {
    double? toDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    bool? toBool(dynamic value) {
      if (value == null) return null;
      if (value is bool) return value;
      if (value is num) return value != 0;
      return value.toString().toLowerCase() == 'true';
    }

    final measurementsRaw = json['measurements'];
    return ForceLevelingWorkflowResponse(
      result: toBool(json['result']) ?? false,
      error: json['error']?.toString() ?? '',
      machineHomed: toBool(json['machine_homed']),
      measurements: measurementsRaw is Map
          ? ForceProbeMeasurements.fromJson(
              Map<String, dynamic>.from(measurementsRaw),
            )
          : null,
      zOffsetApplied: toDouble(json['z_offset_applied']),
      clearedOffset: toBool(json['cleared_offset']),
      parkHeightMm: toDouble(json['park_height_mm']),
      busy: toBool(json['busy']) ?? statusCode == 409,
      sensorUnavailable: statusCode == 503,
      connectionFailed: false,
      statusCode: statusCode,
    );
  }

  factory ForceLevelingWorkflowResponse.httpFailure({
    required int statusCode,
    required String message,
    Map<String, dynamic>? body,
  }) {
    if (body != null) {
      return ForceLevelingWorkflowResponse.fromJson(body,
              statusCode: statusCode)
          .copyWith(
        error: body['error']?.toString() ?? message,
        busy: statusCode == 409 || body['busy'] == true,
        sensorUnavailable: statusCode == 503,
      );
    }
    return ForceLevelingWorkflowResponse(
      result: false,
      error: message,
      busy: statusCode == 409,
      sensorUnavailable: statusCode == 503,
      statusCode: statusCode,
    );
  }

  ForceLevelingWorkflowResponse copyWith({
    bool? result,
    String? error,
    bool? machineHomed,
    ForceProbeMeasurements? measurements,
    double? zOffsetApplied,
    bool? clearedOffset,
    double? parkHeightMm,
    bool? busy,
    bool? sensorUnavailable,
    bool? connectionFailed,
    int? statusCode,
  }) {
    return ForceLevelingWorkflowResponse(
      result: result ?? this.result,
      error: error ?? this.error,
      machineHomed: machineHomed ?? this.machineHomed,
      measurements: measurements ?? this.measurements,
      zOffsetApplied: zOffsetApplied ?? this.zOffsetApplied,
      clearedOffset: clearedOffset ?? this.clearedOffset,
      parkHeightMm: parkHeightMm ?? this.parkHeightMm,
      busy: busy ?? this.busy,
      sensorUnavailable: sensorUnavailable ?? this.sensorUnavailable,
      connectionFailed: connectionFailed ?? this.connectionFailed,
      statusCode: statusCode ?? this.statusCode,
    );
  }

  Map<String, dynamic> toJson() => {
        'result': result,
        'error': error,
        'machine_homed': machineHomed,
        'measurements': measurements?.toJson(),
        'z_offset_applied': zOffsetApplied,
        'cleared_offset': clearedOffset,
        'park_height_mm': parkHeightMm,
        'busy': busy,
        'sensor_unavailable': sensorUnavailable,
        'connection_failed': connectionFailed,
        'status_code': statusCode,
      };
}
