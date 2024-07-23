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
import 'package:orion/util/hold_button.dart';
import 'package:orion/util/sl1_thumbnail.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';

class DetailScreen extends StatefulWidget {
  final String fileName;
  final String fileSubdirectory;
  final String fileLocation;

  const DetailScreen({
    super.key,
    required this.fileName,
    required this.fileSubdirectory,
    required this.fileLocation,
  });

  @override
  DetailScreenState createState() => DetailScreenState();

  static bool _isDefaultDir(String dir) {
    return dir == '';
  }
}

class DetailScreenState extends State<DetailScreen> {
  final _logger = Logger('DetailScreen');
  final ApiService _api = ApiService();

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
  // ignore: unused_field
  Future<void>? _initFileDetailsFuture;

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
          widget.fileLocation, widget.fileSubdirectory, widget.fileName,
          size: 'Large'); // fetch thumbnail from API
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
    bool isLandScape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Details'),
        centerTitle: true,
      ),
      body: Center(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return isLandScape
                ? Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                    child: buildLandscapeLayout(context))
                : Padding(
                    padding:
                        const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                    child: buildPortraitLayout(context));
          },
        ),
      ),
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
                    buildThumbnailView(context),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: buildInfoCard('Layer Height', layerHeight),
                        ),
                        Expanded(
                          child: buildInfoCard('Material & Volume',
                              '$materialName - $materialVolume'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(children: [
                      Expanded(
                        child: buildInfoCard('Print Time', printTime),
                      ),
                      Expanded(
                        child: buildInfoCard('File Size', fileSize),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    buildInfoCard('Modified Date', modifiedDate),
                    const Spacer(),
                    buildPrintButtons(),
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
                    buildInfoCard('Layer Height', layerHeight),
                    buildInfoCard(
                        'Material & Volume', '$materialName - $materialVolume'),
                    buildInfoCard('Print Time', printTime),
                    buildInfoCard('Modified Date', modifiedDate),
                    buildInfoCard('File Size', fileSize),
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
          padding: const EdgeInsets.only(left: 5.0, right: 5.0),
          child: buildPrintButtons(),
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
                text: fileName.length >= 12
                    ? '${fileName.substring(0, 12)}...'
                    : fileName,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildThumbnailView(BuildContext context) {
    return Center(
      child: Card.outlined(
        elevation: 1.0,
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7.75),
            child: thumbnailPath.isNotEmpty
                ? Image.file(File(thumbnailPath))
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget buildPrintButtons() {
    return Row(
      children: [
        HoldButton(
          onPressed: () {
            String subdirectory = widget.fileSubdirectory;
            try {
              _api.deleteFile(widget.fileLocation,
                  path.join(subdirectory, widget.fileName));
              _logger.info('File deleted successfully');
              Navigator.pop(context, true);
            } catch (e) {
              _logger.severe('Failed to delete file', e);
              Navigator.pop(context, false);
            }
          },
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            minimumSize: Size(
              0,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              minimumSize: Size(
                0, // Subtract the padding on both sides
                Theme.of(context).appBarTheme.toolbarHeight as double,
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
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
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
    );
  }
}
