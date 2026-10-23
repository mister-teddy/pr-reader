import 'pr_ref.dart';

DateTime? parseDate(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

typedef Json = Map<String, dynamic>;

class GhUser {
  const GhUser({required this.login, required this.avatarUrl, this.htmlUrl, this.isBot = false});

  final String login;
  final String avatarUrl;
  final String? htmlUrl;
  final bool isBot;

  static const ghost = GhUser(login: 'ghost', avatarUrl: 'https://avatars.githubusercontent.com/u/10137?v=4');

  static GhUser fromJson(Object? json) {
    if (json is! Json) return ghost;
    return GhUser(
      login: json['login'] as String? ?? 'ghost',
      avatarUrl: json['avatar_url'] as String? ?? ghost.avatarUrl,
      htmlUrl: json['html_url'] as String?,
      isBot: json['type'] == 'Bot',
    );
  }
}

class GhLabel {
  const GhLabel({required this.name, required this.color, this.description});

  final String name;

  /// ARGB color.
  final int color;
  final String? description;

  static GhLabel fromJson(Json json) {
    final hex = json['color'] as String? ?? '888888';
    return GhLabel(
      name: json['name'] as String? ?? '',
      color: 0xFF000000 | (int.tryParse(hex, radix: 16) ?? 0x888888),
      description: json['description'] as String?,
    );
  }
}

class GhBranch {
  const GhBranch({required this.ref, required this.sha, required this.label, this.repoFullName});

  final String ref;
  final String sha;
  final String label;
  final String? repoFullName;

  static GhBranch fromJson(Object? json) {
    final j = json is Json ? json : const <String, dynamic>{};
    final repo = j['repo'];
    return GhBranch(
      ref: j['ref'] as String? ?? '',
      sha: j['sha'] as String? ?? '',
      label: j['label'] as String? ?? '',
      repoFullName: repo is Json ? repo['full_name'] as String? : null,
    );
  }
}

enum PrState { open, draft, merged, closed }

PrState _prState({required String? state, required bool draft, required bool merged}) {
  if (merged) return PrState.merged;
  if (state == 'closed') return PrState.closed;
  return draft ? PrState.draft : PrState.open;
}

class PullRequest {
  const PullRequest({
    required this.ref,
    required this.title,
    required this.body,
    required this.state,
    required this.user,
    required this.head,
    required this.base,
    required this.additions,
    required this.deletions,
    required this.changedFiles,
    required this.commits,
    required this.comments,
    required this.reviewComments,
    required this.labels,
    required this.requestedReviewers,
    required this.requestedTeams,
    required this.assignees,
    required this.htmlUrl,
    required this.createdAt,
    required this.updatedAt,
    this.mergedAt,
    this.closedAt,
    this.mergedBy,
    this.milestone,
    this.mergeableState,
  });

  final PrRef ref;
  final String title;
  final String body;
  final PrState state;
  final GhUser user;
  final GhBranch head;
  final GhBranch base;
  final int additions;
  final int deletions;
  final int changedFiles;
  final int commits;
  final int comments;
  final int reviewComments;
  final List<GhLabel> labels;
  final List<GhUser> requestedReviewers;
  final List<String> requestedTeams;
  final List<GhUser> assignees;
  final String htmlUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? mergedAt;
  final DateTime? closedAt;
  final GhUser? mergedBy;
  final String? milestone;
  final String? mergeableState;

  static PullRequest fromJson(PrRef ref, Json j) {
    return PullRequest(
      ref: ref,
      title: j['title'] as String? ?? '',
      body: j['body'] as String? ?? '',
      state: _prState(
        state: j['state'] as String?,
        draft: j['draft'] == true,
        merged: j['merged'] == true || j['merged_at'] != null,
      ),
      user: GhUser.fromJson(j['user']),
      head: GhBranch.fromJson(j['head']),
      base: GhBranch.fromJson(j['base']),
      additions: j['additions'] as int? ?? 0,
      deletions: j['deletions'] as int? ?? 0,
      changedFiles: j['changed_files'] as int? ?? 0,
      commits: j['commits'] as int? ?? 0,
      comments: j['comments'] as int? ?? 0,
      reviewComments: j['review_comments'] as int? ?? 0,
      labels: [for (final l in (j['labels'] as List? ?? const [])) GhLabel.fromJson(l as Json)],
      requestedReviewers: [
        for (final u in (j['requested_reviewers'] as List? ?? const [])) GhUser.fromJson(u),
      ],
      requestedTeams: [
        for (final t in (j['requested_teams'] as List? ?? const [])) (t as Json)['name'] as String? ?? '',
      ],
      assignees: [for (final u in (j['assignees'] as List? ?? const [])) GhUser.fromJson(u)],
      htmlUrl: j['html_url'] as String? ?? ref.webUrl,
      createdAt: parseDate(j['created_at']),
      updatedAt: parseDate(j['updated_at']),
      mergedAt: parseDate(j['merged_at']),
      closedAt: parseDate(j['closed_at']),
      mergedBy: j['merged_by'] == null ? null : GhUser.fromJson(j['merged_by']),
      milestone: (j['milestone'] as Json?)?['title'] as String?,
      mergeableState: j['mergeable_state'] as String?,
    );
  }
}

/// A lightweight pull request entry used in lists and search results.
class PullSummary {
  const PullSummary({
    required this.ref,
    required this.title,
    required this.user,
    required this.state,
    required this.updatedAt,
    required this.labels,
    this.comments,
  });

  final PrRef ref;
  final String title;
  final GhUser user;
  final PrState state;
  final DateTime? updatedAt;
  final List<GhLabel> labels;
  final int? comments;

  static final _repoUrlRe = RegExp(r'/repos/([^/]+)/([^/]+)$');

  /// From `/search/issues` results.
  static PullSummary? fromSearchItem(Json j) {
    final m = _repoUrlRe.firstMatch(j['repository_url'] as String? ?? '');
    if (m == null) return null;
    final pr = j['pull_request'] as Json?;
    return PullSummary(
      ref: PrRef(m.group(1)!, m.group(2)!, j['number'] as int),
      title: j['title'] as String? ?? '',
      user: GhUser.fromJson(j['user']),
      state: _prState(
        state: j['state'] as String?,
        draft: j['draft'] == true,
        merged: pr?['merged_at'] != null,
      ),
      updatedAt: parseDate(j['updated_at']),
      labels: [for (final l in (j['labels'] as List? ?? const [])) GhLabel.fromJson(l as Json)],
      comments: j['comments'] as int?,
    );
  }

  /// From `/repos/{o}/{r}/pulls` results.
  static PullSummary fromPullJson(String owner, String repo, Json j) {
    return PullSummary(
      ref: PrRef(owner, repo, j['number'] as int),
      title: j['title'] as String? ?? '',
      user: GhUser.fromJson(j['user']),
      state: _prState(
        state: j['state'] as String?,
        draft: j['draft'] == true,
        merged: j['merged_at'] != null,
      ),
      updatedAt: parseDate(j['updated_at']),
      labels: [for (final l in (j['labels'] as List? ?? const [])) GhLabel.fromJson(l as Json)],
    );
  }
}

class IssueComment {
  const IssueComment({
    required this.id,
    required this.user,
    required this.body,
    required this.createdAt,
    required this.htmlUrl,
    this.authorAssociation,
  });

  final int id;
  final GhUser user;
  final String body;
  final DateTime? createdAt;
  final String htmlUrl;
  final String? authorAssociation;

  static IssueComment fromJson(Json j) => IssueComment(
    id: j['id'] as int,
    user: GhUser.fromJson(j['user']),
    body: j['body'] as String? ?? '',
    createdAt: parseDate(j['created_at']),
    htmlUrl: j['html_url'] as String? ?? '',
    authorAssociation: j['author_association'] as String?,
  );
}

enum ReviewState { approved, changesRequested, commented, dismissed, pending }

class Review {
  const Review({
    required this.id,
    required this.user,
    required this.body,
    required this.state,
    required this.submittedAt,
    required this.htmlUrl,
  });

  final int id;
  final GhUser user;
  final String body;
  final ReviewState state;
  final DateTime? submittedAt;
  final String htmlUrl;

  static Review fromJson(Json j) => Review(
    id: j['id'] as int,
    user: GhUser.fromJson(j['user']),
    body: j['body'] as String? ?? '',
    state: switch (j['state']) {
      'APPROVED' => ReviewState.approved,
      'CHANGES_REQUESTED' => ReviewState.changesRequested,
      'DISMISSED' => ReviewState.dismissed,
      'PENDING' => ReviewState.pending,
      _ => ReviewState.commented,
    },
    submittedAt: parseDate(j['submitted_at']),
    htmlUrl: j['html_url'] as String? ?? '',
  );
}

enum DiffSide { left, right }

class ReviewComment {
  const ReviewComment({
    required this.id,
    required this.user,
    required this.body,
    required this.path,
    required this.side,
    required this.diffHunk,
    required this.createdAt,
    required this.htmlUrl,
    this.reviewId,
    this.inReplyToId,
    this.line,
    this.originalLine,
    this.startLine,
    this.isFileLevel = false,
  });

  final int id;
  final int? reviewId;
  final int? inReplyToId;
  final GhUser user;
  final String body;
  final String path;

  /// Line in the current diff; null when the comment is outdated.
  final int? line;
  final int? originalLine;
  final int? startLine;
  final DiffSide side;
  final String diffHunk;
  final DateTime? createdAt;
  final String htmlUrl;
  final bool isFileLevel;

  bool get isOutdated => line == null && !isFileLevel;

  static ReviewComment fromJson(Json j) => ReviewComment(
    id: j['id'] as int,
    reviewId: j['pull_request_review_id'] as int?,
    inReplyToId: j['in_reply_to_id'] as int?,
    user: GhUser.fromJson(j['user']),
    body: j['body'] as String? ?? '',
    path: j['path'] as String? ?? '',
    line: j['line'] as int?,
    originalLine: j['original_line'] as int?,
    startLine: j['start_line'] as int?,
    side: j['side'] == 'LEFT' ? DiffSide.left : DiffSide.right,
    diffHunk: j['diff_hunk'] as String? ?? '',
    createdAt: parseDate(j['created_at']),
    htmlUrl: j['html_url'] as String? ?? '',
    isFileLevel: j['subject_type'] == 'file',
  );
}

/// A root review comment plus its replies.
class ReviewThread {
  ReviewThread(this.root);

  final ReviewComment root;
  final List<ReviewComment> replies = [];

  Iterable<ReviewComment> get all sync* {
    yield root;
    yield* replies;
  }

  int get length => 1 + replies.length;
  String get path => root.path;
  DiffSide get side => root.side;
  int? get line => root.line;
  bool get isOutdated => root.isOutdated;

  /// Groups flat review comments into threads ordered by creation time.
  static List<ReviewThread> group(List<ReviewComment> comments) {
    final byId = <int, ReviewThread>{};
    final threads = <ReviewThread>[];
    final sorted = [...comments]
      ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    for (final c in sorted) {
      final parent = c.inReplyToId == null ? null : byId[c.inReplyToId];
      if (parent != null) {
        parent.replies.add(c);
        byId[c.id] = parent;
      } else {
        final t = ReviewThread(c);
        byId[c.id] = t;
        threads.add(t);
      }
    }
    return threads;
  }
}

class Commit {
  const Commit({
    required this.sha,
    required this.message,
    required this.authorName,
    required this.date,
    required this.htmlUrl,
    this.author,
  });

  final String sha;
  final String message;
  final String authorName;
  final GhUser? author;
  final DateTime? date;
  final String htmlUrl;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  String get headline {
    final i = message.indexOf('\n');
    return i < 0 ? message : message.substring(0, i);
  }

  String get details {
    final i = message.indexOf('\n');
    return i < 0 ? '' : message.substring(i + 1).trim();
  }

  static Commit fromJson(Json j) {
    final c = j['commit'] as Json? ?? const {};
    final a = c['author'] as Json? ?? const {};
    return Commit(
      sha: j['sha'] as String? ?? '',
      message: c['message'] as String? ?? '',
      authorName: a['name'] as String? ?? 'unknown',
      author: j['author'] == null ? null : GhUser.fromJson(j['author']),
      date: parseDate(a['date']),
      htmlUrl: j['html_url'] as String? ?? '',
    );
  }
}

class CheckSummary {
  const CheckSummary({
    required this.total,
    required this.success,
    required this.failure,
    required this.pending,
    required this.neutral,
  });

  final int total;
  final int success;
  final int failure;
  final int pending;
  final int neutral;

  static CheckSummary fromCheckRuns(Json j) {
    var success = 0, failure = 0, pending = 0, neutral = 0;
    final runs = j['check_runs'] as List? ?? const [];
    for (final r in runs.cast<Json>()) {
      if (r['status'] != 'completed') {
        pending++;
        continue;
      }
      switch (r['conclusion']) {
        case 'success':
          success++;
        case 'failure' || 'timed_out' || 'action_required' || 'startup_failure':
          failure++;
        case 'cancelled' || 'stale':
          failure++;
        default:
          neutral++;
      }
    }
    return CheckSummary(
      total: j['total_count'] as int? ?? runs.length,
      success: success,
      failure: failure,
      pending: pending,
      neutral: neutral,
    );
  }
}

class RateLimitInfo {
  const RateLimitInfo({required this.limit, required this.remaining, required this.resetAt});

  final int limit;
  final int remaining;
  final DateTime resetAt;
}
