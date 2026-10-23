import 'dart:convert';
import 'dart:typed_data';

import 'diff_models.dart';

final _hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$');

typedef ParsedPatch = ({List<DiffLine> lines, List<DiffHunk> hunks});

/// Parses a unified diff body (the `patch` field GitHub returns per file).
ParsedPatch parsePatch(String patch) {
  final lines = <DiffLine>[];
  final hunks = <DiffHunk>[];
  final raw = patch.split('\n');

  var inHunk = false;
  var oldNo = 0, newNo = 0;
  var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0, start = 0;
  var section = '';

  void closeHunk() {
    if (!inHunk) return;
    hunks.add(
      DiffHunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        section: section,
        start: start,
        end: lines.length,
      ),
    );
  }

  for (var i = 0; i < raw.length; i++) {
    var l = raw[i];
    if (l.startsWith('@@')) {
      final m = _hunkRe.firstMatch(l);
      if (m != null) {
        closeHunk();
        inHunk = true;
        oldStart = int.parse(m.group(1)!);
        oldCount = m.group(2) == null ? 1 : int.parse(m.group(2)!);
        newStart = int.parse(m.group(3)!);
        newCount = m.group(4) == null ? 1 : int.parse(m.group(4)!);
        section = m.group(5)!.trim();
        start = lines.length;
        oldNo = oldStart;
        newNo = newStart;
        continue;
      }
    }
    if (!inHunk) continue;
    if (l.isEmpty) {
      // A trailing newline produces an empty final element; anything else is
      // an empty context line whose leading space was stripped.
      if (i == raw.length - 1) break;
      lines.add(DiffLine(LineKind.context, oldNo++, newNo++, ''));
      continue;
    }
    if (l.endsWith('\r')) l = l.substring(0, l.length - 1);
    switch (l.codeUnitAt(0)) {
      case 0x2B: // +
        lines.add(DiffLine(LineKind.add, 0, newNo++, l.substring(1)));
      case 0x2D: // -
        lines.add(DiffLine(LineKind.del, oldNo++, 0, l.substring(1)));
      case 0x5C: // backslash: "\ No newline at end of file"
        lines.add(DiffLine(LineKind.meta, 0, 0, l.substring(1).trim()));
      case 0x20: // space
        lines.add(DiffLine(LineKind.context, oldNo++, newNo++, l.substring(1)));
      default:
        lines.add(DiffLine(LineKind.context, oldNo++, newNo++, l));
    }
  }
  closeHunk();
  return (lines: lines, hunks: hunks);
}

/// Builds a [DiffFile] from one entry of `GET /pulls/{n}/files`.
DiffFile diffFileFromJson(Map<String, dynamic> j) {
  final patch = j['patch'] as String?;
  final status = FileStatus.parse(j['status'] as String?);
  final additions = j['additions'] as int? ?? 0;
  final deletions = j['deletions'] as int? ?? 0;
  final changes = j['changes'] as int? ?? additions + deletions;

  PatchState state;
  ParsedPatch? parsed;
  if (patch != null && patch.isNotEmpty) {
    parsed = parsePatch(patch);
    state = parsed.lines.isEmpty ? PatchState.noChanges : PatchState.ready;
  } else if (changes > 0) {
    state = PatchState.tooLarge;
  } else if (status == FileStatus.renamed || status == FileStatus.copied || status == FileStatus.changed) {
    state = PatchState.noChanges;
  } else {
    state = PatchState.noTextDiff;
  }

  return DiffFile(
    path: j['filename'] as String? ?? '',
    previousPath: j['previous_filename'] as String?,
    status: status,
    additions: additions,
    deletions: deletions,
    blobSha: j['sha'] as String?,
    lines: parsed?.lines ?? const [],
    hunks: parsed?.hunks ?? const [],
    state: state,
  );
}

/// Decodes and parses one page of `GET /pulls/{n}/files`. Runs in a
/// background isolate.
List<DiffFile> parseFilesPage(Uint8List body) {
  final list = jsonDecode(utf8.decode(body, allowMalformed: true)) as List<dynamic>;
  return [for (final j in list) diffFileFromJson(j as Map<String, dynamic>)];
}
