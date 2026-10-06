/*  tokenizer.x -- shared tokenizer built on character-level scanners

    Copyright (c) 2025 Gary William Flake.

    Tokenizer delegates character recognition to scan.x and tracks position,
    nested code/list/array/string/Lisp modes, and the resulting token stream.
    It borrows source bytes only while scanning; token text is copied into
    canonical `String`s. Line and column coordinates are one-based; `pos` is a
    zero-based byte offset. Consumers iterate the contiguous token storage only
    after scanning completes, when Token pointers become stable. A scanner
    failure appends <error> and <eof> so the stream always terminates.
*/
#pragma once
#include "x2c.x"

/* Describes one token in Tokenizer-owned contiguous storage.
   A Token pointer is borrowed and stable only after scanning finishes. Its
   text is a canonical copy whose String pool controls its lifetime. */
typedef struct Token {
  String text, Symbol type, int line, col, len, pos;
} *Token;

/* Holds one scope-owned, one-shot tokenization and its traversal cursor.
   `text` is borrowed through `Tokenizer.scan`; tokens and modes remain live
   until their owning Scope is released. A nonzero `layout` selects the
   indentation syntax; `#pragma indent` before the first line of code sets
   it during the scan. */
class Tokenizer struct {
  Bytes tokens, char *text, Array modes, struct Token *cursor;
  Symbol scan_status, int line, col, pos, layout;
} *;

#include "exception.x"
#include <string.h>

inline Token Var.token(Var x) => x.pointer();

/* Wraps a borrowed Token pointer without extending its storage lifetime. */
inline Var Token.var(Token x) => Var.new(<token>, x);

/* This adoption stays local while its descriptor registers globally. */
static protocol Var(Token);

/* Hashes a live Token's complete representation; it must be nonnull. */
unsigned Token.hash(Token t) => x2c_hash_bytes(0, t, sizeof(struct Token));

/* Compares bytes; two null Tokens are equal. */
int Token.equal(Token a, Token b) {
  if ((void *) a == (void *) b) return 1;
  if (!a || !b) return 0;
  return memcmp(a, b, sizeof(struct Token)) == 0;
}

/* Returns a live Token's borrowed canonical text. */
String Token.str(Token token) => token.text;

/* Returns a canonical rendering of a live Token and all source coordinates.
   The result follows the active String pool chain and remains live until its
   owning pool is released.
   Raises: `<alloc-fail>` or `<size-limit>` while rendering. */
String Token.repr(Token token) {
  String head = %"{{text:${token}, type:${token.type}";
  String location = %"line:${token.line}, col:${token.col}";
  String extent = %"len:${token.len}, pos:${token.pos}";
  return %"$head, $location, $extent}}";
}

// scanning

/* Scans the borrowed input once and completes the contiguous token stream.
   Success appends `<eof>`; lexical failure records its first status, then
   appends `<error>` and `<eof>`. Token text no longer depends on the source.
   Consumers must not rescan or append after beginning Token pointer traversal.
   Raises: `<alloc-fail>` or `<size-limit>` while storing tokens or modes. */
void Tokenizer.scan(Tokenizer t) {
  while (!t._end_of_file()) {
    if (t._step()) continue;
    t.error();
    return;
  }
  if (t.layout) t._layout();
}

/* Scans one token in the current mode, or returns zero. */
static int Tokenizer._step(Tokenizer t) {
  switch (t._scan_mode()) {
    case <x2c>: case <x2c-par>: return t._x2c_tokens();
    case <array>: case <map>: case <list>: case <lisp>: case <macro-lisp>:
      return t._lisp_tokens();
    case <symbol-set>: return t._common_tokens() || t._symbol_set_tokens();
    case <string>: return t._string_tokens();
  }
  return 0;
}

/* NUL always ends tokenization, even in a nested mode. The parser or Lisp
   reader, not this lexical layer, diagnoses a missing closing delimiter. */
static int Tokenizer._end_of_file(Tokenizer t) {
  if (t.text[t.pos] == '\0') return t.tokenize(0, <eof>);
  return 0;
}

/* x2c code tries C trivia and numbers, `$` forms, `%` and `<` literals, then
   C strings, identifiers, and operators. */
static int Tokenizer._x2c_tokens(Tokenizer t) =>
  t._common_tokens() ||
  (t.text[t.pos] == '$' && (t._embedded_lisp() || t._named_reference())) ||
  t._percent_tokens() || t._angle_symbol_literal() || t._c_tokens();

static int Tokenizer._common_tokens(Tokenizer t) {
  char *text = t.text + t.pos;
  switch (text[0]) {
    case ' ': case '\t': case '\v': case '\f': case '\n': case '\r':
      return t.do_scanner(scan_white_space, <space>);
    case '#': return t._preprocessor();
    case '/':
      if (text[1] == '/') return t.do_scanner(scan_line_comment, <comment>);
      if (text[1] == '*')
        return _status_scanner(t, scan_block_comment_status, <comment>);
      return 0;
    case '\'': return t.do_scanner(scan_c_character, <lit-char>);
    case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9':
      return t._number();
    case '.':
      if (scan_ascii_digit((unsigned char) text[1])) return t._number();
  }
  return 0;
}

