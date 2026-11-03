import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../diff/syntax.dart';

/// Colors taken from a VS Code color theme: the editor and diff colors, and
/// a color per [Tok] picked from the theme's TextMate rules.
@immutable
class EditorTheme {
  const EditorTheme({required this.name, required this.dark, required this.colors, required this.syntax});

  final String name;
  final bool dark;

  /// The workbench colors in [usedColors] that the theme sets.
  final Map<String, Color> colors;

  /// Indexed by [Tok]; null where the theme has no matching rule.
  final List<Color?> syntax;

  static const usedColors = [
    'editor.background',
    'editor.foreground',
    'editorLineNumber.foreground',
    'diffEditor.insertedLineBackground',
    'diffEditor.insertedTextBackground',
    'diffEditor.removedLineBackground',
    'diffEditor.removedTextBackground',
    'diffEditorGutter.insertedLineBackground',
    'diffEditorGutter.removedLineBackground',
    'editorGutter.addedBackground',
    'editorGutter.deletedBackground',
    'editor.findMatchBackground',
    'editor.findMatchHighlightBackground',
    'button.background',
    'focusBorder',
  ];

  Color? operator [](String key) => colors[key];

  Map<String, dynamic> toJson() => {
    'name': name,
    'dark': dark,
    'colors': {for (final e in colors.entries) e.key: e.value.toARGB32()},
    'syntax': [for (final c in syntax) c?.toARGB32()],
  };

  static EditorTheme? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      return EditorTheme(
        name: j['name'] as String,
        dark: j['dark'] as bool,
        colors: {for (final e in (j['colors'] as Map<String, dynamic>).entries) e.key: Color(e.value as int)},
        syntax: [for (final c in j['syntax'] as List) c == null ? null : Color(c as int)],
      );
    } catch (_) {
      return null;
    }
  }
}

/// TextMate scopes to look up for each [Tok], most fitting first.
const _scopes = <int, List<String>>{
  Tok.keyword: ['keyword', 'storage.type', 'keyword.control', 'storage.modifier'],
  Tok.string: ['string.quoted', 'string'],
  Tok.comment: ['comment.line', 'comment'],
  Tok.number: ['constant.numeric', 'constant'],
  Tok.type: ['entity.name.type', 'support.type', 'entity.name.class', 'support.class'],
  Tok.meta: ['meta.decorator', 'entity.name.function.decorator', 'meta.preprocessor', 'keyword.control.directive'],
  Tok.func: ['entity.name.function', 'support.function'],
  Tok.tag: ['entity.name.tag'],
  Tok.property: [
    'variable.other.property',
    'variable.other.object.property',
    'support.type.property-name',
    'meta.object-literal.key',
    'variable',
  ],
};

/// Reads a theme file's text. [include] loads a file the theme includes, by
/// its path relative to the theme; it may return null when that file can't
/// be read, and the theme is used without it.
Future<EditorTheme> parseEditorTheme(
  String text, {
  String? name,
  bool? dark,
  Future<String?> Function(String path)? include,
}) async {
  final colors = <String, Color>{};
  final rules = <(String, Color)>[];
  var themeName = name;
  var type = dark;

  Future<void> load(String text, Future<String?> Function(String path)? include, int depth) async {
    final json = jsonDecode(stripJsonComments(text));
    if (json is! Map<String, dynamic>) throw const FormatException('Not a VS Code color theme');
    final inc = json['include'];
    if (inc is String && include != null && depth < 8) {
      final base = await include(inc);
      if (base != null) {
        await load(base, (p) => include(_join(inc, p)), depth + 1);
      }
    }
    if (depth == 0) {
      themeName ??= json['name'] as String?;
      final t = json['type'];
      if (t is String) type ??= t.toLowerCase().contains('dark') || t == 'hcDark';
    }
    final c = json['colors'];
    if (c is Map) {
      for (final e in c.entries) {
        final color = e.value is String ? parseThemeColor(e.value as String) : null;
        if (color != null) colors[e.key as String] = color;
      }
    }
    final tokens = json['tokenColors'];
    if (tokens is List) {
      for (final r in tokens) {
        if (r is! Map) continue;
        final settings = r['settings'];
        final fg = settings is Map && settings['foreground'] is String
            ? parseThemeColor(settings['foreground'] as String)
            : null;
        if (fg == null) continue;
        final scope = r['scope'];
        final selectors = switch (scope) {
          null => [''],
          String s => s.split(','),
          List l => [for (final s in l) if (s is String) ...s.split(',')],
          _ => const <String>[],
        };
        for (final s in selectors) {
          final sel = s.trim();
          // Descendant and exclusion selectors need the full scope stack.
          if (sel.contains(' ') || sel.startsWith('-')) continue;
          rules.add((sel, fg));
        }
      }
    }
  }

  await load(text, include, 0);
  final syntax = List<Color?>.filled(10, null);
  syntax[Tok.plain] = colors['editor.foreground'] ?? _match(rules, '');
  for (final e in _scopes.entries) {
    for (final scope in e.value) {
      final c = _match(rules, scope);
      if (c != null) {
        syntax[e.key] = c;
        break;
      }
    }
  }
  final bg = colors['editor.background'];
  return EditorTheme(
    name: themeName ?? 'VS Code theme',
    dark: type ?? (bg != null ? bg.computeLuminance() < 0.4 : true),
    colors: {
      for (final k in EditorTheme.usedColors)
        if (colors[k] != null) k: colors[k]!,
    },
    syntax: syntax,
  );
}

