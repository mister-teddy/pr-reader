import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../data/pr_session.dart';
import '../../github/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CommitsTab extends StatelessWidget {
  const CommitsTab({super.key, required this.session});

  final PrSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final commits = session.commits;
        if (commits == null) {
          if (session.commitsError != null) {
            return ErrorView(
              message: describeError(
                session.commitsError!,
                hasToken: AppScope.of(context).settings.token != null,
              ),
            );
          }
          return const LoadingView(message: 'Loading commits…');
        }
        if (commits.isEmpty) return const ErrorView(message: 'No commits.', icon: Icons.inbox_outlined);

        // Flatten into day headers and commit rows.
        final rows = <Object>[];
        String? day;
        for (final c in commits) {
          final d = formatDate(c.date);
          if (d != day) {
            rows.add(d);
            day = d;
          }
          rows.add(c);
        }
        final truncated = session.pr!.commits > commits.length;
        final pad = MediaQuery.sizeOf(context).width < 600 ? 12.0 : 24.0;
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
          itemCount: rows.length + (truncated ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == rows.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'GitHub lists the first ${commits.length} of ${session.pr!.commits} commits.',
                  textAlign: TextAlign.center,
                ),
              );
            }
            final r = rows[i];
            return ReadableWidth(
              child: r is String
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.commit_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text('Commits on $r', style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    )
                  : _CommitTile(commit: r as Commit),
            );
          },
        );
      },
    );
  }
}

class _CommitTile extends StatefulWidget {
  const _CommitTile({required this.commit});

  final Commit commit;

  @override
  State<_CommitTile> createState() => _CommitTileState();
}

class _CommitTileState extends State<_CommitTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.commit;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasDetails = c.details.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hasDetails ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.headline,
                        maxLines: _open ? null : 2,
                        overflow: _open ? null : TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (hasDetails)
                      Icon(
                        _open ? Icons.expand_less_rounded : Icons.more_horiz_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    TextButton(
                      onPressed: () => copyText(context, c.sha, message: 'SHA copied'),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(c.shortSha, style: const TextStyle(fontFamily: kCodeFont, fontSize: 12.5)),
                    ),
                    IconButton(
                      tooltip: 'Open on GitHub',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openUrl(c.htmlUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Avatar(c.author ?? GhUser(login: c.authorName, avatarUrl: ''), size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${c.author?.login ?? c.authorName} committed ${timeAgo(c.date)}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    c.details,
                    style: TextStyle(
                      fontFamily: kCodeFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
