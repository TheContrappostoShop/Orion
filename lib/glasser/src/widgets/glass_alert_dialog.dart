/*
* Glasser - Glass Alert Dialog Widget
* Copyright (C) 2025 Open Resin Alliance
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../util/providers/theme_provider.dart';
import '../constants.dart';
import '../glass_effect.dart';
import 'glass_button.dart';
import '../platform_config.dart';

/// An alert dialog that automatically becomes glassmorphic when the glass theme is active.
///
/// This widget is a drop-in replacement for [AlertDialog]. When the glass theme is enabled,
/// it renders with a glassmorphic effect for visual consistency. Otherwise, it falls back to a normal alert dialog.
///
/// Example usage:
/// ```dart
/// GlassAlertDialog(
///   title: Text('Alert'),
///   content: Text('Are you sure?'),
///   actions: [TextButton(onPressed: () {}, child: Text('OK'))],
/// )
/// ```
///
/// See also:
///
///  * [GlassDialog], for a more generic glass dialog.
///  * [AlertDialog], the standard Flutter alert dialog.
class GlassAlertDialog extends StatelessWidget {
  /// An alert dialog that automatically becomes glassmorphic when the glass theme is active.
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry titlePadding;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry actionsPadding;

  const GlassAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.titlePadding = const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
    this.contentPadding = const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 24.0),
    this.actionsPadding = const EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 16.0),
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final borderRadius = BorderRadius.circular(glassCornerRadius);
    final dialogConstraints = BoxConstraints(
      minWidth: 280,
      maxWidth: MediaQuery.of(context).size.width * 0.8,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
    );

    if (!themeProvider.isGlassTheme) {
      return Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        child: ConstrainedBox(
          constraints: dialogConstraints,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.28),
                width: 1.2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Padding(
                    padding: titlePadding,
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: 'AtkinsonHyperlegible',
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      child: title!,
                    ),
                  ),
                if (content != null)
                  Flexible(
                    child: Padding(
                      padding: contentPadding,
                      child: DefaultTextStyle(
                        style: TextStyle(
                          fontFamily: 'AtkinsonHyperlegible',
                          fontSize: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.84),
                          height: 1.45,
                        ),
                        child: content!,
                      ),
                    ),
                  ),
                if (actions != null && actions!.isNotEmpty)
                  Padding(
                    padding: actionsPadding,
                    child: Row(
                      children: actions!.asMap().entries.map((entry) {
                        final index = entry.key;
                        final action = entry.value;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: index == 0 ? 0 : 6,
                              right: index == actions!.length - 1 ? 0 : 6,
                            ),
                            child: _buildActionButton(action),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final fillOpacity =
        GlassPlatformConfig.surfaceOpacity(0.12, emphasize: true);
    final shadow = GlassPlatformConfig.surfaceShadow(
      blurRadius: 26,
      yOffset: 12,
      alpha: 0.24,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
      child: ConstrainedBox(
        constraints: dialogConstraints,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: shadow,
              ),
              child: GlassEffect(
                borderRadius: borderRadius,
                sigma: glassBlurSigma,
                opacity: fillOpacity,
                floatingSurface: true,
                borderWidth: 1.6,
                emphasizeBorder: true,
                interactiveSurface: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null)
                      Padding(
                        padding: titlePadding,
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            fontFamily: 'AtkinsonHyperlegible',
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          child: title!,
                        ),
                      ),
                    if (content != null)
                      Flexible(
                        child: Padding(
                          padding: contentPadding,
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              fontFamily: 'AtkinsonHyperlegible',
                              fontSize: 20,
                              color: Colors.white70,
                              height: 1.45,
                            ),
                            child: content!,
                          ),
                        ),
                      ),
                    if (actions != null && actions!.isNotEmpty)
                      Padding(
                        padding: actionsPadding,
                        child: Row(
                          children: actions!.asMap().entries.map((entry) {
                            final index = entry.key;
                            final action = entry.value;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: index == 0 ? 0 : 6,
                                  right: index == actions!.length - 1 ? 0 : 6,
                                ),
                                child: _buildActionButton(action),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildActionButton(Widget child) {
  if (child is GlassButton) {
    return child;
  }

  if (child is TextButton) {
    final textButton = child;
    final buttonLabel = _extractButtonLabel(textButton.child);
    final tint = _resolveButtonTint(buttonLabel);

    return GlassButton(
      tint: tint,
      onPressed: textButton.onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 60),
      ),
      child: _buildButtonContentWithIcon(
        textButton.child ?? const SizedBox.shrink(),
      ),
    );
  }

  return child;
}

/// Helper function to add icons to button content based on text
Widget _buildButtonContentWithIcon(Widget originalChild) {
  if (originalChild is Text) {
    final text = originalChild.data?.toLowerCase() ?? '';

    IconData? icon;

    // Map common button text to icons
    if (text.contains('cancel') ||
        text.contains('close') ||
        text.contains('later')) {
      icon = Icons.close;
    } else if (text.contains('confirm') ||
        text.contains('ok') ||
        text.contains('set') ||
        text.contains('save') ||
        text.contains('now')) {
      icon = Icons.check;
    } else if (text.contains('delete')) {
      icon = Icons.delete_outline;
    } else if (text.contains('disconnect')) {
      icon = Icons.wifi_off;
    } else if (text.contains('connect')) {
      icon = Icons.wifi;
    } else if (text.contains('skip')) {
      icon = Icons.skip_next;
    } else if (text.contains('stay')) {
      icon = Icons.stay_current_portrait;
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(originalChild.data ?? ''),
        ],
      );
    }
  }

  return originalChild;
}

String _extractButtonLabel(Widget? child) {
  if (child is Text) {
    return child.data?.toLowerCase().trim() ?? '';
  }

  return '';
}

GlassButtonTint _resolveButtonTint(String label) {
  if (label.contains('delete') ||
      label.contains('remove') ||
      label.contains('disconnect') ||
      label.contains('forget')) {
    return GlassButtonTint.negative;
  }

  if (label.contains('save') ||
      label.contains('confirm') ||
      label.contains('ok') ||
      label.contains('yes') ||
      label.contains('now') ||
      label.contains('connect') ||
      label.contains('apply') ||
      label.contains('update')) {
    return GlassButtonTint.positive;
  }

  if (label.contains('later') ||
      label.contains('cancel') ||
      label.contains('close') ||
      label.contains('back') ||
      label.contains('stay') ||
      label.contains('skip')) {
    return GlassButtonTint.neutral;
  }

  return GlassButtonTint.none;
}
