import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// User preferences, the GitHub token and recently opened PRs.
class SettingsController extends ChangeNotifier {
  SettingsController._(this._prefs, this._secure);

  static const _tokenKey = 'github_token';
  static const _tokenFallbackKey = 'github_token_insecure';
  static const _maxRecents = 30;

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

  void _saveRecents() => _prefs.setString('recents', jsonEncode([for (final r in recents) r.toJson()]));

  /// Forgets every "viewed" mark.
  Future<void> clearViewed() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('viewed:')).toList()) {
      await _prefs.remove(k);
    }
  }
}
