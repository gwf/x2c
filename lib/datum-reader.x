/*  datum-reader.x -- the Lisp reader grammar

    Copyright (c) 2026 Gary William Flake.

    The one reader grammar for Lisp source and datum text: Lists, reader
    prefixes, Strings, numbers, Symbols, and Atoms. Plain data uses the fast
    path; other forms use the shared Tokenizer's Lisp tokens. `Lisp` and
    `datum.x` both read through it.
*/

#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "tokenizer.x"
#include "scan.x"
#include <limits.h>

/* reader

   The reader turns the shared Tokenizer's Lisp tokens into forms. A form
   whose tokens run out is incomplete, and the reader reports it at the
   form's first token. */

/* Reads the next form into `out` and returns `<value>`, or returns `<eof>`
   when no token remains. `cursor` ends past the form, or at the length of
   `source` at EOF; a failure raises with `cursor` at the form's first
   token. */
Symbol Tokenizer.read_lisp_form(
  Tokenizer t, String source, unsigned base, unsigned &cursor, Var &?out) {
  Token token = t.next();
  if (!token || token.type == <eof>) {
    cursor = source.len();
    return <eof>;
  }
  unsigned start = base + token.pos;
  cursor = start;
  LispReader r = {t, source, base, 0};
  Var form = _parse_form(r, token, 0);
  if (form is void) _incomplete(source, start);
  if (out) out = form;
  cursor = base + r.end;
  return <value>;
}

/* One read over scanned tokens: `source` holds their text from byte `base`,
   and `end` is the offset past the last token a form used. */
static typedef struct LispReader {
  Tokenizer tokenizer, char *source, unsigned base, end;
} LispReader;

/* Elements are read in a loop; only Lists and prefixes add nesting. */
#define LISP_READ_DEPTH_MAX 1024

static int _nested_depth(int depth) {
  if (++depth >= LISP_READ_DEPTH_MAX)
    raise %(size-limit (operation "Lisp.read") (depth $depth));
  return depth;
}

/* The form that starts at `token`, or `void` when the tokens end inside
   it. A form is never `void`. */
static Var _parse_form(LispReader &r, Token token, int depth) {
  if (!token || token.type == <eof>) return void;
  Var prefix = void;
  switch (token.type) {
    case <error>:
      if (r.tokenizer.status() == <incomplete>) return void;
      return _malformed_token(r, token);
    case <")">:  return _malformed_token(r, token);
    case <"(">:  return _list(r, _nested_depth(depth));
    case <"'">:  prefix = Atom.intern("quote");            break;
    case <"`">:  prefix = Atom.intern("quasiquote");       break;
    case <",">:  prefix = Atom.intern("unquote");          break;
    case <",@">: prefix = Atom.intern("unquote-splicing"); break;
  }
  if (prefix is not void) return _prefixed(r, prefix, _nested_depth(depth));
  r.end = token.pos + token.len;
  return _atom(r, token);
}

/* A reader prefix wraps the next form, as `'x` reads `(quote x)`. */
static Var _prefixed(LispReader &r, Var prefix, int depth) {
  Var inner = _parse_form(r, r.tokenizer.next(), depth);
  if (inner is void) return void;
  return $(prefix, inner);
}

/* Starts after `(`; incomplete input returns `void`. */
static Var _list(LispReader &r, int depth) {
  Array elements = auto [];
  loop {
    Token token = r.tokenizer.next();
    if (!token || token.type == <eof>) return void;
    if (token.type == <")">) {
      r.end = token.pos + token.len;
      return elements.list();
    }
    Var element = _parse_form(r, token, depth);
    if (element is void) return void;
    elements.push(element);
  }
}

static Var _atom(LispReader &r, Token token) {
  String text = token.text;
  switch (token.type) {
    case <lit-char*>:
      return String.new_len(text + 1, token.len - 2).unescape();
    case <lit-int>:    return _integer(r, token);
    case <lit-float>:  return _floating(r, token);
    case <lit-symbol>: return _symbol(r, token);
    case <ident>:      return Atom.intern(text.unescape());
  }
  return _malformed_token(r, token);
}

/* Prefer the `int` representation when the parsed number fits. */
static Var _integer(LispReader &r, Token token) {
  long value;
  String literal = String.new_len(token.text, token.len);
  if (!literal.try_long(&value)) return _malformed_token(r, token);
  if (value == (int) value) return (int) value;
  return value;
}

static Var _floating(LispReader &r, Token token) {
  double value, String literal = String.new_len(token.text, token.len);
  if (!literal.try_double(&value)) return _malformed_token(r, token);
  return value;
}

