import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pr_reader/src/app/links.dart';
import 'package:pr_reader/src/diff/diff_layout.dart';
import 'package:pr_reader/src/diff/diff_models.dart';
import 'package:pr_reader/src/diff/generated_files.dart';
import 'package:pr_reader/src/diff/intraline.dart';
import 'package:pr_reader/src/diff/line_diff.dart';
import 'package:pr_reader/src/diff/patch_parser.dart';
import 'package:pr_reader/src/diff/syntax.dart';
import 'package:pr_reader/src/diff/text_metrics.dart';
import 'package:pr_reader/src/github/models.dart';
import 'package:pr_reader/src/github/pr_ref.dart';

const _patch = '''@@ -1,4 +1,5 @@ class Foo
 line one
-old two
+new two
+added
 line three
\\ No newline at end of file
@@ -10,2 +11,2 @@
-ten
+TEN
 eleven''';

/// Applies parsed hunks to [oldLines] to reconstruct the new file.
List<String> _apply(List<String> oldLines, ParsedPatch p) {
  final out = <String>[];
  var oi = 0;
  for (final h in p.hunks) {
    final start = h.oldCount == 0 ? h.oldStart : h.oldStart - 1;
    while (oi < start) {
      out.add(oldLines[oi++]);
    }
    for (var i = h.start; i < h.end; i++) {
      final l = p.lines[i];
      switch (l.kind) {
        case LineKind.context:
          expect(oldLines[oi], l.text);
          out.add(l.text);
          oi++;
        case LineKind.del:
          expect(oldLines[oi], l.text);
          oi++;
        case LineKind.add:
          out.add(l.text);
        case LineKind.meta:
          break;
      }
    }
  }
  while (oi < oldLines.length) {
    out.add(oldLines[oi++]);
  }
  return out;
}