/* Scans one directive. `#pragma indent` before the first line of code
   selects the indentation syntax. */
static int Tokenizer._preprocessor(Tokenizer t) {
  if (!t.do_scanner(scan_preprocessor, <preproc>)) return 0;
  Token directive = _significant_back(t, 0), before = directive;
  if (t.layout || !directive.text.startswith("#pragma indent") ||
      directive.text.strip(" \t\r\n") != "#pragma indent")
    return 1;
  while ((before = _significant_before(t, before)) &&
         before.type == <preproc>) { }
  if (!before) t.layout = 1;
  return 1;
}

static int Tokenizer._number(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos, Symbol type;
  int len = scan_number_typed(text, &type);
  if (len < 0) return _error(tokenizer, <malformed>);
  if (len == 0) return 0;
  type = (type == <int>) ? <lit-int> : <lit-float>;
  return tokenizer.tokenize(len, type);
}

/* Enter file-scoped compile-time Lisp until its closing parenthesis. */
static int Tokenizer._embedded_lisp(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos;
  if (text[0] != '$' || text[1] != '(') return 0;
  return tokenizer._operator(2);
}

/* Consume the sigil before calling scan_identifier, whose input must begin
   with an identifier character. */
static int Tokenizer._named_reference(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos;
  tokenizer._operator(1);
  if (text[1] == '_' || scan_ascii_alpha((unsigned char) text[1]))
    return tokenizer.do_scanner(scan_identifier, <ident>);
  return 1;
}

static int Tokenizer._percent_tokens(Tokenizer t) {
  char *text = t.text + t.pos;
  if (text[0] != '%' || !text[1]) return 0;
  char next = text[1];
  /* `%!` is one lambda-prefix token unless operand context makes `%` the
     modulo operator. The parser owns the following parameters and `=>`. */
  if (next == '!') {
    if (_percent_is_operator(t)) return t._operator(1);
    return t.tokenize(2, Symbol.new_len(text, 2));
  }
  if (!strchr("([{<\"", next)) return 0;
  /* Modulo of a string literal is never valid, and neither `[` nor `<<`
     begins an operand, so these literals open after any token. */
  int quoted = next == '"' || next == '[' || (next == '<' && text[2] == '<');
  if (!quoted && _percent_is_operator(t)) return t._operator(1);
  if (next == '<' && text[2] != '<') return t.error();
  return t._operator(next == '<' ? 3 : 2);
}

static int Tokenizer._angle_symbol_literal(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos;
  if (text[0] != '<' || !_can_start_symbol_literal(tokenizer)) return 0;
  int len = scan_symbol_literal(text);
  if (len > 0) return tokenizer.tokenize(len, <lit-symbol>);
  if (len < 0) return tokenizer.error();
  return 0;
}

static int Tokenizer._c_tokens(Tokenizer tokenizer) {
  static const char *opchars = "-,;:!?.()[]{}*/&%^+<=>|~@";
  char *text = tokenizer.text + tokenizer.pos, int n;
  if (text[0] == '"')
    return _status_scanner(tokenizer, scan_c_string_status, <lit-char*>);
  if (text[0] == '_' || scan_ascii_alpha((unsigned char) text[0])) {
    n = scan_identifier(text);
    Symbol type = scan_keyword_type(text, n);
    return tokenizer.tokenize(n, type ? type : <ident>);
  }
  if (strchr(opchars, text[0]) && (n = scan_c_operator(text)) > 0)
    return tokenizer._operator(n);
  return 0;
}

/* Lisp source and data literals share Atom scanning. The mode decides which
   delimiters nest data, which punctuation terminates an Atom, and whether
   `$` escapes into x2c. A collection reads C tokens first; Lisp text claims
   quote characters and signed numbers before the C scanners can. */
static int Tokenizer._lisp_tokens(Tokenizer t) {
  Symbol mode = t._scan_mode();
  int list = mode == <list>, collection = mode == <array> || mode == <map>;
  if (collection && t._common_tokens()) return 1;
  if (t._lisp_prefix(list, collection)) return 1;
  int punctuation = t._lisp_punctuation(list, collection);
  if (punctuation >= 0) return punctuation;
  if (collection) return t._collection_atom();
  if (t._common_tokens()) return 1;
  return _status_scanner(t, scan_atom_status, list ? <lit-atom> : <ident>);
}

/* A token its first characters decide: `void` in a collection, a list's
   `?(` capture and bare `@` operator atom, and the `$` and `@` escapes into
   x2c. Lisp source escapes only `$name`, and a collection splices only
   with `$`. */
