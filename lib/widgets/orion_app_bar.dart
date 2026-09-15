import 'package:flutter/material.dart';

/// A lightweight AppBar replacement that renders a left-aligned title with an
/// underline visually attached to the back button. The leading area (back
/// icon + title) is grouped together and underlined so the underline appears
/// to be part of the back affordance.
///
/// Use it as a drop-in replacement for simple use-cases:
/// ```dart
/// Scaffold(
///   appBar: OrionAppBar(title: const Text('Details')),
/// )
/// ```
class OrionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final double? toolbarHeight;
  final bool automaticallyImplyLeading;
  final double underlineWidth;
  final double underlineOpacity;
  final double backButtonSize;
  final bool centerTitle;
  final Widget? leadingWidget;
  final Widget? centerWidget;
  final bool hasQuestionMark;

  const OrionAppBar({
    super.key,
    required this.title,
    this.actions,
    this.backgroundColor,
    this.toolbarHeight,
    this.automaticallyImplyLeading = true,
    this.underlineWidth = 2.0,
    this.underlineOpacity = 0.55,
    this.backButtonSize = 30.0,
    this.hasQuestionMark = true,
    this.centerTitle = false,
    this.centerWidget,
    this.leadingWidget,
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight ?? kToolbarHeight);

  void _maybePop(BuildContext context) {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    final TextStyle titleStyle = appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge ??
        const TextStyle(fontSize: 20);

    final Color baseUnderlineColor =
        titleStyle.color ?? theme.colorScheme.onSurface;
    final Color underlineColor =
        baseUnderlineColor.withValues(alpha: underlineOpacity);

    final double height =
        toolbarHeight ?? appBarTheme.toolbarHeight ?? kToolbarHeight;

    // Leading + title grouped widget. Underline will be drawn only under the
    // title, not the back icon. Wrap the title in a Container that draws a
    // bottom border so the underline matches the title's width.
    // Create a single interactive control for the back affordance: the
    // chevron and the title are one tappable area, with proper hit target,
    // ripple, tooltip and semantics so users clearly understand the label is
    // part of the return button.
    Widget leadingTitle = Semantics(
      button: true,
      // If the title is a Text widget, extract the string for a helpful
      // accessibility label; otherwise fall back to a generic label.
      label: title is Text ? 'Back — ${(title as Text).data ?? ''}' : 'Back',
      child: Tooltip(
        message:
            title is Text ? 'Back — ${(title as Text).data ?? ''}' : 'Back',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () => _maybePop(context),
            // Make sure the tappable area is at least 48x48. Add a small
            // leading inset so the grouped control doesn't sit flush to the
            // screen edge (matches platform AppBar spacing).
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 6.0, end: 2.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (automaticallyImplyLeading && Navigator.canPop(context))
                      IconTheme(
                        data: IconThemeData(
                          size: backButtonSize,
                          color: appBarTheme.iconTheme?.color ??
                              theme.iconTheme.color,
                        ),
                        // Use BackButton to preserve platform padding and hit
                        // area visually, but prevent it from handling taps so the
                        // outer InkWell is the single control.
                        child: IgnorePointer(
                          child: BackButton(
                              color: appBarTheme.iconTheme?.color ??
                                  theme.iconTheme.color),
                        ),
                      ),
                    const SizedBox(width: 8.0),
                    // Title with underline limited to the title's width.
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: underlineColor, width: underlineWidth),
                        ),
                      ),
                      child: DefaultTextStyle(style: titleStyle, child: title),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Material(
      color: backgroundColor ??
          appBarTheme.backgroundColor ??
          theme.colorScheme.surface,
      elevation: appBarTheme.elevation ?? 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: centerTitle
                ? <Widget>[
                    // Leading back button (interactive) on the left
                    // If a custom leading widget was provided, render that on the
                    // left. Otherwise fall back to the platform BackButton (when
                    // a pop is possible) or a small spacer to align the title.
                    if (leadingWidget != null)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6.0),
                        child: leadingWidget!,
                      )
                    else if (automaticallyImplyLeading &&
                        Navigator.canPop(context))
                      IconTheme(
                        data: IconThemeData(
                          size: backButtonSize,
                          color: appBarTheme.iconTheme?.color ??
                              theme.iconTheme.color,
                        ),
                        child: BackButton(
                          color: appBarTheme.iconTheme?.color ??
                              theme.iconTheme.color,
                        ),
                      )
                    else
                      const SizedBox(width: 12.0),

                    // Centered title
                    Expanded(
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: underlineColor, width: underlineWidth),
                            ),
                          ),
                          child:
                              DefaultTextStyle(style: titleStyle, child: title),
                        ),
                      ),
                    ),

                    // Actions on the right
                    if (actions != null) ...actions!,
                  ]
                : <Widget>[
                    // Align the grouped leading+title to the left. If a
                    // custom leading widget was provided, render it instead of
                    // the grouped tappable leading+title control.
                    if (leadingWidget != null) leadingWidget! else leadingTitle,
                    // Optionally render a centered widget between the
                    // leading area and actions. This lets callers provide
                    // a separate center-aligned title (e.g. filename/date)
                    // while keeping the left back affordance as the
                    // interactive control.
                    if (centerWidget != null)
                      Expanded(child: Center(child: centerWidget))
                    else
                      // Fill remaining space (title area kept left-aligned)
                      const Spacer(),
                    if (actions != null) ...actions!,
                  ],
          ),
        ),
      ),
    );
  }
}
