import 'dart:typed_data';

/// A small, fast, line-oriented tokenizer. It recognises comments, strings,
/// numbers, keywords and a few language-specific forms, which is most of what
/// makes code readable in a diff, at a fraction of the cost of a full grammar.
/// Multi-line comments and strings carry over between lines via a state int.
abstract final class Tok {
  static const plain = 0;
  static const keyword = 1;
  static const string = 2;
  static const comment = 3;
  static const number = 4;
  static const type = 5;
  static const meta = 6;
  static const func = 7;
  static const tag = 8;
  static const property = 9;
}

abstract final class _St {
  static const normal = 0;
  static const block = 1;
  static const tripleDouble = 2;
  static const tripleSingle = 3;
  static const backtick = 4;
}

class LanguageSpec {
  const LanguageSpec({
    this.keywords = const {},
    this.literals = const {},
    this.types = const {},
    this.lineComments = const [],
    this.blockStart,
    this.blockEnd,
    this.quotes = '"\'',
    this.tripleQuotes = false,
    this.multilineBacktick = false,
    this.annotations = false,
    this.preprocessor = false,
    this.capitalizedTypes = true,
    this.markup = false,
    this.jsonKeys = false,
    this.keyBeforeColon = false,
    this.keyBeforeEquals = false,
    this.shellVars = false,
    this.ignoreCase = false,
    this.markdown = false,
  });

  final Set<String> keywords;
  final Set<String> literals;
  final Set<String> types;
  final List<String> lineComments;
  final String? blockStart;
  final String? blockEnd;
  final String quotes;
  final bool tripleQuotes;
  final bool multilineBacktick;
  final bool annotations;
  final bool preprocessor;
  final bool capitalizedTypes;
  final bool markup;
  final bool jsonKeys;
  final bool keyBeforeColon;
  final bool keyBeforeEquals;
  final bool shellVars;
  final bool ignoreCase;
  final bool markdown;
}

Set<String> _w(String words) => words.split(' ').where((w) => w.isNotEmpty).toSet();

final _cLiterals = _w('true false null nullptr NULL nil YES NO');

final _dart = LanguageSpec(
  keywords: _w(
    'abstract as assert async await base break case catch class const continue covariant '
    'default deferred do dynamic else enum export extends extension external factory final '
    'finally for Function get hide if implements import in interface is late library mixin new '
    'of on operator part required rethrow return sealed set show static super switch sync this '
    'throw try typedef var void when while with yield',
  ),
  literals: _w('true false null'),
  types: _w('int double num bool'),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  tripleQuotes: true,
  annotations: true,
);

final _js = LanguageSpec(
  keywords: _w(
    'break case catch class const continue debugger default delete do else enum export extends '
    'finally for function if import in instanceof let new of return super switch this throw try '
    'typeof var void while with yield async await static get set from as implements interface '
    'package private protected public type namespace declare abstract readonly keyof infer is '
    'satisfies override module',
  ),
  literals: _w('true false null undefined NaN Infinity'),
  types: _w('string number boolean any unknown never object symbol bigint'),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  quotes: '"\'`',
  multilineBacktick: true,
  annotations: true,
);

final _jvm = LanguageSpec(
  keywords: _w(
    'abstract assert break case catch class const continue default do else enum extends final '
    'finally for goto if implements import instanceof interface native new package private '
    'protected public return static strictfp super switch synchronized this throw throws '
    'transient try volatile while var record sealed permits yield fun val object companion data '
    'inline override open internal lateinit when is in out by init typealias suspend operator '
    'infix reified vararg namespace using struct readonly ref params async await get set where '
    'partial event delegate base lock virtual def trait extends implicit lazy match',
  ),
  literals: _w('true false null'),
  types: _w(
    'void boolean byte char short int long float double string bool decimal object dynamic uint '
    'ulong ushort sbyte Unit Int Long Boolean String',
  ),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  tripleQuotes: true,
  annotations: true,
);

final _swift = LanguageSpec(
  keywords: _w(
    'associatedtype class deinit enum extension fileprivate func import init inout internal let '
    'open operator private protocol public rethrows static struct subscript typealias var break '
    'case continue default defer do else fallthrough for guard if in repeat return switch where '
    'while as catch is super self Self throw throws try async await actor some any mutating '
    'override weak unowned lazy final required convenience optional get set willSet didSet',
  ),
  literals: _w('true false nil'),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  tripleQuotes: true,
  annotations: true,
);

