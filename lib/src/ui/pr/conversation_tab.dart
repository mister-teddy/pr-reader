import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../data/pr_session.dart';
import '../../github/models.dart';
import '../theme.dart';
import '../widgets/comment_composer.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import '../widgets/thread_view.dart';

sealed class _Item {
  DateTime get at;
}

class _CommentItem extends _Item {
  _CommentItem(this.comment);
  final IssueComment comment;
  @override
  DateTime get at => comment.createdAt ?? DateTime(0);
}

class _ReviewItem extends _Item {
  _ReviewItem(this.review, this.threads);
  final Review review;
  final List<ReviewThread> threads;
  @override
  DateTime get at => review.submittedAt ?? DateTime(0);
}

/// Description, comments and reviews in time order, with PR details in a
/// sidebar on wide windows and inline on phones.
class ConversationTab extends StatelessWidget {
  const ConversationTab({super.key, required this.session, required this.onShowInDiff});

  final PrSession session;
  final void Function(ReviewThread) onShowInDiff;

  List<_Item> _timeline() {
    final threads = session.threads ?? const <ReviewThread>[];
    final byReview = <int, List<ReviewThread>>{};
    for (final t in threads) {
      final id = t.root.reviewId;
      if (id != null) (byReview[id] ??= []).add(t);
    }
    final items = <_Item>[
      for (final c in session.issueComments ?? const <IssueComment>[]) _CommentItem(c),
      for (final r in session.reviews ?? const <Review>[])
        if (r.body.trim().isNotEmpty || byReview.containsKey(r.id) || r.state != ReviewState.commented)
          _ReviewItem(r, byReview[r.id] ?? const []),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final pr = session.pr!;
        final items = _timeline();
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final pad = constraints.maxWidth < 600 ? 12.0 : 24.0;
            final loading = session.issueComments == null && session.conversationError == null;

            Widget itemAt(int i) {
              // 0: summary (phones), 1: description, then timeline, then footer.
              if (i == 0) return wide ? _Title(pr: pr) : _Summary(session: session);
              if (i == 1) return _Description(pr: pr);
              final k = i - 2;
              if (k < items.length) {
                return switch (items[k]) {
                  _CommentItem(:final comment) => _Card(
                    child: CommentTile(
                      user: comment.user,
                      body: comment.body,
                      createdAt: comment.createdAt,
                      url: comment.htmlUrl,
                      badge: _association(context, comment.authorAssociation),
                    ),
                  ),
                  _ReviewItem(:final review, :final threads) => _ReviewCard(
                    review: review,
                    threads: threads,
                    onShowInDiff: onShowInDiff,
                    onReply: session.reply,
                  ),
                };
              }
              if (loading) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (session.conversationError != null) {
                return ErrorView(
                  message: describeError(
                    session.conversationError!,
                    hasToken: AppScope.of(context).settings.token != null,
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: _Card(child: CommentComposer(onSubmit: session.addComment)),
              );
            }

            final list = SelectionArea(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
                itemCount: items.length + 3,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) => ReadableWidth(maxWidth: 860, child: itemAt(i)),
              ),
            );
            if (!wide) return list;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: list),
                SizedBox(
                  width: 320,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                    child: _Sidebar(session: session),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

Widget? _association(BuildContext context, String? a) {
  final label = switch (a) {
    'OWNER' => 'Owner',
    'MEMBER' => 'Member',
    'COLLABORATOR' => 'Collaborator',
    'CONTRIBUTOR' => 'Contributor',
    _ => null,
  };
  if (label == null) return null;
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: scheme.outlineVariant),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}

class _Title extends StatelessWidget {
  const _Title({required this.pr});

  final PullRequest pr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: pr.title),
              TextSpan(
                text: '  #${pr.ref.number}',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _MergeLine(pr: pr),
      ],
    );
  }
}

class _MergeLine extends StatelessWidget {
  const _MergeLine({required this.pr});

  final PullRequest pr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final verb = switch (pr.state) {
      PrState.merged => 'merged',
      PrState.closed => 'wants to merge',
      _ => 'wants to merge',
    };
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StateBadge(pr.state),
        Avatar(pr.user, size: 20),
        Text(pr.user.login, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text('$verb ${formatCount(pr.commits)} commit${pr.commits == 1 ? '' : 's'} into', style: muted),
        _BranchChip(pr.base.label.isEmpty ? pr.base.ref : pr.base.ref),
        Text('from', style: muted),
        _BranchChip(
          pr.head.repoFullName != null && pr.head.repoFullName != pr.ref.slug ? pr.head.label : pr.head.ref,
        ),
      ],
    );
  }
}

class _BranchChip extends StatelessWidget {
  const _BranchChip(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => copyText(context, name, message: 'Branch name copied'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          name,
          style: TextStyle(fontFamily: kCodeFont, fontSize: 12, color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// Header for phones: title, state, branches, stats, labels and reviewers.
class _Summary extends StatelessWidget {
  const _Summary({required this.session});

  final PrSession session;

  @override
  Widget build(BuildContext context) {
    final pr = session.pr!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pr.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _MergeLine(pr: pr),
        const SizedBox(height: 14),
        _Stats(session: session),
        if (pr.labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final l in pr.labels) LabelChip(l)]),
        ],
        const SizedBox(height: 12),
        _Reviewers(session: session, dense: true),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.session});

  final PrSession session;

