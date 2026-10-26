/*  regex.x -- regular expressions over the bytes of a String

    Copyright (c) 2026 Gary William Flake

    A Regex is a compiled pattern, owned by the scope that compiled it. A
    RegexMatch and a RegexCapture are immutable Lists, so their Strings and
    offsets stay valid after the next match. Matching backtracks over a
    small node tree; a repeated single byte class runs as a loop, so the
    common `.*` and `\w+` forms do not recurse per byte. The syntax is the
    byte-oriented subset in the book's "Patterns" section.
*/

#pragma once
#include "x2c.x"

typedef struct _RegexNode *_RegexNode;

/** A compiled pattern. `Regex.compile` makes one; the scope that made it
    frees it. A `RegexMatch` is the `List` of `RegexCapture`s of one match,
    indexed by capture number or name; each capture is the `List` of its
    index, name, whether it took part, text, start, and end.
*/
class Regex struct {
  String pattern;
  _RegexNode program;
  int capture_count;
  List capture_names;
  int caseless, multiline, dotall;
} *;

meta Regex Var.regex(Var value);

/** One capture of a match: index, name, matched, text, start, end. */
typedef List RegexCapture;

/** The captures of one match, with the whole match at index 0. */
typedef List RegexMatch;

/** Indexing a `RegexMatch` by capture number or name yields its text. */
protocol RegexMatchIndex(T) {
  associated Key = Var;
  associated Value = String;

  Value T.getindex(T, Key);
}

protocol RegexMatchIndex(RegexMatch);

#include <string.h>

/* regex diagnostic messages. Payload owners retain failure policy. */

static macro Expression $reason.unmatched_close() => "unmatched closing parenthesis";
static macro Expression $reason.no_repeat() => "nothing to repeat";
static macro Expression $reason.repeat_count() => "repetition count too large";
static macro Expression $reason.repeat_range() => "repetition range out of order";
static macro Expression $reason.missing_close() => "missing closing parenthesis";
static macro Expression $reason.group_syntax() => "unknown group syntax";
static macro Expression $reason.group_name() => "malformed group name";
static macro Expression $reason.unterminated_class() =>
  "unterminated character class";
static macro Expression $reason.character_range() => "character range out of order";
static macro Expression $reason.trailing_backslash() => "pattern ends in a backslash";
static macro Expression $reason.unknown_escape() => "unknown escape";

static macro Stmt $error.compile(Expr $why, Expr $pattern, Expr $offset) {
  raise %(malformed (operation "Regex.compile") (reason $($why))
          (pattern $($pattern)) (offset $($offset)));
}

static macro Stmt $error.depth(Expr $pattern, Expr $limit) {
  raise %(size-limit (operation "Regex.match") (pattern $($pattern))
          (reason "a group repeated more times than one match allows")
          (limit $($limit)));
}

// nodes

/* One node of the compiled pattern; `next` follows the sequence. A `<set>`
   or `<any>` node matches one byte, and `<bol>`, `<eol>`, `<wordb>`, and
   `<nwordb>` test the position. A `<group>` runs its `child` and captures
   as `index`, or not at all for -1, and a `<capend>` ends capture `index`.
   A `<repeat>` runs its `child` `min` to `max` times, with -1 for no
   bound. An `<alt>` holds its first alternative in `child`, and
   alternatives follow each other through `sibling`. */
static struct _RegexNode {
  Symbol kind;
  unsigned char set[32];
  int index;
  int min, max, greedy;
  _RegexNode child, sibling, next;
};

static _RegexNode _node(Symbol kind) {
  _RegexNode node = xcalloc(1, sizeof(struct _RegexNode));
  node.kind = kind;
  return node;
}

static _RegexNode _group_node(int index, _RegexNode child) {
  _RegexNode group = _node(<group>);
  group.index = index;
  group.child = child;
  return group;
}

// byte sets

