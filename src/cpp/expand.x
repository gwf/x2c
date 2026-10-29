/*  expand.x -- macro expansion

    A use of a visible macro is replaced by its replacement list with the
    arguments substituted, `#` and `##` applied, and the result rescanned,
    as C99 specifies. Each token carries the names of the macros whose
    expansion produced it, which do not expand it again. Every token of a
    use's expansion keeps the line, column, and position of the use, so a
    diagnostic in it points at the use. */

static macro Stmt $fail.cpp_use_unterminated(
  Expr $c, Expr $site, Expr $name, Expr $note) =>
  $c.report_error(
    <macro>, %"unterminated use of macro '$($name)'", $site,
    %("expected ')' before the end of the file" $($note)));

static macro Stmt $fail.cpp_use_arity(
  Expr $c, Expr $site, Expr $name, Expr $expected, Expr $given,
  Expr $note) =>
  $c.report_error(
    <macro>, %"macro '$($name)' takes $($expected) arguments", $site,
    %("given: $($given)" $($note)));

static macro Stmt $fail.cpp_paste_invalid(
  Expr $c, Expr $site, Expr $left, Expr $right, Expr $note) =>
  $c.report_error(
    <macro>, %"pasting '$($left)' and '$($right)' does not give one token",
    $site, %($($note)));

static macro Stmt $fail.cpp_paste_edge(Expr $c, Expr $site, Expr $note) =>
  $c.report_error(
    <macro>, "'##' needs a token on each side", $site, %($($note)));

/* One pass over a scanned stream. `in` is the scanned stream and `out` the
   stream the parser reads, NULL until the first expansion. `site` is the
   name of the use being expanded and `next` the index of the input token
   after the ones it has consumed; a directive among its arguments sets
   `retreat`, which leaves the use to the C compiler. `bodies` holds each
   replacement list's tokens, and `rows` the tokenizer's expansion rows. */
static typedef struct Expander {
  Compiler c, Cpp cpp, String path;
  Token in, site;
  size_t next;
  Bytes out;
  Map bodies;
  Array rows;
  int retreat;
} Expander;

/* One substitution of `definition`'s replacement list. `args` holds each
   argument's tokens as a Block, and `expanded` the fully expanded ones
   already computed, by parameter index. */
static typedef struct Substitution {
  List definition, params;
  int function, variadic;
  Array args;
  Map expanded;
  Block out;
} Substitution;

// the pass

/** Expands the visible macros of the scanned token stream and decides its
    conditional groups. The pass starts from the state `c.cpp`, which it
    takes, or from the macros visible before the first line of
    `c.filename`. The expanded stream replaces the scanned one: each token
    of an expansion keeps the line, column, and position of the use, and
    the tokenizer's `expansions` rows name the macro that produced it.
    Directives stay in the stream, and `c.arm_stacks` maps each conditional
    directive to the groups open after it.
*/
void Compiler.expand_macros(Compiler c) {
  Cpp cpp = c.cpp ? c.cpp : Cpp.new(c.initial_macros(c.filename));
  c.cpp = NULL;
  c.arm_stacks = {};
  Expander x = {
    .c = c, .cpp = cpp, .path = c.filename, .in = c.tokenizer.tokens,
    .bodies = {}};
  size_t i = 0;
  for (; (x.in + i).type != <eof>; i++) {
    Token token = x.in + i;
    if (token.type == <preproc>) _directive(x, token);
    else if (!cpp.hidden() && _use_at(x, i)) {
      i = _expand_use(x, i);
      continue;
    }
    _keep(x, token);
  }
  _keep(x, x.in + i);
  if (!x.out) return;
  c.tokenizer.tokens = x.out;
  c.tokenizer.expansions = x.rows;
}

/** Returns the note that names the C macro whose expansion produced the
    source at the diagnostic `location`, or NULL when no expansion did.
*/
String Compiler.cpp_note(Compiler c, List location) {
  Tokenizer tokenizer = c.tokenizer;
  if (!tokenizer || !tokenizer.expansions || !location) return NULL;
  int line = location.assoc(<line>), position = location.assoc(<position>);
  Token tokens = tokenizer.tokens;
  foreach (List row in tokenizer.expansions) {
    (long first, long end, String name, List site) = row;
    Token token = tokens + first;
    if (first < end && token.pos == position && token.line == line)
      return _note(name, site);
  }
  return NULL;
}

