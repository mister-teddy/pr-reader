import 'package:flutter/material.dart';

import '../../data/viewed_state.dart';
import '../../diff/diff_models.dart';
import '../widgets/common.dart';
import 'diff_controller.dart';
import 'diff_rows.dart';

class _Node {
  _Node(this.name, this.path);

  String name;
  final String path;
  final List<_Node> children = [];
  final Map<String, _Node> _dirs = {};
  int file = -1;
  int additions = 0;
  int deletions = 0;
  int fileCount = 0;

  bool get isDir => file < 0;
}

class _Row {
  const _Row(this.node, this.depth);

  final _Node node;
  final int depth;
}

/// The changed files as a collapsible tree, with single-child folders
/// compacted (`src/main/java`) like most IDEs. Children keep the order they
/// arrive in, which is the diff's order, so the tree and diff always agree.
class FileTree extends StatefulWidget {
  const FileTree({super.key, required this.controller, required this.onSelect, this.autofocusFilter = false});

  final DiffController controller;
  final ValueChanged<int> onSelect;
  final bool autofocusFilter;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  final _scroll = ScrollController();
  final _filter = TextEditingController();
  final Set<String> _collapsed = {};
  bool _hideViewed = false;

  _Node? _root;
  int _builtFor = -1;
  List<_Row> _rows = const [];
  String _rowsKey = '';