static int Tokenizer._lisp_prefix(Tokenizer t, int list, int collection) {
  char *text = t.text + t.pos;
  if (collection && !strncmp(text, "void", 4) && scan_identifier(text) == 4)
    return t.tokenize(4, <void>);
  if (list && text[0] == '?' && text[1] == '(') return t._operator(2);
  if (text[0] == '$' && !list && !collection) return t._named_reference();
  /* A bare `@` or `@=` in a list is the operator atom, so an AST literal
     or match pattern can spell `%(op @ a b)`; `@name` and `@{` splice. */
  if (list && text[0] == '@' &&
      (!text[1] || text[1] == '=' || strchr(" \t\n\v\f\r)", text[1])))
    return t.tokenize(text[1] == '=' ? 2 : 1, <lit-atom>);
  if ((list && (text[0] == '$' || text[0] == '@')) ||
      (collection && text[0] == '$'))
    return text[1] == '{' ? t._operator(2) : t._named_reference();
  return 0;
}

/* Punctuation in Lisp-shaped text, or -1 when the character is not
   punctuation in this mode. Lists and collections nest strings, arrays,
   and maps; only a collection ends an atom at `]`, `}`, `:`, or `,`. */
static int Tokenizer._lisp_punctuation(
  Tokenizer t, int list, int collection) {
  char *text = t.text + t.pos;
  int data = list || collection;
  switch (text[0]) {
    case '(': case ')': return t._operator(1);
    case '"':
      if (data) return t._operator(1);
      return _status_scanner(t, scan_c_string_status, <lit-char*>);
    case '{': case '[': if (data) return t._operator(1);
      break;
    case ']': case '}': case ':': if (collection) return t._operator(1);
      break;
    case '\'': case '`': return t.tokenize(1, Symbol.new_len(text, 1));
    case ',': {
      if (collection) return t._operator(1);
      int len = text[1] == '@' ? 2 : 1;
      return t.tokenize(len, Symbol.new_len(text, len));
    }
    case '<': return t._lisp_symbol();
    case '+': case '-':
      if (scan_ascii_digit((unsigned char) text[1])) return t._number();
      break;
  }
  return -1;
}

/* A Symbol literal, or -1 when `<` is an operator atom here. */
static int Tokenizer._lisp_symbol(Tokenizer t) {
  char *text = t.text + t.pos;
  if (!text[1] || text[1] == '=' || strchr("()'`, \n\t\v\f\r", text[1]))
    return -1;
  Symbol status = <ok>;
  int length = scan_symbol_literal_status(text, &status);
  if (length > 0) return t.tokenize(length, <lit-symbol>);
  if (length < 0) return _error(t, status);
  return -1;
}

/* Scans up to an unescaped `,`, `:`, `]`, or `}`. */
static int Tokenizer._collection_atom(Tokenizer t) {
  char *text = t.text + t.pos;
  Symbol status = <ok>;
  int len = scan_atom_status(text, &status);
  if (len < 0) return _error(t, status);
  for (int i = 0; i < len; i++) {
    if (text[i] == '\\') i++;
    else if (strchr(",:]}", text[i])) {
      len = i;
      break;
    }
  }
  return len ? t.tokenize(len, <lit-atom>) : 0;
}

static int Tokenizer._symbol_set_tokens(Tokenizer t) {
  char *text = t.text + t.pos;
  if (text[0] == '>' && text[1] == '>') return t._operator(2);
  if (text[0] == '$' || text[0] == '@') return t._operator(1);
  if (text[0] == '<') {
    int length = scan_symbol_literal(text);
    if (length > 0) return t.tokenize(length, <lit-symbol>);
    if (length < 0) return t.error();
  }
  return t.do_scanner(scan_symbol_set_atom, <lit-atom>);
}

static int Tokenizer._string_tokens(Tokenizer t) {
  char *text = t.text + t.pos;
  if (text[0] == '$')
    return text[1] == '{'
         ? t._operator(2)
         : t._named_reference();
  if (text[0] == '"')  return t._operator(1);
  int len = scan_string_segment(text);
  if (len < 0) return t.error();
  return t.tokenize(len, <segment>);
}

// token output

/* Copies the next `len` source bytes into one token, appends it, advances the
   zero-based byte position and one-based line and column, and returns one.
   `len` must fit the remaining source. State advances only after token storage
   is installed.
   Raises: `<alloc-fail>` or `<size-limit>` while copying or appending. */
int Tokenizer.tokenize(Tokenizer t, int len, Symbol type) {
  String text = String.new_len(t.text + t.pos, len);
  struct Token tok = {
    .type = type, .len = len, .text = text,
    .line = t.line, .col = t.col, .pos = t.pos
  };
  t.tokens = t.tokens.append(&tok, 1);
  scan_next_line_col(t.text + t.pos, len, &t.line, &t.col);
  t.pos += len;
  return 1;
}

/* Invokes one non-retained scanner at the current source byte. `scanner` must
   be nonnull. A positive length appends `type`, zero makes no progress, and
   -1 records a malformed token stream. A cause from the callback or token
   append does not return here. */
int Tokenizer.do_scanner(Tokenizer t, int (*scanner)(char *), Symbol type) {
  int len = scanner(t.text + t.pos);
  if (len > 0) return t.tokenize(len, type);
  if (len < 0) return t.error();
  return 0;
}

