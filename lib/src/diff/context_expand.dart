import 'dart:math' as math;

import 'diff_models.dart';

/// First line a side of [h] covers. A side with no lines (a pure insertion
/// or deletion) is numbered by the line before it, as in `@@ -5,0 +6,2 @@`.
int _oldFirst(DiffHunk h) => h.oldCount == 0 ? h.oldStart + 1 : h.oldStart;
int _newFirst(DiffHunk h) => h.newCount == 0 ? h.newStart + 1 : h.newStart;
int _newLast(DiffHunk h) => _newFirst(h) + h.newCount - 1;
int _oldLast(DiffHunk h) => _oldFirst(h) + h.oldCount - 1;

/// How many unchanged lines are hidden above hunk [h].
int hiddenAbove(List<DiffHunk> hunks, int h) {
  final prevLast = h == 0 ? 0 : _newLast(hunks[h - 1]);
  return math.max(0, _newFirst(hunks[h]) - 1 - prevLast);
}

/// How many unchanged lines are hidden below hunk [h], [newLength] being the
/// line count of the file at the PR head.
int hiddenAfter(List<DiffHunk> hunks, int h, int newLength) =>
    h < hunks.length - 1 ? hiddenAbove(hunks, h + 1) : math.max(0, newLength - _newLast(hunks[h]));

/// How many unchanged lines are hidden below the last hunk.
int hiddenBelow(List<DiffHunk> hunks, int newLength) =>
    hunks.isEmpty ? 0 : hiddenAfter(hunks, hunks.length - 1, newLength);

/// Whether [f] may have unchanged lines after its last hunk. Until the file
/// at the PR head is fetched, that is unknown, so files that existed on both
/// sides are assumed to.
bool hasHiddenBelow(DiffFile f) {
  if (f.hunks.isEmpty || f.status == FileStatus.added || f.status == FileStatus.removed) return false;
  final n = f.newLength;
  return n == null || hiddenBelow(f.hunks, n) > 0;
}

/// Whether [f] has unchanged lines that are not shown.
bool hasHiddenLines(DiffFile f) {
  for (var h = 0; h < f.hunks.length; h++) {
    if (hiddenAbove(f.hunks, h) > 0) return true;
  }
  return hasHiddenBelow(f);
}

/// Whether every line of [f] is shown.
bool isWholeFile(DiffFile f) => f.newLength != null && f.hunks.length == 1 && !hasHiddenLines(f);

/// A diff with more or fewer unchanged lines shown, and where the lines and
/// hunks of the previous one ended up.
class Expansion {
  Expansion(this.lines, this.hunks, {required this.inserted, this._line, this._hunk});

  /// [lines] with runs of `(at, count)` lines inserted, `at` being an index
  /// in the previous lines, in increasing order.
  factory Expansion.inserting(
    List<DiffLine> lines,
    List<DiffHunk> hunks,
    List<(int, int)> inserts, {
    int Function(int)? hunk,
  }) => Expansion(
    lines,
    hunks,
    inserted: inserts.fold(0, (s, r) => s + r.$2),
    hunk: hunk,
    line: (i) {
      var out = i;
      for (final (at, n) in inserts) {
        if (at > i) break;
        out += n;
      }
      return out;
    },
  );

  Expansion._none(this.lines, this.hunks) : inserted = 0, _line = null, _hunk = null;

  final List<DiffLine> lines;
  final List<DiffHunk> hunks;

  /// Lines added, or removed when negative.
  final int inserted;
  final int Function(int)? _line;
  final int Function(int)? _hunk;

  /// Where line index [i] of the previous diff ended up.
  int line(int i) => _line?.call(i) ?? i;

  /// Where hunk [h] of the previous diff ended up.
  int hunk(int h) => _hunk?.call(h) ?? h;
}

List<DiffLine> _context(int oldFrom, int newFrom, int count, List<String> newFile) => [
  for (var i = 0; i < count; i++)
    DiffLine(
      LineKind.context,
      oldFrom + i,
      newFrom + i,
      newFrom + i - 1 < newFile.length ? newFile[newFrom + i - 1] : '',
    ),
];

DiffHunk _hunk(
  DiffHunk x, {
  int? oldStart,
  int? oldCount,
  int? newStart,
  int? newCount,
  String? section,
  int? start,
  int? end,
}) => DiffHunk(
  oldStart: oldStart ?? x.oldStart,
  oldCount: oldCount ?? x.oldCount,
  newStart: newStart ?? x.newStart,
  newCount: newCount ?? x.newCount,
  section: section ?? x.section,
  start: start ?? x.start,
  end: end ?? x.end,
);

/// Up to [count] of the unchanged lines above hunk [h] filled in from
/// [newFile] (the file at the PR head, split into lines). When the gap to
/// the previous hunk closes, the two hunks merge.
Expansion expandAbove(List<DiffLine> lines, List<DiffHunk> hunks, int h, List<String> newFile, {int count = 20}) {
  final hidden = hiddenAbove(hunks, h);
  if (hidden == 0) return Expansion._none(lines, hunks);
  final hunk = hunks[h];
  final k = math.min(count, hidden);
  final nFirst = _newFirst(hunk);
  final oFirst = _oldFirst(hunk);
  if (k == hidden && h > 0) return _merge(lines, hunks, h - 1, oFirst - k, nFirst - k, k, newFile);
  return Expansion.inserting(
    [...lines.sublist(0, hunk.start), ..._context(oFirst - k, nFirst - k, k, newFile), ...lines.sublist(hunk.start)],
    [
      ...hunks.sublist(0, h),
      _hunk(
        hunk,
        oldStart: oFirst - k,
        oldCount: hunk.oldCount + k,
        newStart: nFirst - k,
        newCount: hunk.newCount + k,
        end: hunk.end + k,
      ),
      for (final x in hunks.skip(h + 1)) _hunk(x, start: x.start + k, end: x.end + k),
    ],
    [(hunk.start, k)],
  );
}

