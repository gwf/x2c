/*  tokens.x -- compiler tokenization and cursor navigation */

// tokenizing

/** Scans source, applies directive handling and optional C macro expansion,
    and positions the compiler at its first non-trivia token.

    The compiler borrows `text` for diagnostics and macro source capture until
    translation finishes.
*/
void Compiler.tokenize(Compiler c, char *text) {
  c.scan_source(text);
  c.preprocess_tokens();
}

/** Scans source without preprocessing it and positions the compiler at its
    first non-trivia token. `Compiler.preprocess_tokens` must run before
    the parser reads the tokens. The compiler borrows `text` as
    `Compiler.tokenize` does.
*/
void Compiler.scan_source(Compiler c, char *text) {
  if (_is_script_file(c)) c.script = c.unit_script;
  c.input_boundary = NULL;
  c.arm_stacks = NULL;
  c.text = text;
  c.tokenizer = Tokenizer.new(c.text, <x2c>);
  c.tokenizer.layout = c.layout || Path.is_layout_source(c.filename);
  c.tokenizer.scan();
  c.layout = c.tokenizer.layout;
  _report_malformed_token(c);
  c.token = Token.skip_trivia(c.tokenizer.tokens);
  c.braces.clear();
}

/** Applies directive handling and optional C macro expansion, then positions
    the compiler at its first non-trivia token. Explicit CPP state also
    enables expansion for native-header and REPL callers.
*/
void Compiler.preprocess_tokens(Compiler c) {
  if (c.cpp_expansion || c.cpp) c.expand_macros();
  c.scan_conditionals();
  _retag_keywords(c.tokenizer);
  c.token = Token.skip_trivia(c.tokenizer.tokens);
}

// token navigation

/** Requires and consumes the current token type.

    A mismatch reports a parse diagnostic. An active recovery boundary raises
    `<malformed>`; without one, diagnostic reporting exits.
*/
Symbol Compiler.expect(Compiler c, Symbol type) {
  if (c.token.type != type) {
    c.require_input();
    $fail.compiler_token_expected(c, c.token, type);
  }
  c.next();
  return type;
}

/** Raises `<incomplete>` when a required grammar item reaches the supplied
    input boundary. The caller sets a token in the current token stream after
    tokenizing; tokenization clears it. Semantic failures do not call this.
*/
void Compiler.require_input(Compiler c) {
  if (c.input_boundary && c.token >= c.input_boundary) raise %(incomplete);
}

/** Consumes `type` when current and reports whether it matched. */
inline int Compiler.test(Compiler c, Symbol type) {
  if (c.token.type != type) return 0;
  c.next();
  return 1;
}

/** Consumes the identifier `word` when current and reports whether it
    matched.
*/
int Compiler.take_word(Compiler c, String word) {
  if (!c.at_word(word)) return 0;
  c.next();
  return 1;
}

/** Consumes the current token and advances past following trivia.

    This updates the unmatched-brace stack. An unmatched `}` reports a parse
    diagnostic, which raises `<malformed>` under recovery and otherwise exits.
*/
void Compiler.next(Compiler c) {
  Token consumed = c.token;
  if (consumed.type == <eof>) return;
  c.token = Token.skip_trivia(consumed + 1);
  _update_brace_stack(c, consumed);
}

/** Reports whether the current token is the identifier `word`. A contextual
    keyword such as `with` or `as` is an ordinary identifier elsewhere. This
    query does not consume tokens.
*/
int Compiler.at_word(Compiler c, String word) =>
  c.peek(0) == <ident> && c.token.text == word;

/** Returns the non-trivia token type `steps` from parser position.

    Zero reads the current token; positive and negative steps count forward
    and backward through non-trivia tokens. The parser cursor is unchanged.
*/
Symbol Compiler.peek(Compiler c, int steps) {
  Token token = c.token;
  if (!steps && c.at_completion()) {
    List rows = c.sym.visible_symbols();
    raise %(replcomp (kind <names>) (rows $rows) (keywords ()));
  }
  while (steps > 0) {
    token = Token.skip_trivia(token + 1);
    steps--;
  }
  while (steps < 0) {
    token = _skip_backward(token - 1, c.tokenizer.tokens);
    steps++;
  }
  return token.type;
}

/** Returns the first non-trivia token after the group `t` opens, or after
    `t` when it opens no group. A group that never closes yields `eof`.
*/
Token Token.after_group(Token t) {
  t = t.group_close();
  return t.type == <eof> ? t : Token.skip_trivia(t + 1);
}

/** Returns the first token at or after `token` that is not a space,
    comment, or preprocessor line. The stream must end in `eof`.
*/
Token Token.skip_trivia(Token token) {
  /* The default arm returns eof and every non-trivia token unchanged. */
  loop {
    switch (token.type) {
      case <space>: case <comment>: case <preproc>: token++; break;
      default: return token;
    }
  }
}

