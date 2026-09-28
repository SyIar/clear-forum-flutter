import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

/// One native material behind Flutter controls; it never claims drag gestures.
class GlassPager extends StatelessWidget {
  const GlassPager({
    super.key,
    required this.pageNumber,
    this.onPrevious,
    this.onRefresh,
    this.onNext,
  });

  final int pageNumber;
  final VoidCallback? onPrevious;
  final VoidCallback? onRefresh;
  final VoidCallback? onNext;

  static double heightOf(BuildContext context) =>
      math.max(56, MediaQuery.textScalerOf(context).scale(15) * 1.4 + 16);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // The plugin reads CupertinoTheme on iOS and MediaQuery in its fallback.
    // Keep both in sync with the app, including the web appearance preview.
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(brightness: brightness),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
        child: LiquidGlassContainer(
          shape: const LiquidGlassShape.capsule(),
          height: heightOf(context),
          // The native surface is decorative. Flutter owns each button and
          // vertical drags, so the platform view cannot trap reader scrolling.
          interactive: false,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Page $pageNumber',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh page',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 21),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
