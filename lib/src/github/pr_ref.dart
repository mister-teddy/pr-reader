/// Identifies a pull request on GitHub.
class PrRef {
  const PrRef(this.owner, this.repo, this.number);

  final String owner;
  final String repo;
  final int number;

  String get slug => '$owner/$repo';
  String get key => '$owner/$repo#$number';
  String get webUrl => 'https://github.com/$owner/$repo/pull/$number';
  String get routePath => '/$owner/$repo/pull/$number';

  static final _name = r'[A-Za-z0-9_.-]+';
  static final _urlRe = RegExp(
    '^(?:https?://)?(?:www\\.)?github\\.com/($_name)/($_name)/pulls?/(\\d+)(?:[/?#].*)?\$',
  );
  static final _apiRe = RegExp('^(?:https?://)?api\\.github\\.com/repos/($_name)/($_name)/pulls/(\\d+)');
  static final _shortRe = RegExp('^($_name)/($_name)(?:#|/pulls?/|\\s+#?)(\\d+)\$');

  /// Parses inputs like `https://github.com/o/r/pull/1/files`, `o/r#1`,
  /// `o/r/pull/1` or an API URL. Returns null when nothing matches.
  static PrRef? tryParse(String input) {
    final s = input.trim();
    for (final re in [_urlRe, _apiRe, _shortRe]) {
      final m = re.firstMatch(s);
      if (m != null) {
        final n = int.tryParse(m.group(3)!);
        if (n == null || n <= 0) return null;
        return PrRef(m.group(1)!, _stripGit(m.group(2)!), n);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PrRef &&
      other.owner.toLowerCase() == owner.toLowerCase() &&
      other.repo.toLowerCase() == repo.toLowerCase() &&
      other.number == number;

  @override
  int get hashCode => Object.hash(owner.toLowerCase(), repo.toLowerCase(), number);

  @override
  String toString() => key;
}

/// Identifies a repository on GitHub.
class RepoRef {
  const RepoRef(this.owner, this.repo);

  final String owner;
  final String repo;

  String get slug => '$owner/$repo';
  String get routePath => '/$owner/$repo';
  String get webUrl => 'https://github.com/$owner/$repo';

  static final _urlRe = RegExp(
    r'^(?:https?://)?(?:www\.)?github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?(?:pulls/?)?(?:[?#].*)?$',
  );
  static final _shortRe = RegExp(r'^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$');

  static RepoRef? tryParse(String input) {
    final s = input.trim();
    final m = _urlRe.firstMatch(s) ?? _shortRe.firstMatch(s);
    if (m == null) return null;
    return RepoRef(m.group(1)!, _stripGit(m.group(2)!));
  }
}

String _stripGit(String repo) => repo.endsWith('.git') ? repo.substring(0, repo.length - 4) : repo;