/* Preserve a status-bearing scanner's lexical classification for readers. */
static int _status_scanner(
  Tokenizer tokenizer, int (*scanner)(char *, Symbol *), Symbol type) {
  Symbol status = <ok>;
  int len = scanner(tokenizer.text + tokenizer.pos, &status);
  if (len > 0) return tokenizer.tokenize(len, type);
  if (len < 0) return _error(tokenizer, status);
  return 0;
}

/* Records the first lexical failure as `<malformed>`, appends zero-width
   `<error>` and `<eof>` sentinels at the current position, and returns zero.
   Raises: `<alloc-fail>` or `<size-limit>` while appending. */
int Tokenizer.error(Tokenizer tokenizer) => _error(tokenizer, <malformed>);

static int _error(Tokenizer tokenizer, Symbol status) {
  if (tokenizer.scan_status == <ok>) tokenizer.scan_status = status;
  tokenizer.tokenize(0, <error>);
  tokenizer.tokenize(0, <eof>);
  return 0;
}

// modes

/* Keep the mode stack and token stream atomic. An opening mode is staged
   before its token append and rolled back if that append transfers; a closing
   mode is removed only after its token is installed and the source position
   advances. */
static int Tokenizer._operator(Tokenizer t, int len) {
  Symbol op = Symbol.new_len(t.text + t.pos, len), push = 0;
  Symbol mode = t._scan_mode();
  int pop = 0, token_len = len, Symbol token_type = op;
  switch (mode) {
    case <x2c>: case <x2c-par>:
      switch (op) {
        case <"(">: if (mode == <x2c-par>) push = mode; break;
        case <")">: pop = mode == <x2c-par>; break;
        case <"{">:     push = <x2c>; break;
        case <"%{">:    push = <map>; break;
        case <"%[">:    push = <array>; break;
        case <"$(">:    push = <macro-lisp>; break;
        // A stray `}` at file scope is the parser's to diagnose or skip.
        case <"}">:      pop = t.modes.len() > 1; break;
        case <"%(">:    push = <list>; break;
        case <"%<<">:   push = <symbol-set>; break;
        case <"%\"">:   push = <string>; break;
      }
      break;
    case <list>: case <array>: case <map>:
      switch (op) {
        case <"(">: push = <list>; break;
        case <"${">: push = <x2c>; break;
        case <"?(">: if (mode == <list>) push = <x2c-par>; break;
        case <"@{">: if (mode == <list>) push = <x2c>; break;
        case <"{">: push = <map>; token_type = <"%{">; break;
        case <"[">: push = <array>; token_type = <"%[">; break;
        case <"\"">: push = <string>; token_type = <"%\"">; break;
        case <")">: pop = mode == <list>; break;
        case <"]">: pop = mode == <array>; break;
        case <"}">: pop = mode == <map>; break;
      }
      break;
    case <symbol-set>: if (op == <">>">) pop = 1;
      break;
    case <string>:
      switch (op) {
        case <"${">: push = <x2c>; break;
        case <"\"">: pop = 1; token_len = 1; token_type = <"\"">; break;
      }
      break;
    case <macro-lisp>:
      switch (op) {
        case <"(">: push = <macro-lisp>; break;
        case <")">: pop = 1; break;
      }
      break;
  }
  if (push) t._push_mode(push);
  int mode_committed = !push;
  defer if (!mode_committed) t._pop_mode();
  t.tokenize(token_len, token_type);
  mode_committed = 1;
  if (pop) t._pop_mode();
  return 1;
}

static inline Symbol Tokenizer._scan_mode(Tokenizer t) => t.modes[-1];

static inline void Tokenizer._push_mode(Tokenizer tokenizer, Symbol mode) {
  tokenizer.modes.push(mode);
}

static inline void Tokenizer._pop_mode(Tokenizer tokenizer) {
  if (tokenizer.modes.len()) tokenizer.modes.take_last();
}

// operand context

/* After an operand `%` is modulo, except where a statement starts after a
   control condition or a statement block. */
static inline int _percent_is_operator(Tokenizer tokenizer) {
  if (_layout_statement_start(tokenizer)) return 0;
  Token token = _significant_back(tokenizer, 0);
  return _token_ends_operand(token) &&
         !_closes_control_condition(tokenizer, token) &&
         !_closes_statement_block(tokenizer, token);
}

/* After an operand, `<` opens a Symbol literal only in the comparison forms
   `OPERAND is <sym>` and `OPERAND is not <sym>`. */
static inline int _can_start_symbol_literal(Tokenizer tokenizer) {
  if (!_prev_token_ends_operand(tokenizer)) return 1;
  Token keyword = _significant_back(tokenizer, 0);
  int back = 1;
  if (keyword.type != <ident>) return 0;
  if (keyword.text == "tag") return 1;
  if (keyword.text == "not") {
    keyword = _significant_back(tokenizer, back++);
    if (!keyword || keyword.type != <ident>) return 0;
  }
  return keyword.text == "is" &&
         _token_ends_operand(_significant_back(tokenizer, back));
}

