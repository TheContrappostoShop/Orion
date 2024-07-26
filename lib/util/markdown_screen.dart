/*
* Orion - Markdown Screen
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MarkdownScreen extends StatelessWidget {
  final String? filename;
  final String? changelog;

  const MarkdownScreen({super.key, this.filename, this.changelog});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(filename ?? 'Changelog'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: changelog != null
            ? Markdown(
                data: changelog!,
                styleSheet: _getMarkdownStyleSheet(context),
              )
            : FutureBuilder(
                future: rootBundle.loadString(filename!),
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    return Markdown(
                      data: snapshot.data ?? '',
                      styleSheet: _getMarkdownStyleSheet(context),
                    );
                  } else {
                    return const CircularProgressIndicator();
                  }
                },
              ),
      ),
    );
  }

  MarkdownStyleSheet _getMarkdownStyleSheet(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
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
          );
  }
}