/** Returns the name of the C macro whose expansion produced `token` of the
    compiler's token stream, or NULL.
*/
String Compiler.expanding_macro(Compiler c, Token token) {
  Tokenizer tokenizer = c.tokenizer;
  if (!tokenizer || !tokenizer.expansions) return NULL;
  long index = token - (Token) tokenizer.tokens;
  foreach (List row in tokenizer.expansions) {
    (long first, long end, String name, List site) = row;
    (void) site;
    if (index >= first && index < end) return name;
  }
  return NULL;
}

/* A conditional directive records the groups open after it. */
static void _directive(Expander &x, Token token) {
  int open = x.cpp.groups.len() > 0;
  long index = x.out ? x.out.len() : token - x.in;
  Symbol kind = x.c.cpp_directive(x.cpp, token, x.path);
  if (kind == <open> || (kind && open))
    x.c.arm_stacks[index] = x.cpp.open_groups();
}

static void _keep(Expander &x, Token token) {
  if (x.out) x.out = x.out.append(token, 1);
}

/* A `$` or `@` before a name makes it a macro hole or a reference, not a
   use. */
static int _use_at(Expander &x, size_t i) {
  Token token = x.in + i;
  Var definition;
  if (!token.is_word() || !x.cpp.macros.try_get(token.text, definition) ||
      definition is not <list>)
    return 0;
  if (i && ((x.in + i - 1).type == <$> || (x.in + i - 1).type == <@>)) return 0;
  return definition.list().car() == <object> || _input_paren(x, i + 1);
}

