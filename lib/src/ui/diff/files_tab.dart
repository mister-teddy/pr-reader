import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../app/settings.dart';
import '../../github/models.dart';
import '../adaptive.dart';
import '../widgets/common.dart';
import '../widgets/thread_view.dart';
import 'diff_controller.dart';
import 'diff_view.dart';
import 'file_tree.dart';

/// The Files tab: file tree, toolbar, search and the diff, arranged for the
/// current window. Phones get a bottom bar within thumb reach and a tree
/// sheet; tablets and desktops get a resizable tree pane; very wide windows
/// add a comment panel; book-style foldables put the tree and the diff on
/// either side of the hinge.
class FilesTab extends StatefulWidget {
  const FilesTab({
    super.key,
    required this.controller,
    required this.immersive,
    required this.onToggleImmersive,
  });

  final DiffController controller;
  final bool immersive;
  final VoidCallback onToggleImmersive;

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  // Keeps the diff's element (and scroll position) when the layout moves it
  // to a different parent, e.g. when a window is resized across a breakpoint.
  final _diffKey = GlobalKey(debugLabel: 'diff');
  final _diffFocus = FocusNode(debugLabel: 'diff');
  final _searchFocus = FocusNode(debugLabel: 'diff search');
  final _search = TextEditingController();
  bool _treeOpen = true;
  double _treeWidth = 320;
  bool _searchOpen = false;
  List<ReviewThread>? _panelThreads;
  String _panelTitle = '';

