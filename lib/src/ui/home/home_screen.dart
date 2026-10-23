import 'package:flutter/material.dart';

import '../../app/links.dart';
import '../../app/services.dart';
import '../../github/models.dart';
import '../adaptive.dart';
import '../widgets/common.dart';
import 'pull_tile.dart';

const _samples = [
  ('flutter/flutter#171703', '82k lines · 1,912 files'),
  ('flutter/flutter#192649', '50k lines · 1,287 files'),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  String? _error;
  String? _loadedFor;
  Future<List<PullSummary>>? _review;
  Future<List<PullSummary>>? _mine;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _open(String text) {
    final route = routeForText(text);
    if (route == null) {
      setState(() => _error = 'Paste a PR link like github.com/owner/repo/pull/123, or owner/repo#123');
      return;
    }
    setState(() => _error = null);
    Navigator.pushNamed(context, route);
  }

  void _loadInbox(AppServices s) {
    final token = s.settings.token;
    if (token == _loadedFor) return;
    _loadedFor = token;
    if (token == null) {
      _review = _mine = null;
      return;
    }
    _review = s.gh.searchPulls('is:open archived:false review-requested:@me', perPage: 10);
    _mine = s.gh.searchPulls('is:open archived:false author:@me', perPage: 10);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    return Scaffold(
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          _loadInbox(services);
          final size = context.windowSize;
          final pad = size == WindowSize.compact ? 16.0 : 32.0;
          final twoColumns = size >= WindowSize.large;
          final sections = <Widget>[
            if (_review != null)
              _InboxSection(title: 'Review requested', icon: Icons.rate_review_outlined, future: _review!),
            if (_mine != null)
              _InboxSection(title: 'Your pull requests', icon: Icons.person_outline_rounded, future: _mine!),
          ];
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadedFor = '';
                setState(() {});
                await Future.wait([?_review, ?_mine]);
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 40),
                children: [
                  ReadableWidth(
                    maxWidth: twoColumns ? 1200 : 880,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(services: services),
                        SizedBox(height: size == WindowSize.compact ? 20 : 48),
                        _Hero(
                          input: _input,
                          error: _error,
                          onOpen: _open,
                          compact: size == WindowSize.compact,
                        ),
                        const SizedBox(height: 32),
                        if (settings.token == null) ...[const _TokenCard(), const SizedBox(height: 20)],
                        if (sections.isNotEmpty) ...[
                          if (twoColumns)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final (i, s) in sections.indexed) ...[
                                  if (i > 0) const SizedBox(width: 20),
                                  Expanded(child: s),
                                ],
                              ],
                            )
                          else
                            for (final s in sections) ...[s, const SizedBox(height: 20)],
                          const SizedBox(height: 20),
                        ],
                        if (settings.recents.isNotEmpty) const _Recents(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.merge_type_rounded, color: scheme.onPrimary, size: 22),
          ),
          const SizedBox(width: 12),
          Text('PR Reader', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          ValueListenableBuilder<GhUser?>(
            valueListenable: services.viewer,
            builder: (context, user, _) => user == null
                ? const SizedBox.shrink()
                : Padding(padding: const EdgeInsets.only(right: 4), child: Avatar(user, size: 30)),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.input, required this.error, required this.onOpen, required this.compact});

  final TextEditingController input;
  final String? error;
  final ValueChanged<String> onOpen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Read pull requests of any size',
          style: (compact ? theme.textTheme.headlineSmall : theme.textTheme.displaySmall)?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Smooth scrolling through tens of thousands of changed lines, on any screen.',
          style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: input,
          onSubmitted: onOpen,
          textInputAction: TextInputAction.go,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: const TextStyle(fontSize: 16),
          decoration: InputDecoration(
            hintText: compact
                ? 'PR link or owner/repo#123'
                : 'Paste a pull request link, owner/repo#123, or owner/repo',
            prefixIcon: const Icon(Icons.link_rounded),
            errorText: error,
            errorMaxLines: 2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            suffixIcon: Padding(
              padding: const EdgeInsets.all(6),
              child: FilledButton(
                onPressed: () => onOpen(input.text),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Try a giant one:',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            for (final (ref, info) in _samples)
              ActionChip(
                avatar: const Icon(Icons.bolt_rounded, size: 18),
                label: Text('$ref  ·  $info'),
                onPressed: () => onOpen(ref),
              ),
          ],
        ),
      ],
    );
  }
}

class _TokenCard extends StatelessWidget {
  const _TokenCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.key_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add a GitHub token',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Read private repositories, see PRs waiting on you, and raise the rate limit from 60 to 5,000 requests an hour.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxSection extends StatelessWidget {
  const _InboxSection({required this.title, required this.icon, required this.future});

  final String title;
  final IconData icon;
  final Future<List<PullSummary>> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          FutureBuilder<List<PullSummary>>(
            future: future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(describeError(snap.error!, hasToken: true)),
                );
              }
              final items = snap.data;
              if (items == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Text(
                    'Nothing here. Nice.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return Column(
                children: [
                  for (final (i, p) in items.indexed) ...[
                    if (i > 0) const Divider(indent: 46),
                    PullTile(pull: p),
                  ],
                  const SizedBox(height: 6),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Recents extends StatelessWidget {
  const _Recents();

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recent',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: settings.clearRecents, child: const Text('Clear')),
              ],
            ),
          ),
          for (final r in settings.recents.take(12))
            Dismissible(
              key: ValueKey(r.ref.key),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => settings.removeRecent(r.ref),
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.onErrorContainer),
              ),
              child: InkWell(
                onTap: () => Navigator.pushNamed(context, r.ref.routePath),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      StateIcon(r.state, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text('${r.ref.key} · opened ${timeAgo(r.openedAt)}', style: muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