static void _add(_RegexNode node, int byte) =>
  node.set[byte >> 3] |= (unsigned char) (1 << (byte & 7));

static int _has(_RegexNode node, int byte) =>
  node.set[byte >> 3] & (1 << (byte & 7));

static void _add_range(_RegexNode node, int low, int high) {
  for (int byte = low; byte <= high; byte++) _add(node, byte);
}

static int _is_word(int byte) =>
  byte == '_' || scan_ascii_alpha(byte) || scan_ascii_digit(byte);

/* Adds the bytes of `\d`, `\w`, or `\s` to `node`, or every other byte
   for the capital letter. */
static void _add_class(_RegexNode node, int letter) {
  struct _RegexNode members = {0};
  _RegexNode bytes = &members;
  int negate = letter == 'D' || letter == 'W' || letter == 'S';
  if (negate) letter += 'a' - 'A';
  if (letter == 'd') _add_range(bytes, '0', '9');
  if (letter == 'w')
    for (int byte = 0; byte < 256; byte++)
      if (_is_word(byte)) _add(bytes, byte);
  if (letter == 's') {
    _add(bytes, ' ');
    _add_range(bytes, '\t', '\r');
  }
  for (int i = 0; i < 32; i++)
    node.set[i] |= negate ? (unsigned char) ~members.set[i] : members.set[i];
}

static void _fold(_RegexNode node) {
  for (int byte = 'a'; byte <= 'z'; byte++) {
    int upper = byte - 'a' + 'A';
    if (_has(node, byte) || _has(node, upper)) {
      _add(node, byte);
      _add(node, upper);
    }
  }
}

/* parsing

   The parser reads the pattern once from left to right and builds the
   node tree. A malformed pattern raises `<malformed>` at the byte offset
   where the parser stands. */

static typedef struct Parser {
  Regex regex, const char *text, int pos, len;
} Parser;

static Regex Regex.new(String pattern) {
  Regex regex = xcalloc(1, sizeof(struct Regex));
  regex.pattern = pattern;
  Parser p = {regex, regex.pattern, 0, regex.pattern.len()};
  _flags(p);
  regex.program = _parse_alternation(p);
  if (p.pos < p.len) _fail(p, $reason.unmatched_close());
  return regex;
}

/* Reads a leading `(?i)`, `(?m)`, or `(?s)` in any combination. */
static void _flags(Parser &p) {
  if (p.len < 4 || p.text[0] != '(' || p.text[1] != '?') return;
  int at = 2, caseless = 0, multiline = 0, dotall = 0;
  for (; at < p.len; at++) {
    switch (p.text[at]) {
      case 'i': caseless = 1; continue;
      case 'm': multiline = 1; continue;
      case 's': dotall = 1; continue;
    }
    break;
  }
  if (at == 2 || at >= p.len || p.text[at] != ')') return;
  p.regex.caseless = caseless;
  p.regex.multiline = multiline;
  p.regex.dotall = dotall;
  p.pos = at + 1;
}

/* Sequences separated by `|`. Two or more become an `<alt>` node, with
   each sequence in a group that captures nothing. */
static _RegexNode _parse_alternation(Parser &p) {
  _RegexNode first = _sequence(p);
  if (_peek(p) != '|') return first;
  _RegexNode node = _node(<alt>), last = _group_node(-1, first);
  node.child = last;
  while (_peek(p) == '|') {
    p.pos++;
    last.sibling = _group_node(-1, _sequence(p));
    last = last.sibling;
  }
  return node;
}

static _RegexNode _sequence(Parser &p) {
  _RegexNode head = NULL, last = NULL;
  while (p.pos < p.len && _peek(p) != '|' && _peek(p) != ')') {
    _RegexNode atom = _quantified(p, _atom(p));
    if (last) last.next = atom;
    else head = atom;
    last = atom;
  }
  return head;
}

/* Wraps `atom` in the repetition that follows it, if any. A `?` after the
   quantifier makes it lazy, and another quantifier after that has nothing
   to repeat. */
