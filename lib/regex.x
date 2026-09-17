/*  regex.x -- regular expressions over the bytes of a String

    Copyright (c) 2026 Gary William Flake

    A Regex is a compiled pattern, owned by the scope that compiled it. A
    RegexMatch and a RegexCapture are immutable Lists, so their Strings and
    offsets stay valid after the next match. Matching backtracks over a
    small node tree; a repeated single byte class runs as a loop, so the
    common `.*` and `\w+` forms do not recurse per byte.

    The syntax is the byte-oriented subset described in the book's
    "Patterns" section: sets, `.`, anchors, word boundaries, greedy and
    lazy repetition, alternation, numbered and named captures, and the
    leading `(?i)`, `(?m)`, and `(?s)` flags.
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

#pragma private

#include <string.h>

enum {
  _SET, _ANY, _BOL, _EOL, _WORDB, _NWORDB, _GROUP, _CAPEND, _ALT, _REPEAT
};

struct _RegexNode {
  int kind;
  unsigned char set[32];
  int index;
  int min, max, greedy;
  _RegexNode child;
  _RegexNode *alts;
  int alt_count;
  _RegexNode next;
};

/* Parsing */

typedef struct {
  Regex regex;
  const char *text;
  int pos, len;
} _Parser;

static void _fail(_Parser *p, String why) {
  String pattern = p->regex.pattern;
  int offset = p->pos;
  raise %(bad-arg (operation "Regex.compile") (why $why)
          (pattern $pattern) (offset $offset));
}

static _RegexNode _node(int kind) {
  _RegexNode node = Scope.calloc(1, sizeof(struct _RegexNode));
  node->kind = kind;
  return node;
}

static void _set_add(_RegexNode node, int byte) {
  node->set[byte >> 3] |= (unsigned char) (1 << (byte & 7));
}

static int _set_has(_RegexNode node, int byte) =>
  node->set[byte >> 3] & (1 << (byte & 7));

static void _set_range(_RegexNode node, int low, int high) {
  for (int byte = low; byte <= high; byte++) _set_add(node, byte);
}

