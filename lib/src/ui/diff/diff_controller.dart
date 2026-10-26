import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../data/pr_session.dart';
import '../../diff/diff_layout.dart';
import '../../diff/diff_models.dart';
import '../../diff/text_metrics.dart';
import '../../github/models.dart';

/// Files with more changed lines than this start collapsed.
const kAutoCollapseLines = 1500;

/// The scroll offset just below the sticky header, used to decide which file
/// is "current".
const _currentProbe = 64.0;

class SearchHits {
  SearchHits(this.query, this.file, this.line, this.start, {required this.capped});

  final String query;
  final Int32List file;
  final Int32List line;
  final Int32List start;

  /// True when the search stopped at [DiffController.maxHits].
  final bool capped;

  int get length => file.length;
}

/// State of the files view: layout, expansion, search and navigation.
/// Shared by the diff, the file tree and the toolbars.
class DiffController extends ChangeNotifier {
  /// [resumeAt] and [expanded] come from a saved [ReadingPosition]; the diff
  /// scrolls to [resumeAt] as soon as its file has loaded.
  DiffController(this.session, {RowAnchor? resumeAt, Map<String, bool> expanded = const {}})
    : _resume = resumeAt {
    _overrides.addAll(expanded);
    session.addListener(_onSessionChanged);
    session.viewed.addListener(_onSessionChanged);
    vertical.addListener(_onScroll);
  }

  static const maxHits = 20000;

  final PrSession session;
  final ScrollController vertical = ScrollController();
  final ScrollController horizontal = ScrollController();

  /// Index of the file at the top of the viewport.
  final ValueNotifier<int> currentFile = ValueNotifier(0);

  /// Explicit expand (true) / collapse (false) choices by path.
  final Map<String, bool> _overrides = {};

  /// Saved position still waiting for its file to load. Dropped once reached
  /// or as soon as the reader scrolls or navigates on their own.
  RowAnchor? _resume;

  LayoutMetrics? _metrics;
  DiffLayout? _layout;
  final List<VoidCallback> _whenLaidOut = [];
  bool _dirty = true;
  int _builtRevision = -1;

  SearchHits? hits;
  int currentHit = -1;
  Timer? _searchDebounce;
  String _query = '';

  /// Offsets (0..1) along the scrollbar of comment threads and search hits.
  Float64List commentMarks = Float64List(0);
  Float64List hitMarks = Float64List(0);

  List<DiffFile> get files => session.files;
  DiffLayout? get layout => _layout;
  String get query => _query;

  /// Explicit expand/collapse choices, saved with the reading position.
  Map<String, bool> get overrides => Map.unmodifiable(_overrides);

  /// The row at the top of the diff, or the saved one while it is pending.
  RowAnchor? get readingAnchor {
    final l = _layout;
    if (_resume != null || l == null || vertical.positions.length != 1 || !vertical.position.hasPixels) {
      return _resume;
    }
    return l.anchorAt(vertical.position.pixels);
  }

  void _onSessionChanged() {
    _dirty = true;
    notifyListeners();
  }

  void _onScroll() {
    final l = _layout;
    if (l == null || vertical.positions.length != 1) return;
    if (_resume != null && vertical.position.userScrollDirection != ScrollDirection.idle) _resume = null;
    final f = l.fileAt(vertical.offset + _currentProbe);
    if (f >= 0) currentFile.value = f;
  }

  // ---- Layout -------------------------------------------------------------

  /// Called by the diff view on every build with the current geometry.
  void updateMetrics(LayoutMetrics m) {
    if (_metrics != null && _metrics!.sameAs(m)) return;
    _metrics = m;
    _dirty = true;
  }

  /// Rebuilds the layout if anything changed, keeping the content at the top
  /// of the viewport in place. Returns true when the layout was rebuilt.
  bool ensureLayout() {
    final m = _metrics;
    if (m == null) return false;
    if (!_dirty && _builtRevision == session.revision && _layout != null) return false;
    final old = _layout;
    final next = DiffLayout.build(
      files: List.unmodifiable(files),
      metrics: m,
      bodyOf: bodyOf,
      threads: session.threadsByPath,
    );
    _layout = next;
    _dirty = false;
    _builtRevision = session.revision;
    _computeMarks();
    if (old != null && vertical.positions.length == 1 && vertical.position.hasPixels) {
      final pixels = vertical.position.pixels;
      final anchor = old.anchorAt(pixels);
      final target = anchor == null ? null : next.resolve(anchor);
      if (target != null && (target - pixels).abs() > 0.5) {
        vertical.position.correctPixels(target);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryResume();
      _onScroll();
      if (_whenLaidOut.isNotEmpty && vertical.hasClients) {
        final pending = [..._whenLaidOut];
        _whenLaidOut.clear();
        for (final f in pending) {
          f();
        }
      }
    });
    return true;
  }

