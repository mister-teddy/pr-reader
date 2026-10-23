import 'package:flutter/material.dart';

import '../diff/syntax.dart';
import '../github/models.dart';

const kCodeFont = 'JetBrainsMono';
const _seed = Color(0xFF4F5BD5);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  return base.copyWith(
    extensions: [brightness == Brightness.dark ? DiffTheme.dark(scheme) : DiffTheme.light(scheme)],
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
    required this.lineNo,
    required this.headerBg,
    required this.code,
    required this.searchHit,
    required this.searchCurrent,
    required this.syntax,
    required this.addFg,
    required this.delFg,
  });

  final Color addBg, addGutter, addWord, delBg, delGutter, delWord;
  final Color hunkBg, hunkFg, lineNo, headerBg, code;
  final Color searchHit, searchCurrent;
  final Color addFg, delFg;

  /// Indexed by [Tok] values.
  final List<Color> syntax;

  factory DiffTheme.light(ColorScheme s) => DiffTheme(
    addBg: const Color(0xFFE6FFEC),
    addGutter: const Color(0xFFCCFFD8),
    addWord: const Color(0xFFABF2BC),
    delBg: const Color(0xFFFFEBE9),
    delGutter: const Color(0xFFFFD7D5),
    delWord: const Color(0x66FF8182),
    hunkBg: const Color(0xFFDDF4FF),
    hunkFg: const Color(0xFF57606A),
    lineNo: const Color(0xFF8C959F),
    headerBg: s.surfaceContainer,
    code: const Color(0xFF1F2328),
    searchHit: const Color(0x80FFD33D),
    searchCurrent: const Color(0xFFFF9632),
    addFg: const Color(0xFF1A7F37),
    delFg: const Color(0xFFCF222E),
    syntax: const [
      Color(0xFF1F2328), // plain
      Color(0xFFCF222E), // keyword
      Color(0xFF0A3069), // string
      Color(0xFF6E7781), // comment
      Color(0xFF0550AE), // number
      Color(0xFF953800), // type
      Color(0xFF8250DF), // meta
      Color(0xFF6639BA), // func
      Color(0xFF116329), // tag
      Color(0xFF0550AE), // property
    ],
  );

  factory DiffTheme.dark(ColorScheme s) => DiffTheme(
    addBg: const Color(0x262EA043),
    addGutter: const Color(0x4D3FB950),
    addWord: const Color(0x662EA043),
    delBg: const Color(0x1AF85149),
    delGutter: const Color(0x4DF85149),
    delWord: const Color(0x66F85149),
    hunkBg: const Color(0x1A388BFD),
    hunkFg: const Color(0xFF8B949E),
    lineNo: const Color(0xFF6E7681),
    headerBg: s.surfaceContainer,
    code: const Color(0xFFE6EDF3),
    searchHit: const Color(0x66D29922),
    searchCurrent: const Color(0xFFDB6D28),
    addFg: const Color(0xFF3FB950),
    delFg: const Color(0xFFF85149),
    syntax: const [
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
  );

  static DiffTheme of(BuildContext context) => Theme.of(context).extension<DiffTheme>()!;

  Color syntaxColor(int tok) => tok < syntax.length ? syntax[tok] : syntax[Tok.plain];

  @override
  DiffTheme copyWith() => this;

  @override
  DiffTheme lerp(DiffTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}

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