static int _input_paren(Expander &x, size_t i) {
  Token token = x.in + i;
  while (token.type == <space> || token.type == <comment>) token++;
  return token.type == <(>;
}

/* Expands the use whose name is input token `i` and returns the index of
   its last input token. */
static size_t _expand_use(Expander &x, size_t i) {
  Block stack = auto Block.new(sizeof(CppToken));
  Block sink = auto Block.new(sizeof(CppToken));
  x.site = x.in + i;
  x.next = i + 1;
  x.retreat = 0;
  CppToken name = {.token = *x.site};
  stack.push(&name);
  _rescan(x, stack, sink, 1);
  if (x.retreat) {
    _keep(x, x.site);
    return i;
  }
  _place(x, sink, i);
  return x.next - 1;
}

/* Appends an expansion at the use's location and records its row. */
static void _place(Expander &x, Block sink, size_t i) {
  if (!x.out) x.out = Bytes.new(sizeof(struct Token)).append(x.in, i);
  long first = x.out.len();
  CppToken *items = sink.bytes;
  for (size_t k = 0; k < sink.len(); k++) {
    struct Token token = items[k].token;
    token.line = x.site.line;
    token.col = x.site.col;
    token.pos = x.site.pos;
    x.out = x.out.append(&token, 1);
  }
  if (!x.rows) x.rows = [];
  List definition = x.cpp.macros[x.site.text];
  x.rows.push(
    $(first, (long) x.out.len(), x.site.text, definition.last()));
}

/* Expands the `defined`-free tokens of an `#if` expression of the
   directive `site`. */
module Block _expand_items(Compiler c, Cpp cpp, Block items, Token site) {
  Expander x = {.c = c, .cpp = cpp, .site = site, .bodies = {}};
  return _expand_alone(x, items);
}

// rescanning

/* Moves the tokens of `stack`, top first, to `sink`, replacing each macro
   use. With `input`, a function-like use may take its arguments from the
   input stream after the stack. */
static void _rescan(Expander &x, Block stack, Block sink, int input) {
  CppToken item;
  while (!x.retreat && stack.try_pop(&item)) {
    List definition = _definition(x, item);
    if (!definition) sink.push(&item);
    else if (definition.car() == <object>) {
      List hide = cons(item.token.text, item.hide);
      _push_all(stack, _substitute(x, definition, NULL, hide));
    }
    else if (_paren_next(x, stack, input))
      _call(x, stack, input, item, definition);
    else sink.push(&item);
  }
}

static List _definition(Expander &x, CppToken &item) {
  Var definition;
  Token token = &item.token;
  if (!token.is_word() || token.text in item.hide ||
      !x.cpp.macros.try_get(token.text, definition) ||
      definition is not <list>)
    return NULL;
  return definition;
}

static int _paren_next(Expander &x, Block stack, int input) {
  size_t depth = stack.len();
  if (depth) return ((CppToken *) stack.bytes)[depth - 1].token.type == <(>;
  return input && _input_paren(x, x.next);
}

/* Replaces the function-like use whose name is `name` and whose `(` is the
   next token. */
static void _call(
  Expander &x, Block stack, int input, CppToken &name, List definition) {
  CppToken open, close;
  (void) _pull(x, stack, input, open);
  Array args = [];
  if (!_arguments(x, stack, input, definition, args, close)) return;
  _check_arity(x, definition, args);
  List hide = cons(name.token.text, _meet(name.hide, close.hide));
  _push_all(stack, _substitute(x, definition, args, hide));
}

/* Takes the next token from the stack, else from the input stream after
   blanks and comments. Returns 0 at the end of both, and sets `retreat` at
   a directive. */
static int _pull(Expander &x, Block stack, int input, CppToken &item) {
  if (stack.try_pop(&item)) return 1;
  if (!input) return 0;
  Token token = x.in + x.next;
  int space = 0;
  for (; token.type == <space> || token.type == <comment>; token++)
    space = 1;
  x.next = token - x.in;
  if (token.type == <eof>) return 0;
  if (token.type == <preproc>) {
    x.retreat = 1;
    return 0;
  }
  x.next++;
  item = (CppToken) {.token = *token, .space = space};
  return 1;
}

/* Collects the arguments after the `(` up to the matching `)`, which it
   stores in `close`. A comma inside parentheses, brackets, or braces does
   not separate arguments, because x2c writes Array and Map literals in
   brackets and braces, and the variadic argument keeps its commas. */
static int _arguments(
  Expander &x, Block stack, int input, List definition, Array args,
  CppToken &close) {
  List params = definition[2];
  int last = definition[3] ? params.len() - 1 : -1;
  Block arg = Block.new(sizeof(CppToken));
  Array closers = auto [];
  CppToken item;
  while (_pull(x, stack, input, item)) {
    Symbol type = item.token.type;
    if (!closers.len() && type == <)>) {
      close = item;
      args.push(arg);
      return 1;
    }
    if (!closers.len() && type == <,> && (int) args.len() != last) {
      args.push(arg);
      arg = Block.new(sizeof(CppToken));
      continue;
    }
    _track_group(closers, type);
    arg.push(&item);
  }
  if (!x.retreat)
    $fail.cpp_use_unterminated(
      x.c, x.site, definition.cadr(), _definition_note(definition));
  return 0;
}

static void _track_group(Array closers, Symbol type) {
  switch (type) {
    case <(>: case <"%(">: case <"$(">: case <"@(">: case <"?(">:
      closers.push(<)>);
      break;
    case <"[">: case <"%[">: closers.push(<"]">); break;
    case <"{">: case <"%{">: case <"${">: closers.push(<"}">); break;
    case <)>: case <"]">: case <"}">:
      if (closers.len() && closers[-1] == type) closers.take_last();
      break;
  }
}

/* A variadic macro may omit its variadic argument, and a macro without
   parameters takes one empty argument. */
static void _check_arity(Expander &x, List definition, Array args) {
  List params = definition[2];
  int count = params.len(), given = args.len();
  Block first = args[0];
  if (!count && given == 1 && !first.len()) return;
  if (definition[3] && given == count - 1) {
    args.push(Block.new(sizeof(CppToken)));
    return;
  }
  if (given != count)
    $fail.cpp_use_arity(
      x.c, x.site, definition.cadr(), count, given,
      _definition_note(definition));
}

// substitution

/* The replacement list with the arguments substituted, each token's hide
   set extended by `hide`. */
static Block _substitute(
  Expander &x, List definition, Array args, List hide) {
  Substitution s = {
    .definition = definition, .args = args,
    .out = Block.new(sizeof(CppToken))};
  if (definition.car() == <function>) {
    s.function = 1;
    s.params = definition[2];
    s.variadic = definition[3];
    s.expanded = {};
  }
  Token body = _body_tokens(x, definition);
  _replace(x, s, body, _end(body));
  return _finish(s.out, hide);
}