  void _tryResume() {
    final anchor = _resume;
    final l = _layout;
    if (anchor == null || l == null || !vertical.hasClients) return;
    final target = l.resolve(anchor);
    if (target == null) {
      // Its file isn't loaded yet, or is no longer part of the PR.
      if (session.filesDone) _resume = null;
      return;
    }
    _scrollTo(target);
  }

  /// Runs [action] now if the diff is on screen, or right after its first
  /// layout otherwise (e.g. when jumping in from another tab).
  void runWhenLaidOut(VoidCallback action) {
    if (_layout != null && vertical.hasClients) {
      action();
    } else {
      _whenLaidOut.add(action);
      notifyListeners();
    }
  }

  FileBody bodyOf(int i) {
    final f = files[i];
    final o = _overrides[f.path];
    if (o == false) return const HeaderOnlyBody();
    if (o != true && session.viewed.isViewed(f)) return const HeaderOnlyBody();
    switch (f.state) {
      case PatchState.loading:
        return const NoticeBody(NoticeKind.loading);
      case PatchState.failed:
        return const NoticeBody(NoticeKind.failed);
      case PatchState.tooLarge:
        return const NoticeBody(NoticeKind.tooLarge);
      case PatchState.noTextDiff:
        return const NoticeBody(NoticeKind.noTextDiff);
      case PatchState.noChanges:
        return const NoticeBody(NoticeKind.noChanges);
      case PatchState.ready:
        if (o != true) {
          if (f.isGenerated) return const NoticeBody(NoticeKind.hiddenGenerated);
          if (f.lines.length > kAutoCollapseLines) return const NoticeBody(NoticeKind.hiddenLarge);
        }
        return const FullBody();
    }
  }

  bool isExpanded(int i) => bodyOf(i) is! HeaderOnlyBody;

  void _computeMarks() {
    final l = _layout!;
    final total = l.totalExtent <= 0 ? 1.0 : l.totalExtent;
    final comments = <double>[];
    for (var r = 0; r < l.length; r++) {
      if (l.kind[r] == RowKind.comments) comments.add(l.offsets[r] / total);
    }
    commentMarks = Float64List.fromList(comments);
    final h = hits;
    if (h == null || h.length == 0) {
      hitMarks = Float64List(0);
      return;
    }
    final marks = <double>[];
    var last = -1.0;
    for (var k = 0; k < h.length; k++) {
      final row = l.rowOfLine(h.file[k], h.line[k]);
      final y = (row >= 0 ? l.offsets[row] : l.fileOffset(h.file[k])) / total;
      if (y - last > 0.001) {
        marks.add(y);
        last = y;
      }
    }
    hitMarks = Float64List.fromList(marks);
  }

  // ---- Expansion and viewed ------------------------------------------------

  void setExpanded(int i, bool expanded) {
    _overrides[files[i].path] = expanded;
    _relayoutAndNotify();
  }

  void toggleExpanded(int i) {
    final expanded = isExpanded(i);
    final wasCurrent = _isPinned(i);
    setExpanded(i, !expanded);
    if (wasCurrent) jumpToFile(i);
  }

  void expandAll() {
    for (final f in files) {
      _overrides[f.path] = true;
    }
    _relayoutAndNotify();
  }

  void collapseAll() {
    for (final f in files) {
      _overrides[f.path] = false;
    }
    _relayoutAndNotify();
  }

  bool isViewed(int i) => session.viewed.isViewed(files[i]);

  void setViewed(int i, bool viewed) {
    final wasCurrent = _isPinned(i);
    _overrides.remove(files[i].path);
    session.viewed.set(files[i], viewed);
    if (viewed && wasCurrent) {
      _relayoutAndNotify();
      jumpToFile(i);
    }
  }

  void markAllViewed(bool viewed) {
    for (final f in files) {
      _overrides.remove(f.path);
    }
    session.viewed.setAll(files, viewed);
  }

  /// True when file [i]'s header is the sticky one at the top.
  bool _isPinned(int i) {
    final l = _layout;
    if (l == null || !vertical.hasClients || i >= l.headerRow.length) return false;
    return l.fileAt(vertical.offset + _currentProbe) == i &&
        vertical.offset > l.offsets[l.headerRow[i]] + l.metrics.fileGap;
  }

  void _relayoutAndNotify() {
    _dirty = true;
    ensureLayout();
    notifyListeners();
  }

  void loadFullDiff(int i) {
    _overrides[files[i].path] = true;
    session.loadFullDiff(files[i]);
  }

  // ---- Navigation ---------------------------------------------------------

  double get _maxScroll => vertical.hasClients ? vertical.position.maxScrollExtent : double.infinity;

  void _scrollTo(double offset, {bool animate = false}) {
    if (!vertical.hasClients) return;
    _resume = null;
    final l = _layout;
    final viewport = vertical.position.viewportDimension;
    final max = l == null ? _maxScroll : (l.totalExtent - viewport).clamp(0.0, double.infinity);
    final target = offset.clamp(0.0, max);
    final position = vertical.position;
    if (animate && (target - position.pixels).abs() < viewport * 3) {
      vertical.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
    } else if (!position.hasContentDimensions || target <= position.maxScrollExtent) {
      vertical.jumpTo(target);
    } else {
      // The layout just grew (e.g. a file was expanded) and the viewport has
      // not seen the new extent yet, so a jump would be clamped. Set the
      // pixels directly; the new offsets force a relayout that picks them up.
      position.correctPixels(target);
      notifyListeners();
    }
  }

