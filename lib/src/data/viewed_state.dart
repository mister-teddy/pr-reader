import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diff/diff_models.dart';
import '../github/github_client.dart';

enum ViewedSync {
  /// Marks live only on this device (no token, or GitHub unreachable).
  local,

  /// Loading marks from GitHub.
  syncing,

  /// Marks are read from and written to GitHub.
  synced,

  /// The token can read the PR but not mark files, so marks stay local.
  readOnly,
}

/// Pushes viewed changes to GitHub; see [GitHubClient.setViewed].
typedef ViewedPusher = Future<void> Function(List<String> paths, bool viewed);

/// Which files of a PR the reader marked as viewed.
///
/// With a token that can write to the PR, GitHub is the source of truth, so
/// marks match the "Viewed" checkboxes on github.com: changes show up
/// immediately and are sent in the background, and a failed write is undone.
/// Otherwise marks are kept on the device, tied to each file's blob SHA so
/// they clear when the file changes again (as GitHub does).
class ViewedState extends ChangeNotifier {
  ViewedState(this._prefs, String prKey) : _key = 'viewed:${prKey.toLowerCase()}' {
    try {
      final raw = _prefs.getString(_key);
      if (raw != null) _local.addAll((jsonDecode(raw) as Map).cast<String, String>());
    } catch (_) {}
  }

  /// Local value meaning "viewed, whatever the SHA" (seeded from GitHub).
  static const _anySha = '*';

  final SharedPreferences _prefs;
  final String _key;
  final Map<String, String> _local = {};
  Timer? _save;
  int revision = 0;

  ViewedSync sync = ViewedSync.local;

  /// Path -> GitHub state, when synced.
  Map<String, String>? _remote;
  ViewedPusher? _push;

  /// Pushes in flight per path, so a re-sync doesn't undo a fresh click.
  final Map<String, int> _pending = {};
  Future<void> _queue = Future.value();

  /// The latest sync problem worth telling the user about; the UI shows it
  /// once and calls [clearMessage].
  String? message;

  bool isViewed(DiffFile f) {
    final remote = _remote;
    if (remote != null) return remote[f.path] == 'VIEWED';
    final v = _local[f.path];
    return v != null && (v == _anySha || v == (f.blobSha ?? ''));
  }

  int countViewed(List<DiffFile> files) {
    var n = 0;
    for (final f in files) {
      if (isViewed(f)) n++;
    }
    return n;
  }

  void set(DiffFile f, bool viewed) {
    if (viewed == isViewed(f)) return;
    _apply([f], viewed);
  }

  void setAll(Iterable<DiffFile> files, bool viewed) {
    final changed = [
      for (final f in files)
        if (isViewed(f) != viewed) f,
    ];
    if (changed.isNotEmpty) _apply(changed, viewed);
  }

  void _apply(List<DiffFile> files, bool viewed) {
    _setLocal(files, viewed);
    final remote = _remote, push = _push;
    if (remote != null && push != null) {
      final paths = [for (final f in files) f.path];
      final before = {for (final p in paths) p: remote[p] ?? 'UNVIEWED'};
      for (final p in paths) {
        remote[p] = viewed ? 'VIEWED' : 'UNVIEWED';
        _pending[p] = (_pending[p] ?? 0) + 1;
      }
      // Sequential, so rapid toggles reach GitHub in order.
      _queue = _queue.then((_) async {
        try {
          await push(paths, viewed);
        } catch (e) {
          _onPushFailed(e, before);
        } finally {
          for (final p in paths) {
            final n = (_pending[p] ?? 1) - 1;
            n <= 0 ? _pending.remove(p) : _pending[p] = n;
          }
        }
      });
    }
    revision++;
    notifyListeners();
  }

  void _onPushFailed(Object e, Map<String, String> before) {
    final denied = e is GitHubException && (e.statusCode == 403 || e.statusCode == 401);
    if (denied) {
      // Keep the click, but on this device only from now on.
      _detach(ViewedSync.readOnly);
      message = 'Your token can\'t mark files as viewed on GitHub, so viewed marks are saved on this device.';
    } else {
      _remote?.addAll(before);
      _seedLocal();
      message = 'Couldn\'t update "Viewed" on GitHub: ${e is GitHubException ? e.message : e}';
    }
    revision++;
    notifyListeners();
  }

  /// Switches to GitHub as the source of truth.
  void attachRemote(Map<String, String> states, ViewedPusher push) {
    final remote = {...states};
    // Keep clicks that are still on their way to GitHub.
    for (final p in _pending.keys) {
      final mine = _remote?[p];
      if (mine != null) remote[p] = mine;
    }
    _remote = remote;
    _push = push;
    sync = ViewedSync.synced;
    _seedLocal();
    revision++;
    notifyListeners();
  }

  void setSyncing() {
    if (sync == ViewedSync.synced) return;
    sync = ViewedSync.syncing;
    notifyListeners();
  }

  /// Falls back to device-only marks, keeping what GitHub last said.
  void syncFailed({required bool readOnly}) {
    _detach(readOnly ? ViewedSync.readOnly : ViewedSync.local);
    notifyListeners();
  }

  void _detach(ViewedSync to) {
    _seedLocal();
    _remote = null;
    _push = null;
    sync = to;
  }

  void clearMessage() => message = null;

  void _setLocal(List<DiffFile> files, bool viewed) {
    for (final f in files) {
      if (viewed) {
        _local[f.path] = f.blobSha ?? '';
      } else {
        _local.remove(f.path);
      }
    }
    _schedulePersist();
  }

  /// Mirrors GitHub's marks locally so they survive going offline.
  void _seedLocal() {
    final remote = _remote;
    if (remote == null) return;
    for (final e in remote.entries) {
      if (e.value == 'VIEWED') {
        _local.putIfAbsent(e.key, () => _anySha);
      } else {
        _local.remove(e.key);
      }
    }
    _schedulePersist();
  }

  void _schedulePersist() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), _persist);
  }

  void _persist() {
    if (_local.isEmpty) {
      _prefs.remove(_key);
    } else {
      _prefs.setString(_key, jsonEncode(_local));
    }
  }

  @override
  void dispose() {
    _save?.cancel();
    _persist();
    super.dispose();
  }
}
