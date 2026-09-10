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

/* Holds one scope-owned, one-shot tokenization and its traversal cursor.
   `text` is borrowed through `Tokenizer.scan`; tokens and modes remain live
   until their owning Scope is released. */
typedef struct Tokenizer {
  Bytes tokens, char *text, Array modes, struct Token *cursor;
  Symbol scan_status, int line, col, pos;
} *Tokenizer;

/* Describes one token in Tokenizer-owned contiguous storage.
   A Token pointer is borrowed and stable only after scanning finishes. Its
   text is a canonical copy whose String pool controls its lifetime. */
typedef struct Token {
  String text, Symbol type, int line, col, len, pos;
} *Token;

#pragma private
#include "exception.x"
#include <string.h>

/* Recovers a borrowed Token pointer from its non-owning Var wrapper. */
inline Token Var.token(Var x) => x.pointer();

/* Wraps a borrowed Token pointer without extending its storage lifetime. */
inline Var Token.var(Token x) => Var.new(<token>, x);

/* The converter pair is declared after `#pragma private`, so this Var
   adoption stays local while its descriptor still registers globally. */
protocol Var(Token);

/* Hashes a live Token's complete representation; it must be nonnull. */
unsigned Token.hash(Token token) =>
  x2c_hash_bytes(0, token, sizeof(struct Token));

/* Reports byte-for-byte Token equality, with two null Tokens equal. */
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
  String head = %"{{text:${token.str()}, type:${token.type}";
  String location = %"line:${token.line}, col:${token.col}";
  String extent = %"len:${token.len}, pos:${token.pos}";
  return %"$head, $location, $extent}}";
}

/* Returns a scope-owned Tokenizer in x2c source mode.
   It borrows `text` through `Tokenizer.scan`; null denotes empty input.
   Raises: `<alloc-fail>` while creating internal storage. */
Tokenizer Tokenizer.new(char *text) => Tokenizer.new_mode(text, <x2c>);

/* Returns a scope-owned Tokenizer starting in `mode`.
   It borrows `text` through `Tokenizer.scan`; null denotes empty input. The
   caller selects a mode understood by the scan driver.
   Raises: `<alloc-fail>` while creating internal storage. */
Tokenizer Tokenizer.new_mode(char *text, Symbol mode) {
  Tokenizer tokenizer = Scope.malloc(sizeof(struct Tokenizer));
  /* Empty String is a null pointer, but scanning always dereferences text.
     Use an addressable empty buffer so the first step reaches end-of-file. */
  tokenizer.text = text ? text : "";
  tokenizer.pos = 0;
  tokenizer.line = 1;
  tokenizer.col = 1;
  tokenizer.cursor = NULL;
  tokenizer.scan_status = <ok>;
  tokenizer.modes = %[];
  tokenizer.modes.push(mode);
  tokenizer.tokens = Bytes.new(sizeof(struct Token));
  return tokenizer;
}

// mode stack

static inline Symbol Tokenizer._scan_mode(Tokenizer tokenizer) =>
  tokenizer.modes[-1];

static inline void Tokenizer._push_mode(Tokenizer tokenizer, Symbol mode) {
  tokenizer.modes.push(mode);
}

static inline void Tokenizer._pop_mode(Tokenizer tokenizer) {
  if (tokenizer.modes.len()) tokenizer.modes.take_last();
}

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

static int _error(Tokenizer tokenizer, Symbol status) {
  if (tokenizer.scan_status == <ok>) tokenizer.scan_status = status;
  tokenizer.tokenize(0, <error>);
  tokenizer.tokenize(0, <eof>);
  return 0;
}

/* Records the first lexical failure as `<malformed>`, appends zero-width
   `<error>` and `<eof>` sentinels at the current position, and returns zero.
   Raises: `<alloc-fail>` or `<size-limit>` while appending. */
int Tokenizer.error(Tokenizer tokenizer) => _error(tokenizer, <malformed>);

// scanner adapters

/* Invokes one non-retained scanner at the current source byte. `scanner` must
   be nonnull. A positive length appends `type`, zero makes no progress, and
   -1 records a malformed token stream. A cause from the callback or token
   append does not return here. */
