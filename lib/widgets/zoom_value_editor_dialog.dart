/*
* Orion - Zoom Value Editor Dialog (Reusable)
*/

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter/services.dart';
import 'package:orion/glasser/glasser.dart';
import 'package:orion/util/orion_kb/orion_numeric_field.dart';
import 'package:orion/util/orion_kb/orion_keyboard_expander.dart';

class ZoomValueEditorDialog extends StatefulWidget {
  final String title;
  final String? description;
  final double currentValue;
  final double min;
  final double max;
  final String suffix;
  final int decimals;
  final double? step;

  /// When true (default), zoom is automatically disabled for dense ranges
  /// where total steps ( (max-min)/step ) are <= 40.
  final bool disableZoomWhenDense;

  /// Radius in step points to include on each side when zooming. For example,
  /// radius=15 with step=0.1 yields a zoom window of 3.0 total span centered
  /// around the current value (31 points including the current).
  final int zoomPointsRadius;

  const ZoomValueEditorDialog({
    super.key,
    required this.title,
    this.description,
    required this.currentValue,
    required this.min,
    required this.max,
    required this.suffix,
    required this.decimals,
    this.step,
    this.disableZoomWhenDense = true,
    this.zoomPointsRadius = 15,
  });

  static Future<double?> show(
    BuildContext context, {
    required String title,
    String? description,
    required double currentValue,
    required double min,
    required double max,
    required String suffix,
    required int decimals,
    double? step,
    bool disableZoomWhenDense = true,
    int zoomPointsRadius = 15,
  }) async {
    return showDialog<double>(
      context: context,
      builder: (ctx) => ZoomValueEditorDialog(
        title: title,
        description: description,
        currentValue: currentValue,
        min: min,
        max: max,
        suffix: suffix,
        decimals: decimals,
        step: step,
        disableZoomWhenDense: disableZoomWhenDense,
        zoomPointsRadius: zoomPointsRadius,
      ),
    );
  }

  @override
  State<ZoomValueEditorDialog> createState() => _ZoomValueEditorDialogState();
}

