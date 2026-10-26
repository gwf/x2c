/*  units.x -- top-level forms and definitions

    Copyright (c) 2025 Gary William Flake.
*/

// top-level forms

/** Parses one top-level form and applies its source-ordered compiler effects.
    Returns its AST, or NULL when a keyword definition, linkage brace, or
    compile-time-only `meta` function only updates compiler state, with the
    first following token current. With `skip_body`, collection uses the
    same classifier and bound declarations but skips runtime bodies.
    This continuation is independent of the compiler's shallow-parse state.
*/
List Compiler.parse_top_level_mode(Compiler c, int skip_body) {
  _leading_directives(c, skip_body);
  if (_skip_linkage_brace(c)) return NULL;
  if (skip_body && c.skip_collected_script_statement()) return NULL;
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = skip_body ? NULL : c.try_parse_macro_slot(<unit>);
  if (slot) return slot;
  if (c.keyword_form_is_definition()) return _keyword_definition(c, skip_body);
  if (c.alias_form_starts()) return c.parse_alias_declaration(skip_body);
  if (_module_storage_form(c)) {
    c.token.type = <static>;
    with (c.module_declaration = 1) {
      return c.parse_top_level_mode(skip_body);
    }
  }
  if (_static_interface_form(c)) {
    c.next();
    with (c.source_private = 1) {
      List retained = skip_body ? NULL : c.replay_declaration_source();
      return retained ? retained : c.parse_top_level_mode(skip_body);
    }
  }
  if (skip_body) {
    if (c.protocol_form_starts()) return c.parse_protocol_declaration();
    if (_skip_collected_form(c)) return NULL;
  }
  List macro = skip_body ? NULL : c.try_parse_macro_target_at(<unit>);
  if (macro) return macro;
  if (c.protocol_form_starts()) return c.parse_protocol_declaration();
  switch (c.peek(0)) {
    case <import>:
      if (c.signature_only) {
        _x2c_skip_shallow_expression(c, 0);
        c.expect(<;>);
        return NULL;
      }
      return _parse_import_declaration(c);
    case <@>:      return _top_level_decorator(c);
    case <$>:
      if ((c.token + 1).type == <(> || (c.token + 1).type == <"{">)
        $fail.parse_collection_top(c, c.token);
  }
  if (c.macro_form_is_definition()) return c.parse_macro_definition();
  return _declaration_form(c, skip_body);
}

/* Static storage also applies to source types and protocols. */
static int _static_interface_form(Compiler c) {
  if (c.peek(0) != <static>) return 0;
  Token next = Token.skip_trivia(c.token + 1);
  return next.type == <typedef> || next.type == <protocol> ||
         next.text == "class";
}

/* `module` before a file-scope declaration declares a static name for
   every file of the module unit. Its token becomes `static`, so the
   declaration parses as a static one. The token's text stays `module`, so
   a later parse of the same tokens recognizes it again. `module {` opens
   the member block instead. */
static int _module_storage_form(Compiler c) {
  Symbol word = c.peek(0);
  if (c.module_declaration || (word != <ident> && word != <static>) ||
      c.token.text != "module" || c.sym.get(%("module"))) return 0;
  Symbol next = Token.skip_trivia(c.token + 1).type;
  return next == <ident> || next == <typedef> || next == <inline> ||
         next.is_type_qualifier() || next.is_builtin_type();
}

/* Directives record native macro names and, in the full parse, the
   conditional groups around the form. A template's forms have neither. */
static void _leading_directives(Compiler c, int skip_body) {
  if (c.macro_holes) return;
  c.note_preprocessor_macros(c.leading_preproc());
  if (!skip_body) _track_conditional_arms(c);
}

/* Takes the conditional groups open after the last conditional directive
   before the current top-level form. */
static void _track_conditional_arms(Compiler c) {
  Token base = c.tokenizer.tokens;
  Var stack;
  for (Token token = c.token - 1; token >= base &&
       (token.type == <space> || token.type == <comment> ||
        token.type == <preproc>); token--)
    if (c.arm_stacks.try_get((long) (token - base), stack)) {
      c.arms = stack;
      return;
    }
}

/* Consumes one brace of a C linkage specification at file scope and reports
   whether it did. `extern "C" {` opens a group; a `}` at file scope closes
   the innermost open group, because every other file-scope form consumes
   its own braces. The declarations between them stay at file scope. The
   `#ifdef __cplusplus` arm of the usual header guard is skipped, so only an
   unguarded group reaches this operation.
*/
static int _skip_linkage_brace(Compiler c) {
  if (c.peek(0) == <extern> && c.peek(1) == <lit-char*> &&
      c.peek(2) == <"{">) {
    c.next();
    c.next();
  }
  else if (c.peek(0) != <"}">) return 0;
  else if (!c.braces.len()) {
    // The group opened before an include, in an earlier segment.
    if (!c.open_linkage) return 0;
    c.open_linkage--;
    c.token = Token.skip_trivia(c.token + 1);
    return 1;
  }
  c.next();
  return 1;
}

static List _keyword_definition(Compiler c, int skip_body) {
  if (skip_body) c.collect_compile_time_definition(1);
  else c.parse_keyword_definition();
  return NULL;
}

/* Collection records a macro definition, skips a named type unless it
   collects protocols, and expands or skips unit macro invocations. It
   reports whether that finished the form. */
static int _skip_collected_form(Compiler c) {
  if (c.macro_form_is_definition()) {
    c.collect_compile_time_definition(0);
    return 1;
  }
  if ((!c.collect_protocols || c.signature_only) &&
      c.skip_named_type_declaration()) return 1;
  if (!c.macro_starts_target_at(<unit>)) return 0;
  if (!c.signature_only && c.collect_protocols &&
      c.collect_unit_macro()) return 1;
  do {
    c.skip_macro_invocation();
    if (c.test(<;>)) return 1;
  } while (c.macro_starts_target_at(<unit>));
  return 0;
}

static List _top_level_decorator(Compiler c) {
  $fail.parse_decorator_top(c, c.token);
}

/* A declaration row after any `meta` marker. Collection records it; the
   full parse completes a declaration at `;` or a definition at its body. */
static List _declaration_form(Compiler c, int skip_body) {
  Token meta = NULL;
  int native = 0;
  if (c.meta_form_is_declaration()) meta = _take_meta_marker(c, native);
  Token first = c.token;
  List decl;
  with (c.module_declaration = c.module_declaration || meta != NULL,
        c.shallow = c.shallow || c.public_bodies,
        c.macro_holes =
          c.signature_only && !c.macro_holes ? {} : c.macro_holes) {
    decl = c.parse_declaration_row();
  }
  int body = c.peek(0) == <"{"> || _x2c_at_function_arrow(c);
  Type type = decl.type_from_ast();
  if (skip_body || (c.public_bodies && body &&
      (!type.is_inline() || type.is_static() || c.source_private))) {
    c.finish_collected_declaration(decl, meta, native);
    _record_meta_hash(c, decl, first, body);
    if (meta && !native && body)
      c.install_collected_meta_function(decl, meta);
    return NULL;
  }
  if (native && !type.is_function())
    $fail.parse_meta_function(c, meta);
  if (c.test(<;>)) return _declared(c, decl, meta, first);
  if (body) return _defined(c, decl, meta, native, first);
  c.require_input();
  Symbol unexpected = c.peek(0);
  $fail.parse_body_expected(c, c.token, unexpected);
}

/** Parses one full top-level form through the shared classifier. */
List Compiler.parse_top_level(Compiler c) => c.parse_top_level_mode(0);

/** Parses one submission from the current token stream. `end_position` is
    the byte offset after supplied input, before any synthetic closing text.
    Missing required syntax raises `<incomplete>`; trailing items are rejected.
    Temporary parser scopes and captured parameters are restored on every exit.
    The caller owns the semantic transaction and commits after execution.
*/
List Compiler.parse_submission(Compiler c, int end_position) {
  Token boundary = c.input_boundary;
  SymScope params = c.params;
  int scope_count = c.sym.scope_count();
  defer {
    while (c.sym.scope_count() > scope_count) (void) c.sym.pop_scope();
    c.params = params;
    c.input_boundary = boundary;
  }
  Token token = c.token;
  while (token.type != <eof> && token.pos < end_position) token++;
  c.input_boundary = token;
  List result = c.parse_top_level();
  if (c.peek(0) != <eof>)
    $fail.parse_unit_single(c, c.token);
  return result;
}

// script units

/** Reports whether the unit's tokens define a function named `main` at file
    scope. A script unit that does is an ordinary program: its declarations
    stay at file scope and it may not have top-level statements. Both parse
    passes read the same tokens, so they agree before either parses.
*/
int Compiler.defines_main(Compiler c) {
  for (Token token = Token.skip_trivia(c.tokenizer.tokens);
       token.type != <eof>; token = token.after_group()) {
    Token open = Token.skip_trivia(token + 1);
    if (token.type != <ident> || token.text != "main" || open.type != <(>)
      continue;
    Token body = open.after_group();
    if (body.type == <"{"> || (body.type == <=> &&
        Token.skip_trivia(body + 1).type == <">">))
      return 1;
  }
  return 0;
}

/** Reports whether the top-level item at the cursor is one of a script
    unit's statements, which become `main`'s body.
    Preprocessor lines, imports, protocols, compile-time definitions,
    file-scope macro invocations, `typedef`, `static`, and `extern`
    declarations, linkage braces, type definitions, and function prototypes
    and definitions stay at file scope. This query does not consume tokens.
*/
int Compiler.script_statement_starts(Compiler c) {
  switch (c.peek(0)) {
    case <eof>: case <import>: case <protocol>:
    case <typedef>: case <static>: case <extern>: case <"}">:
      return 0;
  }
  if (_module_storage_form(c)) return 0;
  if (c.test_static_assert() || c.keyword_form_is_definition() ||
      c.macro_form_is_definition() || c.meta_form_is_declaration() ||
      c.protocol_form_starts())
    return 0;
  if (c.peek(0) == <auto>) return c.auto_region_form(<unit>) != <function>;
  if (c.alias_form_starts()) return 0;
  if (c.at_word("with")) return 1;
  if (c.macro_starts_target_at(<unit>)) return !c.macro_targets_unit();
  return !c.test_declaration() || !_declaration_stays(c);
}

/* A declaration in a script unit stays at file scope when a body follows
   its declarator, `{` for a function or aggregate and `=>` for an
   expression-bodied function, or when it ends right after a parameter list
   as a prototype does. An initialized or plain object declaration belongs
   to `main`. */
module int _declaration_stays(Compiler c) {
  Symbol previous = 0;
  for (Token token = c.token; token.type != <eof>;
       previous = token.type, token = token.after_group()) {
    if (token.type == <;>) return previous == <(>;
    if (token.type == <"{">) return 1;
    if (token.type == <=>)
      return Token.skip_trivia(token + 1).type == <">">;
  }
  return 0;
}

/** Reports whether the top-level item at the cursor is a script statement
    that runs, rather than a declaration: an expression, control flow, a
    `with` block, or a statement macro. This query does not consume tokens.
*/
int Compiler.script_statement_executes(Compiler c) =>
  c.script_statement_starts() &&
  (c.peek(0) == <$> || c.at_word("with") || !c.test_declaration() ||
   c.auto_region_form(<unit>) == <statement>);

// markers

/** Reports whether the cursor begins a protocol declaration or adoption,
    including its `meta` and `static` markers. This query does not consume
    tokens.
*/
int Compiler.protocol_form_starts(Compiler c) {
  int at = c.at_word("meta");
  if (c.peek(at) == <static>) at++;
  return c.peek(at) == <protocol>;
}

/** Reports whether the cursor begins a contextual top-level `meta`
    declaration: a function or an initialized file-static value.
*/
int Compiler.meta_form_is_declaration(Compiler c) {
  if (!c.at_word("meta")) return 0;
  Token head = c.token;
  _take_meta_marker(c, NULL);
  int marker = c.test_declaration();
  c.token = head;
  return marker;
}

/* Consumes the `meta` marker at the cursor and the contextual `native`
   marker that may follow it, and returns the `meta` token. `native` binds
   the definition after it the way a bodyless prototype would. `*native`,
   when requested, reports whether that marker was present. */
static Token _take_meta_marker(Compiler c, int &?native) {
  Token meta = c.token;
  c.next();
  Token after = c.token;
  int marked = c.take_word("native");
  if (marked) {
    Token declaration = c.token;
    marked = c.test_declaration();
    c.token = marked ? declaration : after;
  }
  if (native) native = marked;
  return meta;
}

// imports

/* Parses and registers one `import` declaration, including its semicolon.
   The alias defaults to the package name; `with` members add source-ordered
   local spellings. These spellings affect source resolution only; the package
   name in the returned AST drives the generated header include.
*/
static List _parse_import_declaration(Compiler c) {
  Token start = c.token;
  c.expect(<import>);
  String name = _package_name(c), alias = _import_alias(c, name);
  c.collect_package(name, start);
  c.register_package_alias(name, alias, start);
  List members = c.take_word("with") ? _import_members(c, name) : NULL;
  c.install_compile_time_effects(c.package_effects[name]);
  c.expect(<;>);
  if (c.shallow)
    c.sym.set(
      %("source-node" (package-import
        $(Compiler.portable_path(Path.absolute(c.filename))) $(start.pos))),
      %(package-import $name $alias $members));
  return %(import $name $alias);
}

// Rejects unquoted package names before parsing their identifier.
static String _package_name(Compiler c) {
  if (c.peek(0) != <lit-char*>)
    $fail.parse_import_name(c, c.token);
  Token name_token = c.token;
  String name = String.new_len(
    c.token.text + 1, c.token.len - 2).unescape();
  if (!name.is_identifier())
    $fail.parse_package_identifier(c, name_token);
  c.next();
  return name;
}

static String _import_alias(Compiler c, String name) {
  if (!c.take_word("as")) return name;
  if (c.peek(0) != <ident>)
    $fail.parse_alias_name(c, c.token);
  String alias = c.token.text;
  c.next();
  return alias;
}

/* with Name [as Local] {, Name [as Local]}
   Each name binds a bare local spelling to one already-built package member.
   Registration runs at the name's own token so an unknown member and a
   collision both point at the spelling the developer wrote. */
static List _import_members(Compiler c, String name) {
  Array members = [];
  do {
    if (c.peek(0) != <ident>)
      $fail.parse_import_member(c, c.token);
    Token member_token = c.token, local_token = member_token;
    String member = c.token.text, local = member;
    c.next();
    if (c.take_word("as")) {
      if (c.peek(0) != <ident>)
        $fail.parse_import_local(c, c.token);
      local_token = c.token;
      local = c.token.text;
      c.next();
    }
    c.register_package_member(
      name, member, local, member_token, local_token);
    members.push($(member, local));
  } while (c.test(<,>));
  return members.list_free();
}

// file-scope definitions

/* A declaration ends at `;`. A `meta` one installs its compile-time form
   and publishes its prose; an ordinary function prototype keeps its name
   callable at run time. */
static List _declared(Compiler c, List decl, Token meta, Token first) {
  _record_meta_hash(c, decl, first, 0);
  if (meta && decl.type_from_ast().is_function())
    c.install_native_meta_function(decl, meta);
  else if (meta) c.install_meta_declaration(decl, meta);
  c.record_declaration_visibility(decl);
  if (meta)
    _definition_source(c, decl, meta.line, c.definition_doc(meta), NULL);
  else if (decl ~= %(declare ? (bindings
                  (bind (binding ? ?(String name)) *))) &&
           decl.type_from_ast().is_function())
    c.meta_comptime.del(name);
  return decl;
}

/* A definition's body follows its declarator. A staged `meta` body parses
   as compile-time code, and a `meta` function that reaches a `Meta`
   operation exists only inside the compiler, with no runtime form. */
static List _defined(
  Compiler c, List decl, Token meta, int native, Token first) {
  if (decl ~= %(seq *))
    $fail.parse_function_row(c, c.token);
  List function;
  Token tokens = c.tokenizer.tokens;
  int start = (meta ? meta : first) - tokens;
  int body = c.token - tokens;
  Token staged = native ? NULL : meta;
  if (staged) _reject_expanded_meta(c, decl, meta);
  if (native) c.install_native_meta_function(decl, meta);
  with (c.meta_body = staged != NULL) {
    function = _finish_function(c, decl, NULL);
  }
  _record_meta_hash(c, function, first, 0);
  _publish_definition(c, decl, function, meta, staged);
  if (staged && c.capture_unit && c.shallow)
    c.record_project_meta_effect(decl, staged);
  if (!c.capture_unit && staged && c.meta_is_comptime_only(function))
    return NULL;
  if (c.macro_holes)
    return %(api-source $(first.line) $(c.definition_doc(first)) $function);
  _definition_source(c, function, first.line, NULL, $(start, body));
  return function;
}

/* A macro expansion cannot produce a bodied `meta` function: the project
   meta build extracts meta code from source files, not from expansions. */
static void _reject_expanded_meta(Compiler c, List decl, Token meta) {
  if (!c.macro_holes) return;
  String name = "";
  if (decl ~= %(declare ? (bindings (bind (binding ? ?(String own)) *))))
    name = own;
  $fail.parse_meta_constructed(c, meta, name);
}

/* Hashes functions and initialized file-static values, and records the
   names their parsed bodies reference. A linked copy answers only when
   its text and the definitions it reaches agree with the source. */
static void _record_meta_hash(
  Compiler c, List definition, Token first, int collected_body) {
  match (definition) {
    case %(seq *rows):
      _record_meta_rows(c, rows, first, collected_body);
    case %(declare ?spec (bindings *rows)) if (rows.cdr()):
      _record_meta_bindings(c, spec, rows, first, collected_body);
    case %(function ? (bind (binding ? ?(String own)) *) ?content):
      _store_meta_hash(c, own, content, first);
    case %(declare ?spec (bindings
             (op = (bind (binding ? ?(String own)) *) ?init))):
      _store_static_meta(c, spec, own, init, first);
    case %(declare ?spec (bindings
             (bind (!set ?binding (binding ? ?(String own))) *))):
      _store_collected_meta(c, spec, binding, own, first, collected_body);
  }
}

static void _record_meta_rows(
  Compiler c, List rows, Token first, int collected_body) {
  foreach (List row in rows) _record_meta_hash(c, row, first, collected_body);
}

static void _record_meta_bindings(
  Compiler c, Var spec, List bindings, Token first, int collected_body) {
  foreach (List bind in bindings)
    _record_meta_hash(
      c, %(declare $spec (bindings $bind)), first, collected_body);
}

static void _store_static_meta(
  Compiler c, Var spec, String name, Var body, Token first) {
  if (spec.type().is_static()) _store_meta_hash(c, name, body, first);
}

static void _store_collected_meta(
  Compiler c, Var spec, List binding, String name,
  Token first, int collected_body) {
  if (!c.shallow || (!collected_body &&
      (!spec.type().is_static() || !(binding in c.init_tokens)))) return;
  _store_meta_hash(c, name, void, first);
}

static void _store_meta_hash(Compiler c, String name, Var body, Token first) {
  if (!name) return;
  uint64_t hash = FNV_OFFSET_BASIS;
  for (Token token = first; token < c.token; token++)
    if (token.type != <space> && token.type != <comment> && token.len)
      hash = fnv_bytes(
        fnv_bytes(hash, token.text, token.text.len()), " ", 1);
  c.meta_hashes[name] = "%016llx".printf((unsigned long long) hash);
  if (body is void) return;
  Array names = [];
  _referenced_names(body, {}, names);
  c.meta_calls[name] = names.list_free();
}

/* Adds referenced names in source order. Deferred sibling cursors keep deep
   expression chains off the C stack without reversing their children. */
static void _referenced_names(Var node, Map seen, Array names) {
  Array pending = auto [];
  List rest = $(node);
  while (rest || pending.len()) {
    if (!rest) {
      rest = pending.take_last();
      continue;
    }
    Var current = rest.car();
    rest = rest.cdr();
    if (current is not <list>) continue;
    List syntax = current;
    match (syntax)
      case $source_identifier_content(%((binding ? ?name))): {
        if (name is not <string>) break;
        String spelling = name;
        if (!(spelling in seen)) {
          seen[spelling] = 1;
          names.push(spelling);
        }
        continue;
      }
    if (rest) pending.push(rest);
    rest = syntax;
  }
}

/* A staged `meta` definition installs its compile-time form unless the
   compiler's linked copy answers for it. Compile-time only describes a
   `meta` definition: an ordinary declaration or definition of the same
   name, such as a copy the compiler links, is callable at run time. */
static void _publish_definition(
  Compiler c, List decl, List function, Token meta, Token staged) {
  if (staged && !c.bind_linked_meta(
    function, decl.type_from_ast().canonicalize()))
    c.install_meta_function(function, staged);
  c.record_declaration_visibility(function);
  if (!meta && function ~= %(
        function ? (bind (binding ? ?(String name)) *) ?))
    c.meta_comptime.del(name);
}

/* A generated default that completes a documented `meta` prototype
   publishes the prototype's prose. */
module void _definition_source(
  Compiler c, List function, int line, String doc, List declarator) {
  match (function) {
    case %(function ? (bind ?binding ?) ?):
      c.set_fact(%(api-definition $binding), $(line, doc, declarator));
    case %(declare ? (bindings (bind ?binding ?))):
      if (doc && function.type_from_ast().is_function())
        c.set_fact(
          %(api-definition $binding), $(line, doc, declarator));
  }
}

/** Returns the body of the doc comment that documents the definition
    starting at `start`, or NULL. A doc comment opens with two asterisks and
    ends on the line before `start` or on its line. Macro templates carry the
    text until their selected body binds at the invocation.
*/
String Compiler.definition_doc(Compiler c, Token start) {
  Token first = c.tokenizer.tokens;
  if (start <= first) return NULL;
  Token token = start - 1;
  while (token > first && token.type == <space>) token--;
  if (token.type != <comment> || token.len < 5 ||
      !token.text.startswith("/**")) return NULL;
  int lines = 0;
  for (int position = token.pos + token.len; position < start.pos;
       position++)
    if (c.text[position] == '\n' && ++lines > 1) return NULL;
  return String.new_len(token.text + 3, token.len - 5);
}

// constructed file-scope forms

/* A definition an API source form wraps keeps its line and doc comment,
   or those of the invocation that expands it. */
module List _bind_api_source(Compiler c, Var line, Var doc, Var syntax) {
  List bound = c.bind_syntax(syntax, <unit>, c.return_type);
  Token invocation = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
  String invocation_doc = invocation ? c.definition_doc(invocation) : NULL;
  line = invocation ? invocation.line : line;
  doc = invocation_doc ? invocation_doc : _filled_doc(c, doc);
  if (c.shallow) return %(api-source $line $doc $bound);
  _definition_source(c, bound, line, doc, NULL);
  return bound;
}

/* A template's doc comment writes a hole as `$name`. A hole the active
   expansion bound reads as its argument; other text stays as written. */
static String _filled_doc(Compiler c, String doc) {
  if (!doc || !c.macro_stack || doc.find("$") < 0) return doc;
  Map spellings = _hole_spellings(c);
  Buffer out = Buffer.new(0);
  for (char *text = doc; *text;) {
    int named = *text == '$' &&
      (scan_ascii_alpha((unsigned char) text[1]) || text[1] == '_');
    int length = named ? scan_identifier(text + 1) : 0;
    Var spelling = length ? spellings[String.new_len(text + 1, length)] : void;
    if (spelling is void) out.write_char(*text++);
    else {
      out.write(spelling);
      text += length + 1;
    }
  }
  return out.str_free();
}

/* The active expansion's holes as prose spells them: a name as it is, and
   syntax as an invocation in this file wrote it, when the file's text is
   loaded. Forwarding keeps the original source wrapper, so the inner hole
   reads as the outer argument, even when two arguments have equal syntax. */
static Map _hole_spellings(Compiler c) {
  Map written = {}, spellings = {};
  String file = Path.resolved_absolute(c.filename);
  foreach (List frame in c.macro_stack)
    foreach (List binding in frame[2])
      if (binding ~= %(? (src (source ?(String path) ?(int begin)
                                  ?(int end)) ?syntax)) &&
          c.text && path == file)
        written[syntax] = String.new_len(c.text + begin, end - begin);
  foreach (List binding in c.macro_stack.car().list()[2]) {
    (Var binder, Var value) = binding;
    Var syntax = value;
    if (value ~= %(src ? ?captured)) syntax = captured;
    Var spelling = syntax is <string> ? syntax : void;
    if (value ~= %(src (source ?(String path) ?(int begin)
                         ?(int end)) ?) &&
        spelling is void && c.text && path == file)
      spelling = String.new_len(c.text + begin, end - begin);
    if (spelling is void) spelling = written[syntax];
    if (spelling is not void) spellings[binder.str()[1:]] = spelling;
  }
  return spellings;
}

module List _bind_named_type(Compiler c, String name, Var type) {
  List key = $(name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (!type.list_payload()) return %(seq);
  List declaration = type.type().declaration_ast(key);
  if (declaration ~= %(declare ?base ?bindings))
    return c.bind_syntax(%(typedef $base $bindings), <unit>, NULL);
  return _construction_error(c);
}

/* Binds a declaration bundle's rows in order. Collection returns the rows
   as a bundle. */
module List _bind_bundle(Compiler c, List rows) {
  if (c.shallow) c.declaration_produced = 1;
  Array projected = [];
  foreach (List row in rows) {
    List bound = c.bind_syntax(row, <unit>, c.return_type);
    _append_rows(projected, bound);
  }
  List items = projected.list_free();
  return c.shallow ? %(declaration-bundle (rows @items)) : %(seq @items);
}

static void _append_rows(Array output, List syntax) {
  match (syntax) {
    case %(seq *rows):
      foreach (List row in rows) _append_rows(output, row);
    case %(declaration-bundle (rows *rows)):
      foreach (List row in rows) _append_rows(output, row);
    default: output.push(syntax);
  }
}

module List _bind_recipe(
  Compiler c, Var callback, Var arguments, Symbol context) {
  Var syntax = c.evaluate_declaration_recipe(callback, arguments);
  return c.bind_syntax(syntax, context, c.return_type);
}

/* Collection keeps a declaration recipe pending with the macro stack that
   constructed it; the full parse evaluates it. */
module List _bind_decl_recipe(Compiler c, Var callback, Var arguments) {
  if (c.shallow)
    return %(declaration-pending $callback $arguments
              $(c.macro_stack) $(c.source_private));
  return _bind_recipe(c, callback, arguments, <unit>);
}

module List _bind_default(Compiler c, Var function) {
  if (c.shallow)
    return %(declaration-default $function $(c.macro_stack)
              $(c.source_private));
  return c.bind_syntax(function, <unit>, c.return_type);
}

/* Binds a local macro definition in a block and publishes any other one
   at file scope. */
module List _bind_macrodef(Compiler c, Var definition, Symbol context) {
  List macro = definition;
  int local = macro.assoc(<local>).int();
  if (local && context == <block>) {
    c.sym.define_macro(macro.assoc(<name>), macro);
    return %(seq);
  }
  if (!local && context == <unit>)
    return c.publish_macro_definition_node(macro);
  return _construction_error(c);
}

module List _bind_preproc(Compiler c, List directive) {
  c.note_preprocessor_macros($(directive));
  return directive;
}

module List _bind_alias(Compiler c, Var declaration, Var native) {
  List bound = c.bind_syntax(declaration, <unit>, c.return_type);
  return c.finish_foreign_alias(bound, native);
}

// foreign aliases

/** Constructs a foreign alias from one direct function declaration and target.
    `native_syntax` must resolve to a different direct identifier and, when
    typed, a function. Storage is limited to `static` or `inline`, when
    present, and variadic parameters are rejected.
*/
List Compiler.finish_foreign_alias(
  Compiler c, List declaration, List native_syntax) {
  match (declaration) {
    case %(function *):
      $fail.parse_alias_body(c, c.token);
    /* A function returning a pointer puts its pointer modifiers after the
       fnmod. The trailing modifiers are the return type's pointer depth; the
       declaration is still one direct function. */
    case %(declare (!set ?base (*))
           (bindings
             (bind ?binding ((fnmod (params *parameters)) *)))): {
      _alias_storage(c, base);
      _alias_parameters(c, parameters);
      return _alias_target(c, declaration, binding, native_syntax);
    }
  }
  $fail.parse_alias_target(c, c.token);
}

static void _alias_storage(Compiler c, Var base) {
  foreach (Var part in base) {
    if (part is not <symbol>) continue;
    Symbol specifier = part;
    if (specifier.is_storage_class() && specifier != <static>)
      $fail.parse_alias_storage(c, c.token);
  }
}

static void _alias_parameters(Compiler c, List parameters) {
  foreach (Var parameter in parameters)
    if (parameter ~= %(...)) $fail.parse_alias_variadic(c, c.token);
}

static List _alias_target(
  Compiler c, List declaration, Var binding, List native_syntax) {
  List native = c.resolve_expression(native_syntax, c.token);
  if (native ~= %(expr (!set ?native_type (*))
                  $($source_identifier_content(%(?native_binding))))) {
    if (native_type && !native_type.type().is_function())
      $fail.parse_alias_function(c, c.token, native_type);
    if (List.equal(binding, native_binding))
      $fail.parse_alias_self(c, c.token);
    return %(falias $declaration $native_binding);
  }
  $fail.parse_alias_identifier(c, c.token);
}