final _go = LanguageSpec(
  keywords: _w(
    'break case chan const continue default defer else fallthrough for func go goto if import '
    'interface map package range return select struct switch type var',
  ),
  literals: _w('true false nil iota'),
  types: _w(
    'bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string '
    'uint uint8 uint16 uint32 uint64 uintptr any',
  ),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  quotes: '"\'`',
  multilineBacktick: true,
  capitalizedTypes: false,
);

final _rust = LanguageSpec(
  keywords: _w(
    'as async await break const continue crate dyn else enum extern fn for if impl in let loop '
    'match mod move mut pub ref return self Self static struct super trait type unsafe use where '
    'while union',
  ),
  literals: _w('true false None Some Ok Err'),
  types: _w('i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String'),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  quotes: '"',
  annotations: false,
);

final _c = LanguageSpec(
  keywords: _w(
    'auto break case const continue default do else enum extern for goto if inline register '
    'restrict return signed sizeof static struct switch typedef union unsigned volatile while '
    'class namespace template typename public private protected virtual override final new '
    'delete this throw try catch using operator friend explicit constexpr noexcept static_cast '
    'dynamic_cast reinterpret_cast const_cast decltype mutable thread_local concept requires '
    'co_await co_return co_yield self id',
  ),
  literals: _cLiterals,
  types: _w(
    'void char short int long float double bool size_t int8_t int16_t int32_t int64_t uint8_t '
    'uint16_t uint32_t uint64_t',
  ),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  preprocessor: true,
  annotations: true,
);

final _python = LanguageSpec(
  keywords: _w(
    'and as assert async await break class continue def del elif else except finally for from '
    'global if import in is lambda nonlocal not or pass raise return try while with yield match '
    'case self',
  ),
  literals: _w('True False None'),
  types: _w('int float str bool list dict set tuple bytes object'),
  lineComments: const ['#'],
  tripleQuotes: true,
  annotations: true,
);

final _ruby = LanguageSpec(
  keywords: _w(
    'alias and begin break case class def defined? do else elsif end ensure for if in module '
    'next not or redo rescue retry return self super then undef unless until when while yield '
    'require require_relative attr_accessor attr_reader private protected public',
  ),
  literals: _w('true false nil'),
  lineComments: const ['#'],
);

final _php = LanguageSpec(
  keywords: _w(
    'abstract and array as break callable case catch class clone const continue declare default '
    'do echo else elseif empty extends final finally fn for foreach function global goto if '
    'implements include include_once instanceof insteadof interface isset list match namespace '
    'new or print private protected public readonly require require_once return static switch '
    'throw trait try unset use var while xor yield',
  ),
  literals: _w('true false null TRUE FALSE NULL'),
  lineComments: const ['//', '#'],
  blockStart: '/*',
  blockEnd: '*/',
  shellVars: true,
);

final _shell = LanguageSpec(
  keywords: _w(
    'if then else elif fi case esac for while until do done in function return exit export '
    'local readonly declare unset shift source alias set echo cd',
  ),
  literals: _w('true false'),
  lineComments: const ['#'],
  shellVars: true,
  capitalizedTypes: false,
);

final _sql = LanguageSpec(
  keywords: _w(
    'select from where insert into values update set delete create table alter drop index view '
    'join left right inner outer full cross on as and or not is in exists between like ilike '
    'group by order having limit offset union all distinct case when then else end primary key '
    'foreign references default constraint unique check returning with begin commit rollback '
    'transaction grant revoke if replace trigger function procedure declare cascade asc desc '
    'add column rename to using',
  ),
  literals: _w('null true false'),
  types: _w(
    'int integer bigint smallint serial bigserial text varchar char boolean bool date time '
    'timestamp timestamptz uuid json jsonb numeric decimal real float double',
  ),
  lineComments: const ['--'],
  blockStart: '/*',
  blockEnd: '*/',
  ignoreCase: true,
  capitalizedTypes: false,
);

final _yaml = LanguageSpec(
  literals: _w('true false null yes no on off True False Null'),
  lineComments: const ['#'],
  keyBeforeColon: true,
  capitalizedTypes: false,
);

final _json = LanguageSpec(
  literals: _w('true false null'),
  quotes: '"',
  jsonKeys: true,
  capitalizedTypes: false,
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
);

