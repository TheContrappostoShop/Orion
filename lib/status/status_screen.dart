import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/files/details_screen.dart';
import 'package:orion/home/home_screen.dart';
import 'package:orion/settings/settings_screen.dart';
import 'package:orion/themes/themes.dart';

/*
 *    Orion Status Screen
 *    Copyright (c) 2024 TheContrappostoShop (PaulGD03)
 *    GPLv3 Licensing (see LICENSE)
 */

class StatusScreen extends StatefulWidget {
  final bool newPrint;
  const StatusScreen({super.key, required this.newPrint});

  @override
  StatusScreenState createState() => StatusScreenState();
}

class StatusScreenState extends State<StatusScreen> {
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
    timer =
        Timer.periodic(const Duration(seconds: 1), (Timer t) => getStatus());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> getStatus() async {
    try {
      status = await ApiService.getStatus();
      if (status!['status'] == 'Printing' || status!['status'] == 'Idle') {
        if (status!['print_data'] != null &&
            status!['print_data']['file_data'] != null) {
          String? thumbnailFullPath =
              status!['print_data']['file_data']['path'];
          String? fileName = status!['print_data']['file_data']['name'];
          String location = status!['print_data']['file_data']
                  ['location_category'] ??
              'Local';
          if (thumbnailFullPath != null && fileName != null) {
            String thumbnailSubdir = thumbnailFullPath.split('/').first;
            // If we are in the home directory, the thumbnailSubdir will be the file name.
            // Therefore, change it to / manually.
            if (thumbnailSubdir.endsWith('.sl1')) thumbnailSubdir = '/';
            thumbnailNotifier.value = await DetailScreen.extractThumbnail(
              location,
              thumbnailSubdir,
              fileName,
            );
          }
        } else {
          thumbnailNotifier.value = null;
        }
      } else {
        thumbnailNotifier.value = null;
      }
      setState(() {});
    } catch (e) {
      //('Failed to get status: $e');
    }
  }