static _RegexNode _quantified(Parser &p, _RegexNode atom) {
  int min, max;
  if (!_bounds(p, min, max)) return atom;
  if (atom.kind == <bol> || atom.kind == <eol> || atom.kind == <wordb> ||
      atom.kind == <nwordb>)
    _fail(p, $reason.no_repeat());
  p.pos++;
  _RegexNode node = _node(<repeat>);
  node.min = min;
  node.max = max;
  node.greedy = _peek(p) != '?';
  node.child = atom;
  if (!node.greedy) p.pos++;
  if (_is_quantifier(_peek(p))) _fail(p, $reason.no_repeat());
  return node;
}

/* Reads the bounds of the quantifier at the position and leaves the
   position on its last byte, or returns 0 when none is there. */
static int _bounds(Parser &p, int &min, int &max) {
  switch (_peek(p)) {
    case '*': min = 0; max = -1; return 1;
    case '+': min = 1; max = -1; return 1;
    case '?': min = 0; max = 1; return 1;
    case '{': return _braces(p, min, max);
  }
  return 0;
}

/* Reads `{m}`, `{m,}`, or `{m,n}` and leaves the position on its `}`. A
   brace that starts no repetition returns 0 and leaves the position on
   the brace. */
static int _braces(Parser &p, int &min, int &max) {
  int start = p.pos++;
  long long low, high;
  if (!_digits(p, low)) {
    p.pos = start;
    return 0;
  }
  high = low;
  if (_peek(p) == ',') {
    p.pos++;
    if (!_digits(p, high)) high = -1;
  }
  if (_peek(p) != '}') {
    p.pos = start;
    return 0;
  }
  if (low > INT_MAX || high > INT_MAX) {
    p.pos++;
    _fail(p, $reason.repeat_count());
  }
  if (high >= 0 && high < low) {
    p.pos++;
    _fail(p, $reason.repeat_range());
  }
  min = (int) low;
  max = (int) high;
  return 1;
}

/* Reads a decimal count into `out`, which stops growing once it passes
   INT_MAX. */
static int _digits(Parser &p, long long &out) {
  int start = p.pos;
  long long value = 0;
  for (; scan_ascii_digit(_peek(p)); p.pos++)
    if (value <= INT_MAX) value = value * 10 + (p.text[p.pos] - '0');
  out = value;
  return p.pos > start;
}

static int _is_quantifier(int byte) =>
  byte == '*' || byte == '+' || byte == '?';

static int _peek(Parser &p) =>
  p.pos < p.len ? (unsigned char) p.text[p.pos] : -1;

static void _fail(Parser &p, String why) {
  $error.compile(why, p.regex.pattern, p.pos);
}

// atoms

/* A quantifier here has nothing before it to repeat. */
static _RegexNode _atom(Parser &p) {
  int byte = (unsigned char) p.text[p.pos];
  if (_is_quantifier(byte)) _fail(p, $reason.no_repeat());
  p.pos++;
  switch (byte) {
    case '.':  return _node(<any>);
    case '^':  return _node(<bol>);
    case '$':  return _node(<eol>);
    case '[':  return _set(p);
    case '(':  return _parse_group(p);
    case '\\': return _escape_atom(p);
  }
  return _literal(p, byte);
}

/* An escape outside a set: a word boundary test, or a set of the byte or
   class the escape names. */
static _RegexNode _escape_atom(Parser &p) {
  int letter = _peek(p);
  if (letter != 'b' && letter != 'B') return _literal(p, _escape(p));
  p.pos++;
  return _node(letter == 'b' ? <wordb> : <nwordb>);
}

/* A set of one byte, or of the class a negated letter names, folded when
   the pattern ignores case. */
static _RegexNode _literal(Parser &p, int byte) {
  _RegexNode node = _node(<set>);
  if (byte < 0) _add_class(node, -byte);
  else _add(node, byte);
  if (p.regex.caseless) _fold(node);
  return node;
}

