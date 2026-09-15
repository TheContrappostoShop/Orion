/*
* Orion - Edit Resin Screen
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
import 'package:orion/backend_service/providers/resins_provider.dart';
import 'package:orion/backend_service/backend_service.dart';
import 'package:orion/backend_service/domain/models.dart';
import 'package:orion/backend_service/nanodlp/models/nano_profiles.dart';
import 'package:orion/util/orion_kb/orion_keyboard_expander.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/error_handling/error_dialog.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/widgets/system_status_widget.dart';
import 'package:orion/widgets/orion_app_bar.dart';
import 'package:orion/widgets/zoom_value_editor_dialog.dart';

/// Edit screen showing 6 cards (2x3 grid) displaying current resin parameter
/// values. Tapping any card opens a dialog with a slider to adjust the value.
class EditResinScreen extends StatefulWidget {
  final ResinProfile? resin;

  /// Invoked after the backend write succeeds, before this screen returns.
  /// Owners pass a refresh here so a cloned profile is in the list as soon as
  /// the user gets back to it.
  final Future<void> Function()? onSaved;

  const EditResinScreen({super.key, this.resin, this.onSaved});

  @override
  EditResinScreenState createState() => EditResinScreenState();
}

class EditResinScreenState extends State<EditResinScreen> {
  final _log = Logger('EditResinScreen');

  late double _burnInTime; // seconds
  late double _normalTime; // seconds
  late double _liftAfter; // mm
  late int _burnInCount; // count
  late double _waitAfterCure; // seconds
  late double _waitAfterLife; // seconds

  late Map<String, dynamic> _initial;
  bool _saving = false;

  ResinSettings _settingsFromMeta(Map<String, dynamic> meta) {
    // Single source of truth for NanoDLP key mapping lives in the model so
    // the pre-fetch placeholder and the fetched values can never disagree.
    return ResinSettings.fromNormalizedMap(NanoProfile.normalizeForEdit(meta));
  }

  void _applySettings(ResinSettings settings, {bool setInitial = false}) {
    _burnInTime = settings.burnInCureTime;
    _normalTime = settings.normalCureTime;
    _liftAfter = settings.liftAfterPrint;
    _burnInCount = settings.burnInCount;
    _waitAfterCure = settings.waitAfterCure;
    _waitAfterLife = settings.waitAfterLife;

    if (setInitial) {
      _initial = settings.toNormalizedMap();
    }
  }

  @override
  void initState() {
    super.initState();
    // Initialize from any metadata available on the provided resin immediately
    // so the UI can render quickly. After that, attempt to fetch the full
    // profile JSON from the backend (when supported) and, if available,
    // overwrite the in-memory fields with the authoritative values.
    final meta = widget.resin?.meta ?? {};
    final fallbackSettings = _settingsFromMeta(meta);
    _applySettings(fallbackSettings, setInitial: true);

    // Fetch and normalize detailed profile data (model handles backend
    // specifics). This keeps the UI simple and backend-agnostic.
    Future(() async {
      try {
        int? profileId;
        try {
          profileId = ResinsProvider.resolveProfileIdFromMeta(meta);
        } catch (_) {
          profileId = null;
        }
        if (profileId == null || profileId == 0) return;

        final svc = BackendService();
        final settings = await svc.getResinSettings(profileId);
        if (settings == null) return;

        if (!mounted) return;
        setState(() {
          _applySettings(settings, setInitial: true);
        });
      } catch (e, st) {
        _log.fine('Failed to fetch or apply profile details', e, st);
      }
    });
  }

  void _reset() {
    setState(() {
      _burnInTime = (_initial['burn_in_cure_time'] as num).toDouble();
      _normalTime = (_initial['normal_cure_time'] as num).toDouble();
      _liftAfter = _initial['lift_after_print'] as double;
      _burnInCount = _initial['burn_in_count'] as int;
      _waitAfterCure = (_initial['wait_after_cure'] as num).toDouble();
      _waitAfterLife = (_initial['wait_after_life'] as num).toDouble();
    });
  }

  void _save() async {
    // Locked (manufacturer) profiles are never overwritten in place: saving
    // them always produces a renamed clone. Ask for the clone name first so
    // the user explicitly acknowledges the copy.
    String? cloneName;
    if (widget.resin?.locked == true) {
      cloneName = await _promptCloneName();
      // Empty/cancelled: stay on the edit screen, nothing is saved.
      if (cloneName == null || cloneName.isEmpty) return;
    }

    final result = {
      'burn_in_cure_time': _burnInTime,
      'normal_cure_time': _normalTime,
      'lift_after_print': _liftAfter,
      'burn_in_count': _burnInCount,
      'wait_after_cure': _waitAfterCure,
      'wait_after_life': _waitAfterLife,
      if (cloneName != null) 'title': cloneName,
    };

    _log.info('Saving profile edits: $result');
    // Try to post back to backend when we can identify a profile id in the
    // provided resin meta. Otherwise just return the result to the caller.
    int? profileId;
    try {
      final meta = widget.resin?.meta ?? {};
      profileId = ResinsProvider.resolveProfileIdFromMeta(meta);
    } catch (_) {
      profileId = null;
    }

    if (profileId == null || profileId == 0) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final svc = BackendService();
      final settings = ResinSettings(
        burnInCureTime: _burnInTime,
        normalCureTime: _normalTime,
        liftAfterPrint: _liftAfter,
        burnInCount: _burnInCount,
        waitAfterCure: _waitAfterCure,
        waitAfterLife: _waitAfterLife,
      );
      if (cloneName != null) {
        // Cloned save: create a new profile from the locked source, storing
        // the edited values under the name the user chose.
        final fields =
            NanoProfile.denormalizeForBackend(settings.toNormalizedMap());
        fields['Title'] = cloneName;
        await svc.cloneProfile(profileId, fields);
      } else {
        await svc.saveResinSettings(profileId, settings);
      }

      // The write landed; let the owner re-read profiles now so the list is
      // already up to date when the user returns to it (a clone adds an
      // entry the pre-save list cannot contain).
      await widget.onSaved?.call();

      if (mounted) {
        setState(() {
          _saving = false;
        });
      }

      // Show success dialog with old→new comparison for normal cure time
      double parseNum(dynamic v) {
        if (v == null) return 0.0;
        if (v is num) return v.toDouble();
        final pd = double.tryParse('$v');
        return pd ?? 0.0;
      }

      final oldNormalTime = parseNum(_initial['normal_cure_time']);
      final newNormalTime = parseNum(result['normal_cure_time']);
      final hasChanged = oldNormalTime != newNormalTime;

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => GlassAlertDialog(
            title: Text(
                FlutterI18n.translate(context, 'editResin.profileSaved'),
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cloneName ?? widget.resin?.name ?? 'Resin Profile',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasChanged) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Text(
                            FlutterI18n.translate(
                                context, 'editResin.previous'),
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${oldNormalTime.toStringAsFixed(2)}s',
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
                            FlutterI18n.translate(context, 'editResin.updated'),
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${newNormalTime.toStringAsFixed(2)}s',
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
                ],
                Text(
                  hasChanged
                      ? FlutterI18n.translate(
                          context, 'postCal.layerExposureUpdated')
                      : FlutterI18n.translate(
                          context, 'editResin.savedSuccess'),
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
                },
                child: Text(FlutterI18n.translate(context, 'editResin.done')),
              ),
            ],
          ),
        );
      }

      // Return the submitted result (or backend response) to the caller so
      // callers can update UI immediately.
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e, st) {
      _log.severe('Failed to post profile edits', e, st);
      if (mounted) showErrorDialog(context, 'PROFILE-EDIT-FAILED');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  /// Ask the user to name the clone produced from a locked (manufacturer)
  /// profile. Returns the chosen name, or null when the dialog is
  /// cancelled or left empty.
  Future<String?> _promptCloneName() {
    final nameKey = GlobalKey<SpawnOrionTextFieldState>();
    final defaultName = '${widget.resin?.name ?? 'Resin Profile'} copy';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => GlassAlertDialog(
        title: Text(FlutterI18n.translate(context, 'editResin.cloneNameTitle')),
        content: SizedBox(
          width: MediaQuery.of(dialogContext).size.width * 0.5,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SpawnOrionTextField(
                  key: nameKey,
                  keyboardHint:
                      FlutterI18n.translate(context, 'editResin.cloneNameHint'),
                  locale: Localizations.localeOf(dialogContext).toString(),
                  presetText: defaultName,
                ),
                OrionKbExpander(textFieldKey: nameKey),
              ],
            ),
          ),
        ),
        actions: [
          GlassButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 60),
            ),
            child: Text(FlutterI18n.translate(context, 'common.cancel'),
                style: const TextStyle(fontSize: 20)),
          ),
          GlassButton(
            tint: GlassButtonTint.positive,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 60),
            ),
            onPressed: () {
              final name = nameKey.currentState?.getCurrentText().trim() ?? '';
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(name);
            },
            child: Text(FlutterI18n.translate(context, 'common.save'),
                style: const TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
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
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade400,
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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

  @override
  Widget build(BuildContext context) {
    final title = widget.resin?.name ?? 'Edit Resin';

    return GlassApp(
      child: Scaffold(
        appBar: OrionAppBar(
          title: Text(title),
          actions: const [SystemStatusWidget()],
          toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight,
        ),
        body: Padding(
          // The settings inset compensates GlassCard's default 4px margin, so
          // the two together land on the app baseline of 20 - the same edge the
          // rest of Orion uses. The tight top offset is the one for a screen
          // sitting directly under OrionAppBar; the bottom stays at 20 because
          // this route is pushed over the materials shell rather than sitting
          // above its nav bar.
          padding: OrionSpacing.settingsScreenPaddingTightTop.copyWith(
            bottom: 20.0,
          ),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildCard(
                              title: FlutterI18n.translate(
                                  context, 'editResin.burnInCure'),
                              value: '${_burnInTime.toStringAsFixed(2)} s',
                              onTap: () => _editValue(
                                title: FlutterI18n.translate(
                                    context, 'editResin.burnInCure'),
                                description: FlutterI18n.translate(
                                    context, 'editResin.burnInDesc'),
                                currentValue: _burnInTime.toDouble(),
                                min: 0,
                                max: 30,
                                suffix: ' s',
                                decimals: 2,
                                step: 0.10,
                                onSave: (v) => setState(() => _burnInTime = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCard(
                              title: FlutterI18n.translate(
                                  context, 'editResin.burnInCount'),
                              value: '$_burnInCount',
                              onTap: () => _editValue(
                                title: FlutterI18n.translate(
                                    context, 'editResin.burnInCount'),
                                description: FlutterI18n.translate(
                                    context, 'editResin.burnInCountDesc'),
                                currentValue: _burnInCount.toDouble(),
                                min: 0,
                                max: 20,
                                suffix: '',
                                decimals: 0,
                                onSave: (v) =>
                                    setState(() => _burnInCount = v.round()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildCard(
                              title: FlutterI18n.translate(
                                  context, 'editResin.normalCure'),
                              // Display two decimals but restrict edits to 0.1s
                              value: '${_normalTime.toStringAsFixed(2)} s',
                              onTap: () => _editValue(
                                title: FlutterI18n.translate(
                                    context, 'editResin.normalCure'),
                                description: FlutterI18n.translate(
                                    context, 'editResin.normalCureDesc'),
                                currentValue: _normalTime.toDouble(),
                                min: 0,
                                max: 15,
                                suffix: ' s',
                                decimals: 2,
                                step: 0.1,
                                onSave: (v) => setState(() => _normalTime = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCard(
                              title: FlutterI18n.translate(
                                  context, 'editResin.waitAfterCure'),
                              value: '${_waitAfterCure.toStringAsFixed(2)} s',
                              onTap: () => _editValue(
                                title: FlutterI18n.translate(
                                    context, 'editResin.waitAfterCure'),
                                description: FlutterI18n.translate(
                                    context, 'editResin.waitAfterCureDesc'),
                                currentValue: _waitAfterCure.toDouble(),
                                min: 0,
                                max: 20,
                                suffix: ' s',
                                decimals: 2,
                                step: 0.1,
                                onSave: (v) =>
                                    setState(() => _waitAfterCure = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildCard(
                              title: FlutterI18n.translate(
                                  context, 'editResin.liftAfterPrint'),
                              value: '${_liftAfter.toStringAsFixed(1)} mm',
                              onTap: () => _editValue(
                                title: FlutterI18n.translate(
                                    context, 'editResin.liftAfterPrint'),
                                description: FlutterI18n.translate(
                                    context, 'editResin.liftAfterPrintDesc'),
                                currentValue: _liftAfter,
                                min: 0,
                                max: 20,
                                suffix: ' mm',
                                decimals: 2,
                                step: 0.1,
                                onSave: (v) => setState(() => _liftAfter = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildCard(
                              title: FlutterI18n.translate(
                                  context, 'editResin.waitAfterLift'),
                              value: '${_waitAfterLife.toStringAsFixed(2)} s',
                              onTap: () => _editValue(
                                title: FlutterI18n.translate(
                                    context, 'editResin.waitAfterLift'),
                                description: FlutterI18n.translate(
                                    context, 'editResin.waitAfterLiftDesc'),
                                currentValue: _waitAfterLife.toDouble(),
                                min: 0,
                                max: 20,
                                suffix: ' s',
                                decimals: 2,
                                step: 0.1,
                                onSave: (v) =>
                                    setState(() => _waitAfterLife = v),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      tint: GlassButtonTint.negative,
                      onPressed: _reset,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 65),
                      ),
                      child: Text(
                          FlutterI18n.translate(context, 'common.reset'),
                          style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassButton(
                      tint: GlassButtonTint.positive,
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 65),
                      ),
                      child: _saving
                          ? Text(
                              FlutterI18n.translate(
                                  context, 'editResin.saving'),
                              style: TextStyle(fontSize: 22))
                          : Text(FlutterI18n.translate(context, 'common.save'),
                              style: TextStyle(fontSize: 22)),
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
}
