import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diff/diff_layout.dart';
import '../github/models.dart';
import '../github/pr_ref.dart';

enum DiffLayoutPref { auto, unified, split }

enum WrapPref { auto, on, off }

class RecentPr {
  const RecentPr({required this.ref, required this.title, required this.state, required this.openedAt});

  final PrRef ref;
  final String title;
  final PrState state;
  final DateTime openedAt;

  Map<String, dynamic> toJson() => {
    'o': ref.owner,
    'r': ref.repo,
    'n': ref.number,
    't': title,
    's': state.name,
    'at': openedAt.millisecondsSinceEpoch,
  };

  static RecentPr? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      return RecentPr(
        ref: PrRef(j['o'] as String, j['r'] as String, j['n'] as int),
        title: j['t'] as String? ?? '',
        state: PrState.values.asNameMap()[j['s']] ?? PrState.open,
        openedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int? ?? 0),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where the reader was in a PR, so reopening it resumes there, like a
/// bookmark in an ebook.
class ReadingPosition {
  const ReadingPosition({this.tab, this.diff, this.conversation = 0, this.expanded = const {}});

  /// Name of the open tab (a `PrTab`).
  final String? tab;

  /// The row at the top of the diff. Stored as content rather than pixels,
  /// so it still lands right with a different window size or wrapping.
  final RowAnchor? diff;

  final double conversation;

  /// Files the reader explicitly expanded (true) or collapsed (false).
  final Map<String, bool> expanded;

  Map<String, dynamic> toJson() => {
    't': ?tab,
    'd': ?diff?.toJson(),
    'c': conversation,
    if (expanded.isNotEmpty) 'e': expanded,
  };

  static ReadingPosition? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      return ReadingPosition(
        tab: j['t'] as String?,
        diff: RowAnchor.fromJson(j['d']),
        conversation: (j['c'] as num? ?? 0).toDouble(),
        expanded: {for (final e in (j['e'] as Map? ?? const {}).entries) e.key as String: e.value as bool},
      );
    } catch (_) {
      return null;
    }
  }
}

/// User preferences, the GitHub token and recently opened PRs.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this._secure);

  static const _tokenKey = 'github_token';
  static const _tokenFallbackKey = 'github_token_insecure';
  static const _maxRecents = 30;
  static const _lastPrKey = 'last_pr';
  static const _positionPrefix = 'pos:';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  ThemeMode themeMode = ThemeMode.system;
  double diffFontSize = 13;
  DiffLayoutPref diffLayout = DiffLayoutPref.auto;
  WrapPref wrap = WrapPref.auto;
  bool syntaxHighlight = true;
  String? token;

  /// True when the OS keychain was unavailable and the token sits in plain
  /// preferences instead.
  bool tokenInsecure = false;
  List<RecentPr> recents = [];

  SharedPreferences get prefs => _prefs;

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    const secure = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
    final s = SettingsController._(prefs, secure);
    s.themeMode = ThemeMode.values.asNameMap()[prefs.getString('theme')] ?? ThemeMode.system;
    s.diffFontSize = prefs.getDouble('diff_font_size') ?? 13;
    s.diffLayout = DiffLayoutPref.values.asNameMap()[prefs.getString('diff_layout')] ?? DiffLayoutPref.auto;
    s.wrap = WrapPref.values.asNameMap()[prefs.getString('wrap')] ?? WrapPref.auto;
    s.syntaxHighlight = prefs.getBool('syntax') ?? true;
    try {
      s.token = await secure.read(key: _tokenKey);
    } catch (_) {
      s.token = prefs.getString(_tokenFallbackKey);
      s.tokenInsecure = s.token != null;
    }
    s.token ??= prefs.getString(_tokenFallbackKey);
    try {
      final raw = prefs.getString('recents');
      if (raw != null) {
        s.recents = [for (final j in jsonDecode(raw) as List) ?RecentPr.fromJson(j)];
      }
    } catch (_) {}
    return s;
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _prefs.setString('theme', mode.name);
    notifyListeners();
  }

  void setDiffFontSize(double size) {
    diffFontSize = size;
    _prefs.setDouble('diff_font_size', size);
    notifyListeners();
  }

  void setDiffLayout(DiffLayoutPref v) {
    diffLayout = v;
    _prefs.setString('diff_layout', v.name);
    notifyListeners();
  }

  void setWrap(WrapPref v) {
    wrap = v;
    _prefs.setString('wrap', v.name);
    notifyListeners();
  }

  void setSyntaxHighlight(bool v) {
    syntaxHighlight = v;
    _prefs.setBool('syntax', v);
    notifyListeners();
  }

  Future<void> setToken(String? value) async {
    final v = value?.trim();
    token = (v == null || v.isEmpty) ? null : v;
    tokenInsecure = false;
    try {
      if (token == null) {
        await _secure.delete(key: _tokenKey);
      } else {
        await _secure.write(key: _tokenKey, value: token);
      }
      await _prefs.remove(_tokenFallbackKey);
    } catch (_) {
      if (token == null) {
        await _prefs.remove(_tokenFallbackKey);
      } else {
        await _prefs.setString(_tokenFallbackKey, token!);
        tokenInsecure = true;
      }
    }
    notifyListeners();
  }

  void addRecent(PullRequest pr) {
    recents = [
      RecentPr(ref: pr.ref, title: pr.title, state: pr.state, openedAt: DateTime.now()),
      ...recents.where((r) => r.ref != pr.ref),
    ].take(_maxRecents).toList();
    _saveRecents();
    notifyListeners();
  }

  void removeRecent(PrRef ref) {
    recents = recents.where((r) => r.ref != ref).toList();
    _saveRecents();
    notifyListeners();
  }

  void clearRecents() {
    recents = [];
    _saveRecents();
    notifyListeners();
  }

  void _saveRecents() {
    _prefs.setString('recents', jsonEncode([for (final r in recents) r.toJson()]));
    // Reading positions are kept only for PRs still in the recents list.
    final keep = {for (final r in recents) '$_positionPrefix${r.ref.key}'};
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_positionPrefix) && !keep.contains(k)).toList()) {
      _prefs.remove(k);
    }
  }

  /// The PR that was open when the app last closed, reopened on launch.
  PrRef? get lastPr {
    final raw = _prefs.getString(_lastPrKey);
    return raw == null ? null : PrRef.tryParse(raw);
  }

  void setLastPr(PrRef? ref) {
    if (ref == null) {
      _prefs.remove(_lastPrKey);
    } else {
      _prefs.setString(_lastPrKey, ref.key);
    }
  }

  ReadingPosition? readingPosition(PrRef ref) {
    try {
      final raw = _prefs.getString('$_positionPrefix${ref.key}');
      return raw == null ? null : ReadingPosition.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void saveReadingPosition(PrRef ref, ReadingPosition p) =>
      _prefs.setString('$_positionPrefix${ref.key}', jsonEncode(p.toJson()));

  /// Forgets every "viewed" mark.
  Future<void> clearViewed() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('viewed:')).toList()) {
      await _prefs.remove(k);
    }
  }
}
