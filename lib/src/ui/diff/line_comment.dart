import 'package:flutter/material.dart';

import '../../data/pr_session.dart';
import '../../diff/diff_models.dart';
import '../../github/models.dart';
import '../adaptive.dart';
import '../theme.dart';
import '../widgets/comment_composer.dart';

/// Opens a composer for a new review comment on [line] of [file]: a bottom
/// sheet on phones, a dialog elsewhere. Deleted lines are commented on the
/// base side, other lines on the head side, as on github.com.
Future<void> showLineComment(
  BuildContext context, {
  required PrSession session,
  required DiffFile file,
  required DiffLine line,
}) {
  final left = line.kind == LineKind.del;
  final no = left ? line.oldNo : line.newNo;
  final messenger = ScaffoldMessenger.maybeOf(context);

  Widget body(BuildContext sheet) {
    final theme = Theme.of(sheet);
    final d = DiffTheme.of(sheet);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Comment on '),
                      TextSpan(
                        text: '${file.name}:$no',
                        style: const TextStyle(fontFamily: kCodeFont, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(sheet), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: switch (line.kind) {
                LineKind.add => d.addBg,
                LineKind.del => d.delBg,
                _ => theme.colorScheme.surfaceContainerHigh,
              },
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${switch (line.kind) {
                LineKind.add => '+',
                LineKind.del => '-',
                _ => ' ',
              }} ${line.text}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: kCodeFont, fontSize: 12.5, color: d.code),
            ),
          ),
          const SizedBox(height: 12),
          CommentComposer(
            autofocus: true,
            onCancel: () => Navigator.pop(sheet),
            onSubmit: (text) async {
              await session.commentOnLine(
                path: file.path,
                line: no,
                side: left ? DiffSide.left : DiffSide.right,
                body: text,
              );
              if (sheet.mounted) Navigator.pop(sheet);
              messenger?.showSnackBar(
                const SnackBar(content: Text('Comment posted'), behavior: SnackBarBehavior.floating),
              );
            },
          ),
        ],
      ),
    );
  }

  if (context.windowSize == WindowSize.compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
        child: SingleChildScrollView(child: body(sheet)),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (sheet) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(child: body(sheet)),
      ),
    ),
  );
}
