import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/windows.dart';
import '../../data/pr_session.dart';
import '../../github/pr_ref.dart';
import '../widgets/common.dart';
import '../widgets/thread_view.dart';
import 'diff_controller.dart';
import 'diff_view.dart';

/// Shares the PR's session with the other windows, so viewed marks and
/// comments stay in sync.
class FileWindowScreen extends StatefulWidget {
  const FileWindowScreen({super.key, required this.prRef, required this.path});

  final PrRef prRef;
  final String path;

  @override
  State<FileWindowScreen> createState() => _FileWindowScreenState();
}

class _FileWindowScreenState extends State<FileWindowScreen> {
  PrSession? _session;
  late final DiffController _diff;
  String? _title;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session != null) return;
    _session = AppScope.of(context).session(widget.prRef);
    _diff = DiffController(_session!, onlyPath: widget.path);
    _session!.addListener(_updateTitle);
    _updateTitle();
  }

  @override
  void dispose() {
    _session?.removeListener(_updateTitle);
    _diff.dispose();
    super.dispose();
  }

  void _updateTitle() {
    final name = widget.path.split('/').last;
    final pr = _session!.pr;
    final title = pr == null ? name : '$name · ${pr.title}';
    if (title == _title) return;
    _title = title;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setWindowTitle(context, title);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            final pr = session.pr;
            final header = Material(
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    if (pr != null) ...[StateBadge(pr.state, dense: true), const SizedBox(width: 10)],
                    Expanded(
                      child: Text(
                        pr == null ? widget.prRef.key : '${pr.title}  ·  ${widget.prRef.slug} #${widget.prRef.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final route = '${widget.prRef.routePath}/files';
                        final windows = AppWindows.maybeOf(context);
                        windows == null ? Navigator.pushNamed(context, route) : windows.open(route);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open PR'),
                    ),
                  ],
                ),
              ),
            );
            final Widget body;
            if (pr == null || _diff.files.isEmpty) {
              final error = session.error;
              body = error != null
                  ? ErrorView(message: describeError(error, hasToken: AppScope.of(context).settings.token != null))
                  : session.filesDone
                  ? const ErrorView(message: 'This file is not part of the PR.')
                  : const LoadingView(message: 'Loading file…');
            } else {
              body = DiffView(
                controller: _diff,
                openThreads: (threads, title) => showThreads(context, threads, title, onReply: session.reply),
              );
            }
            return Column(
              children: [
                header,
                const Divider(height: 1),
                Expanded(child: body),
              ],
            );
          },
        ),
      ),
    );
  }
}
