import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../app/editor_theme.dart';
import '../app/settings.dart';
import '../diff/syntax.dart';
import '../github/models.dart';

const kCodeFont = 'JetBrainsMono';
const _seed = Color(0xFF4F5BD5);

/// The app theme. With an [editor] theme, its accent seeds the app's colors
/// and the diff uses its colors.
ThemeData buildTheme(Brightness brightness, {CodeColors codeColors = CodeColors.github, EditorTheme? editor}) {
  final accent = editor?['button.background'] ?? editor?['focusBorder'];
  final scheme = ColorScheme.fromSeed(
    seedColor: accent?.withValues(alpha: 1) ?? _seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  return base.copyWith(
    extensions: [
      if (editor != null)
        DiffTheme.editor(scheme, editor, dark: brightness == Brightness.dark)
      else if (brightness == Brightness.dark)
        DiffTheme.dark(scheme, codeColors)
      else
        DiffTheme.light(scheme, codeColors),
    ],
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
    tabBarTheme: TabBarThemeData(
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.6),
      labelStyle: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: base.textTheme.titleSmall,
      tabAlignment: TabAlignment.start,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    visualDensity: VisualDensity.standard,
  );
}

/// Colors for diffs and code, modeled on GitHub's Primer palette.
@immutable
class DiffTheme extends ThemeExtension<DiffTheme> {
  const DiffTheme({
    required this.addBg,
    required this.addGutter,
    required this.addWord,
    required this.delBg,
    required this.delGutter,
    required this.delWord,
    required this.hunkBg,
    required this.hunkFg,
    required this.hunkGutter,
    required this.hunkActive,
    required this.lineNo,
    required this.headerBg,
    required this.code,
    required this.searchHit,
    required this.searchCurrent,
    required this.syntax,
    required this.addFg,
    required this.delFg,
    this.codeBg,
    this.emptySide,
  });

  final Color addBg, addGutter, addWord, delBg, delGutter, delWord;
  final Color hunkBg, hunkFg, lineNo, headerBg, code;

  /// The hunk header's gutter, and its expand buttons while hovered.
  final Color hunkGutter, hunkActive;
  final Color searchHit, searchCurrent;
  final Color addFg, delFg;

  /// Behind unchanged lines, and where a split side has no line; the app's
  /// surface when null.
  final Color? codeBg, emptySide;

  /// Indexed by [Tok] values.
  final List<Color> syntax;

  factory DiffTheme.light(ColorScheme s, [CodeColors colors = CodeColors.github]) => DiffTheme(
    addBg: const Color(0xFFE6FFEC),
    addGutter: const Color(0xFFCCFFD8),
    addWord: const Color(0xFFABF2BC),
    delBg: const Color(0xFFFFEBE9),
    delGutter: const Color(0xFFFFD7D5),
    delWord: const Color(0x66FF8182),
    hunkBg: const Color(0xFFDDF4FF),
    hunkFg: const Color(0xFF57606A),
    hunkGutter: const Color(0xFFBBDFFF),
    hunkActive: const Color(0xFF0969DA),
    lineNo: const Color(0xFF8C959F),
    headerBg: s.surfaceContainer,
    code: _syntax(colors, dark: false)[Tok.plain],
    searchHit: const Color(0x80FFD33D),
    searchCurrent: const Color(0xFFFF9632),
    addFg: const Color(0xFF1A7F37),
    delFg: const Color(0xFFCF222E),
    syntax: _syntax(colors, dark: false),
  );

  factory DiffTheme.dark(ColorScheme s, [CodeColors colors = CodeColors.github]) => DiffTheme(
    addBg: const Color(0x262EA043),
    addGutter: const Color(0x4D3FB950),
    addWord: const Color(0x662EA043),
    delBg: const Color(0x1AF85149),
    delGutter: const Color(0x4DF85149),
    delWord: const Color(0x66F85149),
    hunkBg: const Color(0x1A388BFD),
    hunkFg: const Color(0xFF8B949E),
    hunkGutter: const Color(0x66388BFD),
    hunkActive: const Color(0xFF1F6FEB),
    lineNo: const Color(0xFF6E7681),
    headerBg: s.surfaceContainer,
    code: _syntax(colors, dark: true)[Tok.plain],
    searchHit: const Color(0x66D29922),
    searchCurrent: const Color(0xFFDB6D28),
    addFg: const Color(0xFF3FB950),
    delFg: const Color(0xFFF85149),
    syntax: _syntax(colors, dark: true),
  );

  /// Colors of a VS Code theme, with VS Code's defaults for the diff colors
  /// it doesn't set.
  factory DiffTheme.editor(ColorScheme s, EditorTheme e, {required bool dark}) {
    final base = dark ? DiffTheme.dark(s) : DiffTheme.light(s);
    final bg = e['editor.background'] ?? s.surface;
    final fg = e.syntax[Tok.plain] ?? base.code;
    Color solid(Color c) => Color.alphaBlend(c, bg);
    final addBg = solid(e['diffEditor.insertedLineBackground'] ?? const Color(0x339BB955));
    final delBg = solid(e['diffEditor.removedLineBackground'] ?? const Color(0x33FF0000));
    final lineNo = e['editorLineNumber.foreground'] ?? base.lineNo;
    return DiffTheme(
      addBg: addBg,
      addGutter: _solidOr(e['diffEditorGutter.insertedLineBackground'], bg, addBg),
      addWord: e['diffEditor.insertedTextBackground'] ?? (dark ? const Color(0x339CCC2C) : const Color(0x409CCC2C)),
      delBg: delBg,
      delGutter: _solidOr(e['diffEditorGutter.removedLineBackground'], bg, delBg),
      delWord: e['diffEditor.removedTextBackground'] ?? const Color(0x33FF0000),
      hunkBg: base.hunkBg,
      hunkFg: base.hunkFg,
      hunkGutter: base.hunkGutter,
      hunkActive: base.hunkActive,
      lineNo: lineNo,
      headerBg: base.headerBg,
      code: fg,
      searchHit: e['editor.findMatchHighlightBackground'] ?? base.searchHit,
      searchCurrent: e['editor.findMatchBackground'] ?? base.searchCurrent,
      addFg: e['editorGutter.addedBackground'] ?? base.addFg,
      delFg: e['editorGutter.deletedBackground'] ?? base.delFg,
      syntax: [for (var i = 0; i < base.syntax.length; i++) e.syntax[i] ?? (i == Tok.comment ? lineNo : fg)],
      codeBg: bg,
      emptySide: Color.alphaBlend(fg.withValues(alpha: 0.05), bg),
    );
  }

  static DiffTheme of(BuildContext context) => Theme.of(context).extension<DiffTheme>()!;

  Color syntaxColor(int tok) => tok < syntax.length ? syntax[tok] : syntax[Tok.plain];

  @override
  DiffTheme copyWith() => this;

  @override
  DiffTheme lerp(DiffTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}

Color _solidOr(Color? c, Color bg, Color fallback) => c == null ? fallback : Color.alphaBlend(c, bg);

/// Token colors indexed by [Tok]: plain, keyword, string, comment, number,
/// type, meta, func, tag, property.
List<Color> _syntax(CodeColors colors, {required bool dark}) => switch ((colors, dark)) {
  (CodeColors.github, false) => const [
    Color(0xFF1F2328),
    Color(0xFFCF222E),
    Color(0xFF0A3069),
    Color(0xFF6E7781),
    Color(0xFF0550AE),
    Color(0xFF953800),
    Color(0xFF8250DF),
    Color(0xFF6639BA),
    Color(0xFF116329),
    Color(0xFF0550AE),
  ],
  (CodeColors.github, true) => const [
    Color(0xFFE6EDF3),
    Color(0xFFFF7B72),
    Color(0xFFA5D6FF),
    Color(0xFF8B949E),
    Color(0xFF79C0FF),
    Color(0xFFFFA657),
    Color(0xFFD2A8FF),
    Color(0xFFD2A8FF),
    Color(0xFF7EE787),
    Color(0xFF79C0FF),
  ],
  (CodeColors.solarized, false) => const [
    Color(0xFF586E75),
    Color(0xFF859900),
    Color(0xFF2AA198),
    Color(0xFF93A1A1),
    Color(0xFFD33682),
    Color(0xFFB58900),
    Color(0xFFCB4B16),
    Color(0xFF268BD2),
    Color(0xFF268BD2),
    Color(0xFF6C71C4),
  ],
  (CodeColors.solarized, true) => const [
    Color(0xFF93A1A1),
    Color(0xFF859900),
    Color(0xFF2AA198),
    Color(0xFF657B83),
    Color(0xFFD33682),
    Color(0xFFB58900),
    Color(0xFFCB4B16),
    Color(0xFF268BD2),
    Color(0xFF268BD2),
    Color(0xFF6C71C4),
  ],
  (CodeColors.one, false) => const [
    Color(0xFF383A42),
    Color(0xFFA626A4),
    Color(0xFF50A14F),
    Color(0xFFA0A1A7),
    Color(0xFF986801),
    Color(0xFFC18401),
    Color(0xFF0184BC),
    Color(0xFF4078F2),
    Color(0xFFE45649),
    Color(0xFFE45649),
  ],
  (CodeColors.one, true) => const [
    Color(0xFFABB2BF),
    Color(0xFFC678DD),
    Color(0xFF98C379),
    Color(0xFF7F848E),
    Color(0xFFD19A66),
    Color(0xFFE5C07B),
    Color(0xFF56B6C2),
    Color(0xFF61AFEF),
    Color(0xFFE06C75),
    Color(0xFFE06C75),
  ],
  (CodeColors.mono, false) => const [
    Color(0xFF1F2328),
    Color(0xFF1F2328),
    Color(0xFF1F2328),
    Color(0xFF8C959F),
    Color(0xFF1F2328),
    Color(0xFF1F2328),
    Color(0xFF1F2328),
    Color(0xFF1F2328),
    Color(0xFF1F2328),
    Color(0xFF1F2328),
  ],
  (CodeColors.mono, true) => const [
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
    Color(0xFF7D8590),
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
    Color(0xFFE6EDF3),
  ],
};

/// The font family for [SettingsController.codeFont].
String codeFontFamily(String font) => switch (font) {
  '' => kCodeFont,
  kSystemCodeFont => systemMonoFont,
  _ => font,
};

String get systemMonoFont => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => 'Menlo',
  TargetPlatform.windows => 'Consolas',
  _ => 'monospace',
};

/// Colors for PR states, matching GitHub's conventions.
({Color color, IconData icon, String label}) prStateStyle(PrState state, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (state) {
    PrState.open => (
      color: dark ? const Color(0xFF3FB950) : const Color(0xFF1A7F37),
      icon: Icons.call_split_rounded,
      label: 'Open',
    ),
    PrState.draft => (color: scheme.outline, icon: Icons.edit_note_rounded, label: 'Draft'),
    PrState.merged => (
      color: dark ? const Color(0xFFA371F7) : const Color(0xFF8250DF),
      icon: Icons.merge_rounded,
      label: 'Merged',
    ),
    PrState.closed => (
      color: dark ? const Color(0xFFF85149) : const Color(0xFFCF222E),
      icon: Icons.do_not_disturb_on_outlined,
      label: 'Closed',
    ),
  };
}