final _toml = LanguageSpec(
  literals: _w('true false'),
  lineComments: const ['#', ';'],
  keyBeforeEquals: true,
  tripleQuotes: true,
  capitalizedTypes: false,
);

final _css = LanguageSpec(
  keywords: _w('important from to and not only'),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
  keyBeforeColon: true,
  capitalizedTypes: false,
  shellVars: true,
);

final _markup = LanguageSpec(blockStart: '<!--', blockEnd: '-->', markup: true, capitalizedTypes: false);

final _lua = LanguageSpec(
  keywords: _w(
    'and break do else elseif end for function goto if in local not or repeat return then until '
    'while',
  ),
  literals: _w('true false nil'),
  lineComments: const ['--'],
  capitalizedTypes: false,
);

final _proto = LanguageSpec(
  keywords: _w(
    'syntax package import option message enum service rpc returns repeated optional required '
    'oneof map reserved extend stream edition',
  ),
  literals: _w('true false'),
  types: _w(
    'double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool '
    'string bytes',
  ),
  lineComments: const ['//'],
  blockStart: '/*',
  blockEnd: '*/',
);

final _graphql = LanguageSpec(
  keywords: _w(
    'query mutation subscription fragment on type interface union enum input scalar schema '
    'extend implements directive',
  ),
  literals: _w('true false null'),
  lineComments: const ['#'],
  tripleQuotes: true,
  annotations: true,
);

final _docker = LanguageSpec(
  keywords: _w(
    'from run cmd label expose env add copy entrypoint volume user workdir arg onbuild '
    'stopsignal healthcheck shell as',
  ),
  lineComments: const ['#'],
  shellVars: true,
  ignoreCase: true,
  capitalizedTypes: false,
);

final _make = LanguageSpec(
  keywords: _w('ifeq ifneq ifdef ifndef else endif include define endef export override'),
  lineComments: const ['#'],
  shellVars: true,
  capitalizedTypes: false,
);

const _markdown = LanguageSpec(markdown: true, quotes: '', capitalizedTypes: false);

final Map<String, LanguageSpec> _byExtension = {
  'dart': _dart,
  for (final e in ['js', 'jsx', 'mjs', 'cjs', 'ts', 'tsx', 'mts', 'cts', 'vue', 'svelte', 'astro']) e: _js,
  for (final e in ['java', 'kt', 'kts', 'scala', 'groovy', 'gradle', 'cs', 'fs']) e: _jvm,
  'swift': _swift,
  'go': _go,
  'rs': _rust,
  for (final e in ['c', 'h', 'cc', 'cpp', 'cxx', 'hpp', 'hh', 'hxx', 'm', 'mm', 'ino', 'cu']) e: _c,
  for (final e in ['py', 'pyi', 'pyx', 'bzl', 'star']) e: _python,
  for (final e in ['rb', 'rake', 'gemspec']) e: _ruby,
  'php': _php,
  for (final e in ['sh', 'bash', 'zsh', 'fish', 'ksh', 'env']) e: _shell,
  'sql': _sql,
  for (final e in ['yaml', 'yml']) e: _yaml,
  for (final e in ['json', 'jsonc', 'json5', 'arb', 'webmanifest']) e: _json,
  for (final e in ['toml', 'ini', 'cfg', 'conf', 'properties']) e: _toml,
  for (final e in ['css', 'scss', 'sass', 'less']) e: _css,
  for (final e in ['html', 'htm', 'xml', 'svg', 'xaml', 'plist', 'xib', 'storyboard', 'csproj']) e: _markup,
  'lua': _lua,
  'proto': _proto,
  for (final e in ['graphql', 'gql']) e: _graphql,
  for (final e in ['md', 'markdown', 'mdx']) e: _markdown,
  'mk': _make,
  'dockerfile': _docker,
};

final Map<String, LanguageSpec> _byName = {
  'dockerfile': _docker,
  'containerfile': _docker,
  'makefile': _make,
  'gnumakefile': _make,
  'build': _python,
  'workspace': _python,
  'gemfile': _ruby,
  'rakefile': _ruby,
  'podfile': _ruby,
  'fastfile': _ruby,
  'jenkinsfile': _jvm,
  '.bashrc': _shell,
  '.zshrc': _shell,
  '.gitignore': _shell,
  '.gitattributes': _shell,
  '.editorconfig': _toml,
};

