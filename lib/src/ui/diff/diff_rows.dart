import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/pr_session.dart';
import '../../diff/diff_layout.dart';
import '../../diff/diff_models.dart';
import '../../diff/highlight_cache.dart';
import '../../diff/intraline.dart';
import '../../diff/text_metrics.dart';
import '../../github/models.dart';
import '../adaptive.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'code_spans.dart';
import 'diff_controller.dart';
import 'line_comment.dart';

typedef OpenThreads = void Function(List<ReviewThread> threads, String title);

/// Everything a row needs to paint itself; rebuilt with each layout.
class DiffRowContext {
  DiffRowContext({
    required this.controller,
    required this.layout,
    required this.theme,
    required this.scheme,
    required this.codeStyle,
    required this.strut,
    required this.syntax,
    required this.compact,
    required this.viewportWidth,
    required this.noWrap,
    required this.openThreads,
  }) : lineNoStyle = codeStyle.copyWith(color: theme.lineNo, fontSize: codeStyle.fontSize! * 0.92),
       query = controller.hits?.query;

  final DiffController controller;
  final DiffLayout layout;
  final DiffTheme theme;
  final ColorScheme scheme;
  final TextStyle codeStyle;
  final StrutStyle strut;
  final TextStyle lineNoStyle;
  final bool syntax;

  /// Narrow screen: smaller header, fewer decorations.
  final bool compact;
  final double viewportWidth;

  /// Rows are laid out wider than the viewport and scroll horizontally.
  final bool noWrap;
  final String? query;
  final OpenThreads openThreads;

  PrSession get session => controller.session;
  LayoutMetrics get m => layout.metrics;
  List<DiffFile> get files => layout.files;
}

Widget buildDiffRow(DiffRowContext ctx, int index) {
  final l = ctx.layout;
  final f = l.file[index];
  return switch (l.kind[index]) {
    RowKind.fileHeader => Padding(
      padding: EdgeInsets.only(top: ctx.m.fileGap),
      child: _pinned(ctx, FileHeader(ctx: ctx, index: f)),
    ),
    RowKind.hunk => _pinned(ctx, _HunkRow(ctx: ctx, file: f, hunk: l.a[index])),
    RowKind.line => _LineRow(ctx: ctx, file: f, line: l.a[index]),
    RowKind.split => _SplitRow(ctx: ctx, file: f, left: l.a[index], right: l.b[index]),
    RowKind.notice => _pinned(ctx, _NoticeRow(ctx: ctx, file: f, kind: NoticeKind.values[l.a[index]])),
    RowKind.comments => _pinned(ctx, _CommentsRow(ctx: ctx, file: f, anchorKey: l.b[index])),
    RowKind.fileEnd => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ctx.scheme.outlineVariant)),
      ),
    ),
    _ => _pinned(ctx, _ListEnd(ctx: ctx)),
  };
}

/// Keeps non-code rows at the viewport's left edge while code scrolls
/// horizontally underneath.
Widget _pinned(DiffRowContext ctx, Widget child) {
  if (!ctx.noWrap) return child;
  final h = ctx.controller.horizontal;
  return ClipRect(
    child: AnimatedBuilder(
      animation: h,
      builder: (context, child) =>
          Transform.translate(offset: Offset(h.hasClients ? h.offset : 0, 0), child: child),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: ctx.viewportWidth, child: child),
      ),
    ),
  );
}

String _blobUrl(PrSession s, DiffFile f, {int? line}) {
  final pr = s.pr!;
  final removed = f.status == FileStatus.removed;
  final sha = removed ? pr.base.sha : pr.head.sha;
  final path = removed ? (f.previousPath ?? f.path) : f.path;
  return 'https://github.com/${s.ref.owner}/${s.ref.repo}/blob/$sha/$path${line == null ? '' : '#L$line'}';
}

// ---- File header ------------------------------------------------------------

class FileHeader extends StatelessWidget {
  const FileHeader({super.key, required this.ctx, required this.index, this.elevated = false});