/// Up to [count] of the unchanged lines below hunk [h] filled in from
/// [newFile]. When the gap to the next hunk closes, the two hunks merge.
Expansion expandAfter(List<DiffLine> lines, List<DiffHunk> hunks, int h, List<String> newFile, {int count = 20}) {
  final hidden = hiddenAfter(hunks, h, newFile.length);
  if (hidden == 0) return Expansion._none(lines, hunks);
  final hunk = hunks[h];
  final k = math.min(count, hidden);
  final oFrom = _oldLast(hunk) + 1;
  final nFrom = _newLast(hunk) + 1;
  if (k == hidden && h < hunks.length - 1) return _merge(lines, hunks, h, oFrom, nFrom, k, newFile);
  return Expansion.inserting(
    [...lines.sublist(0, hunk.end), ..._context(oFrom, nFrom, k, newFile), ...lines.sublist(hunk.end)],
    [
      ...hunks.sublist(0, h),
      _hunk(hunk, oldCount: hunk.oldCount + k, newCount: hunk.newCount + k, end: hunk.end + k),
      for (final x in hunks.skip(h + 1)) _hunk(x, start: x.start + k, end: x.end + k),
    ],
    [(hunk.end, k)],
  );
}

/// Hunks [h] and `h + 1` joined by the [k] lines between them, which start
/// at [oFrom] and [nFrom].
Expansion _merge(List<DiffLine> lines, List<DiffHunk> hunks, int h, int oFrom, int nFrom, int k, List<String> newFile) {
  final a = hunks[h];
  final b = hunks[h + 1];
  return Expansion.inserting(
    [...lines.sublist(0, a.end), ..._context(oFrom, nFrom, k, newFile), ...lines.sublist(a.end)],
    [
      ...hunks.sublist(0, h),
      _hunk(
        a,
        oldStart: _oldFirst(a),
        oldCount: a.oldCount + k + b.oldCount,
        newStart: _newFirst(a),
        newCount: a.newCount + k + b.newCount,
        end: b.end + k,
      ),
      for (final x in hunks.skip(h + 2)) _hunk(x, start: x.start + k, end: x.end + k),
    ],
    [(a.end, k)],
    hunk: (i) => i > h ? i - 1 : i,
  );
}

/// Up to [count] of the unchanged lines below the last hunk.
Expansion expandBelow(List<DiffLine> lines, List<DiffHunk> hunks, List<String> newFile, {int count = 20}) =>
    hunks.isEmpty ? Expansion._none(lines, hunks) : expandAfter(lines, hunks, hunks.length - 1, newFile, count: count);

/// The whole file: every gap filled in from [newFile], as a single hunk.
Expansion expandWhole(List<DiffLine> lines, List<DiffHunk> hunks, List<String> newFile) {
  if (hunks.isEmpty) return Expansion._none(lines, hunks);
  final out = <DiffLine>[];
  final inserts = <(int, int)>[];
  for (var h = 0; h < hunks.length; h++) {
    final x = hunks[h];
    final gap = hiddenAbove(hunks, h);
    if (gap > 0) {
      out.addAll(_context(_oldFirst(x) - gap, _newFirst(x) - gap, gap, newFile));
      inserts.add((x.start, gap));
    }
    out.addAll(lines.sublist(x.start, x.end));
  }
  final last = hunks.last;
  final tail = hiddenBelow(hunks, newFile.length);
  if (tail > 0) {
    out.addAll(_context(_oldLast(last) + 1, _newLast(last) + 1, tail, newFile));
    inserts.add((last.end, tail));
  }
  final oldTotal = _oldLast(last) + tail;
  final newTotal = _newLast(last) + tail;
  return Expansion.inserting(
    out,
    [
      DiffHunk(
        oldStart: oldTotal == 0 ? 0 : 1,
        oldCount: oldTotal,
        newStart: newTotal == 0 ? 0 : 1,
        newCount: newTotal,
        section: hiddenAbove(hunks, 0) > 0 ? '' : hunks.first.section,
        start: 0,
        end: out.length,
      ),
    ],
    inserts,
    hunk: (_) => 0,
  );
}

/// Back to [lines] and [hunks] as the patch had them, from [shown] and
/// [shownHunks], which hold the same line objects with unchanged lines added
/// around them.
Expansion collapseTo(List<DiffLine> shown, List<DiffHunk> shownHunks, List<DiffLine> lines, List<DiffHunk> hunks) {
  final map = List<int>.filled(shown.length, 0);
  var j = 0;
  for (var i = 0; i < shown.length; i++) {
    map[i] = math.min(j, math.max(0, lines.length - 1));
    if (j < lines.length && identical(shown[i], lines[j])) j++;
  }
  int line(int i) => i < map.length ? map[i] : i;
  int hunk(int h) {
    if (h >= shownHunks.length || hunks.isEmpty) return 0;
    final l = line(shownHunks[h].start);
    var i = 0;
    while (i < hunks.length - 1 && hunks[i].end <= l) {
      i++;
    }
    return i;
  }

  return Expansion(lines, hunks, inserted: lines.length - shown.length, line: line, hunk: hunk);
}
