/* the parse driver

   A full parse reads the unit's top-level forms in source order. A form
   that fails is skipped whole, so one error does not hide the next. */

/** Parses and types the positioned source against `globs`.

    The result is a source-ordered top-level AST. This resets macro state
    and protocol resolution; origins live for the whole unit.
    `generated_symbols` publishes external adapter signatures before parsing.
*/
List Compiler.full_parse(Compiler c, Map globs, int generated_symbols) {
  Array nodes = [];
  c.unit_nodes = nodes;
  _reset_parse(c, globs, generated_symbols);
  if (c.script) _parse_script(c, nodes);
  else with (c.recovery_depth = c.recovery_depth + 1) {
    _append_preproc(c, nodes);
    _parse_forms(c, nodes);
  }
  List ast = _finish_parse(c, nodes);
  if (c.script) _finish_script(c, ast);
  _check_unmatched_braces(c);
  if (!c.error_count()) _check_static_inits(c);
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
  c.install_syntax_prelude();
  if (!c.declaration_produced) c.imports = {};
  c.import_stack.clear();
  c.macro_count = 0;
  c.macro_stack = NULL;
  c.source_private = 0;
}

// Reads ordinary top-level forms, including generated script functions.
module void _parse_forms(Compiler c, Array nodes) {
  while (c.peek(0) != <eof>) if (!_form(c, nodes)) break;
}

// Parses one form, or recovers at the next whole form.
static int _form(Compiler c, Array nodes) {
  Token start = c.token;
  int braces = c.braces.len();
  try {
    _top_level(c, nodes);
    _append_preproc(c, nodes);
    _debug_tokens(start, c.token);
  }
  catch %(malformed (category ?category) *): {
    (void) category;
    if (!_recover_form(c, start, braces)) return 0;
    _append_preproc(c, nodes);
    return c.peek(0) != <eof>;
  }
  return 1;
}

// A retained declaration bundle replays; any other form parses.
module void _top_level(Compiler c, Array nodes) {
  Token tokens = c.tokenizer.tokens;
  int begin = c.token - tokens;
  Ast node = c.replay_declaration_source();
  if (!node) node = c.parse_top_level();
  int end = _end_index(c, tokens);
  if (node && node.car() == <seq>)
    foreach (List item in node.cdr()) _add(c, nodes, item, begin, end);
  else if (node) _add(c, nodes, node, begin, end);
}

static void _add(Compiler c, Array nodes, List node, int begin, int end) {
  Token tokens = c.tokenizer.tokens;
  _record_top_level(c, node, tokens + begin);
  _record_span(c, node, begin, end);
  nodes.push(node);
}

// Stops at the error limit; otherwise restores the next form's cursor.
module int _recover_form(Compiler c, Token start, int braces) {
  if (c.diagnostics.reached_limit()) return 0;
  _sync_top_level(c, start, braces);
  return 1;
}

/* Directives join the nodes in source order, after they record native
   macro names and includes deliver their public compile-time effects. */
module void _append_preproc(Compiler c, Array nodes) {
  List directives = c.leading_preproc();
  c.note_preprocessor_macros(directives);
  if (c.included_effects.len()) c.install_included_effects();
  foreach (List directive in directives) nodes.push(directive);
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
  if (c.load_source && !c.error_count()) c.prepare_loaded_main(nodes);
  c.finish_meta_functions(nodes);
  if (c.load_source && !c.error_count()) c.prepare_loaded_functions(nodes);
  if (c.meta_build) c.write_meta_build();
  c.unit_nodes = NULL;
  return nodes.list_free();
}
