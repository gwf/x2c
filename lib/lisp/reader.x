/*  reader.x -- Lisp reader

    Copyright (c) 2026 Gary William Flake.
*/

static keyword loop $private.loop;

/* reader

   The reader turns the shared Tokenizer's Lisp tokens into forms. A form
   whose tokens run out is incomplete, and the reader reports it at the
   form's first token. */

/* Reads the next form into `out` and returns `<value>`, or returns `<eof>`
   when no token remains. `cursor` ends past the form, or at the length of
   `source` at EOF; a failure raises with `cursor` at the form's first
   token. */
module Symbol _read_form(
  Tokenizer tokenizer, String source, unsigned base, unsigned &cursor,
  Var &?out) {
  Token token = tokenizer.next();
  if (!token || token.type == <eof>) {
    cursor = source.len();
    return <eof>;
  }
  unsigned start = base + token.pos;
  cursor = start;
  LispReader r = {tokenizer, source, base, 0};
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
    case <"(">:  return _list(r, depth + 1);
    case <"'">:  prefix = lsym_quote;      break;
    case <"`">:  prefix = lsym_quasiquote; break;
    case <",">:  prefix = lsym_unquote;    break;
    case <",@">: prefix = lsym_splicing;   break;
  }
  if (prefix is not void) return _prefixed(r, prefix, depth);
  r.end = token.pos + token.len;
  return _atom(r, token);
}

/* A reader prefix wraps the next form, as `'x` reads `(quote x)`. */
static Var _prefixed(LispReader &r, Var prefix, int depth) {
  Var inner = _parse_form(r, r.tokenizer.next(), depth + 1);
  if (inner is void) return void;
  return %($prefix $inner);
}

/* A form's elements are read in a loop, so only nesting costs a frame.
   The reader fences that nesting instead of exhausting the C stack, which
   on a worker thread is a fraction of the main thread's. */
#define LISP_READ_DEPTH_MAX 1024

/* Starts after `(`; incomplete input returns `void`. */
static Var _list(LispReader &r, int depth) {
  if (depth >= LISP_READ_DEPTH_MAX)
    raise %(size-limit (operation "Lisp.read") (depth $depth));
  Array elements = $auto([]);
  Var out = void;
  loop {
    Token token = r.tokenizer.next();
    if (!token || token.type == <eof>) break;
    if (token.type == <")">) {
      r.end = token.pos + token.len;
      out = elements.list();
      break;
    }
    Var element = _parse_form(r, token, depth);
    if (element is void) break;
    elements.push(element);
  }
  return out;
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

static Var _malformed_token(LispReader &r, Token token) =>
  _malformed(r.source, r.base + token.pos);

static Var _malformed(String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(malformed (source $source) (line $line) (column $column));
}

static Var _incomplete(String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(incomplete (source $source) (line $line) (column $column));
}

module Tokenizer _scan_lisp_tokens(String source, Scope *scope) {
  Tokenizer tokenizer = NULL;
  $scope(scope) {
    tokenizer = Tokenizer.new(source, <lisp>);
    tokenizer.scan();
  }
  return tokenizer;
}

/** Reads one Lisp form and returns `<value>` or `<eof>`.
    A nonnull `out` receives the form only for `<value>`; it is otherwise
    unchanged. New result storage uses the caller's active `Scope` and
    canonical pools, not the temporary token `Scope`, and remains valid
    until those owners are released. On success `cursor` advances past the
    form, at EOF it becomes the source length, and on a reader error it
    identifies the failing form's first token. A null source or cursor
    returns `<eof>` without raising. A nonnull cursor must initially hold a
    byte offset no greater than the source length. A successful session
    construction must first initialize the shared reader names; afterward
    `lisp` is not consulted and may be null.
    Raises: `<incomplete>` for a truncated form, `<malformed>` for invalid
    reader syntax, or `<alloc-fail>`, `<size-limit>`, or `<bad-enc>` while
    tokenizing, constructing, interning, or boxing the form.
*/
Symbol Lisp.read(Lisp lisp, String source, unsigned &?cursor, Var &?out) {
  (void) lisp;
  if (!source) return <eof>;
  if (!cursor) return <eof>;
  unsigned base = cursor;
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source + base, &tokens_scope);
  return _read_form(tokenizer, source, base, cursor, out);
}