  void jumpToFile(int i, {bool animate = false}) {
    ensureLayout();
    final l = _layout;
    if (l == null || i < 0 || i >= l.headerRow.length) return;
    currentFile.value = i;
    _scrollTo(l.fileOffset(i), animate: animate);
  }

  void nextFile() => jumpToFile((currentFile.value + 1).clamp(0, files.length - 1), animate: true);

  void previousFile() {
    final l = _layout;
    var i = currentFile.value;
    // If the current file's header is scrolled away, go to its top first.
    if (l != null && vertical.hasClients && vertical.offset <= l.fileOffset(i) + 1) i--;
    jumpToFile(i.clamp(0, files.length - 1), animate: true);
  }

  void jumpToLine(int file, int line) {
    if (bodyOf(file) is! FullBody) {
      _overrides[files[file].path] = true;
      _dirty = true;
    }
    ensureLayout();
    final l = _layout;
    if (l == null) return;
    final row = l.rowOfLine(file, line);
    if (row < 0) return jumpToFile(file);
    final viewport = vertical.hasClients ? vertical.position.viewportDimension : 600;
    _scrollTo(l.offsets[row] - viewport * 0.35);
  }

  /// Scrolls to the thread anchored on [line] of the file at [path].
  void jumpToThread(ReviewThread t) {
    final f = files.indexWhere((f) => f.path == t.path);
    if (f < 0) return;
    final line = t.line;
    final lines = files[f].lines;
    if (line != null) {
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final n = t.side == DiffSide.left ? l.oldNo : l.newNo;
        final kindOk = t.side == DiffSide.left ? l.kind != LineKind.add : l.kind != LineKind.del;
        if (n == line && kindOk) return jumpToLine(f, i);
      }
    }
    jumpToFile(f);
  }

  void scrollBy(double delta) {
    if (!vertical.hasClients) return;
    final p = vertical.position;
    final target = (p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent);
    vertical.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  // ---- Search -------------------------------------------------------------

  void search(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () => _runSearch(query));
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    _query = '';
    hits = null;
    currentHit = -1;
    hitMarks = Float64List(0);
    notifyListeners();
  }

  void _runSearch(String query) {
    _query = query;
    if (query.length < 2) {
      hits = null;
      currentHit = -1;
      hitMarks = Float64List(0);
      notifyListeners();
      return;
    }
    final q = query.toLowerCase();
    final fl = <int>[], ln = <int>[], st = <int>[];
    var capped = false;
    outer:
    for (var f = 0; f < files.length; f++) {
      final lines = files[f].lines;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.kind == LineKind.meta || l.text.length < q.length) continue;
        final text = renderText(l.text).toLowerCase();
        var at = text.indexOf(q);
        while (at >= 0) {
          fl.add(f);
          ln.add(i);
          st.add(at);
          if (fl.length >= maxHits) {
            capped = true;
            break outer;
          }
          at = text.indexOf(q, at + q.length);
        }
      }
    }
    hits = SearchHits(
      query,
      Int32List.fromList(fl),
      Int32List.fromList(ln),
      Int32List.fromList(st),
      capped: capped,
    );
    currentHit = -1;
    if (_layout != null) _computeMarks();
    notifyListeners();
    if (fl.isNotEmpty) _goToFirstHitAfterViewport();
  }

  void _goToFirstHitAfterViewport() {
    final h = hits!;
    final l = _layout;
    var target = 0;
    if (l != null && vertical.hasClients) {
      final top = l.rowAt(vertical.offset);
      for (var k = 0; k < h.length; k++) {
        final row = l.rowOfLine(h.file[k], h.line[k]);
        if (row >= top) {
          target = k;
          break;
        }
      }
    }
    goToHit(target);
  }

  void goToHit(int k) {
    final h = hits;
    if (h == null || h.length == 0) return;
    currentHit = k % h.length;
    if (currentHit < 0) currentHit += h.length;
    jumpToLine(h.file[currentHit], h.line[currentHit]);
    notifyListeners();
  }

  void nextHit() => goToHit(currentHit + 1);
  void previousHit() => goToHit(currentHit - 1);

  /// Whether search hit [currentHit] is on line [line] of [file] at [start].
  bool isCurrentHit(int file, int line, int start) {
    final h = hits;
    if (h == null || currentHit < 0) return false;
    return h.file[currentHit] == file && h.line[currentHit] == line && h.start[currentHit] == start;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    session.removeListener(_onSessionChanged);
    session.viewed.removeListener(_onSessionChanged);
    vertical.dispose();
    horizontal.dispose();
    currentFile.dispose();
    super.dispose();
  }
}
