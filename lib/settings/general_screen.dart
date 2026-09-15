/*
* Orion - General Config Screen
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

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:http/http.dart' as http;
import 'package:orion/settings/machine_settings_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'package:country_flags/country_flags.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/settings/settings_screen.dart';
import 'package:orion/settings/ui_screen.dart';
import 'package:orion/settings/language_screen.dart';
import 'package:orion/util/locales/available_languages.dart';
import 'package:orion/util/orion_config.dart';
import 'package:orion/util/orion_kb/orion_keyboard_expander.dart';
import 'package:orion/util/orion_kb/orion_textfield_spawn.dart';
import 'package:orion/util/orion_list_tile.dart';
import 'package:orion/util/orion_spacing.dart';
import 'package:orion/util/providers/theme_provider.dart';
import 'package:orion/util/thumbnail_cache.dart';
import 'package:orion/widgets/selection_screens.dart';

class GeneralCfgScreen extends StatefulWidget {
  const GeneralCfgScreen({super.key});

  @override
  GeneralCfgScreenState createState() => GeneralCfgScreenState();
}

class GeneralCfgScreenState extends State<GeneralCfgScreen> {
  late OrionThemeMode themeMode;
  late bool useUsbByDefault;
  late bool overrideScreenRotation;
  late String screenRotation;
  late bool useCustomUrl;
  late String customUrl;
  late bool developerMode;
  late bool releaseOverride;
  late bool overrideUpdateCheck;
  late bool overrideRawForceSensorValues;
  late bool reuseCalibrationPlate;
  late bool forceMechanicalSkew;
  late String overrideRelease;
  late bool verboseLogging;
  late bool selfDestructMode;
  late String machineName;

  late String originalRotation;

  final ScrollController _scrollController = ScrollController();

  final OrionConfig config = OrionConfig();

  final GlobalKey<SpawnOrionTextFieldState> urlTextFieldKey =
      GlobalKey<SpawnOrionTextFieldState>();

  final GlobalKey<SpawnOrionTextFieldState> branchTextFieldKey =
      GlobalKey<SpawnOrionTextFieldState>();

  List<String> _availableReleases = [];
  bool _isLoadingReleases = false;
  Map<String, String> _releaseDates = {};
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final OrionConfig config = OrionConfig();
    // We'll set themeMode in didChangeDependencies
    themeMode = OrionThemeMode.light; // default, will be updated
    useUsbByDefault = config.getFlag('useUsbByDefault');
    useCustomUrl = config.getFlag('useCustomUrl', category: 'advanced');
    overrideScreenRotation =
        config.getFlag('overrideScreenRotation', category: 'advanced');
    screenRotation = config.getString('screenRotation', category: 'advanced');
    customUrl = config.getString('customUrl', category: 'advanced');
    developerMode = config.getFlag('developerMode', category: 'advanced');
    releaseOverride = config.getFlag('releaseOverride', category: 'developer');
    overrideUpdateCheck =
        config.getFlag('overrideUpdateCheck', category: 'developer');
    overrideRawForceSensorValues =
        config.getFlag('overrideRawForceSensorValues', category: 'developer');
    reuseCalibrationPlate =
        config.getFlag('reuseCalibrationPlate', category: 'developer');
    forceMechanicalSkew =
        config.getFlag('forceMechanicalSkew', category: 'developer');
    overrideRelease =
        config.getString('overrideRelease', category: 'developer');
    verboseLogging = config.getFlag('verboseLogging', category: 'developer');
    selfDestructMode =
        config.getFlag('selfDestructMode', category: 'topsecret');
    screenRotation = screenRotation == '' ? '0' : screenRotation;
    config.setString('screenRotation', screenRotation, category: 'advanced');
    originalRotation = screenRotation;
    machineName = config.getString('machineName', category: 'machine');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = context.watch<ThemeProvider>();
    themeMode = themeProvider.orionThemeMode;
  }

  bool shouldDestruct() {
    // Always make the Self-Destruct option rare to appear,
    // regardless of whether it has ever been toggled before.
    // Roughly ~0.1% chance on a given build of this screen.
    final rand = Random();
    return rand.nextInt(1000) == 0;
  }

  Widget _buildOffsetNavCard({
    required BuildContext context,
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final navCardElevation = switch (themeMode) {
      OrionThemeMode.glass => 4.0,
      OrionThemeMode.dark => 3.0,
      OrionThemeMode.light => 1.0,
    };

    return GlassCard(
      outlined: true,
      elevation: navCardElevation,
      child: ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontSize: 20)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 16)),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = Localizations.localeOf(context);
    final currentLangCode =
        '${currentLocale.languageCode}_${currentLocale.countryCode}';
    final langMatch =
        availableLanguages.cast<Map<String, String>?>().firstWhere(
              (e) => e!['code'] == currentLangCode,
              orElse: () => null,
            );
    final flagCode = langMatch?['flag'] ?? '';

    return PopScope(
      child: Scaffold(
        body: Padding(
          padding: OrionSpacing.settingsScreenPaddingTightTop,
          child: ListView(
            controller: _scrollController,
            children: <Widget>[
              if (shouldDestruct())
                GlassCard(
                  elevation: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                          10), // match this with your Card's border radius
                      gradient: LinearGradient(
                        colors: [
                          Colors.red,
                          Colors.orange,
                          Colors.yellow,
                          Colors.green,
                          Colors.blue,
                          Colors.indigo,
                          Colors.purple
                        ]
                            .map((color) =>
                                Color.lerp(color, Colors.black, 0.25))
                            .where((color) => color != null)
                            .cast<Color>()
                            .toList(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: OrionListTile(
                        ignoreColor: true,
                        title: FlutterI18n.translate(
                            context, 'generalSettings.selfDestruct'),
                        icon: PhosphorIcons.skull,
                        value: selfDestructMode,
                        onChanged: (bool value) {
                          setState(() {
                            selfDestructMode = value;
                            config.setFlag('selfDestructMode', selfDestructMode,
                                category: 'topsecret');
                            config.blowUp(context, 'assets/images/bsod.png');
                          });
                        },
                      ),
                    ),
                  ),
                ),
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
                            context, 'generalSettings.section'),
                        style: TextStyle(
                          fontSize: 28.0,
                        ),
                      ),
                      const SizedBox(height: 20.0),

                      // UI Settings & Language Navigation
                      Row(
                        children: [
                          Expanded(
                            child: _buildOffsetNavCard(
                              context: context,
                              leading: Icon(Icons.palette),
                              title: FlutterI18n.translate(
                                  context, 'generalSettings.ui'),
                              subtitle: FlutterI18n.translate(
                                  context, 'generalSettings.uiDesc'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const UIScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildOffsetNavCard(
                              context: context,
                              leading: flagCode.isNotEmpty
                                  ? CountryFlag.fromCountryCode(
                                      flagCode,
                                      height: 32,
                                      width: 48,
                                      shape: RoundedRectangle(6),
                                    )
                                  : const Icon(Icons.language),
                              title: FlutterI18n.translate(
                                  context, 'generalSettings.language'),
                              subtitle: FlutterI18n.translate(
                                  context, 'generalSettings.languageDesc'),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const LanguageScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20.0),
                      OrionListTile(
                        title: FlutterI18n.translate(
                            context, 'generalSettings.useUsbDefault'),
                        icon: PhosphorIcons.usb,
                        value: useUsbByDefault,
                        onChanged: (bool value) {
                          setState(() {
                            useUsbByDefault = value;
                            config.setFlag('useUsbByDefault', useUsbByDefault);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
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
                            context, 'generalSettings.advanced'),
                        style: TextStyle(
                          fontSize: 28.0,
                        ),
                      ),
                      const SizedBox(height: 20.0),
                      _buildOffsetNavCard(
                        context: context,
                        leading: Icon(Icons.engineering),
                        title: FlutterI18n.translate(
                            context, 'generalSettings.machineSettings'),
                        subtitle: FlutterI18n.translate(
                            context, 'generalSettings.machineDesc'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const MachineSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      if (Platform.isLinux) const SizedBox(height: 20.0),
                      if (Platform.isLinux)
                        OrionListTile(
                          title: FlutterI18n.translate(
                              context, 'generalSettings.overrideRotation'),
                          icon: PhosphorIcons.deviceRotate(),
                          value: overrideScreenRotation,
                          onChanged: (bool value) {
                            setState(() {
                              overrideScreenRotation = value;
                              config.setFlag('overrideScreenRotation',
                                  overrideScreenRotation,
                                  category: 'advanced');
                            });
                          },
                        ),
                      if (overrideScreenRotation && Platform.isLinux)
                        const SizedBox(height: 20.0),
                      if (overrideScreenRotation && Platform.isLinux)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(4, (index) {
                            final value = [0, 90, 180, 270][index];
                            return Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    right: 10,
                                    left:
                                        10), // Add padding only if it's not the last item
                                child: ChoiceChip.elevated(
                                  label: SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      '$value°',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  selected: screenRotation == '$value',
                                  onSelected: (selected) {
                                    setState(() {
                                      if (selected) screenRotation = '$value';
                                      config.setString(
                                          'screenRotation', screenRotation,
                                          category: 'advanced');
                                      if (screenRotation != originalRotation) {
                                        config.setFlag('needsRestart', true,
                                            category: 'internal');
                                        final settingsScreenState =
                                            context.findAncestorStateOfType<
                                                SettingsScreenState>();
                                        settingsScreenState
                                            ?.setRestartStatus(true);
                                      }
                                    });
                                  },
                                ),
                              ),
                            );
                          }),
                        ),
                      const SizedBox(height: 20.0),
                      OrionListTile(
                        title: FlutterI18n.translate(
                            context, 'generalSettings.useCustomUrl'),
                        icon: PhosphorIcons.network,
                        value: useCustomUrl,
                        onChanged: (bool value) {
                          setState(() {
                            useCustomUrl = value;
                            config.setFlag('useCustomUrl', useCustomUrl,
                                category: 'advanced');
                          });
                        },
                      ),
                      if (useCustomUrl) const SizedBox(height: 20.0),
                      if (useCustomUrl)
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 60,
                                child: GlassButton(
                                  style: ElevatedButton.styleFrom(
                                    elevation: 3,
                                    alignment:
                                        Alignment.center, // Center the content
                                  ),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return GlassAlertDialog(
                                          title: Center(
                                              child: Text(FlutterI18n.translate(
                                                  context,
                                                  'generalSettings.customUrl'))),
                                          content: SizedBox(
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width *
                                                0.5,
                                            child: SingleChildScrollView(
                                              child: Column(
                                                children: [
                                                  SpawnOrionTextField(
                                                    key: urlTextFieldKey,
                                                    keyboardHint:
                                                        FlutterI18n.translate(
                                                            context,
                                                            'generalSettings.enterUrl'),
                                                    locale:
                                                        Localizations.localeOf(
                                                                context)
                                                            .toString(),
                                                    scrollController:
                                                        _scrollController,
                                                    presetText: config
                                                        .getString('customUrl',
                                                            category:
                                                                'advanced'),
                                                  ),
                                                  OrionKbExpander(
                                                      textFieldKey:
                                                          urlTextFieldKey),
                                                ],
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            GlassButton(
                                              tint: GlassButtonTint.neutral,
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                              },
                                              style: ElevatedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 60)),
                                              child: Text(FlutterI18n.translate(
                                                  context, 'common.close')),
                                            ),
                                            GlassButton(
                                              tint: GlassButtonTint.positive,
                                              onPressed: () {
                                                setState(() {
                                                  customUrl = urlTextFieldKey
                                                      .currentState!
                                                      .getCurrentText();
                                                  config.setString(
                                                      'customUrl', customUrl,
                                                      category: 'advanced');
                                                });
                                                Navigator.of(context).pop();
                                              },
                                              style: ElevatedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(0, 60)),
                                              child: Text(FlutterI18n.translate(
                                                  context, 'common.confirm')),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  child: Center(
                                    // Wrap in Center widget
                                    child: AutoSizeText(
                                      customUrl == ''
                                          ? FlutterI18n.translate(
                                              context, 'generalSettings.setUrl')
                                          : customUrl.split('//').last,
                                      style: const TextStyle(fontSize: 22),
                                      minFontSize: 20,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign
                                          .center, // Center text alignment
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: SizedBox(
                                height:
                                    60, // Increase height to prevent text cutoff
                                child: customUrl == ''
                                    ? GlassButton(
                                        style: ElevatedButton.styleFrom(
                                          elevation: 3,
                                          alignment: Alignment
                                              .center, // Center the content
                                        ),
                                        onPressed:
                                            () {}, // Empty callback for disabled state
                                        child: Opacity(
                                          opacity: 0.5, // Make it look disabled
                                          child: Center(
                                            child: Text(
                                              FlutterI18n.translate(
                                                  context, 'common.clear'),
                                              style:
                                                  const TextStyle(fontSize: 20),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      )
                                    : GlassButton(
                                        style: ElevatedButton.styleFrom(
                                          elevation: 3,
                                          alignment: Alignment
                                              .center, // Center the content
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            customUrl = '';
                                            config.setString(
                                                'customUrl', customUrl,
                                                category: 'advanced');
                                          });
                                        },
                                        child: Center(
                                          child: Text(
                                            FlutterI18n.translate(
                                                context, 'common.clear'),
                                            style:
                                                const TextStyle(fontSize: 20),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      if (developerMode) const SizedBox(height: 20.0),
                      if (developerMode)
                        OrionListTile(
                          title: FlutterI18n.translate(
                              context, 'generalSettings.developerMode'),
                          icon: PhosphorIcons.code,
                          value: developerMode,
                          onChanged: (bool value) {
                            setState(() {
                              developerMode = value;
                              config.setFlag('developerMode', developerMode,
                                  category: 'advanced');
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ),

              /// Developer Section for build overrides.
              if (developerMode) _buildDeveloperSection(),
              const SizedBox(height: 12.0),
              // Danger Zone - critical actions
              GlassCard(
                accentColor: Colors.redAccent.shade100,
                outlined: true,
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FlutterI18n.translate(
                            context, 'generalSettings.dangerZone'),
                        style:
                            TextStyle(fontSize: 28.0, color: Colors.redAccent),
                      ),
                      const SizedBox(height: 12.0),
                      Text(
                        FlutterI18n.translate(
                            context, 'generalSettings.dangerZoneDesc'),
                        style: TextStyle(
                            fontSize: 20, color: Colors.redAccent.shade100),
                      ),
                      const SizedBox(height: 20.0),
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
                                            'generalSettings.resetUserConfig')),
                                        content: Text(
                                            FlutterI18n.translate(context,
                                                'generalSettings.resetConfirmMsg'),
                                            style: TextStyle(fontSize: 20.0)),
                                        actions: [
                                          GlassButton(
                                            style: ElevatedButton.styleFrom(
                                              minimumSize: const Size(0, 60),
                                            ),
                                            tint: GlassButtonTint.warn,
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: Text(FlutterI18n.translate(
                                                context, 'common.cancel')),
                                          ),
                                          GlassButton(
                                              tint: GlassButtonTint.negative,
                                              style: ElevatedButton.styleFrom(
                                                minimumSize: const Size(0, 60),
                                              ),
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              child: Text(FlutterI18n.translate(
                                                  context, 'common.reset'))),
                                        ],
                                      ),
                                    ) ??
                                    false;

                                if (confirmed) {
                                  // Capture translations before any async gaps
                                  if (!context.mounted) return;
                                  final cfgPath = config.getConfigPath();
                                  final hasDefault =
                                      File('$cfgPath/orion.default.cfg')
                                          .existsSync();
                                  final rebootingMsg = hasDefault
                                      ? FlutterI18n.translate(context,
                                          'generalSettings.rebootingMsg')
                                      : FlutterI18n.translate(context,
                                          'generalSettings.clearingMsg');

                                  try {
                                    final defaultFile =
                                        File('$cfgPath/orion.default.cfg');
                                    final targetFile =
                                        File('$cfgPath/orion.cfg');

                                    if (defaultFile.existsSync()) {
                                      // Overwrite orion.cfg with the default
                                      final contents =
                                          defaultFile.readAsStringSync();
                                      targetFile.writeAsStringSync(contents);
                                    } else {
                                      // No default provided: remove orion.cfg
                                      if (targetFile.existsSync()) {
                                        targetFile.deleteSync();
                                      }
                                    }

                                    // Show rebooting message then reboot
                                    if (!context.mounted) return;
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) => GlassAlertDialog(
                                        title: Text(FlutterI18n.translate(
                                            context,
                                            'generalSettings.rebooting')),
                                        content: Text(rebootingMsg),
                                      ),
                                    );

                                    // Flush and reboot
                                    await Process.run(
                                        'sudo', ['reboot', 'now']);
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => GlassAlertDialog(
                                        title: Text(FlutterI18n.translate(
                                            context, 'common.error')),
                                        content: Text(FlutterI18n.translate(
                                            context,
                                            'generalSettings.unableToResetMsg')),
                                        actions: [
                                          GlassButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            child: Text(FlutterI18n.translate(
                                                context, 'common.ok')),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                FlutterI18n.translate(
                                    context, 'generalSettings.resetUserConfig'),
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (developerMode) const SizedBox(height: 12.0),
                      if (developerMode)
                        Row(
                          children: [
                            Expanded(
                              child: GlassButton(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 60),
                                ),
                                tint: GlassButtonTint.warn,
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => GlassAlertDialog(
                                          title: Text(FlutterI18n.translate(
                                              context,
                                              'generalSettings.prepareForDelivery')),
                                          content: Text(
                                              FlutterI18n.translate(context,
                                                  'generalSettings.deliveryMsg'),
                                              style: const TextStyle(
                                                  fontSize: 20.0)),
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
                                                    'generalSettings.prepareForDelivery'))),
                                          ],
                                        ),
                                      ) ??
                                      false;

                                  if (confirmed) {
                                    try {
                                      // Mark firstRun so onboarding will run on next boot
                                      config.setFlag('firstRun', true,
                                          category: 'machine');

                                      // Show immediate shutdown dialog then power off
                                      if (!context.mounted) return;
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (ctx) => GlassAlertDialog(
                                          title: Text(FlutterI18n.translate(
                                              context,
                                              'generalSettings.shuttingDown')),
                                          content: Text(FlutterI18n.translate(
                                              context,
                                              'generalSettings.shuttingDownMsg')),
                                        ),
                                      );

                                      await Process.run(
                                          'sudo', ['shutdown', 'now']);
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => GlassAlertDialog(
                                          title: Text(FlutterI18n.translate(
                                              context, 'common.error')),
                                          content: Text(FlutterI18n.translate(
                                              context,
                                              'generalSettings.unableToPrepare')),
                                          actions: [
                                            GlassButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: Text(FlutterI18n.translate(
                                                  context, 'common.ok')),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Text(
                                  FlutterI18n.translate(context,
                                      'generalSettings.prepareForDelivery'),
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
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
    );
  }

  GlassCard _buildDeveloperSection() {
    return GlassCard(
      outlined: true,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              FlutterI18n.translate(context, 'generalSettings.developer'),
              style: const TextStyle(
                fontSize: 28.0,
              ),
            ),
            const SizedBox(height: 20.0),
            OrionListTile(
              title:
                  FlutterI18n.translate(context, 'update.releaseTagOverride'),
              icon: PhosphorIcons.download(),
              value: releaseOverride,
              onChanged: (bool value) {
                setState(() {
                  releaseOverride = value;
                  config.setFlag('releaseOverride', releaseOverride,
                      category: 'developer');
                });
              },
            ),
            if (releaseOverride) const SizedBox(height: 20.0),
            if (releaseOverride)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: GlassButton(
                        style: ElevatedButton.styleFrom(
                          elevation: 3,
                          alignment: Alignment.center, // Center the content
                        ),
                        onPressed: () {
                          _showReleaseDialog();
                        },
                        child: Center(
                          // Wrap in Center widget
                          child: AutoSizeText(
                            overrideRelease == ''
                                ? FlutterI18n.translate(
                                    context, 'update.selectReleaseVersion')
                                : overrideRelease,
                            style: const TextStyle(fontSize: 22),
                            minFontSize: 20,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign:
                                TextAlign.center, // Center text alignment
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: SizedBox(
                      height: 60, // Increase height to prevent text cutoff
                      child: overrideRelease == ''
                          ? GlassButton(
                              style: ElevatedButton.styleFrom(
                                elevation: 3,
                                alignment:
                                    Alignment.center, // Center the content
                              ),
                              onPressed:
                                  () {}, // Empty callback for disabled state
                              child: Opacity(
                                opacity: 0.5, // Make it look disabled
                                child: Center(
                                  child: Text(
                                    FlutterI18n.translate(
                                        context, 'update.clearRelease'),
                                    style: const TextStyle(fontSize: 18),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            )
                          : GlassButton(
                              style: ElevatedButton.styleFrom(
                                elevation: 3,
                                alignment: Alignment.center,
                              ),
                              onPressed: () {
                                setState(() {
                                  overrideRelease = '';
                                  config.setString(
                                      'overrideRelease', overrideRelease,
                                      category: 'developer');
                                });
                              },
                              child: Center(
                                child: AutoSizeText(
                                  FlutterI18n.translate(
                                      context, 'update.clearReleaseTag'),
                                  style: const TextStyle(fontSize: 18),
                                  minFontSize: 16,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflowReplacement: Text(
                                    FlutterI18n.translate(
                                        context, 'update.clearTag'),
                                    style: const TextStyle(fontSize: 18),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20.0),
            OrionListTile(
              title: FlutterI18n.translate(context, 'update.forceUpdate'),
              icon: PhosphorIcons.warning(),
              value: overrideUpdateCheck,
              onChanged: (bool value) {
                setState(() {
                  overrideUpdateCheck = value;
                  config.setFlag('overrideUpdateCheck', overrideUpdateCheck,
                      category: 'developer');
                });
              },
            ),
            const SizedBox(height: 20.0),
            OrionListTile(
              title: FlutterI18n.translate(context, 'update.rawForceSensor'),
              icon: PhosphorIcons.scales(),
              value: overrideRawForceSensorValues,
              onChanged: (bool value) {
                setState(() {
                  overrideRawForceSensorValues = value;
                  config.setFlag('overrideRawForceSensorValues',
                      overrideRawForceSensorValues,
                      category: 'developer');
                });
              },
            ),
            const SizedBox(height: 20.0),
            OrionListTile(
              title: FlutterI18n.translate(context, 'update.reuseCalPlate'),
              icon: PhosphorIcons.flask(),
              value: reuseCalibrationPlate,
              onChanged: (bool value) {
                setState(() {
                  reuseCalibrationPlate = value;
                  config.setFlag('reuseCalibrationPlate', value,
                      category: 'developer');
                });
              },
            ),
            const SizedBox(height: 20.0),
            OrionListTile(
              title: FlutterI18n.translate(
                  context, 'update.forceMechanicalSkew'),
              icon: PhosphorIcons.warning(),
              value: forceMechanicalSkew,
              onChanged: (bool value) {
                setState(() {
                  forceMechanicalSkew = value;
                  config.setFlag('forceMechanicalSkew', value,
                      category: 'developer');
                });
              },
            ),
            const SizedBox(height: 20.0),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 60),
                    ),
                    tint: GlassButtonTint.warn,
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => GlassAlertDialog(
                              title: Text(FlutterI18n.translate(context,
                                  'generalSettings.clearThumbnailCache')),
                              content: Text(
                                  FlutterI18n.translate(
                                      context, 'generalSettings.cacheClearMsg'),
                                  style: const TextStyle(fontSize: 20.0)),
                              actions: [
                                GlassButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 60),
                                    ),
                                    tint: GlassButtonTint.neutral,
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text(FlutterI18n.translate(
                                        context, 'common.cancel'))),
                                GlassButton(
                                    tint: GlassButtonTint.warn,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 60),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(FlutterI18n.translate(
                                        context, 'common.clear'))),
                              ],
                            ),
                          ) ??
                          false;

                      if (confirmed) {
                        try {
                          // Show clearing message
                          final navCtx = nav.context;
                          if (!navCtx.mounted) return;
                          showDialog(
                            context: navCtx,
                            barrierDismissible: false,
                            builder: (ctx) => GlassAlertDialog(
                              title: Text(FlutterI18n.translate(
                                  context, 'generalSettings.clearingCache')),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                      FlutterI18n.translate(context,
                                          'generalSettings.cacheClearing'),
                                      style: const TextStyle(fontSize: 20)),
                                ],
                              ),
                            ),
                          );

                          // Clear the cache
                          await ThumbnailCache.instance.clearAll();

                          // Close progress dialog
                          if (mounted) Navigator.of(context).pop();

                          // Show success message
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => GlassAlertDialog(
                                title: Text(FlutterI18n.translate(
                                    context, 'common.success')),
                                content: Text(
                                    FlutterI18n.translate(context,
                                        'generalSettings.cacheCleared'),
                                    style: const TextStyle(fontSize: 20)),
                                actions: [
                                  GlassButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 60),
                                    ),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: Text(FlutterI18n.translate(
                                        context, 'common.ok')),
                                  ),
                                ],
                              ),
                            );
                          }
                        } catch (e) {
                          // Close progress dialog if still showing
                          if (mounted) Navigator.of(context).pop();

                          // Show error message
                          if (mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => GlassAlertDialog(
                                title: Text(FlutterI18n.translate(
                                    context, 'common.error')),
                                content: Text(
                                    '${FlutterI18n.translate(context, 'generalSettings.failedToClearCache')}$e',
                                    style: const TextStyle(fontSize: 20)),
                                actions: [
                                  GlassButton(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 60),
                                    ),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: Text(FlutterI18n.translate(
                                        context, 'common.ok')),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      }
                    },
                    child: Text(
                      FlutterI18n.translate(
                          context, 'generalSettings.clearThumbnailCache'),
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _isLoadingReleases = false;
    super.dispose();
  }

  void _showReleaseDialog() {
    // Reset state before showing dialog
    setState(() {
      _loadError = null;
      if (_availableReleases.isEmpty) {
        _isLoadingReleases = false;
      }
    });

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setRouteState) {
              void fetchReleases() async {
                if (_availableReleases.isNotEmpty && _loadError == null) {
                  return;
                }

                setRouteState(() {
                  _isLoadingReleases = true;
                  _loadError = null;
                });

                try {
                  final response = await http.get(
                    Uri.parse(
                        'https://api.github.com/repos/Open-Resin-Alliance/Orion/releases'),
                    headers: {'Accept': 'application/vnd.github.v3+json'},
                  ).timeout(const Duration(seconds: 10));

                  if (!context.mounted) return;

                  if (response.statusCode == 200) {
                    final List<dynamic> releases = json.decode(response.body);
                    List<String> regularReleases = [];
                    List<String> branchReleases = [];
                    Map<String, String> dates = {};

                    for (var release in releases) {
                      String tag = release['tag_name'] as String;
                      if (tag.startsWith('v')) {
                        tag = tag.substring(1);
                      }

                      String publishedAt = release['published_at'] as String;
                      DateTime releaseDate = DateTime.parse(publishedAt);
                      String formattedDate =
                          "${releaseDate.year}-${releaseDate.month.toString().padLeft(2, '0')}-${releaseDate.day.toString().padLeft(2, '0')}";

                      dates[tag] = formattedDate;

                      if (tag.startsWith('BRANCH_')) {
                        branchReleases.add(tag);
                      } else {
                        regularReleases.add(tag);
                      }
                    }

                    regularReleases
                        .sort((a, b) => dates[b]!.compareTo(dates[a]!));
                    branchReleases
                        .sort((a, b) => dates[b]!.compareTo(dates[a]!));

                    setRouteState(() {
                      _availableReleases = [
                        ...regularReleases,
                        ...branchReleases
                      ];
                      _releaseDates = dates;
                      _isLoadingReleases = false;
                    });
                  } else {
                    final errMsg =
                        '${FlutterI18n.translate(context, 'update.failedToLoadReleases')}: HTTP ${response.statusCode}';
                    setRouteState(() {
                      _isLoadingReleases = false;
                      _loadError = errMsg;
                    });
                  }
                } catch (e) {
                  setRouteState(() {
                    _isLoadingReleases = false;
                    _loadError = e.toString();
                  });
                }
              }

              if (_availableReleases.isEmpty && !_isLoadingReleases) {
                fetchReleases();
              }

              return DetailedSelectionScreen(
                title: FlutterI18n.translate(
                    context, 'update.selectReleaseVersion'),
                child: Column(
                  children: [
                    if (overrideRelease.isNotEmpty)
                      GlassCard(
                        outlined: true,
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 22,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      FlutterI18n.translate(context,
                                          'update.currentReleaseOverride'),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      overrideRelease,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (overrideRelease.isNotEmpty) const SizedBox(height: 12),
                    Expanded(
                      child: _isLoadingReleases
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 24),
                                  Text(
                                    FlutterI18n.translate(
                                        context, 'update.loadingReleases'),
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    FlutterI18n.translate(
                                        context, 'update.loadingReleasesHint'),
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : _loadError != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.error_outline,
                                            size: 64, color: Colors.red),
                                        const SizedBox(height: 24),
                                        Text(
                                          FlutterI18n.translate(context,
                                              'update.failedToLoadReleases'),
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade300,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _loadError!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                        const SizedBox(height: 24),
                                        GlassButton(
                                          onPressed: fetchReleases,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.refresh,
                                                  size: 20),
                                              const SizedBox(width: 8),
                                              Text(
                                                  FlutterI18n.translate(
                                                      context, 'common.retry'),
                                                  style: const TextStyle(
                                                      fontSize: 18)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : _availableReleases.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.inbox_outlined,
                                              size: 64, color: Colors.grey),
                                          const SizedBox(height: 24),
                                          Text(
                                            FlutterI18n.translate(context,
                                                'update.noReleasesFound'),
                                            style: const TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            FlutterI18n.translate(context,
                                                'update.noReleasesDesc'),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontSize: 16,
                                                color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    )
                                  : _buildReleasesList(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    )
        .then((_) {
      // Cleanup when dialog is closed
      if (mounted) {
        setState(() {
          _isLoadingReleases = false;
        });
      }
    });
  }

  Widget _buildReleaseSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 22, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the modernized releases list with Orion-style hierarchy
  Widget _buildReleasesList() {
    final regularReleases =
        _availableReleases.where((r) => !r.startsWith('BRANCH_')).toList();
    final branchReleases =
        _availableReleases.where((r) => r.startsWith('BRANCH_')).toList();

    return ListView(
      children: [
        if (regularReleases.isNotEmpty) ...[
          _buildReleaseSectionHeader(
            icon: Icons.verified,
            title: FlutterI18n.translate(context, 'update.stableReleases'),
            subtitle:
                FlutterI18n.translate(context, 'update.stableReleasesDesc'),
            accent: Colors.green.shade300,
          ),
          ...regularReleases
              .map((release) => _buildReleaseItem(release, isStable: true)),
        ],
        if (branchReleases.isNotEmpty && regularReleases.isNotEmpty)
          const SizedBox(height: 18),
        if (branchReleases.isNotEmpty) ...[
          _buildReleaseSectionHeader(
            icon: Icons.science,
            title: FlutterI18n.translate(context, 'update.devBranches'),
            subtitle: FlutterI18n.translate(context, 'update.devBranchesDesc'),
            accent: Colors.orange.shade300,
          ),
          ...branchReleases
              .map((release) => _buildReleaseItem(release, isStable: false)),
        ],
      ],
    );
  }

  /// Builds an individual release item with Orion card styling
  Widget _buildReleaseItem(String release, {required bool isStable}) {
    final isSelected = overrideRelease == release;
    final releaseDate = _releaseDates[release] ??
        FlutterI18n.translate(context, 'update.unknownDate');
    final accent = isStable ? Colors.green.shade300 : Colors.orange.shade300;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: GlassCard(
        elevation: isSelected ? 2.0 : 1.0,
        outlined: true,
        color: isSelected
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3)
            : null,
        child: InkWell(
          onTap: () {
            setState(() {
              overrideRelease = release;
              config.setString('overrideRelease', overrideRelease,
                  category: 'developer');
            });
            Navigator.of(context).pop();
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.2)
                        : accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : (isStable ? Icons.verified : Icons.science),
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        release,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        releaseDate,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    border: isSelected
                        ? null
                        : Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
