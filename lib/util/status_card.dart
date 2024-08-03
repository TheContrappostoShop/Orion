/*
* Orion - Status Card
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

class StatusCard extends StatefulWidget {
  final bool isCanceling;
  final bool isPausing;
  final double progress;
  final Color statusColor;
  final Map<String, dynamic> status;

  const StatusCard(
      {super.key,
      required this.isCanceling,
      required this.isPausing,
      required this.progress,
      required this.statusColor,
      required this.status});

  @override
  StatusCardState createState() => StatusCardState();
}

class StatusCardState extends State<StatusCard> {
  Icon cardIcon = const Icon(Icons.help);

  @override
  Widget build(BuildContext context) {
    if (widget.status['status'] == 'Idle' && widget.status['layer'] != null) {
      cardIcon = const Icon(Icons.check);
    } else if (widget.isCanceling || widget.status['layer'] == null) {
      cardIcon = const Icon(Icons.stop);
    } else if (widget.isPausing || widget.status['paused'] == true) {
      cardIcon = const Icon(Icons.pause);
    }

    // While pausing or canceling, show a spinning circle.
    // When paused, show current print progress.
    // When canceled, show a full circle.
    final circleProgress =
        (widget.isPausing && widget.status['paused'] != true) ||
                (widget.isCanceling && widget.status['layer'] != null)
            ? null
            : widget.progress;

    // If the print is active, not paused, canceled or finished, it is active.
    final isActive = (widget.isPausing == false &&
        widget.isCanceling == false &&
        widget.status['layer'] != null &&
        widget.status['paused'] != true &&
        widget.status['status'] != 'Idle');

    // While the print is active, show the progress in percentage. (overlapping text for outline effect)
    return isActive
        ? Stack(
            children: <Widget>[
              Text(
                '${(widget.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 75,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 5
                    ..color = Theme.of(context).colorScheme.primaryContainer,
                ),
              ),
              Text(
                '${(widget.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 75,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          )
        : Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        value: circleProgress,
                        strokeWidth: 6,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(widget.statusColor),
                        backgroundColor: widget.statusColor.withOpacity(0.5),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(25),
                    child: Icon(
                      cardIcon.icon,
                      color: widget.statusColor,
                      size: 70,
                    ),
                  )
                ],
              ),
            ),
          );
  }
}
