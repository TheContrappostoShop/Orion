/*
* Orion - Machine Settings Screen
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
import 'package:orion/util/orion_list_tile.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/widgets/system_status_widget.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/widgets/orion_app_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class MachineSettingsScreen extends StatefulWidget {
  const MachineSettingsScreen({super.key});

  @override
  State<MachineSettingsScreen> createState() => _MachineSettingsScreenState();
}

class _MachineSettingsScreenState extends State<MachineSettingsScreen> {
  final OrionConfig _cfg = OrionConfig();

  static const hardwareFlagKeys = <String, String>{
    'hasHeatedChamber': 'heatedChamber',
    'hasHeatedVat': 'heatedVat',
    'hasCamera': 'camera',
    'hasAirFilter': 'airFilter',
    'hasForceSensor': 'forceSensor',
    'hasCameraFlash': 'cameraFlash',
    'hasSmartpower': 'smartPower',
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: GlassApp(
        child: Scaffold(
          appBar: OrionAppBar(
            title:
                Text(FlutterI18n.translate(context, 'machineSettings.section')),
            toolbarHeight: Theme.of(context).appBarTheme.toolbarHeight,
            actions: <Widget>[
              SystemStatusWidget(),
            ],
          ),
          body: Padding(
            padding: OrionSpacing.settingsScreenPadding,
            child: ListView(
              children: [
                GlassCard(
                  outlined: true,
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          FlutterI18n.translate(
                              context, 'machineSettings.section'),
                          style: TextStyle(
                            fontSize: 28.0,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...hardwareFlagKeys.entries.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 20.0),
                                  child: OrionListTile(
                                    // Allow vendor or user-provided names to override
                                    // the translated default name.
                                    title: _cfg.getFeatureDisplayName(e.key,
                                        defaultName: FlutterI18n.translate(
                                            context,
                                            'machineSettings.${e.value}')),
                                    icon: _iconForKey(e.key),
                                    value: _cfg.getHardwareFeature(e.key),
                                    onChanged: (v) {
                                      setState(() {
                                        _cfg.setUserHardwareFeature(e.key, v);
                                      });
                                    },
                                  ),
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
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 60),
                                ),
                                tint: GlassButtonTint.negative,
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => GlassAlertDialog(
                                          title: Text(FlutterI18n.translate(
                                              context,
                                              'machineSettings.clearOverrides')),
                                          content: Text(
                                              FlutterI18n.translate(context,
                                                  'machineSettings.clearConfirm'),
                                              style: TextStyle(fontSize: 20.0)),
                                          actions: [
                                            GlassButton(
                                                style: ElevatedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 60),
                                                ),
                                                tint: GlassButtonTint.warn,
                                                onPressed: () =>
                                                    Navigator.of(ctx)
                                                        .pop(false),
                                                child: Text(
                                                    FlutterI18n.translate(
                                                        context,
                                                        'common.cancel'))),
                                            GlassButton(
                                                tint: GlassButtonTint.negative,
                                                style: ElevatedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 60),
                                                ),
                                                onPressed: () =>
                                                    Navigator.of(ctx).pop(true),
                                                child: Text(FlutterI18n.translate(
                                                    context,
                                                    'machineSettings.remove'))),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                  if (confirmed) {
                                    _cfg.clearUserFeatureOverrides();
                                    setState(() {});
                                  }
                                },
                                child: Text(FlutterI18n.translate(
                                    context, 'machineSettings.clearOverrides')),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Map hardware feature keys to fitting icons (Phosphor icon constructors)
  dynamic _iconForKey(String key) {
    switch (key) {
      case 'hasHeatedChamber':
        return PhosphorIcons.thermometer;
      case 'hasHeatedVat':
        return PhosphorIcons.fire;
      case 'hasCamera':
        return PhosphorIcons.camera;
      case 'hasAirFilter':
        return PhosphorIcons.fan;
      case 'hasForceSensor':
        return PhosphorIcons.scales;
      case 'hasCameraFlash':
        return Icons.flash_on;
      case 'hasSmartpower':
        return PhosphorIcons.plug;
      default:
        return PhosphorIcons.memory;
    }
  }
}
