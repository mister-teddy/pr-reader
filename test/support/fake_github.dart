import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A deterministic, large synthetic pull request served through a mock HTTP
/// client: ~260 files and 25k+ changed lines across several languages, plus
/// a generated lockfile, a file too large for GitHub to return a patch for,
/// a binary file, a pure rename, review threads, reviews and commits.
class FakeGitHub {
  FakeGitHub({this.fileCount = 260, int seed = 7}) : _rnd = math.Random(seed) {
    _buildFiles();
  }

  static const owner = 'acme';
  static const repo = 'engine';
  static const number = 4242;
  static const headSha = 'f00dfacecafebeef0000000000000000000000aa';
  static const baseSha = 'ba5eba11ba5eba11000000000000000000000bb';

  final int fileCount;
  final math.Random _rnd;
  final List<Map<String, dynamic>> files = [];
  int additions = 0;
  int deletions = 0;
  int requests = 0;

  /// "Viewed" state per path as GitHub would report it over GraphQL.
  final Map<String, String> viewedOnGitHub = {};

  /// False simulates a token that can read the PR but not mark files.
  bool canMarkViewed = true;
  final List<String> viewedMutations = [];

  /// False simulates a token without permission to comment.
  bool canComment = true;

  /// Bodies of everything posted, as `kind:body`.
  final List<String> posted = [];
  int _nextId = 1000;

  static const _words = [
    'render',
    'layout',
    'paint',
    'frame',
    'buffer',
    'texture',
    'surface',
    'pipeline',
    'shader',
    'command',
    'queue',
    'device',
    'context',
    'state',
    'cache',
    'handle',
    'stream',
    'config',
  ];
  static const _types = ['Renderer', 'FrameBuffer', 'Pipeline', 'ShaderCache', 'Surface', 'CommandQueue'];

  String _w() => _words[_rnd.nextInt(_words.length)];
  String _t() => _types[_rnd.nextInt(_types.length)];
  String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  String _line(String ext, int depth) {
    final ind = '  ' * depth;
    final r = _rnd.nextInt(10);
    switch (ext) {
      case 'dart':
        return switch (r) {
          0 => "${ind}final ${_w()}${_cap(_w())} = await ${_w()}.${_w()}(${_rnd.nextInt(512)});",
          1 => '$ind// ${_cap(_w())} the ${_w()} before the next ${_w()} is scheduled.',
          2 => '${ind}if (${_w()}.is${_cap(_w())} && ${_w()} != null) {',
          3 =>
            '${ind}return ${_t()}(${_w()}: ${_w()}, ${_w()}: const Duration(milliseconds: ${_rnd.nextInt(900)}));',
          4 => "${ind}debugPrint('${_w()} ${_w()} took \${stopwatch.elapsedMilliseconds}ms');",
          5 => '$ind@override',
          6 => '${ind}void ${_w()}${_cap(_w())}(${_t()} ${_w()}) {',
          7 => '$ind}',
          8 => '${ind}_${_w()}s.add(${_t()}.from${_cap(_w())}(${_w()}));',
          _ => '${ind}late final ${_t()} _${_w()} = ${_t()}(); // TODO(${_w()}): pool these',
        };
      case 'ts':
        return switch (r) {
          0 => "${ind}const ${_w()}${_cap(_w())} = await ${_w()}.${_w()}(${_rnd.nextInt(512)});",
          1 => '$ind// ${_cap(_w())} ${_w()} when the ${_w()} changes.',
          2 => '${ind}if (!${_w()} || ${_w()}.length === ${_rnd.nextInt(9)}) {',
          3 => '${ind}return { ${_w()}, ${_w()}: `\${${_w()}}-${_w()}` };',
          4 => '${ind}export function ${_w()}${_cap(_w())}(${_w()}: ${_t()}): Promise<void> {',
          5 => '$ind}',
          6 => "${ind}import { ${_t()} } from './${_w()}';",
          _ => '$ind${_w()}.on(\'${_w()}\', (e) => ${_w()}(e.detail));',
        };
      case 'go':
        return switch (r) {
          0 => '$ind${_w()}, err := ${_w()}.${_cap(_w())}(ctx, ${_rnd.nextInt(64)})',
          1 => '${ind}if err != nil {',
          2 => '$ind\treturn nil, fmt.Errorf("${_w()}: %w", err)',
          3 => '$ind}',
          4 => '$ind// ${_cap(_w())} returns the ${_w()} for the given ${_w()}.',
          _ => '${ind}func (r *${_t()}) ${_cap(_w())}(${_w()} string) error {',
        };
      default:
        return switch (r) {
          0 => '${ind}def ${_w()}_${_w()}(self, ${_w()}=${_rnd.nextInt(9)}):',
          1 => '$ind# ${_cap(_w())} the ${_w()}.',
          2 => '${ind}return self._${_w()}[${_rnd.nextInt(32)}]',
          _ => "$ind${_w()} = {'${_w()}': ${_rnd.nextInt(100)}, '${_w()}': None}",
        };
    }
  }

