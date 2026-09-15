import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Pre-renders and caches leveling SVGs so they appear instantly.
///
/// Asset pictograms are decoded via [SvgAssetLoader] and primed in
/// [svg.cache]; string pictograms (LCD/puck) are decoded via
/// [SvgStringLoader] and likewise cached. Subsequent [SvgPicture]
/// builds hit the cache and render without parsing delay.
class LevelingSvgCache {
  static bool _precached = false;

  /// Warm the cache. Safe to call multiple times.
  static Future<void> precache(BuildContext context, {bool force = false}) async {
    if (_precached && !force) return;
    _precached = true;

    final assetSvgs = <String>[
      'assets/images/ISO_7010_W024.svg',
      'assets/images/concepts_3d/levelingsystem/a2_lcd_ui_top_view_sanitized.svg',
      'assets/images/concepts_3d/levelingsystem/a2_hex_key_ui_front_view_tight.svg',
    ];

    for (final asset in assetSvgs) {
      try {
        final loader = SvgAssetLoader(asset);
        await svg.cache.putIfAbsent(
          loader.cacheKey(context),
          () => loader.loadBytes(context),
        );
      } catch (_) {
        // Asset may not exist on some builds — ignore.
      }
    }
  }

  /// Precache a string-based SVG (e.g. sanitized LCD body).
  static Future<void> precacheString(BuildContext context, String svgString) async {
    try {
      final loader = SvgStringLoader(svgString);
      await svg.cache.putIfAbsent(
        loader.cacheKey(context),
        () => loader.loadBytes(context),
      );
    } catch (_) {}
  }

  static void invalidate() => _precached = false;
}
