import 'dart:math' as math;
import 'dart:typed_data';

import '../github/models.dart';
import 'diff_models.dart';
import 'text_metrics.dart';

/// The whole PR diff flattened into rows with exact pixel extents.
///
/// Rows live in parallel typed arrays and their offsets are a prefix sum, so
/// finding the row at a scroll offset is a binary search and jumping to any
/// file or line is O(1). Wrapped lines are measured with [wrapCount], which
/// matches how they are painted, so no row ever needs to be laid out to know
/// its height.
abstract final class RowKind {
  static const fileHeader = 0;

  /// `a` = hunk index.
  static const hunk = 1;

  /// Unified line; `a` = line index.
  static const line = 2;

  /// Side-by-side pair; `a` = left line index, `b` = right line index, -1 for none.
  static const split = 3;

  /// `a` = [NoticeKind] index.
  static const notice = 4;

  /// Comment threads anchored on a line; `b` = [threadKey].
  static const comments = 5;
  static const fileEnd = 6;
  static const listEnd = 7;
}

enum NoticeKind { hiddenLarge, hiddenGenerated, tooLarge, loading, failed, noTextDiff, noChanges }

sealed class FileBody {
  const FileBody();
}

class FullBody extends FileBody {
  const FullBody();
}

class HeaderOnlyBody extends FileBody {
  const HeaderOnlyBody();
}

class NoticeBody extends FileBody {
  const NoticeBody(this.kind);
  final NoticeKind kind;
}

int threadKey(int line, DiffSide side) => line * 2 + (side == DiffSide.right ? 1 : 0);

/// Review threads of one file, indexed by [threadKey].
class FileThreads {
  FileThreads(this.all) {
    for (final t in all) {
      final line = t.line;
      if (line == null || t.root.isFileLevel) continue;
      (byKey[threadKey(line, t.side)] ??= []).add(t);
    }
  }

  final List<ReviewThread> all;
  final Map<int, List<ReviewThread>> byKey = {};
}

class LayoutMetrics {
  const LayoutMetrics({
    required this.width,
    required this.charWidth,
    required this.lineHeight,
    required this.split,
    required this.wrap,
    required this.compactGutter,
    this.headerExtent = 52,
    this.fileGap = 12,
    this.hunkExtent = 30,
    this.noticeExtent = 64,
    this.commentsExtent = 40,
    this.fileEndExtent = 4,
    this.listEndExtent = 140,
  });

  /// Width available to rows (the viewport width).
  final double width;
  final double charWidth;
  final double lineHeight;
  final bool split;
  final bool wrap;

  /// One line-number column instead of two (unified mode on narrow screens).
  final bool compactGutter;
  final double headerExtent;
  final double fileGap;
  final double hunkExtent;
  final double noticeExtent;
  final double commentsExtent;
  final double fileEndExtent;
  final double listEndExtent;

  /// Horizontal padding inside a line-number cell.
  static const numberPadding = 16.0;
  static const signPadding = 10.0;
  static const codePaddingRight = 16.0;

  double numberColumnWidth(int maxLineNo) {
    final digits = math.max(3, maxLineNo.toString().length);
    return digits * charWidth + numberPadding;
  }

  double get signWidth => charWidth + signPadding;

  /// Width of the gutter (line numbers + sign) for a file.
  double gutterWidth(int maxLineNo) {
    final n = numberColumnWidth(maxLineNo);
    if (split) return n + signWidth;
    return (compactGutter ? n : n * 2) + signWidth;
  }

  /// Columns of code that fit on one visual line for a file.
  int codeColumns(int maxLineNo) {
    final available = split
        ? (width - 1) / 2 - gutterWidth(maxLineNo) - codePaddingRight
        : width - gutterWidth(maxLineNo) - codePaddingRight;
    return math.max(8, (available / charWidth).floor());
  }

  bool sameAs(LayoutMetrics o) =>
      o.width == width &&
      o.charWidth == charWidth &&
      o.lineHeight == lineHeight &&
      o.split == split &&
      o.wrap == wrap &&
      o.compactGutter == compactGutter;
}

class DiffLayout {
  DiffLayout._({
    required this.files,
    required this.metrics,
    required this.kind,
    required this.file,
    required this.a,
    required this.b,
    required this.offsets,
    required this.headerRow,
    required this.lineRow,
    required this.contentWidth,
    required this.lineCount,
  });

  final List<DiffFile> files;
  final LayoutMetrics metrics;
  final Uint8List kind;
  final Int32List file;
  final Int32List a;
  final Int32List b;

  /// `offsets[i]` is the top of row i; `offsets[length]` is the total extent.
  final Float64List offsets;

  /// Row of each file's header.
  final Int32List headerRow;

