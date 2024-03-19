import 'dart:convert';
import 'dart:io';
// ignore: unused_import
import 'dart:math';
import 'package:flutter/scheduler.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ini/ini.dart';
import 'package:crypto/crypto.dart';

class DetailScreen extends StatefulWidget {
  final File file;

  const DetailScreen({super.key, required this.file});

  @override
  // ignore: library_private_types_in_public_api
  _DetailScreenState createState() => _DetailScreenState();
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

  String generateHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  Future<String> extractThumbnail(File sl1File, String subfolder) async {
    try {
      final bytes = sl1File.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.name == 'thumbnail/thumbnail400x400.png') {
          final tempDir = await getTemporaryDirectory();
          final filePath =
              '${tempDir.path}/orionDevEnv/$subfolder/${file.name}';
          final outputFile = File(filePath);
          outputFile.createSync(recursive: true);
          outputFile.writeAsBytesSync(file.content as List<int>);
          return filePath;
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error extracting thumbnail.'),
        ),
      );
    }

    return 'assets/images/placeholder.png';
  }

  Future<String> parseSlicedFile(File sl1File, String key) async {
    try {
      final bytes = sl1File.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        if (file.name == 'config.ini') {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/${file.name}';
          final outputFile = File(filePath);
          outputFile.createSync(recursive: true);
          outputFile.writeAsBytesSync(file.content as List<int>);

          // Read the config.ini file as a string
          final configFileContent = outputFile.readAsStringSync();

          // Parse the config.ini file
          final config = Config.fromString(configFileContent);

          // Get the value of the key
          final requested = config.defaults()[key];

          return requested.toString();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error parsing sliced file.'),
        ),
      );
    }

    return 'Error parsing sliced file.';
  }

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

  Future<void> _initFileDetails() async {
    String hash = generateHash(widget.file.path);
    layerHeight = await parseSlicedFile(widget.file, 'layerHeight');
    modifiedDate = await parseSlicedFile(widget.file, 'fileCreationTimestamp');
    materialName = await parseSlicedFile(widget.file, 'materialName');
    thumbnailPath = await extractThumbnail(widget.file, hash);
    printTimeInSeconds =
        double.parse(await parseSlicedFile(widget.file, 'printTime'));
    Duration printDuration = Duration(seconds: printTimeInSeconds.toInt());
    printTime =
        '${printDuration.inHours.remainder(24).toString().padLeft(2, '0')}:${printDuration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${printDuration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    materialVolumeInMilliliters =
        double.parse(await parseSlicedFile(widget.file, 'usedMaterial'));
    materialVolume = '${materialVolumeInMilliliters.toStringAsFixed(2)} mL';
  }

  late ValueNotifier<Future<String>> thumbnailFutureNotifier;

  @override
  void initState() {
    super.initState();
    fileStat = widget.file.statSync();
    fileName = path.basename(widget.file.path);
    fileSize = fileStat!.size >= 1000000
        ? '${fileStat!.size ~/ 1000000} MB'
        : fileStat!.size >= 1000
            ? '${fileStat!.size ~/ 1000} KB'
            : '${fileStat!.size} B';
    fileExtension = path.extension(widget.file.path);
    _initFileDetails();
  }

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final keys = [textKey1, textKey2, textKey3, textKey4, textKey5, textKey6];
      double maxWidth = 0;

      for (var key in keys) {
        final width = key.currentContext?.size?.width ?? 0;
        if (width > maxWidth) {
          maxWidth = width;
        }
      }

      final screenWidth = MediaQuery.of(context)
          .size
          .width; // 200 placeholder, change to your image width.
      setState(() {
        leftPadding = (screenWidth - maxWidth - 200) / 3;
        if (leftPadding < 0) leftPadding = 0;
        rightPadding = leftPadding;
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('File Details | $modifiedDate'),
      ),
      body: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding:
                      EdgeInsets.only(left: leftPadding), // Add left padding
                  child: FittedBox(
                    child: Text(
                      fileName,
                      key: textKey1,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // ignore: unnecessary_null_comparison
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding:
                      EdgeInsets.only(left: leftPadding), // Add left padding
                  child: FittedBox(
                    // ignore: unnecessary_null_comparison
                    child: Text(
                      'File Size: $fileSize',
                      key: textKey2,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
              // ignore: unnecessary_null_comparison
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding:
                      EdgeInsets.only(left: leftPadding), // Add left padding
                  child: FittedBox(
                    child: Text(
                      'Layer Height: $layerHeight mm',
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
                  padding:
                      EdgeInsets.only(left: leftPadding), // Add left padding
                  child: FittedBox(
                    child: Text(
                      'Material: ${materialName.split('@0.')[0]}',
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
                  padding:
                      EdgeInsets.only(left: leftPadding), // Add left padding
                  child: FittedBox(
                    child: Text(
                      'Estimated Time: $printTime',
                      key: textKey5,
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
                      'Estimated Material: $materialVolume',
                      key: textKey6,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kToolbarHeight * 0.4),
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
                      ? Image.file(
                          File(thumbnailPath),
                          width: 200,
                          height: 200,
                        )
                      : const Image(
                          image: AssetImage('assets/images/placeholder.png'),
                          width: 200,
                          height: 200,
                        ),
                  const SizedBox(height: kToolbarHeight * 0.4),
                ],
              ),
            ),
          )
        ],
      ),
      bottomNavigationBar: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Add your print logic here
              },
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color>(
                  (Set<MaterialState> states) {
                    if (states.contains(MaterialState.hovered) &&
                        fileExtension != '.sl1') {
                      return Colors.transparent;
                    }
                    return Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.08); // default color
                  },
                ),
                minimumSize: MaterialStateProperty.all<Size>(
                    const Size(double.infinity, kToolbarHeight * 1.2)),
                shape: MaterialStateProperty.all<OutlinedBorder>(
                    const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)),
              ),
              child: Text(
                'Print',
                style: TextStyle(
                    fontSize: 20,
                    color: fileExtension == '.sl1'
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey),
              ),
            ),
          ),
          SizedBox(
            height: kToolbarHeight,
            child: VerticalDivider(
              width: 2,
              color: Theme.of(context).primaryColor,
            ),
          ),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Add your delete logic here
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, kToolbarHeight * 1.2),
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
