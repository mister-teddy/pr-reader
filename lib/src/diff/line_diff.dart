import 'dart:collection';
import 'dart:typed_data';

import 'diff_models.dart';
import 'patch_parser.dart';

const _eq = 0, _del = 1, _add = 2;

/// Regions without unique anchor lines fall back to an exact LCS when they
/// have at most this many cells, and to delete-then-insert beyond that.
const _lcsCellLimit = 1 << 20;
const _maxDepth = 256;

/// Line diff for files GitHub would not return a patch for. Uses patience
/// diff (anchored on lines unique to both sides), which stays fast on very
/// large files, with an exact LCS on the small gaps between anchors.
ParsedPatch diffTexts(String oldText, String newText, {int context = 3}) {
  final a = splitLines(oldText);
  final b = splitLines(newText);
  return buildHunks(a, b, diffLineLists(a, b), context: context);
}

/// Args are passed as a record so this can run through `compute`.
ParsedPatch diffTextsArgs(({String oldText, String newText}) args) => diffTexts(args.oldText, args.newText);

List<String> splitLines(String s) {
  if (s.isEmpty) return const [];
  final lines = s.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.endsWith('\r')) lines[i] = l.substring(0, l.length - 1);
  }
  return lines;
}

/// Returns edit ops (0 = equal, 1 = delete, 2 = insert) turning [a] into [b].
List<int> diffLineLists(List<String> a, List<String> b) {
  final ids = HashMap<String, int>();
  final av = Int32List(a.length);
  final bv = Int32List(b.length);
  for (var i = 0; i < a.length; i++) {
    av[i] = ids.putIfAbsent(a[i], () => ids.length);
  }
  for (var i = 0; i < b.length; i++) {
    bv[i] = ids.putIfAbsent(b[i], () => ids.length);
  }
  final out = <int>[];
  _diff(av, 0, av.length, bv, 0, bv.length, out, 0);
  return out;
}

void _diff(Int32List a, int a0, int a1, Int32List b, int b0, int b1, List<int> out, int depth) {
  while (a0 < a1 && b0 < b1 && a[a0] == b[b0]) {
    out.add(_eq);
    a0++;
    b0++;
  }
  var suffix = 0;
  while (a1 > a0 && b1 > b0 && a[a1 - 1] == b[b1 - 1]) {
    a1--;
    b1--;
    suffix++;
  }

  if (a0 == a1) {
    for (var j = b0; j < b1; j++) {
      out.add(_add);
    }
  } else if (b0 == b1) {
    for (var i = a0; i < a1; i++) {
      out.add(_del);
    }
  } else {
    final anchors = depth < _maxDepth ? _uniqueAnchors(a, a0, a1, b, b0, b1) : const <int>[];
    if (anchors.isNotEmpty) {
      var pa = a0, pb = b0;
      for (var k = 0; k < anchors.length; k += 2) {
        final ai = anchors[k], bi = anchors[k + 1];
        _diff(a, pa, ai, b, pb, bi, out, depth + 1);
        out.add(_eq);
        pa = ai + 1;
        pb = bi + 1;
      }
      _diff(a, pa, a1, b, pb, b1, out, depth + 1);
    } else if ((a1 - a0) * (b1 - b0) <= _lcsCellLimit) {
      _lcs(a, a0, a1, b, b0, b1, out);
    } else {
      for (var i = a0; i < a1; i++) {
        out.add(_del);
      }
      for (var j = b0; j < b1; j++) {
        out.add(_add);
      }
    }
  }

  for (var k = 0; k < suffix; k++) {
    out.add(_eq);
  }
}