  @override
  Widget build(BuildContext context) {
    final pr = session.pr!;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final checks = session.checks;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChangeCounts(additions: pr.additions, deletions: pr.deletions, fontSize: 13),
        Text('${formatCount(pr.changedFiles)} files', style: muted),
        Text('${formatCount(pr.commits)} commits', style: muted),
        if (checks != null && checks.total > 0) _ChecksLine(checks: checks),
      ],
    );
  }
}

class _ChecksLine extends StatelessWidget {
  const _ChecksLine({required this.checks});

  final CheckSummary checks;

  @override
  Widget build(BuildContext context) {
    final d = DiffTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = checks.failure > 0
        ? (Icons.cancel_rounded, d.delFg)
        : checks.pending > 0
        ? (Icons.pending_rounded, const Color(0xFFBF8700))
        : (Icons.check_circle_rounded, d.addFg);
    final parts = [
      if (checks.success > 0) '${checks.success} passed',
      if (checks.failure > 0) '${checks.failure} failed',
      if (checks.pending > 0) '${checks.pending} pending',
      if (checks.neutral > 0) '${checks.neutral} skipped',
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(parts.join(' · '), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Description extends StatelessWidget {
  const _Description({required this.pr});

  final PullRequest pr;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: CommentTile(user: pr.user, body: pr.body, createdAt: pr.createdAt, url: pr.htmlUrl),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.threads,
    required this.onShowInDiff,
    required this.onReply,
  });

  final Review review;
  final List<ReviewThread> threads;
  final void Function(ReviewThread) onShowInDiff;
  final ReplyToThread onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = DiffTheme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String verb) = switch (review.state) {
      ReviewState.approved => (Icons.check_circle_rounded, d.addFg, 'approved these changes'),
      ReviewState.changesRequested => (Icons.change_circle_rounded, d.delFg, 'requested changes'),
      ReviewState.dismissed => (
        Icons.remove_circle_outline_rounded,
        scheme.outline,
        'had a review dismissed',
      ),
      _ => (Icons.rate_review_outlined, scheme.onSurfaceVariant, 'reviewed'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Avatar(review.user, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: review.user.login,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' $verb · ${timeAgo(review.submittedAt)}'),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        if (review.body.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          _Card(child: MarkdownView(review.body)),
        ],
        for (final t in threads) ...[
          const SizedBox(height: 8),
          ThreadCard(thread: t, onJump: () => onShowInDiff(t), onReply: onReply),
        ],
      ],
    );
  }
}

class _Reviewers extends StatelessWidget {
  const _Reviewers({required this.session, this.dense = false});

  final PrSession session;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pr = session.pr!;
    final d = DiffTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final latest = <String, Review>{};
    for (final r in session.reviews ?? const <Review>[]) {
      if (r.user.login == pr.user.login) continue;
      final prev = latest[r.user.login];
      // A plain comment doesn't replace an approval or change request.
      if (prev != null && r.state == ReviewState.commented && prev.state != ReviewState.commented) continue;
      latest[r.user.login] = r;
    }
    final entries = <(GhUser, Widget)>[
      for (final r in latest.values)
        (
          r.user,
          switch (r.state) {
            ReviewState.approved => Icon(Icons.check_rounded, size: 16, color: d.addFg),
            ReviewState.changesRequested => Icon(Icons.close_rounded, size: 16, color: d.delFg),
            _ => Icon(Icons.chat_bubble_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
          },
        ),
      for (final u in pr.requestedReviewers)
        if (!latest.containsKey(u.login))
          (u, Icon(Icons.schedule_rounded, size: 15, color: const Color(0xFFBF8700))),
    ];
    if (entries.isEmpty && pr.requestedTeams.isEmpty) {
      return dense
          ? const SizedBox.shrink()
          : Text('No reviews yet', style: TextStyle(color: scheme.onSurfaceVariant));
    }
    if (dense) {
      return Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final (u, icon) in entries)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [Avatar(u, size: 22), const SizedBox(width: 2), icon],
            ),
          for (final t in pr.requestedTeams)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups_outlined, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(t, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
        ],
      );
    }
    return Column(
      children: [
        for (final (u, icon) in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Avatar(u, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(u.login, overflow: TextOverflow.ellipsis)),
                icon,
              ],
            ),
          ),
        for (final t in pr.requestedTeams)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.groups_outlined, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.session});

  final PrSession session;

  @override
  Widget build(BuildContext context) {
    final pr = session.pr!;
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('Changes', _Stats(session: session)),
        section('Reviewers', _Reviewers(session: session)),
        section(
          'Assignees',
          pr.assignees.isEmpty
              ? Text('No one', style: muted)
              : Column(
                  children: [
                    for (final u in pr.assignees)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [Avatar(u, size: 22), const SizedBox(width: 8), Text(u.login)]),
                      ),
                  ],
                ),
        ),
        section(
          'Labels',
          pr.labels.isEmpty
              ? Text('None', style: muted)
              : Wrap(spacing: 6, runSpacing: 6, children: [for (final l in pr.labels) LabelChip(l)]),
        ),
        if (pr.milestone != null) section('Milestone', Text(pr.milestone!)),
        section(
          'Timeline',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Opened ${formatDate(pr.createdAt)}', style: muted),
              if (pr.mergedAt != null)
                Text(
                  'Merged ${formatDate(pr.mergedAt)}${pr.mergedBy == null ? '' : ' by ${pr.mergedBy!.login}'}',
                  style: muted,
                )
              else if (pr.closedAt != null)
                Text('Closed ${formatDate(pr.closedAt)}', style: muted),
              Text('Updated ${timeAgo(pr.updatedAt)}', style: muted),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => openUrl(pr.htmlUrl),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Open on GitHub'),
        ),
      ],
    );
  }
}