  /// Builds a patch with [hunks] hunks of roughly [size] lines each.
  String _patch(String ext, {int hunks = 2, int size = 40, bool onlyAdds = false}) {
    final buf = StringBuffer();
    var oldLine = 1 + _rnd.nextInt(40), newLine = oldLine;
    for (var h = 0; h < hunks; h++) {
      final lines = <String>[];
      var o = 0, n = 0;
      for (var i = 0; i < size; i++) {
        final depth = 1 + _rnd.nextInt(3);
        final roll = onlyAdds ? 1 : _rnd.nextInt(6);
        final text = _line(ext, depth);
        if (roll == 0 || roll == 2) {
          lines.add(' $text');
          o++;
          n++;
        } else if (roll == 1 || roll == 3) {
          lines.add('+$text');
          n++;
          additions++;
        } else if (roll == 4) {
          lines.add('-$text');
          o++;
          deletions++;
        } else {
          // A modified line: delete then add something similar.
          lines.add('-$text');
          lines.add('+${text.replaceFirst(RegExp(r'\d+'), '${_rnd.nextInt(999)}')}');
          o++;
          n++;
          additions++;
          deletions++;
        }
      }
      final section = ext == 'dart' ? ' class ${_t()} extends State<${_t()}> {' : '';
      buf.writeln('@@ -${onlyAdds ? 0 : oldLine},$o +$newLine,$n @@$section');
      for (final l in lines) {
        buf.writeln(l);
      }
      oldLine += o + 20 + _rnd.nextInt(80);
      newLine += n + 20 + _rnd.nextInt(80);
    }
    return buf.toString().trimRight();
  }

  void _add(String path, String status, String? patch, {int adds = 0, int dels = 0, String? previous}) {
    var a = adds, d = dels;
    if (patch != null) {
      a = 0;
      d = 0;
      for (final l in patch.split('\n')) {
        if (l.startsWith('+')) a++;
        if (l.startsWith('-')) d++;
      }
    }
    files.add({
      'sha': 'blob${files.length}',
      'filename': path,
      'status': status,
      'additions': a,
      'deletions': d,
      'changes': a + d,
      'patch': ?patch,
      'previous_filename': ?previous,
    });
  }

  void _buildFiles() {
    const dirs = [
      'engine/src/renderer',
      'engine/src/renderer/backend/metal',
      'engine/src/renderer/backend/vulkan',
      'engine/src/compositor',
      'lib/src/widgets',
      'lib/src/rendering',
      'tools/bench',
      'web/src/canvas',
      'services/api',
    ];
    final exts = {'engine': 'go', 'lib': 'dart', 'tools': 'py', 'web': 'ts', 'services': 'go'};
    final paths = <String>[];
    for (var i = 0; i < fileCount; i++) {
      final dir = dirs[i % dirs.length];
      final ext = exts[dir.split('/').first]!;
      paths.add('$dir/${_w()}_${_w()}_$i.$ext');
    }
    paths.add('package-lock.json');
    paths.add('engine/src/renderer/shader_tables.go');
    paths.add('assets/images/logo.png');
    paths.add('docs/renderer_old.md');
    paths.sort();
    for (final p in paths) {
      if (p == 'package-lock.json') {
        final lines = [
          for (var i = 0; i < 5200; i++)
            '+    "node_modules/${_w()}-${_w()}-$i": { "version": "1.${_rnd.nextInt(40)}.${_rnd.nextInt(9)}" },',
        ];
        _add(p, 'modified', '@@ -1,0 +1,${lines.length} @@\n${lines.join('\n')}');
      } else if (p.endsWith('shader_tables.go')) {
        _add(p, 'modified', null, adds: 4100, dels: 3900);
      } else if (p.endsWith('.png')) {
        _add(p, 'added', null);
      } else if (p == 'docs/renderer_old.md') {
        _add('docs/renderer.md', 'renamed', null, previous: p);
      } else {
        final ext = p.split('.').last;
        final big = _rnd.nextInt(14) == 0;
        final added = _rnd.nextInt(9) == 0;
        _add(
          p,
          added ? 'added' : 'modified',
          _patch(
            ext,
            hunks: big ? 6 : 1 + _rnd.nextInt(3),
            size: big ? 110 : 10 + _rnd.nextInt(45),
            onlyAdds: added,
          ),
        );
      }
    }
    additions = files.fold(0, (n, f) => n + (f['additions'] as int));
    deletions = files.fold(0, (n, f) => n + (f['deletions'] as int));
  }

