import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme.dart';
import 'common.dart';

/// Renders GitHub-flavored markdown, including the handful of HTML tags
/// that show up constantly in PR descriptions (images, details, br, ...).
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key, this.emptyText = 'No description provided.'});

  final String data;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = githubHtmlToMarkdown(data).trim();
    if (text.isEmpty) {
      return Text(
        emptyText,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final codeStyle = TextStyle(
      fontFamily: kCodeFont,
      fontSize: 13,
      color: scheme.onSurface,
      backgroundColor: Colors.transparent,
    );
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      code: codeStyle.copyWith(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        fontSize: 12.5,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      h1: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      h2: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
      h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary.withValues(alpha: 0.4),
      ),
      tableBorder: TableBorder.all(color: scheme.outlineVariant, width: 0.5),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
      ),
    );
    return MarkdownBody(
      data: text,
      styleSheet: sheet,
      extensionSet: md.ExtensionSet.gitHubWeb,
      onTapLink: (_, href, _) {
        if (href != null) openUrl(href);
      },
      imageBuilder: (uri, title, alt) => _MarkdownImage(uri: uri, alt: alt),
    );
  }
}

class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({required this.uri, this.alt});

  final Uri uri;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              (alt == null || alt!.isEmpty) ? 'image' : alt!,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    if (!uri.isScheme('http') && !uri.isScheme('https')) return fallback;
    return InkWell(
      onTap: () => openUrl(uri.toString()),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: scheme.outline)),
                ),
        ),
      ),
    );
  }
}

final _fenceRe = RegExp(r'^(\s*)(```|~~~)', multiLine: true);
final _commentRe = RegExp(r'<!--[\s\S]*?-->');
final _imgRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
final _attrRe = RegExp(r'''(\w+)\s*=\s*("([^"]*)"|'([^']*)')''');
final _brRe = RegExp(r'<br\s*/?>', caseSensitive: false);
final _summaryRe = RegExp(r'<summary[^>]*>([\s\S]*?)</summary>', caseSensitive: false);
final _linkRe = RegExp(r'<a\b[^>]*href\s*=\s*"([^"]*)"[^>]*>([\s\S]*?)</a>', caseSensitive: false);
final _codeRe = RegExp(r'<code>([\s\S]*?)</code>', caseSensitive: false);
final _boldRe = RegExp(r'<(b|strong)>([\s\S]*?)</\1>', caseSensitive: false);
final _italicRe = RegExp(r'<(i|em)>([\s\S]*?)</\1>', caseSensitive: false);
final _headingRe = RegExp(r'<h([1-6])[^>]*>([\s\S]*?)</h\1>', caseSensitive: false);
final _stripRe = RegExp(
  r'</?(details|p|div|span|sub|sup|center|picture|source|kbd|ins|small|big|font|tt|u|a|table|thead|tbody|tr|td|th|video|dl|dt|dd)\b[^>]*>',
  caseSensitive: false,
);

/// Converts common inline HTML to markdown, leaving fenced code untouched.
String githubHtmlToMarkdown(String input) {
  if (!input.contains('<')) return input;
  final out = StringBuffer();
  var inFence = false;
  var last = 0;
  String? fence;
  for (final m in _fenceRe.allMatches(input)) {
    final segment = input.substring(last, m.start);
    out.write(inFence ? segment : _convert(segment));
    last = m.start;
    final marker = m.group(2)!;
    if (!inFence) {
      inFence = true;
      fence = marker;
    } else if (marker == fence) {
      inFence = false;
    }
  }
  final tail = input.substring(last);
  out.write(inFence ? tail : _convert(tail));
  return out.toString();
}

String _convert(String s) {
  if (!s.contains('<')) return s;
  return s
      .replaceAll(_commentRe, '')
      .replaceAllMapped(_imgRe, (m) {
        final attrs = <String, String>{
          for (final a in _attrRe.allMatches(m.group(0)!))
            a.group(1)!.toLowerCase(): a.group(3) ?? a.group(4) ?? '',
        };
        final src = attrs['src'];
        if (src == null) return '';
        return '![${attrs['alt'] ?? ''}]($src)';
      })
      .replaceAllMapped(_summaryRe, (m) => '\n**${m.group(1)!.trim()}**\n\n')
      .replaceAllMapped(_linkRe, (m) => '[${m.group(2)}](${m.group(1)})')
      .replaceAllMapped(_codeRe, (m) => '`${m.group(1)}`')
      .replaceAllMapped(_boldRe, (m) => '**${m.group(2)}**')
      .replaceAllMapped(_italicRe, (m) => '*${m.group(2)}*')
      .replaceAllMapped(_headingRe, (m) => '\n${'#' * int.parse(m.group(1)!)} ${m.group(2)!.trim()}\n')
      .replaceAll(_brRe, '  \n')
      .replaceAll(_stripRe, '');
}