  DiffController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.currentFile.addListener(_reveal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(jump: true));
  }

  @override
  void dispose() {
    c.currentFile.removeListener(_reveal);
    _scroll.dispose();
    _filter.dispose();
    super.dispose();
  }

  double get _rowHeight =>
      Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS
      ? 40
      : 32;

  void _reveal({bool jump = false}) {
    if (!mounted || !_scroll.hasClients) return;
    final i = _rows.indexWhere((r) => r.node.file == c.currentFile.value);
    if (i < 0) return;
    final top = i * _rowHeight;
    final view = _scroll.position.viewportDimension;
    final off = _scroll.offset;
    if (top >= off && top + _rowHeight <= off + view) return;
    final target = (top - view / 3).clamp(0.0, _scroll.position.maxScrollExtent);
    if (jump) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  void _buildTree() {
    if (_builtFor == c.files.length && _root != null) return;
    final root = _Node('', '');
    final files = c.files;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final parts = f.path.split('/');
      var node = root;
      var path = '';
      for (var p = 0; p < parts.length - 1; p++) {
        path = path.isEmpty ? parts[p] : '$path/${parts[p]}';
        var next = node._dirs[parts[p]];
        if (next == null) {
          next = _Node(parts[p], path);
          node._dirs[parts[p]] = next;
          node.children.add(next);
        }
        node = next;
      }
      node.children.add(_Node(parts.last, f.path)..file = i);
    }
    void aggregate(_Node n) {
      for (final ch in n.children) {
        if (ch.isDir) {
          aggregate(ch);
          n.fileCount += ch.fileCount;
          n.additions += ch.additions;
          n.deletions += ch.deletions;
        } else {
          final f = files[ch.file];
          n.fileCount++;
          n.additions += f.additions;
          n.deletions += f.deletions;
        }
      }
    }

    void compact(_Node n) {
      for (var i = 0; i < n.children.length; i++) {
        var ch = n.children[i];
        while (ch.isDir && ch.children.length == 1 && ch.children.first.isDir) {
          final only = ch.children.first;
          only.name = '${ch.name}/${only.name}';
          ch = only;
        }
        n.children[i] = ch;
        if (ch.isDir) compact(ch);
      }
    }

    aggregate(root);
    compact(root);
    _root = root;
    _builtFor = files.length;
    _rowsKey = '';
  }

  List<_Row> _flatten() {
    final q = _filter.text.trim().toLowerCase();
    final key = '$q|$_hideViewed|${_collapsed.length}|${c.session.viewed.revision}|$_builtFor';
    if (key == _rowsKey) return _rows;
    final out = <_Row>[];
    final files = c.files;

    bool visibleFile(_Node n) {
      final f = files[n.file];
      if (_hideViewed && c.session.viewed.isViewed(f)) return false;
      return q.isEmpty || f.path.toLowerCase().contains(q);
    }

    bool hasVisible(_Node n) => n.isDir ? n.children.any(hasVisible) : visibleFile(n);

    void walk(_Node n, int depth) {
      for (final ch in n.children) {
        if (ch.isDir) {
          if (!hasVisible(ch)) continue;
          out.add(_Row(ch, depth));
          if (q.isNotEmpty || !_collapsed.contains(ch.path)) walk(ch, depth + 1);
        } else if (visibleFile(ch)) {
          out.add(_Row(ch, depth));
        }
      }
    }

    walk(_root!, 0);
    _rows = out;
    _rowsKey = key;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.session.viewed]),
      builder: (context, _) {
        _buildTree();
        final rows = _flatten();
        final files = c.files;
        final viewed = c.session.viewed.countViewed(files);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _filter,
                        autofocus: widget.autofocusFilter,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Filter ${formatCount(files.length)} files',
                          prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          suffixIcon: _filter.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () => setState(_filter.clear),
                                ),
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Tree options',
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    onSelected: (v) => setState(() {
                      switch (v) {
                        case 'hide':
                          _hideViewed = !_hideViewed;
                        case 'collapse':
                          _collapsed.addAll(rows.where((r) => r.node.isDir).map((r) => r.node.path));
                        case 'expand':
                          _collapsed.clear();
                      }
                      _rowsKey = '';
                    }),
                    itemBuilder: (context) => [
                      CheckedPopupMenuItem(
                        value: 'hide',
                        checked: _hideViewed,
                        child: const Text('Hide viewed files'),
                      ),
                      const PopupMenuItem(value: 'collapse', child: Text('Collapse folders')),
                      const PopupMenuItem(value: 'expand', child: Text('Expand folders')),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: files.isEmpty ? 0 : viewed / files.length,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _SyncBadge(sync: c.session.viewed.sync),
                  const SizedBox(width: 6),
                  Text(
                    '${formatCount(viewed)} / ${formatCount(files.length)} viewed',
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        files.isEmpty ? 'Loading files…' : 'No matching files',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ValueListenableBuilder<int>(
                      valueListenable: c.currentFile,
                      builder: (context, current, _) => ListView.builder(
                        controller: _scroll,
                        itemExtent: _rowHeight,
                        itemCount: rows.length,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemBuilder: (context, i) => _buildRow(rows[i], current),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRow(_Row row, int current) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = row.node;
    final indent = 8.0 + row.depth * 14;
    if (n.isDir) {
      final collapsed = _collapsed.contains(n.path) && _filter.text.isEmpty;
      return InkWell(
        onTap: () => setState(() {
          collapsed ? _collapsed.remove(n.path) : _collapsed.add(n.path);
          _rowsKey = '';
        }),
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 12),
          child: Row(
            children: [
              Icon(
                collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 2),
              Icon(
                collapsed ? Icons.folder_outlined : Icons.folder_open_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  n.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
              ),
              Text('${n.fileCount}', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline)),
            ],
          ),
        ),
      );
    }
    final f = c.files[n.file];
    final selected = n.file == current;
    final viewed = c.session.viewed.isViewed(f);
    final comments = c.session.threadsByPath[f.path]?.all.length ?? 0;
    return Material(
      color: selected ? scheme.secondaryContainer.withValues(alpha: 0.8) : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelect(n.file),
        child: Padding(
          padding: EdgeInsets.only(left: indent + 20, right: 4),
          child: Row(
            children: [
              FileStatusIcon(f.status, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  n.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : null,
                    color: viewed ? scheme.onSurfaceVariant : null,
                    decoration: f.status == FileStatus.removed ? TextDecoration.lineThrough : null,
                    decorationColor: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (comments > 0) ...[
                Icon(Icons.chat_bubble_outline_rounded, size: 13, color: scheme.secondary),
                const SizedBox(width: 6),
              ],
              if (f.changes > 0) ChangeCounts(additions: f.additions, deletions: f.deletions, fontSize: 11),
              SizedBox(
                width: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: viewed ? 'Unmark as viewed' : 'Mark as viewed',
                  onPressed: () => c.setViewed(n.file, !viewed),
                  icon: Icon(
                    viewed ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 16,
                    color: viewed ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether "Viewed" marks are synced with GitHub or kept on this device.
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.sync});

  final ViewedSync sync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sync == ViewedSync.syncing) {
      return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5));
    }
    final (IconData icon, String tip, Color color) = switch (sync) {
      ViewedSync.synced => (Icons.cloud_done_outlined, 'Viewed marks sync with GitHub', scheme.primary),
      ViewedSync.readOnly => (
        Icons.cloud_off_outlined,
        'Your token can\'t mark files as viewed on GitHub; marks are saved on this device',
        scheme.outline,
      ),
      _ => (
        Icons.phone_android_outlined,
        'Viewed marks are saved on this device. Add a token to sync with GitHub.',
        scheme.outline,
      ),
    };
    return Tooltip(
      message: tip,
      child: Icon(icon, size: 14, color: color),
    );
  }
}