static int _is_word(int byte) =>
  byte == '_' || (byte >= '0' && byte <= '9') ||
  (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z');

/* Adds the bytes of `\d`, `\w`, or `\s` to `node`, or every other byte
   for the capital letter. */
static void _set_class(_RegexNode node, int letter) {
  struct _RegexNode members = {0};
  int negate = letter == 'D' || letter == 'W' || letter == 'S';
  if (negate) letter += 'a' - 'A';
  if (letter == 'd') _set_range(&members, '0', '9');
  if (letter == 'w') {
    for (int byte = 0; byte < 256; byte++)
      if (_is_word(byte)) _set_add(&members, byte);
  }
  if (letter == 's') {
    _set_add(&members, ' ');
    _set_range(&members, '\t', '\r');
  }
  for (int i = 0; i < 32; i++)
    node->set[i] |= negate ? (unsigned char) ~members.set[i] : members.set[i];
}

static void _set_fold(_RegexNode node) {
  for (int byte = 'a'; byte <= 'z'; byte++) {
    int upper = byte - 'a' + 'A';
    if (_set_has(node, byte) || _set_has(node, upper)) {
      _set_add(node, byte);
      _set_add(node, upper);
    }
  }
}

/* Reads one escaped byte after the backslash, or a class letter, which is
   returned as its negative letter code. `in_class` refuses `\b`. */
static int _escape(_Parser *p, int in_class) {
  if (p->pos >= p->len) _fail(p, "pattern ends in a backslash");
  int byte = (unsigned char) p->text[p->pos++];
  switch (byte) {
    case 't': return '\t';
    case 'n': return '\n';
    case 'r': return '\r';
    case 'f': return '\f';
    case 'v': return '\v';
    case '0': return 0;
    case 'd': case 'D': case 'w': case 'W': case 's': case 'S':
      return -byte;
    case 'b': case 'B':
      if (in_class) break;
      return -byte;
    default:
      if (!_is_word(byte) && byte < 128) return byte;
      break;
  }
  p->pos--;
  _fail(p, "unknown escape");
  return 0;
}

static _RegexNode _class(_Parser *p) {
  _RegexNode node = _node(_SET);
  int negate = 0, first = 1;
  if (p->pos < p->len && p->text[p->pos] == '^') {
    negate = 1;
    p->pos++;
  }
  for (;;) {
    if (p->pos >= p->len) _fail(p, "unterminated character class");
    int byte = (unsigned char) p->text[p->pos++];
    if (byte == ']' && !first) break;
    first = 0;
    if (byte == '\\') {
      byte = _escape(p, 1);
      if (byte < 0) {
        _set_class(node, -byte);
        continue;
      }
    }
    if (p->pos + 1 < p->len && p->text[p->pos] == '-' &&
        p->text[p->pos + 1] != ']') {
      p->pos++;
      int high = (unsigned char) p->text[p->pos++];
      if (high == '\\') high = _escape(p, 1);
      if (high < byte) _fail(p, "character range out of order");
      _set_range(node, byte, high);
    }
    else {
      _set_add(node, byte);
    }
  }
  if (p->regex.caseless) _set_fold(node);
  if (negate)
    for (int i = 0; i < 32; i++) node->set[i] = (unsigned char) ~node->set[i];
  return node;
}

static _RegexNode _alternation(_Parser *p);

static _RegexNode _group(_Parser *p) {
  int index = -1;
  String name = NULL;
  if (p->pos + 1 < p->len && p->text[p->pos] == '?') {
    if (p->text[p->pos + 1] == ':') {
      p->pos += 2;
    }
    else if (p->text[p->pos + 1] == '<') {
      p->pos += 2;
      int start = p->pos;
      while (p->pos < p->len && _is_word((unsigned char) p->text[p->pos]))
        p->pos++;
      int digit = p->text[start] >= '0' && p->text[start] <= '9';
      if (p->pos == start || digit || p->pos >= p->len ||
          p->text[p->pos] != '>') {
        p->pos = start;
        _fail(p, "malformed group name");
      }
      name = String.new_len(p->text + start, p->pos - start);
      p->pos++;
      index = ++p->regex.capture_count;
    }
    else {
      _fail(p, "unknown group syntax");
    }
  }
  else {
    index = ++p->regex.capture_count;
  }
  if (index > 0)
    p->regex.capture_names = p->regex.capture_names.append(%($name));
  _RegexNode node = _node(_GROUP);
  node->index = index;
  node->child = _alternation(p);
  if (p->pos >= p->len || p->text[p->pos] != ')')
    _fail(p, "missing closing parenthesis");
  p->pos++;
  if (index < 0) return node;
  _RegexNode end = _node(_CAPEND);
  end->index = index;
  if (!node->child) {
    node->child = end;
  }
  else {
    _RegexNode last = node->child;
    while (last->next) last = last->next;
    last->next = end;
  }
  return node;
}

static int _digits(_Parser *p, int *out) {
  int start = p->pos, value = 0;
  while (p->pos < p->len && p->text[p->pos] >= '0' && p->text[p->pos] <= '9')
    value = value * 10 + (p->text[p->pos++] - '0');
  *out = value;
  return p->pos > start;
}

/* Reads `{m}`, `{m,}`, or `{m,n}` after the brace. Leaves the position
   unchanged and returns 0 when the brace is not a repetition. */
static int _braces(_Parser *p, int *min, int *max) {
  int start = p->pos;
  if (!_digits(p, min)) {
    p->pos = start;
    return 0;
  }
  *max = *min;
  if (p->pos < p->len && p->text[p->pos] == ',') {
    p->pos++;
    if (!_digits(p, max)) *max = -1;
  }
  if (p->pos >= p->len || p->text[p->pos] != '}') {
    p->pos = start;
    return 0;
  }
  p->pos++;
  if (*max >= 0 && *max < *min) _fail(p, "repetition range out of order");
  return 1;
}

static _RegexNode _quantify(_Parser *p, _RegexNode atom, int min, int max) {
  if (!atom || atom->kind == _BOL || atom->kind == _EOL ||
      atom->kind == _WORDB || atom->kind == _NWORDB)
    _fail(p, "nothing to repeat");
  _RegexNode node = _node(_REPEAT);
  node->min = min;
  node->max = max;
  node->greedy = 1;
  node->child = atom;
  if (p->pos < p->len && p->text[p->pos] == '?') {
    node->greedy = 0;
    p->pos++;
  }
  return node;
}

static _RegexNode _sequence(_Parser *p) {
  _RegexNode head = NULL, last = NULL, prev = NULL;
  while (p->pos < p->len) {
    int byte = (unsigned char) p->text[p->pos];
    if (byte == '|' || byte == ')') break;
    p->pos++;
    _RegexNode atom = NULL;
    int min = -2, max = -1;
    switch (byte) {
      case '*': min = 0; break;
      case '+': min = 1; break;
      case '?': min = 0; max = 1; break;
      case '{':
        if (!_braces(p, &min, &max)) {
          min = -2;
          atom = _node(_SET);
          _set_add(atom, '{');
        }
        break;
      case '.':
        atom = _node(_ANY);
        break;
      case '^':
        atom = _node(_BOL);
        break;
      case '$':
        atom = _node(_EOL);
        break;
      case '[':
        atom = _class(p);
        break;
      case '(':
        atom = _group(p);
        break;
      case '\\': {
        int escaped = _escape(p, 0);
        if (escaped == -'b') atom = _node(_WORDB);
        else if (escaped == -'B') atom = _node(_NWORDB);
        else {
          atom = _node(_SET);
          if (escaped < 0) _set_class(atom, -escaped);
          else _set_add(atom, escaped);
          if (p->regex.caseless) _set_fold(atom);
        }
        break;
      }
      default:
        atom = _node(_SET);
        _set_add(atom, byte);
        if (p->regex.caseless) _set_fold(atom);
        break;
    }
    if (min != -2) {
      _RegexNode repeated = _quantify(p, last, min, max);
      last->next = NULL;
      if (prev) prev->next = repeated;
      else head = repeated;
      last = repeated;
      continue;
    }
    if (last) last->next = atom;
    else head = atom;
    prev = last;
    last = atom;
  }
  return head;
}

static _RegexNode _alternation(_Parser *p) {
  _RegexNode first = _sequence(p);
  if (p->pos >= p->len || p->text[p->pos] != '|') return first;
  _RegexNode node = _node(_ALT);
  int capacity = 4;
  node->alts = Scope.calloc(capacity, sizeof(_RegexNode));
  node->alts[node->alt_count++] = first;
  while (p->pos < p->len && p->text[p->pos] == '|') {
    p->pos++;
    if (node->alt_count == capacity) {
      _RegexNode *grown = Scope.calloc(capacity * 2, sizeof(_RegexNode));
      memcpy(grown, node->alts, capacity * sizeof(_RegexNode));
      node->alts = grown;
      capacity *= 2;
    }
    node->alts[node->alt_count++] = _sequence(p);
  }
  return node;
}

static void _flags(_Parser *p) {
  if (p->len < 4 || p->text[0] != '(' || p->text[1] != '?') return;
  int at = 2;
  while (at < p->len && strchr("ims", p->text[at])) {
    if (p->text[at] == 'i') p->regex.caseless = 1;
    if (p->text[at] == 'm') p->regex.multiline = 1;
    if (p->text[at] == 's') p->regex.dotall = 1;
    at++;
  }
  if (at > 2 && at < p->len && p->text[at] == ')') p->pos = at + 1;
}

/* Matching */

typedef struct _Cont {
  int repeat;
  _RegexNode node;
  int count, start;
  struct _Cont *up;
} _Cont;

typedef struct {
  Regex regex;
  const char *text;
  int len, end, depth;
  int *starts, *ends;
} _State;

/* Each iteration of a repeated group is a C frame, so a match bounds them
   before the stack runs out, on any thread. */
static const int _DEPTH_LIMIT = 2000;

static int _run(_State *st, _RegexNode n, int pos, _Cont *k);

static int _iterate_from(_State *st, _RegexNode rep, int count, int pos,
                         int last_start, _Cont *k);

static int _iterate(_State *st, _RegexNode rep, int count, int pos,
                    int last_start, _Cont *k) {
  if (st->depth == _DEPTH_LIMIT) {
    String pattern = st->regex.pattern;
    raise %(size-limit (operation "Regex.match") (pattern $pattern)
            (why "a group repeated more times than one match allows")
            (limit $_DEPTH_LIMIT));
  }
  st->depth++;
  int matched = _iterate_from(st, rep, count, pos, last_start, k);
  st->depth--;
  return matched;
}

static int _iterate_from(_State *st, _RegexNode rep, int count, int pos,
                         int last_start, _Cont *k) {
  if (count > 0 && pos == last_start && count >= rep->min)
    return _run(st, rep->next, pos, k);
  int more = rep->max < 0 || count < rep->max;
  _Cont again = {1, rep, count, pos, k};
  if (count < rep->min) return _run(st, rep->child, pos, &again);
  if (rep->greedy) {
    if (more && _run(st, rep->child, pos, &again)) return 1;
    return _run(st, rep->next, pos, k);
  }
  if (_run(st, rep->next, pos, k)) return 1;
  return more && _run(st, rep->child, pos, &again);
}

static int _single(_State *st, _RegexNode n, int pos) {
  if (pos >= st->len) return 0;
  int byte = (unsigned char) st->text[pos];
  if (n->kind == _ANY) return st->regex.dotall || byte != '\n';
  return _set_has(n, byte) != 0;
}

/* A repeated byte class needs no continuation per iteration: count the
   longest run, then offer the ends in greedy or lazy order. */
static int _run_loop(_State *st, _RegexNode rep, int pos, _Cont *k) {
  int limit = rep->max < 0 ? st->len - pos : rep->max, count = 0;
  while (count < limit && _single(st, rep->child, pos + count)) count++;
  if (count < rep->min) return 0;
  if (rep->greedy) {
    for (int n = count; n >= rep->min; n--)
      if (_run(st, rep->next, pos + n, k)) return 1;
    return 0;
  }
  for (int n = rep->min; n <= count; n++)
    if (_run(st, rep->next, pos + n, k)) return 1;
  return 0;
}

static int _at_boundary(_State *st, int pos) {
  int before = pos > 0 && _is_word((unsigned char) st->text[pos - 1]);
  int after = pos < st->len && _is_word((unsigned char) st->text[pos]);
  return before != after;
}

static int _run(_State *st, _RegexNode n, int pos, _Cont *k) {
  while (n) {
    switch (n->kind) {
      case _SET:
      case _ANY:
        if (!_single(st, n, pos)) return 0;
        pos++;
        break;
      case _BOL:
        if (pos != 0 &&
            !(st->regex.multiline && st->text[pos - 1] == '\n')) return 0;
        break;
      case _EOL:
        if (pos != st->len &&
            !(st->regex.multiline && st->text[pos] == '\n')) return 0;
        break;
      case _WORDB:
        if (!_at_boundary(st, pos)) return 0;
        break;
      case _NWORDB:
        if (_at_boundary(st, pos)) return 0;
        break;
      case _GROUP: {
        _Cont after = {0, n->next, 0, 0, k};
        if (n->index < 0) return _run(st, n->child, pos, &after);
        int old_start = st->starts[n->index], old_end = st->ends[n->index];
        st->starts[n->index] = pos;
        if (_run(st, n->child, pos, &after)) return 1;
        st->starts[n->index] = old_start;
        st->ends[n->index] = old_end;
        return 0;
      }
      case _CAPEND: {
        int old_end = st->ends[n->index];
        st->ends[n->index] = pos;
        if (_run(st, n->next, pos, k)) return 1;
        st->ends[n->index] = old_end;
        return 0;
      }
      case _ALT: {
        _Cont after = {0, n->next, 0, 0, k};
        for (int i = 0; i < n->alt_count; i++)
          if (_run(st, n->alts[i], pos, &after)) return 1;
        return 0;
      }
      case _REPEAT:
        if (n->child->kind == _SET || n->child->kind == _ANY)
          return _run_loop(st, n, pos, k);
        return _iterate(st, n, 0, pos, -1, k);
    }
    n = n->next;
  }
  if (!k) {
    st->end = pos;
    return 1;
  }
  if (k->repeat)
    return _iterate(st, k->node, k->count + 1, pos, k->start, k->up);
  return _run(st, k->node, pos, k->up);
}

static RegexCapture _capture(Regex regex, String subject, int index,
                             int start, int end) {
  int matched = start >= 0 && end >= 0;
  String name = index ? regex.capture_names[index - 1] : NULL;
  String text = matched ? String.new_len(subject + start, end - start) : NULL;
  int first = matched ? start : -1, last = matched ? end : -1;
  return %($index $name $matched $text $first $last);
}

static RegexMatch _search(Regex regex, String subject, int offset) {
  int count = regex.capture_count + 1;
  int starts[count], ends[count];
  _State st = {regex, subject ? subject : "", subject.len(), 0, 0,
               starts, ends};
  for (int at = offset; at <= st.len; at++) {
    for (int i = 0; i < count; i++) starts[i] = ends[i] = -1;
    if (!_run(&st, regex.program, at, NULL)) continue;
    starts[0] = at;
    ends[0] = st.end;
    List captures = NULL;
    for (int i = count - 1; i >= 0; i--)
      captures = cons(_capture(regex, subject, i, starts[i], ends[i]),
                      captures);
    return (RegexMatch) captures;
  }
  return NULL;
}

static int _whole_start(RegexMatch found) => found.car().list()[4].int();
static int _whole_end(RegexMatch found) => found.car().list()[5].int();

static void _write(Buffer out, String text) {
  if (text) out.write(text);
}

static String _expand(Regex regex, RegexMatch found, String replacement) {
  Buffer out = Buffer.new(0);
  int n = replacement.len();
  for (int i = 0; i < n; i++) {
    char byte = replacement[i];
    if (byte != '$' || i + 1 >= n) {
      out.write_char(byte);
      continue;
    }
    char next = replacement[i + 1];
    if (next == '$') {
      out.write_char('$');
      i++;
    }
    else if (next >= '0' && next <= '9') {
      _write(out, found[next - '0']);
      i++;
    }
    else if (next == '{') {
      int close = replacement.find_within("}", i + 2, -1);
      if (close < 0) {
        out.write_char(byte);
        continue;
      }
      _write(out, found[replacement[i + 2:close]]);
      i = close;
    }
    else {
      out.write_char(byte);
    }
  }
  return out.str();
}

static String _rebuild(Regex regex, String subject, int limit, Func fn,
                       String replacement) {
  Buffer out = Buffer.new(0);
  int cursor = 0, done = 0;
  foreach (RegexMatch found, regex.find_all(subject)) {
    if (limit >= 0 && done == limit) break;
    _write(out, subject[cursor:_whole_start(found)]);
    _write(out, fn ? fn(found).str() : _expand(regex, found, replacement));
    cursor = _whole_end(found);
    done++;
  }
  _write(out, subject[cursor:]);
  return out.str();
}

static Regex Regex.new(String pattern) {
  Regex regex = Scope.calloc(1, sizeof(struct Regex));
  regex.pattern = pattern ? pattern : "";
  _Parser p = {regex, regex.pattern, 0, regex.pattern.len()};
  _flags(&p);
  regex.program = _alternation(&p);
  if (p.pos < p.len) _fail(&p, "unmatched closing parenthesis");
  return regex;
}

#pragma public

/** Compiles `pattern` and returns the `Regex`, owned by the current scope.
    Raises: `<bad-arg>` with `why`, the `pattern`, and the byte `offset`
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
  Buffer out = Buffer.new(0);
  int n = literal.len();
  for (int i = 0; i < n; i++) {
    int byte = (unsigned char) literal[i];
    if (byte < 128 && !_is_word(byte)) out.write_char('\\');
    out.write_char((char) byte);
  }
  return out.str();
}

/** Returns the first match of `regex` in `subject` at or after the byte
    `offset`, or NULL. An offset beyond the end of `subject` finds nothing.
*/
RegexMatch Regex.match_from(Regex regex, String subject, int offset) =>
  offset < 0 || offset > subject.len() ? NULL
                                       : _search(regex, subject, offset);

/** Returns the first match of `regex` in `subject`, or NULL. */
RegexMatch Regex.match(Regex regex, String subject) =>
  _search(regex, subject, 0);

/** Returns every non-overlapping match of `regex` in `subject`, in order.
    An empty match advances one byte. No match returns an empty `List`.
*/
List Regex.find_all(Regex regex, String subject) {
  List found = NULL;
  int len = subject.len(), at = 0;
  while (at <= len) {
    RegexMatch next = _search(regex, subject, at);
    if (!next) break;
    found = cons(next, found);
    int end = _whole_end(next);
    at = end > _whole_start(next) ? end : end + 1;
  }
  return found.reverse();
}

/** Returns the text of `subject` between the matches of `regex`, keeping
    an empty field where two matches touch or a match sits at either end.
*/
List Regex.split(Regex regex, String subject) {
  List parts = NULL;
  int cursor = 0;
  foreach (RegexMatch found, regex.find_all(subject)) {
    parts = cons(subject[cursor:_whole_start(found)], parts);
    cursor = _whole_end(found);
  }
  parts = cons(subject[cursor:], parts);
  return parts.reverse();
}

/** Returns `subject` with the first match of `regex` replaced. In
    `replacement`, `$0` through `$9` and `${name}` insert a capture and `$$`
    is a dollar sign.
*/
String Regex.replace(Regex regex, String subject, String replacement) =>
  _rebuild(regex, subject, 1, NULL, replacement);

/** Returns `subject` with every match of `regex` replaced, expanding
    `replacement` as `replace` does.
*/
String Regex.replace_all(Regex regex, String subject, String replacement) =>
  _rebuild(regex, subject, -1, NULL, replacement);

/** Returns `subject` with every match of `regex` replaced by what `fn`
    returns for its `RegexMatch`, inserted as is.
    Raises: whatever `fn` raises.
*/
String Regex.replace_fn(Regex regex, String subject, Func fn) =>
  _rebuild(regex, subject, -1, fn, NULL);

/** Returns the capture of `found` selected by `key`: a capture number, or
    a name as a `Symbol` or `String`. NULL when there is no such capture.
*/
RegexCapture RegexMatch.capture(RegexMatch found, Var key) {
  int numbered = key.is_integer(), number = numbered ? key.int() : -1;
  String name = numbered ? NULL : key.str();
  foreach (RegexCapture capture, found) {
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
int RegexCapture.index(RegexCapture capture) => capture.getindex(0).int();

/** Returns the capture's name, or NULL. */
String RegexCapture.name(RegexCapture capture) => capture.getindex(1).string();

/** Reports whether the capture took part in the match. */
int RegexCapture.matched(RegexCapture capture) => capture.getindex(2).truth();

/** Returns the matched text, or NULL for a capture that did not take part. */
String RegexCapture.text(RegexCapture capture) => capture.getindex(3).string();

/** Returns the byte offset where the capture starts, or -1. */
int RegexCapture.start(RegexCapture capture) => capture.getindex(4).int();

/** Returns the byte offset just past the capture, or -1. */
int RegexCapture.end(RegexCapture capture) => capture.getindex(5).int();

/** Reads a `RegexCapture` back out of a `Var`, as `foreach` does. */
RegexCapture Var.regexcapture(Var value) => (RegexCapture) value.list();

/** Reads a `RegexMatch` back out of a `Var`, as `foreach` does. */
RegexMatch Var.regexmatch(Var value) => (RegexMatch) value.list();