/** Returns the token that closes the group `t` opens, `t` itself when it
    opens no group, or the `eof` token when the group never closes.
*/
Token Token.group_close(Token t) {
  for (int depth = 0; t.type != <eof>; t++)
    if ((depth += t.type.group_step()) <= 0) return t;
  return t;
}

/** Returns 1 for a token type that opens a delimited group, -1 for one that
    closes a group, and 0 otherwise. Every opener spelling ends in the `(`,
    `[`, or `{` that its closer matches.
*/
int Symbol.group_step(Symbol s) {
  switch (s) {
    case <"(">: case <"[">: case <"{">: case <"?(">: case <"$(">:
    case <"@(">:
    case <"${">: case <"%(">: case <"%[">: case <"%{">:
      return 1;
    case <")">: case <"]">: case <"}">:
      return -1;
  }
  return 0;
}

// completion

/** Retags the token beginning at `position` as a private completion marker. */
void Compiler.mark_completion(Compiler c, int position) {
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.pos == position && token.type == <ident>) {
      token.type = <replcomp>;
      return;
    }
  }
}

/* Raises `<replcomp>` at the completion marker with the visible symbols,
    grammar `role`, and available `keywords`. Does nothing elsewhere. */
void _x2c_complete_here(Compiler c, Symbol role, List keywords) {
  if (!c.at_completion()) return;
  List rows = c.sym.visible_symbols();
  raise %(replcomp (kind $role) (rows $rows) (keywords $keywords));
}

/** Reports whether the parser is at the private REPL completion marker. */
int Compiler.at_completion(Compiler c) => c.token.type == <replcomp>;

// compiler tokenization and cursor navigation

/* The unit's script settings apply to the one file that carries the
   shebang, whichever compiler reads it. */
static int _is_script_file(Compiler c) =>
  c.unit_script && c.filename &&
  (c.filename == c.unit_script.path ||
   Path.resolved_absolute(c.filename) == c.unit_script.path);

/* A lexical failure truncates the token stream, so the parser reaches the
   appended `<eof>` and blames the end of the file. Report the refused byte
   instead. An `<incomplete>` token really did run out of source, so it keeps
   the end-of-file diagnostic that describes it. */
static void _report_malformed_token(Compiler c) {
  Symbol status = c.tokenizer.status();
  if (status != <malformed> && status != <indent>) return;
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <error>)
      $fail.compiler_token_malformed(c, token, status);
  }
}

/* `in` and `match` are C identifiers as often as x2c keywords. `in` stays
   the operator where its neighbors plainly end and begin operands, and the
   parser reads it by position everywhere else; `match` is the statement
   only as `match (...)` followed by `case` or `{`. Every other occurrence
   is a name, so C that uses them keeps compiling. */
static void _retag_keywords(Tokenizer tokenizer) {
  Token prev = NULL;
  for (Token token = tokenizer.tokens; token.type != <eof>;
       token = Token.skip_trivia(token + 1)) {
    if (token.type == <in>) {
      Token next = Token.skip_trivia(token + 1);
      if (!(prev && _ends_operand(prev.type) && _starts_operand(next.type)))
        token.type = <ident>;
    }
    else if (token.type == <match>) {
      Token next = Token.skip_trivia(token + 1);
      if (next.type == <(>) next = next.after_group();
      if (next.type != <case> && next.type != <"{">) token.type = <ident>;
    }
    prev = token;
  }
}

static int _ends_operand(Symbol type) {
  switch (type)
    case <ident>: case <lit-int>: case <lit-float>: case <lit-char>:
    case <lit-char*>: case <lit-atom>: case <lit-symbol>: case <)>: case <]>:
      return 1;
  return 0;
}

static int _starts_operand(Symbol type) {
  switch (type)
    case <ident>: case <lit-int>: case <lit-float>: case <lit-char>:
    case <lit-char*>: case <lit-atom>: case <lit-symbol>: case <(>:
    case <"%(">: case <"%[">: case <"%{">: case <$>: case <!>: case <->:
    case <*>: case <&>: case <~>: case <++>: case <-->:
      return 1;
  return 0;
}

static void _update_brace_stack(Compiler c, Token consumed) {
  switch (consumed.type) {
    case <"{">: case <"%{">: case <"${">:
      c.braces.push(consumed);
      break;
    case <"}">:
      if (c.braces.len()) c.braces.take_last();
      else
        $fail.compiler_brace_unexpected(c, consumed);
      break;
  }
}

static Token _skip_backward(Token token, Token origin) {
  while (token > origin) {
    switch (token.type) {
      case <space>: case <comment>: case <preproc>: token--; break;
      default: return token;
    }
  }
  return origin;
}

// The index after the last non-trivia token before the cursor.
module long _end_index(Compiler c, Token tokens) =>
  _skip_backward(c.token - 1, tokens) + 1 - tokens;

module void _check_unmatched_braces(Compiler c) {
  if (!c.braces.len()) return;
  $fail.compiler_brace_missing(c, c.braces[-1]);
}
