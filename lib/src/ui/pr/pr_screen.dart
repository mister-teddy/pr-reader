import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/home_widgets.dart';
import '../../app/services.dart';
import '../../app/settings.dart';
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
  const PrScreen({super.key, required this.prRef, this.initialTab});

  final PrRef prRef;

  /// The tab to open. Null resumes the tab the reader was last on.
  final PrTab? initialTab;

  @override
  State<PrScreen> createState() => _PrScreenState();
}

class _PrScreenState extends State<PrScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final Set<int> _visited = {};
  PrSession? _session;
  DiffController? _diff;
  bool _immersive = false;

  late final SettingsController _settings;
  late final HomeWidgets _widgets;

  /// Whether this PR is in the macOS pinned list.
  bool _pinned = false;
  ReadingPosition? _saved;
  final ScrollController _conversation = ScrollController();
  double? _resumeConversation;
  int _resumeTries = 0;
  Timer? _saveTimer;

  /// Header hidden because the reader scrolled down the diff (small screens).
  bool _autoHidden = false;
  bool _recorded = false;

  /// Picks up "Viewed" changes made on github.com while the app was away,
  /// and saves the reading position before it goes.
  AppLifecycleListener? _lifecycle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _settings = AppScope.of(context).settings;
      _widgets = AppScope.of(context).widgets;
      if (HomeWidgets.macos) {
        _widgets.pinned().then((p) {
          if (mounted && p.contains(widget.prRef)) setState(() => _pinned = true);
        });
      }
      _saved = _settings.readingPosition(widget.prRef);
      final tab = widget.initialTab ?? PrTab.values.asNameMap()[_saved?.tab] ?? PrTab.conversation;
      _tabs = TabController(length: PrTab.values.length, vsync: this, initialIndex: tab.index)
        ..addListener(_onTab);
      final offset = _saved?.conversation ?? 0;
      if (offset > 0) _resumeConversation = offset;
      _conversation.addListener(_scheduleSave);
      _session = AppScope.of(context).session(widget.prRef);
      _session!.addListener(_onSession);
      _session!.viewed.addListener(_scheduleSave);
      _lifecycle = AppLifecycleListener(
        onResume: _session!.syncViewed,
        onInactive: _savePosition,
        onHide: _savePosition,
        onPause: _savePosition,
      );
      _visited.add(_tabs.index);
      _onSession();
    }
    // Whichever PR is on top is the one to reopen on the next launch.
    if (ModalRoute.of(context)?.isCurrent ?? false) _settings.setLastPr(widget.prRef);
  }

  @override
  void dispose() {
    _savePosition();
    // Leaving the PR (back to home) means the next launch starts at home.
    if (_settings.lastPr == widget.prRef) _settings.setLastPr(null);
    _saveTimer?.cancel();
    _lifecycle?.dispose();
    _session?.removeListener(_onSession);
    _session?.viewed.removeListener(_scheduleSave);
    _diff?.dispose();
    _conversation.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_visited.add(_tabs.index) || _tabs.indexIsChanging) setState(() {});
    _scheduleSave();
  }

  void _onSession() {
    final pr = _session?.pr;
    if (pr != null && !_recorded) {
      _recorded = true;
      _settings.addRecent(pr);
      _widgets.setRecents(_settings.recents);
    }
    if (pr != null && _diff == null) {
      _diff = DiffController(_session!, resumeAt: _saved?.diff, expanded: _saved?.expanded ?? const {});
      _diff!.vertical.addListener(_scheduleSave);
    }
    _resumeConversationScroll();
    if (pr != null) _scheduleSave();
  }

  /// Scrolls the conversation back to the saved offset once it has loaded.
  /// The list builds lazily, so its extent grows as it scrolls; this retries
  /// for a few frames until the offset is reachable.
  void _resumeConversationScroll() {
    final target = _resumeConversation;
    final s = _session!;
    if (target == null || s.issueComments == null && s.conversationError == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _resumeConversation == null || !_conversation.hasClients) return;
      final p = _conversation.position;
      p.jumpTo(math.min(target, p.maxScrollExtent));
      if (p.pixels >= target - 1 || ++_resumeTries >= 10) {
        _resumeConversation = null;
      } else {
        _resumeConversationScroll();
      }
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _savePosition);
  }

  void _savePosition() {
    _saveTimer?.cancel();
    if (_session?.pr == null) return;
    final conversation = _conversation.hasClients && _resumeConversation == null
        ? _conversation.offset
        : _resumeConversation ?? _saved?.conversation ?? 0;
    _saved = ReadingPosition(
      tab: PrTab.values[_tabs.index].name,
      diff: _diff?.readingAnchor ?? _saved?.diff,
      conversation: conversation,
      expanded: _diff?.overrides ?? _saved?.expanded ?? const {},
    );
    _settings.saveReadingPosition(widget.prRef, _saved!);
    _widgets.update(_session!, readingFile: _saved!.diff?.path);
  }

  Future<void> _pinToHomeScreen() async {
    final messenger = ScaffoldMessenger.of(context);
    if (HomeWidgets.macos && _pinned) {
      await _widgets.unpin(widget.prRef);
      if (mounted) setState(() => _pinned = false);
      return;
    }
    final placed = await _widgets.pin(_session!, readingFile: _saved?.diff?.path);
    if (HomeWidgets.macos) {
      if (mounted) setState(() => _pinned = placed);
      if (placed) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Pinned. To show it, right-click the desktop, choose Edit Widgets '
              'and add a PR Reader widget.',
            ),
          ),
        );
      }
    } else if (!placed) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Your launcher can't add widgets from apps. Long-press the home screen, "
            'open Widgets and add PR Reader; it shows the last PR you opened.',
          ),
        ),
      );
    }
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
                      : _Header(
                          pr: pr,
                          session: session,
                          tabs: _tabs,
                          pinned: _pinned,
                          onPin: _pinToHomeScreen,
                        ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tabs.index,
                    children: [
                      _visited.contains(0)
                          ? ConversationTab(
                              session: session,
                              scrollController: _conversation,
                              onShowInDiff: _showInDiff,
                            )
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
  const _Header({
    required this.pr,
    required this.session,
    required this.tabs,
    required this.pinned,
    required this.onPin,
  });

  final PullRequest pr;
  final PrSession session;
  final TabController tabs;
  final bool pinned;
  final VoidCallback onPin;

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
                      case 'pin':
                        onPin();
                      case 'settings':
                        Navigator.pushNamed(context, '/settings');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'open', child: Text('Open on GitHub')),
                    const PopupMenuItem(value: 'copy', child: Text('Copy link')),
                    if (HomeWidgets.supported)
                      PopupMenuItem(
                        value: 'pin',
                        child: Text(
                          HomeWidgets.android
                              ? 'Pin to home screen'
                              : pinned
                              ? 'Unpin widget'
                              : 'Pin as widget',
                        ),
                      ),
                    const PopupMenuItem(value: 'settings', child: Text('Settings')),
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
