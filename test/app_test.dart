import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pr_reader/src/data/pr_session.dart';
import 'package:pr_reader/src/data/viewed_state.dart';
import 'package:pr_reader/src/diff/diff_models.dart';
import 'package:pr_reader/src/github/pr_ref.dart';
import 'package:pr_reader/src/ui/diff/diff_controller.dart';
import 'package:pr_reader/src/ui/diff/diff_rows.dart';
import 'package:pr_reader/src/ui/diff/files_tab.dart';
import 'package:pr_reader/src/ui/pr/pr_screen.dart';

import 'support/fake_github.dart';
import 'support/harness.dart';

const _pr = '/acme/engine/pull/4242';
const _ref = PrRef('acme', 'engine', 4242);

PrSession _session(TestApp app) => app.services.session(_ref);

final _vertical = find
    .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
    .first;

/// Whether the in-list (not sticky) header of file [i] is built.
bool _headerBuilt(int i) =>
    find.byWidgetPredicate((w) => w is FileHeader && w.index == i && !w.elevated).evaluate().isNotEmpty;

DiffController _diff(WidgetTester tester) => tester.widget<FilesTab>(find.byType(FilesTab)).controller;

Future<void> _openFiles(WidgetTester tester, TestApp app) async {
  await settle(tester, () => _session(app).pr != null);
  await tester.tap(find.textContaining('Files').first);
  await settle(tester, () => _session(app).filesDone);
}

/// Everything the app saved, to start the next "launch" from.
Map<String, Object> _savedPrefs(TestApp app) {
  final p = app.services.settings.prefs;
  return {for (final k in p.getKeys()) k: p.get(k)!};
}

