import '../github/pr_ref.dart';

/// The app's URL schemes, registered on macOS, iOS and Android.
const kAppSchemes = {'pr', 'reader'};

final _tabRe = RegExp(r'/pulls?/\d+/(files|changes|commits|file)\b');

/// The app route for a pasted link or reference, keeping the tab it points
/// at: `.../pull/1/changes` and `.../pull/1/files` open the Files tab, and
/// `.../pull/1/file?path=lib/a.dart` that single file.
String? routeForText(String input) {
  final pr = PrRef.tryParse(input);
  if (pr != null) {
    final path = Uri.tryParse(input)?.queryParameters['path'];
    return switch (_tabRe.firstMatch(input)?.group(1)) {
      'files' || 'changes' => '${pr.routePath}/files',
      'commits' => '${pr.routePath}/commits',
      'file' when path != null => '${pr.routePath}/file?path=${Uri.encodeQueryComponent(path)}',
      _ => pr.routePath,
    };
  }
  return RepoRef.tryParse(input)?.routePath;
}

/// The app route for a link the OS opened the app with. Accepts GitHub URLs
/// and these `pr:` forms (`reader:` works the same):
///
///   pr://github.com/owner/repo/pull/1/changes
///   pr://owner/repo/pull/1
///   pr://open?url=https%3A%2F%2Fgithub.com%2Fowner%2Frepo%2Fpull%2F1
///   pr://github.com/owner/repo/pull/1/file?path=lib/a.dart
String? routeForLink(Uri uri) {
  if (!kAppSchemes.contains(uri.scheme)) return routeForText(uri.toString());
  final url = uri.queryParameters['url'];
  if (url != null) return routeForText(url);
  final host = uri.host;
  final github = host.isEmpty || host == 'github.com' || host == 'www.github.com';
  final path = uri.queryParameters['path'];
  final query = path == null ? '' : '?path=${Uri.encodeQueryComponent(path)}';
  return routeForText(github ? 'github.com${uri.path}$query' : 'github.com/$host${uri.path}$query');
}
