import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import 'common.dart';
import 'markdown_view.dart';

/// A markdown comment box with Write / Preview, used for conversation
/// comments, thread replies and new line comments. Ctrl/⌘+Enter posts.
///
/// [onSubmit] does the posting; if it throws, the text is kept and the error
/// is shown under the box.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.onSubmit,
    this.hint = 'Leave a comment',
    this.submitLabel = 'Comment',
    this.autofocus = false,
    this.collapsed = false,
    this.onCancel,
  });

  final Future<void> Function(String body) onSubmit;
  final String hint;
  final String submitLabel;
  final bool autofocus;

  /// Starts as a one-line "Reply…" field that expands on focus.
  final bool collapsed;
  final VoidCallback? onCancel;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

bool get _apple => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => true,
  _ => false,
};

class _CommentComposerState extends State<CommentComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _preview = false;
  bool _sending = false;
  bool _expanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.collapsed;
    _focus.addListener(() {
      if (_focus.hasFocus && !_expanded) setState(() => _expanded = true);
    });
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(body);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _preview = false;
        _expanded = !widget.collapsed;
      });
      if (widget.collapsed) _focus.unfocus();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e, hasToken: true));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _cancel() {
    _text.clear();
    _focus.unfocus();
    setState(() {
      _expanded = !widget.collapsed;
      _preview = false;
      _error = null;
    });
    widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (settings.token == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            const Expanded(child: Text('Add a GitHub token in Settings to comment.')),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/settings'),
              child: const Text('Settings'),
            ),
          ],
        ),
      );
    }

    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: widget.autofocus,
        enabled: !_sending,
        minLines: _expanded ? 3 : 1,
        maxLines: 12,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 14, height: 1.4),
        decoration: InputDecoration(hintText: widget.hint, isDense: !_expanded),
      ),
    );
    if (!_expanded) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Write')),
              ButtonSegment(value: true, label: Text('Preview')),
            ],
            selected: {_preview},
            onSelectionChanged: (s) => setState(() => _preview = s.first),
          ),
        ),
        const SizedBox(height: 8),
        if (_preview)
          Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: MarkdownView(_text.text, emptyText: 'Nothing to preview.'),
          )
        else
          field,
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Markdown supported · ${_apple ? '⌘' : 'Ctrl'}+Enter to post',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.collapsed || widget.onCancel != null)
              TextButton(onPressed: _sending ? null : _cancel, child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _sending || _text.text.trim().isEmpty ? null : _submit,
              child: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.submitLabel),
            ),
          ],
        ),
      ],
    );
  }
}