/* A group after its `(`. A plain `(` captures by number, `(?<name>` by
   number and name, and `(?:` not at all. */
static _RegexNode _parse_group(Parser &p) {
  int index = _peek(p) == '?' ? _group_syntax(p) : _add_capture(p, NULL);
  _RegexNode body = _parse_alternation(p);
  if (_peek(p) != ')') _fail(p, $reason.missing_close());
  p.pos++;
  return _group_node(index, index < 0 ? body : _close_capture(body, index));
}

/* Reads the rest of a `(?` and returns the group's capture number, or -1
   for `(?:`. */
static int _group_syntax(Parser &p) {
  p.pos++;
  int marker = _peek(p);
  if (marker == ':') {
    p.pos++;
    return -1;
  }
  if (marker != '<') {
    p.pos--;
    _fail(p, $reason.group_syntax());
  }
  p.pos++;
  return _add_capture(p, _name(p));
}

/* Reads a capture name and its `>`: word bytes that do not start with a
   digit. */
static String _name(Parser &p) {
  int start = p.pos;
  while (_is_word(_peek(p))) p.pos++;
  if (p.pos == start || scan_ascii_digit(p.text[start]) || _peek(p) != '>') {
    p.pos = start;
    _fail(p, $reason.group_name());
  }
  String name = p.regex.pattern[start:p.pos];
  p.pos++;
  return name;
}

/* Numbers a new capture and records its name, which may be NULL. */
static int _add_capture(Parser &p, String name) {
  int index = ++p.regex.capture_count;
  p.regex.capture_names = p.regex.capture_names.append($(name));
  return index;
}

/* Ends the sequence `body` with the `<capend>` node of capture `index`. */
static _RegexNode _close_capture(_RegexNode body, int index) {
  _RegexNode end = _node(<capend>);
  end.index = index;
  if (!body) return end;
  _RegexNode last = body;
  while (last.next) last = last.next;
  last.next = end;
  return body;
}

/* A set after its `[`. A `]` first in the set is a member, and a leading
   `^` negates the set after case folding. */
static _RegexNode _set(Parser &p) {
  _RegexNode node = _node(<set>);
  int negate = _peek(p) == '^';
  if (negate) p.pos++;
  int first = p.pos;
  while (p.pos == first || _peek(p) != ']') {
    if (p.pos >= p.len) _fail(p, $reason.unterminated_class());
    _member(p, node);
  }
  p.pos++;
  if (p.regex.caseless) _fold(node);
  if (negate)
    for (int i = 0; i < 32; i++) node.set[i] = (unsigned char) ~node.set[i];
  return node;
}

/* Adds one member to the set `node`: a byte, an escaped byte or class, or
   a range of bytes. */
static void _member(Parser &p, _RegexNode node) {
  int low = (unsigned char) p.text[p.pos++];
  if (low == '\\') low = _escape(p);
  if (low < 0) _add_class(node, -low);
  else if (_peek(p) == '-' && p.pos + 1 < p.len && p.text[p.pos + 1] != ']')
    _add_range(node, low, _range_end(p, low));
  else _add(node, low);
}

/* Reads the byte after `-`, which may be escaped and must not be below
   `low`. */
static int _range_end(Parser &p, int low) {
  p.pos++;
  int high = (unsigned char) p.text[p.pos++];
  if (high == '\\') high = _escape(p);
  if (high < low) _fail(p, $reason.character_range());
  return high;
}

/* Reads the byte after a backslash and returns the byte it stands for, or
   the negated letter of a `\d`, `\w`, or `\s` class or its capital. */
