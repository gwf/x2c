// shallow collection

/** Collects file-scope declarations into `globals` without parsing bodies. */
void Compiler.shallow_parse(Compiler c, Map globals) {
  c.macros = {};
  c.kw_aliases = {};
  c.binding_rows = c.binding_sealed = NULL;
  c.sym.reset(globals);
  _shallow_parse_loop(c);
  _check_unmatched_braces(c);
}

/** Collects declarations with reads over `base` then `overlay`.

    Writes go to `overlay`, which captures exactly what this translation
    contributes above `base`.
*/
void Compiler.shallow_parse_overlay(Compiler c, Map base, Map overlay) {
  if (c.macros == NULL || !c.macros.len()) _start_macros(c);
  c.sym.reset_overlay(base, overlay);
  _shallow_parse_loop(c);
  // Only linkage groups remain open; a later segment of the file closes them.
  c.open_linkage += c.braces.len();
}

/* A unit with no macros yet starts its macro and keyword state, and the
   Lisp binding groups that state records. */
static void _start_macros(Compiler c) {
  c.macros = {};
  if (c.kw_aliases == NULL) c.kw_aliases = {};
  c.binding_rows = c.binding_sealed = NULL;
}

static void _shallow_parse_loop(Compiler c) {
  c.start_collection();
  c.braces.clear();
  while (c.peek(0) != <eof>) {
    Token start = c.token;
    if (c.package && c.line_markers && c.source_private < 0) {
      int line = start.line;
      String package = c.owns_package_source(c.token_source(start, line))
                     ? c.package : NULL;
      with (c.package = package) { (void) c.parse_top_level_mode(1); }
    }
    else (void) c.parse_top_level_mode(1);
    _debug_tokens(start, c.token);
  }
  /* Definitions after the last declaration, as before an include, still
     define macros for the segments that follow. */
  foreach (List directive in c.leading_preproc())
    c.note_object_macro(directive.cadr());
  c.shallow = 0;
}

/** Starts a collection pass with the built-in macros. It parses no bodies,
    and an import it reads installs the protocols visible to it when a
    template or `meta` body first asks for one. */
void Compiler.start_collection(Compiler c) {
  c.install_builtin_macros();
  c.rebuild_protocols(NULL);
  c.import_protocols = 1;
  c.conforms = {};
  c.shallow = 1;
}

module void _debug_tokens(Token start, Token end) {
  if (!log_should_log(<debug>, <tokenizer>)) return;
  for (Token tok = start; tok < end; tok++)
    if (tok.type != <space> && tok.type != <comment> && tok.type != <preproc>)
      $debug.compiler_token(tok);
}

/** Collects macro definitions or keyword aliases before the full source parse.
    The owning source reports malformed definitions during its full parse,
    which can recover at later forms. Included providers reject them here.
*/
void Compiler.collect_compile_time_definition(Compiler c, int keyword) {
  if (c.interface_provider) {
    if (keyword) c.parse_keyword_definition();
    else c.parse_macro_definition();
    return;
  }
  int failed = 0;
  DiagnosticsHold hold = c.diagnostics.hold();
  with (c.recovery_depth = c.recovery_depth + 1) {
    try {
      if (keyword) c.parse_keyword_definition();
      else c.parse_macro_definition();
    }
    catch %(malformed *): failed = 1;
  }
  c.diagnostics.release(hold, 0);
  if (failed) while (c.peek(0) != <eof>) c.next();
}

/** Records declaration visibility and meta facts, then skips its body.
    The declaration is already bound by the shared top-level parser.
*/
void Compiler.finish_collected_declaration(
  Compiler c, List declaration, Token meta, int native) {
  /* Collection records the runtime function a `meta` marker precedes, the
     native binding a bodyless or `native` marker advertises, and the stub
     of a bodied one; the full parse installs the compile-time form. */
  c.record_declaration_visibility(declaration);
  /* Lexical privacy also marks a name in Sym.statics, so a static function
     is marked again as `(function name)`. File collection reads that key to
     keep the function out of an ordinary include's interface. */
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ((fnmod *) *)))):
      if (type.type().is_static())
        c.sym.mark_static(%(function ${Ast.binding_spelling(binding)}));
  if (c.peek(0) == <"{"> || c.peek(0) == <"%{"> || _x2c_at_function_arrow(c))
    _skip_body(c, declaration, meta, native);
  else if (c.peek(0) == <;>) {
    if (meta) c.record_native_meta_effect(declaration, meta);
    c.next();
  }
  else c.next();
}

static void _skip_body(
  Compiler c, List declaration, Token meta, int native) {
  if (native) c.record_native_meta_effect(declaration, meta);
  else if (meta) c.record_project_meta_effect(declaration, meta);
  match (declaration)
    case %(declare ? (bindings (bind ?binding ?))):
      _note_function_body(c, declaration.type_from_ast(), binding);
  c.record_inline_function(declaration);
  if (_x2c_at_function_arrow(c)) {
    c.next();
    c.next();
    _x2c_skip_shallow_expression(c, 0);
    c.expect(<;>);
  }
  else _shallow_block(c);
}

/** Records the header linkage of a public inline definition. Semantic
    function types discard storage, so this declaration fact survives there. */
void Compiler.record_inline_function(Compiler c, List declaration) {
  Type type = declaration.type_from_ast();
  if (!type.is_inline() || type.is_static() || c.source_private) return;
  match (declaration)
    case %(declare ? (bindings (bind ?binding ?))): {
      String name = Ast.binding_spelling(binding);
      c.sym.set(%("function-inline" $name), %(inline));
    }
}

// `fn_defs` holds each non-static function the unit defines.
static void _note_function_body(Compiler c, Type type, List binding) {
  if (!type.is_function() || type.is_static()) return;
  c.fn_defs[Ast.binding_spelling(binding)] = 1;
}

/* Reports whether the current two tokens are `=>`. */
int _x2c_at_function_arrow(Compiler c) =>
  c.peek(0) == <=> && c.peek(1) == <">">;

/* Skips a balanced shallow expression without consuming its terminator.
    A top-level comma also terminates the expression when `stop_at_comma` is
    nonzero.
*/
void _x2c_skip_shallow_expression(Compiler c, int stop_at_comma) {
  for (Symbol type = c.peek(0);
       type != <eof> && type != <;> && (!stop_at_comma || type != <,>);
       type = c.peek(0)) {
    if (type.group_step() > 0) c.token = c.token.after_group();
    else c.next();
  }
}

static void _shallow_block(Compiler c) {
  c.next();
  for (Symbol peek = c.peek(0); peek != <"}">; peek = c.peek(0)) {
    if (peek == <eof>)
      $fail.compiler_token_eof(c, c.token);
    if (peek == <"{"> || peek == <"%{"> || peek == <"${"> || peek == <"@{">)
      _shallow_block(c);
    else c.next();
  }
  c.expect(<"}">);
}
