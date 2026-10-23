import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../github/models.dart';
import '../../github/pr_ref.dart';
import '../widgets/common.dart';
import 'pull_tile.dart';

/// Pull requests of one repository, paginated.
class RepoPullsScreen extends StatefulWidget {
  const RepoPullsScreen({super.key, required this.repo});

  final RepoRef repo;

  @override
  State<RepoPullsScreen> createState() => _RepoPullsScreenState();
}

class _RepoPullsScreenState extends State<RepoPullsScreen> {
  String _state = 'open';
  final List<PullSummary> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _done = false;
  Object? _error;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == 0 && !_loading) _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final next = await AppScope.of(context).gh.listRepoPulls(widget.repo, state: _state, page: _page + 1);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(next);
        _page++;
        _done = next.length < 30;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _setState(String s) {
    setState(() {
      _generation++;
      _state = s;
      _items.clear();
      _page = 0;
      _done = false;
      _error = null;
      _loading = false;
    });
    _more();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repo.slug),
        actions: [
          IconButton(
            tooltip: 'Open on GitHub',
            onPressed: () => openUrl('${widget.repo.webUrl}/pulls'),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: ReadableWidth(
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'open', label: Text('Open')),
                    ButtonSegment(value: 'closed', label: Text('Closed')),
                    ButtonSegment(value: 'all', label: Text('All')),
                  ],
                  selected: {_state},
                  onSelectionChanged: (s) => _setState(s.first),
                ),
              ),
            ),
          ),
          Expanded(
            child: _error != null && _items.isEmpty
                ? ErrorView(
                    message: describeError(_error!, hasToken: AppScope.of(context).settings.token != null),
                    onRetry: () => _setState(_state),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 600) _more();
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 32),
                      itemCount: _items.length + 1,
                      itemBuilder: (context, i) {
                        if (i == _items.length) {
                          if (_loading) {
                            return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (_items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(48),
                              child: Center(child: Text('No pull requests')),
                            );
                          }
                          return const SizedBox(height: 24);
                        }
                        return ReadableWidth(child: PullTile(pull: _items[i], showRepo: false));
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