static int _escape(Parser &p) {
  if (p.pos >= p.len) _fail(p, $reason.trailing_backslash());
  int byte = (unsigned char) p.text[p.pos++];
  switch (byte) {
    case 't': return '\t';
    case 'n': return '\n';
    case 'r': return '\r';
    case 'f': return '\f';
    case 'v': return '\v';
    case '0': return 0;
    case 'd': case 'D': case 'w': case 'W': case 's': case 'S': return -byte;
  }
  if (!_is_word(byte) && byte < 128) return byte;
  p.pos--;
  _fail(p, $reason.unknown_escape());
}

/* matching

   A search runs the program from each start offset in turn. The first
   start where it matches gives the match, as the List of its captures. */

/* One search of `text`: `end` is where the match ends, `depth` counts the
   iterations of repeated groups in progress, and `starts` and `ends` hold
   each capture's offsets, or -1. */
static typedef struct Matcher {
  Regex regex, const char *text, int len, end, depth, int *starts, *ends;
} Matcher;

static RegexMatch _search(Regex regex, String subject, int offset) {
  int count = regex.capture_count + 1;
  int *starts = xcalloc(2 * count, sizeof(int)), *ends = starts + count;
  defer xfree(starts);
  Matcher m = {regex, subject, subject.len(), 0, 0, starts, ends};
  for (int at = offset; at <= m.len; at++) {
    for (int i = 0; i < count; i++) starts[i] = ends[i] = -1;
    if (_run(m, regex.program, at, NULL)) return _found(m, subject, at);
  }
  return NULL;
}

/* The match that starts at `at`, with its captures in number order. */
static RegexMatch _found(Matcher &m, String subject, int at) {
  m.starts[0] = at;
  m.ends[0] = m.end;
  List captures = NULL;
  for (int i = m.regex.capture_count; i >= 0; i--)
    captures = cons(_capture(m, subject, i), captures);
  return (RegexMatch) captures;
}

/* Result fields are `(index name matched text start end)`. */
static RegexCapture _capture(Matcher &m, String subject, int i) {
  int start = m.starts[i], end = m.ends[i], matched = start >= 0;
  String name = i ? m.regex.capture_names[i - 1] : NULL;
  String text = matched ? subject[start:end] : NULL;
  return $(i, name, matched, text, start, end);
}

static RegexCapture _whole(RegexMatch found) => found.car();

/* The match after `previous`; an empty match advances one byte. */
static RegexMatch _next(Regex r, String subject, RegexMatch previous) {
  int start = _whole(previous).start(), end = _whole(previous).end();
  return _search(r, subject, end > start ? end : end + 1);
}

/* backtracking

   A byte test or an assertion goes on to the next node of its sequence. A
   group, capture end, alternation, or repeat runs the rest of the match
   itself and passes what follows its body as a continuation, so a failure
   returns to the most recent choice. */

/* What runs once a sequence ends: the node after a group or alternation,
   or the next iteration of a repeated group. */
static typedef struct Rest {
  int repeat, _RegexNode node, int count, start, struct Rest *up;
} Rest;

/* Runs the sequence from `n` at `pos`, then the rest `k`, and returns
   whether the whole pattern matched. */
static int _run(Matcher &m, _RegexNode n, int pos, Rest *k) {
  for (; n; n = n.next) {
    switch (n.kind) {
      case <set>: case <any>:
        if (!_accepts(m, n, pos)) return 0;
        pos++;
        break;
      case <bol>:    if (!_at_line_start(m, pos)) return 0; break;
      case <eol>:    if (!_at_line_end(m, pos)) return 0; break;
      case <wordb>:  if (!_at_boundary(m, pos)) return 0; break;
      case <nwordb>: if (_at_boundary(m, pos)) return 0; break;
      case <group>:  return _match_group(m, n, pos, k);
      case <capend>: return _capture_end(m, n, pos, k);
      case <alt>:    return _match_alternation(m, n, pos, k);
      case <repeat>: return _repeat(m, n, pos, k);
    }
  }
  return _resume(m, pos, k);
}

