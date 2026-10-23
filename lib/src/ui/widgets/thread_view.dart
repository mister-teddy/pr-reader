import 'package:flutter/material.dart';

import '../../diff/diff_models.dart';
import '../../diff/patch_parser.dart';
import '../../github/models.dart';
import '../adaptive.dart';
import '../theme.dart';
import 'comment_composer.dart';
import 'common.dart';
import 'markdown_view.dart';

/// One comment: avatar, author, time and markdown body.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.user,
    required this.body,
    required this.createdAt,
    this.url,
    this.badge,
    this.dense = false,
  });

  final GhUser user;
  final String body;
  final DateTime? createdAt;
  final String? url;
  final Widget? badge;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Avatar(user, size: dense ? 22 : 28),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                user.login,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 8), badge!],
            const SizedBox(width: 8),
            Text(timeAgo(createdAt), style: muted),
            const Spacer(),
            if (url != null && url!.isNotEmpty)
              IconButton(
                tooltip: 'Open on GitHub',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                onPressed: () => openUrl(url!),
              ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(left: dense ? 30 : 36, top: 2),
          child: MarkdownView(body, emptyText: 'No comment.'),
        ),
      ],
    );
  }
}

/// The few diff lines a review comment was made on.
class DiffHunkSnippet extends StatelessWidget {
  const DiffHunkSnippet({super.key, required this.hunk, this.maxLines = 6});

  final String hunk;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final parsed = parsePatch(hunk);
    if (parsed.lines.isEmpty) return const SizedBox.shrink();
    final lines = parsed.lines.length > maxLines
        ? parsed.lines.sublist(parsed.lines.length - maxLines)
        : parsed.lines;
    final d = DiffTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    const style = TextStyle(fontFamily: kCodeFont, fontSize: 12, height: 1.5);
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in lines)
          Container(
            color: switch (l.kind) {
              LineKind.add => d.addBg,
              LineKind.del => d.delBg,
              _ => Colors.transparent,
            },
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${switch (l.kind) {
                LineKind.add => '+',
                LineKind.del => '-',
                _ => ' ',
              }} ${l.text}',
              style: style.copyWith(color: d.code),
              softWrap: false,
            ),
          ),
      ],
    );
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // Rows fill the card, and scroll sideways when a line is longer.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: IntrinsicWidth(child: rows),
          ),
        ),
      ),
    );
  }
}

typedef ReplyToThread = Future<void> Function(ReviewThread thread, String body);

class ThreadCard extends StatefulWidget {
  const ThreadCard({super.key, required this.thread, this.showSnippet = true, this.onJump, this.onReply});

  final ReviewThread thread;
  final bool showSnippet;
  final VoidCallback? onJump;

  /// Shows a reply box when set.
  final ReplyToThread? onReply;

  @override
  State<ThreadCard> createState() => _ThreadCardState();
}

class _ThreadCardState extends State<ThreadCard> {
  ReviewThread get thread => widget.thread;

  @override
  Widget build(BuildContext context) {
    final showSnippet = widget.showSnippet;
    final onJump = widget.onJump;
    final onReply = widget.onReply;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final root = thread.root;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description_outlined, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    root.line == null ? root.path : '${root.path}:${root.line}',
                    style: theme.textTheme.labelMedium?.copyWith(fontFamily: kCodeFont),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (thread.isOutdated)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Outdated', style: theme.textTheme.labelSmall),
                  ),
                if (onJump != null && !thread.isOutdated)
                  TextButton(onPressed: onJump, child: const Text('Show in diff')),
              ],
            ),
            if (showSnippet && root.diffHunk.isNotEmpty) ...[
              const SizedBox(height: 8),
              DiffHunkSnippet(hunk: root.diffHunk),
            ],
            const SizedBox(height: 10),
            for (final (i, c) in thread.all.indexed) ...[
              if (i > 0) const Divider(height: 20),
              CommentTile(user: c.user, body: c.body, createdAt: c.createdAt, url: c.htmlUrl, dense: true),
            ],
            if (onReply != null) ...[
              const SizedBox(height: 12),
              CommentComposer(
                collapsed: true,
                hint: 'Reply…',
                submitLabel: 'Reply',
                onSubmit: (body) async {
                  await onReply(thread, body);
                  // The reply was appended to this thread.
                  if (mounted) setState(() {});
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ThreadList extends StatelessWidget {
  const ThreadList({
    super.key,
    required this.threads,
    this.controller,
    this.onJump,
    this.onReply,
    this.padding,
  });

  final List<ReviewThread> threads;
  final ReplyToThread? onReply;
  final ScrollController? controller;
  final void Function(ReviewThread)? onJump;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView.separated(
        controller: controller,
        padding: padding ?? const EdgeInsets.all(16),
        itemCount: threads.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => ThreadCard(
          thread: threads[i],
          showSnippet: false,
          onJump: onJump == null ? null : () => onJump!(threads[i]),
          onReply: onReply,
        ),
      ),
    );
  }
}

/// Shows threads as a bottom sheet on phones and a dialog elsewhere.
Future<void> showThreads(
  BuildContext context,
  List<ReviewThread> threads,
  String title, {
  ReplyToThread? onReply,
}) {
  final size = context.windowSize;
  Widget header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
        ),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
      ],
    ),
  );
  if (size == WindowSize.compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(
          children: [
            header(context),
            Expanded(
              child: ThreadList(threads: threads, controller: scroll, onReply: onReply),
            ),
          ],
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            header(context),
            Flexible(
              child: ThreadList(threads: threads, onReply: onReply),
            ),
          ],
        ),
      ),
    ),
  );
}
