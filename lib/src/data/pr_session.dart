import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../diff/diff_layout.dart';
import '../diff/diff_models.dart';
import '../diff/line_diff.dart';
import '../diff/patch_parser.dart';
import '../github/github_client.dart';
import '../github/models.dart';
import '../github/pr_ref.dart';
import 'viewed_state.dart';

/// Everything loaded for one pull request. Files stream in page by page
/// (fetched concurrently, parsed off the UI isolate, appended in order) so
/// the diff is readable long before a 3,000-file PR finishes loading.
class PrSession extends ChangeNotifier {
  PrSession(this.ref, this.gh, this.viewed);

  /// GitHub's API returns at most this many files for a PR.
  static const maxFiles = 3000;
  static const _concurrency = 4;

  final PrRef ref;
  final GitHubClient gh;
  final ViewedState viewed;

  PullRequest? pr;
  Object? error;

  final List<DiffFile> files = [];
  int filesExpected = 0;
  bool filesDone = false;
  Object? filesError;

  /// Bumped whenever something the diff layout depends on changes.
  int revision = 0;

  List<IssueComment>? issueComments;
  List<Review>? reviews;
  List<ReviewThread>? threads;
  Map<String, FileThreads> threadsByPath = const {};
  Object? conversationError;

  List<Commit>? commits;
  Object? commitsError;

  CheckSummary? checks;

  String? _mergeBase;
  bool _disposed = false;
  int _generation = 0;

  bool get loading => pr == null && error == null;
  bool get truncatedByApi => (pr?.changedFiles ?? 0) > maxFiles;

