import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../app/settings.dart';
import '../../github/models.dart';
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
                                  : 'Stored in the system keychain',
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
                                'to 5,000 requests per hour. Read-only access is enough: classic tokens need the '
                                '"repo" scope for private repos; fine-grained tokens need read access to pull requests '
                                'and contents.',
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
                      _Choice<ThemeMode>(
                        label: 'Theme',
                        value: settings.themeMode,
                        options: const {
                          ThemeMode.system: 'System',
                          ThemeMode.light: 'Light',
                          ThemeMode.dark: 'Dark',
                        },
                        onChanged: settings.setThemeMode,
                      ),
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
                      SwitchListTile(
                        title: const Text('Syntax highlighting'),
                        value: settings.syntaxHighlight,
                        onChanged: settings.setSyntaxHighlight,
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
  final T value;
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
            segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
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
