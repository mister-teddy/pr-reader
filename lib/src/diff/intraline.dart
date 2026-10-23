import 'dart:typed_data';

import 'diff_models.dart';

/// Word-level emphasis for a deleted line and the added line that replaced
/// it. Pairs are found the same way split view pairs rows; the emphasized
/// span is what remains after trimming the common prefix and suffix, which is
/// cheap enough to compute while building a row.
abstract final class Intraline {
  static final _pairs = Expando<Int32List>();

  /// Index of the line paired with line [index] of [file], or -1.
  static int pairOf(DiffFile file, int index) {
    var pairs = _pairs[file.lines];
    if (pairs == null) {
      pairs = _computePairs(file);
      _pairs[file.lines] = pairs;
    }
    return index >= 0 && index < pairs.length ? pairs[index] : -1;
  }

  static Int32List _computePairs(DiffFile file) {
    final lines = file.lines;
    final pairs = Int32List(lines.length)..fillRange(0, lines.length, -1);
    for (final h in file.hunks) {
      var i = h.start;
      while (i < h.end) {
        if (lines[i].kind != LineKind.del) {
          i++;
          continue;
        }
        final delStart = i;
        while (i < h.end && lines[i].kind == LineKind.del) {
          i++;
        }
        final addStart = i;
        while (i < h.end && lines[i].kind == LineKind.add) {
          i++;
        }
        final n = (addStart - delStart) < (i - addStart) ? addStart - delStart : i - addStart;
        for (var k = 0; k < n; k++) {
          pairs[delStart + k] = addStart + k;
          pairs[addStart + k] = delStart + k;
        }
      }
    }
    return pairs;
  }

  /// The `[start, end)` range of [text] that differs from [other], or null
  /// when the lines share too little for emphasis to help.
  static (int, int)? changedRange(String text, String other) {
    final minLen = text.length < other.length ? text.length : other.length;
    var prefix = 0;
    while (prefix < minLen && text.codeUnitAt(prefix) == other.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < minLen - prefix &&
        text.codeUnitAt(text.length - 1 - suffix) == other.codeUnitAt(other.length - 1 - suffix)) {
      suffix++;
    }
    final start = prefix, end = text.length - suffix;
    if (end <= start) return null;
    final common = prefix + suffix;
    if (common < 3 || common * 4 < minLen) return null;
    return (start, end);
  }
}
