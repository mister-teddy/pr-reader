import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'pr_ref.dart';

class GitHubException implements Exception {
  GitHubException(this.statusCode, this.message, {this.resetAt});

  final int statusCode;
  final String message;
  final DateTime? resetAt;

  bool get isRateLimited => (statusCode == 403 || statusCode == 429) && resetAt != null;
  bool get isNotFound => statusCode == 404;
  bool get isUnauthorized => statusCode == 401;
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => 'GitHubException($statusCode): $message';
}

/// Thin REST client for the parts of the GitHub API the reader needs.
class GitHubClient {
  GitHubClient({http.Client? httpClient, this.token, this.onRateLimit}) : _http = httpClient ?? http.Client();

  static const apiBase = 'https://api.github.com';

  final http.Client _http;
  String? token;
  void Function(RateLimitInfo info)? onRateLimit;
  RateLimitInfo? rateLimit;

  Map<String, String> _headers(String accept) => {
    'Accept': accept,
    if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Uri uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse(path.startsWith('http') ? path : '$apiBase$path');
    return query == null ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  Future<http.Response> _send(Uri u, {String accept = 'application/vnd.github+json', String? body}) async {
    http.Response res;
    try {
      final request = body == null
          ? _http.get(u, headers: _headers(accept))
          : _http.post(u, headers: {..._headers(accept), 'Content-Type': 'application/json'}, body: body);
      res = await request.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw GitHubException(0, 'The request to GitHub timed out.');
    } catch (e) {
      throw GitHubException(0, 'Could not reach GitHub. Check your connection.');
    }
    _readRateLimit(res);
    if (res.statusCode >= 400) throw _error(res);
    return res;
  }

  void _readRateLimit(http.Response res) {
    final limit = int.tryParse(res.headers['x-ratelimit-limit'] ?? '');
    final remaining = int.tryParse(res.headers['x-ratelimit-remaining'] ?? '');
    final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '');
    if (limit == null || remaining == null || reset == null) return;
    // Search has its own, smaller bucket; keep reporting the core one.
    if (res.headers['x-ratelimit-resource'] == 'search') return;
    final info = RateLimitInfo(
      limit: limit,
      remaining: remaining,
      resetAt: DateTime.fromMillisecondsSinceEpoch(reset * 1000),
    );
    rateLimit = info;
    onRateLimit?.call(info);
  }