/* Substitutes the replacement tokens from `token` up to `end`. */
static void _replace(Expander &x, Substitution &s, Token token, Token end) {
  while (token < end) {
    Token next = token + 1;
    int param = _param(s, token), after = next < end;
    if (s.function && token.type == <"#"> && after && _param(s, next) >= 0)
      token = _stringized(s, next);
    else if (token.type == <"##"> && after) token = _pasted(x, s, next);
    else if (token.type == <"##">)
      $fail.cpp_paste_edge(x.c, x.site, _definition_note(s.definition));
    else if (param >= 0)
      token = _argument(x, s, param, after && next.type == <"##">, next);
    else if (s.variadic && token.text == "__VA_OPT__" && after &&
             next.type == <(>)
      token = _va_opt(x, s, next, end);
    else token = _copied(s, token);
  }
}

static Token _copied(Substitution &s, Token token) {
  CppToken item = {.token = *token};
  s.out.push(&item);
  return token + 1;
}

/* A parameter beside `##` takes its argument as written, and a parameter
   elsewhere its argument fully expanded. */
static Token _argument(
  Expander &x, Substitution &s, int param, int pasted, Token next) {
  Block arg = s.args[param];
  if (pasted) _push_raw(s, arg);
  else _push_block(s.out, _expanded(x, s, param));
  return next;
}

static void _push_raw(Substitution &s, Block arg) {
  if (arg.len()) _push_block(s.out, arg);
  else _push_placemarker(s.out);
}

static void _push_placemarker(Block out) {
  CppToken mark = {.token = {.type = <empty>}};
  out.push(&mark);
}

static Block _expanded(Expander &x, Substitution &s, int param) {
  Var cached;
  if (s.expanded.try_get(param, cached)) return cached;
  Block expanded = _expand_alone(x, s.args[param]);
  s.expanded[param] = expanded;
  return expanded;
}

/* `#` makes a string literal of an argument as written, its blanks
   reduced to one space. */
static Token _stringized(Substitution &s, Token param) {
  Block arg = s.args[_param(s, param)];
  CppToken *items = arg.bytes;
  Array parts = ["\""];
  for (size_t i = 0; i < arg.len(); i++) {
    Token token = &items[i].token;
    if (i && items[i].space) parts.push(" ");
    if (token.type == <lit-char*> || token.type == <lit-char>)
      parts.push(token.text.replace("\\", "\\\\").replace("\"", "\\\""));
    else parts.push(token.text);
  }
  parts.push("\"");
  CppToken item = _made(<lit-char*>, "".join(parts.list_free()));
  s.out.push(&item);
  return param + 1;
}

/* `##` joins the last token before it to the first token after it. An
   empty argument on either side leaves the other side. Between a comma and
   the variadic argument, as GNU C reads `, ## __VA_ARGS__`, `##` keeps
   both unjoined, and an empty variadic argument removes the comma. */
static Token _pasted(Expander &x, Substitution &s, Token next) {
  int param = _param(s, next);
  Block right = Block.new(sizeof(CppToken));
  CppToken operand = {.token = *next}, left;
  if (param >= 0) right = s.args[param];
  else right.push(&operand);
  if (!s.out.try_pop(&left))
    $fail.cpp_paste_edge(x.c, x.site, _definition_note(s.definition));
  CppToken *items = right.bytes;
  int comma = left.token.type == <,> && s.variadic &&
              param == s.params.len() - 1;
  if (left.token.type == <empty>) _push_raw(s, right);
  else if (comma || !right.len()) {
    if (!comma || right.len()) s.out.push(&left);
    _push_block(s.out, right);
  }
  else {
    CppToken joined = _join(x, s, left, items[0]);
    s.out.push(&joined);
    for (size_t i = 1; i < right.len(); i++) s.out.push(&items[i]);
  }
  return next + 1;
}

/* The one token two tokens' text spells together. */
static CppToken _join(
  Expander &x, Substitution &s, CppToken &left, CppToken &right) {
  String text = left.token.text + right.token.text;
  Token token = Compiler.scan_directive(text);
  if (token.len != text.len() || (token + 1).type != <eof>)
    $fail.cpp_paste_invalid(
      x.c, x.site, left.token.text, right.token.text,
      _definition_note(s.definition));
  return (CppToken) {.token = *token, .hide = _meet(left.hide, right.hide)};
}

/* `__VA_OPT__(...)` holds its tokens when the variadic argument has any. */
static Token _va_opt(Expander &x, Substitution &s, Token open, Token end) {
  Token close = open.group_close();
  if (close >= end) return _copied(s, open - 1);
  Block variadic = s.args[s.params.len() - 1];
  if (variadic.len()) _replace(x, s, open + 1, close);
  else _push_placemarker(s.out);
  return close + 1;
}

static int _param(Substitution &s, Token token) {
  if (!s.function || !token.is_word()) return -1;
  int index = 0;
  foreach (String param in s.params) {
    if (param == token.text) return index;
    index++;
  }
  return -1;
}

/* Drops the placemarkers and extends each token's hide set. */
static Block _finish(Block out, List hide) {
  Block done = Block.new(sizeof(CppToken));
  CppToken *items = out.bytes;
  for (size_t i = 0; i < out.len(); i++) {
    CppToken item = items[i];
    if (item.token.type == <empty>) continue;
    item.hide = _union(item.hide, hide);
    done.push(&item);
  }
  return done;
}

/* The tokens of a fully expanded argument, which takes nothing after it. */
static Block _expand_alone(Expander &x, Block tokens) {
  Block stack = Block.new(sizeof(CppToken));
  Block sink = Block.new(sizeof(CppToken));
  _push_all(stack, tokens);
  _rescan(x, stack, sink, 0);
  return sink;
}

// replacement lists

/* A replacement list's tokens, ending in `eof`, with each `#` and `##`
   operator one token. */
static Token _body_tokens(Expander &x, List definition) {
  String body = definition.car() == <object> ? definition[2] : definition[4];
  Var cached;
  if (x.bodies.try_get(body, cached)) {
    Block tokens = cached;
    return tokens.bytes;
  }
  Block tokens = Block.new(sizeof(struct Token));
  _scan_body(tokens, body);
  struct Token end = {.type = <eof>, .text = ""};
  tokens.push(&end);
  x.bodies[body] = tokens;
  return tokens.bytes;
}

/* The x2c tokenizer reads `#` as the start of a directive running to the
   end of the line, so each `#` or `##` becomes an operator token and the
   text after it is scanned again. */
static void _scan_body(Block tokens, String text) {
  for (Token token = Compiler.scan_directive(text); token.type != <eof>;
       token++) {
    if (token.type == <space> || token.type == <comment>) continue;
    if (token.type != <preproc>) {
      tokens.push(token);
      continue;
    }
    int pasting = token.text.startswith("##"), skip = pasting ? 2 : 1;
    CppToken mark = _made(pasting ? <"##"> : <"#">, pasting ? "##" : "#");
    tokens.push(&mark.token);
    _scan_body(tokens, token.text[skip:]);
    return;
  }
}

static Token _end(Token token) {
  while (token.type != <eof>) token++;
  return token;
}

// tokens and hide sets

static CppToken _made(Symbol type, String text) =>
  (CppToken) {.token = {.type = type, .text = text, .len = text.len()}};

static void _push_block(Block out, Block tokens) {
  CppToken *items = tokens.bytes;
  for (size_t i = 0; i < tokens.len(); i++) out.push(&items[i]);
}

/* Pushes `tokens` so that the first is on top. */
static void _push_all(Block stack, Block tokens) {
  CppToken *items = tokens.bytes;
  for (size_t i = tokens.len(); i; i--) stack.push(&items[i - 1]);
}

static List _union(List set, List names) {
  foreach (String name in names) if (!(name in set)) set = cons(name, set);
  return set;
}

static List _meet(List set, List names) {
  Array kept = [];
  foreach (String name in set) if (name in names) kept.push(name);
  return kept.list_free();
}

// diagnostics

static String _note(String name, List site) {
  (String file, int line) = site;
  return %"in expansion of '$name' defined at $file:$line";
}

static String _definition_note(List definition) =>
  _note(definition.cadr(), definition.last());