  String get firstCodePath =>
      files.firstWhere((f) => (f['filename'] as String).endsWith('.go'))['filename'] as String;

  int _firstAddedLine(String path) {
    final patch = files.firstWhere((f) => f['filename'] == path)['patch'] as String;
    final m = RegExp(r'\+(\d+),').firstMatch(patch)!;
    var n = int.parse(m.group(1)!);
    for (final l in patch.split('\n').skip(1)) {
      if (l.startsWith('+')) return n;
      if (!l.startsWith('-')) n++;
    }
    return n;
  }

  Map<String, dynamic> _graphql(Map<String, dynamic> body) {
    final query = body['query'] as String;
    final vars = (body['variables'] as Map).cast<String, dynamic>();
    if (query.startsWith('mutation')) {
      if (!canMarkViewed) {
        return {
          'errors': [
            {'type': 'FORBIDDEN', 'message': 'Resource not accessible by personal access token'},
          ],
        };
      }
      final viewed = query.contains('markFileAsViewed(') && !query.contains('unmarkFileAsViewed');
      for (final e in vars.entries) {
        if (e.key == 'pr') continue;
        final p = e.value as String;
        viewedOnGitHub[p] = viewed ? 'VIEWED' : 'UNVIEWED';
        viewedMutations.add('${viewed ? '+' : '-'}$p');
      }
      return {'data': {}};
    }
    final start = int.tryParse(vars['after'] as String? ?? '') ?? 0;
    final page = files.skip(start).take(100).toList();
    final next = start + page.length;
    return {
      'data': {
        'repository': {
          'pullRequest': {
            'id': 'PR_node_4242',
            'files': {
              'pageInfo': {'hasNextPage': next < files.length, 'endCursor': '$next'},
              'nodes': [
                for (final f in page)
                  {'path': f['filename'], 'viewerViewedState': viewedOnGitHub[f['filename']] ?? 'UNVIEWED'},
              ],
            },
          },
        },
      },
    };
  }

  Map<String, dynamic> _user(String login, int id) => {
    'login': login,
    'avatar_url': 'https://avatars.example/u/$id',
    'html_url': 'https://github.com/$login',
    'type': 'User',
  };