  final DiffRowContext ctx;
  final int index;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final c = ctx.controller;
    final f = ctx.files[index];
    final expanded = c.isExpanded(index);
    final viewed = c.isViewed(index);
    final threads = ctx.session.threadsByPath[f.path]?.all ?? const [];
    final scheme = ctx.scheme;
    final compact = ctx.compact;

    return Material(
      color: ctx.theme.headerBg,
      elevation: elevated ? 3 : 0,
      shadowColor: Colors.black38,
      child: InkWell(
        onTap: () => c.toggleExpanded(index),
        child: Container(
          height: ctx.m.headerExtent,
          padding: EdgeInsets.only(left: compact ? 4 : 8, right: compact ? 0 : 4),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0 : -0.25,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.expand_more_rounded, size: 20, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              FileStatusIcon(f.status),
              const SizedBox(width: 8),
              Expanded(child: PathLabel(file: f)),
              if (threads.isNotEmpty)
                _CommentBadge(
                  count: threads.fold(0, (n, t) => n + t.length),
                  onTap: () => ctx.openThreads(threads, f.name),
                ),
              if (!compact && f.changes > 0) ...[
                const SizedBox(width: 10),
                ChangeCounts(additions: f.additions, deletions: f.deletions),
                const SizedBox(width: 6),
                DiffStatBar(additions: f.additions, deletions: f.deletions),
                const SizedBox(width: 8),
              ],
              _ViewedToggle(viewed: viewed, compact: compact, onChanged: (v) => c.setViewed(index, v)),
              _FileMenu(ctx: ctx, index: index),
            ],
          ),
        ),
      ),
    );
  }
}

class FileStatusIcon extends StatelessWidget {
  const FileStatusIcon(this.status, {super.key, this.size = 18});

  final FileStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = DiffTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (status) {
      FileStatus.added => (Icons.add_box_outlined, d.addFg, 'Added'),
      FileStatus.removed => (Icons.indeterminate_check_box_outlined, d.delFg, 'Deleted'),
      FileStatus.renamed => (Icons.drive_file_move_outline, scheme.tertiary, 'Renamed'),
      FileStatus.copied => (Icons.file_copy_outlined, scheme.tertiary, 'Copied'),
      _ => (Icons.edit_document, const Color(0xFFBF8700), 'Modified'),
    };
    return Tooltip(
      message: label,
      child: Icon(icon, size: size, color: color),
    );
  }
}

/// `dir/` in a muted color followed by the file name. When space runs out
/// the directory is ellipsized first so the name stays readable.
class PathLabel extends StatelessWidget {
  const PathLabel({super.key, required this.file, this.style});

  final DiffFile file;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium!.copyWith(fontSize: 13.5);
    final nameStyle = base.copyWith(fontWeight: FontWeight.w600);
    final dirStyle = base.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final renamed = file.previousPath != null && file.previousPath != file.path;
    final label = LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: file.name, style: nameStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final nameWidth = tp.width + 1;
        tp.dispose();
        final name = Text(file.name, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
        if (file.dir.isEmpty || nameWidth >= constraints.maxWidth - 24) return name;
        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth - nameWidth),
              child: Text(file.dir, style: dirStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            name,
          ],
        );
      },
    );
    return Tooltip(
      message: renamed ? '${file.previousPath} → ${file.path}' : file.path,
      waitDuration: const Duration(milliseconds: 800),
      child: label,
    );
  }
}