  int get lineCount => files.fold(0, (n, f) => n + f.lines.length);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final gen = ++_generation;
    error = null;
    _notify();
    try {
      final p = await gh.getPull(ref);
      if (gen != _generation) return;
      pr = p;
      _notify();
    } catch (e) {
      if (gen != _generation) return;
      error = e;
      _notify();
      return;
    }
    unawaited(_loadFiles(gen));
    unawaited(_loadConversation(gen));
    unawaited(_loadCommits(gen));
    unawaited(_loadChecks(gen));
    unawaited(syncViewed());
  }

  Future<void> refresh() {
    pr = null;
    files.clear();
    filesDone = false;
    filesError = null;
    issueComments = null;
    reviews = null;
    threads = null;
    threadsByPath = const {};
    commits = null;
    checks = null;
    _mergeBase = null;
    revision++;
    return load();
  }

  Future<void> retryFiles() {
    files.clear();
    filesDone = false;
    filesError = null;
    revision++;
    _notify();
    return _loadFiles(_generation);
  }

  Future<void> _loadFiles(int gen) async {
    final total = pr!.changedFiles;
    filesExpected = math.min(total, maxFiles);
    final pages = math.max(1, (filesExpected / 100).ceil());
    final results = List<List<DiffFile>?>.filled(pages, null);
    var nextPage = 0;
    var appended = 0;
    var failed = false;

    Future<void> worker() async {
      while (!failed && nextPage < pages) {
        final page = nextPage++;
        List<DiffFile> parsed;
        try {
          final bytes = await _withRetry(() => gh.getFilesPage(ref, page + 1));
          parsed = await compute(parseFilesPage, bytes, debugLabel: 'parse files page');
        } catch (e) {
          failed = true;
          if (gen == _generation) {
            filesError = e;
            _notify();
          }
          return;
        }
        if (gen != _generation) return;
        results[page] = parsed;
        var changed = false;
        while (appended < pages && results[appended] != null) {
          files.addAll(results[appended]!);
          results[appended] = null;
          appended++;
          changed = true;
        }
        if (changed) {
          revision++;
          _notify();
        }
      }
    }

    await Future.wait([for (var i = 0; i < math.min(_concurrency, pages); i++) worker()]);
    if (gen != _generation || failed) return;
    filesDone = true;
    filesExpected = files.length;
    revision++;
    _notify();
  }

  Future<T> _withRetry<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on GitHubException catch (e) {
      if (e.isRateLimited || e.isNotFound || e.isUnauthorized) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return run();
    }
  }

  Future<void> _loadConversation(int gen) async {
    try {
      final results = await Future.wait([
        gh.getIssueComments(ref),
        gh.getReviews(ref),
        gh.getReviewComments(ref),
      ]);
      if (gen != _generation) return;
      issueComments = results[0] as List<IssueComment>;
      reviews = results[1] as List<Review>;
      threads = ReviewThread.group(results[2] as List<ReviewComment>);
      _indexThreads();
    } catch (e) {
      if (gen != _generation) return;
      conversationError = e;
    }
    _notify();
  }

  void _indexThreads() {
    final byPath = <String, List<ReviewThread>>{};
    for (final t in threads ?? const <ReviewThread>[]) {
      (byPath[t.path] ??= []).add(t);
    }
    threadsByPath = {for (final e in byPath.entries) e.key: FileThreads(e.value)};
    revision++;
  }

  // ---- Commenting ---------------------------------------------------------

  /// Posts a comment on the conversation. Throws [GitHubException] on failure.
  Future<void> addComment(String body) async {
    final c = await gh.createIssueComment(ref, body);
    issueComments = [...?issueComments, c];
    _notify();
  }

  /// Replies in [thread]; the reply is appended to the same thread object so
  /// open thread views pick it up.
  Future<void> reply(ReviewThread thread, String body) async {
    final c = await gh.replyToReviewComment(ref, thread.root.id, body);
    thread.replies.add(c);
    _indexThreads();
    _notify();
  }

  /// Starts a review thread on [line] of [path]. Deleted lines are commented
  /// on the base side, everything else on the head side.
  Future<ReviewThread> commentOnLine({
    required String path,
    required int line,
    required DiffSide side,
    required String body,
  }) async {
    final c = await gh.createLineComment(
      ref,
      commitId: pr!.head.sha,
      path: path,
      line: line,
      side: side,
      body: body,
    );
    final t = ReviewThread(c);
    threads = [...?threads, t];
    _indexThreads();
    _notify();
    return t;
  }

  Future<void> _loadCommits(int gen) async {
    try {
      final c = await gh.getCommits(ref);
      if (gen != _generation) return;
      commits = c;
    } catch (e) {
      if (gen != _generation) return;
      commitsError = e;
    }
    _notify();
  }

  bool _syncingViewed = false;

  /// Loads "Viewed" marks from GitHub so they match github.com. Needs a
  /// token; without one, or if GitHub refuses, marks stay on the device.
  Future<void> syncViewed() async {
    if (pr == null || _syncingViewed) return;
    if (gh.token == null || gh.token!.isEmpty) {
      viewed.syncFailed(readOnly: false);
      return;
    }
    if (viewed.sync == ViewedSync.readOnly) return;
    _syncingViewed = true;
    viewed.setSyncing();
    try {
      final r = await gh.getViewedStates(ref);
      if (!_disposed) viewed.attachRemote(r.states, (paths, v) => gh.setViewed(r.prId, paths, v));
    } catch (e) {
      if (!_disposed) viewed.syncFailed(readOnly: false);
    } finally {
      _syncingViewed = false;
    }
  }

  Future<void> _loadChecks(int gen) async {
    try {
      final c = await gh.getChecks(ref, pr!.head.sha);
      if (gen != _generation) return;
      checks = c;
      _notify();
    } catch (_) {
      // Checks are a nice-to-have; private repos without the scope 403 here.
    }
  }

  /// Computes the diff of a file GitHub did not return a patch for, from
  /// the full contents of both sides.
  Future<void> loadFullDiff(DiffFile f) async {
    final p = pr;
    if (p == null || f.state == PatchState.loading) return;
    f.state = PatchState.loading;
    f.error = null;
    revision++;
    _notify();
    try {
      final base = _mergeBase ??= await gh.getMergeBase(ref, p.base.sha, p.head.sha);
      final oldText = f.status == FileStatus.added
          ? ''
          : await gh.getRawFile(ref, f.previousPath ?? f.path, base) ?? '';
      final newText = f.status == FileStatus.removed
          ? ''
          : await gh.getRawFile(ref, f.path, p.head.sha) ?? '';
      if (oldText.contains('\u0000') || newText.contains('\u0000')) {
        f.setDiff(const [], const []);
        f.state = PatchState.noTextDiff;
      } else {
        final parsed = await compute(diffTextsArgs, (
          oldText: oldText,
          newText: newText,
        ), debugLabel: 'diff ${f.name}');
        f.setDiff(parsed.lines, parsed.hunks);
        f.state = parsed.lines.isEmpty ? PatchState.noChanges : PatchState.ready;
      }
    } catch (e) {
      f.state = PatchState.failed;
      f.error = e is GitHubException ? e.message : '$e';
    }
    revision++;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    viewed.dispose();
    super.dispose();
  }
}
