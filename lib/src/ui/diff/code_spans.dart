import 'dart:typed_data';

import 'package:flutter/painting.dart';

import '../../diff/syntax.dart';
import '../theme.dart';

/// Builds the spans for one line of code: syntax colors, word-level diff
/// emphasis and search highlights, with `\n` inserted at precomputed wrap
/// points so the painted height matches the layout exactly.
List<InlineSpan> buildCodeSpans({
  required String text,
  required DiffTheme theme,
  Int32List? tokens,
  (int, int)? emphasis,
  Color? emphasisColor,
  String? query,
  bool Function(int start)? isCurrentHit,
  List<int> breaks = const [],
}) {
  final n = text.length;
  if (n == 0) return const [];

  // Search hits (case-insensitive), as flat [start, end, ...].
  final hits = <int>[];
  if (query != null && query.length >= 2) {
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    var at = lower.indexOf(q);
    while (at >= 0) {
      hits
        ..add(at)
        ..add(at + q.length);
      at = lower.indexOf(q, at + q.length);
    }
  }

  if (tokens == null && emphasis == null && hits.isEmpty && breaks.isEmpty) {
    return [TextSpan(text: text)];
  }

  // Collect every boundary where the style may change.
  final cuts = <int>{0, n};
  if (tokens != null) {
    for (var i = 0; i < tokens.length; i += 3) {
      cuts
        ..add(tokens[i].clamp(0, n))
        ..add(tokens[i + 1].clamp(0, n));
    }
  }
  if (emphasis != null) {
    cuts
      ..add(emphasis.$1.clamp(0, n))
      ..add(emphasis.$2.clamp(0, n));
  }
  cuts.addAll(hits);
  cuts.addAll(breaks);
  final sorted = cuts.toList()..sort();

  final spans = <InlineSpan>[];
  var tok = 0, hit = 0, brk = 0;
  for (var c = 0; c < sorted.length - 1; c++) {
    final s = sorted[c], e = sorted[c + 1];
    if (e <= s) continue;
    while (brk < breaks.length && breaks[brk] <= s) {
      if (breaks[brk] == s) spans.add(const TextSpan(text: '\n'));
      brk++;
    }
    var type = Tok.plain;
    if (tokens != null) {
      while (tok < tokens.length && tokens[tok + 1] <= s) {
        tok += 3;
      }
      if (tok < tokens.length && tokens[tok] <= s) type = tokens[tok + 2];
    }
    while (hit < hits.length && hits[hit + 1] <= s) {
      hit += 2;
    }
    final inHit = hit < hits.length && hits[hit] <= s;
    final current = inHit && (isCurrentHit?.call(hits[hit]) ?? false);
    final inEmphasis = emphasis != null && s >= emphasis.$1 && s < emphasis.$2;

    Color? bg;
    if (current) {
      bg = theme.searchCurrent;
    } else if (inHit) {
      bg = theme.searchHit;
    } else if (inEmphasis) {
      bg = emphasisColor;
    }
    final color = type == Tok.plain ? null : theme.syntaxColor(type);
    spans.add(
      TextSpan(
        text: text.substring(s, e),
        style: (color == null && bg == null)
            ? null
            : TextStyle(
                color: current ? const Color(0xFF1F2328) : color,
                backgroundColor: bg,
                fontStyle: type == Tok.comment ? FontStyle.italic : null,
              ),
      ),
    );
  }
  return spans;
}
