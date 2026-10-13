/* the parse driver

   A full parse reads the unit's top-level forms in source order. A form
   that fails is skipped whole, so one error does not hide the next. */

/* One full parse of a unit. A script unit that does not define `main`
   hoists its statements: `statements` holds each run's first and
   past-the-end token index, `runs` counts the runs, `first` is where the
   first one starts, and `gap` is the index after the last form, where the
   next form's conditional directives begin. */
static typedef struct FullParse {
  Compiler c, Array nodes, statements;
  int hoisting, gap, runs, first;
} FullParse;

/** Parses and types the positioned source against `globs`.

    The result is a source-ordered top-level AST. This resets macro state
    and protocol resolution; origins live for the whole unit.
    `generated_symbols` publishes external adapter signatures before parsing.
*/
List Compiler.full_parse(Compiler c, Map globs, int generated_symbols) {
  Array nodes = [];
  c.unit_nodes = nodes;
  _reset_parse(c, globs, generated_symbols);
  Token conflict = NULL;
  $let(c.recovery_depth, c.recovery_depth + 1)
    conflict = _parse_forms(c, nodes);
  if (conflict) {
    c.token = conflict;
    _report_script_statement(c);
  }
  List ast = _finish_parse(c, nodes);
  if (!c.public_bodies) c.publish_inline_types(ast);
  return ast;
}

/* A full parse starts from the unit's collected symbols, without the parse
   state that collection or an earlier parse left. */
static void _reset_parse(Compiler c, Map globs, int generated) {
  c.meta_group.clear();
  c.meta_group_bound = {};
  c.meta_comptime = {};
  c.meta_regions = {};
  c.native_meta = {};
  c.project_meta = {};
  c.inherit_library_comptime();
  c.init_tokens = {};
  c.static_init_deps = {};
  c.origin = 0;
  c.braces.clear();
  c.arms = NULL;
  c.sym.reset(globs);
  c.rebuild_protocols(globs);
  _reset_macros(c);
  c.resolve_protocols();
  if (generated) c.install_generated_protocol_symbols();
  c.install_native_meta_effects(globs);
  c.included_effects = c.included_compile_time_effects(globs);
}

static void _reset_macros(Compiler c) {
  c.macros = {};
  c.kw_aliases = {};
  c.rewrite_rules = NULL;
  c.active_rewrites = NULL;
  c.prepared_rewrites = NULL;
  c.install_builtin_macros();
  if (!c.declaration_produced) c.imports = {};
  c.import_stack.clear();
  c.macro_count = 0;
  c.macro_stack = NULL;
  c.source_private = 0;
}

/* Parses every form, then the `main` that a script's statement runs
   become. Returns the first hoisted statement when a macro defined `main`
   where the token scan saw none, and NULL otherwise. */
static Token _parse_forms(Compiler c, Array nodes) {
  _append_preproc(c, nodes);
  Array statements = [];
  FullParse p = {
    .c = c, .nodes = nodes, .statements = statements,
    .hoisting = c.script && !c.script.defines_main};
  loop {
    while (c.peek(0) != <eof>) if (!_form(p)) break;
    if (!p.runs) return NULL;
    Token tokens = c.tokenizer.tokens;
    if ("main" in c.fn_defs) return tokens + p.first;
    _push_conditionals(c, statements, p.gap, c.token - tokens);
    _append_script_main(c, statements);
    p.hoisting = p.runs = 0;
  }
}

/* Parses one form, or skips a failed one whole. Returns 0 when the parse
   stops: the error limit is reached, or the skip reached the end. */
static int _form(FullParse &p) {
  Compiler c = p.c;
  Token start = c.token;
  int braces = c.braces.len();
  try {
    _parse(p, start);
  }
  catch %(malformed (category ?category) *): {
    (void) category;
    if (c.diagnostics.reached_limit()) return 0;
    _sync_top_level(c, start, braces);
    p.gap = _end_index(c, c.tokenizer.tokens);
    _append_preproc(c, p.nodes);
    return c.peek(0) != <eof>;
  }
  return 1;
}

static void _parse(FullParse &p, Token start) {
  Compiler c = p.c;
  Token tokens = c.tokenizer.tokens;
  int begin = start - tokens;
  if (p.hoisting) _push_conditionals(c, p.statements, p.gap, begin);
  if (p.hoisting && c.script_statement_starts()) _hoist(p, begin, tokens);
  else _top_level(p, begin, tokens);
  p.gap = _end_index(c, tokens);
  _append_preproc(c, p.nodes);
  _debug_tokens(start, c.token);
}

// A script statement joins the runs that `main` executes.
static void _hoist(FullParse &p, int begin, Token tokens) {
  p.c.skip_script_statement();
  int end = _end_index(p.c, tokens);
  p.statements.push(begin);
  p.statements.push(end);
  if (!p.runs++) p.first = begin;
}

// A retained declaration bundle replays; any other form parses.
static void _top_level(FullParse &p, int begin, Token tokens) {
  Compiler c = p.c;
  _reject_statement(c);
  Ast node = c.replay_declaration_source();
  if (!node) node = c.parse_top_level();
  int end = _end_index(c, tokens);
  if (node && node.car() == <seq>)
    foreach (List item, node.cdr()) _add(p, item, begin, end);
  else if (node) _add(p, node, begin, end);
}

static void _add(FullParse &p, List node, int begin, int end) {
  Token tokens = p.c.tokenizer.tokens;
  _record_top_level(p.c, node, tokens + begin);
  _record_span(p.c, node, begin, end);
  p.nodes.push(node);
}

/* Directives join the nodes in source order, after they record native
   macro names and includes deliver their public compile-time effects. */
static void _append_preproc(Compiler c, Array nodes) {
  List directives = c.leading_preproc();
  c.note_preprocessor_macros(directives);
  if (c.included_effects.len()) c.install_included_effects();
  foreach (Var directive, directives) nodes.push(directive);
}

/* A failed declaration is skipped whole from its first token, because a
   report inside a body leaves the cursor where no declaration can start.
   The declaration ends at a `;` outside delimiters, at a closing delimiter
   whose next token begins a later line, such as a function body or a macro
   invocation, or at a `}` that nothing on its line continues. A `struct`
   body continues to its declarators, and a second function body on the
   same line is a second declaration. */
static void _sync_top_level(Compiler c, Token start, int braces) {
  c.token = start;
  c.braces.resize(braces);
  int depth = 0;
  while (c.peek(0) != <eof>) {
    Token token = c.token;
    c.next();
    if (!depth && token.type == <;>) return;
    int step = token.type.group_step();
    depth += step;
    if (depth < 0) depth = 0;
    Symbol next = c.peek(0);
    if (!depth && step < 0 &&
        (c.token.line > token.line ||
         (token.type == <"}"> && next != <ident> && next != <*> &&
          next != <;> && next != <,> && next != <(>)))
      return;
  }
}

static List _finish_parse(Compiler c, Array nodes) {
  c.finish_meta_functions(nodes);
  if (c.meta_build) c.write_meta_build();
  c.unit_nodes = NULL;
  List ast = nodes.list_free();
  if (c.script && !c.script.defines_main && !c.error_count())
    _check_script_locals(c, ast);
  _check_unmatched_braces(c);
  if (!c.error_count()) _check_static_inits(c);
  return ast;
}
