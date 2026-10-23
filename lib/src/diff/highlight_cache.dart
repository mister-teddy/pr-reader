import 'dart:typed_data';

import 'diff_models.dart';
import 'syntax.dart';
import 'text_metrics.dart';

/// Lazily tokenizes diff lines in blocks so that jumping into the middle of a
/// 50k-line file only pays for the lines on screen. Multi-line state is
/// carried within a hunk and reset at block boundaries.
class HighlightCache {
  static const _blockBits = 9;
  static final _files = Expando<_FileTokens>();

  /// Tokens for line [index] of [file], or null when the language is unknown.
  static Int32List? tokens(DiffFile file, int index) {
    var entry = _files[file];
    if (entry == null || !identical(entry.lines, file.lines)) {
      final spec = languageFor(file.path);
      if (spec == null) return null;
      entry = _FileTokens(file, spec);
      _files[file] = entry;
    }
    return entry.get(index);
  }
}

class _FileTokens {
  _FileTokens(DiffFile file, this.spec)
    : lines = file.lines,
      tokens = List<Int32List?>.filled(file.lines.length, null),
      done = Uint8List((file.lines.length >> HighlightCache._blockBits) + 1),
      hunkStart = Uint8List(file.lines.length) {
    for (final h in file.hunks) {
      if (h.start < hunkStart.length) hunkStart[h.start] = 1;
    }
  }

  final List<DiffLine> lines;
  final LanguageSpec spec;
  final List<Int32List?> tokens;
  final Uint8List done;
  final Uint8List hunkStart;

  Int32List? get(int index) {
    if (index < 0 || index >= lines.length) return null;
    final block = index >> HighlightCache._blockBits;
    if (done[block] == 0) {
      _compute(block);
      done[block] = 1;
    }
    return tokens[index];
  }

  void _compute(int block) {
    final start = block << HighlightCache._blockBits;
    final end = (start + (1 << HighlightCache._blockBits)).clamp(0, lines.length);
    final docBlocks = spec.blockStart == '/*';
    var oldState = 0, newState = 0;
    for (var i = start; i < end; i++) {
      if (hunkStart[i] == 1) {
        oldState = 0;
        newState = 0;
      }
      final line = lines[i];
      if (line.kind == LineKind.meta) continue;
      final text = renderText(line.text);
      var state = line.kind == LineKind.del ? oldState : newState;
      // A hunk that starts inside a doc comment: ` * foo` or ` */`.
      if (state == 0 && docBlocks) {
        final t = text.trimLeft();
        if (t == '*' || t.startsWith('* ') || t.startsWith('*/')) state = 1;
      }
      final (toks, next) = tokenizeLine(text, spec, state);
      tokens[i] = toks;
      switch (line.kind) {
        case LineKind.add:
          newState = next;
        case LineKind.del:
          oldState = next;
        default:
          if (oldState != newState) {
            oldState = tokenizeLine(text, spec, oldState).$2;
          } else {
            oldState = next;
          }
          newState = next;
      }
    }
  }
}