static int _accepts(Matcher &m, _RegexNode n, int pos) {
  if (pos >= m.len) return 0;
  int byte = (unsigned char) m.text[pos];
  if (n.kind == <any>) return m.regex.dotall || byte != '\n';
  return _has(n, byte) != 0;
}

static int _at_line_start(Matcher &m, int pos) =>
  pos == 0 || (m.regex.multiline && m.text[pos - 1] == '\n');

static int _at_line_end(Matcher &m, int pos) =>
  pos == m.len || (m.regex.multiline && m.text[pos] == '\n');

static int _at_boundary(Matcher &m, int pos) {
  int before = pos > 0 && _is_word((unsigned char) m.text[pos - 1]);
  int after = pos < m.len && _is_word((unsigned char) m.text[pos]);
  return before != after;
}

/* A capture records its start, and restores the old offsets when the rest
   of the match fails. */
static int _match_group(Matcher &m, _RegexNode n, int pos, Rest *k) {
  Rest after = {0, n.next, 0, 0, k};
  if (n.index < 0) return _run(m, n.child, pos, &after);
  int old_start = m.starts[n.index], old_end = m.ends[n.index];
  m.starts[n.index] = pos;
  if (_run(m, n.child, pos, &after)) return 1;
  m.starts[n.index] = old_start;
  m.ends[n.index] = old_end;
  return 0;
}

static int _capture_end(Matcher &m, _RegexNode n, int pos, Rest *k) {
  int old_end = m.ends[n.index];
  m.ends[n.index] = pos;
  if (_run(m, n.next, pos, k)) return 1;
  m.ends[n.index] = old_end;
  return 0;
}

static int _match_alternation(Matcher &m, _RegexNode n, int pos, Rest *k) {
  Rest after = {0, n.next, 0, 0, k};
  for (_RegexNode alt = n.child; alt; alt = alt.sibling)
    if (_run(m, alt.child, pos, &after)) return 1;
  return 0;
}

/* Without a continuation the match is complete at `pos`. */
static int _resume(Matcher &m, int pos, Rest *k) {
  if (!k) {
    m.end = pos;
    return 1;
  }
  if (k.repeat) return _iterate(m, k.node, k.count + 1, pos, k.start, k.up);
  return _run(m, k.node, pos, k.up);
}

/* repeats

   A repeated byte test counts its longest run and offers the ends in
   greedy or lazy order. Any other repeat runs each iteration through a
   continuation. */

/* Each iteration of a repeated group is a C frame, so a match bounds them
   before the stack runs out, on any thread. */
static const int _DEPTH_LIMIT = 2000;

static int _repeat(Matcher &m, _RegexNode n, int pos, Rest *k) {
  if (n.child.kind == <set> || n.child.kind == <any>)
    return _byte_loop(m, n, pos, k);
  return _iterate(m, n, 0, pos, -1, k);
}

static int _byte_loop(Matcher &m, _RegexNode rep, int pos, Rest *k) {
  int limit = rep.max < 0 ? m.len - pos : rep.max, count = 0;
  while (count < limit && _accepts(m, rep.child, pos + count)) count++;
  if (count < rep.min) return 0;
  if (rep.greedy) {
    for (int n = count; n >= rep.min; n--)
      if (_run(m, rep.next, pos + n, k)) return 1;
    return 0;
  }
  for (int n = rep.min; n <= count; n++)
    if (_run(m, rep.next, pos + n, k)) return 1;
  return 0;
}

/* Runs iteration `count` of `rep` at `pos`; the previous iteration started
   at `last_start`. */
static int _iterate(
  Matcher &m, _RegexNode rep, int count, int pos, int last_start, Rest *k) {
  if (m.depth == _DEPTH_LIMIT) _too_deep(m);
  m.depth++;
  int matched = _iteration(m, rep, count, pos, last_start, k);
  m.depth--;
  return matched;
}

static void _too_deep(Matcher &m) {
  $error.depth(m.regex.pattern, _DEPTH_LIMIT);
}