class _CommentBadge extends StatelessWidget {
  const _CommentBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$count review comment${count == 1 ? '' : 's'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: scheme.onSecondaryContainer),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewedToggle extends StatelessWidget {
  const _ViewedToggle({required this.viewed, required this.compact, required this.onChanged});

  final bool viewed;
  final bool compact;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      viewed ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
      size: 20,
      color: viewed ? scheme.primary : scheme.onSurfaceVariant,
    );
    if (compact) {
      return IconButton(
        tooltip: viewed ? 'Viewed' : 'Mark as viewed',
        onPressed: () => onChanged(!viewed),
        icon: icon,
        visualDensity: VisualDensity.compact,
      );
    }
    return Tooltip(
      message: viewed ? 'Unmark as viewed' : 'Mark as viewed (v)',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!viewed),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: viewed ? scheme.primaryContainer.withValues(alpha: 0.6) : null,
            border: Border.all(color: viewed ? Colors.transparent : scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: 4),
              Text('Viewed', style: TextStyle(fontSize: 13, color: scheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileMenu extends StatelessWidget {
  const _FileMenu({required this.ctx, required this.index});

  final DiffRowContext ctx;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = ctx.controller;
    final f = ctx.files[index];
    final expanded = c.isExpanded(index);
    return PopupMenuButton<String>(
      tooltip: 'File actions',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'copy':
            copyText(context, f.path, message: 'Path copied');
          case 'open':
            openUrl(_blobUrl(ctx.session, f));
          case 'toggle':
            c.toggleExpanded(index);
          case 'full':
            c.loadFullDiff(index);
          case 'comments':
            ctx.openThreads(ctx.session.threadsByPath[f.path]!.all, f.name);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'toggle', child: Text(expanded ? 'Collapse file' : 'Expand file')),
        const PopupMenuItem(value: 'copy', child: Text('Copy path')),
        if (ctx.session.pr != null) const PopupMenuItem(value: 'open', child: Text('View file on GitHub')),
        if (f.state == PatchState.tooLarge || f.state == PatchState.failed)
          const PopupMenuItem(value: 'full', child: Text('Load full diff')),
        if (ctx.session.threadsByPath[f.path] != null)
          const PopupMenuItem(value: 'comments', child: Text('Show comments')),
      ],
    );
  }
}

// ---- Hunk, notice, comments, end ---------------------------------------------

class _HunkRow extends StatelessWidget {
  const _HunkRow({required this.ctx, required this.file, required this.hunk});

  final DiffRowContext ctx;
  final int file;
  final int hunk;