static inline int _prev_token_ends_operand(Tokenizer tokenizer) =>
  !_layout_statement_start(tokenizer) &&
  _token_ends_operand(_significant_back(tokenizer, 0));

/* True when the indentation syntax starts a statement at the current
   position: a line break precedes it and it is no deeper than the line that
   holds the previous significant token. A deeper line continues that line,
   so an operand before it still makes `%` and `<` operators. */
static int _layout_statement_start(Tokenizer tokenizer) {
  if (!tokenizer.layout) return 0;
  struct Token *tokens = (struct Token *) tokenizer.tokens;
  size_t count = tokenizer.tokens.len();
  if (!count || tokens[count - 1].type != <space> ||
      !strchr(tokens[count - 1].text, '\n'))
    return 0;
  Token previous = _significant_back(tokenizer, 0);
  if (!previous) return 0;
  Token start = previous;
  for (struct Token *scan = previous;
       scan > tokens && scan[-1].line == previous.line;)
    if ((--scan).type != <space> && scan.type != <comment>) start = scan;
  return tokenizer.col <= start.col;
}

/* True when `token` closes the condition of `if`, `while`, `for`, or
   `switch`. A statement follows, so C allows no operator there. */
static int _closes_control_condition(Tokenizer tokenizer, Token token) =>
  token && token.type == <")"> &&
  _is_control_keyword(_before_group(tokenizer, token, <"(">));

/* True when `token` is the `}` of a compound statement or declaration body,
   which binary `%` cannot follow. The token before its `{` decides: a
   statement boundary, an identifier or `]` as in `with value {`, or a `)`
   after a control keyword, `match`, or an identifier as in a function header
   or `foreach (...)`. A compound literal or initializer brace follows an
   operator or a cast's `)` and does not qualify. */
static int _closes_statement_block(Tokenizer tokenizer, Token token) {
  if (!token || token.type != <"}">) return 0;
  Token before = _before_group(tokenizer, token, <"{">);
  if (!before) return 0;
  switch (before.type) {
    case <;>: case <:>: case <"{">: case <"}">: case <"]">: case <ident>:
    case <else>: case <do>: case <try>: case <finally>: case <defer>:
      return 1;
    case <")">: {
      Token head = _before_group(tokenizer, before, <"(">);
      return head && (head.type == <ident> || head.type == <match> ||
                      _is_control_keyword(head));
    }
  }
  return 0;
}

static inline int _is_control_keyword(Token token) =>
  token && (token.type == <if> || token.type == <while> ||
            token.type == <for> || token.type == <switch>);

/* Returns the significant token before the group that the `)` or `}` token
   `close` ends, or NULL when that group does not open with `opener` or
   starts the stream. Nesting counts delimiter token types, so parentheses
   and braces inside strings, comments, and Lisp atoms never count. */
static Token _before_group(Tokenizer tokenizer, Token close, Symbol opener) {
  struct Token *first = (struct Token *) tokenizer.tokens;
  int depth = 0;
  for (Token scan = close + 1; scan > first;) {
    switch ((--scan).type) {
      case <")">: case <"}">:
        depth++;
        break;
      case <"(">: case <"%(">: case <"$(">: case <"?(">:
      case <"{">: case <"%{">: case <"${">: case <"@{">:
        if (--depth) break;
        return scan.type == opener ? _significant_before(tokenizer, scan)
                                   : NULL;
    }
  }
  return NULL;
}

/* True when `token` can end an operand, so that a following `%` or `<` is
   an operator. */
static int _token_ends_operand(Token token) {
  if (!token) return 0;
  switch (token.type) {
    case <ident>: case <lit-int>: case <lit-float>: case <lit-char*>:
    case <lit-char>: case <lit-atom>: case <lit-symbol>:
    case <")">: case <"]">: case <"}">: case <"\"">:
    case <++>: case <-->:
      return 1;
  }
  return 0;
}

/* Returns the token `back` significant tokens from the end, skipping the
   trivia the parser never sees, or NULL when the stream holds fewer. */
static Token _significant_back(Tokenizer tokenizer, int back) {
  struct Token *tokens = (struct Token *) tokenizer.tokens;
  for (size_t count = tokenizer.tokens.len(); count; count--) {
    Symbol type = tokens[count - 1].type;
    if (type == <space> || type == <comment>) continue;
    if (!back--) return &tokens[count - 1];
  }
  return NULL;
}

/* NULL at stream start. */
static Token _significant_before(Tokenizer tokenizer, Token token) {
  struct Token *first = (struct Token *) tokenizer.tokens;
  while (token > first) {
    token--;
    if (token.type != <space> && token.type != <comment>) return token;
  }
  return NULL;
}

// indentation syntax

