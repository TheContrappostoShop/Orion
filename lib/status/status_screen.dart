/*
* Orion - Status Screen
* Copyright (C) 2024 TheContrappostoShop (PaulGD0, shifubrams)
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
import 'package:orion/files/details_screen.dart';
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

class StatusScreenState extends State<StatusScreen> with SingleTickerProviderStateMixin {
  final _logger = Logger('StatusScreen');
  double leftPadding = 0;
  double rightPadding = 0;

  final GlobalKey textKey1 = GlobalKey();
  final GlobalKey textKey2 = GlobalKey();
  final GlobalKey textKey3 = GlobalKey();
  final GlobalKey textKey4 = GlobalKey();
  final GlobalKey textKey5 = GlobalKey();
  final GlobalKey previewKey = GlobalKey();

  final ValueNotifier<String?> thumbnailNotifier = ValueNotifier<String?>(null);
  late ValueNotifier<bool> newPrintNotifier = ValueNotifier<bool>(false);
  Future<void>? _initStatusDetailsFuture;
  Map<String, dynamic>? status;
  double opacity = 0.0;
  bool isPausing = false;
  bool isCanceling = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _initStatusDetailsFuture = getStatus();
    newPrintNotifier = ValueNotifier<bool>(widget.newPrint);

    timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => getStatus());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> getStatus() async {
    try {
      status = await ApiService.getStatus();
      if (status != null) {
        if (status!['status'] == 'Printing' || status!['status'] == 'Idle') {
          if (status!['print_data'] != null && status!['print_data']['file_data'] != null) {
            String? thumbnailFullPath = status!['print_data']['file_data']['path'];
            String? fileName = status!['print_data']['file_data']['name'];
            String location = status!['print_data']['file_data']['location_category'] ?? 'Local';
            if (thumbnailFullPath != null && fileName != null) {
              String thumbnailSubdir = '/';
              if (thumbnailFullPath.contains('/')) {
                thumbnailSubdir = thumbnailFullPath.substring(0, thumbnailFullPath.lastIndexOf('/'));
              }
              thumbnailNotifier.value = await ThumbnailUtil.extractThumbnail(
                location,
                thumbnailSubdir,
                fileName,
              );
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

  Color getStatusColor() {
    final Map<String, Color> statusColor = {
      'Printing':
          Theme.of(context).brightness == Brightness.dark ? Theme.of(context).colorScheme.primary : Colors.black54,
      'Idle': Colors.greenAccent,
      'Shutdown': Colors.red,
      'Canceled': Colors.red,
      'Pause': Colors.orange,
      'Curing': Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.primaryContainer.withBrightness(1.7)
          : Theme.of(context).colorScheme.primary,
    };

    String printStatus = status!['status'];
    bool curing = status!['physical_state']['curing'] ?? false; // Default to false if 'curing' is null

    bool paused = status!['paused'] ?? false;
    bool canceled = status!['layer'] == null;

    if (curing) {
      return statusColor['Curing'] ?? Colors.black; // Default to black if 'Curing' is not in the map
    } else if (paused) {
      return statusColor['Pause'] ?? Colors.black; // Default to black if 'Pause' is not in the map
    } else if (canceled) {
      return statusColor['Canceled'] ?? Colors.black; // Default to black if 'Canceled' is not in the map
    } else {
      return statusColor[printStatus] ?? Colors.black; // Default to black if the status is not in the map
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
          if (status != null && status!['print_data'] == null && newPrintNotifier.value == false) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('No Print Data Available'),
              ),
              body: Center(
                child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const GridFilesScreen()),
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
              (status!['layer'] == null || status!['layer'] == status!['print_data']['layer_count']) &&
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final keys = [
                textKey1,
                textKey2,
                textKey3,
                textKey4,
                textKey5,
              ];
              double maxWidth = 0;

              for (var key in keys) {
                final width = key.currentContext?.size?.width ?? 0;
                if (width > maxWidth) {
                  maxWidth = width;
                }
              }

              final previewWidth = previewKey.currentContext?.size?.width ?? 0;

              final screenWidth = MediaQuery.of(context).size.width;
              leftPadding = (screenWidth - maxWidth - previewWidth) / 3;
              if (leftPadding < 0) leftPadding = 0;
              rightPadding = leftPadding;

              setState(() {
                opacity = 1.0; // Set opacity to 1 after sizes have been calculated
              });
            });

            int totalSeconds = status!['print_data']['print_time'].toInt();
            Duration duration = Duration(seconds: totalSeconds);

            String twoDigits(int n) => n.toString().padLeft(2, "0");
            String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
            String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Print Status', style: Theme.of(context).appBarTheme.titleTextStyle),
                      TextSpan(text: ' - ', style: Theme.of(context).appBarTheme.titleTextStyle),
                      TextSpan(
                        text: isCanceling && status!['layer'] != null
                            ? 'Canceling'
                            : status!['layer'] == null
                                ? 'Canceled'
                                : isPausing == true && status!['paused'] == false
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
              body: Opacity(
                opacity: opacity,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return Stack(
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            if (status!['status'] == 'Printing' || status!['status'] == 'Idle') ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: leftPadding <= 0 ? leftPadding : leftPadding - 10),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 300),
                                    child: Card.outlined(
                                      key: textKey1,
                                      elevation: 1,
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: AutoSizeText(
                                          maxLines: 2,
                                          minFontSize: 16,
                                          '${status!['print_data']['file_data']['name']}',
                                          style: TextStyle(
                                              fontSize: 24, fontWeight: FontWeight.bold, color: getStatusColor()),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: leftPadding),
                                  child: Text(
                                    'Z Position: ${(status!['physical_state']['z'] as double).toStringAsFixed(3)} mm',
                                    style: const TextStyle(fontSize: 20),
                                    key: textKey2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: leftPadding),
                                  child: Text(
                                    'Layer: ${status!['layer'] == null ? '-' : status!['layer'] + 1 ?? '-'} / ${status!['print_data']['layer_count'] + 1}',
                                    style: const TextStyle(fontSize: 20),
                                    key: textKey3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: leftPadding),
                                  child: Text(
                                    'Printing Time: ${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds',
                                    style: const TextStyle(fontSize: 20),
                                    key: textKey4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: leftPadding),
                                  child: Text(
                                    'Material: ${(status!['print_data']['used_material'] as double).toStringAsFixed(2)} mL',
                                    style: const TextStyle(fontSize: 20),
                                    key: textKey5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.only(right: rightPadding),
                            child: ValueListenableBuilder<String?>(
                              valueListenable: thumbnailNotifier,
                              builder: (BuildContext context, String? thumbnail, Widget? child) {
                                double progress = 0.0;
                                if (status!['layer'] != null && status!['print_data']['layer_count'] != null) {
                                  progress = status!['layer'] / status!['print_data']['layer_count'];
                                }
                                return thumbnail != null
                                    ? Stack(
                                        children: [
                                          Card(
                                            key: previewKey,
                                            child: Padding(
                                              padding: const EdgeInsets.all(4.5),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(7.75),
                                                child: Image.file(
                                                  File(thumbnail),
                                                  width: 220,
                                                  height: 220,
                                                  color: Colors.black,
                                                  colorBlendMode: BlendMode.saturation,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Card(
                                            //key: previewKey,
                                            child: Padding(
                                              padding: const EdgeInsets.all(4.5),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(7.75),
                                                child: Stack(
                                                  children: [
                                                    Image.file(
                                                      File(thumbnail),
                                                      width: 220,
                                                      height: 220,
                                                    ),
                                                    Container(
                                                      width: 220,
                                                      height: 220,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.bottomCenter,
                                                          end: Alignment.topCenter,
                                                          colors: [
                                                            Colors.transparent,
                                                            Colors.black.withOpacity(0.65),
                                                          ],
                                                          stops: [(progress), (progress)],
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      top: 0,
                                                      bottom: 0,
                                                      left: 0,
                                                      right: 0,
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
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(4.5),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(7.75),
                                            child: const Image(
                                              image: AssetImage('assets/images/placeholder.png'),
                                              width: 220,
                                              height: 220,
                                            ),
                                          ),
                                        ),
                                      );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              bottomNavigationBar: Opacity(
                opacity: opacity,
                child: Padding(
                  padding: EdgeInsets.only(
                      left: (leftPadding - 10) < 0 ? 0 : leftPadding - 10,
                      right: (rightPadding - 10) < 0 ? 0 : rightPadding - 10,
                      bottom: 40,
                      top: 20),
                  child: Row(
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
                                              width: MediaQuery.of(context).size.width * 0.5, // 80% of screen width
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  const SizedBox(height: 10),
                                                  const Padding(
                                                    padding: EdgeInsets.all(8.0),
                                                    child: Text(
                                                      'Options',
                                                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 20, right: 20),
                                                    child: SizedBox(
                                                      height: 65,
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        onPressed: () {
                                                          Navigator.pop(context);
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder: (context) => const SettingsScreen()),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Settings',
                                                          style: TextStyle(fontSize: 24),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20), // Add some spacing between the buttons
                                                  Padding(
                                                    padding: const EdgeInsets.only(left: 20, right: 20),
                                                    child: SizedBox(
                                                      height: 65,
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        onPressed: () {
                                                          Navigator.pop(context);
                                                          ApiService.cancelPrint();
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
                                          Navigator.popUntil(context, ModalRoute.withName('/'));
                                        }
                                      : status!['status'] == 'Idle'
                                          ? () {
                                              Navigator.pop(context);
                                            }
                                          : () {
                                              if (status!['paused'] == true) {
                                                ApiService.resumePrint();
                                                setState(() {
                                                  isPausing = false;
                                                });
                                              } else {
                                                ApiService.pausePrint();
                                                setState(() {
                                                  isPausing = true;
                                                });
                                              }
                                            },
                          style: ElevatedButton.styleFrom(
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
                  ),
                ),
              ),
            );
          }
        }
      },
    );
  }
}