  @override
  Widget build(BuildContext context) {
    final f = ctx.files[file];
    final h = f.hunks[hunk];
    final gutter = ctx.m.split ? 0.0 : ctx.m.gutterWidth(f.maxLineNo) - ctx.m.signWidth;
    return Container(
      color: ctx.theme.hunkBg,
      child: Row(
        children: [
          SizedBox(
            width: math.max(gutter, 36),
            child: Icon(Icons.unfold_more_rounded, size: 16, color: ctx.theme.hunkFg),
          ),
          Expanded(
            child: Text(
              h.header,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ctx.codeStyle.copyWith(
                color: ctx.theme.hunkFg,
                fontSize: ctx.codeStyle.fontSize! * 0.95,
              ),
              textScaler: TextScaler.noScaling,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.ctx, required this.file, required this.kind});

  final DiffRowContext ctx;
  final int file;
  final NoticeKind kind;

  @override
  Widget build(BuildContext context) {
    final c = ctx.controller;
    final f = ctx.files[file];
    final scheme = ctx.scheme;
    final lines = formatCount(f.lines.isEmpty ? f.changes : f.lines.length);
    final (IconData icon, String text, String? action, VoidCallback? onAction) = switch (kind) {
      NoticeKind.hiddenLarge => (
        Icons.unfold_more_rounded,
        'Large diff · $lines lines hidden',
        'Show diff',
        () => c.setExpanded(file, true),
      ),
      NoticeKind.hiddenGenerated => (
        Icons.auto_awesome_outlined,
        'Generated or lock file · $lines lines hidden',
        'Show diff',
        () => c.setExpanded(file, true),
      ),
      NoticeKind.tooLarge => (
        Icons.data_object_rounded,
        'GitHub does not return diffs this large · ${formatCount(f.changes)} lines',
        'Load diff',
        () => c.loadFullDiff(file),
      ),
      NoticeKind.loading => (Icons.hourglass_top_rounded, 'Computing diff…', null, null),
      NoticeKind.failed => (
        Icons.error_outline_rounded,
        'Could not load this diff${f.error == null ? '' : ': ${f.error}'}',
        'Retry',
        () => c.loadFullDiff(file),
      ),
      NoticeKind.noTextDiff => (
        Icons.insert_drive_file_outlined,
        'Binary or empty file · no text diff',
        ctx.session.pr == null ? null : 'View file',
        () => openUrl(_blobUrl(ctx.session, f)),
      ),
      NoticeKind.noChanges => (
        Icons.drive_file_rename_outline,
        f.status == FileStatus.renamed ? 'File renamed without changes' : 'No content changes',
        null,
        null,
      ),
    };
    return Container(
      color: scheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (kind == NoticeKind.loading)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: onAction,
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(action),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentsRow extends StatelessWidget {
  const _CommentsRow({required this.ctx, required this.file, required this.anchorKey});

  final DiffRowContext ctx;
  final int file;
  final int anchorKey;

  @override
  Widget build(BuildContext context) {
    final f = ctx.files[file];
    final threads = ctx.session.threadsByPath[f.path]?.byKey[anchorKey] ?? const [];
    if (threads.isEmpty) return const SizedBox.shrink();
    final scheme = ctx.scheme;
    final right = anchorKey & 1 == 1;
    final gutter = ctx.m.gutterWidth(f.maxLineNo);
    final indent = ctx.m.split && right ? ctx.m.width / 2 + gutter : gutter;
    final count = threads.fold(0, (n, t) => n + t.length);
    final root = threads.first.root;
    final users = <String, GhUser>{
      for (final t in threads)
        for (final c in t.all) c.user.login: c.user,
    };
    return Container(
      color: scheme.surfaceContainerLowest,
      padding: EdgeInsets.only(left: math.min(indent, ctx.viewportWidth * 0.5), right: 12),
      alignment: Alignment.centerLeft,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => ctx.openThreads(threads, '${f.name}:${anchorKey >> 1}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final u in users.values.take(3))
                  Padding(padding: const EdgeInsets.only(right: 2), child: Avatar(u, size: 22)),
                const SizedBox(width: 6),
                Text(
                  '$count comment${count == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      root.body.replaceAll(RegExp(r'\s+'), ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSecondaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListEnd extends StatelessWidget {
  const _ListEnd({required this.ctx});

  final DiffRowContext ctx;

  @override
  Widget build(BuildContext context) {
    final s = ctx.session;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget child;
    if (s.filesError != null) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Some files failed to load.', style: muted),
          TextButton(onPressed: s.retryFiles, child: const Text('Retry')),
        ],
      );
    } else if (!s.filesDone) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              value: s.filesExpected == 0 ? null : s.files.length / s.filesExpected,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Loading files… ${formatCount(s.files.length)} of ${formatCount(s.filesExpected)}',
            style: muted,
          ),
        ],
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: theme.colorScheme.outline),
          const SizedBox(height: 6),
          Text(
            'End of changes · ${formatCount(s.files.length)} files · ${formatCount(ctx.layout.lineCount)} lines',
            style: muted,
          ),
          if (s.truncatedByApi)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'GitHub\'s API lists only the first ${formatCount(PrSession.maxFiles)} of '
                '${formatCount(s.pr!.changedFiles)} files.',
                style: muted,
              ),
            ),
        ],
      );
    }
    return Center(child: child);
  }
}

// ---- Code lines ---------------------------------------------------------------

({Color bg, Color gutter, String sign}) _lineColors(DiffRowContext ctx, LineKind kind) {
  final t = ctx.theme;
  return switch (kind) {
    LineKind.add => (bg: t.addBg, gutter: t.addGutter, sign: '+'),
    LineKind.del => (bg: t.delBg, gutter: t.delGutter, sign: '−'),
    _ => (bg: Colors.transparent, gutter: Colors.transparent, sign: ''),
  };
}

