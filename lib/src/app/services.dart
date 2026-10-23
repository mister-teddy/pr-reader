import 'package:flutter/widgets.dart';

import '../data/pr_session.dart';
import '../data/viewed_state.dart';
import '../github/github_client.dart';
import '../github/models.dart';
import '../github/pr_ref.dart';
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
