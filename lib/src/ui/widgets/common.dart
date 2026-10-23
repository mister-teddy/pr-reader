import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../github/github_client.dart';
import '../../github/models.dart';
import '../theme.dart';

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 30) return '${d.inDays}d ago';
  if (d.inDays < 365) return '${d.inDays ~/ 30}mo ago';
  return '${d.inDays ~/ 365}y ago';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final base = '${_months[t.month - 1]} ${t.day}';
  return t.year == now.year ? base : '$base, ${t.year}';
}

String formatCount(int n) {
  if (n < 1000) return '$n';
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String describeError(Object error, {bool hasToken = false}) {
  if (error is GitHubException) {
    if (error.isRateLimited) {
      final mins = error.resetAt == null
          ? null
          : error.resetAt!.difference(DateTime.now()).inMinutes.clamp(0, 999) + 1;
      final wait = mins == null ? '' : ' Try again in about $mins min.';
      return hasToken
          ? 'GitHub rate limit reached.$wait'
          : 'GitHub rate limit reached for anonymous use.$wait Add a token in Settings for 5,000 requests per hour.';
    }
    if (error.isNotFound) {
      return hasToken
          ? 'Pull request not found, or your token cannot access it.'
          : 'Pull request not found. If it is private, add a token in Settings.';
    }
    if (error.isUnauthorized) return 'Your GitHub token was rejected. Update it in Settings.';
    return error.message;
  }
  return '$error';
}

Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> copyText(BuildContext context, String text, {String? message}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message ?? 'Copied'), behavior: SnackBarBehavior.floating, width: 280),
    );
}

class Avatar extends StatelessWidget {
  const Avatar(this.user, {super.key, this.size = 24});

  final GhUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user?.avatarUrl;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round();
    final fallback = Center(
      child: Text(
        (user?.login ?? '?').characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.45,
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Tooltip(
      message: user?.login ?? '',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: user?.isBot == true ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: user?.isBot == true ? BorderRadius.circular(size * 0.25) : null,
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(
                url.contains('?') ? '$url&s=$px' : '$url?s=$px',
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: px,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class StateBadge extends StatelessWidget {
  const StateBadge(this.state, {super.key, this.dense = false});

  final PrState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = prStateStyle(state, Theme.of(context).colorScheme);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 3 : 6),
      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: dense ? 14 : 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            s.label,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 13),
          ),
        ],
      ),
    );
  }
}

class StateIcon extends StatelessWidget {
  const StateIcon(this.state, {super.key, this.size = 20});

  final PrState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = prStateStyle(state, Theme.of(context).colorScheme);
    return Tooltip(
      message: s.label,
      child: Icon(s.icon, color: s.color, size: size),
    );
  }
}

class LabelChip extends StatelessWidget {
  const LabelChip(this.label, {super.key});

  final GhLabel label;

  @override
  Widget build(BuildContext context) {
    final c = Color(label.color);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark
        ? Color.lerp(c, Colors.white, 0.35)!
        : (c.computeLuminance() > 0.6 ? Color.lerp(c, Colors.black, 0.6)! : c);
    return Tooltip(
      message: label.description ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: dark ? 0.2 : 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Text(
          label.name,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }
}

/// `+12 −3` with GitHub's colors.
class ChangeCounts extends StatelessWidget {
  const ChangeCounts({super.key, required this.additions, required this.deletions, this.fontSize = 12});

  final int additions;
  final int deletions;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final d = DiffTheme.of(context);
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+${formatCount(additions)}',
            style: style.copyWith(color: d.addFg),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '−${formatCount(deletions)}',
            style: style.copyWith(color: d.delFg),
          ),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// Five-block bar showing the add/delete ratio, as on GitHub.
class DiffStatBar extends StatelessWidget {
  const DiffStatBar({super.key, required this.additions, required this.deletions});

  final int additions;
  final int deletions;

  @override
  Widget build(BuildContext context) {
    final d = DiffTheme.of(context);
    final total = additions + deletions;
    final adds = total == 0 ? 0 : (additions * 5 / total).round();
    final dels = total == 0 ? 0 : (5 - adds).clamp(0, 5);
    final empty = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(left: 1.5),
            decoration: BoxDecoration(
              color: i < adds ? d.addFg : (i < adds + dels ? d.delFg : empty),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
      ],
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.icon = Icons.cloud_off_rounded});

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message, this.progress});

  final String? message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(4)),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Centers [child] and caps its width, for readable text on wide screens.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 920});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
