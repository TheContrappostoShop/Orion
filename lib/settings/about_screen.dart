/*
* Orion - About Screen
* Copyright (C) 2024 TheContrappostoShop
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:orion/pubspec.dart';
import 'package:orion/themes/themes.dart';
import 'package:orion/util/orion_config.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:toastification/toastification.dart';
import 'dart:io';

Logger _logger = Logger('AboutScreen');

Future<String> executeCommand(String command, List<String> arguments) async {
  final result = await Process.run(command, arguments);
  if (result.exitCode == 0) {
    return result.stdout.trim();
  } else {
    throw Exception(
        'Failed to execute command: $command ${arguments.join(" ")}\nError: ${result.stderr}');
  }
}

Future<String> getRaspberryPiModel() async {
  try {
    final model = await executeCommand('cat', ['/proc/device-tree/model']);
    _logger.info('Raspberry Pi model: $model');
    return model.trim();
  } catch (e) {
    _logger.warning('Error getting Raspberry Pi model: $e');
    return 'Unknown Model';
  }
}

Future<String> getVersionNumber() async {
  return 'Orion ${Pubspec.version}' ' - Odyssey 1.0.0';
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  AboutScreenState createState() => AboutScreenState();
}

class AboutScreenState extends State<AboutScreen> {
  int qrTapCount = 0;
  Toastification toastification = Toastification();

  @override
  Widget build(BuildContext context) {
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0),
            child: isLandscape
                ? buildLandscapeLayout(context)
                : buildPortraitLayout(context),
          ),
        ),
      ),
    );
  }

  Widget buildPortraitLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildNameCard('Prometheus mSLA'),
        buildInfoCard(
            'Serial Number', kDebugMode ? 'DBG-0001-001' : 'BLEEDING-EDGE'),
        buildVersionCard(),
        buildHardwareCard(),
        const SizedBox(height: 16),
        buildQrView(context),
      ],
    );
  }

  Widget buildLandscapeLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildNameCard('Prometheus mSLA'),
              buildInfoCard('Serial Number',
                  kDebugMode ? 'DBG-0001-001' : 'BLEEDING-EDGE'),
              buildVersionCard(),
              buildHardwareCard(),
            ],
          ),
        ),
        const SizedBox(width: 16),
        buildQrView(context),
      ],
    );
  }

  Widget buildInfoCard(String title, String subtitle) {
    return Card.outlined(
      elevation: 1.0,
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget buildVersionCard() {
    return Card.outlined(
      elevation: 1.0,
      child: ListTile(
        title: const Text('UI & API Version'),
        subtitle: FutureBuilder<String>(
          future: getVersionNumber(),
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            return Text(snapshot.data ?? 'N/A');
          },
        ),
      ),
    );
  }

  Widget buildHardwareCard() {
    return Card.outlined(
      elevation: 1.0,
      child: ListTile(
        title: const Text('Hardware (Local)'),
        subtitle: FutureBuilder<String>(
          future: getRaspberryPiModel(),
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            // Sanitize the model string to remove non-printable characters before logging and displaying
            final sanitizedModel =
                snapshot.data?.replaceAll(RegExp(r'[^\x20-\x7E]'), '') ?? 'N/A';
            _logger.info('Raspberry Pi model: $sanitizedModel');
            return Text(sanitizedModel);
          },
        ),
      ),
    );
  }

  Widget buildNameCard(String title) {
    return Card.outlined(
      elevation: 1.0,
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget buildQrView(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: handleQrTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Card.outlined(
            elevation: 1.0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: QrImageView(
                data: 'https://github.com/TheContrappostoShop/Orion',
                version: QrVersions.auto,
                size: 250,
                eyeStyle: QrEyeStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  dataModuleShape: QrDataModuleShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void handleQrTap() {
    setState(() {
      if (OrionConfig().getFlag('developerMode', category: 'advanced')) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
          title: const Text('You are already a developer',
              style: TextStyle(fontSize: 18)),
          alignment: Alignment.topCenter,
          primaryColor: Colors.green,
          backgroundColor:
              Theme.of(context).colorScheme.surface.withBrightness(1.35),
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        );
      } else {
        qrTapCount++;
        if (qrTapCount >= 5) {
          OrionConfig().setFlag('developerMode', true, category: 'advanced');
          toastification.show(
            context: context,
            type: ToastificationType.success,
            style: ToastificationStyle.fillColored,
            autoCloseDuration: const Duration(seconds: 2),
            title: const Text(
                'Developer Mode Activated: You are now a developer!',
                style: TextStyle(fontSize: 18)),
            alignment: Alignment.topCenter,
            primaryColor: Colors.green,
            backgroundColor:
                Theme.of(context).colorScheme.surface.withBrightness(1.35),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          );
        } else {
          toastification.show(
            context: context,
            type: ToastificationType.info,
            style: ToastificationStyle.flatColored,
            autoCloseDuration: const Duration(seconds: 2),
            title: Text(
                'You are ${5 - qrTapCount} ${5 - qrTapCount == 1 ? 'tap' : 'taps'} away from becoming a developer',
                style: const TextStyle(fontSize: 18)),
            alignment: Alignment.topCenter,
            primaryColor: Theme.of(context).colorScheme.primary,
            backgroundColor:
                Theme.of(context).colorScheme.surface.withBrightness(1.35),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            showProgressBar: false,
          );
        }
      }
    });
  }
}
