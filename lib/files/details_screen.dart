/*
* Orion - Detail Screen
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

import 'dart:io';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:logging/logging.dart';
import 'package:orion/api_services/api_services.dart';
import 'package:orion/status/status_screen.dart';
import 'package:orion/util/sl1_thumbnail.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';

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
  DetailScreenState createState() => DetailScreenState();

  static bool _isDefaultDir(String dir) {
    return dir == '';
  }
}

class DetailScreenState extends State<DetailScreen> {
  final _logger = Logger('DetailScreen');
  final ApiService _api = ApiService();

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
      final fileDetails = await _api.getFileMetadata(
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
      String tempThumbnailPath = await ThumbnailUtil.extractThumbnail(
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
      _logger.severe('Failed to fetch file details', e);
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
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
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 300),
                                child: Card.outlined(
                                  elevation: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: AutoSizeText.rich(
                                      maxLines: 1,
                                      minFontSize: 16,
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: fileName.length >= 12
                                                ? '${fileName.substring(0, 12)}...'
                                                : fileName,
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
                  top: 20,
                ),
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        String subdirectory = widget.fileSubdirectory;
                        try {
                          _api.deleteFile(widget.fileLocation,
                              path.join(subdirectory, widget.fileName));
                        } catch (e) {
                          _logger.severe('Failed to delete file', e);
                        }
                        Navigator.pop(context);
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
                          try {
                            String subdirectory = widget.fileSubdirectory;
                            _api.startPrint(widget.fileLocation,
                                path.join(subdirectory, widget.fileName));
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const StatusScreen(
                                    newPrint: true,
                                  ),
                                ));
                          } catch (e) {
                            _logger.severe('Failed to start print', e);
                          }
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
                      onPressed: null,
                      // TODO: Add edit logic here
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