class _ZoomValueEditorDialogState extends State<ZoomValueEditorDialog>
    with SingleTickerProviderStateMixin {
  late double _currentValue;
  String? _tempEditValue; // Temporary unclamped value while editing
  bool _isZoomed = false;
  bool _isEditingNumeric = false;
  Timer? _holdTimer;
  double? _zoomMin;
  double? _zoomMax;
  final ValueNotifier<bool> _keyboardOpen = ValueNotifier<bool>(false);
  final GlobalKey _valueDisplayKey = GlobalKey();
  late AnimationController _cursorBlinkController;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.currentValue;
    _cursorBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _keyboardOpen.dispose();
    _cursorBlinkController.dispose();
    super.dispose();
  }

  Future<void> _editNumericValue() async {
    _exitZoom();
    setState(() {
      _isEditingNumeric = true;
      _tempEditValue = '';
    });
    _keyboardOpen.value = true;

    final result = await showOrionNumericKeyboard(
      context,
      initialValue: _currentValue,
      allowNegative: widget.min < 0,
      decimalPlaces: widget.decimals,
      clearOnOpen: true,
      maxIntegerDigits: _maxIntegerDigitsFromRange(widget.min, widget.max),
      onChanged: (text) {
        // Live update with unclamped temporary value
        setState(() {
          _tempEditValue = text;
        });
      },
    );

    if (mounted) {
      _keyboardOpen.value = false;
      setState(() {
        _tempEditValue = null;
      });
      if (result != null && result.isNotEmpty) {
        try {
          final parsed = double.parse(result);
          final clamped = parsed.clamp(widget.min, widget.max);
          setState(() {
            _currentValue = clamped;
            _isEditingNumeric = false;
          });
          HapticFeedback.lightImpact();
        } catch (e) {
          setState(() => _isEditingNumeric = false);
        }
      } else {
        setState(() => _isEditingNumeric = false);
      }
    }
  }

  int _maxIntegerDigitsFromRange(double min, double max) {
    final spanMax = math.max(min.abs(), max.abs());
    if (spanMax < 1) return 1;
    final floorVal = spanMax.floor();
    return floorVal.toString().length;
  }

  void _resetHoldTimer() {
    _holdTimer?.cancel();
    // 600ms delay to detect "holding still"
    if (_shouldAllowZoom()) {
      _holdTimer = Timer(const Duration(milliseconds: 600), _enterZoom);
    }
  }

  bool _isDenseRange() {
    final s = widget.step ?? (widget.decimals == 0 ? 1.0 : 0.1);
    if (s <= 0) return true;
    final totalSteps = (widget.max - widget.min) / s;
    return totalSteps <= 40.0;
  }

  bool _shouldAllowZoom() {
    if (!_isZoomed && widget.disableZoomWhenDense && _isDenseRange()) {
      return false;
    }
    return true;
  }

  void _enterZoom() {
    if (_isZoomed) return;
    if (widget.disableZoomWhenDense && _isDenseRange()) return;

    final totalRange = widget.max - widget.min;
    if (totalRange <= 0) return;

    // Define Zoom Span and bias it so the thumb stays under the finger when zooming.
    final originalStep = widget.step ?? (widget.decimals == 0 ? 1.0 : 0.1);
    final radius = widget.zoomPointsRadius;
    if (radius <= 0 || originalStep <= 0) return;

    double zoomSpan = originalStep * (radius * 2); // 31 points at radius=15
    if (zoomSpan > totalRange) zoomSpan = totalRange;

    // Preserve the thumb's relative position on screen (avoid jump-to-center).
    final anchorFraction = totalRange > 0
        ? ((_currentValue - widget.min) / totalRange).clamp(0.0, 1.0)
        : 0.5;

    double zMin = _currentValue - (anchorFraction * zoomSpan);
    double zMax = zMin + zoomSpan;

    // Clamp to valid bounds while preserving total span when possible
    if (zMin < widget.min) {
      zMin = widget.min;
      zMax = (zMin + zoomSpan).clamp(widget.min, widget.max);
    }
    if (zMax > widget.max) {
      zMax = widget.max;
      zMin = (zMax - zoomSpan).clamp(widget.min, widget.max);
    }
    // Final sanity: ensure ordering and minimum span
    if (zMax < zMin) {
      zMin = widget.min;
      zMax = widget.max;
    }

    if (zMin < widget.min) {
      zMin = widget.min;
      zMax = zMin + zoomSpan;
    }
    if (zMax > widget.max) {
      zMax = widget.max;
      zMin = zMax - zoomSpan;
    }
    if (zMin < widget.min) zMin = widget.min;

    if (mounted) {
      setState(() {
        _zoomMin = zMin;
        _zoomMax = zMax;
        _isZoomed = true;
        HapticFeedback.lightImpact();
      });
    }
  }

  void _exitZoom() {
    _holdTimer?.cancel();
    if (_isZoomed) {
      setState(() {
        _isZoomed = false;
        _zoomMin = null;
        _zoomMax = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;

    double activeMin = _isZoomed ? (_zoomMin ?? widget.min) : widget.min;
    double activeMax = _isZoomed ? (_zoomMax ?? widget.max) : widget.max;
    final originalStep = widget.step ?? (widget.decimals == 0 ? 1.0 : 0.1);
    final activeStep = originalStep; // keep constant; range narrows instead
    final activeDecimals = widget.decimals; // keep constant

    return GlassAlertDialog(
      title: Text(widget.title,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _keyboardOpen,
              builder: (context, isKeyboardOpen, child) {
                return AnimatedOpacity(
                  opacity: isKeyboardOpen ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: isKeyboardOpen ? 0 : null,
                    child: widget.description != null
                        ? Padding(
                            padding: EdgeInsets.only(
                              bottom: isKeyboardOpen ? 0 : 24,
                            ),
                            child: Text(
                              widget.description!,
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.grey.shade400,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : SizedBox(
                            height: isKeyboardOpen ? 0 : 24,
                          ),
                  ),
                );
              },
            ),
            if (widget.description == null)
              ValueListenableBuilder<bool>(
                valueListenable: _keyboardOpen,
                builder: (context, isKeyboardOpen, child) {
                  return SizedBox(
                    height: isKeyboardOpen ? 0 : 24,
                  );
                },
              ),

            // Value Display (tap to edit with numeric keyboard)
            GestureDetector(
              onTap: _isEditingNumeric ? null : _editNumericValue,
              child: MouseRegion(
                cursor: _isEditingNumeric
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: AnimatedBuilder(
                  animation: _cursorBlinkController,
                  builder: (context, _) {
                    String valueStr;
                    bool showCursor = false;

                    if (_tempEditValue != null) {
                      showCursor = true;
                      // Editing mode: format with placeholder dashes
                      if (_tempEditValue!.isEmpty) {
                        // Empty: show just integer placeholder dashes
                        final intPlaces =
                            widget.max.toString().split('.')[0].length;
                        valueStr = '−' * intPlaces;
                      } else {
                        valueStr = _tempEditValue!;
                        // Only add decimal placeholder if user has entered decimal point
                        if (valueStr.contains('.') && activeDecimals > 0) {
                          final parts = valueStr.split('.');
                          if (parts[1].length < activeDecimals) {
                            // Has decimal but incomplete, pad with dashes
                            valueStr +=
                                '−' * (activeDecimals - parts[1].length);
                          }
                        }
                      }
                    } else {
                      // Not editing: show formatted current value
                      valueStr = activeDecimals == 0
                          ? _currentValue.round().toString()
                          : _currentValue.toStringAsFixed(activeDecimals);
                    }

                    final baseStyle = TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: activeColor,
                        shadows: null,
                        fontFamily: 'AtkinsonHyperlegible');

                    final spans = <TextSpan>[];

                    if (_isZoomed &&
                        valueStr.isNotEmpty &&
                        _tempEditValue == null) {
                      final stepForHighlight = activeStep;
                      if (stepForHighlight > 0) {
                        final dimColor = activeColor.withValues(alpha: 0.5);
                        final decimalIndex = valueStr.indexOf('.');
                        final digitsBeforeDecimal =
                            decimalIndex >= 0 ? decimalIndex : valueStr.length;
                        final thresholdExp = stepForHighlight > 0
                            ? (math.log(stepForHighlight) / math.ln10).floor()
                            : 0;

                        int currentExp = digitsBeforeDecimal - 1;
                        for (var i = 0; i < valueStr.length; i++) {
                          final ch = valueStr[i];
                          if (ch == '-' || ch == '−') {
                            spans.add(TextSpan(
                                text: ch,
                                style: baseStyle.copyWith(color: dimColor)));
                            continue;
                          }
                          if (ch == '.') {
                            spans.add(TextSpan(text: ch, style: baseStyle));
                            currentExp =
                                -1; // next digit is the first fractional
                            continue;
                          }
                          if (ch.codeUnitAt(0) >= 48 &&
                              ch.codeUnitAt(0) <= 57) {
                            final shouldDim = currentExp > thresholdExp;
                            spans.add(TextSpan(
                              text: ch,
                              style: baseStyle.copyWith(
                                  color: shouldDim ? dimColor : activeColor),
                            ));
                            currentExp -= 1;
                          } else {
                            spans.add(TextSpan(text: ch, style: baseStyle));
                          }
                        }
                      } else {
                        spans.add(TextSpan(text: valueStr, style: baseStyle));
                      }
                    } else {
                      // Build spans with blinking dashes in edit mode
                      bool editingDecimals =
                          showCursor && _tempEditValue!.contains('.');

                      for (var i = 0; i < valueStr.length; i++) {
                        final ch = valueStr[i];
                        // Make placeholder dashes blink based on editing position
                        if (showCursor && ch == '−') {
                          // Find if we're before or after decimal point
                          bool isBeforeDecimal = true;
                          for (var j = 0; j < i; j++) {
                            if (valueStr[j] == '.') {
                              isBeforeDecimal = false;
                              break;
                            }
                          }

                          // Blink integer dashes when editing integers, decimal dashes when editing decimals
                          bool shouldBlink =
                              (isBeforeDecimal && !editingDecimals) ||
                                  (!isBeforeDecimal && editingDecimals);

                          spans.add(TextSpan(
                            text: ch,
                            style: baseStyle.copyWith(
                              color: activeColor.withValues(
                                alpha: shouldBlink
                                    ? 0.3 + (0.7 * _cursorBlinkController.value)
                                    : 0.3,
                              ),
                            ),
                          ));
                        } else {
                          spans.add(TextSpan(text: ch, style: baseStyle));
                        }
                      }
                    }
                    if (widget.suffix.isNotEmpty) {
                      spans
                          .add(TextSpan(text: widget.suffix, style: baseStyle));
                    }
                    return RichText(
                      key: _valueDisplayKey,
                      text: TextSpan(children: spans),
                    );
                  },
                ),
              ),
            ),

            // Expander to push content up when keyboard opens
            OrionKbExpander(
              isKeyboardOpen: _keyboardOpen,
              widgetKey: _valueDisplayKey,
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                // Min Label / Caret
                SizedBox(
                  width: 50,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) {
                      final scale = TweenSequence<double>([
                        TweenSequenceItem(
                          tween: Tween(begin: 0.9, end: 1.1)
                              .chain(CurveTween(curve: Curves.easeOut)),
                          weight: 60,
                        ),
                        TweenSequenceItem(
                          tween: Tween(begin: 1.1, end: 1.0)
                              .chain(CurveTween(curve: Curves.easeIn)),
                          weight: 40,
                        ),
                      ]).animate(animation);

                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
                      );

                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: _isZoomed
                        ? Icon(
                            Icons.keyboard_double_arrow_right,
                            key: const ValueKey('min-caret'),
                            color: activeColor,
                            size: 30,
                          )
                        : Text(
                            activeDecimals == 0
                                ? activeMin.round().toString()
                                : activeMin.toStringAsFixed(activeDecimals),
                            key: const ValueKey('min-text'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.end,
                          ),
                  ),
                ),
                const SizedBox(width: 8),

                // Slider with Hold Detection
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: activeColor,
                      inactiveTrackColor: Colors.grey.shade700,
                      thumbColor: _isZoomed ? activeColor : Colors.white,
                      overlayColor: _isZoomed
                          ? activeColor.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.2),
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 12.0),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 24.0),
                      trackHeight: 8.0,
                    ),
                    child: Slider(
                      value: _currentValue.clamp(activeMin, activeMax),
                      min: activeMin,
                      max: activeMax,
                      divisions: (activeMax - activeMin) > 0
                          ? ((activeMax - activeMin) / activeStep)
                              .round()
                              .clamp(1, 10000)
                          : 1,
                      onChangeStart: (_) => _resetHoldTimer(),
                      onChangeEnd: (_) => _exitZoom(),
                      onChanged: (v) {
                        _resetHoldTimer();
                        setState(() {
                          final precision = widget.decimals;
                          final snapped =
                              (v / originalStep).roundToDouble() * originalStep;
                          _currentValue = precision == 0
                              ? snapped.roundToDouble()
                              : double.parse(
                                  snapped.toStringAsFixed(precision));
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Max Label / Caret
                SizedBox(
                  width: 50,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, animation) {
                      final scale = TweenSequence<double>([
                        TweenSequenceItem(
                          tween: Tween(begin: 0.9, end: 1.1)
                              .chain(CurveTween(curve: Curves.easeOut)),
                          weight: 60,
                        ),
                        TweenSequenceItem(
                          tween: Tween(begin: 1.1, end: 1.0)
                              .chain(CurveTween(curve: Curves.easeIn)),
                          weight: 40,
                        ),
                      ]).animate(animation);

                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
                      );

                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: _isZoomed
                        ? Icon(
                            Icons.keyboard_double_arrow_left,
                            key: const ValueKey('max-caret'),
                            color: activeColor,
                            size: 30,
                          )
                        : Text(
                            activeDecimals == 0
                                ? activeMax.round().toString()
                                : activeMax.toStringAsFixed(activeDecimals),
                            key: const ValueKey('max-text'),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.start,
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      actions: [
        GlassButton(
          tint: GlassButtonTint.negative,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 60),
          ),
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(FlutterI18n.translate(context, 'common.cancel')),
        ),
        GlassButton(
          tint: GlassButtonTint.positive,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(120, 60),
          ),
          onPressed: () => Navigator.of(context).pop(_currentValue),
          child: Text(FlutterI18n.translate(context, 'common.save')),
        ),
      ],
    );
  }
}