Widget _code(DiffRowContext ctx, int fileIndex, int index, {required int cols}) {
  final f = ctx.files[fileIndex];
  final line = f.lines[index];
  if (line.kind == LineKind.meta) {
    return Text(
      line.text,
      style: ctx.codeStyle.copyWith(color: ctx.theme.lineNo, fontStyle: FontStyle.italic),
      strutStyle: ctx.strut,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
    );
  }
  final display = renderText(line.text);
  final breaks = !ctx.noWrap && (line.cols > cols || line.wide) ? wrapBreaks(display, cols) : const <int>[];
  (int, int)? emphasis;
  final pair = line.kind == LineKind.context ? -1 : Intraline.pairOf(f, index);
  if (pair >= 0) emphasis = Intraline.changedRange(display, renderText(f.lines[pair].text));
  final spans = buildCodeSpans(
    text: display,
    theme: ctx.theme,
    tokens: ctx.syntax ? HighlightCache.tokens(f, index) : null,
    emphasis: emphasis,
    emphasisColor: line.kind == LineKind.add ? ctx.theme.addWord : ctx.theme.delWord,
    query: ctx.query,
    isCurrentHit: (start) => ctx.controller.isCurrentHit(fileIndex, index, start),
    breaks: breaks,
  );
  return Text.rich(
    TextSpan(style: ctx.codeStyle, children: spans),
    strutStyle: ctx.strut,
    softWrap: false,
    overflow: TextOverflow.clip,
    textScaler: TextScaler.noScaling,
  );
}

Widget _number(DiffRowContext ctx, int n, double width, Color bg) {
  return Container(
    width: width,
    color: bg,
    padding: const EdgeInsets.only(right: LayoutMetrics.numberPadding / 2),
    alignment: Alignment.topRight,
    child: n == 0
        ? null
        : Text(
            '$n',
            style: ctx.lineNoStyle,
            strutStyle: ctx.strut,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
          ),
  );
}

Widget _sign(DiffRowContext ctx, String sign, LineKind kind) {
  return SizedBox(
    width: ctx.m.signWidth,
    child: Text(
      sign,
      textAlign: TextAlign.center,
      style: ctx.codeStyle.copyWith(
        color: kind == LineKind.add ? ctx.theme.addFg : ctx.theme.delFg,
        fontWeight: FontWeight.w600,
      ),
      strutStyle: ctx.strut,
      textScaler: TextScaler.noScaling,
    ),
  );
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.ctx, required this.file, required this.line});

  final DiffRowContext ctx;
  final int file;
  final int line;

  @override
  Widget build(BuildContext context) {
    final f = ctx.files[file];
    final l = f.lines[line];
    final colors = _lineColors(ctx, l.kind);
    final numW = ctx.m.numberColumnWidth(f.maxLineNo);
    return _LineGestures(
      ctx: ctx,
      file: file,
      line: line,
      gutter: ctx.m.compactGutter ? numW : numW * 2,
      child: ColoredBox(
        color: colors.bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ctx.m.compactGutter)
              _number(ctx, l.kind == LineKind.del ? l.oldNo : l.newNo, numW, colors.gutter)
            else ...[
              _number(ctx, l.oldNo, numW, colors.gutter),
              _number(ctx, l.newNo, numW, colors.gutter),
            ],
            _sign(ctx, colors.sign, l.kind),
            Expanded(child: _code(ctx, file, line, cols: ctx.m.codeColumns(f.maxLineNo))),
          ],
        ),
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.ctx, required this.file, required this.left, required this.right});

  final DiffRowContext ctx;
  final int file;
  final int left;
  final int right;

  Widget _side(DiffFile f, int index, bool isLeft, int cols) {
    if (index < 0) {
      return ColoredBox(color: ctx.scheme.surfaceContainerLow, child: const SizedBox.expand());
    }
    final l = f.lines[index];
    final colors = _lineColors(ctx, l.kind);
    final numW = ctx.m.numberColumnWidth(f.maxLineNo);
    return _LineGestures(
      ctx: ctx,
      file: file,
      line: index,
      gutter: numW,
      child: ColoredBox(
        color: colors.bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _number(ctx, isLeft ? l.oldNo : l.newNo, numW, colors.gutter),
            _sign(ctx, colors.sign, l.kind),
            Expanded(child: _code(ctx, file, index, cols: cols)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = ctx.files[file];
    final cols = ctx.m.codeColumns(f.maxLineNo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _side(f, left, true, cols)),
        ColoredBox(color: ctx.scheme.outlineVariant, child: const SizedBox(width: 1)),
        Expanded(child: _side(f, right, false, cols)),
      ],
    );
  }
}