/* Runs the body again or goes on with the rest, in greedy or lazy order.
   An iteration that matched nothing ends the repeat once `min` is met, so
   an empty body cannot loop. */
static int _iteration(
  Matcher &m, _RegexNode rep, int count, int pos, int last_start, Rest *k) {
  if (count > 0 && pos == last_start && count >= rep.min)
    return _run(m, rep.next, pos, k);
  int more = rep.max < 0 || count < rep.max;
  Rest again = {1, rep, count, pos, k};
  if (count < rep.min) return _run(m, rep.child, pos, &again);
  if (rep.greedy) {
    if (more && _run(m, rep.child, pos, &again)) return 1;
    return _run(m, rep.next, pos, k);
  }
  if (_run(m, rep.next, pos, k)) return 1;
  return more && _run(m, rep.child, pos, &again);
}

// replacement

/* `subject` with its first match, or every match when `all` is set,
   replaced by what `fn` returns for the match or else by `replacement`
   with its references expanded. */
static String _rebuild(
  Regex r, String subject, int all, Func fn, String replacement) {
  Buffer out = auto Buffer.new(0);
  int cursor = 0;
  for (RegexMatch found = _search(r, subject, 0); found;
       found = all ? _next(r, subject, found) : NULL) {
    subject[cursor:_whole(found).start()].write_str(out);
    if (fn) fn(found).str().write_str(out);
    else _expand(out, found, replacement);
    cursor = _whole(found).end();
  }
  subject[cursor:].write_str(out);
  return out;
}

static void _expand(Buffer out, RegexMatch found, String replacement) {
  int n = replacement.len();
  for (int i = 0; i < n; i++) {
    char byte = replacement[i];
    if (byte == '$') i = _reference(out, found, replacement, i);
    else out.write_char(byte);
  }
}

/* Writes the `$` reference at `i` of `text` and returns the index of its
   last byte. `$$` is a dollar sign, `$0` through `$9` and `${name}` insert
   a capture, and any other `$` is itself. */
static int _reference(Buffer out, RegexMatch found, String text, int i) {
  int next = i + 1 < text.len() ? text[i + 1] : -1;
  if (next == '$') {
    out.write_char('$');
    return i + 1;
  }
  if (scan_ascii_digit(next)) {
    found[next - '0'].write_str(out);
    return i + 1;
  }
  int close = next == '{' ? text.find_within("}", i + 2, -1) : -1;
  if (close < 0) {
    out.write_char('$');
    return i;
  }
  found[text[i + 2:close]].write_str(out);
  return close;
}

// patterns

/** Compiles `pattern` and returns the `Regex`, owned by the current scope.
    Raises: `<malformed>` with `reason`, the `pattern`, and the byte `offset`
    of the problem when the pattern does not parse.
*/
Regex Regex.compile(String pattern) => Regex.new(pattern);

/** Returns the text `regex` was compiled from. */
String Regex.pattern(Regex regex) => regex.pattern;

/** Returns the number of capturing groups in `regex`. */
int Regex.capture_count(Regex regex) => regex.capture_count;

/** Returns the names of the capturing groups of `regex` in capture order,
    with NULL for a group without a name.
*/
List Regex.capture_names(Regex regex) => regex.capture_names;

/** Returns `literal` with every ASCII byte that is not a letter, digit, or
    underscore escaped, so that it matches itself inside a pattern.
*/
String Regex.escape(String literal) {
  Buffer out = auto Buffer.new(0);
  int n = literal.len();
  for (int i = 0; i < n; i++) {
    int byte = (unsigned char) literal[i];
    if (byte < 128 && !_is_word(byte)) out.write_char('\\');
    out.write_char((char) byte);
  }
  return out;
}

// searching