/* Rewrites a scanned indentation-syntax stream into the brace form the
   parser reads. Blocks open at a line ending in `:` before a deeper line and
   close at each dedent; other statement lines end with `;`. Inserted tokens
   are zero-width at the source position of their neighbor. An inconsistent
   dedent or a tab in indentation ends the stream with `<error>` under the
   `<indent>` status. */
static void Tokenizer._layout(Tokenizer t) {
  _Layout l = _layout_open(t);
  defer l.close();
  l.split_lines();
  for (int i = 0; i < l.nlines; i++) l.edit_line(i);
  if (l.error_at) t.scan_status = <indent>;
  t.tokens = l.emit();
}

/* One logical line of significant tokens, as indices into `sig`. */
static typedef struct _LayoutLine { int first, last, indent, directive; } _LayoutLine;

/* Edits the layout pass applies to one source token: punctuation inserted
   before and after it, and a replacement type. */
static typedef struct _LayoutEdit { String before, after; Symbol type; } _LayoutEdit;

/* What a block header's words say: an aggregate or enum header names no
   parameters, unlike a function's, and a label keeps its colon. */
static typedef struct _LayoutHeader {
  int aggregate, enumeration, labeled;
} _LayoutHeader;

/* The layout pass over one token stream. `sig` holds the significant tokens
   of `all`, `depths` their bracket depths, and `ternary` marks the colons
   that close a `?`. `edits` holds the rewrite of each token of `all`.
   `indents`, `closers`, and `enums` describe the blocks open up to `top`,
   and `error_at` is the first inconsistently indented token. */
static typedef struct _Layout {
  struct Token *all, Token *sig, Token error_at;
  int *depths, *indents, char *ternary, *enums;
  _LayoutLine *lines, _LayoutEdit *edits, String *closers;
  int count, nsig, nlines, top;
} _Layout;

static _Layout _layout_open(Tokenizer t) {
  int count = t.tokens.len() - 1;
  _Layout l = {
    .all = (struct Token *) t.tokens, .count = count,
    .sig = calloc(count + 1, sizeof(Token)),
    .depths = calloc(count + 1, sizeof(int)),
    .lines = calloc(count + 1, sizeof(_LayoutLine)),
    .edits = calloc(count + 1, sizeof(_LayoutEdit)),
    .indents = calloc(count + 2, sizeof(int)),
    .closers = calloc(count + 2, sizeof(String)),
    .enums = calloc(count + 2, 1), .ternary = calloc(count + 1, 1)};
  for (int i = 0; i < count; i++)
    if (l.all[i].type != <space> && l.all[i].type != <comment>)
      l.sig[l.nsig++] = &l.all[i];
  return l;
}

static void _Layout.close(_Layout &l) {
  free(l.sig); free(l.depths); free(l.lines); free(l.edits);
  free(l.indents); free(l.closers); free(l.enums); free(l.ternary);
}

/* The edit of significant token `k`. */
static _LayoutEdit *_Layout.edit(_Layout &l, int k) =>
  &l.edits[l.sig[k] - l.all];

// logical lines

/* Logical lines run to a line break at bracket depth zero, except that a
   deeper line or one starting with `.` continues them. A colon that closes
   a `?` opens no block, so the line after it continues too. */
static void _Layout.split_lines(_Layout &l) {
  int depth = 0, end_line = 0, pending = 0;
  for (int k = 0; k < l.nsig; k++) {
    Token tok = l.sig[k];
    if (l.starts_line(k, depth, end_line)) {
      l.check_tab(tok);
      l.lines[l.nlines++] =
        (_LayoutLine) {k, k, tok.col, tok.type == <preproc>};
      pending = 0;
    }
    l.lines[l.nlines - 1].last = k;
    if (_closes(tok)) depth--;
    l.depths[k] = depth;
    if (!depth && tok.text == "?") pending++;
    else if (!depth && tok.text == ":" && pending) {
      l.ternary[k] = 1;
      pending--;
    }
    if (_opens(tok)) depth++;
    end_line = _end_line(tok);
  }
}

static int _Layout.starts_line(_Layout &l, int k, int depth, int end_line) {
  Token tok = l.sig[k];
  if (tok.type == <preproc> || !l.nlines || l.lines[l.nlines - 1].directive)
    return 1;
  return depth == 0 && tok.line > end_line && tok.text != "." &&
    (tok.col <= l.lines[l.nlines - 1].indent ||
     (l.sig[k - 1].text == ":" && !l.ternary[k - 1]));
}

/* A tab in a statement line's indentation is inconsistent. */
static void _Layout.check_tab(_Layout &l, Token tok) {
  if (tok.type == <preproc> || l.error_at || tok <= l.all) return;
  Token space = tok - 1;
  if (space.type != <space>) return;
  char *newline = strrchr(space.text, '\n');
  if (newline && strchr(newline, '\t')) l.error_at = tok;
}

static int _end_line(Token tok) {
  int line = tok.line;
  for (char *c = tok.text; c && *c; c++) line += *c == '\n';
  return line;
}

// line edits

