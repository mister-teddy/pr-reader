/// Column math for monospace rendering. Tabs expand to [kTabWidth] spaces and
/// East Asian wide characters and astral-plane characters (emoji) take two
/// columns. Both the layout and the renderer use these functions, which keeps
/// precomputed row heights in sync with what is painted.
library;

const kTabWidth = 4;
const _tabSpaces = '    ';

/// Lines longer than this are truncated for display.
const kMaxRenderCols = 3000;

bool _isWide(int c) =>
    (c >= 0x1100 && c <= 0x115F) ||
    (c >= 0x2E80 && c <= 0xA4CF && c != 0x303F) ||
    (c >= 0xAC00 && c <= 0xD7A3) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFE30 && c <= 0xFE4F) ||
    (c >= 0xFF00 && c <= 0xFF60) ||
    (c >= 0xFFE0 && c <= 0xFFE6);

bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;

bool hasWideChars(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x1100 && (_isWide(c) || _isHighSurrogate(c))) return true;
  }
  return false;
}

int displayColumns(String s) {
  var cols = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x09) {
      cols += kTabWidth;
    } else if (c < 0x1100) {
      cols++;
    } else if (_isHighSurrogate(c)) {
      cols += 2;
      i++;
    } else {
      cols += _isWide(c) ? 2 : 1;
    }
  }
  return cols;
}

/// The text as painted: tabs expanded, very long lines truncated.
String renderText(String text, {int maxCols = kMaxRenderCols}) {
  var s = text.contains('\t') ? text.replaceAll('\t', _tabSpaces) : text;
  if (s.length > maxCols) {
    var cut = maxCols;
    if (_isHighSurrogate(s.codeUnitAt(cut - 1))) cut--;
    s = '${s.substring(0, cut)}…';
  }
  return s;
}

/// Offsets in [display] where a new visual line starts when wrapping at
/// [cols] columns. An empty list means the text fits on one line.
List<int> wrapBreaks(String display, int cols) {
  final breaks = <int>[];
  if (cols <= 0) return breaks;
  var used = 0;
  for (var i = 0; i < display.length; i++) {
    final c = display.codeUnitAt(i);
    final high = _isHighSurrogate(c);
    final w = high ? 2 : (c >= 0x1100 && _isWide(c) ? 2 : 1);
    if (used + w > cols && used > 0) {
      breaks.add(i);
      used = 0;
    }
    used += w;
    if (high) i++;
  }
  return breaks;
}

/// Number of visual lines [text] needs at [cols] columns. Matches
/// `wrapBreaks(renderText(text), cols).length + 1`.
int wrapCount(String text, int lineCols, bool wide, int cols) {
  if (cols <= 0) return 1;
  if (!wide && lineCols <= kMaxRenderCols) {
    return lineCols <= cols ? 1 : (lineCols + cols - 1) ~/ cols;
  }
  return wrapBreaks(renderText(text), cols).length + 1;
}
