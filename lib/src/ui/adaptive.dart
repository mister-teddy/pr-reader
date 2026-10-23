import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 window size classes.
enum WindowSize {
  compact,
  medium,
  expanded,
  large,
  extraLarge;

  static WindowSize of(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    if (width < 1600) return large;
    return extraLarge;
  }

  bool operator >=(WindowSize other) => index >= other.index;
  bool operator <(WindowSize other) => index < other.index;
}

extension AdaptiveContext on BuildContext {
  WindowSize get windowSize => WindowSize.of(MediaQuery.sizeOf(this).width);
}

/// True on the web outside phones and tablets, where a mouse is likely.
bool get kIsWebDesktopLike =>
    kIsWeb && defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS;

/// True on platforms where a mouse and keyboard are the norm.
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
    _ => false,
  };
}

/// A fold or hinge that splits the window into two usable panes, as on a
/// book-style foldable held open or a dual-screen device.
class Hinge {
  const Hinge(this.bounds, {required this.vertical});

  final Rect bounds;

  /// True for a vertical hinge (panes side by side).
  final bool vertical;

  static Hinge? of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    for (final DisplayFeature f in MediaQuery.displayFeaturesOf(context)) {
      if (f.type == DisplayFeatureType.cutout) continue;
      final isFold = f.type == DisplayFeatureType.fold;
      // A flat fold doesn't separate anything; only a half-open one does.
      if (isFold && f.state != DisplayFeatureState.postureHalfOpened) continue;
      final b = f.bounds;
      if (b.height >= size.height - 1 && b.left > 0 && b.right < size.width) {
        return Hinge(b, vertical: true);
      }
      if (b.width >= size.width - 1 && b.top > 0 && b.bottom < size.height) {
        return Hinge(b, vertical: false);
      }
    }
    return null;
  }
}

/// Lays out [first] and [second] on either side of a [Hinge].
class HingeSplit extends StatelessWidget {
  const HingeSplit({super.key, required this.hinge, required this.first, required this.second});

  final Hinge hinge;
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Convert the hinge from screen to local coordinates.
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null && box.attached ? box.localToGlobal(Offset.zero) : Offset.zero;
        if (hinge.vertical) {
          final left = (hinge.bounds.left - origin.dx).clamp(0.0, constraints.maxWidth);
          final right = (hinge.bounds.right - origin.dx).clamp(left, constraints.maxWidth);
          return Row(
            children: [
              SizedBox(width: left, child: first),
              SizedBox(width: right - left),
              Expanded(child: second),
            ],
          );
        }
        final top = (hinge.bounds.top - origin.dy).clamp(0.0, constraints.maxHeight);
        final bottom = (hinge.bounds.bottom - origin.dy).clamp(top, constraints.maxHeight);
        return Column(
          children: [
            SizedBox(height: top, child: first),
            SizedBox(height: bottom - top),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}