  GitHubException _error(http.Response res) {
    var message = 'GitHub returned ${res.statusCode}.';
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      message = j['message'] as String? ?? message;
    } catch (_) {}
    DateTime? resetAt;
    final remaining = res.headers['x-ratelimit-remaining'];
    final reset = int.tryParse(res.headers['x-ratelimit-reset'] ?? '');
    final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
    if ((res.statusCode == 403 || res.statusCode == 429) && (remaining == '0' || retryAfter != null)) {
      resetAt = retryAfter != null
          ? DateTime.now().add(Duration(seconds: retryAfter))
          : DateTime.fromMillisecondsSinceEpoch((reset ?? 0) * 1000);
    }
    return GitHubException(res.statusCode, message, resetAt: resetAt);
  }

  Future<dynamic> postJson(String path, Map<String, Object?> body) async {
    final res = await _send(uri(path), body: jsonEncode(body));
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  Future<dynamic> getJson(String path, {Map<String, String>? query}) async {
    final res = await _send(uri(path, query));
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  Future<Uint8List> getBytes(String path, {Map<String, String>? query, String? accept}) async {
    final res = await _send(uri(path, query), accept: accept ?? 'application/vnd.github+json');
    return res.bodyBytes;
  }

  /// Fetches every page of a list endpoint by following `Link: rel="next"`.
  Future<List<dynamic>> getAllPages(String path, {Map<String, String>? query, int maxPages = 30}) async {
    final out = <dynamic>[];
    Uri? next = uri(path, {'per_page': '100', ...?query});
    var pages = 0;
    while (next != null && pages < maxPages) {
      final res = await _send(next);
      out.addAll(jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true)) as List);
      next = _nextLink(res.headers['link']);
      pages++;
    }
    return out;
  }

  static final _linkRe = RegExp(r'<([^>]+)>;\s*rel="next"');

  Uri? _nextLink(String? header) {
    if (header == null) return null;
    final m = _linkRe.firstMatch(header);
    return m == null ? null : Uri.parse(m.group(1)!);
  }

  // ---- Endpoints --------------------------------------------------------

  String _pr(PrRef r) => '/repos/${r.owner}/${r.repo}/pulls/${r.number}';

  Future<PullRequest> getPull(PrRef ref) async => PullRequest.fromJson(ref, await getJson(_pr(ref)) as Json);

  /// Raw JSON bytes of one page (100 files) of the PR's changed files.
  Future<Uint8List> getFilesPage(PrRef ref, int page) =>
      getBytes('${_pr(ref)}/files', query: {'per_page': '100', 'page': '$page'});

  Future<List<ReviewComment>> getReviewComments(PrRef ref) async => [
    for (final j in await getAllPages('${_pr(ref)}/comments')) ReviewComment.fromJson(j as Json),
  ];

  Future<List<Review>> getReviews(PrRef ref) async => [
    for (final j in await getAllPages('${_pr(ref)}/reviews')) Review.fromJson(j as Json),
  ];

  Future<List<IssueComment>> getIssueComments(PrRef ref) async => [
    for (final j in await getAllPages('/repos/${ref.owner}/${ref.repo}/issues/${ref.number}/comments'))
      IssueComment.fromJson(j as Json),
  ];

  /// GitHub returns at most 250 commits for a PR.
  Future<List<Commit>> getCommits(PrRef ref) async => [
    for (final j in await getAllPages('${_pr(ref)}/commits', maxPages: 3)) Commit.fromJson(j as Json),
  ];

  Future<CheckSummary> getChecks(PrRef ref, String sha) async {
    final j = await getJson(
      '/repos/${ref.owner}/${ref.repo}/commits/$sha/check-runs',
      query: {'per_page': '100'},
    );
    return CheckSummary.fromCheckRuns(j as Json);
  }

  /// The merge base of [base] and [head], which is what the PR diff is
  /// computed against. Page 2 with one commit per page keeps the response
  /// small, since files are only included on the first page.
  Future<String> getMergeBase(PrRef ref, String base, String head) async {
    final j = await getJson(
      '/repos/${ref.owner}/${ref.repo}/compare/$base...$head',
      query: {'per_page': '1', 'page': '2'},
    );
    return ((j as Json)['merge_base_commit'] as Json)['sha'] as String;
  }

  /// Raw file contents at [sha], or null when the file does not exist there.
  Future<String?> getRawFile(PrRef ref, String path, String sha) async {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    try {
      final bytes = await getBytes(
        '/repos/${ref.owner}/${ref.repo}/contents/$encoded',
        query: {'ref': sha},
        accept: 'application/vnd.github.raw',
      );
      return utf8.decode(bytes, allowMalformed: true);
    } on GitHubException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  Future<GhUser> getViewer() async => GhUser.fromJson(await getJson('/user'));

  Future<List<PullSummary>> searchPulls(String query, {int perPage = 30}) async {
    final j = await getJson(
      '/search/issues',
      query: {'q': 'is:pr $query', 'sort': 'updated', 'order': 'desc', 'per_page': '$perPage'},
    );
    return [
      for (final item in ((j as Json)['items'] as List? ?? const []))
        ?PullSummary.fromSearchItem(item as Json),
    ];
  }

  Future<List<PullSummary>> listRepoPulls(RepoRef repo, {String state = 'open', int page = 1}) async {
    final j = await getJson(
      '/repos/${repo.owner}/${repo.repo}/pulls',
      query: {
        'state': state,
        'per_page': '30',
        'page': '$page',
        'sort': state == 'open' ? 'created' : 'updated',
        'direction': 'desc',
      },
    );
    return [for (final p in (j as List)) PullSummary.fromPullJson(repo.owner, repo.repo, p as Json)];
  }

  // ---- Comments ------------------------------------------------------------

  /// A comment on the PR's conversation.
  Future<IssueComment> createIssueComment(PrRef ref, String body) async => IssueComment.fromJson(
    await postJson('/repos/${ref.owner}/${ref.repo}/issues/${ref.number}/comments', {'body': body}) as Json,
  );

  /// A reply in the review thread that [commentId] belongs to.
  Future<ReviewComment> replyToReviewComment(PrRef ref, int commentId, String body) async =>
      ReviewComment.fromJson(
        await postJson('${_pr(ref)}/comments/$commentId/replies', {'body': body}) as Json,
      );

  /// A new comment on one line of the diff, published right away (not part
  /// of a pending review).
  Future<ReviewComment> createLineComment(
    PrRef ref, {
    required String commitId,
    required String path,
    required int line,
    required DiffSide side,
    required String body,
  }) async => ReviewComment.fromJson(
    await postJson('${_pr(ref)}/comments', {
          'body': body,
          'commit_id': commitId,
          'path': path,
          'line': line,
          'side': side == DiffSide.left ? 'LEFT' : 'RIGHT',
        })
        as Json,
  );

  // ---- GraphQL (viewed state) ------------------------------------------------

  /// Runs a GraphQL request. GraphQL errors come back with HTTP 200, so they
  /// are turned into [GitHubException]s here; permission problems map to 403.
  Future<Json> graphql(String query, Map<String, Object?> variables) async {
    final res = await _send(uri('/graphql'), body: jsonEncode({'query': query, 'variables': variables}));
    final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true)) as Json;
    final errors = j['errors'] as List?;
    if (errors != null && errors.isNotEmpty) {
      final e = errors.first as Json;
      final type = e['type'] as String?;
      final message = e['message'] as String? ?? 'GraphQL error';
      final status = switch (type) {
        'NOT_FOUND' => 404,
        'FORBIDDEN' || 'INSUFFICIENT_SCOPES' => 403,
        _ => message.contains('not accessible') ? 403 : 422,
      };
      throw GitHubException(status, message);
    }
    return j['data'] as Json;
  }

  static const _viewedQuery = r'''
query($owner: String!, $repo: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      id
      files(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes { path viewerViewedState }
      }
    }
  }
}''';

  /// The PR's GraphQL node id and the viewer's "Viewed" state of each file
  /// (`VIEWED`, `UNVIEWED`, or `DISMISSED` when the file changed since).
  Future<({String prId, Map<String, String> states})> getViewedStates(PrRef ref) async {
    final states = <String, String>{};
    String? after;
    var prId = '';
    for (var page = 0; page < 40; page++) {
      final data = await graphql(_viewedQuery, {
        'owner': ref.owner,
        'repo': ref.repo,
        'number': ref.number,
        'after': after,
      });
      final pr = (data['repository'] as Json?)?['pullRequest'] as Json?;
      if (pr == null) throw GitHubException(404, 'Pull request not found');
      prId = pr['id'] as String;
      final files = pr['files'] as Json;
      for (final n in (files['nodes'] as List).cast<Json>()) {
        states[n['path'] as String] = n['viewerViewedState'] as String? ?? 'UNVIEWED';
      }
      final info = files['pageInfo'] as Json;
      if (info['hasNextPage'] != true) break;
      after = info['endCursor'] as String?;
    }
    return (prId: prId, states: states);
  }

  /// Marks [paths] as viewed (or not) on GitHub, batching many files into
  /// each request.
  Future<void> setViewed(String prId, List<String> paths, bool viewed) async {
    final op = viewed ? 'markFileAsViewed' : 'unmarkFileAsViewed';
    for (var start = 0; start < paths.length; start += 50) {
      final chunk = paths.sublist(start, (start + 50).clamp(0, paths.length));
      final params = [for (var i = 0; i < chunk.length; i++) '\$p$i: String!'].join(', ');
      final fields = [
        for (var i = 0; i < chunk.length; i++)
          'f$i: $op(input: {pullRequestId: \$pr, path: \$p$i}) { clientMutationId }',
      ].join('\n');
      await graphql('mutation(\$pr: ID!, $params) {\n$fields\n}', {
        'pr': prId,
        for (var i = 0; i < chunk.length; i++) 'p$i': chunk[i],
      });
    }
  }

  void close() => _http.close();
}