  Map<String, dynamic> get pull => {
    'number': number,
    'title': 'Move the renderer to an explicit command-queue pipeline',
    'body': '''
## Summary

This replaces the implicit draw-call batching with an explicit **command queue** per frame.
It removes most of the per-frame allocations and lets the Metal and Vulkan backends share
scheduling code.

<details><summary>Benchmarks</summary>

| Scene | Before | After |
|---|---|---|
| scroll_large_list | 11.8 ms | 6.1 ms |
| shader_warmup | 240 ms | 95 ms |

</details>

### Notes for reviewers
- `package-lock.json` is regenerated; no need to review it.
- `shader_tables.go` is generated by `tools/bench/gen_tables.py`.

Fixes #4100
''',
    'state': 'open',
    'draft': false,
    'merged': false,
    'user': _user('mona', 1),
    'head': {
      'ref': 'feature/command-queue',
      'label': 'mona:feature/command-queue',
      'sha': headSha,
      'repo': {'full_name': '$owner/$repo'},
    },
    'base': {
      'ref': 'main',
      'label': 'acme:main',
      'sha': baseSha,
      'repo': {'full_name': '$owner/$repo'},
    },
    'additions': additions,
    'deletions': deletions,
    'changed_files': files.length,
    'commits': 12,
    'comments': 2,
    'review_comments': 4,
    'labels': [
      {'name': 'performance', 'color': '0e8a16'},
      {'name': 'renderer', 'color': '1d76db'},
      {'name': 'needs-review', 'color': 'fbca04'},
    ],
    'requested_reviewers': [_user('hubot', 3)],
    'requested_teams': [
      {'name': 'rendering-core'},
    ],
    'assignees': [_user('mona', 1)],
    'html_url': 'https://github.com/$owner/$repo/pull/$number',
    'created_at': '2026-10-14T09:12:00Z',
    'updated_at': '2026-10-22T16:40:00Z',
    'milestone': {'title': 'v4.0'},
  };

  List<Map<String, dynamic>> get reviewComments {
    final path = firstCodePath;
    final line = _firstAddedLine(path);
    return [
      {
        'id': 1,
        'pull_request_review_id': 100,
        'user': _user('octocat', 2),
        'body': 'Should this queue be bounded? Under load we could grow without limit.',
        'path': path,
        'line': line,
        'side': 'RIGHT',
        'diff_hunk': '@@ -1,3 +1,4 @@\n context\n+added line',
        'created_at': '2026-10-20T10:00:00Z',
        'html_url': 'https://github.com/$owner/$repo/pull/$number#discussion_r1',
      },
      {
        'id': 2,
        'pull_request_review_id': 101,
        'in_reply_to_id': 1,
        'user': _user('mona', 1),
        'body': 'Good catch. It is bounded by the frame budget, but I will add an explicit cap.',
        'path': path,
        'line': line,
        'side': 'RIGHT',
        'diff_hunk': '@@ -1,3 +1,4 @@\n context\n+added line',
        'created_at': '2026-10-20T11:30:00Z',
        'html_url': 'https://github.com/$owner/$repo/pull/$number#discussion_r2',
      },
    ];
  }

  List<Map<String, dynamic>> get reviews => [
    {
      'id': 100,
      'user': _user('octocat', 2),
      'body': 'Looks great overall. One question about back-pressure.',
      'state': 'CHANGES_REQUESTED',
      'submitted_at': '2026-10-20T10:00:00Z',
    },
    {
      'id': 102,
      'user': _user('lisa', 4),
      'body': 'LGTM 🚀',
      'state': 'APPROVED',
      'submitted_at': '2026-10-21T08:00:00Z',
    },
  ];

  List<Map<String, dynamic>> get issueComments => [
    {
      'id': 9,
      'user': _user('lisa', 4),
      'body': 'Benchmarks look fantastic. Can we also run `scroll_large_list` on the low-end device lab?',
      'created_at': '2026-10-15T09:00:00Z',
      'author_association': 'MEMBER',
    },
  ];

  List<Map<String, dynamic>> get commits => [
    for (var i = 0; i < 12; i++)
      {
        'sha': '${i}abc${'0' * 34}',
        'commit': {
          'message': '${_cap(_w())} ${_w()} ${_w()} for the command queue\n\nDetails about change $i.',
          'author': {'name': 'Mona', 'date': '2026-10-${14 + i ~/ 3}T1$i:00:00Z'},
        },
        'author': _user('mona', 1),
        'html_url': 'https://github.com/$owner/$repo/commit/$i',
      },
  ];

