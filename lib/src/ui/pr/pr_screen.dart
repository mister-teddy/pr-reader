import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../data/pr_session.dart';
import '../../github/models.dart';
import '../../github/pr_ref.dart';
import '../diff/diff_controller.dart';
import '../diff/files_tab.dart';
import '../widgets/common.dart';
import 'commits_tab.dart';
import 'conversation_tab.dart';

enum PrTab { conversation, commits, files }

class PrScreen extends StatefulWidget {
  const PrScreen({super.key, required this.prRef, this.initialTab = PrTab.conversation});

  final PrRef prRef;
  final PrTab initialTab;

  @override
  State<PrScreen> createState() => _PrScreenState();
}

class _PrScreenState extends State<PrScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: PrTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  )..addListener(_onTab);
  final Set<int> _visited = {};
  PrSession? _session;
  DiffController? _diff;
  bool _immersive = false;

  /// Header hidden because the reader scrolled down the diff (small screens).
  bool _autoHidden = false;
  bool _recorded = false;

  /// Picks up "Viewed" changes made on github.com while the app was away.
  AppLifecycleListener? _lifecycle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = AppScope.of(context).session(widget.prRef);
      _session!.addListener(_onSession);
      _lifecycle = AppLifecycleListener(onResume: _session!.syncViewed);
      _visited.add(_tabs.index);
      _onSession();
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _session?.removeListener(_onSession);
    _diff?.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_visited.add(_tabs.index) || _tabs.indexIsChanging) setState(() {});
  }

  void _onSession() {
    final pr = _session?.pr;
    if (pr != null && !_recorded) {
      _recorded = true;
      AppScope.of(context).settings.addRecent(pr);
    }
    if (pr != null && _diff == null) _diff = DiffController(_session!);
  }

  /// Hides the header while reading down the diff and brings it back on the
  /// way up, like a browser toolbar, to free space on phones.
  bool _onScroll(ScrollNotification n, bool enabled) {
    if (!enabled || n.metrics.axis != Axis.vertical) return false;
    var hide = _autoHidden;
    // Only finger/trackpad drags toggle it; jumps and the scrubber don't.
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final delta = n.scrollDelta ?? 0;
      if (delta > 2 && n.metrics.pixels > 120) hide = true;
      if (delta < -2) hide = false;
    }
    if (n.metrics.pixels <= 0) hide = false;
    if (hide != _autoHidden) setState(() => _autoHidden = hide);
    return false;
  }

  void _showInDiff(ReviewThread t) {
    _tabs.animateTo(PrTab.files.index);
    _visited.add(PrTab.files.index);
    setState(() {});
    _diff?.runWhenLaidOut(() => _diff?.jumpToThread(t));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final pr = session.pr;
        if (pr == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.prRef.key)),
            body: session.error != null
                ? ErrorView(
                    message: describeError(
                      session.error!,
                      hasToken: AppScope.of(context).settings.token != null,
                    ),
                    onRetry: session.load,
                  )
                : const LoadingView(message: 'Loading pull request…'),
          );
        }
        final filesTab = _tabs.index == PrTab.files.index;
        final size = MediaQuery.sizeOf(context);
        final autoHide = size.width < 600 || size.height < 500;
        final hideHeader = filesTab && (_immersive || (autoHide && _autoHidden));
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: hideHeader
                      ? const SizedBox(width: double.infinity)
                      : _Header(pr: pr, session: session, tabs: _tabs),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tabs.index,
                    children: [
                      _visited.contains(0)
                          ? ConversationTab(session: session, onShowInDiff: _showInDiff)
                          : const SizedBox.shrink(),
                      _visited.contains(1) ? CommitsTab(session: session) : const SizedBox.shrink(),
                      _visited.contains(2) && _diff != null
                          ? NotificationListener<ScrollNotification>(
                              onNotification: (n) => _onScroll(n, autoHide),
                              child: FilesTab(
                                controller: _diff!,
                                immersive: _immersive,
                                onToggleImmersive: () => setState(() => _immersive = !_immersive),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.pr, required this.session, required this.tabs});

  final PullRequest pr;
  final PrSession session;
  final TabController tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final short = MediaQuery.sizeOf(context).height < 500;
    final canPop = Navigator.of(context).canPop();
    final commentCount = (session.issueComments?.length ?? pr.comments) + (session.threads?.length ?? 0);

    Widget tab(String label, int? count) => Tab(
      height: short ? 38 : 46,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(formatCount(count), style: theme.textTheme.labelSmall),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: short ? 48 : 60,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  tooltip: canPop ? 'Back' : 'Home',
                  onPressed: () =>
                      canPop ? Navigator.pop(context) : Navigator.pushReplacementNamed(context, '/'),
                  icon: Icon(canPop ? Icons.arrow_back_rounded : Icons.home_outlined),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pr.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (!short)
                        Row(
                          children: [
                            StateBadge(pr.state, dense: true),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${pr.ref.slug} #${pr.ref.number} · ${pr.user.login}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: session.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) {
                    switch (v) {
                      case 'open':
                        openUrl(pr.htmlUrl);
                      case 'copy':
                        copyText(context, pr.htmlUrl, message: 'Link copied');
                      case 'settings':
                        Navigator.pushNamed(context, '/settings');
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'open', child: Text('Open on GitHub')),
                    PopupMenuItem(value: 'copy', child: Text('Copy link')),
                    PopupMenuItem(value: 'settings', child: Text('Settings')),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          TabBar(
            controller: tabs,
            isScrollable: true,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              tab('Conversation', commentCount),
              tab('Commits', session.commits?.length ?? pr.commits),
              tab('Files', pr.changedFiles),
            ],
          ),
        ],
      ),
    );
  }
}