LanguageSpec? languageFor(String path) {
  final slash = path.lastIndexOf('/');
  final name = (slash < 0 ? path : path.substring(slash + 1)).toLowerCase();
  final byName = _byName[name];
  if (byName != null) return byName;
  if (name.startsWith('dockerfile')) return _docker;
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  return _byExtension[name.substring(dot + 1)];
}

bool _isIdentStart(int c) =>
    (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F || c == 0x24 || c > 0x7F;

bool _isIdentPart(int c) => _isIdentStart(c) || (c >= 0x30 && c <= 0x39);

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isSpace(int c) => c == 0x20 || c == 0x09;

bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;

/// Tokenizes one line. Returns flat `[start, end, type, ...]` triples (plain
/// text is omitted) and the state to pass to the next line.
(Int32List, int) tokenizeLine(String s, LanguageSpec spec, int state) {
  final out = <int>[];
  final n = s.length;
  var i = 0;

  void emit(int start, int end, int type) {
    if (end > start && type != Tok.plain) {
      out
        ..add(start)
        ..add(end)
        ..add(type);
    }
  }

  // Finds [close] from [from], honouring backslash escapes when [escapes].
  int findClose(String close, int from, {bool escapes = true}) {
    var j = from;
    while (j < n) {
      final c = s.codeUnitAt(j);
      if (escapes && c == 0x5C) {
        j += 2;
        continue;
      }
      if (s.startsWith(close, j)) return j + close.length;
      j++;
    }
    return -1;
  }

  if (spec.markdown) {
    final trimmed = s.trimLeft();
    if (trimmed.startsWith('#')) {
      emit(0, n, Tok.keyword);
    } else if (trimmed.startsWith('>')) {
      emit(0, n, Tok.comment);
    } else if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      emit(0, n, Tok.meta);
    } else {
      var j = 0;
      while (j < n) {
        final open = s.indexOf('`', j);
        if (open < 0) break;
        final close = s.indexOf('`', open + 1);
        if (close < 0) break;
        emit(open, close + 1, Tok.string);
        j = close + 1;
      }
    }
    return (Int32List.fromList(out), _St.normal);
  }

  // Continue multi-line constructs from the previous line.
  if (state != _St.normal) {
    final (close, type, escapes) = switch (state) {
      _St.block => (spec.blockEnd ?? '*/', Tok.comment, false),
      _St.tripleDouble => ('"""', Tok.string, true),
      _St.tripleSingle => ("'''", Tok.string, true),
      _ => ('`', Tok.string, true),
    };
    final end = findClose(close, 0, escapes: escapes);
    if (end < 0) {
      emit(0, n, type);
      return (Int32List.fromList(out), state);
    }
    emit(0, end, type);
    i = end;
    state = _St.normal;
  }

  var firstNonSpace = true;
  while (i < n) {
    final c = s.codeUnitAt(i);
    if (_isSpace(c)) {
      i++;
      continue;
    }
    final atLineStart = firstNonSpace;
    firstNonSpace = false;

    // Line comments. `#` only counts at the start or after whitespace so
    // shell's `$#` and URL fragments survive.
    var isComment = false;
    for (final lc in spec.lineComments) {
      if (s.startsWith(lc, i) && (lc != '#' || i == 0 || _isSpace(s.codeUnitAt(i - 1)))) {
        isComment = true;
        break;
      }
    }
    if (isComment) {
      emit(i, n, Tok.comment);
      break;
    }

    final bs = spec.blockStart;
    if (bs != null && s.startsWith(bs, i)) {
      final end = findClose(spec.blockEnd!, i + bs.length, escapes: false);
      if (end < 0) {
        emit(i, n, Tok.comment);
        return (Int32List.fromList(out), _St.block);
      }
      emit(i, end, Tok.comment);
      i = end;
      continue;
    }

    if (spec.preprocessor && atLineStart && c == 0x23) {
      var j = i + 1;
      while (j < n && _isIdentPart(s.codeUnitAt(j))) {
        j++;
      }
      emit(i, j, Tok.meta);
      i = j;
      continue;
    }

    if (spec.markup && c == 0x3C) {
      var j = i + 1;
      if (j < n && (s.codeUnitAt(j) == 0x2F || s.codeUnitAt(j) == 0x3F || s.codeUnitAt(j) == 0x21)) {
        j++;
      }
      final nameStart = j;
      while (j < n) {
        final d = s.codeUnitAt(j);
        if (!_isIdentPart(d) && d != 0x2D && d != 0x3A && d != 0x2E) break;
        j++;
      }
      emit(nameStart, j, Tok.tag);
      i = j > i + 1 ? j : i + 1;
      continue;
    }

    if (spec.quotes.isNotEmpty && spec.quotes.contains(String.fromCharCode(c))) {
      final q = String.fromCharCode(c);
      if (spec.tripleQuotes && (c == 0x22 || c == 0x27) && s.startsWith('$q$q$q', i)) {
        final end = findClose('$q$q$q', i + 3);
        if (end < 0) {
          emit(i, n, Tok.string);
          return (Int32List.fromList(out), c == 0x22 ? _St.tripleDouble : _St.tripleSingle);
        }
        emit(i, end, Tok.string);
        i = end;
        continue;
      }
      final end = findClose(q, i + 1);
      if (end < 0) {
        emit(i, n, Tok.string);
        if (c == 0x60 && spec.multilineBacktick) {
          return (Int32List.fromList(out), _St.backtick);
        }
        break;
      }
      var type = Tok.string;
      if (spec.jsonKeys) {
        var j = end;
        while (j < n && _isSpace(s.codeUnitAt(j))) {
          j++;
        }
        if (j < n && s.codeUnitAt(j) == 0x3A) type = Tok.property;
      }
      emit(i, end, type);
      i = end;
      continue;
    }

    if (_isDigit(c) || (c == 0x2E && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
      if (i > 0 && _isIdentPart(s.codeUnitAt(i - 1))) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < n) {
        final d = s.codeUnitAt(j);
        if (_isIdentPart(d) || d == 0x2E || d == 0x5F) {
          j++;
        } else if ((d == 0x2B || d == 0x2D) && (s.codeUnitAt(j - 1) | 0x20) == 0x65) {
          j++; // exponent sign
        } else {
          break;
        }
      }
      emit(i, j, Tok.number);
      i = j;
      continue;
    }

    if ((c == 0x40 && spec.annotations) || (c == 0x24 && spec.shellVars)) {
      var j = i + 1;
      if (j < n && s.codeUnitAt(j) == 0x7B) {
        final close = s.indexOf('}', j);
        j = close < 0 ? n : close + 1;
      } else {
        while (j < n && (_isIdentPart(s.codeUnitAt(j)) || s.codeUnitAt(j) == 0x2E)) {
          j++;
        }
      }
      if (j > i + 1) {
        emit(i, j, Tok.meta);
        i = j;
        continue;
      }
    }

    if (_isIdentStart(c)) {
      var j = i + 1;
      final keyish = spec.keyBeforeColon || spec.keyBeforeEquals;
      while (j < n) {
        final d = s.codeUnitAt(j);
        if (_isIdentPart(d) || (keyish && (d == 0x2D || d == 0x2E))) {
          j++;
        } else {
          break;
        }
      }
      final word = s.substring(i, j);
      final lookup = spec.ignoreCase ? word.toLowerCase() : word;
      var k = j;
      while (k < n && _isSpace(s.codeUnitAt(k))) {
        k++;
      }
      final next = k < n ? s.codeUnitAt(k) : 0;
      var type = Tok.plain;
      if (spec.keyBeforeColon && next == 0x3A && (k + 1 >= n || s.codeUnitAt(k + 1) != 0x3A)) {
        type = Tok.property;
      } else if (spec.keyBeforeEquals && atLineStart && next == 0x3D) {
        type = Tok.property;
      } else if (spec.keywords.contains(lookup)) {
        type = Tok.keyword;
      } else if (spec.literals.contains(lookup)) {
        type = Tok.number;
      } else if (spec.types.contains(lookup)) {
        type = Tok.type;
      } else if (spec.markup && next == 0x3D) {
        type = Tok.property;
      } else if (spec.capitalizedTypes && _isUpper(c) && word.length > 1) {
        type = Tok.type;
      } else if (next == 0x28 && !spec.markup) {
        type = Tok.func;
      }
      emit(i, j, type);
      i = j;
      continue;
    }

    if (spec.keyBeforeEquals && atLineStart && c == 0x5B) {
      final close = s.indexOf(']', i);
      final end = close < 0 ? n : close + 1;
      emit(i, end, Tok.meta);
      i = end;
      continue;
    }

    i++;
  }
  return (Int32List.fromList(out), state);
}