int Tokenizer.do_scanner(
  Tokenizer tokenizer, int (*scanner)(char *), Symbol type) {
  int len = scanner(tokenizer.text + tokenizer.pos);
  if (len > 0) return tokenizer.tokenize(len, type);
  if (len < 0) return tokenizer.error();
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
        case <"}">:      pop = 1; break;
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

/* Consume the sigil before calling scan_identifier, whose input must begin
   with an identifier character. */
static int Tokenizer._named_reference(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos;
  tokenizer._operator(1);
  if (text[1] == '_' || scan_ascii_alpha((unsigned char) text[1]))
    return tokenizer.do_scanner(scan_identifier, <ident>);
  return 1;
}

/* Enter file-scoped compile-time Lisp until its closing parenthesis. */
static int Tokenizer._embedded_lisp(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos;
  if (text[0] != '$' || text[1] != '(') return 0;
  return tokenizer._operator(2);
}

static int Tokenizer._number(Tokenizer tokenizer) {
  char *text = tokenizer.text + tokenizer.pos, Symbol type;
  int len = scan_number_typed(text, &type);
  if (len < 0) return _error(tokenizer, <malformed>);
  if (len == 0) return 0;
  type = (type == <int>) ? <lit-int> : <lit-float>;
  return tokenizer.tokenize(len, type);
}

// percent context

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

/* True when `token` can end an operand, which makes a following `%` or `<`
   an operator rather than the opening of a literal. */
static int _token_ends_operand(Token token) {
  if (!token) return 0;
  switch (token.type) {
    case <ident>: case <lit-int>: case <lit-float>: case <lit-char*>:
    case <lit-char>: case <lit-atom>: case <lit-symbol>:
    case <")">: case <"]">: case <"}">:
    case <++>: case <-->:
      return 1;
  }
  return 0;
}

static inline int _prev_token_ends_operand(Tokenizer tokenizer) =>
  _token_ends_operand(_significant_back(tokenizer, 0));

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

// mode handlers

static int Tokenizer._percent_tokens(Tokenizer t) {
  char *text = t.text + t.pos;
  if (text[0] != '%') return 0;
  char next = text[1], int opener = strchr("([{<\"", next) != NULL;
  /* `%!` is one lambda-prefix token unless operand context makes `%` the
     modulo operator. The parser owns the following parameters and `=>`. */
  if (next == '!') {
    if (_prev_token_ends_operand(t)) return t._operator(1);
    return t.tokenize(2, Symbol.new_len(text, 2));
  }
  if (!opener) return 0;
  if (_prev_token_ends_operand(t)) return t._operator(1);
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

static int Tokenizer._common_tokens(Tokenizer t) {
  char *text = t.text + t.pos;
  switch (text[0]) {
    case ' ': case '\t': case '\v': case '\f': case '\n': case '\r':
      return t.do_scanner(scan_white_space, <space>);
    case '#': return t.do_scanner(scan_preprocessor, <preproc>);
    case '/':
      if (text[1] == '/') return t.do_scanner(scan_line_comment, <comment>);
      if (text[1] == '*')
        return t._scan_mode() == <lisp>
          ? _status_scanner(t, scan_block_comment_status, <comment>)
          : t.do_scanner(scan_block_comment, <comment>);
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

static int Tokenizer._x2c_tokens(Tokenizer tokenizer) {
  static const char *opchars = "-,;:!?.()[]{}*/&%^+<=>|~@";
  char *text = tokenizer.text + tokenizer.pos, int n;
  if (text[0] == '"') return tokenizer.do_scanner(scan_c_string, <lit-char*>);
  if (text[0] == '_' || scan_ascii_alpha((unsigned char) text[0])) {
    n = scan_identifier(text);
    Symbol type = scan_keyword_type(text, n);
    return tokenizer.tokenize(n, type ? type : <ident>);
  }
  if (strchr(opchars, text[0]) && (n = scan_c_operator(text)) > 0)
    return tokenizer._operator(n);
  return 0;
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

/* Lisp source and data literals share Atom scanning. The mode decides which
   delimiters nest data, which punctuation terminates an Atom, and whether
   `$` escapes into x2c. */
static int Tokenizer._lisp_tokens(Tokenizer t) {
  Symbol mode = t._scan_mode();
  int list = mode == <list>, collection = mode == <array> || mode == <map>;
  char *text = t.text + t.pos, int len;
  if (collection && t._common_tokens()) return 1;
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
    return text[1] == '{'
         ? t._operator(2)
         : t._named_reference();
  switch (text[0]) {
    case '(' : case ')': return t._operator(1);
    case '"': if (list || collection) return t._operator(1);
      return _status_scanner(t, scan_c_string_status, <lit-char*>);
    case '{': case '[': if (list || collection) return t._operator(1);
      break;
    case ']': case '}': case ':': if (collection) return t._operator(1);
      break;
    case '\'': case '`': return t.tokenize(1, Symbol.new_len(text, 1));
    case ',': if (collection) return t._operator(1);
      len = text[1] == '@' ? 2 : 1;
      return t.tokenize(len, Symbol.new_len(text, len));
    case '<': {
      if (!text[1] || text[1] == '=' || strchr("()'`, \n\t\v\f\r", text[1]))
        break;
      Symbol status = <ok>;
      int length = scan_symbol_literal_status(text, &status);
      if (length > 0) return t.tokenize(length, <lit-symbol>);
      if (length < 0) return _error(t, status);
      break;
    }
    case '+': case '-':
      if (scan_ascii_digit((unsigned char) text[1])) return t._number();
      break;
  }
  if (!collection && t._common_tokens()) return 1;
  if (collection) {
    Symbol status = <ok>;
    len = scan_atom_status(text, &status);
    if (len < 0) return _error(t, status);
    for (int i = 0; i < len; i++) {
      if (text[i] == '\\') {
        i++;
        continue;
      }
      if (strchr(",:]}", text[i])) {
        len = i;
        break;
      }
    }
    return len ? t.tokenize(len, <lit-atom>) : 0;
  }
  return _status_scanner(
    t, scan_atom_status, list ? <lit-atom> : <ident>);
}

// driver

/* NUL always ends tokenization, even in a nested mode. The parser or Lisp
   reader, not this lexical layer, diagnoses a missing closing delimiter. */
static int Tokenizer._end_of_file(Tokenizer tokenizer) {
  if (tokenizer.text[tokenizer.pos] == '\0')
    return tokenizer.tokenize(0, <eof>);
  return 0;
}

/* Scans the borrowed input once and completes the contiguous token stream.
   Success appends `<eof>`; lexical failure records its first status, then
   appends `<error>` and `<eof>`. Token text no longer depends on the source.
   Consumers must not rescan or append after beginning Token pointer traversal.
   Raises: `<alloc-fail>` or `<size-limit>` while storing tokens or modes. */
void Tokenizer.scan(Tokenizer t) {
  while (!t._end_of_file()) {
    Symbol mode = t._scan_mode();
    switch (mode) {
      case <x2c>: case <x2c-par>:
        if (t._common_tokens()) continue;
        if (t.text[t.pos] == '$' &&
            (t._embedded_lisp() || t._named_reference()))
          continue;
        if (t._percent_tokens() ||
            t._angle_symbol_literal() ||
            t._x2c_tokens())
          continue;
        break;
      case <array>: case <map>:
        if (t._lisp_tokens()) continue;
        break;
      case <symbol-set>:
        if (t._common_tokens() ||
            t._symbol_set_tokens()) continue;
        break;
      case <list>: case <lisp>: case <macro-lisp>:
        if (t._lisp_tokens()) continue;
        break;
      case <string>: if (t._string_tokens()) continue;
        break;
    }
    t.error();
    return;
  }
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

/* Returns the first scan status, or `<malformed>` for a null Tokenizer. */
Symbol Tokenizer.status(Tokenizer tokenizer) =>
  tokenizer ? tokenizer.scan_status : <malformed>;
