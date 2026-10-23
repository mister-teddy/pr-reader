import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/services.dart';
import '../../app/settings.dart';
import '../../diff/diff_layout.dart';
import '../adaptive.dart';
import '../theme.dart';
import 'diff_controller.dart';
import 'diff_rows.dart';
import 'prefix_extent_list.dart';

/// Above this width the diff switches to side-by-side in auto mode.
const kAutoSplitWidth = 1000.0;

/// Below this width lines wrap in auto mode.
const kAutoWrapWidth = 720.0;

class CodeMetrics {
  CodeMetrics._(this.style, this.strut, this.charWidth, this.lineHeight);

  final TextStyle style;
  final StrutStyle strut;
  final double charWidth;
  final double lineHeight;

  static CodeMetrics? _cache;

  static CodeMetrics of(double fontSize, Color color) {
    final c = _cache;
    if (c != null && c.style.fontSize == fontSize && c.style.color == color) return c;
    final lineHeight = (fontSize * 1.55).roundToDouble();
    final style = TextStyle(
      fontFamily: kCodeFont,
      fontSize: fontSize,
      height: lineHeight / fontSize,
      color: color,
      fontFeatures: const [FontFeature.disable('liga'), FontFeature.disable('calt')],
    );
    final strut = StrutStyle(
      fontFamily: kCodeFont,
      fontSize: fontSize,
      height: lineHeight / fontSize,
      forceStrutHeight: true,
    );
    final tp = TextPainter(
      text: TextSpan(text: 'M' * 100, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final width = tp.width / 100;
    tp.dispose();
    return _cache = CodeMetrics._(style, strut, width, lineHeight);
  }
}

/// The virtualized diff of every file in the PR.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.controller, required this.openThreads});

  final DiffController controller;
  final OpenThreads openThreads;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, settings]),
      builder: (context, _) =>
          LayoutBuilder(builder: (context, constraints) => _build(context, constraints, settings)),
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints, SettingsController settings) {
    final theme = Theme.of(context);
    final diffTheme = DiffTheme.of(context);
    final width = constraints.maxWidth;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(0.85, 1.6);
    final code = CodeMetrics.of((settings.diffFontSize * scale).roundToDouble(), diffTheme.code);

    final split = switch (settings.diffLayout) {
      DiffLayoutPref.split => width >= 600,
      DiffLayoutPref.unified => false,
      DiffLayoutPref.auto => width >= kAutoSplitWidth,
    };
    final wrap =
        split ||
        switch (settings.wrap) {
          WrapPref.on => true,
          WrapPref.off => false,
          WrapPref.auto => width < kAutoWrapWidth,
        };
    final compact = width < 600;
    controller.updateMetrics(
      LayoutMetrics(
        width: width,
        charWidth: code.charWidth,
        lineHeight: code.lineHeight,
        split: split,
        wrap: wrap,
        compactGutter: compact && !split,
        headerExtent: compact ? 48 : 52,
      ),
    );
    controller.ensureLayout();
    final layout = controller.layout!;
    final noWrap = !wrap && layout.contentWidth > width + 0.5;

    final ctx = DiffRowContext(
      controller: controller,
      layout: layout,
      theme: diffTheme,
      scheme: theme.colorScheme,
      codeStyle: code.style,
      strut: code.strut,
      syntax: settings.syntaxHighlight,
      compact: compact,
      viewportWidth: width,
      noWrap: noWrap,
      openThreads: openThreads,
    );

    Widget list = CustomScrollView(
      controller: controller.vertical,
      scrollCacheExtent: const ScrollCacheExtent.pixels(400),
      slivers: [
        SliverPrefixExtentList(
          offsets: layout.offsets,
          delegate: SliverChildBuilderDelegate(
            (context, i) => buildDiffRow(ctx, i),
            childCount: layout.length,
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
          ),
        ),
      ],
    );
    if (noWrap) {
      list = Scrollbar(
        controller: controller.horizontal,
        thumbVisibility: isDesktopPlatform,
        child: SingleChildScrollView(
          controller: controller.horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: layout.contentWidth, height: constraints.maxHeight, child: list),
        ),
      );
    }

    return ClipRect(
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: list,
          ),
          Positioned(top: 0, left: 0, right: 0, child: _StickyHeader(ctx: ctx)),
          Positioned(
            top: 0,
            bottom: noWrap && isDesktopPlatform ? 12 : 0,
            right: 0,
            width: 48,
            child: DiffScrubber(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({required this.ctx});

  final DiffRowContext ctx;

  @override
  Widget build(BuildContext context) {
    final c = ctx.controller;
    return AnimatedBuilder(
      animation: c.vertical,
      builder: (context, _) {
        final l = ctx.layout;
        if (c.vertical.positions.length != 1 || l.length == 0) return const SizedBox.shrink();
        final off = c.vertical.offset;
        if (off <= 0) return const SizedBox.shrink();
        final f = l.fileAt(off);
        if (f < 0 || f >= l.headerRow.length) return const SizedBox.shrink();
        final gap = l.metrics.fileGap;
        if (off <= l.offsets[l.headerRow[f]] + gap) return const SizedBox.shrink();
        var dy = 0.0;
        if (f + 1 < l.headerRow.length) {
          final nextTop = l.offsets[l.headerRow[f + 1]] + gap;
          dy = math.min(0, nextTop - gap - off - l.metrics.headerExtent);
        }
        return Transform.translate(
          offset: Offset(0, dy),
          child: FileHeader(key: ValueKey(f), ctx: ctx, index: f, elevated: true),
        );
      },
    );
  }
}

/// A scrollbar built for very long content: the thumb can be dragged
/// directly, a bubble names the file under it while dragging, and ticks mark
/// review comments and search hits.
class DiffScrubber extends StatefulWidget {
  const DiffScrubber({super.key, required this.controller});

  final DiffController controller;

  @override
  State<DiffScrubber> createState() => _DiffScrubberState();
}

class _DiffScrubberState extends State<DiffScrubber> {
  bool _dragging = false;
  bool _hover = false;
  double _dragStartOffset = 0;
  double _dragStartY = 0;

  DiffController get c => widget.controller;

  static const _pad = 4.0;

  void _jumpToFraction(double fraction) {
    if (!c.vertical.hasClients) return;
    final p = c.vertical.position;
    c.vertical.jumpTo((fraction.clamp(0.0, 1.0) * p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final touch = !isDesktopPlatform;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackH = constraints.maxHeight - _pad * 2;
        return AnimatedBuilder(
          animation: Listenable.merge([c.vertical, c]),
          builder: (context, _) {
            final l = c.layout;
            if (l == null || c.vertical.positions.length != 1 || !c.vertical.position.hasContentDimensions) {
              return const SizedBox.shrink();
            }
            final p = c.vertical.position;
            final max = p.maxScrollExtent;
            if (max <= 0 || trackH <= 0) return const SizedBox.shrink();
            final total = l.totalExtent <= 0 ? 1.0 : l.totalExtent;
            final thumbH = (p.viewportDimension / total * trackH).clamp(touch ? 48.0 : 32.0, trackH / 2);
            final travel = trackH - thumbH;
            final thumbTop = _pad + (p.pixels / max).clamp(0.0, 1.0) * travel;
            final active = _dragging || _hover;

            void onDragStart(DragStartDetails d) {
              setState(() => _dragging = true);
              _dragStartOffset = p.pixels;
              _dragStartY = d.globalPosition.dy;
            }

            void onDragUpdate(DragUpdateDetails d) {
              if (travel <= 0) return;
              final dy = d.globalPosition.dy - _dragStartY;
              c.vertical.jumpTo((_dragStartOffset + dy / travel * max).clamp(0.0, max));
            }

            void onDragEnd([DragEndDetails? _]) => setState(() => _dragging = false);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: _pad,
                  bottom: _pad,
                  right: 1,
                  width: 4,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MarksPainter(
                        comments: c.commentMarks,
                        hits: c.hitMarks,
                        commentColor: scheme.tertiary,
                        hitColor: DiffTheme.of(context).searchCurrent,
                      ),
                    ),
                  ),
                ),
                if (!touch)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 14,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hover = true),
                      onExit: (_) => setState(() => _hover = false),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) =>
                            _jumpToFraction((d.localPosition.dy - _pad - thumbH / 2) / math.max(1, travel)),
                        onVerticalDragStart: onDragStart,
                        onVerticalDragUpdate: onDragUpdate,
                        onVerticalDragEnd: onDragEnd,
                        onVerticalDragCancel: onDragEnd,
                      ),
                    ),
                  ),
                Positioned(
                  top: thumbTop,
                  right: 0,
                  height: thumbH,
                  width: touch ? 40 : 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onVerticalDragStart: onDragStart,
                    onVerticalDragUpdate: onDragUpdate,
                    onVerticalDragEnd: onDragEnd,
                    onVerticalDragCancel: onDragEnd,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: active ? 10 : (touch ? 6 : 6),
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: active ? 0.55 : 0.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_dragging)
                  Positioned(
                    right: 20,
                    top: (thumbTop + thumbH / 2 - 18).clamp(0.0, constraints.maxHeight - 36),
                    child: _FileBubble(controller: c, offset: p.pixels + 64),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FileBubble extends StatelessWidget {
  const _FileBubble({required this.controller, required this.offset});

  final DiffController controller;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final l = controller.layout!;
    final f = l.fileAt(offset);
    if (f < 0) return const SizedBox.shrink();
    final file = l.files[f];
    final scheme = Theme.of(context).colorScheme;
    final maxW = MediaQuery.sizeOf(context).width * 0.7;
    return Material(
      elevation: 6,
      color: scheme.inverseSurface,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: math.min(maxW, 460)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: file.dir,
                  style: TextStyle(color: scheme.onInverseSurface.withValues(alpha: 0.7)),
                ),
                TextSpan(
                  text: file.name,
                  style: TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: '   ${f + 1}/${l.files.length}',
                  style: TextStyle(color: scheme.onInverseSurface.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter({
    required this.comments,
    required this.hits,
    required this.commentColor,
    required this.hitColor,
  });

  final Float64List comments;
  final Float64List hits;
  final Color commentColor;
  final Color hitColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = commentColor;
    for (final y in comments) {
      canvas.drawRect(Rect.fromLTWH(0, y * size.height - 1, size.width, 3), paint);
    }
    paint.color = hitColor;
    for (final y in hits) {
      canvas.drawRect(Rect.fromLTWH(0, y * size.height - 1, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) =>
      !identical(old.comments, comments) ||
      !identical(old.hits, hits) ||
      old.commentColor != commentColor ||
      old.hitColor != hitColor;
}