/** Returns the first match of `r` in `subject` at or after the byte
    `offset`, or NULL. An offset beyond the end of `subject` finds nothing.
*/
RegexMatch Regex.match_from(Regex r, String subject, int offset) =>
  offset < 0 || offset > subject.len() ? NULL : _search(r, subject, offset);

/** Returns the first match of `r` in `subject`, or NULL. */
RegexMatch Regex.match(Regex r, String subject) => _search(r, subject, 0);

/** Returns every non-overlapping match of `r` in `subject`, in order.
    An empty match advances one byte. No match returns an empty `List`.
*/
List Regex.find_all(Regex r, String subject) {
  Array found = auto [];
  for (RegexMatch next = _search(r, subject, 0); next;
       next = _next(r, subject, next))
    found.push(next);
  return found;
}

/** Returns the text of `subject` between the matches of `regex`, keeping
    an empty field where two matches touch or a match sits at either end.
*/
List Regex.split(Regex regex, String subject) {
  Array parts = auto [];
  int cursor = 0;
  for (RegexMatch found = _search(regex, subject, 0); found;
       found = _next(regex, subject, found)) {
    parts.push(subject[cursor:_whole(found).start()]);
    cursor = _whole(found).end();
  }
  parts.push(subject[cursor:]);
  return parts;
}

/** Returns `subject` with the first match of `regex` replaced. In
    `replacement`, `$0` through `$9` and `${name}` insert a capture and `$$`
    is a dollar sign.
*/
String Regex.replace(Regex regex, String subject, String replacement) =>
  _rebuild(regex, subject, 0, NULL, replacement);

/** Returns `subject` with every match of `regex` replaced, expanding
    `replacement` as `replace` does.
*/
String Regex.replace_all(Regex regex, String subject, String replacement) =>
  _rebuild(regex, subject, 1, NULL, replacement);

/** Returns `subject` with every match of `regex` replaced by what `fn`
    returns for its `RegexMatch`, inserted as is.
    Raises: whatever `fn` raises.
*/
String Regex.replace_fn(Regex regex, String subject, Func fn) =>
  _rebuild(regex, subject, 1, fn, NULL);

// captures

/** Returns the capture of `found` selected by `key`: a capture number, or
    a name as a `Symbol` or `String`. NULL when there is no such capture.
*/
RegexCapture RegexMatch.capture(RegexMatch found, Var key) {
  int numbered = key.is_integer(), number = numbered ? key : -1;
  String name = numbered ? NULL : key.str();
  foreach (RegexCapture capture in found) {
    if (numbered && capture.index() == number) return capture;
    if (!numbered && capture.name() == name) return capture;
  }
  return NULL;
}

/** Returns the text of the capture selected by `key`, or NULL when the
    capture does not exist or did not take part in the match.
*/
String RegexMatch.getindex(RegexMatch found, Var key) {
  RegexCapture capture = found.capture(key);
  return capture && capture.matched() ? capture.text() : NULL;
}

/** Returns the capture number, with 0 for the whole match. */
int RegexCapture.index(RegexCapture capture) => capture[0].int();

/** Returns the capture's name, or NULL. */
String RegexCapture.name(RegexCapture capture) => capture[1];

/** Reports whether the capture took part in the match. */
int RegexCapture.matched(RegexCapture capture) => !!capture[2];

/** Returns the matched text, or NULL for a capture that did not take part. */
String RegexCapture.text(RegexCapture capture) => capture[3];

/** Returns the byte offset where the capture starts, or -1. */
int RegexCapture.start(RegexCapture capture) => capture[4].int();

/** Returns the byte offset after the capture, or -1. */
int RegexCapture.end(RegexCapture capture) => capture[5].int();

/** Reads a `RegexCapture` back out of a `Var`, as `foreach` does. */
meta native RegexCapture Var.regexcapture(Var v) => (RegexCapture) v.list();

/** Reads a `RegexMatch` back out of a `Var`, as `foreach` does. */
meta native RegexMatch Var.regexmatch(Var value) => (RegexMatch) value.list();
