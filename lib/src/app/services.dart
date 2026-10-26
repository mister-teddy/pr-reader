import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/pr_session.dart';
import '../data/viewed_state.dart';
import '../github/github_client.dart';
import '../github/models.dart';
import '../github/pr_ref.dart';
import 'home_widgets.dart';
import 'settings.dart';

/// App-wide services, created once at startup.
class AppServices {
  AppServices({required this.settings, GitHubClient? client})
    : gh = client ?? GitHubClient(token: settings.token) {
    gh.onRateLimit = (info) => rateLimit.value = info;
    settings.addListener(_syncToken);
  }

  final SettingsController settings;
  final GitHubClient gh;
  final ValueNotifier<RateLimitInfo?> rateLimit = ValueNotifier(null);
  final ValueNotifier<GhUser?> viewer = ValueNotifier(null);
  late final HomeWidgets widgets = HomeWidgets(settings.prefs);

  static const _maxSessions = 4;
  final _sessions = <PrRef, PrSession>{};
  String? _lastToken;

  void _syncToken() {
    if (settings.token == _lastToken) return;
    _lastToken = settings.token;
    gh.token = settings.token;
    viewer.value = null;
    _sessions.clear();
    refreshViewer();
  }

  Future<void> refreshViewer() async {
    _lastToken = settings.token;
    if (settings.token == null) {
      viewer.value = null;
      return;
    }
    try {
      viewer.value = await gh.getViewer();
    } catch (_) {
      viewer.value = null;
    }
  }

  /// Loads pinned and recent PRs that widgets have no snapshot for, one at a
  /// time, so a widget can show any of them right away.
  Future<void> backfillWidgets({int maxRecents = 6}) async {
    final pinned = await widgets.pinned();
    final refs = {...pinned, for (final r in settings.recents.take(maxRecents)) r.ref};
    for (final ref in refs) {
      if (widgets.hasSnapshot(ref)) continue;
      final s = session(ref);
      final done = Completer<void>();
      void check() {
        final viewedSettled = s.viewed.sync != ViewedSync.syncing;
        if ((s.error != null || s.filesDone && viewedSettled) && !done.isCompleted) done.complete();
      }

      s.addListener(check);
      s.viewed.addListener(check);
      check();
      await done.future.timeout(const Duration(seconds: 90), onTimeout: () {});
      s.removeListener(check);
      s.viewed.removeListener(check);
      if (s.pr != null) {
        await widgets.update(s, readingFile: settings.readingPosition(ref)?.diff?.path);
      }
    }
  }

  /// Returns a cached session for [ref] or starts loading a new one.
  PrSession session(PrRef ref) {
    final existing = _sessions.remove(ref);
    if (existing != null) {
      _sessions[ref] = existing;
      return existing;
    }
    final s = PrSession(ref, gh, ViewedState(settings.prefs, ref.key))..load();
    _sessions[ref] = s;
    while (_sessions.length > _maxSessions) {
      _sessions.remove(_sessions.keys.first);
    }
    return s;
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