/* A line ending in `:` before a deeper line opens a block, and any other
   statement line ends with `;` where it needs one. Each dedent after the
   line closes the blocks it leaves. */
static void _Layout.edit_line(_Layout &l, int i) {
  _LayoutLine line = l.lines[i];
  if (line.directive) {
    if (l.sig[line.first].text.strip(" \t\r\n") == "#pragma indent")
      l.edit(line.first).type = <comment>;
    return;
  }
  if (!l.top && !l.indents[0]) l.indents[0] = line.indent;
  int j = l.next_statement(i);
  int next = j < l.nlines ? l.lines[j].indent : l.indents[0];
  String suffix = NULL;
  if (l.sig[line.last].text == ":" && !l.ternary[line.last] &&
      next > line.indent)
    l.open_block(line, j, next);
  else suffix = l.end_statement(line);
  while (l.top && next < l.indents[l.top])
    suffix = %"${suffix}${l.closers[l.top--]}";
  if (next != l.indents[l.top] && !l.error_at && j < l.nlines)
    l.error_at = l.sig[l.lines[j].first];
  _LayoutEdit *tail = l.edit(line.last);
  if (suffix) tail.after = tail.after ? %"${tail.after}$suffix" : suffix;
}

static int _Layout.next_statement(_Layout &l, int i) {
  int j = i + 1;
  while (j < l.nlines && l.lines[j].directive) j++;
  return j;
}

static void _Layout.open_block(
  _Layout &l, _LayoutLine line, int j, int next) {
  Token first = l.sig[line.first];
  _LayoutHeader header = l.header(line);
  if (header.labeled) l.edit(line.last).after = "{";
  else if (!l.condition(line.first, line.last, "{"))
    l.edit(line.last).type = <"{">;
  if (first.text == "do" && line.last == line.first + 1 && l.bare_do(line, j))
    l.edit(line.first).type = <space>;
  l.indents[++l.top] = next;
  l.enums[l.top] = header.enumeration;
  l.closers[l.top] = header.aggregate && first.text != "typedef" ? "};" : "}";
}

static _LayoutHeader _Layout.header(_Layout &l, _LayoutLine line) {
  int aggregate = 0, enumeration = 0, parameters = 0, labeled = 0;
  for (int m = line.first; m < line.last; m++) {
    String word = l.sig[m].text;
    aggregate |= word == "struct" || word == "union" || word == "enum";
    enumeration |= word == "enum";
    parameters |= l.sig[m].type == <"(">;
    labeled |= !l.depths[m] && _is_label(word);
  }
  return (_LayoutHeader) {
    aggregate && !parameters, enumeration && !parameters, labeled};
}

/* `do:` without a `while` trailer at its own indentation is a bare block. */
static int _Layout.bare_do(_Layout &l, _LayoutLine line, int j) {
  int k = j;
  for (; k < l.nlines; k++)
    if (!l.lines[k].directive && l.lines[k].indent <= line.indent) break;
  if (k == l.nlines) return 1;
  _LayoutLine trailer = l.lines[k];
  return trailer.indent != line.indent ||
    l.sig[trailer.first].text != "while" || l.sig[trailer.last].text == ":";
}

/* A statement line ends with `;` unless it already does or it is an enum
   member, one whole `$(...)` form, or a bare macro hole. A leading `@` marks
   a decorator line, which takes none. */
static String _Layout.end_statement(_Layout &l, _LayoutLine line) {
  l.one_line_body(line);
  if (l.sig[line.first].type == <"@">) {
    l.edit(line.first).type = <space>;
    return NULL;
  }
  if (l.sig[line.last].type == <;> || l.enums[l.top] || l.lisp_form(line) ||
      l.hole(line))
    return NULL;
  return ";";
}

/* A one-line body follows the first colon at depth zero that closes no
   `?`, unless a label owns that colon. */
static void _Layout.one_line_body(_Layout &l, _LayoutLine line) {
  for (int m = line.first + 1; m < line.last; m++) {
    String word = l.sig[m].text;
    if (l.depths[m]) continue;
    if (_is_label(word)) return;
    if (word != ":" || l.ternary[m]) continue;
    if (!l.condition(line.first, m, NULL) && l.sig[m - 1].text == "else")
      l.edit(m).type = <space>;
    return;
  }
}

static int _Layout.lisp_form(_Layout &l, _LayoutLine line) {
  if (l.sig[line.first].type != <"$(">) return 0;
  for (int m = line.first + 1; m < line.last; m++)
    if (l.depths[m] <= 0) return 0;
  return 1;
}

static int _Layout.hole(_Layout &l, _LayoutLine line) {
  int last = line.last;
  return l.sig[last].type == <ident> && last > line.first &&
    l.sig[last - 1].type == <"$"> &&
    (last - 1 == line.first || l.sig[last - 2].type == <")">);
}

/* Makes the colon at `colon` end the condition of the last control keyword
   at depth zero before it, adding parentheses unless one group already
   spans the condition. A `for` header keeps the parentheses it must have.
   The colon then becomes `body`, or goes when `body` is NULL.
   Returns 0 when no control keyword precedes the colon. */