  late final http.Client client = MockClient((req) async {
    requests++;
    final path = req.url.path;
    final q = req.url.queryParameters;
    final base = '/repos/$owner/$repo';
    final headers = {
      'content-type': 'application/json; charset=utf-8',
      'x-ratelimit-limit': '5000',
      'x-ratelimit-remaining': '${5000 - requests}',
      'x-ratelimit-reset':
          '${DateTime.now().add(const Duration(minutes: 40)).millisecondsSinceEpoch ~/ 1000}',
    };
    http.Response json(Object body) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: headers);
    if (req.method == 'POST' && path != '/graphql') {
      if (!canComment) {
        return http.Response(
          '{"message":"Resource not accessible by personal access token"}',
          403,
          headers: headers,
        );
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final now = DateTime.now().toUtc().toIso8601String();
      final id = _nextId++;
      if (path == '$base/issues/$number/comments') {
        posted.add('issue:${body['body']}');
        return json({'id': id, 'user': _user('mona', 1), 'body': body['body'], 'created_at': now});
      }
      final reply = RegExp(r'/pulls/\d+/comments/(\d+)/replies$').firstMatch(path);
      if (reply != null) {
        final root = reviewComments.firstWhere((c) => c['id'] == int.parse(reply.group(1)!));
        posted.add('reply:${body['body']}');
        return json({
          ...root,
          'id': id,
          'in_reply_to_id': root['id'],
          'user': _user('mona', 1),
          'body': body['body'],
          'created_at': now,
        });
      }
      if (path == '$base/pulls/$number/comments') {
        posted.add('line:${body['path']}:${body['line']}:${body['side']}:${body['body']}');
        return json({
          'id': id,
          'user': _user('mona', 1),
          'body': body['body'],
          'path': body['path'],
          'line': body['line'],
          'side': body['side'],
          'diff_hunk': '',
          'created_at': now,
        });
      }
    }
    if (path == '$base/pulls/$number') return json(pull);
    if (path == '$base/pulls/$number/files') {
      final page = int.parse(q['page'] ?? '1');
      final per = int.parse(q['per_page'] ?? '30');
      final start = (page - 1) * per;
      return json(files.sublist(math.min(start, files.length), math.min(start + per, files.length)));
    }
    if (path == '$base/pulls/$number/comments') return json(reviewComments);
    if (path == '$base/pulls/$number/reviews') return json(reviews);
    if (path == '$base/issues/$number/comments') return json(issueComments);
    if (path == '$base/pulls/$number/commits') return json(commits);
    if (path.startsWith('$base/commits/')) {
      return json({
        'total_count': 14,
        'check_runs': [
          for (var i = 0; i < 12; i++) {'status': 'completed', 'conclusion': 'success'},
          {'status': 'completed', 'conclusion': 'failure'},
          {'status': 'in_progress'},
        ],
      });
    }
    if (path.startsWith('$base/compare/')) {
      return json({
        'merge_base_commit': {'sha': baseSha},
      });
    }
    if (path.startsWith('$base/contents/')) {
      final ref = q['ref'];
      final lines = [
        for (var i = 0; i < 6000; i++)
          '\t{0x${i.toRadixString(16)}, "${ref == headSha && i % 7 == 0 ? 'new_' : ''}shader_$i"},',
      ];
      return http.Response.bytes(
        utf8.encode('package tables\n\nvar Shaders = []Entry{\n${lines.join('\n')}\n}\n'),
        200,
        headers: headers,
      );
    }
    if (path == '$base/pulls') {
      return json([
        for (var i = 0; i < 12; i++)
          {
            'number': 4242 - i,
            'title': '${_cap(_w())} the ${_w()} ${_w()}',
            'user': _user('mona', 1),
            'state': 'open',
            'draft': i == 3,
            'updated_at': '2026-10-2${i % 3}T10:00:00Z',
            'labels': i.isEven
                ? [
                    {'name': 'renderer', 'color': '1d76db'},
                  ]
                : [],
          },
      ]);
    }
    if (path == '/search/issues') {
      return json({
        'items': [
          for (var i = 0; i < 4; i++)
            {
              'repository_url': 'https://api.github.com/repos/$owner/$repo',
              'number': 4242 - i,
              'title': i == 0 ? pull['title'] : '${_cap(_w())} the ${_w()} ${_w()}',
              'user': _user(i.isEven ? 'mona' : 'lisa', 1),
              'state': 'open',
              'draft': i == 2,
              'updated_at': '2026-10-22T1$i:00:00Z',
              'labels': [],
              'pull_request': {'merged_at': null},
            },
        ],
      });
    }
    if (path == '/user') return json(_user('mona', 1));
    if (path == '/graphql') return json(_graphql(jsonDecode(req.body) as Map<String, dynamic>));
    return http.Response('{"message":"Not Found"}', 404, headers: headers);
  });
}
