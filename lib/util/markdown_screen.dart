import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MarkdownScreen extends StatelessWidget {
  final String filename;

  const MarkdownScreen({super.key, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(filename),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: FutureBuilder(
          future: rootBundle.loadString(filename),
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return Markdown(
                data: snapshot.data ?? '',
                styleSheet: Theme.of(context).brightness == Brightness.dark
                    ? MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        code: const TextStyle(
                          color: Colors.limeAccent,
                          backgroundColor: Colors.black,
                          fontFamily: 'monospace',
                        ),
                      )
                    : MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        code: const TextStyle(
                          color: Colors.deepPurple,
                          backgroundColor: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
              );
            } else {
              return const CircularProgressIndicator();
            }
          },
        ),
      ),
    );
  }
}