void main() {
  testWidgets('home on a phone', (tester) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      dpr: 3,
      padding: const EdgeInsets.only(top: 47, bottom: 34),
    );
    await settle(tester, () => true, maxRounds: 3);
    await capture(tester, 'phone_home');
  });

  testWidgets('home on desktop, signed in', (tester) async {
    await pumpApp(tester, size: const Size(1440, 900), dpr: 1, token: true);
    await settle(tester, () => find.text('Review requested').evaluate().isNotEmpty, maxRounds: 20);
    await settle(tester, () => false, maxRounds: 10);
    await capture(tester, 'desktop_home');
  });

  testWidgets('phone: conversation, files, tree sheet', (tester) async {
    final app = await pumpApp(
      tester,
      size: const Size(390, 844),
      dpr: 3,
      route: _pr,
      padding: const EdgeInsets.only(top: 47, bottom: 34),
    );
    await settle(tester, () => _session(app).issueComments != null);
    await capture(tester, 'phone_conversation');

    await _openFiles(tester, app);
    expect(tester.takeException(), isNull);
    await capture(tester, 'phone_files');

    // Scroll deep into the diff; the sticky header should follow.
    final c = _diff(tester);
    c.vertical.jumpTo(c.layout!.totalExtent * 0.4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await capture(tester, 'phone_files_deep');

    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();
    await capture(tester, 'phone_tree_sheet');
  });

  testWidgets('phone landscape', (tester) async {
    final app = await pumpApp(
      tester,
      size: const Size(844, 390),
      dpr: 3,
      route: '$_pr/files',
      padding: const EdgeInsets.only(left: 47, right: 47, bottom: 21),
    );
    await settle(tester, () => _session(app).filesDone);
    await capture(tester, 'phone_landscape_files');
    // Reading down the diff hides the PR header to give the code more room.
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsNothing);
    await capture(tester, 'phone_landscape_scrolled');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('Conversation'), findsOneWidget);
  });

  testWidgets('foldable with a vertical hinge', (tester) async {
    final app = await pumpApp(
      tester,
      size: const Size(884, 1104),
      dpr: 2.5,
      route: '$_pr/files',
      displayFeatures: [
        ui.DisplayFeature(
          bounds: const Rect.fromLTWH(436, 0, 12, 1104),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ],
    );
    await settle(tester, () => _session(app).filesDone);
    expect(tester.takeException(), isNull);
    await capture(tester, 'foldable_files');
  });

  testWidgets('tablet portrait and landscape', (tester) async {
    var app = await pumpApp(tester, size: const Size(820, 1180), dpr: 2, route: '$_pr/files');
    await settle(tester, () => _session(app).filesDone);
    await capture(tester, 'tablet_portrait_files');
    app = await pumpApp(tester, size: const Size(1180, 820), dpr: 2, route: '$_pr/files');
    await settle(tester, () => _session(app).filesDone);
    await capture(tester, 'tablet_landscape_files');
  });

  testWidgets('desktop: split diff, search, comments panel, dark', (tester) async {
    final app = await pumpApp(tester, size: const Size(1440, 900), dpr: 1, route: _pr);
    await settle(tester, () => _session(app).issueComments != null);
    await capture(tester, 'desktop_conversation');
    await _openFiles(tester, app);
    await capture(tester, 'desktop_files_split');

    final c = _diff(tester);
    c.search('command');
    await settle(tester, () => c.hits != null, maxRounds: 30);
    expect(c.hits!.length, greaterThan(0));
    await tester.pump();
    // The list itself (not just the sticky header) must move to the hit.
    final hitFile = c.hits!.file[c.currentHit];
    final hitRow = c.layout!.rowOfLine(hitFile, c.hits!.line[c.currentHit]);
    expect(c.vertical.offset, lessThanOrEqualTo(c.layout!.offsets[hitRow]));
    expect(c.vertical.offset + 900, greaterThan(c.layout!.offsets[hitRow]));
    expect(find.byWidgetPredicate((w) => w is FileHeader && w.index == hitFile), findsWidgets);
    await capture(tester, 'desktop_search');

    // Jumping to a file that is already laid out scrolls the list there.
    c.jumpToFile(120);
    await tester.pump();
    expect(_headerBuilt(120), isTrue);

    final big = await pumpApp(
      tester,
      size: const Size(1920, 1080),
      dpr: 1,
      route: '$_pr/files',
      theme: ThemeMode.dark,
    );
    await settle(tester, () => _session(big).filesDone && _session(big).threads != null);
    await tester.tap(find.textContaining('2 comments').first);
    await tester.pumpAndSettle();
    await capture(tester, 'xl_dark_comments_panel');
  });

  testWidgets('viewed marks sync with GitHub', (tester) async {
    final fake = FakeGitHub();
    final first = fake.files[5]['filename'] as String;
    fake.viewedOnGitHub[first] = 'VIEWED';
    fake.viewedOnGitHub[fake.files[6]['filename'] as String] = 'DISMISSED';
    final app = await pumpApp(
      tester,
      size: const Size(1440, 900),
      dpr: 1,
      route: '$_pr/files',
      token: true,
      fake: fake,
    );
    final s = _session(app);
    await settle(tester, () => s.filesDone && s.viewed.sync == ViewedSync.synced);
    final c = _diff(tester);
    expect(s.viewed.sync, ViewedSync.synced);
    expect(c.isViewed(5), isTrue, reason: 'marked viewed on github.com');
    expect(c.isViewed(6), isFalse, reason: 'changed since it was viewed');
    expect(c.isExpanded(5), isFalse);

    // Clicks go to GitHub, single and batched.
    c.setViewed(7, true);
    c.setViewed(5, false);
    c.markAllViewed(true);
    await settle(tester, () => fake.viewedMutations.length >= fake.files.length, maxRounds: 50);
    expect(fake.viewedMutations.take(2), ['+${fake.files[7]['filename']}', '-$first']);
    expect(fake.viewedOnGitHub.values.every((v) => v == 'VIEWED'), isTrue);
    expect(s.viewed.countViewed(s.files), s.files.length);

    // Changes made on the web show up after a re-sync.
    fake.viewedOnGitHub[first] = 'UNVIEWED';
    await tester.runAsync(s.syncViewed);
    await tester.pump();
    expect(c.isViewed(5), isFalse);
    await capture(tester, 'desktop_viewed_synced');

    // A token that can't write falls back to device-only marks, keeping the click.
    fake.canMarkViewed = false;
    c.setViewed(8, false);
    await settle(tester, () => s.viewed.sync == ViewedSync.readOnly, maxRounds: 30);
    expect(s.viewed.sync, ViewedSync.readOnly);
    expect(c.isViewed(8), isFalse);
    expect(c.isViewed(9), isTrue, reason: 'GitHub marks are kept locally');
    expect(find.textContaining("can't mark files as viewed"), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('without a token viewed marks stay on the device', (tester) async {
    final app = await pumpApp(tester, size: const Size(1440, 900), dpr: 1, route: '$_pr/files');
    final s = _session(app);
    await settle(tester, () => s.filesDone);
    expect(s.viewed.sync, ViewedSync.local);
    _diff(tester).setViewed(3, true);
    await tester.pump();
    expect(_diff(tester).isViewed(3), isTrue);
    expect(app.fake.viewedMutations, isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('commenting: conversation, replies and diff lines', (tester) async {
    final fake = FakeGitHub();
    final app = await pumpApp(
      tester,
      size: const Size(1440, 900),
      dpr: 1,
      route: _pr,
      token: true,
      fake: fake,
    );
    final s = _session(app);
    await settle(tester, () => s.issueComments != null && s.threads != null);

    // A conversation comment.
    final box = find.widgetWithText(TextField, 'Leave a comment');
    await tester.scrollUntilVisible(box, 300, scrollable: _vertical);
    await tester.enterText(box, 'Ship it **now**');
    await tester.pump();
    final send = find.widgetWithText(FilledButton, 'Comment');
    await tester.ensureVisible(send);
    await tester.pumpAndSettle();
    await tester.tap(send);
    await settle(tester, () => fake.posted.isNotEmpty, maxRounds: 30);
    expect(fake.posted, ['issue:Ship it **now**']);
    expect(s.issueComments!.last.body, 'Ship it **now**');

    // A reply in the review thread shown in the conversation.
    final reply = find.widgetWithText(TextField, 'Reply…').first;
    await tester.scrollUntilVisible(reply, -300, scrollable: _vertical);
    await tester.tap(reply);
    await tester.pump();
    await tester.enterText(reply, 'Added the cap in the latest push.');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Reply'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
    await settle(tester, () => fake.posted.length == 2, maxRounds: 30);
    expect(fake.posted.last, 'reply:Added the cap in the latest push.');
    expect(s.threads!.first.replies.last.body, 'Added the cap in the latest push.');
    expect(find.text('Added the cap in the latest push.'), findsOneWidget);
    await capture(tester, 'desktop_conversation_commented');

    // A new comment on a diff line, from the line's menu.
    await tester.tap(find.textContaining('Files').first);
    await settle(tester, () => s.filesDone);
    final threadsBefore = s.threads!.length;
    final lines = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_LineGestures');
    await tester.longPress(lines.at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Comment on line'));
    await tester.pumpAndSettle();
    await capture(tester, 'desktop_line_comment_dialog');
    await tester.enterText(find.widgetWithText(TextField, 'Leave a comment'), 'Nit: rename this.');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Comment'));
    await settle(tester, () => fake.posted.length == 3, maxRounds: 30);
    expect(fake.posted.last, startsWith('line:'));
    expect(fake.posted.last, endsWith(':Nit: rename this.'));
    expect(s.threads!.length, threadsBefore + 1);
    await tester.pumpAndSettle();
    expect(find.text('Comment posted'), findsOneWidget);
    expect(find.textContaining('Nit: rename this.'), findsWidgets, reason: 'new thread marker in the diff');

    // Failures keep the text and explain why.
    fake.canComment = false;
    await tester.longPress(lines.at(5));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Comment on line'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Leave a comment'), 'Will fail');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Comment'));
    await settle(tester, () => find.textContaining('not accessible').evaluate().isNotEmpty, maxRounds: 30);
    expect(find.textContaining('not accessible'), findsOneWidget);
    expect(find.text('Will fail'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('commenting needs a token', (tester) async {
    final app = await pumpApp(tester, size: const Size(1440, 900), dpr: 1, route: _pr);
    await settle(tester, () => _session(app).issueComments != null);
    final hint = find.text('Add a GitHub token in Settings to comment.');
    await tester.scrollUntilVisible(hint.first, 300, scrollable: _vertical);
    expect(hint, findsWidgets);
  });

  testWidgets('large PR stays fast and consistent', (tester) async {
    final fake = FakeGitHub(fileCount: 1200, seed: 3);
    final app = await pumpApp(tester, size: const Size(1280, 800), dpr: 1, route: '$_pr/files', fake: fake);
    await settle(tester, () => _session(app).filesDone, maxRounds: 600);
    final s = _session(app);
    expect(s.files.length, fake.files.length);
    final c = _diff(tester);
    final layout = c.layout!;
    final lines = s.files.fold<int>(0, (n, f) => n + f.lines.length);
    // ignore: avoid_print
    print(
      'files=${s.files.length} lines=$lines rows=${layout.length} extent=${layout.totalExtent.round()}px',
    );
    expect(lines, greaterThan(20000));

    // Jump around the whole diff; each frame must build without errors and
    // only build what is visible.
    final sw = Stopwatch()..start();
    for (final f in [0.1, 0.5, 0.9, 0.99, 0.0, 0.73]) {
      c.vertical.jumpTo(c.vertical.position.maxScrollExtent * f);
      await tester.pump();
    }
    sw.stop();
    // ignore: avoid_print
    print('6 jumps across the diff took ${sw.elapsedMilliseconds}ms in the test runner');
    expect(tester.takeException(), isNull);

    // Expanding the generated lockfile and the too-large file works.
    final lock = s.files.indexWhere((f) => f.path == 'package-lock.json');
    c.setExpanded(lock, true);
    c.jumpToFile(lock);
    await tester.pump();
    await tester.pump();
    expect(c.layout!.lineRow[lock], isNotNull);

    final tables = s.files.indexWhere((f) => f.path.endsWith('shader_tables.go'));
    expect(s.files[tables].state, PatchState.tooLarge);
    c.loadFullDiff(tables);
    await settle(tester, () => s.files[tables].state != PatchState.loading, maxRounds: 200);
    expect(s.files[tables].state, PatchState.ready);
    expect(s.files[tables].hunks, isNotEmpty);
    c.jumpToFile(tables);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(_headerBuilt(tables), isTrue);
    await capture(tester, 'desktop_loaded_full_diff');

    // Viewed marks collapse files and persist.
    c.setViewed(0, true);
    await tester.pump();
    expect(c.isExpanded(0), isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('relaunching resumes the open PR where reading stopped', (tester) async {
    final fake = FakeGitHub(fileCount: 600, seed: 5);
    final app = await pumpApp(tester, size: const Size(1440, 900), dpr: 1, route: '$_pr/files', fake: fake);
    await settle(tester, () => _session(app).filesDone, maxRounds: 400);
    final s = _session(app);
    final c = _diff(tester);
    // Read deep into a late file, past its header.
    final target = s.files.indexWhere((f) => f.lines.length > 40, 500);
    c.jumpToLine(target, 30);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final top = c.readingAnchor!;
    expect(top.path, s.files[target].path);
    final saved = _savedPrefs(app);
    expect(saved['last_pr'], _ref.key);

    // Relaunch on a phone (different width, so different pixels) at home.
    final again = await pumpApp(
      tester,
      size: const Size(390, 844),
      dpr: 3,
      fake: FakeGitHub(fileCount: 600, seed: 5),
      prefs: saved,
    );
    expect(find.byType(PrScreen), findsOneWidget);
    await settle(tester, () => _session(again).filesDone, maxRounds: 400);
    await tester.pump();
    final c2 = _diff(tester);
    expect(c2.currentFile.value, target);
    // The phone shows unified rows, so compare where the saved row lands.
    expect(c2.readingAnchor!.path, top.path);
    expect(c2.vertical.offset, closeTo(c2.layout!.resolve(top)!, 1));
    expect(c2.vertical.offset, greaterThan(c2.layout!.fileOffset(target) + 100));
    await capture(tester, 'phone_resumed');

    // Going back home means the next launch starts at home.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(again.services.settings.lastPr, isNull);
    expect(again.services.settings.readingPosition(_ref)?.diff?.path, top.path);
  });
}