/// Lines occurring exactly once in both ranges, reduced to the longest
/// sequence increasing on both sides. Returned flat as `[ai, bi, ...]`.
List<int> _uniqueAnchors(Int32List a, int a0, int a1, Int32List b, int b0, int b1) {
  // Value encodes count (capped at 2) and position: pos * 4 + count.
  final inA = HashMap<int, int>();
  for (var i = a0; i < a1; i++) {
    final v = inA[a[i]];
    inA[a[i]] = v == null ? i * 4 + 1 : (v & ~3) | 2;
  }
  final inB = HashMap<int, int>();
  for (var j = b0; j < b1; j++) {
    final id = b[j];
    if (!inA.containsKey(id)) continue;
    final v = inB[id];
    inB[id] = v == null ? j * 4 + 1 : (v & ~3) | 2;
  }

  final candA = <int>[];
  final candB = <int>[];
  for (var i = a0; i < a1; i++) {
    final va = inA[a[i]]!;
    if (va & 3 != 1) continue;
    final vb = inB[a[i]];
    if (vb == null || vb & 3 != 1) continue;
    candA.add(i);
    candB.add(vb >> 2);
  }
  if (candA.isEmpty) return const [];

  // Longest increasing subsequence of candB (patience sorting).
  final n = candA.length;
  final tails = <int>[];
  final prev = Int32List(n);
  for (var k = 0; k < n; k++) {
    final v = candB[k];
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (candB[tails[mid]] < v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    prev[k] = lo > 0 ? tails[lo - 1] : -1;
    if (lo == tails.length) {
      tails.add(k);
    } else {
      tails[lo] = k;
    }
  }
  final result = List<int>.filled(tails.length * 2, 0);
  var k = tails.last;
  for (var r = tails.length - 1; r >= 0; r--) {
    result[r * 2] = candA[k];
    result[r * 2 + 1] = candB[k];
    k = prev[k];
  }
  return result;
}

void _lcs(Int32List a, int a0, int a1, Int32List b, int b0, int b1, List<int> out) {
  final n = a1 - a0, m = b1 - b0;
  final w = m + 1;
  // dp[i][j] = LCS length of a[a0+i:] and b[b0+j:].
  final dp = Uint16List((n + 1) * w);
  for (var i = n - 1; i >= 0; i--) {
    final ai = a[a0 + i];
    final row = i * w, next = (i + 1) * w;
    for (var j = m - 1; j >= 0; j--) {
      if (ai == b[b0 + j]) {
        dp[row + j] = dp[next + j + 1] + 1;
      } else {
        final down = dp[next + j], right = dp[row + j + 1];
        dp[row + j] = down >= right ? down : right;
      }
    }
  }
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[a0 + i] == b[b0 + j]) {
      out.add(_eq);
      i++;
      j++;
    } else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
      out.add(_del);
      i++;
    } else {
      out.add(_add);
      j++;
    }
  }
  for (; i < n; i++) {
    out.add(_del);
  }
  for (; j < m; j++) {
    out.add(_add);
  }
}

/// Groups edit ops into hunks with [context] unchanged lines around changes.
ParsedPatch buildHunks(List<String> a, List<String> b, List<int> ops, {int context = 3}) {
  final n = ops.length;
  final ai = Int32List(n + 1), bi = Int32List(n + 1);
  for (var k = 0; k < n; k++) {
    final op = ops[k];
    ai[k + 1] = ai[k] + (op == _add ? 0 : 1);
    bi[k + 1] = bi[k] + (op == _del ? 0 : 1);
  }

  // Ranges [start, end) of ops covered by each hunk.
  final ranges = <int>[];
  var k = 0;
  while (k < n) {
    if (ops[k] == _eq) {
      k++;
      continue;
    }
    var end = k;
    while (end < n && ops[end] != _eq) {
      end++;
    }
    final s = k - context < 0 ? 0 : k - context;
    final e = end + context > n ? n : end + context;
    if (ranges.isNotEmpty && s <= ranges.last) {
      ranges.last = e;
    } else {
      ranges
        ..add(s)
        ..add(e);
    }
    k = end;
  }

  final lines = <DiffLine>[];
  final hunks = <DiffHunk>[];
  for (var r = 0; r < ranges.length; r += 2) {
    final s = ranges[r], e = ranges[r + 1];
    final start = lines.length;
    for (var q = s; q < e; q++) {
      switch (ops[q]) {
        case _eq:
          lines.add(DiffLine(LineKind.context, ai[q] + 1, bi[q] + 1, b[bi[q]]));
        case _del:
          lines.add(DiffLine(LineKind.del, ai[q] + 1, 0, a[ai[q]]));
        default:
          lines.add(DiffLine(LineKind.add, 0, bi[q] + 1, b[bi[q]]));
      }
    }
    final oldCount = ai[e] - ai[s], newCount = bi[e] - bi[s];
    hunks.add(
      DiffHunk(
        oldStart: oldCount == 0 ? ai[s] : ai[s] + 1,
        oldCount: oldCount,
        newStart: newCount == 0 ? bi[s] : bi[s] + 1,
        newCount: newCount,
        section: '',
        start: start,
        end: lines.length,
      ),
    );
  }
  return (lines: lines, hunks: hunks);
}