/* Accepts `<name>` and `<"escaped name">`. */
static Var _symbol(LispReader &r, Token token) {
  String text = token.text, int n = token.len;
  String inner = text[1] == '"'
    ? String.new_len(text + 2, n - 4).unescape()
    : String.new_len(text + 1, n - 2);
  if (!inner) return _malformed_token(r, token);
  return Symbol.new(inner);
}

static Var _malformed_token(LispReader &r, Token token) {
  String source = r.source;
  unsigned at = r.base + token.pos;
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(malformed (source $source) (line $line) (column $column));
}

static Var _incomplete(String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(incomplete (source $source) (line $line) (column $column));
}

/* plain spellings

   Lists, Strings, decimal integers, and bare Atoms are read here without
   the Lisp tokenizer, which costs most of an interface read. Each reader
   returns 0 for any other spelling, and the token reader then reads the
   form from its start. `items` holds the elements of the Lists being read. */

static int _plain_form(
  char *s, unsigned &at, Var &out, Array items, int depth) {
  char c = s[at];
  if (c == '(') return _plain_list(s, at, out, items, depth);
  if (c == '"') return _plain_string(s, at, out);
  if (_digit(c) || (c == '-' && _digit(s[at + 1])))
    return _plain_integer(s, at, out);
  return _plain_atom(s, at, out);
}

static int _plain_list(
  char *s, unsigned &at, Var &out, Array items, int depth) {
  if (depth >= LISP_READ_DEPTH_MAX) return 0;
  int first = items.len();
  for (at++; ; ) {
    while (_blank(s[at])) at++;
    if (s[at] == ')') break;
    Var item = void;
    if (!_plain_form(s, at, item, items, depth + 1)) return 0;
    items.push(item);
  }
  at++;
  List list = NULL;
  for (int i = items.len() - 1; i >= first; i--) list = cons(items[i], list);
  items.truncate(first);
  out = list;
  return 1;
}

/* Use the same string scanner as the Lisp tokenizer. */
static int _plain_string(char *s, unsigned &at, Var &out) {
  int length = scan_c_string(s + at);
  if (length < 0 || !_token_end(s[at + length])) return 0;
  out = String.new_len(s + at + 1, length - 2).unescape();
  at += length;
  return 1;
}

/* A decimal integer whose magnitude fits a positive `long`. */
static int _plain_integer(char *s, unsigned &at, Var &out) {
  unsigned end = at + (s[at] == '-');
  if (s[end] == '0' && _digit(s[end + 1])) return 0;
  long value = 0;
  for (; _digit(s[end]); end++) {
    int digit = s[end] - '0';
    if (value > (LONG_MAX - digit) / 10) return 0;
    value = value * 10 + digit;
  }
  if (!_token_end(s[end])) return 0;
  if (s[at] == '-') value = -value;
  if (value == (int) value) out = (int) value;
  else out = value;
  at = end;
  return 1;
}

static int _plain_atom(char *s, unsigned &at, Var &out) {
  int length = 0;
  while (!_token_end(s[at + length])) length++;
  String spelling = String.new_len(s + at, length);
  if (!Atom.bare_spelling(spelling)) return 0;
  out = Atom.intern(spelling);
  at += length;
  return 1;
}

static int _digit(char c) => c >= '0' && c <= '9';

static int _blank(char c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

/* Whether the reader's token ends before `c`. */
static int _token_end(char c) => !c || c == ')' || _blank(c);

/* Scans all of `source` into Lisp tokens whose storage `scope` owns. */
Tokenizer Tokenizer.from_lisp(String source, Scope *scope) {
  Tokenizer tokenizer = NULL;
  auto (scope) {
    tokenizer = Tokenizer.new(source, <lisp>);
    tokenizer.scan();
  }
  return tokenizer;
}

/* Reads one Lisp form, returning `<value>` or `<eof>`. A null source or
   cursor returns `<eof>`. On success, a nonnull `out` receives the form and
   `cursor` advances past it; at EOF, `cursor` reaches the source length.
   Plain spellings use the fast path; other forms use temporary Lisp tokens.
   Result storage follows the caller's Scope and canonical pools.
   Raises: `<incomplete>` or `<malformed>`, with `cursor` at the failing
   form's first token and `out` unchanged, or allocation and depth failures. */
Symbol String.read_lisp_form(String source, unsigned &?cursor, Var &?out) {
  if (!source) return <eof>;
  if (!cursor) return <eof>;
  unsigned base = cursor;
  unsigned at = base;
  while (_blank(source[at])) at++;
  Array items = auto [];
  Var value = void;
  if (source[at] && _plain_form(source, at, value, items, 1)) {
    cursor = at;
    if (out) out = value;
    return <value>;
  }
  Scope tokens_scope = auto Scope.new_named("Lisp tokens");
  Tokenizer tokenizer = Tokenizer.from_lisp(source + base, &tokens_scope);
  return tokenizer.read_lisp_form(source, base, cursor, out);
}
