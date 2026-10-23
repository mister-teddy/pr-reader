import 'generated_files.dart';
import 'text_metrics.dart';

enum FileStatus {
  added,
  removed,
  modified,
  renamed,
  copied,
  changed,
  unchanged;

  static FileStatus parse(String? s) => switch (s) {
    'added' => added,
    'removed' => removed,
    'renamed' => renamed,
    'copied' => copied,
    'changed' => changed,
    'unchanged' => unchanged,
    _ => modified,
  };
}

enum LineKind { context, add, del, meta }

/// One line of a diff. Line numbers are 0 when not applicable.
final class DiffLine {
  DiffLine(this.kind, this.oldNo, this.newNo, this.text)
    : cols = displayColumns(text),
      wide = hasWideChars(text);

  final LineKind kind;
  final int oldNo;
  final int newNo;
  final String text;

  /// Width in monospace columns once tabs are expanded.
  final int cols;

  /// Whether the text has characters that render wider than one column.
  final bool wide;
}

final class DiffHunk {
  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.section,
    required this.start,
    required this.end,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  /// The text after the closing `@@`, usually the enclosing function.
  final String section;

  /// Range of this hunk in [DiffFile.lines]: `[start, end)`.
  final int start;
  final int end;

  String get header {
    final range = '@@ -$oldStart,$oldCount +$newStart,$newCount @@';
    return section.isEmpty ? range : '$range $section';
  }
}

enum PatchState {
  /// [DiffFile.lines] holds the diff.
  ready,

  /// GitHub omitted the patch because it is too large; it can be computed locally.
  tooLarge,

  /// Binary or empty file.
  noTextDiff,

  /// Renamed or mode change with no content changes.
  noChanges,

  loading,
  failed,
}

class DiffFile {
  DiffFile({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    this.previousPath,
    this.blobSha,
    List<DiffLine> lines = const [],
    List<DiffHunk> hunks = const [],
    this.state = PatchState.ready,
  }) {
    setDiff(lines, hunks);
  }

  final String path;
  final String? previousPath;
  final FileStatus status;
  final int additions;
  final int deletions;
  final String? blobSha;

  late List<DiffLine> lines;
  late List<DiffHunk> hunks;
  PatchState state;
  String? error;

  /// Largest line number, for sizing the gutter.
  int maxLineNo = 0;

  /// Widest line, in columns.
  int maxCols = 0;

  void setDiff(List<DiffLine> lines, List<DiffHunk> hunks) {
    this.lines = lines;
    this.hunks = hunks;
    var maxNo = 0, maxC = 0;
    for (final l in lines) {
      if (l.oldNo > maxNo) maxNo = l.oldNo;
      if (l.newNo > maxNo) maxNo = l.newNo;
      if (l.cols > maxC) maxC = l.cols;
    }
    maxLineNo = maxNo;
    maxCols = maxC;
  }

  int get changes => additions + deletions;

  bool get isGenerated => isLikelyGenerated(path);

  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  String get dir {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i + 1);
  }

  String get extension {
    final n = name;
    final i = n.lastIndexOf('.');
    return i <= 0 ? '' : n.substring(i + 1).toLowerCase();
  }
}

/// Git's path ordering: plain code-unit comparison.
int comparePaths(String a, String b) => a.compareTo(b);