  Color getStatusColor() {
    final Map<String, Color> statusColor = {
      'Printing': Theme.of(context).colorScheme.primary,
      'Idle': Colors.greenAccent,
      'Shutdown': Colors.red,
      'Canceled': Colors.red,
      'Pause': Colors.orange,
      'Curing':
          Theme.of(context).colorScheme.primaryContainer.withBrightness(1.7),
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
          if (status!['print_data'] == null) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Loading...'),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          } else if (newPrintNotifier.value == true &&
              (status == null || status!['status'] != 'Printing')) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Loading...'),
              ),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            );
          } else {
            if (status!['status'] == 'Printing') {
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
                opacity =
                    1.0; // Set opacity to 1 after sizes have been calculated
              });
            });

            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: const Text('Print Status'),
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
                            if (status!['status'] == 'Printing' ||
                                status!['status'] == 'Idle') ...[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                      left: leftPadding <= 0
                                          ? leftPadding
                                          : leftPadding - 10),
                                  child: Card.outlined(
                                    elevation: 1,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: FittedBox(
                                        child: RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text:
                                                    '${status!['print_data']['file_data']['name']}',
                                                style: TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color: getStatusColor()),
                                              ),
                                              TextSpan(
                                                text: ' - ',
                                                style: TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color: getStatusColor()),
                                              ),
                                              TextSpan(
                                                text: isCanceling &&
                                                        status!['layer'] != null
                                                    ? 'Canceling...'
                                                    : status!['layer'] == null
                                                        ? 'Canceled'
                                                        : isPausing == true &&
                                                                status!['paused'] ==
                                                                    false
                                                            ? 'Pausing...'
                                                            : status!['paused'] ==
                                                                    true
                                                                ? 'Paused'
                                                                : status!['status'] ==
                                                                        'Idle'
                                                                    ? 'Finished'
                                                                    : '${status!['status']}',
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
                                    'Layer: ${status!['layer']} of ${status!['print_data']['layer_count']}',
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
                                    'Print Time: ${status!['print_data']['print_time']}',
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
                                    'Material: ${(status!['print_data']['used_material'] as double).toStringAsFixed(3)} mL',
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
                              builder: (BuildContext context, String? thumbnail,
                                  Widget? child) {
                                double progress = 0.0;
                                if (status!['layer'] != null &&
                                    status!['print_data']['layer_count'] !=
                                        null) {
                                  progress = status!['layer'] /
                                      status!['print_data']['layer_count'];
                                }
                                return thumbnail != null
                                    ? Stack(
                                        children: [
                                          Card(
                                            key: previewKey,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(4.5),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(7.75),
                                                child: Image.file(
                                                  File(thumbnail),
                                                  width: 220,
                                                  height: 220,
                                                  color: Colors.black,
                                                  colorBlendMode:
                                                      BlendMode.saturation,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Card(
                                            //key: previewKey,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(4.5),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(7.75),
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
                                                        gradient:
                                                            LinearGradient(
                                                          begin: Alignment
                                                              .bottomCenter,
                                                          end: Alignment
                                                              .topCenter,
                                                          colors: [
                                                            Colors.transparent,
                                                            Colors.black
                                                                .withOpacity(
                                                                    0.3),
                                                          ],
                                                          stops: [
                                                            progress,
                                                            progress
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      top: 0,
                                                      bottom: 0,
                                                      left: 0,
                                                      right: 0,
                                                      child: Center(
                                                        child: Stack(
                                                          children: <Widget>[
                                                            // Stroked text to act as an outline
                                                            Text(
                                                              '${(progress * 100).toStringAsFixed(0)}%',
                                                              style: TextStyle(
                                                                fontSize: 32,
                                                                foreground:
                                                                    Paint()
                                                                      ..style =
                                                                          PaintingStyle
                                                                              .stroke
                                                                      ..strokeWidth =
                                                                          3
                                                                      ..color = Theme.of(
                                                                              context)
                                                                          .colorScheme
                                                                          .primaryContainer,
                                                              ),
                                                            ),
                                                            // Solid text as fill.
                                                            Text(
                                                              '${(progress * 100).toStringAsFixed(0)}%',
                                                              style: TextStyle(
                                                                fontSize: 32,
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .primary,
                                                              ),
                                                            ),
                                                          ],
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
                                            borderRadius:
                                                BorderRadius.circular(7.75),
                                            child: const Image(
                                              image: AssetImage(
                                                  'assets/images/placeholder.png'),
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
                          onPressed: isCanceling == true &&
                                  status!['layer'] != null
                              ? null
                              : status!['layer'] == null
                                  ? null
                                  : () {
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return Dialog(
                                            child: SizedBox(
                                              width: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.8, // 80% of screen width
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  const SizedBox(height: 10),
                                                  const Padding(
                                                    padding:
                                                        EdgeInsets.all(8.0),
                                                    child: Text(
                                                      'Options',
                                                      style: TextStyle(
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            left: 20,
                                                            right: 20),
                                                    child: SizedBox(
                                                      height: 65,
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        onPressed: () {
                                                          Navigator.pop(
                                                              context);
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                                builder:
                                                                    (context) =>
                                                                        const SettingsScreen()),
                                                          );
                                                        },
                                                        child: const Text(
                                                          'Settings',
                                                          style: TextStyle(
                                                              fontSize: 24),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      height:
                                                          40), // Add some spacing between the buttons
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            left: 20,
                                                            right: 20),
                                                    child: SizedBox(
                                                      height: 65,
                                                      width: double.infinity,
                                                      child: ElevatedButton(
                                                        onPressed: () {
                                                          Navigator.pop(
                                                              context);
                                                          ApiService
                                                              .cancelPrint();
                                                          setState(() {
                                                            isCanceling = true;
                                                          });
                                                        },
                                                        child: const Text(
                                                          'Cancel Print',
                                                          style: TextStyle(
                                                              fontSize: 24),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 30),
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                    },
                                                    child: const Text(
                                                      'Close',
                                                      style: TextStyle(
                                                          fontSize: 20),
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
                              Theme.of(context).appBarTheme.toolbarHeight
                                  as double,
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
                          onPressed: isCanceling == true &&
                                  status!['layer'] != null
                              ? null
                              : isPausing == true && status!['paused'] == false
                                  ? null
                                  : status!['layer'] == null
                                      ? () {
                                          Navigator.pop(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) =>
                                                    const HomeScreen(),
                                              ));
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
                              Theme.of(context).appBarTheme.toolbarHeight
                                  as double,
                            ),
                          ),
                          child: Text(
                            status!['layer'] == null
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