static int _Layout.condition(_Layout &l, int first, int colon, String body) {
  int key = l.control_keyword(first, colon);
  if (key < 0) return 0;
  _LayoutEdit *tail = l.edit(colon);
  if (l.wrapped(key, colon)) tail.type = body ? <"{"> : <space>;
  else {
    l.edit(key + 1).before = "(";
    tail.type = <")">;
    tail.after = body;
  }
  return 1;
}

static int _Layout.control_keyword(_Layout &l, int first, int colon) {
  int key = -1;
  for (int m = first; m < colon; m++)
    if (!l.depths[m] && _conditional(l.sig[m]) &&
        (m == first || l.sig[m - 1].text != "."))
      key = m;
  return key;
}

static int _Layout.wrapped(_Layout &l, int key, int colon) {
  int wrapped = l.sig[key].text == "for" ||
    (l.sig[key + 1].type == <"("> && l.sig[colon - 1].type == <")">);
  for (int m = key + 2; wrapped && m < colon - 1; m++)
    wrapped = l.depths[m] > 0;
  return wrapped;
}

// output

/* Copies each token with its edits and ends the stream at the first
   inconsistently indented token. */
static Bytes _Layout.emit(_Layout &l) {
  Bytes out = Bytes.new(sizeof(struct Token));
  for (int i = 0; i <= l.count; i++) {
    Token tok = &l.all[i];
    if (tok == l.error_at) return _append_error(out, tok);
    _LayoutEdit edit = l.edits[i];
    out = _layout_insert(out, edit.before, tok, 0);
    struct Token copy = *tok;
    if (edit.type && edit.type != <space> && edit.type != <comment>)
      copy.text = Symbol.str(edit.type);
    if (edit.type) copy.type = edit.type;
    out = out.append(&copy, 1);
    out = _layout_insert(out, edit.after, tok, 1);
  }
  return out;
}

static Bytes _append_error(Bytes out, Token at) {
  struct Token marks[2] = {
    {.text = NULL, .type = <error>, .line = at.line, .col = at.col,
     .pos = at.pos},
    {.text = NULL, .type = <eof>, .line = at.line, .col = at.col,
     .pos = at.pos}
  };
  return out.append(marks, 2);
}

/* Appends zero-width punctuation tokens at `at`'s start or end. */
static Bytes _layout_insert(Bytes out, char *chars, Token at, int end) {
  for (; chars && *chars; chars++) {
    struct Token tok = {
      .text = String.new_len(chars, 1),
      .type = Symbol.new_len(chars, 1), .len = 0, .line = at.line,
      .col = end ? at.col + at.len : at.col, .pos = end ? at.pos + at.len
                                                        : at.pos
    };
    out = out.append(&tok, 1);
  }
  return out;
}

static inline int _opens(Token t) =>
  t.type != <lit-char*> && t.type != <lit-char> && t.type != <segment> &&
  t.len && strchr("([{", t.text[t.len - 1]);

static inline int _closes(Token t) =>
  t.type == <")"> || t.type == <"]"> || t.type == <"}">;

static inline int _conditional(Token t) =>
  t.text == "if" || t.text == "while" || t.text == "for" ||
  t.text == "foreach" || t.text == "switch" || t.text == "match";

static int _is_label(String word) =>
  word == "case" || word == "default" || word == "catch";

// lifecycle

/* Prepares a scope-owned Tokenizer starting in `mode`.
   It borrows `text` through `Tokenizer.scan`; null denotes empty input. The
   caller selects a mode understood by the scan driver, such as `<x2c>`.
   Raises: `<alloc-fail>` while creating internal storage. */
void Tokenizer.init(Tokenizer tokenizer, char *text, Symbol mode) {
  /* Empty String is a null pointer, but scanning always dereferences text.
     Use an addressable empty buffer so the first step reaches end-of-file. */
  tokenizer.text = text ? text : "";
  tokenizer.line = 1;
  tokenizer.col = 1;
  tokenizer.scan_status = <ok>;
  tokenizer.modes = [mode];
  tokenizer.tokens = Bytes.new(sizeof(struct Token));
}

/* Returns the next semantic Token after a completed scan.
   Whitespace and comments are skipped, preprocessor tokens are retained, and
   repeated calls at EOF return the same pointer. The returned pointer borrows
   Tokenizer storage. A null Tokenizer or empty stream returns NULL. */
Token Tokenizer.next(Tokenizer tokenizer) {
  if (!tokenizer) return NULL;
  with tokenizer.cursor {
    if (_ && _.type == <eof>) return _;
    if (!_ && !tokenizer.tokens.len()) return NULL;
    Token token = _ ? _ + 1 : (void *) tokenizer.tokens;
    while (token.type == <space> || token.type == <comment>) token++;
    _ = token;
    return token;
  }
}

/* `<malformed>` for a null Tokenizer. */
Symbol Tokenizer.status(Tokenizer t) => t ? t.scan_status : <malformed>;