  DiffController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.session.viewed.addListener(_onViewed);
  }

  /// Surfaces "Viewed" sync problems (e.g. a read-only token) once.
  void _onViewed() {
    final viewed = c.session.viewed;
    final message = viewed.message;
    if (message == null || !mounted) return;
    viewed.clearMessage();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  void dispose() {
    c.session.viewed.removeListener(_onViewed);
    _diffFocus.dispose();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocus.requestFocus();
      _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
    });
  }

  void _closeSearch() {
    _search.clear();
    c.clearSearch();
    setState(() => _searchOpen = false);
    _diffFocus.requestFocus();
  }

  void _openThreads(List<ReviewThread> threads, String title, {required bool panel}) {
    if (panel) {
      setState(() {
        _panelThreads = threads;
        _panelTitle = title;
      });
    } else {
      showThreads(context, threads, title, onReply: c.session.reply);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final mod = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (mod) return KeyEventResult.ignored;
    final viewport = c.vertical.hasClients ? c.vertical.position.viewportDimension : 600.0;
    final file = c.currentFile.value;
    switch (k) {
      case LogicalKeyboardKey.keyJ:
        c.nextFile();
      case LogicalKeyboardKey.keyK:
        c.previousFile();
      case LogicalKeyboardKey.keyN:
        shift ? c.previousHit() : c.nextHit();
      case LogicalKeyboardKey.keyV when c.files.isNotEmpty:
        c.setViewed(file, !c.isViewed(file));
      case LogicalKeyboardKey.keyX when c.files.isNotEmpty:
        c.toggleExpanded(file);
      case LogicalKeyboardKey.keyT:
        setState(() => _treeOpen = !_treeOpen);
      case LogicalKeyboardKey.slash:
        _openSearch();
      case LogicalKeyboardKey.arrowDown:
        c.scrollBy(60);
      case LogicalKeyboardKey.arrowUp:
        c.scrollBy(-60);
      case LogicalKeyboardKey.pageDown:
        c.scrollBy(viewport * 0.85);
      case LogicalKeyboardKey.pageUp:
        c.scrollBy(-viewport * 0.85);
      case LogicalKeyboardKey.space:
        c.scrollBy(shift ? -viewport * 0.85 : viewport * 0.85);
      case LogicalKeyboardKey.home:
        c.vertical.jumpTo(0);
      case LogicalKeyboardKey.end:
        c.vertical.jumpTo(c.vertical.position.maxScrollExtent);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final session = c.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.files.isEmpty) {
          if (session.filesError != null) {
            return ErrorView(
              message: describeError(
                session.filesError!,
                hasToken: AppScope.of(context).settings.token != null,
              ),
              onRetry: session.retryFiles,
            );
          }
          if (!session.filesDone) {
            final expected = session.filesExpected;
            return LoadingView(
              message: expected > 0 ? 'Loading ${formatCount(expected)} files…' : 'Loading files…',
            );
          }
          return const ErrorView(
            message: 'This pull request has no file changes.',
            icon: Icons.inbox_outlined,
          );
        }
        return LayoutBuilder(builder: _buildLayout);
      },
    );
  }

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final hinge = Hinge.of(context);
    final splitByHinge = hinge != null && hinge.vertical;
    final wide = width >= 840 || splitByHinge;
    final panelMode = width >= 1600 && !splitByHinge;

    final diff = Focus(
      key: _diffKey,
      focusNode: _diffFocus,
      autofocus: isDesktopPlatform,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerDown: (_) {
          if (!_searchFocus.hasFocus) _diffFocus.requestFocus();
        },
        child: DiffView(
          controller: c,
          openThreads: (t, title) => _openThreads(t, title, panel: panelMode),
        ),
      ),
    );

    Widget body;
    if (wide) {
      final tree = FileTree(controller: c, onSelect: (i) => c.jumpToFile(i));
      final toolbar = _Toolbar(
        controller: c,
        search: _search,
        searchFocus: _searchFocus,
        treeOpen: _treeOpen || splitByHinge,
        onToggleTree: splitByHinge ? null : () => setState(() => _treeOpen = !_treeOpen),
        onCloseSearch: _closeSearch,
        immersive: widget.immersive,
        onToggleImmersive: widget.onToggleImmersive,
      );
      if (splitByHinge) {
        body = HingeSplit(
          hinge: hinge,
          first: tree,
          second: Column(
            children: [
              toolbar,
              Expanded(child: diff),
            ],
          ),
        );
      } else {
        body = Column(
          children: [
            toolbar,
            Expanded(
              child: Row(
                children: [
                  if (_treeOpen) ...[
                    SizedBox(width: _treeWidth, child: tree),
                    _ResizeHandle(
                      onDrag: (dx) =>
                          setState(() => _treeWidth = (_treeWidth + dx).clamp(200.0, width * 0.45)),
                    ),
                  ],
                  Expanded(child: diff),
                  if (panelMode && _panelThreads != null) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 420,
                      child: _ThreadPanel(
                        title: _panelTitle,
                        threads: _panelThreads!,
                        onClose: () => setState(() => _panelThreads = null),
                        onJump: c.jumpToThread,
                        onReply: c.session.reply,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }
    } else {
      body = Column(
        children: [
          Expanded(child: diff),
          _BottomBar(
            controller: c,
            searchOpen: _searchOpen,
            search: _search,
            searchFocus: _searchFocus,
            onOpenSearch: _openSearch,
            onCloseSearch: _closeSearch,
            onOpenTree: () => _openTreeSheet(context, side: width >= 600),
            immersive: widget.immersive,
            onToggleImmersive: widget.onToggleImmersive,
          ),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchOpen || _search.text.isNotEmpty) _closeSearch();
        },
      },
      child: body,
    );
  }

  Future<void> _openTreeSheet(BuildContext context, {required bool side}) async {
    void select(BuildContext sheet, int i) {
      Navigator.pop(sheet);
      c.jumpToFile(i);
    }

    if (side) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close files',
        barrierColor: Colors.black38,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (sheet, _, _) => Align(
          alignment: Alignment.centerLeft,
          child: Material(
            elevation: 8,
            color: Theme.of(sheet).colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              right: false,
              child: SizedBox(
                width: 380,
                child: FileTree(controller: c, onSelect: (i) => select(sheet, i)),
              ),
            ),
          ),
        ),
        transitionBuilder: (context, anim, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.8,
        child: FileTree(controller: c, onSelect: (i) => select(sheet, i)),
      ),
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: const SizedBox(width: 6, child: VerticalDivider(width: 6, thickness: 1)),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.text,
    required this.focus,
    required this.onClose,
    this.autofocus = false,
  });

  final DiffController controller;
  final TextEditingController text;
  final FocusNode focus;
  final VoidCallback onClose;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([c, text]),
      builder: (context, _) {
        final hits = c.hits;
        final count = hits == null
            ? null
            : hits.length == 0
            ? 'No results'
            : '${c.currentHit + 1} / ${formatCount(hits.length)}${hits.capped ? '+' : ''}';
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): c.nextHit,
            const SingleActivator(LogicalKeyboardKey.enter, shift: true): c.previousHit,
            const SingleActivator(LogicalKeyboardKey.escape): onClose,
          },
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: text,
              focusNode: focus,
              autofocus: autofocus,
              onChanged: c.search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                c.nextHit();
                focus.requestFocus();
              },
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search in diff',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: text.text.isEmpty
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count != null)
                            Text(count, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          IconButton(
                            tooltip: 'Previous (Shift+Enter)',
                            visualDensity: VisualDensity.compact,
                            onPressed: hits == null || hits.length == 0 ? null : c.previousHit,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            tooltip: 'Next (Enter)',
                            visualDensity: VisualDensity.compact,
                            onPressed: hits == null || hits.length == 0 ? null : c.nextHit,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                          IconButton(
                            tooltip: 'Clear',
                            visualDensity: VisualDensity.compact,
                            onPressed: onClose,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Toolbar above the diff on tablets and desktops.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.treeOpen,
    required this.onToggleTree,
    required this.onCloseSearch,
    required this.immersive,
    required this.onToggleImmersive,
  });

  final DiffController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
  final bool treeOpen;
  final VoidCallback? onToggleTree;
  final VoidCallback onCloseSearch;
  final bool immersive;
  final VoidCallback onToggleImmersive;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final roomy = constraints.maxWidth >= 640;
            return Row(
              children: [
                if (onToggleTree != null)
                  IconButton(
                    tooltip: treeOpen ? 'Hide file tree (t)' : 'Show file tree (t)',
                    isSelected: treeOpen,
                    onPressed: onToggleTree,
                    icon: const Icon(Icons.view_sidebar_outlined),
                    selectedIcon: const Icon(Icons.view_sidebar_rounded),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _SearchField(
                        controller: controller,
                        text: search,
                        focus: searchFocus,
                        onClose: onCloseSearch,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (roomy)
                  SegmentedButton<DiffLayoutPref>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: DiffLayoutPref.auto, label: Text('Auto')),
                      ButtonSegment(value: DiffLayoutPref.unified, label: Text('Unified')),
                      ButtonSegment(value: DiffLayoutPref.split, label: Text('Split')),
                    ],
                    selected: {settings.diffLayout},
                    onSelectionChanged: (s) => settings.setDiffLayout(s.first),
                  ),
                const SizedBox(width: 4),
                _OptionsMenu(
                  controller: controller,
                  immersive: immersive,
                  onToggleImmersive: onToggleImmersive,
                  compact: !roomy,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bottom bar for phones: current file, quick navigation and search.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.searchOpen,
    required this.search,
    required this.searchFocus,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onOpenTree,
    required this.immersive,
    required this.onToggleImmersive,
  });

  final DiffController controller;
  final bool searchOpen;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final VoidCallback onOpenTree;
  final bool immersive;
  final VoidCallback onToggleImmersive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = controller;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
          ),
          child: searchOpen
              ? Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: _SearchField(
                        controller: c,
                        text: search,
                        focus: searchFocus,
                        onClose: onCloseSearch,
                        autofocus: true,
                      ),
                    ),
                    IconButton(
                      onPressed: onCloseSearch,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close search',
                    ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      onPressed: onOpenTree,
                      tooltip: 'Files',
                      icon: const Icon(Icons.account_tree_outlined),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onOpenTree,
                        child: ValueListenableBuilder<int>(
                          valueListenable: c.currentFile,
                          builder: (context, i, _) {
                            if (i >= c.files.length) return const SizedBox.shrink();
                            final f = c.files[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${i + 1} of ${formatCount(c.files.length)}${f.dir.isEmpty ? '' : ' · ${f.dir}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: c.previousFile,
                      tooltip: 'Previous file',
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      onPressed: c.nextFile,
                      tooltip: 'Next file',
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    IconButton(
                      onPressed: onOpenSearch,
                      tooltip: 'Search',
                      icon: const Icon(Icons.search_rounded),
                    ),
                    _OptionsMenu(
                      controller: c,
                      immersive: immersive,
                      onToggleImmersive: onToggleImmersive,
                      compact: true,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OptionsMenu extends StatelessWidget {
  const _OptionsMenu({
    required this.controller,
    required this.immersive,
    required this.onToggleImmersive,
    this.compact = false,
  });

  final DiffController controller;
  final bool immersive;
  final VoidCallback onToggleImmersive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final c = controller;
    return PopupMenuButton<String>(
      tooltip: 'Diff options',
      icon: const Icon(Icons.tune_rounded),
      onSelected: (v) {
        switch (v) {
          case 'wrap':
            settings.setWrap(switch (settings.wrap) {
              WrapPref.auto => WrapPref.on,
              WrapPref.on => WrapPref.off,
              WrapPref.off => WrapPref.auto,
            });
          case 'syntax':
            settings.setSyntaxHighlight(!settings.syntaxHighlight);
          case 'bigger':
            settings.setDiffFontSize((settings.diffFontSize + 1).clamp(9, 22));
          case 'smaller':
            settings.setDiffFontSize((settings.diffFontSize - 1).clamp(9, 22));
          case 'expand':
            c.expandAll();
          case 'collapse':
            c.collapseAll();
          case 'viewed':
            c.markAllViewed(true);
          case 'unviewed':
            c.markAllViewed(false);
          case 'immersive':
            onToggleImmersive();
          case 'split':
            settings.setDiffLayout(
              settings.diffLayout == DiffLayoutPref.split ? DiffLayoutPref.unified : DiffLayoutPref.split,
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'wrap',
          child: ListTile(
            leading: const Icon(Icons.wrap_text_rounded),
            title: const Text('Wrap lines'),
            trailing: Text(switch (settings.wrap) {
              WrapPref.auto => 'Auto',
              WrapPref.on => 'On',
              WrapPref.off => 'Off',
            }),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (compact)
          CheckedPopupMenuItem(
            value: 'split',
            checked: settings.diffLayout == DiffLayoutPref.split,
            child: const Text('Side by side'),
          ),
        CheckedPopupMenuItem(
          value: 'syntax',
          checked: settings.syntaxHighlight,
          child: const Text('Syntax colors'),
        ),
        const PopupMenuItem(
          value: 'bigger',
          child: ListTile(
            leading: Icon(Icons.text_increase_rounded),
            title: Text('Larger text'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'smaller',
          child: ListTile(
            leading: Icon(Icons.text_decrease_rounded),
            title: Text('Smaller text'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'expand', child: Text('Expand all files')),
        const PopupMenuItem(value: 'collapse', child: Text('Collapse all files')),
        const PopupMenuItem(value: 'viewed', child: Text('Mark all as viewed')),
        const PopupMenuItem(value: 'unviewed', child: Text('Clear viewed')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'immersive',
          child: ListTile(
            leading: Icon(immersive ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
            title: Text(immersive ? 'Show header' : 'Focus mode'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

class _ThreadPanel extends StatelessWidget {
  const _ThreadPanel({
    required this.title,
    required this.threads,
    required this.onClose,
    required this.onJump,
    required this.onReply,
  });

  final String title;
  final List<ReviewThread> threads;
  final VoidCallback onClose;
  final void Function(ReviewThread) onJump;
  final ReplyToThread onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.forum_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Close'),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ThreadList(threads: threads, onJump: onJump, onReply: onReply),
          ),
        ],
      ),
    );
  }
}