/// The color of the most specific rule matching [scope]; later rules win
/// ties, as in TextMate. An empty selector is the theme's default.
Color? _match(List<(String, Color)> rules, String scope) {
  Color? best;
  var bestLen = -1;
  for (final (sel, color) in rules) {
    final matches = sel.isEmpty ? scope.isEmpty : scope == sel || scope.startsWith('$sel.');
    if (matches && sel.length >= bestLen) {
      best = color;
      bestLen = sel.length;
    }
  }
  return best;
}

/// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`.
Color? parseThemeColor(String s) {
  var h = s.trim();
  if (!h.startsWith('#')) return null;
  h = h.substring(1);
  if (h.length == 3 || h.length == 4) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = '${h}ff';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(((v & 0xff) << 24) | (v >> 8));
}

/// JSON with comments and trailing commas, as VS Code writes it, as JSON.
String stripJsonComments(String s) {
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '"') {
      final start = i++;
      while (i < s.length && s[i] != '"') {
        if (s[i] == '\\') i++;
        i++;
      }
      out.write(s.substring(start, (i + 1).clamp(0, s.length)));
      i++;
    } else if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
    } else if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      final end = s.indexOf('*/', i + 2);
      i = end < 0 ? s.length : end + 2;
    } else if (c == ',') {
      var j = i + 1;
      while (j < s.length && ' \t\r\n'.contains(s[j])) {
        j++;
      }
      if (j < s.length && (s[j] == '}' || s[j] == ']')) {
        i++;
      } else {
        out.write(c);
        i++;
      }
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// [rel] resolved against the directory of [from], both `/`-separated.
String _join(String from, String rel) {
  final dir = from.contains('/') ? from.substring(0, from.lastIndexOf('/') + 1) : '';
  final parts = <String>[];
  for (final p in '$dir$rel'.split('/')) {
    if (p == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
    } else if (p != '.' && p.isNotEmpty) {
      parts.add(p);
    }
  }
  return '${from.startsWith('/') ? '/' : ''}${parts.join('/')}';
}

/// A theme from [source]: a URL of a theme `.json`, or the JSON itself.
Future<EditorTheme> importEditorTheme(String source, {http.Client? client}) async {
  final s = source.trim();
  if (s.startsWith('{')) return parseEditorTheme(s);
  final uri = Uri.tryParse(_rawUrl(s));
  if (uri == null || !uri.hasScheme) throw const FormatException('Paste a theme URL or its JSON');
  final c = client ?? http.Client();
  Future<String?> get(Uri u) async {
    final r = await c.get(u);
    if (r.statusCode != 200) return null;
    return utf8.decode(r.bodyBytes);
  }

  try {
    final text = await get(uri);
    if (text == null) throw FormatException('Could not load $uri');
    return await parseEditorTheme(text, include: (p) => get(uri.resolve(p)));
  } finally {
    if (client == null) c.close();
  }
}

/// GitHub file pages as their raw content.
String _rawUrl(String url) {
  final m = RegExp(r'^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$').firstMatch(url);
  return m == null ? url : 'https://raw.githubusercontent.com/${m[1]}/${m[2]}/${m[3]}';
}

/// A color theme contributed by an installed editor extension.
class InstalledTheme {
  const InstalledTheme({required this.label, required this.editor, required this.path, required this.dark});

  final String label;

  /// Which editor it was found in, e.g. "VS Code" or "Cursor".
  final String editor;
  final String path;
  final bool dark;

  Future<EditorTheme> load() async => parseEditorTheme(
    await File(path).readAsString(),
    name: label,
    dark: dark,
    include: (p) async {
      try {
        return await File(_join(path, p)).readAsString();
      } catch (_) {
        return null;
      }
    },
  );
}

/// The real home folder; in the macOS sandbox, HOME is the app's container.
String? _home() {
  final h = Platform.environment['HOME'];
  if (h == null) return null;
  final i = h.indexOf('/Library/Containers/');
  return i < 0 ? h : h.substring(0, i);
}

/// Extension folders of VS Code and its forks, by editor name.
List<(String, String)> _extensionDirs() {
  final home = _home();
  return [
    if (home != null) ...[
      ('VS Code', '$home/.vscode/extensions'),
      ('VS Code Insiders', '$home/.vscode-insiders/extensions'),
      ('Cursor', '$home/.cursor/extensions'),
      ('VSCodium', '$home/.vscode-oss/extensions'),
      ('Windsurf', '$home/.windsurf/extensions'),
    ],
    if (Platform.isMacOS)
      for (final (name, app) in const [
        ('VS Code', 'Visual Studio Code'),
        ('VS Code Insiders', 'Visual Studio Code - Insiders'),
        ('Cursor', 'Cursor'),
        ('VSCodium', 'VSCodium'),
        ('Windsurf', 'Windsurf'),
      ])
        (name, '/Applications/$app.app/Contents/Resources/app/extensions'),
  ];
}

/// Color themes of installed VS Code-like editors, built-in ones included.
Future<List<InstalledTheme>> findInstalledThemes() async {
  if (kIsWeb || !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) return const [];
  final out = <InstalledTheme>[];
  final seen = <String>{};
  for (final (editor, dir) in _extensionDirs()) {
    final d = Directory(dir);
    try {
      if (!await d.exists()) continue;
      await for (final ext in d.list()) {
        if (ext is! Directory) continue;
        try {
          final pkg = File('${ext.path}/package.json');
          if (!await pkg.exists()) continue;
          final json = jsonDecode(stripJsonComments(await pkg.readAsString()));
          final contributes = json is Map<String, dynamic> ? json['contributes'] : null;
          final themes = contributes is Map ? contributes['themes'] : null;
          if (themes is! List || themes.isEmpty) continue;
          Map<String, dynamic>? nls;
          for (final t in themes) {
            if (t is! Map || t['path'] is! String) continue;
            var label = (t['label'] ?? t['id'] ?? '') as String;
            final key = RegExp(r'^%(.+)%$').firstMatch(label)?[1];
            if (key != null) {
              nls ??= await _nls(ext.path);
              label = (nls?[key] as String?) ?? (t['id'] as String?) ?? key;
            }
            if (!seen.add('$editor/$label')) continue;
            final ui = (t['uiTheme'] as String?) ?? 'vs-dark';
            out.add(
              InstalledTheme(
                label: label,
                editor: editor,
                path: _join('${ext.path}/package.json', t['path'] as String),
                dark: ui == 'vs-dark' || ui == 'hc-black',
              ),
            );
          }
        } catch (_) {
          // A broken extension shouldn't hide the others.
        }
      }
    } catch (_) {}
  }
  out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return out;
}

Future<Map<String, dynamic>?> _nls(String dir) async {
  try {
    final v = jsonDecode(await File('$dir/package.nls.json').readAsString());
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}
