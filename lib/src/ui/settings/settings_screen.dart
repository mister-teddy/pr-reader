import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/editor_theme.dart';
import '../../app/fonts.dart';
import '../../app/services.dart';
import '../../app/settings.dart';
import '../../diff/diff_models.dart';
import '../../diff/syntax.dart';
import '../../github/models.dart';
import '../diff/diff_view.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _newTokenUrl = 'https://github.com/settings/tokens/new?scopes=repo&description=PR%20Reader';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _token = TextEditingController();
  bool _saving = false;
  String? _tokenError;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _saveToken(AppServices s) async {
    final value = _token.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _saving = true;
      _tokenError = null;
    });
    final previous = s.gh.token;
    s.gh.token = value;
    try {
      await s.gh.getViewer();
      await s.settings.setToken(value);
      _token.clear();
    } catch (e) {
      s.gh.token = previous;
      _tokenError = describeError(e, hasToken: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final settings = services.settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            ReadableWidth(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Section(
                    title: 'GitHub account',
                    children: [
                      if (settings.token != null)
                        ValueListenableBuilder<GhUser?>(
                          valueListenable: services.viewer,
                          builder: (context, user, _) => ListTile(
                            leading: user == null ? const Icon(Icons.key_rounded) : Avatar(user, size: 36),
                            title: Text(user?.login ?? 'Token saved'),
                            subtitle: Text(
                              settings.tokenInsecure
                                  ? 'Stored in app preferences (system keychain unavailable)'
                                  : 'Stored in ${_keychainName()}',
                            ),
                            trailing: TextButton(
                              onPressed: () => settings.setToken(null),
                              child: const Text('Remove'),
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'A personal access token lets you read private repositories and raises the rate limit '
                                'to 5,000 requests per hour. Classic tokens need the "repo" scope; fine-grained '
                                'tokens need read access to contents and read and write access to pull requests, '
                                'which commenting and syncing "Viewed" marks use.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _token,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) => _saveToken(services),
                                decoration: InputDecoration(
                                  hintText: 'ghp_… or github_pat_…',
                                  prefixIcon: const Icon(Icons.key_rounded),
                                  errorText: _tokenError,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  FilledButton(
                                    onPressed: _saving ? null : () => _saveToken(services),
                                    child: _saving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Text('Save token'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () => openUrl(_newTokenUrl),
                                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                    label: const Text('Create a token'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ValueListenableBuilder<RateLimitInfo?>(
                        valueListenable: services.rateLimit,
                        builder: (context, r, _) => r == null
                            ? const SizedBox.shrink()
                            : ListTile(
                                leading: const Icon(Icons.speed_rounded),
                                title: Text(
                                  '${formatCount(r.remaining)} of ${formatCount(r.limit)} API requests left',
                                ),
                                subtitle: Text(
                                  'Resets in ${r.resetAt.difference(DateTime.now()).inMinutes.clamp(0, 999)} min',
                                ),
                              ),
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Appearance',
                    children: [
                      _Choice<_ThemeChoice>(
                        label: 'Theme',
                        value: settings.editorTheme != null ? _ThemeChoice.vsCode : _ThemeChoice.of(settings.themeMode),
                        options: const {
                          _ThemeChoice.system: 'System',
                          _ThemeChoice.light: 'Light',
                          _ThemeChoice.dark: 'Dark',
                          _ThemeChoice.vsCode: 'VS Code',
                        },
                        onChanged: (v) {
                          final mode = v.mode;
                          if (mode != null) {
                            settings.setThemeMode(mode);
                          } else if (settings.editorTheme == null) {
                            _pickEditorTheme(context, settings);
                          }
                        },
                      ),
                      if (settings.editorTheme case final t?)
                        ListTile(
                          title: const Text('VS Code theme'),
                          subtitle: Text('${t.name} · ${t.dark ? 'dark' : 'light'}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _pickEditorTheme(context, settings),
                        )
                      else
                        _Choice<CodeColors>(
                          label: 'Code colors',
                          value: settings.codeColors,
                          options: _builtInColors,
                          onChanged: settings.setCodeColors,
                        ),
                      ListTile(
                        title: const Text('Code font'),
                        subtitle: Text(_fontLabel(settings.codeFont)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showInWindowDialog<void>(
                          context: context,
                          builder: (_) => _FontDialog(settings: settings),
                        ),
                      ),
                      ListTile(
                        title: const Text('Code font size'),
                        subtitle: Slider(
                          value: settings.diffFontSize,
                          min: 9,
                          max: 20,
                          divisions: 11,
                          label: settings.diffFontSize.round().toString(),
                          onChanged: settings.setDiffFontSize,
                        ),
                        trailing: Text('${settings.diffFontSize.round()} pt'),
                      ),
                      _Choice<LineSpacing>(
                        label: 'Line spacing',
                        value: settings.lineSpacing,
                        options: const {
                          LineSpacing.compact: 'Compact',
                          LineSpacing.normal: 'Normal',
                          LineSpacing.relaxed: 'Relaxed',
                        },
                        onChanged: settings.setLineSpacing,
                      ),
                      SwitchListTile(
                        title: const Text('Syntax highlighting'),
                        value: settings.syntaxHighlight,
                        onChanged: settings.setSyntaxHighlight,
                      ),
                      const _CodePreview(),
                    ],
                  ),
                  _Section(
                    title: 'Diff',
                    children: [
                      _Choice<DiffLayoutPref>(
                        label: 'Layout',
                        help: 'Auto shows side by side on wide windows.',
                        value: settings.diffLayout,
                        options: const {
                          DiffLayoutPref.auto: 'Auto',
                          DiffLayoutPref.unified: 'Unified',
                          DiffLayoutPref.split: 'Split',
                        },
                        onChanged: settings.setDiffLayout,
                      ),
                      _Choice<WrapPref>(
                        label: 'Wrap long lines',
                        help: 'Auto wraps on narrow screens. Split view always wraps.',
                        value: settings.wrap,
                        options: const {WrapPref.auto: 'Auto', WrapPref.on: 'On', WrapPref.off: 'Off'},
                        onChanged: settings.setWrap,
                      ),
                      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)
                        SwitchListTile(
                          title: const Text('Separate windows'),
                          subtitle: const Text(
                            'Open PRs and single files in their own windows (⌘N). Experimental; '
                            'takes effect after restarting the app.',
                          ),
                          value: settings.multiWindow,
                          onChanged: settings.setMultiWindow,
                        ),
                    ],
                  ),
                  _Section(
                    title: 'Data',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.history_rounded),
                        title: const Text('Clear recent pull requests'),
                        onTap: () {
                          settings.clearRecents();
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(const SnackBar(content: Text('Recent list cleared')));
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.check_box_outline_blank_rounded),
                        title: const Text('Clear all "viewed" marks'),
                        onTap: () async {
                          await settings.clearViewed();
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(const SnackBar(content: Text('Viewed marks cleared')));
                          }
                        },
                      ),
                    ],
                  ),
                  _Section(
                    title: 'Keyboard shortcuts',
                    children: const [
                      _Shortcut('j / k', 'Next / previous file'),
                      _Shortcut('v', 'Toggle viewed on current file'),
                      _Shortcut('x', 'Collapse / expand current file'),
                      _Shortcut('t', 'Toggle file tree'),
                      _Shortcut('/  or  Ctrl/⌘ F', 'Search in diff'),
                      _Shortcut('n / Shift n', 'Next / previous match'),
                      _Shortcut('Space / Page Down', 'Scroll a page'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _keychainName() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => 'the system keychain',
  TargetPlatform.android => "Android's secure storage",
  _ => kIsWeb ? 'browser storage' : 'secure storage',
};

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.help,
  });

  final String label;
  final String? help;

  /// Null when none of [options] applies.
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 16,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
              if (help != null)
                Text(
                  help!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          SegmentedButton<T>(
            showSelectedIcon: false,
            style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10))),
            segments: [
              for (final e in options.entries)
                ButtonSegment(
                  value: e.key,
                  label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value, maxLines: 1, softWrap: false)),
                ),
            ],
            selected: {?value},
            emptySelectionAllowed: value == null,
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
          ),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.keys, this.action);

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      title: Text(action),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(keys, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _CodePreview extends StatelessWidget {
  const _CodePreview();

  static const _lines = [
    (LineKind.context, 12, 'function greet(name: string) {'),
    (LineKind.del, 13, '  return "Hi " + name; // old'),
    (LineKind.add, 13, '  return `Hello, \${name}!`; // new'),
    (LineKind.context, 14, '}'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final d = DiffTheme.of(context);
    final code = CodeMetrics.of(
      settings.diffFontSize,
      d.code,
      family: codeFontFamily(settings.codeFont),
      spacing: settings.lineSpacing.factor,
    );
    final spec = languageFor('preview.ts')!;
    Widget line((LineKind, int, String) l) {
      final (kind, no, text) = l;
      final spans = <TextSpan>[];
      if (settings.syntaxHighlight) {
        final (toks, _) = tokenizeLine(text, spec, 0);
        var at = 0;
        for (var i = 0; i + 2 < toks.length; i += 3) {
          if (toks[i] > at) spans.add(TextSpan(text: text.substring(at, toks[i])));
          spans.add(TextSpan(text: text.substring(toks[i], toks[i + 1]), style: TextStyle(color: d.syntaxColor(toks[i + 2]))));
          at = toks[i + 1];
        }
        if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
      } else {
        spans.add(TextSpan(text: text));
      }
      final sign = switch (kind) {
        LineKind.add => '+',
        LineKind.del => '-',
        _ => ' ',
      };
      return ColoredBox(
        color: switch (kind) {
          LineKind.add => d.addBg,
          LineKind.del => d.delBg,
          _ => d.codeBg ?? Colors.transparent,
        },
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${'$no'.padLeft(3)} ', style: TextStyle(color: d.lineNo)),
              TextSpan(text: '$sign ', style: TextStyle(color: kind == LineKind.add ? d.addFg : d.delFg)),
              ...spans,
            ],
          ),
          style: code.style,
          strutStyle: code.strut,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textScaler: TextScaler.noScaling,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final l in _lines) line(l)],
            ),
          ),
        ),
      ),
    );
  }
}

