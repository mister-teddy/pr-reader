import 'package:flutter/material.dart';

import '../../github/models.dart';
import '../widgets/common.dart';

class PullTile extends StatelessWidget {
  const PullTile({super.key, required this.pull, this.showRepo = true});

  final PullSummary pull;
  final bool showRepo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return InkWell(
      onTap: () => Navigator.pushNamed(context, pull.ref.routePath),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: StateIcon(pull.state, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pull.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (showRepo) pull.ref.slug,
                      '#${pull.ref.number}',
                      pull.user.login,
                      timeAgo(pull.updatedAt),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                  if (pull.labels.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [for (final l in pull.labels.take(4)) LabelChip(l)],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Avatar(pull.user, size: 28),
          ],
        ),
      ),
    );
  }
}