void main() {
  group('PrRef', () {
    test('parses common forms', () {
      expect(
        PrRef.tryParse('https://github.com/flutter/flutter/pull/171703'),
        const PrRef('flutter', 'flutter', 171703),
      );
      expect(PrRef.tryParse('github.com/a/b/pull/3/files#diff-123'), const PrRef('a', 'b', 3));
      expect(PrRef.tryParse('a-b/c.d#12'), const PrRef('a-b', 'c.d', 12));
      expect(PrRef.tryParse('a/b/pull/7'), const PrRef('a', 'b', 7));
      expect(PrRef.tryParse('https://api.github.com/repos/a/b/pulls/9'), const PrRef('a', 'b', 9));
      expect(PrRef.tryParse('a/b'), isNull);
      expect(PrRef.tryParse('hello'), isNull);
      expect(RepoRef.tryParse('https://github.com/a/b')?.slug, 'a/b');
      expect(RepoRef.tryParse('a/b.git')?.slug, 'a/b');
    });
  });

  group('links', () {
    test('map GitHub URLs and pr:/reader: links to routes', () {
      const pr = '/acme-co/monorepo/pull/17056';
      expect(routeForText('https://github.com/acme-co/monorepo/pull/17056/changes'), '$pr/files');
      expect(routeForText('https://github.com/acme-co/monorepo/pull/17056/files#diff-abc'), '$pr/files');
      expect(routeForText('https://github.com/acme-co/monorepo/pull/17056/commits'), '$pr/commits');
      expect(routeForText('https://github.com/acme-co/monorepo/pull/17056'), pr);
      expect(routeForText('acme-co/monorepo#17056'), pr);
      expect(routeForText('acme-co/monorepo'), '/acme-co/monorepo');
      expect(routeForText('nonsense'), isNull);
      expect(
        routeForLink(Uri.parse('pr://github.com/acme-co/monorepo/pull/17056/changes')),
        '$pr/files',
      );
      expect(
        routeForLink(Uri.parse('reader://github.com/acme-co/monorepo/pull/17056/changes')),
        '$pr/files',
      );
      expect(routeForLink(Uri.parse('other://github.com/a/b/pull/1')), isNull);
      expect(
        routeForLink(Uri.parse('https://github.com/acme-co/monorepo/pull/17056/changes')),
        '$pr/files',
      );
      expect(
        routeForLink(
          Uri.parse('pr://open?url=${Uri.encodeComponent('https://github.com/a/b/pull/3/changes')}'),
        ),
        '/a/b/pull/3/files',
      );
      // The URI host is lowercased by parsing; GitHub owners are case-insensitive.
      expect(
        routeForLink(Uri.parse('pr://acme-co/monorepo/pull/17056')),
        '/acme-co/monorepo/pull/17056',
      );
    });
  });

  group('parsePatch', () {
    test('parses hunks, numbers and meta lines', () {
      final p = parsePatch(_patch);
      expect(p.hunks, hasLength(2));
      expect(p.hunks[0].section, 'class Foo');
      final first = p.lines.sublist(p.hunks[0].start, p.hunks[0].end);
      expect(first.map((l) => l.kind), [
        LineKind.context,
        LineKind.del,
        LineKind.add,
        LineKind.add,
        LineKind.context,
        LineKind.meta,
      ]);
      expect(first[1].oldNo, 2);
      expect(first[2].newNo, 2);
      expect(first[4].oldNo, 3);
      expect(first[4].newNo, 4);
      final second = p.lines.sublist(p.hunks[1].start, p.hunks[1].end);
      expect(second.first.oldNo, 10);
      expect(second.last.newNo, 12);
    });

    test('classifies files without patches', () {
      expect(
        diffFileFromJson({'filename': 'a.png', 'status': 'added', 'changes': 0}).state,
        PatchState.noTextDiff,
      );
      expect(
        diffFileFromJson({'filename': 'b', 'status': 'renamed', 'changes': 0}).state,
        PatchState.noChanges,
      );
      expect(
        diffFileFromJson({'filename': 'c', 'status': 'modified', 'changes': 9000}).state,
        PatchState.tooLarge,
      );
    });
  });

  group('diffTexts', () {
    test('round-trips random edits', () {
      final rnd = math.Random(42);
      for (var iter = 0; iter < 200; iter++) {
        final a = List.generate(rnd.nextInt(60), (_) => 'l${rnd.nextInt(12)}');
        final b = [...a];
        for (var e = rnd.nextInt(8); e > 0; e--) {
          final op = rnd.nextInt(3);
          if (op == 0 && b.isNotEmpty) {
            b.removeAt(rnd.nextInt(b.length));
          } else if (op == 1) {
            b.insert(rnd.nextInt(b.length + 1), 'n${rnd.nextInt(20)}');
          } else if (b.isNotEmpty) {
            b[rnd.nextInt(b.length)] = 'x${rnd.nextInt(5)}';
          }
        }
        final p = diffTexts(a.join('\n'), b.join('\n'));
        expect(_apply(a, p), b, reason: 'iteration $iter');
      }
    });

    test('is fast on a large rewritten file', () {
      final a = List.generate(60000, (i) => 'line $i ${i % 7}');
      final b = [
        for (var i = 0; i < 60000; i++)
          if (i % 50 == 0) 'changed $i' else if (i % 333 != 0) a[i],
      ];
      final sw = Stopwatch()..start();
      final p = diffTexts(a.join('\n'), b.join('\n'));
      sw.stop();
      expect(_apply(a, p), b);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('new file is one hunk of additions', () {
      final p = diffTexts('', 'a\nb\nc\n');
      expect(p.hunks.single.header, '@@ -0,0 +1,3 @@');
      expect(p.lines.every((l) => l.kind == LineKind.add), isTrue);
    });
  });

  group('text metrics', () {
    test('wrapCount matches wrapBreaks', () {
      const samples = ['', 'abc', '\tindented\tcode', '日本語のテキストと English', '😀 emoji 😀😀', 'x'];
      for (final s in samples) {
        for (final cols in [1, 3, 5, 8, 13, 40]) {
          final line = DiffLine(LineKind.add, 0, 1, s * 7);
          expect(
            wrapCount(line.text, line.cols, line.wide, cols),
            wrapBreaks(renderText(line.text), cols).length + 1,
            reason: '"$s" at $cols',
          );
        }
      }
    });

    test('truncates very long lines', () {
      final long = 'a' * (kMaxRenderCols + 500);
      expect(renderText(long).length, kMaxRenderCols + 1);
      final l = DiffLine(LineKind.add, 0, 1, long);
      expect(wrapCount(l.text, l.cols, l.wide, 100), wrapBreaks(renderText(long), 100).length + 1);
    });
  });

  group('syntax', () {
    test('tokenizes dart', () {
      final spec = languageFor('lib/a.dart')!;
      final (toks, state) = tokenizeLine("final x = 'hi'; // note", spec, 0);
      final types = <int>[for (var i = 2; i < toks.length; i += 3) toks[i]];
      expect(types, [Tok.keyword, Tok.string, Tok.comment]);
      expect(state, 0);
      final (_, s2) = tokenizeLine('/* open', spec, 0);
      expect(s2, isNot(0));
      final (t3, s3) = tokenizeLine('still */ int y', spec, s2);
      expect(s3, 0);
      expect(t3[2], Tok.comment);
    });

    test('knows generated files', () {
      expect(isLikelyGenerated('package-lock.json'), isTrue);
      expect(isLikelyGenerated('lib/a.g.dart'), isTrue);
      expect(isLikelyGenerated('lib/main.dart'), isFalse);
    });
  });

  group('intraline', () {
    test('finds changed middle', () {
      expect(Intraline.changedRange('final a = 1;', 'final a = 2;'), (10, 11));
      expect(Intraline.changedRange('abc', 'xyz'), isNull);
    });
  });

  group('DiffLayout', () {
    DiffFile file(String path, int n) {
      final lines = [
        for (var i = 0; i < n; i++)
          DiffLine(
            i.isEven ? LineKind.add : LineKind.del,
            i.isEven ? 0 : i,
            i.isEven ? i : 0,
            'x' * (i % 120),
          ),
      ];
      return DiffFile(
        path: path,
        status: FileStatus.modified,
        additions: n ~/ 2,
        deletions: n ~/ 2,
        lines: lines,
        hunks: [DiffHunk(oldStart: 1, oldCount: n, newStart: 1, newCount: n, section: '', start: 0, end: n)],
      );
    }

    test('offsets are consistent and anchors survive relayout', () {
      final files = [for (var i = 0; i < 300; i++) file('dir/f$i.dart', 100)];
      LayoutMetrics metrics(double width, {bool split = false}) => LayoutMetrics(
        width: width,
        charWidth: 7.8,
        lineHeight: 20,
        split: split,
        wrap: true,
        compactGutter: false,
      );
      final sw = Stopwatch()..start();
      final layout = DiffLayout.build(
        files: files,
        metrics: metrics(800),
        bodyOf: (_) => const FullBody(),
        threads: const {},
      );
      sw.stop();
      expect(layout.lineCount, 30000);
      expect(sw.elapsedMilliseconds, lessThan(500));
      for (var r = 0; r < layout.length; r += 997) {
        expect(layout.rowAt(layout.offsets[r]), r);
        expect(layout.rowAt(layout.offsets[r] + layout.extentOf(r) / 2), r);
      }
      final row = layout.rowOfLine(150, 40);
      final anchor = layout.anchorAt(layout.offsets[row] + 3)!;
      for (final next in [metrics(400), metrics(1400, split: true)]) {
        final relaid = DiffLayout.build(
          files: files,
          metrics: next,
          bodyOf: (_) => const FullBody(),
          threads: const {},
        );
        final offset = relaid.resolve(anchor)!;
        final r = relaid.rowAt(offset);
        expect(relaid.file[r], 150);
        expect(relaid.rowOfLine(150, 40), r);
      }
    });

    test('collapsed files contribute only a header', () {
      final files = [file('a', 10), file('b', 10)];
      final layout = DiffLayout.build(
        files: files,
        metrics: const LayoutMetrics(
          width: 800,
          charWidth: 8,
          lineHeight: 20,
          split: false,
          wrap: false,
          compactGutter: false,
        ),
        bodyOf: (i) => i == 0 ? const HeaderOnlyBody() : const FullBody(),
        threads: const {},
      );
      expect(layout.lineRow[0], isNull);
      expect(layout.headerRow[1], 1);
      expect(layout.contentWidth, greaterThanOrEqualTo(800));
    });

    test('comment rows follow their line', () {
      final f = file('a', 10);
      final c = ReviewComment.fromJson({
        'id': 1,
        'user': {'login': 'me'},
        'path': 'a',
        'line': 4,
        'side': 'RIGHT',
        'created_at': '2026-01-01T00:00:00Z',
      });
      final layout = DiffLayout.build(
        files: [f],
        metrics: const LayoutMetrics(
          width: 800,
          charWidth: 8,
          lineHeight: 20,
          split: false,
          wrap: true,
          compactGutter: false,
        ),
        bodyOf: (_) => const FullBody(),
        threads: {
          'a': FileThreads(ReviewThread.group([c])),
        },
      );
      final lineRow = layout.rowOfLine(0, 4);
      expect(layout.kind[lineRow + 1], RowKind.comments);
      expect(layout.b[lineRow + 1], threadKey(4, DiffSide.right));
    });
  });
}
