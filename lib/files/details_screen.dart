import 'dart:convert';
import 'dart:io';
// ignore: unused_import
import 'dart:math';
import 'package:flutter/scheduler.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/util/orion_api_filesystem/orion_api_file.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ini/ini.dart';
import 'package:crypto/crypto.dart';

/*
 *    Orion Grid Files Screen
 *    Copyright (c) 2024 TheContrappostoShop (PaulGD03)
 *    GPLv3 Licensing (see LICENSE)
 */

class DetailScreen extends StatefulWidget {
  final String fileName;
  final String fileSubdirectory;
  final String fileLocation;

  const DetailScreen(
      {super.key,
      required this.fileName,
      required this.fileSubdirectory,
      required this.fileLocation});

  @override
  // ignore: library_private_types_in_public_api
  _DetailScreenState createState() => _DetailScreenState();

  static bool _isDefaultDir(String dir) {
    return dir == '/' || dir == '/uploads/';
  }

  static Future<String> extractThumbnail(
      String location, String subdirectory, String filename) async {
    try {
      String finalLocation = [
        (_isDefaultDir(subdirectory) ? '' : subdirectory),
        filename
      ].join(_isDefaultDir(subdirectory) ? '' : '/');
      final bytes = await ApiService.getFileThumbnail(location, finalLocation);

      final tempDir = await getTemporaryDirectory();
      final orionTmpDir = Directory('${tempDir.path}/oriontmp/$finalLocation');
      if (!await orionTmpDir.exists()) {
        await orionTmpDir.create(recursive: true);
      }

      final filePath = '${orionTmpDir.path}/thumbnail400x400.png';
      final outputFile = File(filePath);
      outputFile.writeAsBytesSync(bytes);

      // Check the total size of the oriontmp directory
      int totalSize = 0;
      final files = orionTmpDir.listSync(recursive: true);
      for (var file in files) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      // If the total size exceeds 100MB, delete the oldest files
      if (totalSize > 100 * 1024 * 1024) {
        files.sort(
            (a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        while (totalSize > 100 * 1024 * 1024 && files.isNotEmpty) {
          int fileSize = await (files.first as File).length();
          await files.first.delete();
          totalSize -= fileSize;
          files.removeAt(0);
        }
      }

      return filePath;
    } catch (e) {
      print('Failed to fetch thumbnail: $e');
    }

    return 'assets/images/placeholder.png';
  }

  static String generateHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}

class _DetailScreenState extends State<DetailScreen> {
  double leftPadding = 0;
  double rightPadding = 0;

  final GlobalKey textKey1 = GlobalKey();
  final GlobalKey textKey2 = GlobalKey();
  final GlobalKey textKey3 = GlobalKey();
  final GlobalKey textKey4 = GlobalKey();
  final GlobalKey textKey5 = GlobalKey();
  final GlobalKey textKey6 = GlobalKey();
  final GlobalKey previewKey = GlobalKey();

  FileStat? fileStat;
  String fileName = ''; // path.basename(widget.file.path)
  String layerHeight = ''; // layerHeight
  String fileSize = ''; // fileStat!.size
  String modifiedDate = ''; // fileCreationTimestamp
  String materialName = ''; // materialName
  String fileExtension = ''; // path.extension(widget.file.path)
  String thumbnailPath = ''; // extractThumbnail(widget.file, hash)
  String printTime = ''; // printTime
  double printTimeInSeconds = 0; // printTime in seconds
  String materialVolume = ''; // usedMaterial
  double materialVolumeInMilliliters = 0; // usedMaterial in milliliters

  late ValueNotifier<Future<String>> thumbnailFutureNotifier;
  Future<void>? _initFileDetailsFuture;
  double opacity = 0.0;

  @override
  void initState() {
    super.initState();
    _initFileDetailsFuture = _initFileDetails();
  }

  Future<void> _initFileDetails() async {
    try {
      final fileDetails = await ApiService.getFileMetadata(
        widget.fileLocation,
        [
          (DetailScreen._isDefaultDir(widget.fileSubdirectory)
              ? ''
              : widget.fileSubdirectory),
          widget.fileName
        ].join(DetailScreen._isDefaultDir(widget.fileSubdirectory) ? '' : '/'),
      );

      String tempFileName = fileDetails['file_data']['name'] ?? 'Placeholder';
      String tempFileSize =
          (fileDetails['file_data']['file_size'] / 1024 / 1024)
                  .toStringAsFixed(2) +
              ' MB'; // convert to MB
      String tempFileExtension = path.extension(tempFileName);
      String tempLayerHeight =
          '${fileDetails['layer_height'].toStringAsFixed(3)} mm';
      String tempModifiedDate = DateTime.fromMillisecondsSinceEpoch(
              fileDetails['file_data']['last_modified'] * 1000)
          .toString(); // convert to milliseconds
      String tempMaterialName =
          'N/A'; // this information is not provided by the API
      String tempThumbnailPath = await DetailScreen.extractThumbnail(
          widget.fileLocation,
          widget.fileSubdirectory,
          widget.fileName); // fetch thumbnail from API
      double tempPrintTimeInSeconds = fileDetails['print_time'];
      Duration printDuration =
          Duration(seconds: tempPrintTimeInSeconds.toInt());
      String tempPrintTime =
          '${printDuration.inHours.remainder(24).toString().padLeft(2, '0')}:${printDuration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${printDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
      double tempMaterialVolumeInMilliliters = fileDetails['used_material'];
      String tempMaterialVolume =
          '${tempMaterialVolumeInMilliliters.toStringAsFixed(2)} mL';

      setState(() {
        fileName = tempFileName;
        fileSize = tempFileSize;
        fileExtension = tempFileExtension;
        layerHeight = tempLayerHeight;
        modifiedDate = tempModifiedDate;
        materialName = tempMaterialName;
        thumbnailPath = tempThumbnailPath;
        printTimeInSeconds = tempPrintTimeInSeconds;
        printTime = tempPrintTime;
        materialVolumeInMilliliters = tempMaterialVolumeInMilliliters;
        materialVolume = tempMaterialVolume;
      });
    } catch (e) {
      print('Failed to fetch file details: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFileDetailsFuture,
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
          WidgetsBinding.instance!.addPostFrameCallback((_) {
            final keys = [
              textKey1,
              textKey2,
              textKey3,
              textKey4,
              textKey5,
              textKey6
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
              title: const Text('File Details'),
            ),
            body: Opacity(
              opacity: opacity,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(
                                  left: leftPadding <= 0
                                      ? leftPadding
                                      : leftPadding - 10),
                              child: Card.outlined(
                                elevation: 3,
                                child: Padding(
                                  padding: EdgeInsets.all(10),
                                  child: FittedBox(
                                    child: RichText(
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: fileName,
                                            style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary),
                                          ),
                                          TextSpan(
                                            text: ' - ',
                                            style: TextStyle(
                                                fontSize: 24,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary),
                                          ),
                                          TextSpan(
                                            text: fileSize,
                                            style: TextStyle(
                                                fontSize: 24,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary),
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
                              child: FittedBox(
                                child: Text(
                                  'Layer Height: $layerHeight',
                                  key: textKey2,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: leftPadding),
                              child: FittedBox(
                                child: Text(
                                  'Material: ${materialName.split('@0.')[0]}',
                                  key: textKey3,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: leftPadding),
                              child: FittedBox(
                                child: Text(
                                  'Print Time: $printTime',
                                  key: textKey4,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.only(left: leftPadding),
                              child: FittedBox(
                                child: Text(
                                  'Material Usage: $materialVolume',
                                  key: textKey5,
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(right: rightPadding),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              thumbnailPath.isNotEmpty
                                  ? Card(
                                      key: previewKey,
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.5),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(7.75),
                                          child: Image.file(
                                            File(thumbnailPath),
                                            width: 220,
                                            height: 220,
                                          ),
                                        ),
                                      ),
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
                                    ),
                            ],
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
                    ElevatedButton(
                      onPressed: () {
                        // Add your delete logic here
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(
                          120, // Subtract the padding on both sides
                          Theme.of(context).appBarTheme.toolbarHeight as double,
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Add your delete logic here
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(
                            0, // Subtract the padding on both sides
                            Theme.of(context).appBarTheme.toolbarHeight
                                as double,
                          ),
                        ),
                        child: const Text(
                          'Print',
                          style: TextStyle(fontSize: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: () {
                        // Add your delete logic here
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(
                          120, // Subtract the padding on both sides
                          Theme.of(context).appBarTheme.toolbarHeight as double,
                        ),
                      ),
                      child: const Text(
                        'Edit',
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      },
    );
  }
}
