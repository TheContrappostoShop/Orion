/*
* Orion - Status Screen
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

import 'dart:async';
import 'dart:io';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/files/grid_files_screen.dart';
import 'package:orion/settings/settings_screen.dart';
import 'package:orion/themes/themes.dart';
import 'package:orion/util/sl1_thumbnail.dart';
import 'package:orion/util/status_card.dart';

class StatusScreen extends StatefulWidget {
  final bool newPrint;
  const StatusScreen({super.key, required this.newPrint});

  @override
  StatusScreenState createState() => StatusScreenState();
}

class StatusScreenState extends State<StatusScreen>
    with SingleTickerProviderStateMixin {
  final _logger = Logger('StatusScreen');
  final ApiService _api = ApiService();

  String fileName = '';

  int totalSeconds = 0;
  Duration duration = const Duration();
  String twoDigits = '';
  String twoDigitHours = '';
  String twoDigitMinutes = '';
  String twoDigitSeconds = '';

  final ValueNotifier<String?> thumbnailNotifier = ValueNotifier<String?>(null);
  late ValueNotifier<bool> newPrintNotifier = ValueNotifier<bool>(false);
  Future<void>? _initStatusDetailsFuture;
  Map<String, dynamic>? status;
  double opacity = 0.0;
  bool isPausing = false; // Flag to check if pausing is in progress
  bool isCanceling = false; // Flag to check if canceling is in progress
  bool isThumbnailFetched = false; // Flag to check if thumbnail is fetched
  Timer? timer; // Timer for fetching status

  @override
  void initState() {
    super.initState();
    _initStatusDetailsFuture = getStatus();
    newPrintNotifier = ValueNotifier<bool>(widget.newPrint);
    if (widget.newPrint == true) {
      isThumbnailFetched = false;
    }
    timer = Timer.periodic(const Duration(seconds: 1),
        (Timer t) => getStatus()); // Fetch status every second
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> getStatus() async {
    try {
      status = await _api.getStatus();
      if (status != null) {
        if (status!['status'] == 'Printing' || status!['status'] == 'Idle') {
          if (status!['print_data'] != null &&
              status!['print_data']['file_data'] != null) {
            String? thumbnailFullPath =
                status!['print_data']['file_data']['path'];
            fileName = status!['print_data']['file_data']['name'];
            String location = status!['print_data']['file_data']
                    ['location_category'] ??
                'Local';
            if (thumbnailFullPath != null &&
                !isThumbnailFetched &&
                status!['status'] == 'Printing') {
              String thumbnailSubdir = '/';
              if (thumbnailFullPath.contains('/')) {
                thumbnailSubdir = thumbnailFullPath.substring(
                    0, thumbnailFullPath.lastIndexOf('/'));
              }
              thumbnailNotifier.value = await ThumbnailUtil.extractThumbnail(
                location,
                thumbnailSubdir,
                fileName,
                size: 'Large',
              );
              isThumbnailFetched = true;
            }
          } else {
            thumbnailNotifier.value = null;
          }
        }
      } else {
        thumbnailNotifier.value = null;
      }
      if (mounted) setState(() {});
    } catch (e) {
      _logger.severe('Failed to get status: $e');
    }
  }

  // Method to get the status color based on the status
  Color getStatusColor() {
    final Map<String, Color> statusColor = {
      'Printing': Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.primary
          : Colors.black54,
      'Idle': Colors.greenAccent,
      'Shutdown': Colors.red,
      'Canceled': Colors.red,
      'Pause': Colors.orange,
      'Curing': Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.primaryContainer.withBrightness(1.7)
          : Theme.of(context).colorScheme.primary,
    };

    String printStatus = status!['status'];
    bool curing = status!['physical_state']['curing'] ??
        false; // Default to false if 'curing' is null

    bool paused = status!['paused'] ?? false;
    bool canceled = status!['layer'] == null;

    if (curing) {
      return statusColor['Curing'] ??
          Colors.black; // Default to black if 'Curing' is not in the map
    } else if (paused) {
      return statusColor['Pause'] ??
          Colors.black; // Default to black if 'Pause' is not in the map
    } else if (canceled) {
      return statusColor['Canceled'] ??
          Colors.black; // Default to black if 'Canceled' is not in the map
    } else {
      return statusColor[printStatus] ??
          Colors.black; // Default to black if the status is not in the map
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initStatusDetailsFuture,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        } else if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Error: ${snapshot.error}'),
            ),
          );
        } else {
          if (status != null &&
              status!['print_data'] == null &&
              newPrintNotifier.value == false) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('No Print Data Available'),
              ),
              body: Center(
                child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const GridFilesScreen()),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Go to Files',
                        style: TextStyle(fontSize: 26),
                      ),
                    )),
              ),
            );
          } else if (status != null &&
              (status!['layer'] == null ||
                  status!['layer'] == status!['print_data']['layer_count']) &&
              newPrintNotifier.value == true) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Loading...'),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          } else if (status == null) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Error'),
              ),
              body: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'An Error has occurred while fetching files!\n'
                      'Please ensure that Odyssey is running and accessible.\n\n'
                      'If the issue persists, please contact support.\n'
                      'Error Code: PINK-CARROT',
                    ),
                    SizedBox(height: kToolbarHeight / 2)
                  ],
                ),
              ),
            );
          } else {
            if (status != null && status!['status'] == 'Printing') {
              newPrintNotifier.value = false;
            }

            bool isLandScape =
                MediaQuery.of(context).orientation == Orientation.landscape;

            totalSeconds = status!['print_data']['print_time'].toInt();
            duration = Duration(seconds: totalSeconds);
            twoDigits(int n) => n.toString().padLeft(2, "0");

            twoDigitHours = twoDigits(duration.inHours.remainder(24));
            twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
            twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                          text: 'Print Status',
                          style: Theme.of(context).appBarTheme.titleTextStyle),
                      TextSpan(
                          text: ' - ',
                          style: Theme.of(context).appBarTheme.titleTextStyle),
                      TextSpan(
                        text: isCanceling && status!['layer'] != null
                            ? 'Canceling'
                            : status!['layer'] == null
                                ? 'Canceled'
                                : isPausing == true &&
                                        status!['paused'] == false
                                    ? 'Pausing'
                                    : status!['paused'] == true
                                        ? 'Paused'
                                        : status!['status'] == 'Idle'
                                            ? 'Finished'
                                            : '${status!['status']}',
                        style: Theme.of(context).appBarTheme.titleTextStyle,
                      ),
                    ],
                  ),
                ),
              ),
              body: Center(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return isLandScape
                        ? Padding(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 20),
                            child: buildLandscapeLayout(context))
                        : Padding(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 20),
                            child: buildPortraitLayout(context));
                  },
                ),
              ),
            );
          }
        }
      },
    );
  }

  Widget buildPortraitLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildNameCard(fileName),
              const SizedBox(height: 16),
              Expanded(
                child: Column(
                  children: [
                    const Spacer(),
                    buildThumbnailView(context),
                    const Spacer(),
                    buildNameCard(fileName),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: buildInfoCard('Current Z Position',
                              '${(status!['physical_state']['z'] as double).toStringAsFixed(3)} mm'),
                        ),
                        Expanded(
                          child: buildInfoCard('Print Layers',
                              '${status!['layer'] == null ? '-' : status!['layer'] + 1 ?? '-'} / ${status!['print_data']['layer_count'] + 1}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    buildInfoCard('Estimated Print Time',
                        '$twoDigitHours:$twoDigitMinutes:$twoDigitSeconds'),
                    const SizedBox(height: 5),
                    buildInfoCard('Estimated Volume',
                        '${(status!['print_data']['used_material'] as double).toStringAsFixed(2)} mL'),
                    const Spacer(),
                    buildButtons(),
                  ],
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget buildLandscapeLayout(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child: ListView(
                  children: [
                    buildNameCard(fileName),
                    buildInfoCard('Current Z Position',
                        '${(status!['physical_state']['z'] as double).toStringAsFixed(3)} mm'),
                    buildInfoCard('Print Layers',
                        '${status!['layer'] == null ? '-' : status!['layer'] + 1 ?? '-'} / ${status!['print_data']['layer_count'] + 1}'),
                    buildInfoCard('Estimated Print Time',
                        '$twoDigitHours:$twoDigitMinutes:$twoDigitSeconds'),
                    buildInfoCard('Estimated Volume',
                        '${(status!['print_data']['used_material'] as double).toStringAsFixed(2)} mL')
                  ],
                ),
              ),
              const SizedBox(width: 16.0),
              Flexible(
                flex: 0,
                child: buildThumbnailView(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 5, right: 5),
          child: buildButtons(),
        ),
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

  Widget buildNameCard(String title) {
    return Card.outlined(
      elevation: 1.0,
      child: ListTile(
        title: AutoSizeText.rich(
          maxLines: 1,
          minFontSize: 16,
          TextSpan(
            children: [
              TextSpan(
                text: fileName.length >= 4
                    ? '${fileName.substring(0, 12)}...'
                    : fileName,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: getStatusColor(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildThumbnailView(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: thumbnailNotifier,
      builder: (BuildContext context, String? thumbnail, Widget? child) {
        double progress = 0.0;
        if (status!['layer'] != null &&
            status!['print_data']['layer_count'] != null) {
          progress = status!['layer'] / status!['print_data']['layer_count'];
        }
        return Center(
          child: Stack(
            children: [
              Card.outlined(
                elevation: 1.0,
                child: Padding(
                  padding: const EdgeInsets.all(4.5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7.75),
                    child: Stack(
                      children: [
                        // Grayscale image
                        ColorFiltered(
                          colorFilter: const ColorFilter.matrix(<double>[
                            0.2126, 0.7152, 0.0722, 0, 0, //
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0.2126, 0.7152, 0.0722, 0, 0,
                            0, 0, 0, 1, 0,
                          ]),
                          child: thumbnail != null && thumbnail.isNotEmpty
                              ? Image.file(
                                  File(thumbnail),
                                  fit: BoxFit.cover,
                                )
                              : const Center(
                                  child: CircularProgressIndicator(),
                                ),
                        ),
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.35),
                          ),
                        ),
                        // Colored image revealed based on progress
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                heightFactor: progress,
                                child: thumbnail != null && thumbnail.isNotEmpty
                                    ? Image.file(
                                        File(thumbnail),
                                        fit: BoxFit.cover,
                                      )
                                    : const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                right: 15,
                child: Center(
                  child: StatusCard(
                    isCanceling: isCanceling,
                    isPausing: isPausing,
                    progress: progress,
                    statusColor: getStatusColor(),
                    status: status!,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Card(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(9.75),
                        bottomRight: Radius.circular(9.75),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2.5),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(7.75),
                          bottomRight: Radius.circular(7.75),
                        ),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: LinearProgressIndicator(
                            minHeight: 30,
                            color: getStatusColor(),
                            value: progress,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: isCanceling == true && status!['layer'] != null
                ? null
                : status!['layer'] == null || status!['status'] == 'Idle'
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return Dialog(
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width *
                                    0.5, // 80% of screen width
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const SizedBox(height: 10),
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text(
                                        'Options',
                                        style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 20, right: 20),
                                      child: SizedBox(
                                        height: 65,
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      const SettingsScreen()),
                                            );
                                          },
                                          child: const Text(
                                            'Settings',
                                            style: TextStyle(fontSize: 24),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(
                                        height:
                                            20), // Add some spacing between the buttons
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 20, right: 20),
                                      child: SizedBox(
                                        height: 65,
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _api.cancelPrint();
                                            setState(() {
                                              isCanceling = true;
                                            });
                                          },
                                          child: const Text(
                                            'Cancel Print',
                                            style: TextStyle(fontSize: 24),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              minimumSize: Size(
                0, // Subtract the padding on both sides
                Theme.of(context).appBarTheme.toolbarHeight as double,
              ),
            ),
            child: const Text(
              'Options',
              style: TextStyle(fontSize: 24),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: ElevatedButton(
            onPressed: isCanceling == true && status!['layer'] != null
                ? null
                : isPausing == true && status!['paused'] == false
                    ? null
                    : status!['layer'] == null
                        ? () {
                            Navigator.popUntil(
                                context, ModalRoute.withName('/'));
                          }
                        : status!['status'] == 'Idle'
                            ? () {
                                Navigator.pop(context);
                              }
                            : () {
                                if (status!['paused'] == true) {
                                  _api.resumePrint();
                                  setState(() {
                                    isPausing = false;
                                  });
                                } else {
                                  _api.pausePrint();
                                  setState(() {
                                    isPausing = true;
                                  });
                                }
                              },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              minimumSize: Size(
                0, // Subtract the padding on both sides
                Theme.of(context).appBarTheme.toolbarHeight as double,
              ),
            ),
            child: Text(
              status!['layer'] == null || status!['status'] == 'Idle'
                  ? 'Return to Home'
                  : status!['paused'] == true
                      ? 'Resume'
                      : 'Pause',
              style: const TextStyle(fontSize: 24),
            ),
          ),
        ),
      ],
    );
  }
}