  /// Per file, the row showing each line (-1 when hidden); null when the
  /// file's body is not expanded.
  final List<Int32List?> lineRow;

  /// Width rows need without wrapping; at least [LayoutMetrics.width].
  final double contentWidth;

  /// Number of rendered code lines.
  final int lineCount;

  int get length => kind.length;
  double get totalExtent => offsets[length];
  double extentOf(int row) => offsets[row + 1] - offsets[row];

  /// Index of the row containing [offset].
  int rowAt(double offset) {
    if (length == 0) return 0;
    var lo = 0, hi = length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (offsets[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int fileAt(double offset) => length == 0 ? -1 : file[rowAt(offset)];

  /// Scroll offset that puts the header of [fileIndex] at the top.
  double fileOffset(int fileIndex) => offsets[headerRow[fileIndex]] + metrics.fileGap;

  /// Row showing line [lineIndex] of [fileIndex], or -1.
  int rowOfLine(int fileIndex, int lineIndex) {
    final rows = lineRow[fileIndex];
    if (rows == null || lineIndex < 0 || lineIndex >= rows.length) return -1;
    return rows[lineIndex];
  }

  /// Describes the row at [offset] so the same content can be found after a
  /// relayout (resize, collapse, wrap toggle).
  RowAnchor? anchorAt(double offset) {
    if (length == 0) return null;
    final row = rowAt(offset);
    final f = file[row];
    if (f < 0) return null;
    return RowAnchor(
      path: files[f].path,
      kind: kind[row],
      a: a[row],
      b: b[row],
      delta: offset - offsets[row],
    );
  }

  /// Scroll offset of [anchor] in this layout, or null if its file is gone.
  double? resolve(RowAnchor anchor) {
    var f = -1;
    for (var i = 0; i < files.length; i++) {
      if (files[i].path == anchor.path) {
        f = i;
        break;
      }
    }
    if (f < 0) return null;
    var row = -1;
    var delta = anchor.delta;
    switch (anchor.kind) {
      case RowKind.line || RowKind.split:
        row = rowOfLine(f, anchor.a >= 0 ? anchor.a : anchor.b);
      case RowKind.hunk:
        final hunks = files[f].hunks;
        if (anchor.a < hunks.length) {
          final first = rowOfLine(f, hunks[anchor.a].start);
          if (first > 0) row = first - 1;
        }
      case RowKind.comments:
        final line = rowOfLine(f, anchor.a);
        if (line >= 0) {
          row = line;
          delta = extentOf(line);
        }
    }
    if (row < 0) {
      row = headerRow[f];
      if (anchor.kind != RowKind.fileHeader) delta = metrics.fileGap;
    }
    return offsets[row] + math.min(delta, math.max(0.0, extentOf(row) - 0.5));
  }

  static DiffLayout build({
    required List<DiffFile> files,
    required LayoutMetrics metrics,
    required FileBody Function(int fileIndex) bodyOf,
    required Map<String, FileThreads> threads,
  }) {
    final rows = _RowBuffer();
    final headerRow = Int32List(files.length);
    final lineRow = List<Int32List?>.filled(files.length, null);
    final m = metrics;
    final lh = m.lineHeight;
    var contentWidth = m.width;
    var lineCount = 0;

    for (var f = 0; f < files.length; f++) {
      final df = files[f];
      final body = bodyOf(f);
      headerRow[f] = rows.length;
      rows.add(RowKind.fileHeader, f, 0, 0, m.fileGap + m.headerExtent);

      switch (body) {
        case HeaderOnlyBody():
          continue;
        case NoticeBody(:final kind):
          rows.add(RowKind.notice, f, kind.index, 0, m.noticeExtent);
          rows.add(RowKind.fileEnd, f, 0, 0, m.fileEndExtent);
          continue;
        case FullBody():
          break;
      }

      final lines = df.lines;
      final map = Int32List(lines.length)..fillRange(0, lines.length, -1);
      lineRow[f] = map;
      final cols = m.wrap ? m.codeColumns(df.maxLineNo) : 0;
      if (!m.wrap) {
        final w =
            m.gutterWidth(df.maxLineNo) +
            math.min(df.maxCols, kMaxRenderCols + 1) * m.charWidth +
            LayoutMetrics.codePaddingRight;
        if (w > contentWidth) contentWidth = w;
      }
      int segs(DiffLine l) => m.wrap ? wrapCount(l.text, l.cols, l.wide, cols) : 1;
      final ft = threads[df.path];

      void commentsAfter(DiffLine l, int lineIndex, {bool left = true, bool right = true}) {
        if (ft == null) return;
        if (left && l.kind != LineKind.add && l.oldNo > 0) {
          final key = threadKey(l.oldNo, DiffSide.left);
          if (ft.byKey.containsKey(key)) {
            rows.add(RowKind.comments, f, lineIndex, key, m.commentsExtent);
          }
        }
        if (right && l.kind != LineKind.del && l.newNo > 0) {
          final key = threadKey(l.newNo, DiffSide.right);
          if (ft.byKey.containsKey(key)) {
            rows.add(RowKind.comments, f, lineIndex, key, m.commentsExtent);
          }
        }
      }

      for (var h = 0; h < df.hunks.length; h++) {
        final hunk = df.hunks[h];
        rows.add(RowKind.hunk, f, h, 0, m.hunkExtent);
        if (!m.split) {
          for (var i = hunk.start; i < hunk.end; i++) {
            final l = lines[i];
            map[i] = rows.length;
            rows.add(RowKind.line, f, i, -1, segs(l) * lh);
            lineCount++;
            commentsAfter(l, i);
          }
          continue;
        }
        // Side by side: pair each run of deletions with the following run of
        // additions; context lines sit on both sides.
        var i = hunk.start;
        final left = <int>[], right = <int>[];
        while (i < hunk.end) {
          final l = lines[i];
          if (l.kind == LineKind.context || l.kind == LineKind.meta) {
            map[i] = rows.length;
            rows.add(RowKind.split, f, i, i, segs(l) * lh);
            lineCount++;
            commentsAfter(l, i);
            i++;
            continue;
          }
          left.clear();
          right.clear();
          while (i < hunk.end && lines[i].kind == LineKind.del) {
            left.add(i++);
          }
          while (i < hunk.end && lines[i].kind == LineKind.add) {
            right.add(i++);
          }
          final pairs = math.max(left.length, right.length);
          for (var p = 0; p < pairs; p++) {
            final li = p < left.length ? left[p] : -1;
            final ri = p < right.length ? right[p] : -1;
            final ls = li < 0 ? 0 : segs(lines[li]);
            final rs = ri < 0 ? 0 : segs(lines[ri]);
            final row = rows.length;
            if (li >= 0) map[li] = row;
            if (ri >= 0) map[ri] = row;
            rows.add(RowKind.split, f, li, ri, math.max(ls, rs) * lh);
            lineCount++;
            if (li >= 0) commentsAfter(lines[li], li, right: false);
            if (ri >= 0) commentsAfter(lines[ri], ri, left: false);
          }
        }
      }
      rows.add(RowKind.fileEnd, f, 0, 0, m.fileEndExtent);
    }
    rows.add(RowKind.listEnd, -1, 0, 0, m.listEndExtent);

    return DiffLayout._(
      files: files,
      metrics: metrics,
      kind: rows.kinds(),
      file: rows.ints(rows._file),
      a: rows.ints(rows._a),
      b: rows.ints(rows._b),
      offsets: rows.offsets(),
      headerRow: headerRow,
      lineRow: lineRow,
      contentWidth: contentWidth,
      lineCount: lineCount,
    );
  }
}

class RowAnchor {
  const RowAnchor({
    required this.path,
    required this.kind,
    required this.a,
    required this.b,
    required this.delta,
  });

  final String path;
  final int kind;
  final int a;
  final int b;
  final double delta;

  Map<String, dynamic> toJson() => {'p': path, 'k': kind, 'a': a, 'b': b, 'd': delta};

  static RowAnchor? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      return RowAnchor(
        path: j['p'] as String,
        kind: j['k'] as int,
        a: j['a'] as int,
        b: j['b'] as int,
        delta: (j['d'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _RowBuffer {
  var _kind = Uint8List(1024);
  var _file = Int32List(1024);
  var _a = Int32List(1024);
  var _b = Int32List(1024);
  var _ext = Float64List(1024);
  int length = 0;

  void add(int kind, int file, int a, int b, double extent) {
    if (length == _kind.length) _grow();
    _kind[length] = kind;
    _file[length] = file;
    _a[length] = a;
    _b[length] = b;
    _ext[length] = extent;
    length++;
  }

  void _grow() {
    final n = _kind.length * 2;
    _kind = Uint8List(n)..setRange(0, length, _kind);
    _file = Int32List(n)..setRange(0, length, _file);
    _a = Int32List(n)..setRange(0, length, _a);
    _b = Int32List(n)..setRange(0, length, _b);
    _ext = Float64List(n)..setRange(0, length, _ext);
  }

  Uint8List kinds() => Uint8List.sublistView(_kind, 0, length);
  Int32List ints(Int32List src) => Int32List.sublistView(src, 0, length);

  Float64List offsets() {
    final out = Float64List(length + 1);
    var acc = 0.0;
    for (var i = 0; i < length; i++) {
      out[i] = acc;
      acc += _ext[i];
    }
    out[length] = acc;
    return out;
  }
}
