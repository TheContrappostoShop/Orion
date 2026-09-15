/*
* Glasser - Glass Button Widget
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
import 'package:orion/util/providers/theme_provider.dart';
import '../constants.dart';
import '../glass_effect.dart';
import '../platform_config.dart';

/// Available tint accents for [GlassButton].
enum GlassButtonTint {
  /// No tint, keeps the default styling for both glass and non-glass themes.
  none,

  /// Positive accent, rendered with a green emphasis.
  positive,

  /// Neutral accent that uses the current theme primary color.
  neutral,

  /// Warning accent, rendered with an orange emphasis.
  warn,

  /// Cold accent, rendered with a blue emphasis.
  cold,

  /// Negative accent, rendered with a red emphasis.
  negative,
}

/// A button that automatically becomes glassmorphic when the glass theme is active.
///
/// This widget is a drop-in replacement for [ElevatedButton]. When the glass theme is enabled,
/// it renders with a glassmorphic effect for visual consistency. Otherwise, it falls back to a normal button.
///
/// Example usage:
/// ```dart
/// GlassButton(
///   onPressed: () {},
///   child: Text('OK'),
/// )
/// ```
///
/// See also:
///
///  * [GlassScaffold], for glass-aware scaffolds.
///  * [ElevatedButton], the standard Flutter button.
class GlassButton extends StatelessWidget {
  /// A button that automatically becomes glassmorphic when the glass theme is active.
  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final bool wantIcon;
  final GlassButtonTint tint;
  final EdgeInsetsGeometry? margin;

  const GlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.style,
    this.wantIcon = false,
    this.tint = GlassButtonTint.none,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    // If the button is disabled, force no tint so disabled buttons keep
    // the neutral / muted appearance.
    final effectiveTint = (onPressed == null) ? GlassButtonTint.none : tint;
    // Resolve palette; neutral needs the theme primary so use context-aware resolver.
    final tintPalette = _resolveTintPaletteWithContext(effectiveTint, context);
    final baseMaterialStyle =
        _baseNonGlassButtonStyle(context, tintColor: tintPalette?.color);
    final resolvedMaterialStyle =
        baseMaterialStyle.merge(tintPalette?.toButtonStyle()).merge(style);

    if (!themeProvider.isGlassTheme) {
      return Padding(
        padding: margin ?? const EdgeInsets.all(0.0),
        child: ElevatedButton(
          onPressed: onPressed,
          style: resolvedMaterialStyle,
          child: child,
        ),
      );
    }

    return _GlassmorphicButton(
      onPressed: onPressed,
      style: style,
      wantIcon: wantIcon,
      tintPalette: tintPalette, // Pass the wantIcon parameter
      margin: margin,
      child: child,
    );
  }
}

ButtonStyle _baseNonGlassButtonStyle(BuildContext context, {Color? tintColor}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  // For untinted buttons, use the seed primary as the outline tint so
  // the border matches the text/icon color the theme already applies.
  // The fill uses a plain surface elevation (white overlay) regardless of tint,
  // keeping the inside neutral like card.outlined.
  final effectiveTint = tintColor ?? theme.colorScheme.primary;

  final neutralFill = Color.alphaBlend(
    Colors.white.withValues(alpha: isDark ? 0.05 : 0.018),
    theme.colorScheme.surface,
  );

  final tintedFill = tintColor != null
      ? Color.alphaBlend(
          tintColor.withValues(alpha: isDark ? 0.14 : 0.07),
          theme.colorScheme.surface,
        )
      : neutralFill;

  final disabledFill = Color.alphaBlend(
    Colors.white.withValues(alpha: isDark ? 0.025 : 0.01),
    theme.colorScheme.surface,
  );

  final outlineColor = effectiveTint;
  final baseTextStyle =
      (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontFamily: 'AtkinsonHyperlegible',
    fontSize: 21,
    fontWeight: FontWeight.w500,
  );

  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return disabledFill;
      }
      return tintedFill;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      final isDisabled = states.contains(WidgetState.disabled);
      final outlineAlpha = isDisabled ? 0.12 : 0.22;
      return BorderSide(
        color: outlineColor.withValues(alpha: outlineAlpha),
        width: 1.2,
      );
    }),
    shape: WidgetStateProperty.all(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(glassCornerRadius),
      ),
    ),
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return 0.5;
      if (states.contains(WidgetState.pressed)) return 0.5;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return 1.8;
      }
      return 1.2;
    }),
    shadowColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return Colors.black.withValues(alpha: 0.06);
      }
      return Colors.black.withValues(alpha: isDark ? 0.2 : 0.12);
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return theme.colorScheme.onSurface.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return theme.colorScheme.onSurface.withValues(alpha: 0.04);
      }
      return null;
    }),
    textStyle: WidgetStateProperty.all(baseTextStyle),
    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
  );
}

/// Internal glassmorphic button implementation
class _GlassmorphicButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final ButtonStyle? style;
  final bool wantIcon;
  final _GlassButtonTintPalette? tintPalette;
  final EdgeInsetsGeometry? margin;

  const _GlassmorphicButton({
    required this.child,
    required this.onPressed,
    this.style,
    this.wantIcon = true,
    this.tintPalette,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    // Extract size constraints from style if provided
    Size? minimumSize;
    Size? maximumSize;

    if (style != null) {
      minimumSize = style!.minimumSize?.resolve({});
      maximumSize = style!.maximumSize?.resolve({});
    }

    final isEnabled = onPressed != null;

    // Detect if the button is a circle (CircleBorder)
    final isCircle = style?.shape?.resolve({}) is CircleBorder;
    final borderRadius =
        BorderRadius.circular(isCircle ? 30 : glassCornerRadius);
    final palette = tintPalette;
    final hasTint = palette != null;
    final tintColor = palette?.color;

    GlassPlatformConfig.surfaceOpacity(
      isEnabled ? 0.14 : 0.1,
      emphasize: isEnabled,
    );

    Color? blendedFillColor;
    if (hasTint) {
      // Blend a low-opacity tint over white. Use alphaBlend so the result
      // keeps white highlights while adding color.
      blendedFillColor =
          Color.alphaBlend(tintColor!.withValues(alpha: 0.75), Colors.white);
    }

    final shadow = GlassPlatformConfig.interactiveShadow(
      enabled: isEnabled,
      blurRadius: isCircle ? 18 : 16,
      yOffset: isCircle ? 4 : 3,
      alpha: 0.14,
    );

    Widget buttonChild = Container(
      margin: margin ?? const EdgeInsets.all(0.0),
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow,
      ),
      child: GlassEffect(
        borderRadius: borderRadius,
        sigma: glassBlurSigma,
        opacity: GlassPlatformConfig.surfaceOpacity(
          0.12,
          emphasize: isEnabled,
        ),
        // Provide a subtle tinted white base when a tint is requested so the
        // control remains frosted but carries semantic color.
        color: blendedFillColor,
        // Tone down the outline brightness so tinted buttons aren't too
        // aggressive. We still bypass platform adjustments for tinted buttons
        // but use a reduced alpha for a softer outline.
        borderWidth: 1.5,
        emphasizeBorder: isEnabled,
        borderColor: hasTint ? tintColor : null,
        borderAlpha: hasTint ? 0.45 : 0.2,
        useRawBorderAlpha: hasTint,
        interactiveSurface: true,
        floatingSurface: false,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onPressed,
            splashColor: isEnabled
                ? (hasTint
                    ? tintColor!.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.2))
                : null,
            highlightColor: isEnabled
                ? (hasTint
                    ? tintColor!.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.1))
                : null,
            child: Opacity(
              opacity: isEnabled ? 1.0 : 0.4,
              child: Padding(
                padding: isCircle
                    ? const EdgeInsets.all(0)
                    : const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 8.0),
                child: Center(
                  child: _buildTintAwareContent(
                    _buildButtonContentWithIcon(child, wantIcon: wantIcon),
                    palette,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Apply size constraints if specified, or use default
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: ((minimumSize?.width ?? 20) - 5).clamp(0.0, double.infinity),
        minHeight: ((minimumSize?.height ?? 5) - 5).clamp(0.0, double.infinity),
        maxWidth: (maximumSize?.width ?? double.infinity) - 5,
        maxHeight: (maximumSize?.height ?? double.infinity) - 5,
      ),
      child: buttonChild,
    );
  }
}

/// Helper function to add icons to button content based on text
Widget _buildButtonContentWithIcon(Widget originalChild,
    {required bool wantIcon}) {
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

    if (!wantIcon) {
      // If we don't want an icon, just return the original text
      return originalChild;
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

Widget _buildTintAwareContent(
  Widget content,
  _GlassButtonTintPalette? palette,
) {
  if (palette == null) {
    return content;
  }

  return IconTheme(
    data: IconThemeData(color: palette.glassForeground),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: palette.glassForeground),
      child: content,
    ),
  );
}

_GlassButtonTintPalette? _resolveTintPalette(GlassButtonTint tint) {
  switch (tint) {
    case GlassButtonTint.none:
      return null;
    case GlassButtonTint.positive:
      return const _GlassButtonTintPalette(
        color: Colors.greenAccent,
        materialForeground: Colors.white,
        glassForeground: Colors.greenAccent,
      );
    case GlassButtonTint.warn:
      return const _GlassButtonTintPalette(
        color: Colors.orangeAccent,
        materialForeground: Colors.white,
        glassForeground: Colors.orangeAccent,
      );
    case GlassButtonTint.cold:
      return const _GlassButtonTintPalette(
        color: Colors.lightBlueAccent,
        materialForeground: Colors.white,
        glassForeground: Colors.lightBlueAccent,
      );
    case GlassButtonTint.neutral:
      // neutral uses theme primary; we'll resolve a placeholder here but
      // callers should call the context-aware resolver below.
      return const _GlassButtonTintPalette(
        color: Colors.black,
        materialForeground: Colors.white,
        glassForeground: Colors.black,
      );
    case GlassButtonTint.negative:
      return const _GlassButtonTintPalette(
        color: Colors.redAccent,
        materialForeground: Colors.white,
        glassForeground: Colors.redAccent,
      );
  }
}

_GlassButtonTintPalette? _resolveTintPaletteWithContext(
    GlassButtonTint tint, BuildContext context) {
  if (tint == GlassButtonTint.neutral) {
    final primary = Theme.of(context).colorScheme.primary;
    return _GlassButtonTintPalette(
      color: primary,
      materialForeground: Colors.white,
      glassForeground: primary,
    );
  }

  return _resolveTintPalette(tint);
}

class _GlassButtonTintPalette {
  final Color color;

  /// Foreground color to use for non-glass (material) buttons - usually a
  /// high-contrast value like white.
  final Color materialForeground;

  /// Foreground color to use for glass buttons: full tint color so the text
  /// and icons match the outline.
  final Color glassForeground;

  const _GlassButtonTintPalette({
    required this.color,
    required this.materialForeground,
    required this.glassForeground,
  });

  ButtonStyle toButtonStyle() {
    return ButtonStyle(
      // Foreground (text/icon) should be full tint color for punchiness.
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return color.withValues(alpha: 0.6);
        }
        return color;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return color.withValues(alpha: 0.6);
        }
        return color;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return color.withValues(alpha: 0.22);
        }
        if (states.contains(WidgetState.focused) ||
            states.contains(WidgetState.hovered)) {
          return color.withValues(alpha: 0.12);
        }
        return null;
      }),
      surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
      shadowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.black.withValues(alpha: 0.08);
        }
        return Colors.black.withValues(alpha: 0.18);
      }),
    );
  }
}