/// Long-press (touch) or right-click (mouse) on a line opens line actions,
/// including commenting. With a mouse, hovering a line also shows a "+"
/// button at the end of the line numbers, like github.com.
class _LineGestures extends StatefulWidget {
  const _LineGestures({
    required this.ctx,
    required this.file,
    required this.line,
    required this.gutter,
    required this.child,
  });

  final DiffRowContext ctx;
  final int file;
  final int line;

  /// Width of the line-number columns, where the "+" button sits.
  final double gutter;
  final Widget child;

  @override
  State<_LineGestures> createState() => _LineGesturesState();
}

class _LineGesturesState extends State<_LineGestures> {
  bool _hover = false;

  DiffRowContext get ctx => widget.ctx;
  int get file => widget.file;
  int get line => widget.line;

  bool get _commentable {
    final l = ctx.files[file].lines[line];
    return ctx.session.pr != null &&
        l.kind != LineKind.meta &&
        (l.kind == LineKind.del ? l.oldNo : l.newNo) > 0;
  }

  void _comment(BuildContext context) => showLineComment(
    context,
    session: ctx.session,
    file: ctx.files[file],
    line: ctx.files[file].lines[line],
  );

  Future<void> _menu(BuildContext context, Offset global) async {
    final f = ctx.files[file];
    final l = f.lines[line];
    final no = l.kind == LineKind.del ? l.oldNo : l.newNo;
    final ft = ctx.session.threadsByPath[f.path];
    final threads = [
      ...?ft?.byKey[threadKey(l.oldNo, DiffSide.left)],
      if (l.newNo > 0) ...?ft?.byKey[threadKey(l.newNo, DiffSide.right)],
    ];
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(global);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        if (_commentable) PopupMenuItem(value: 'comment', child: Text('Comment on line $no')),
        const PopupMenuItem(value: 'line', child: Text('Copy line')),
        const PopupMenuItem(value: 'path', child: Text('Copy path')),
        if (ctx.session.pr != null && l.kind != LineKind.del)
          PopupMenuItem(value: 'open', child: Text('View line $no on GitHub')),
        if (threads.isNotEmpty) const PopupMenuItem(value: 'threads', child: Text('Show comments')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'comment':
        _comment(context);
      case 'line':
        copyText(context, l.text, message: 'Line copied');
      case 'path':
        copyText(context, f.path, message: 'Path copied');
      case 'open':
        openUrl(_blobUrl(ctx.session, f, line: no));
      case 'threads':
        ctx.openThreads(threads, '${f.name}:$no');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (d) => _menu(context, d.globalPosition),
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: widget.child,
    );
    if (!isDesktopPlatform && !kIsWebDesktopLike) return child;
    if (_commentable) {
      child = Stack(
        children: [
          child,
          if (_hover)
            Positioned(
              left: (widget.gutter - 18).clamp(0.0, double.infinity),
              top: 1,
              child: Tooltip(
                message: 'Comment on this line',
                child: Material(
                  color: ctx.scheme.primary,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => _comment(context),
                    child: Icon(Icons.add_rounded, size: 18, color: ctx.scheme.onPrimary),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: child,
    );
  }
}