String _fontLabel(String font) => switch (font) {
  '' => 'JetBrains Mono',
  kSystemCodeFont => 'System ($systemMonoFont)',
  _ => font,
};

enum _ThemeChoice {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark),
  vsCode(null);

  const _ThemeChoice(this.mode);
  final ThemeMode? mode;

  static _ThemeChoice of(ThemeMode m) => values.firstWhere((c) => c.mode == m);
}

Future<void> _pickEditorTheme(BuildContext context, SettingsController settings) =>
    showInWindowDialog<void>(context: context, builder: (_) => _EditorThemeDialog(settings: settings));

const _builtInColors = {
  CodeColors.github: 'GitHub',
  CodeColors.solarized: 'Solarized',
  CodeColors.one: 'One',
  CodeColors.mono: 'Mono',
};

/// Picks a VS Code color theme: one installed with an editor, or a theme
/// file by URL or pasted JSON.
class _EditorThemeDialog extends StatefulWidget {
  const _EditorThemeDialog({required this.settings});

  final SettingsController settings;

  @override
  State<_EditorThemeDialog> createState() => _EditorThemeDialogState();
}

class _EditorThemeDialogState extends State<_EditorThemeDialog> {
  final _source = TextEditingController();
  final _filter = TextEditingController();
  late final Future<List<InstalledTheme>> _installed = findInstalledThemes();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _source.dispose();
    _filter.dispose();
    super.dispose();
  }

  Future<void> _use(Future<EditorTheme> Function() load) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await load();
      widget.settings.setEditorTheme(t);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'Could not read this theme: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.settings.editorTheme?.name;
    return AlertDialog(
      title: const Text('VS Code theme'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'The diff takes the theme\'s colors, and the app its light or dark mode.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _source,
                    enabled: !_busy,
                    decoration: const InputDecoration(hintText: 'Theme .json URL, or paste its JSON'),
                    onSubmitted: (v) => _use(() => importEditorTheme(v)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _use(() => importEditorTheme(_source.text)),
                  child: const Text('Import'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            FutureBuilder(
              future: _installed,
              builder: (context, snap) {
                final all = snap.data ?? const <InstalledTheme>[];
                if (snap.connectionState != ConnectionState.done || all.isEmpty) return const SizedBox(height: 12);
                return ListenableBuilder(
                  listenable: _filter,
                  builder: (context, _) {
                    final q = _filter.text.toLowerCase();
                    final shown = [
                      for (final t in all)
                        if (q.isEmpty || '${t.label} ${t.editor}'.toLowerCase().contains(q)) t,
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text('Installed', style: theme.textTheme.labelLarge),
                        ),
                        if (all.length > 8)
                          TextField(
                            controller: _filter,
                            decoration: const InputDecoration(
                              hintText: 'Filter themes',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final t = shown[i];
                              return ListTile(
                                dense: true,
                                enabled: !_busy,
                                leading: Icon(t.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 20),
                                title: Text(t.label),
                                subtitle: Text(t.editor),
                                trailing: t.label == current ? const Icon(Icons.check_rounded) : null,
                                onTap: () => _use(t.load),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

/// Picks the code font: the bundled one, the system's, or any installed
/// monospaced font (macOS), each shown in itself.
class _FontDialog extends StatefulWidget {
  const _FontDialog({required this.settings});

  final SettingsController settings;

  @override
  State<_FontDialog> createState() => _FontDialogState();
}

class _FontDialogState extends State<_FontDialog> {
  late final Future<List<String>> _families = monospaceFamilies();
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final theme = Theme.of(context);
    Widget option(String value, String family, String label, {String? note}) => ListTile(
      dense: true,
      title: Text(label, style: TextStyle(fontFamily: family, fontSize: 15)),
      subtitle: note == null ? null : Text(note),
      trailing: settings.codeFont == value ? const Icon(Icons.check_rounded) : null,
      onTap: () {
        settings.setCodeFont(value);
        Navigator.of(context).pop();
      },
    );

    return AlertDialog(
      title: const Text('Code font'),
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      content: SizedBox(
        width: 420,
        child: FutureBuilder(
          future: _families,
          builder: (context, snap) {
            final installed = [
              for (final f in snap.data ?? const <String>[])
                if (f != kCodeFont && f != systemMonoFont) f,
            ];
            return ListenableBuilder(
              listenable: _filter,
              builder: (context, _) {
                final q = _filter.text.toLowerCase();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    option('', kCodeFont, 'JetBrains Mono', note: 'Built in'),
                    option(kSystemCodeFont, systemMonoFont, systemMonoFont, note: 'System default'),
                    if (installed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Installed monospaced fonts', style: theme.textTheme.titleSmall),
                      ),
                      if (installed.length > 8)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextField(
                            controller: _filter,
                            decoration: const InputDecoration(
                              hintText: 'Filter fonts',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final f in installed)
                              if (q.isEmpty || f.toLowerCase().contains(q)) option(f, f, f),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
