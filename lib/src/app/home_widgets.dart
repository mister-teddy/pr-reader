import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pr_session.dart';
import '../github/pr_ref.dart';
import 'settings.dart';

/// Widgets that show a pinned PR: on the Android home screen and on the
/// macOS desktop / Notification Center.
///
/// The app writes a small JSON snapshot per PR to shared preferences under
/// `widget:<owner/repo#n>`. On Android the native widget reads it from the
/// same file (`FlutterSharedPreferences`, keys prefixed with `flutter.`); on
/// macOS it is also handed over the method channel, which stores it in the
/// App Group the widget extension reads. Tapping a widget opens the PR
/// through its `pr://` link, which resumes reading where it stopped.
///
/// Pinning differs: Android asks the launcher to place a widget for the PR,
/// while macOS adds it to a pinned list that the widgets show.
class HomeWidgets {
  HomeWidgets(this._prefs);

  static const _channel = MethodChannel('pr_reader/widgets');
  static const prefix = 'widget:';

  final SharedPreferences _prefs;

  static bool get supported => android || macos;
  static bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get macos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // No native side (tests, or a platform without widgets).
      return null;
    }
  }

  /// Pins [session]'s PR. On Android this asks the launcher to place a
  /// widget and returns false if it can't.
  Future<bool> pin(PrSession session, {String? readingFile}) async {
    await _write(session, readingFile: readingFile);
    return await _call<bool>('pin', {'key': session.ref.key}) ?? false;
  }

  /// Removes a PR from the pinned list (macOS; on Android the widget is
  /// removed from the home screen instead).
  Future<void> unpin(PrRef ref) => _call<void>('unpin', {'key': ref.key});

  /// PRs that are pinned, or on Android have a widget on the home screen.
  Future<Set<PrRef>> pinned() async {
    if (!supported) return {};
    final keys = await _call<List<Object?>>('pinned') ?? const [];
    return {for (final k in keys.whereType<String>()) ?PrRef.tryParse(k)};
  }

  /// Recent PRs offered when choosing a widget's PR (macOS "Edit Widget"),
  /// with titles so they can be found before being opened again.
  Future<void> setRecents(Iterable<RecentPr> recents) async {
    if (!macos) return;
    await _call<void>('setRecents', {
      'keys': [for (final r in recents) r.ref.key],
      'info': {
        for (final r in recents) r.ref.key: {'title': r.title, 'state': r.state.name},
      },
    });
  }

  /// Saves what a widget for [session]'s PR shows and redraws the widgets.
  /// [readingFile] is the path of the file the reader is in. Callers
  /// debounce this; files arrive page by page.
  Future<void> update(PrSession session, {String? readingFile}) async {
    if (!supported || session.pr == null) return;
    await _write(session, readingFile: readingFile);
    await _call<void>('refresh');
  }

  Future<void> _write(PrSession s, {String? readingFile}) async {
    final pr = s.pr!;
    final key = '$prefix${s.ref.key}';
    Map<String, dynamic>? old;
    try {
      old =
          jsonDecode(_prefs.getString(key) ?? 'null') as Map<String, dynamic>?;
    } catch (_) {}
    final loaded = s.files.length;
    final viewed = loaded == 0
        ? (old?['viewed'] as int? ?? 0)
        : s.files.where(s.viewed.isViewed).length;
    final json = jsonEncode({
      'title': pr.title,
      'state': pr.state.name,
      'repo': pr.ref.slug,
      'number': pr.ref.number,
      'author': pr.user.login,
      'viewed': viewed,
      'files': pr.changedFiles,
      'additions': pr.additions,
      'deletions': pr.deletions,
      'comments': pr.comments + (s.threads?.length ?? 0),
      'reading': readingFile ?? old?['reading'],
      'updated': DateTime.now().millisecondsSinceEpoch,
    });
    await _prefs.setString(key, json);
    if (macos) await _call<void>('save', {'key': s.ref.key, 'json': json});
  }

  bool hasSnapshot(PrRef ref) => _prefs.containsKey('$prefix${ref.key}');

  /// Drops snapshots for PRs that are neither recent nor pinned.
  Future<void> prune(Iterable<PrRef> keep) async {
    final pinned = await this.pinned();
    final names = {
      for (final r in [...keep, ...pinned]) '$prefix${r.key}',
    };
    for (final k
        in _prefs
            .getKeys()
            .where((k) => k.startsWith(prefix) && !names.contains(k))
            .toList()) {
      await _prefs.remove(k);
    }
  }
}
