import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:flutter/scheduler.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';

class DetailScreen extends StatefulWidget {
  final File file;

  const DetailScreen({Key? key, required this.file}) : super(key: key);

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

  @override
  Widget build(BuildContext context) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final keys = [textKey1, textKey2, textKey3, textKey4, textKey5];
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
        rightPadding = leftPadding;
      });
    });

    final FileStat fileStat = widget.file.statSync();
    final String fileName = path.basename(widget.file.path);
    final String fileExtension = path.extension(widget.file.path);
    final String fileSize = '${fileStat.size} bytes';
    final String creationDate = fileStat.changed.toString().substring(0, 19);
    final String modifiedDate = fileStat.modified.toString().substring(0, 19);

    Future<String> extractThumbnail(File sl1File) async {
      try {
        final bytes = sl1File.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        for (final file in archive) {
          if (file.name == 'thumbnail/thumbnail400x400.png') {
            final tempDir = await getTemporaryDirectory();
            final filePath = '${tempDir.path}/${file.name}';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Details'),
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
              if (fileExtension.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding:
                        EdgeInsets.only(left: leftPadding), // Add left padding
                    child: FittedBox(
                      // ignore: unnecessary_null_comparison
                      child: Text(
                        'File Extension: $fileExtension',
                        key: textKey2,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              // ignore: unnecessary_null_comparison
              if (fileExtension.isNotEmpty) const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding:
                      EdgeInsets.only(left: leftPadding), // Add left padding
                  child: FittedBox(
                    child: Text(
                      'File Size: $fileSize',
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
                      'Creation Date: $creationDate',
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
                      'Modified Date: $modifiedDate',
                      key: textKey5,
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
                  FutureBuilder<String>(
                    future: extractThumbnail(widget.file),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.file(
                          File(snapshot.data!),
                          width: 200,
                          height: 200,
                        );
                      } else {
                        return const Image(
                          image: AssetImage('assets/images/placeholder.png'),
                          width: 200,
                          height: 200,
                        );
                      }
                    },
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
