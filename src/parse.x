/*  parse.x -- x2c declarations, parsed from source or constructed

    Copyright (c) 2025 Gary William Flake.

    This module owns declarations and the top-level forms that hold them.
    One classifier reads each top-level form in collection and in the full
    parse. Each declarator installs its name in the current Sym before its
    initializer resolves, and syntax that macros and compile-time Lisp
    construct binds through the same declaration operations. Expressions,
    statements, and literals parse in their own modules.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#include "type.x"
#pragma private
$(import "../src/parse-report-macros.xmacro")
$(import "../src/grammar.xmacro")
#include "statements.x"
#include "expressions.x"
#include "literals.x"
#include "collect.x"
#include "macros.x"
#include "protocol.x"
#include "utils.x"

// top-level forms

/** Parses one top-level form and applies its source-ordered compiler effects.
    Returns its AST, or NULL when a keyword definition, top-level Lisp form,
    linkage brace, or compile-time-only `meta` function only updates compiler
    state, with the first following token current. A macro import whose
    `.xmacro` makes `meta` declarations retains their runtime forms, which
    the unit emits where it reaches them. With `skip_body`, collection uses
    the same classifier and bound declarations but skips runtime bodies.
    This continuation is independent of the compiler's shallow-parse state.
*/
List Compiler.parse_top_level_mode(Compiler c, int skip_body) {
  c._leading_directives(skip_body);
  if (c.skip_linkage_brace()) return NULL;
  if (skip_body && c.skip_collected_script_statement()) return NULL;
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = skip_body ? NULL : c.try_parse_macro_slot(<unit>);
  if (slot) return slot;
  if (c.keyword_form_is_definition()) return c._keyword_definition(skip_body);
  if (skip_body) {
    if (c.protocol_form_starts()) return c.parse_protocol_declaration();
    if (c._skip_collected_form()) return NULL;
  }
  List macro = skip_body ? NULL : c.try_parse_macro_target_at(AST_UNIT);
  if (macro) return macro;
  if (c.protocol_form_starts()) return c.parse_protocol_declaration();
  switch (c.peek(0)) {
    case <import>: return c.parse_import_declaration();
    case <"$(">:   return c._top_level_lisp(skip_body);
    case <@>:      return c._top_level_decorator();
  }
  if (c.macro_form_is_definition()) return c.parse_macro_definition();
  return c._declaration_form(skip_body);
}

/* The directives before a form set its visibility and, in the full parse,
   the conditional groups it is in. A template's forms have neither. */
static void Compiler._leading_directives(Compiler c, int skip_body) {
  if (c.macro_holes) return;
  c.update_source_visibility(c.leading_preproc());
  if (!skip_body) c._track_conditional_arms();
}

/* Takes the conditional groups open after the last conditional directive
   before the current top-level form. */
static void Compiler._track_conditional_arms(Compiler c) {
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

/** Consumes one brace of a C linkage specification at file scope and reports
    whether it did. `extern "C" {` opens a group; a `}` at file scope closes
    the innermost open group, because every other file-scope form consumes
    its own braces. The declarations between them stay at file scope. The
    `#ifdef __cplusplus` arm of the usual header guard is skipped, so only an
    unguarded group reaches this operation.
*/
int Compiler.skip_linkage_brace(Compiler c) {
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

static List Compiler._keyword_definition(Compiler c, int skip_body) {
  if (skip_body) c.collect_compile_time_definition(1);
  else c.parse_keyword_definition();
  return NULL;
}

/* Collection records a macro definition, skips a named type unless it
   collects protocols, and expands or skips unit macro invocations. It
   reports whether that finished the form. */
static int Compiler._skip_collected_form(Compiler c) {
  if (c.macro_form_is_definition()) {
    c.collect_compile_time_definition(0);
    return 1;
  }
  if (!c.collect_protocols && c.skip_named_type_declaration()) return 1;
  if (!c.macro_starts_target_at(AST_UNIT)) return 0;
  if (c.collect_protocols && c.collect_unit_macro()) return 1;
  do {
    c.skip_macro_invocation();
    if (c.test(<;>)) return 1;
  } while (c.macro_starts_target_at(AST_UNIT));
  return 0;
}

/* Top-level Lisp updates compiler state only. The `meta` declarations of a
   macro import keep their runtime forms for the unit to emit. */
static List Compiler._top_level_lisp(Compiler c, int skip_body) {
  if (skip_body) {
    c.parse_macro_lisp_shallow();
    return NULL;
  }
  List imported = c.parse_macro_lisp_top_level();
  if (imported) foreach (Var definition, imported.cdr())
    c.meta_defs.push(definition);
  c.record_meta_import();
  return NULL;
}

macro Statement $report.parse_decorator_top(Expr $c) {
  $c.report_error(
    <parse>, "top-level decorators are not supported",
    $c.token, %( "module initialization: void TYPE.initialize(void)" ));
}

static List Compiler._top_level_decorator(Compiler c) {
  $report.parse_decorator_top(c);
}

macro Statement $report.parse_body_expected(Expr $c, Expr $unexpected) {
  $c.report_error(
    <parse>, "expected ';', '{', or '=>'",
    $c.token, %("token:" ${$c.token.text} "symbol:" ${$unexpected.str()}));
}

macro Statement $report.parse_meta_function(Expr $c, Expr $origin) {
  $c.report_error(
    <parse>, "a native meta declaration must be a function",
    $origin, NULL);
}

/* A declaration row after any `meta` marker. Collection records it; the
   full parse completes a declaration at `;` or a definition at its body. */
static List Compiler._declaration_form(Compiler c, int skip_body) {
  Token meta = NULL;
  int native = 0;
  if (c.meta_form_is_declaration()) meta = c.take_meta_marker(native);
  Token first = c.token;
  List decl = c.parse_declaration_row();
  if (skip_body) {
    int body = c.peek(0) == <"{"> || c._at_function_arrow();
    c.finish_collected_declaration(decl, meta, native);
    c._record_meta_hash(decl, first, body);
    return NULL;
  }
  if (native && !decl.type_from_ast().is_function())
    $report.parse_meta_function(c, meta);
  if (c.test(<;>)) return c._declared(decl, meta, first);
  if (c.peek(0) == <"{"> || c._at_function_arrow())
    return c._defined(decl, meta, native, first);
  c.require_input();
  Symbol unexpected = c.peek(0);
  $report.parse_body_expected(c, unexpected);
}

/** Parses one full top-level form through the shared classifier. */
List Compiler.parse_top_level(Compiler c) => c.parse_top_level_mode(0);

macro Statement $report.parse_unit_single(Expr $c) {
  $c.report_error(
    <parse>, "submit one top-level item at a time",
    $c.token, NULL);
}

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
    $report.parse_unit_single(c);
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
    Preprocessor lines, imports, protocols, compile-time definitions and
    Lisp, file-scope macro invocations, `typedef`, `static`, and `extern`
    declarations, linkage braces, type definitions, and function prototypes
    and definitions stay at file scope. This query does not consume tokens.
*/
int Compiler.script_statement_starts(Compiler c) {
  switch (c.peek(0)) {
    case <eof>: case <import>: case <protocol>: case <"$(">:
    case <typedef>: case <static>: case <extern>: case <"}">:
      return 0;
  }
  if (c.test_static_assert() || c.keyword_form_is_definition() ||
      c.macro_form_is_definition() || c.meta_form_is_declaration() ||
      c.protocol_form_starts())
    return 0;
  if (c.at_word("with")) return 1;
  if (c.macro_starts_target_at(AST_UNIT)) return !c.macro_targets_unit();
  return !c.test_declaration() || !c._declaration_stays();
}

/* A declaration in a script unit stays at file scope when a body follows
   its declarator, `{` for a function or aggregate and `=>` for an
   expression-bodied function, or when it ends right after a parameter list
   as a prototype does. An initialized or plain object declaration belongs
   to `main`. */
static int Compiler._declaration_stays(Compiler c) {
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
  (c.peek(0) == <$> || c.at_word("with") || !c.test_declaration());

// markers

/** Reports whether the cursor begins a protocol declaration or adoption,
    including its `meta` and `static` markers. This query does not consume
    tokens. */
int Compiler.protocol_form_starts(Compiler c) {
  int at = c.at_word("meta");
  if (c.peek(at) == <static>) at++;
  return c.peek(at) == <protocol>;
}

/** Reports whether the cursor begins a contextual top-level `meta`
    declaration: a function or an initialized file-static value. */
int Compiler.meta_form_is_declaration(Compiler c) {
  if (!c.at_word("meta")) return 0;
  Token head = c.token;
  c.take_meta_marker(NULL);
  int marker = c.test_declaration();
  c.token = head;
  return marker;
}

/** Consumes the `meta` marker at the cursor and the contextual `native`
    marker that may follow it, and returns the `meta` token. `native` binds
    the definition after it the way a bodyless prototype would. `*native`,
    when requested, reports whether that marker was present. */
Token Compiler.take_meta_marker(Compiler c, int &?native) {
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

/** Parses and registers one `import` declaration, including its semicolon.
    The alias defaults to the package name; `with` members add source-ordered
    local spellings. These spellings affect source resolution only; the package
    name in the returned AST drives the generated header include.
*/
List Compiler.parse_import_declaration(Compiler c) {
  Token start = c.token;
  c.expect(<import>);
  String name = c._package_name(), alias = c._import_alias(name);
  c.collect_package(name, start);
  c.register_package_alias(name, alias, start);
  List members = c.take_word("with") ? c._import_members(name) : NULL;
  c.import_package_macros(name, start);
  c.expect(<;>);
  if (c.shallow)
    c.sym.set(
      %("source-node" (package-import
        ${home_portable_path(Path.absolute(c.filename))} ${start.pos})),
      %(package-import $name $alias $members));
  return %(import $name $alias);
}

macro Statement $report.parse_package_identifier(Expr $c, Expr $origin) {
  $c.report_error(
    <parse>, "package name must be a C identifier",
    $origin, NULL);
}

macro Statement $report.parse_import_name(Expr $c) {
  $c.report_error(
    <parse>, "expected a quoted package name after 'import'",
    $c.token, NULL);
}

// Rejects unquoted package names before parsing their identifier.
static String Compiler._package_name(Compiler c) {
  if (c.peek(0) != <lit-char*>)
    $report.parse_import_name(c);
  Token name_token = c.token;
  String name = String.new_len(
    c.token.text + 1, c.token.len - 2).unescape();
  if (!name.is_identifier())
    $report.parse_package_identifier(c, name_token);
  c.next();
  return name;
}

static String Compiler._import_alias(Compiler c, String name) {
  if (!c.take_word("as")) return name;
  if (c.peek(0) != <ident>)
    $report.parse_alias_name(c);
  String alias = c.token.text;
  c.next();
  return alias;
}

macro Statement $report.parse_import_local(Expr $c) {
  $c.report_error(
    <parse>, "expected a local name after 'as'",
    $c.token, NULL);
}

macro Statement $report.parse_import_member(Expr $c) {
  $c.report_error(
    <parse>, "expected a package member name after 'with'",
    $c.token, NULL);
}

/* with Name [as Local] {, Name [as Local]}
   Each name binds a bare local spelling to one already-built package member.
   Registration runs at the name's own token so an unknown member and a
   collision both point at the spelling the developer wrote. */
static List Compiler._import_members(Compiler c, String name) {
  Array members = [];
  do {
    if (c.peek(0) != <ident>)
      $report.parse_import_member(c);
    Token member_token = c.token, local_token = member_token;
    String member = c.token.text, local = member;
    c.next();
    if (c.take_word("as")) {
      if (c.peek(0) != <ident>)
        $report.parse_import_local(c);
      local_token = c.token;
      local = c.token.text;
      c.next();
    }
    c.register_package_member(
      name, member, local, member_token, local_token);
    members.push(%($member $local));
  } while (c.test(<,>));
  return members.list_free();
}

// file-scope definitions

/* A declaration ends at `;`. A `meta` one installs its compile-time form
   and publishes its prose; an ordinary function prototype keeps its name
   callable at run time. */
static List Compiler._declared(
  Compiler c, List decl, Token meta, Token first) {
  c._record_meta_hash(decl, first, 0);
  if (meta && decl.type_from_ast().is_function())
    c.install_native_meta_function(decl, meta);
  else if (meta) c.install_meta_declaration(decl, meta);
  c.record_declaration_visibility(decl);
  if (meta)
    c._definition_source(decl, meta.line, c.definition_doc(meta), NULL);
  else
    match (decl)
      case %(declare ? (bindings (bind (binding ? ?(String name)) *))):
        if (decl.type_from_ast().is_function()) c.meta_comptime.del(name);
  return decl;
}

macro Statement $report.parse_function_row(Expr $c) {
  $c.report_error(
    <parse>, "a function definition cannot share a declaration row",
    $c.token, NULL);
}

/* A definition's body follows its declarator. A staged `meta` body parses
   as compile-time code, and a `meta` function that reaches a `Meta`
   operation exists only inside the compiler, with no runtime form. */
static List Compiler._defined(
  Compiler c, List decl, Token meta, int native, Token first) {
  match (decl) case %(seq *):
    $report.parse_function_row(c);
  List function;
  Token tokens = c.tokenizer.tokens;
  int start = (meta ? meta : first) - tokens;
  int body = c.token - tokens;
  Token staged = native ? NULL : meta;
  if (staged) c._reject_expanded_meta(decl, meta);
  if (native) c.install_native_meta_function(decl, meta);
  $let(c.meta_body, staged != NULL) function = c._finish_function(decl, NULL);
  c._record_meta_hash(function, first, 0);
  c._publish_definition(decl, function, meta, staged);
  if (staged && c.meta_is_comptime_only(function)) return NULL;
  if (c.macro_holes)
    return %(api-source ${first.line} ${c.definition_doc(first)} $function);
  c._definition_source(function, first.line, NULL, %($start $body));
  return function;
}

macro Statement $report.parse_meta_constructed(
  Expr $c, Expr $name, Expr $origin) {
  $c.report_error(
    <parse>, %"meta function '${$name}' cannot be produced by a macro",
    $origin, %( "move it to a source file and call it from the macro" ));
}

/* A macro expansion cannot produce a bodied `meta` function: the project
   meta build extracts meta code from source files, not from expansions. */
static void Compiler._reject_expanded_meta(Compiler c, List decl, Token meta) {
  if (!c.macro_holes) return;
  String name = "";
  match (decl)
    case %(declare ? (bindings (bind (binding ? ?(String own)) *))):
      name = own;
  $report.parse_meta_constructed(c, name, meta);
}

/* Hashes functions and initialized file-static values, and records the
   names their parsed bodies reference. A linked copy answers only when
   its text and the definitions it reaches agree with the source. */
static void Compiler._record_meta_hash(
  Compiler c, List definition, Token first, int collected_body) {
  match (definition) {
    case %(seq *rows): {
      foreach (List row, rows)
        c._record_meta_hash(row, first, collected_body);
      return;
    }
    case %(declare ?spec (bindings ?one *more)):
      if (more) {
        foreach (Var bind, definition.caddr().list().cdr())
          c._record_meta_hash(%(declare $spec (bindings $bind)),
            first, collected_body);
        return;
      }
  }
  String name = NULL;
  Var body = void;
  match (definition) {
    case %(function ? (bind (binding ? ?(String own)) *) ?content): {
      name = own;
      body = content;
    }
    case %(declare ?spec
             (bindings (op = (bind (binding ? ?(String own)) *)
                             ?initializer))): {
      if (!spec.type().is_static()) return;
      name = own;
      body = initializer;
    }
    case %(declare ?spec
             (bindings (bind (!set ?binding (binding ? ?(String own))) *))): {
      if (!c.shallow || (!collected_body &&
          (!spec.type().is_static() || !(binding in c.init_tokens))))
        return;
      name = own;
    }
  }
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

/* Adds each name `node` references to `names`, once, in source order. */
static void _referenced_names(Var node, Map seen, Array names) {
  if (node is not <list>) return;
  List syntax = node;
  match (syntax)
    case $source_identifier_content(%((binding ? ?name))): {
      if (name is not <string>) break;
      String spelling = name;
      if (!(spelling in seen)) {
        seen[spelling] = 1;
        names.push(spelling);
      }
      return;
    }
  foreach (Var child, syntax) _referenced_names(child, seen, names);
}

/* A staged `meta` definition installs its compile-time form unless the
   compiler's linked copy answers for it. Compile-time only describes a
   `meta` definition: an ordinary declaration or definition of the same
   name, such as a copy the compiler links, is callable at run time. */
static void Compiler._publish_definition(
  Compiler c, List decl, List function, Token meta, Token staged) {
  if (staged && !c.bind_linked_meta(
    function, decl.type_from_ast().canonicalize()))
    c.install_meta_function(function, staged);
  c.record_declaration_visibility(function);
  if (!meta)
    match (function)
      case %(function ? (bind (binding ? ?(String name)) *) ?):
        c.meta_comptime.del(name);
}

/* A generated default that completes a documented `meta` prototype
   publishes the prototype's prose. */
static void Compiler._definition_source(
  Compiler c, List function, int line, String doc, List declarator) {
  match (function) {
    case %(function ? (bind ?binding ?) ?):
      c.semantic_binding_facts()[%(api-definition $binding)] =
        %($line $doc $declarator);
    case %(declare ? (bindings (bind ?binding ?))):
      if (doc && function.type_from_ast().is_function())
        c.semantic_binding_facts()[%(api-definition $binding)] =
          %($line $doc $declarator);
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

// declarations

/** Parses one x2c declaration row and leaves its terminator current.
    A mixed-type comma row returns a `seq` of declarations in source order;
    a single declaration returns directly.
*/
List Compiler.parse_declaration_row(Compiler c) {
  List rows = c._declaration_rows();
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

static List Compiler._declaration_rows(Compiler c) {
  Array declarations = [];
  loop {
    declarations.push(c._declaration_group(1));
    if (!c._group_comma()) break;
    c.next();
  }
  return declarations.list_free();
}

/** Parses one declaration group and leaves its terminating token current.
    Declared names are installed in `Sym` as their declarators are completed;
    the result is one `declare`, `typedef`, or initialized `dstrdecl` AST.
*/
List Compiler.parse_simple_declaration(Compiler c) => c._declaration_group(0);

/** Parses a declaration that sits inside an expression or a `for` header,
    such as a cast's type name, and returns it as one `(decl ...)` node.
    When `type` is not null, it receives the declared `Type`.
*/
List Compiler.parse_type_operand(Compiler c, Type *type) {
  List declaration = c.parse_simple_declaration();
  if (type) *type = declaration.type_from_ast();
  return %(decl @{declaration.cdr()});
}

static List Compiler._declaration_group(Compiler c, int row) {
  List storage = c._storage_class();
  if (storage === %(typedef)) return c._typedef(storage, row);
  List (type, binding_type) = c._declaration_types(storage);
  if (c._destructure_starts())
    return c._destructure_declaration(type, binding_type, 0);
  List bindings = c._declarator_list(binding_type, NULL, row);
  return c._finish_declaration(<declare>, type, bindings, 0);
}

static List Compiler._typedef(Compiler c, List context, int row) {
  Token first = c.token;
  // An imported `typedef const char *(*fn)(int)` names a qualified type
  // like an object declaration does, so read the qualifiers first.
  List quals = c._type_qualifiers();
  List spec = quals.append(c._type_specifier());
  spec = c.sym.local_type(spec);
  List bindings = c._declarator_list(spec, context, row);
  /* A typedef's own alignment changes every record field that names it,
     even when the record declaration has no attribute of its own. */
  if (c._layout_attribute_since(first))
    foreach (List declarator, bindings) {
      String name = binding_identity_spelling(declarator.cadr());
      if (name) c.sym.set(%($name "layout-attribute"), %(unknown));
    }
  return c._finish_declaration(<typedef>, spec, bindings, 0);
}

/* Reads the qualifiers, the type specifier, and any storage macro after it,
   `int LOCAL f(void)`, and returns the declared type and the type its names
   are bound to. Source specifier text, such as `("_Noreturn")`, is written
   with the declaration but is no part of the bound type. An aggregate binds
   its short tag; the declared type keeps the body. */
static List Compiler._declaration_types(Compiler c, List storage) {
  List quals = c._type_qualifiers();
  Type spec = c._type_specifier();
  Array trailing = [];
  // C11 6.11.5: a storage class after the type is obsolescent but legal, and
  // preprocessed source spells an expanded storage macro that way.
  loop {
    Symbol symbol = c.peek(0);
    if (symbol != <typedef> &&
        (symbol.is_storage_class() || symbol.is_inline())) {
      trailing.push(symbol);
      c.next();
      continue;
    }
    if (!c._prefix_macro_words(0, trailing)) break;
  }
  if (trailing.len()) storage = %( @{trailing.list_free()} @storage );
  List words = storage.filter(%!(item) => item is <symbol>);
  Type binding_type = c.sym.local_type(%( @words @quals @spec ));
  if (spec.is_aggregate_tag_body()) {
    Var (aggregate, tag, body) = spec;
    binding_type = %( @words @quals $aggregate $tag );
  }
  return %( ${c.sym.local_type(%( @storage @quals @spec ))} $binding_type );
}

macro Statement $report.parse_decl_function(Expr $c) {
  $c.report_error(
    <parse>, "Decl macro argument cannot be a function declaration",
    $c.token, NULL);
}

macro Statement $report.parse_decl_typedef(Expr $c) {
  $c.report_error(
    <parse>, "Decl macro argument cannot be a typedef",
    $c.token, NULL);
}

/** Parses one non-function, non-typedef `Decl` macro argument.
    Returns a single declaration without consuming the invocation delimiter;
    flat destructuring may omit an initializer in this position.
*/
List Compiler.parse_declaration_argument(Compiler c) {
  List storage = c._storage_class();
  if (storage === %(typedef))
    $report.parse_decl_typedef(c);
  List (type, binding_type) = c._declaration_types(storage);
  if (c._destructure_starts())
    return c._destructure_declaration(type, binding_type, 1);
  List binding = c._declarator_init(binding_type, NULL);
  List declaration = c._finish_declaration(<declare>, type, %($binding), 0);
  if (declaration.type_from_ast().is_function())
    $report.parse_decl_function(c);
  return declaration;
}

/** Reports whether the current identifier starts a C static assertion. */
int Compiler.test_static_assert(Compiler c) =>
  c.at_word("_Static_assert");

/** Parses a C assertion declaration; native C owns constant-expression
    checks. */
List Compiler.parse_static_assert(Compiler c) {
  if (c.shallow) {
    c._skip_shallow_expression(0);
    c.expect(<;>);
    return %(c-assert);
  }
  c.next();
  c.expect(<(>);
  List condition = c.parse_assignment();
  c.expect(<,>);
  List message = c.parse_assignment();
  c.expect(<)>);
  c.expect(<;>);
  return %(c-assert $condition $message);
}

/* declaration starts

   Statement, expression, and row parsing share one recognizer of the
   declaration prefix. A row can additionally require an identifier type to
   be followed by a declarator, which resolves the one C-compatible comma
   ambiguity. */

/** Tests whether the current token can begin a declaration without consuming.
    Typedefs, package aliases, and macro-hole kinds are resolved through the
    current compiler state.
*/
int Compiler.test_declaration(Compiler c) => c._test_declaration_start(0);

static int Compiler._test_declaration_start(
  Compiler c, int require_declarator) {
  Symbol sym = c.peek(0);
  if (c.macro_holes && sym == <"$(">)
    return c.macro_lisp_starts_declaration();
  if (c.macro_holes && sym == <$>) return c._hole_starts();
  if (sym.is_storage_class() || sym.is_type_qualifier() ||
      sym.is_builtin_type() || sym == <inline>) return 1;
  if (sym != <ident>) return 0;
  // A leading attribute belongs to a declaration in every position.
  if (c.token.text == "__attribute__" && c._attribute_starts()) return 1;
  /* A prefix macro contributes declaration specifiers, so `LOCAL int x = 1;`
     is a declaration wherever it is written. */
  Var definition;
  if (c.object_macros.try_get(c.token.text, definition) &&
      (definition is <list> || definition.equal(<wrapper>)))
    return 1;
  return c._type_name_starts(require_declarator);
}

/* A type hole starts a declaration, and so does a hole of no declared kind
   that a name follows. */
static int Compiler._hole_starts(Compiler c) {
  List hole = c.peek_macro_hole();
  if (!hole) return c.macro_lisp_starts_declaration();
  Symbol kind = hole.assoc(<kind>);
  if (kind) return kind == <type>;
  Symbol next = c.peek(2);
  return next == <ident> || next == <$> || next == <"$(">;
}

/* An identifier that names no object starts a declaration when the token
   after it, or after a package alias's member, can follow a type name. */
static int Compiler._type_name_starts(Compiler c, int require_declarator) {
  Token head = c.token;
  String alias = c.package_alias_spelling();
  String name = alias ? alias
              : c.package_member_spelling(c.token.text);
  Type lookup = c.sym.get(%(${name ? name : c.token.text}));
  if (lookup && !lookup.is_typedef()) return 0;
  c.next();
  if (alias) { c.next(); c.next(); }
  Symbol next = c.peek(0);
  int is_operator = c.at_word("is");
  // `int a, b __attribute__((unused));` declares `b`, not a type named `b`.
  int attribute = c._attribute_starts();
  c.token = head;
  if (c.macro_holes && is_operator) return 0;
  if (lookup.is_typedef() && !require_declarator) return next != <.>;
  return next == <*> || next == <&> || (next == <ident> && !attribute) ||
         (!require_declarator && next == <)>) ||
         (require_declarator && (next == <^> || next.is_type_qualifier()));
}

/* A typedef name after a comma is ambiguous: `int i, T;` declares another
   int, while `int i, T value;` begins a fresh declaration. Ask the same
   declaration recognizer used by every other parser entry, but require a
   declarator after an identifier type in this one ambiguous position. */
static int Compiler._group_comma(Compiler c) {
  if (c.peek(0) != <,>) return 0;
  Token comma = c.token;
  c.next();
  int result = c._test_declaration_start(1);
  c.token = comma;
  return result;
}

// destructuring declarations

// Distinguish '(ident, ...)' from an ordinary parenthesized declarator.
static int Compiler._destructure_starts(Compiler c) {
  Token token = c.token;
  if (token.type != <(>) return 0;
  token = Token.skip_trivia(token + 1);
  if (token.type != <ident>) return 0;
  token = Token.skip_trivia(token + 1);
  return token.type == <,>;
}

macro Statement $report.parse_destructure_init(Expr $c) {
  $c.report_error(
    <parse>, "destructuring declaration requires an initializer",
    $c.token, NULL);
}

static List Compiler._destructure_declaration(
  Compiler c, List type, List binding_type, int allow_uninitialized) {
  Token origin_token = c.token;
  List bindings = c._destructure_targets(binding_type);
  /* A foreach destructures each element rather than an initializer, so the
     same `(a, b)` spelling stands without `=`. It reduces to the
     multi-binding declaration `_for_statement` already knows how to
     carry across `in`. */
  if (allow_uninitialized || c.peek(0) == <in>)
    return %(declare $type (bindings @{_destructure_binds(bindings)}));
  if (!c.test(<=>))
    $report.parse_destructure_init(c);
  List source = c.parse_assignment();
  List result = %(dstrdecl $type (targets @bindings) $source);
  return c.anchor_origin(result, origin_token);
}

macro Statement $report.parse_destructure_name(Expr $c) {
  $c.report_error(
    <parse>, "expected identifier in destructuring declaration",
    $c.token, %("destructuring targets must be simple identifiers"));
}

// ( ident, ident, ... ), each declared with the destructured type.
static List Compiler._destructure_targets(Compiler c, List binding_type) {
  Array targets = [];
  c.expect(<(>);
  loop {
    if (c.peek(0) != <ident>)
      $report.parse_destructure_name(c);
    List ident = c.parse_basic_identifier();
    if (c.macro_holes) {
      List local = c.macro_introduced_name(ident.car());
      c.bind_template_local(local, binding_type, NULL);
      targets.push(local);
    }
    else targets.push(c.sym.declare(NULL, ident, binding_type));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return targets.list_free();
}

/* Wraps destructuring targets as the binding forms a declaration carries,
   so a foreach binder reaches the transform as a plain declaration of two
   names. */
static List _destructure_binds(List targets) {
  Array binds = [];
  foreach (List target, targets) binds.push(%(bind $target ()));
  return binds.list_free();
}

// finishing a declaration

static List Compiler._finish_declaration(
  Compiler c, Symbol tag, List base, List declarators,
  int preserved_self) {
  List modifiers = NULL;
  base = _declaration_base(base, modifiers);
  if (modifiers) {
    Array bound = [];
    foreach (List declarator, declarators)
      bound.push(_append_modifiers(declarator, modifiers));
    declarators = bound.list_free();
  }
  List declaration = %($tag $base (bindings @declarators));
  return tag == <declare> && !preserved_self
    ? c._lower_self_declaration(declaration)
    : declaration;
}

/* An expanded alias may contribute pointer, array, or function modifiers.
   Keep parsed modifiers (and parameter bindings) intact and append only the
   alias's declarators. Storage still belongs on the declaration's base. */
static List _declaration_base(Type t, List &modifiers) {
  // Source specifier text, such as `("_Noreturn")`, follows the storage.
  Array storage = [], text = [], typed = [];
  defer { storage.free(); text.free(); typed.free(); }
  foreach (Var item, t)
    if (item is <list> && car(item) is <string>) text.push(item);
    else typed.push(item);
  List (base, mods) = typed.list().type().declared().declaration_parts();
  modifiers = mods;
  if (!mods) return t;
  foreach (Var item, t)
    if (item is <symbol> &&
        (Symbol.is_storage_class(item) || Symbol.is_inline(item)))
      storage.push(item);
  return %( @{storage.list()} @{text.list()} @base );
}

static List _append_modifiers(List declarator, List modifiers) {
  if (!modifiers) return declarator;
  match (declarator) {
    case %(bind ?binding ?mods):
      return %(bind $binding (@{mods} @modifiers));
    case %(op = ?binding ?initializer):
      return %(op = ${_append_modifiers(binding, modifiers)}
               $initializer);
  }
  return declarator;
}

/* Keep Self only in method metadata. The binding and AST receive the
   declaring owner, so direct calls and generated C retain the existing
   function signature. */
static List Compiler._lower_self_declaration(Compiler c, List declaration) {
  List items = declaration.caddr().cdr();
  if (!items || items.cdr()) return declaration;
  List target = items.car();
  if (target.car() == <op>) target = target.caddr();
  List binding = target.cadr(), method = c._method_identity(binding);
  if (!method) return declaration;
  Type owner = c._self_owner_type(method);
  if (!owner) return declaration;
  List lowered = declaration.search_replace(<self>, owner.car());
  if (lowered == declaration) {
    c.semantic_binding_facts().del(%(self $binding));
    return declaration;
  }
  Type signature = declaration.type_from_ast();
  if (!signature.is_function()) return declaration;
  String spelling = binding_identity_spelling(binding);
  Type relative = signature.declared();
  Type concrete = lowered.type_from_ast().declared();
  c.semantic_binding_facts()[%(self $binding)] = relative;
  c.sym.set(%($spelling), concrete);
  c.sym.set(%(self $spelling), relative);
  c._lower_parameter_self(owner.car());
  return lowered;
}

static List Compiler._method_identity(Compiler c, List binding) {
  Var stored;
  return c.semantic_binding_facts().try_get(
    %(method $binding), stored) ? stored : NULL;
}

static List Compiler._method_self_signature(Compiler c, List binding) {
  Var stored;
  return c.semantic_binding_facts().try_get(
    %(self $binding), stored) ? stored : NULL;
}

static Type Compiler._self_owner_type(Compiler c, List method) {
  String source = method.car();
  Type declared = c.sym.get(%($source));
  if (declared.is_typedef()) return %(${c._package_type_reference(0, source)});
  Symbol builtin = Atom.intern(source);
  return builtin.is_builtin_type() ? %($builtin) : NULL;
}

static void Compiler._lower_parameter_self(Compiler c, Var replacement) {
  Map symbols = c.params.symbols;
  if (!symbols) return;
  foreach (Var (key, value), symbols) {
    List original = value;
    List lowered = original.search_replace(<self>, replacement);
    if (lowered != original) {
      symbols[key] = lowered;
      Var binding;
      if (c.params.bindings.try_get(key, binding))
        c.semantic_binding_facts()[
          %(type $binding)
        ] = lowered;
    }
  }
}

// declaration specifiers

/* Declaration specifiers before the qualifiers and type: storage classes
   and `inline` in source order, then `_Noreturn` and attributes as source
   text. The storage words lead, where C places them and where a declared
   type's storage is read. One storage class is allowed, except that
   `threaded` pairs with another one the way C's thread-local specifier
   pairs with `static` or `extern`. A second one stops the run, so
   `static extern` is diagnosed instead of passed to C. */
static List Compiler._storage_class(Compiler c) {
  Array storage = [], text = [], int seen_threaded = 0, seen_ordinary = 0;
  defer { storage.free(); text.free(); }
  loop {
    Symbol symbol = c.peek(0);
    String attribute = c._attribute();
    if (attribute) text.push(%($attribute));
    else if (c.take_word("_Noreturn")) text.push(%("_Noreturn"));
    else if (symbol.is_inline() ||
             (symbol == <threaded> ? !seen_threaded++ :
              symbol.is_storage_class() && !seen_ordinary++)) {
      storage.push(symbol);
      c.next();
      // The linkage name in `extern "C" int f(void);` means nothing to C.
      if (symbol == <extern> && c.peek(0) == <lit-char*>) c.next();
    }
    else if (!c._prefix_macro_words(0, storage)) break;
  }
  return %( @{storage.list()} @{text.list()} );
}

static String Compiler._attribute(Compiler c) {
  if (!c._attribute_starts()) return NULL;
  Token first = c.token, last = Token.skip_trivia(first + 1).group_close();
  c.token = last.after_group();
  return String.new_len(c.text + first.pos, last.pos + last.len - first.pos);
}

/* A GNU attribute or an attribute macro is kept as its source text. */
static int Compiler._attribute_starts(Compiler c) {
  Var definition;
  return c.peek(0) == <ident> && c.peek(1) == <(> &&
         (c.token.text == "__attribute__" ||
          (c.object_macros.try_get(c.token.text, definition) &&
           definition.equal(<annotation>)));
}

/* Source is read before preprocessing, so a macro whose body is declaration
   specifiers and attributes, such as an export annotation, still sits in a
   declaration. A specifier position of `rank`, 0 for storage classes and
   `inline`, 1 for qualifiers, and 2 for builtin types, leaves a macro with
   words of a later rank to that position; otherwise it consumes the macro
   and takes all of its words into `words`, so `int LOCAL f(void)` keeps the
   `static` of `#define LOCAL static`. */
static int Compiler._prefix_macro_words(Compiler c, int rank, Array words) {
  Var definition;
  if (c.peek(0) != <ident>) return 0;
  if (!c.object_macros.try_get(c.token.text, definition)) {
    if (rank || !c._unseen_prefix()) return 0;
    c.next();
    return 1;
  }
  if (definition.equal(<wrapper>) && c.peek(1) == <(>) {
    /* `EXPORT(const char *) f(void);` wraps the type. The name and its
       parentheses contribute nothing; the closing one is hidden so the
       type and declarator between them parse as written. */
    Token close = Token.skip_trivia(c.token + 1).group_close();
    if (close.type != <eof>) close.type = <comment>;
    c.next();
    c.next();
    return 1;
  }
  if (definition is not <list>) return 0;
  foreach (Symbol word, definition)
    if ((word.is_type_qualifier() ? 1 : word.is_builtin_type() * 2) > rank)
      return 0;
  foreach (Symbol word, definition) words.push(word);
  c.next();
  return 1;
}

/* A collected C header may prefix a declaration with a macro defined only
   where collection cannot see it, such as on the C compile line. A name
   before a declaration keyword cannot be a type, so it expands to storage,
   visibility, or attributes and contributes nothing to the collected type. */
static int Compiler._unseen_prefix(Compiler c) {
  Symbol next = c.peek(1);
  return c.shallow && c.filename.endswith(".h") &&
         (next.is_builtin_type() || next.is_type_modifier() ||
          next.is_type_qualifier() || next.is_storage_class() ||
          next.is_inline());
}

static List Compiler._type_qualifiers(Compiler c) {
  Array quals = $auto([]);
  loop {
    c.__complete_here(<type>, _type_keywords());
    Symbol symbol = c.peek(0);
    if (symbol.is_type_qualifier()) {
      quals.push(symbol);
      c.next();
    }
    else if (!c._prefix_macro_words(1, quals)) break;
  }
  return quals;
}

static List _type_keywords(void) => %(
  "void" "char" "short" "int" "long" "float" "double"
  "signed" "unsigned" "struct" "union" "enum"
  "const" "restrict" "volatile"
);

// type specifiers

/** Parses a type specifier with qualifiers and pointer/reference modifiers.
    Returns its flat `Type` AST and leaves the first following token current.
*/
Type Compiler.parse_type_name(Compiler c) {
  List qualifiers = c._type_qualifiers();
  List specifier = c._type_specifier();
  List pointers = c._pointer();
  Type type = %( @pointers @qualifiers @specifier );
  return c.sym.local_type(type);
}

static List Compiler._type_specifier(Compiler c) {
  c.require_input();
  List slot = c.try_parse_macro_slot(<type>);
  if (slot) return %($slot);
  List syntax = NULL;
  switch (c.peek(0)) {
    case <struct>: case <union>:
      syntax = c._struct_or_union(); break;
    case <enum>:
      syntax = c._enum(); break;
    case <ident>:
      if (c.token.text == "Self") {
        c.next();
        syntax = %(self);
        break;
      }
      Array words = [];
      c._prefix_macro_words(2, words);
      syntax = words.list_free();
      if (!syntax) syntax = c._typedef_name();
      break;
    default:
      syntax = c._primitive_type();
  }
  return syntax;
}

macro Statement $report.type_scalar_invalid(
  Expr $c, Expr $source, Expr $origin) {
  $c.report_error(
    <type>, $source ? %"invalid scalar type ${$source}"
                 : "expected scalar type",
    $origin, NULL);
}

static List Compiler._primitive_type(Compiler c) {
  Token start = c.token;
  Array specs = [];
  while (_is_scalar_specifier(c.peek(0))) {
    specs.push(c.peek(0));
    c.next();
  }
  Type source = specs.list_free(), scalar = source.scalar();
  if (scalar) return scalar;
  // The preprocessed shallow pass only contributes declarations. The full
  // pass over the original source reports source-level type diagnostics.
  if (c.shallow) return source;
  $report.type_scalar_invalid(c, source, start);
}

static int _is_scalar_specifier(Symbol symbol) {
  switch (symbol)
    case <signed>: case <unsigned>: case <short>: case <long>:
    case <char>: case <int>: case <float>: case <double>: case <void>:
      return 1;
  return 0;
}

static List Compiler._typedef_name(Compiler c) {
  String name = c._package_alias_member();
  if (!name) name = c.package_member_spelling(c.token.text);
  if (!name) name = c.token.text;
  c.next();
  if (c.package) name = c._package_type_reference(0, name);
  return %($name);
}

/* Package files spell their own file-scope type names bare. A bare-key
   miss with a prefixed hit re-spells the reference; ASTs carry raw
   strings and emit literally. */
static String Compiler._package_type_reference(
  Compiler c, Symbol tag, String name) {
  String prefixed = c.package_spelling(name);
  if (prefixed == name) return name;
  List bare = tag ? %($tag $name) : %($name);
  if (c.sym.get_exact(bare)) return name;
  List hit = tag ? %($tag $prefixed) : %($prefixed);
  return c.sym.get_exact(hit) ? prefixed : name;
}

// aggregates

static List Compiler._struct_or_union(Compiler c) {
  Token first = c.token;
  Symbol tag = c.peek(0);
  c.next();
  c._skip_attributes();
  List name = c._tag_name();
  if (name && c.package) name = c._package_aggregate_name(tag, name);
  List usedname = name ? name : c.gensym();
  usedname = %(${c.aggregate_name(
    tag, usedname.car(), c.peek(0) == <"{"> || c.peek(0) == <;>)});
  List type = cons(tag, usedname), fields = NULL;
  if (c.test(<"{">)) {
    fields = c.parse_fields(type);
    c.expect(<"}">);
    c._skip_attributes();
    if (!c.macro_holes)
      return c._publish_aggregate_type(tag, usedname.car(), fields, first);
    fields = cons(<fields>, fields);
  }
  return fields ? type.append(%($fields)): type;
}

/* C places an aggregate's own attributes after its keyword and after its
   closing brace, written out or through a macro whose body is attributes.
   Collection skips them: attribute text is no part of a collected type, and
   the layout marks hold any layout they change (see Compiler.tokenize). */
static void Compiler._skip_attributes(Compiler c) {
  if (!c.shallow) return;
  loop {
    Var definition;
    if (c._attribute()) continue;
    if (c.peek(0) != <ident> ||
        !c.object_macros.try_get(c.token.text, definition) ||
        !definition.equal(%()))
      return;
    c.next();
  }
}

/* A template may spell a tag through a Name hole or compile-time Lisp,
   which publishes it; a literal tag there is a template local. */
static List Compiler._tag_name(Compiler c) {
  List slot = c.try_parse_macro_slot(<name>);
  return slot ? %($slot) : c.parse_optional_identifier();
}

/* An aggregate definition takes the prefix its declaration key carries, so
   the tag, its member keys, and the pointee spellings recorded for it agree
   in the shallow collection an importing unit reads and in the full parse. */
static List Compiler._package_aggregate_name(
  Compiler c, Symbol tag, List name) {
  // A template's tag slot supplies its exact spelling where it expands.
  if (name.car() is not <string>) return name;
  String spelling = name.car();
  if (c.peek(0) == <"{">) return %(${c.package_spelling(spelling)});
  return %(${c._package_type_reference(tag, spelling)});
}

macro Statement $report.parse_attribute_packed(Expr $c, Expr $origin) {
  $c.report_error(
    <parse>, "packed attributes are unsupported",
    $origin, NULL);
}

/* Publishes an aggregate whose tokens start at `first`. A constructed
   aggregate passes the current token, so its attributes are in its form. An
   enum with a layout attribute can be narrower than int, so it has no int
   layout. */
static List Compiler._publish_aggregate_type(
  Compiler c, Symbol tag, Var name, List members, Token first) {
  int layout = c._layout_attribute_since(first);
  int packed = c._attribute_since(first, c.packed_marks);
  if (tag == <struct> && packed && c.source_private >= 0)
    $report.parse_attribute_packed(c, first);
  List type = %($tag $name);
  List body = tag == <enum> ? members : %(fields @members);
  if (name is <list> && name.car() == <binding>)
    c.sym.bind_identity(%($tag), name, %($tag $body));
  else
    c.sym.declare(NULL, type, tag == <enum> ? %(enum) : %($tag $body));
  if (tag != <enum>) {
    c.sym.declare_field_order(type, members);
    if (layout) c.sym.set(%(@type "layout-attribute"), %(unknown));
    // Meta code lays out only the records x2c units define.
    if (c.source_private >= 0 && !c.filename.endswith(".h"))
      c.sym.set(%(@type "x2c-record"), %(x2c));
  }
  else if (!layout && _enum_fits_int(type, members)) {
    c.sym.set(%(@type "int-range"), %(int));
    c._record_enum_values(members);
  }
  return %($tag $name $body);
}

static int Compiler._layout_attribute_since(Compiler c, Token first) =>
  c._attribute_since(first, c.layout_marks);

/* Reports a layout attribute between `first` and the current token. Tokens
   outside this unit's input, such as a constructed form's, have no marks. */
static int Compiler._attribute_since(Compiler c, Token first, Array marks) {
  Token base = c.tokenizer.tokens, end = base + c.tokenizer.tokens.len();
  if (first < base || c.token >= end) return 0;
  // Marks ascend, so the ones before `first` are a prefix.
  int before = 0, count = marks.len();
  for (int high = count; before < high;) {
    int middle = (before + high) / 2;
    if ((long) marks[middle] < first - base) before = middle + 1;
    else high = middle;
  }
  return before % 2 ||
         (before < count && (long) marks[before] < c.token - base);
}

// fields

/** Parses aggregate fields in source order up to the current closing brace.
    Returns a flat field `List`, publishes delegate-field metadata, and leaves
    the closing brace unconsumed.
*/
List Compiler.parse_fields(Compiler c, List context) {
  Array fields = [];
  loop {
    int delegated = c.test(<delegate>);
    List field = delegated
      ? c._field(context, 1) : c.parse_field(context);
    match (field) {
      case %(seq *rows):
        foreach (Var row, rows) fields.push(row);
      default: fields.push(field);
    }
    if (c.peek(0) == <"}">) return fields.list_free();
  }
}

/** Parses one field for aggregate type `context` and returns its AST.
    Ordinary fields publish their binding in the aggregate's field scope and
    consume their terminating semicolon; macro forms follow their own syntax.
*/
List Compiler.parse_field(Compiler c, List context) {
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = c.try_parse_macro_slot(<field>);
  if (slot) return slot;
  List macro = c._member_macro(context, AST_FIELD);
  if (macro) return macro;
  return c._field(context, 0);
}

/* A macro invocation may stand for an aggregate member. It expands with
   the aggregate as the current aggregate type. */
static List Compiler._member_macro(Compiler c, List context, AstPos position) {
  if (c.peek(0) != <$> && c.peek(0) != <ident>) return NULL;
  $let(c.aggregate_type, context)
    return c.try_parse_macro_target_at(position);
}

static List Compiler._field(Compiler c, List context, int delegated) {
  List rows = c._field_row(context);
  if (delegated) c._declare_delegates(context, rows);
  c.expect(<;>);
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

macro Statement $report.parse_delegate_name(Expr $c) {
  $c.report_error(
    <parse>, "delegate field requires a name",
    $c.token, NULL);
}

// Each declarator of a delegate field must name the field.
static void Compiler._declare_delegates(Compiler c, List context, List rows) {
  foreach (List declaration, rows)
    match (declaration)
      case %(declare ? (bindings *declarators)): {
        if (!declarators)
          $report.parse_delegate_name(c);
        foreach (List declarator, declarators)
          match (declarator)
            case %(bind ?binding ?): c._declare_delegate(context, binding);
      }
}

static void Compiler._declare_delegate(Compiler c, List context, Var binding) {
  String name = binding_identity_spelling(binding);
  if (!name)
    $report.parse_delegate_name(c);
  if (!c.macro_holes) c.sym.declare_delegate_field(context, name);
}

static List Compiler._field_row(Compiler c, List context) {
  Array declarations = [];
  loop {
    declarations.push(c._field_group(context));
    if (!c._group_comma()) break;
    c.next();
  }
  return declarations.list_free();
}

static List Compiler._field_group(Compiler c, List context) {
  List storage = c._storage_class();
  List (type, binding_type) = c._declaration_types(storage);
  List binds = c._declarator_list(binding_type, context, 1);
  return c._finish_declaration(<declare>, type, binds, 0);
}

// named types

/** Captures a name followed by an ordinary complete type and semicolon.
    The reserved typedef identity permits fields to refer to their enclosing
    named type before its pointer or value representation is complete.
*/
List Compiler.parse_named_type(Compiler c) {
  List slot = c.try_parse_macro_slot(<named-type>);
  if (slot) return slot;
  Token start = c.token;
  String name = c.package_spelling(c.token.text);
  c.expect(<ident>);
  List key = %($name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (c.test(<;>)) return %(named-type $name ());
  List qualifiers = c._type_qualifiers();
  List base = qualifiers.append(
    c._record_follows() ? c._record_body(name, start) : c._type_specifier());
  Type type = c._declare_named_type(key, base, start);
  return %(named-type $name $type);
}

/* A named type may define its record in place, with or without `struct`
   or `union` before the brace. */
static int Compiler._record_follows(Compiler c) =>
  c.peek(0) == <"{"> ||
  ((c.peek(0) == <struct> || c.peek(0) == <union>) && c.peek(1) == <"{">);

static List Compiler._record_body(Compiler c, String name, Token start) {
  Symbol tag = c.peek(0) == <union> ? <union> : <struct>;
  if (c.peek(0) != <"{">) c.next();
  c.expect(<"{">);
  List fields = c.peek(0) == <"}">
              ? NULL : c.parse_fields(%($tag $name));
  c.expect(<"}">);
  return c.macro_holes ? %($tag $name (fields @fields))
                       : c._publish_aggregate_type(tag, name, fields, start);
}

macro Statement $report.parse_named_type_abstract(Expr $c, Expr $origin) {
  $c.report_error(
    <parse>, "named type requires an abstract type after its name",
    $origin, NULL);
}

/* Completes a named type from the abstract declarator after its base. The
   type keeps an aggregate's body in place of its tag. */
static Type Compiler._declare_named_type(
  Compiler c, List key, List base, Token start) {
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = c._declarator(base, NULL, method, first, after);
  List modifiers = NULL;
  match (declarator) {
    case %(bind () ?captured): modifiers = captured;
    default: $report.parse_named_type_abstract(c, start);
  }
  c.expect(<;>);
  Type type = %(declare $base (bindings (bind () $modifiers)))
                .type_from_ast();
  if (!c.macro_holes) c.sym.declare(%(typedef), key, type);
  Type specifier = base.type().base_type();
  if (specifier.is_aggregate_tag_body())
    type = type.list()[:type.len() - type.base_type().len()]
      .append(specifier);
  return type;
}

// enumerations

static List Compiler._enum(Compiler c) {
  Token first = c.token;
  c.expect(<enum>);
  c._skip_attributes();
  List name = c._tag_name();
  if (name && c.package) name = c._package_aggregate_name(<enum>, name);
  if (name && c.macro_holes)
    name = %(${c.aggregate_name(
      <enum>, name.car(), c.peek(0) == <"{"> || c.peek(0) == <;>)});
  List usedname = name ? name : c.gensym();
  List type = cons(<enum>, usedname), enums = NULL;
  if (c.test(<"{">)) {
    enums = c.parse_enumerators(type);
    c.expect(<"}">);
    c._skip_attributes();
    if (!c.macro_holes)
      return c._publish_aggregate_type(<enum>, usedname.car(), enums, first);
  }
  return enums ? type.append(%($enums)): type;
}

/** Parses comma-separated enumerators up to the current closing brace.
    Returns their flat source-order `List` and leaves the brace unconsumed.
*/
List Compiler.parse_enumerators(Compiler c, List context) {
  Array enumerators = [];
  while (c.peek(0) != <"}">) {
    if (c.shallow && c.macro_starts_target_at(AST_ENUMERATOR))
      c.skip_macro_invocation();
    else _push_items(enumerators, c.parse_enumerator(context));
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return enumerators.list_free();
}

/* Pushes the items of a `seq`, or any other node itself. */
static void _push_items(Array out, List node) {
  if (node.car() == <seq>)
    foreach (Var item, node.cdr()) out.push(item);
  else out.push(node);
}

macro Statement $report.parse_enum_name(Expr $c) {
  $c.report_error(
    <parse>, "expected enumerator identifier",
    $c.token, NULL);
}

/** Parses one enumerator for enum type `context` and returns its AST.
    Outside macro-template parsing, its binding is published immediately so
    later initializers and enumerators can resolve it.
*/
List Compiler.parse_enumerator(Compiler c, Type context) {
  List slot = c.try_parse_macro_slot(<enumerator>);
  if (slot) return slot;
  List macro = c._member_macro(context, AST_ENUMERATOR);
  if (macro) return macro;
  if (c.macro_holes) return c._template_enumerator(context);
  if (c.peek(0) != <ident>)
    $report.parse_enum_name(c);
  String spelling = c.token.text;
  Token origin = c.token;
  c.next();
  List binding = %($spelling), syntax = binding;
  if (c.test(<=>)) {
    List value = c.parse_conditional();
    syntax = %(op = $binding $value);
  }
  return c._publish_enumerator(syntax, context, origin);
}

/* A template's enumerator is named by a hole, a Lisp slot, or a name each
   expansion introduces. */
static List Compiler._template_enumerator(Compiler c, Type context) {
  List name = c._enumerator_name(context);
  List target = %(bind $name ());
  if (c.test(<=>)) return %(op = $target ${c.parse_conditional()});
  return target;
}

static List Compiler._enumerator_name(Compiler c, Type context) {
  switch (c.peek(0)) {
    case <"$(">: case <$>: return c.try_parse_macro_slot(<name>);
    case <ident>: {
      String spelling = c.token.text;
      c.next();
      List name = c.macro_introduced_name(spelling);
      c.sym.bind_identity(NULL, name, context.declaration_ast(name));
      return name;
    }
    default:
      $report.parse_enum_name(c);
  }
}

macro Statement $report.parse_enum_bound(Expr $c, Expr $spelling, Expr $origin) {
  $c.report_error(
    <parse>, %"enumerator '${$spelling}' is already bound in this scope",
    $origin, %("prior binding: '${$spelling}'"));
}

macro Statement $report.parse_syntax_position(Expr $c, Expr $origin) {
  $c.report_error(
    <parse>, "syntax cannot be constructed at this position",
    $origin, NULL);
}

static List Compiler._publish_enumerator(
  Compiler c, List input, Type context, Token origin) {
  input = c.evaluate_macro_slot(input);
  List target = input, initializer = NULL;
  match (input)
    case %(op = ?captured_target ?value): {
      target = captured_target;
      initializer = c.resolve_expression(value, c.token);
    }
  target = c.evaluate_macro_slot(target);
  Var name = target;
  match (target) case %(bind ?binding_name ?): name = binding_name;
  name = c.evaluate_macro_slot(name);
  String exact = _syntax_exact_name(name);
  List binding = exact ? NULL : name is <list> ? name.list() : NULL;
  String spelling = exact ? exact : binding_identity_spelling(binding);
  if (!spelling)
    $report.parse_syntax_position(c, origin);
  List key = %($spelling);
  Symbol prior = c.sym.enumerator_owner(key);
  if (prior && binding) {
    List existing = c.sym.lookup(key, NULL);
    if (existing && existing.equal(binding)) return input;
  }
  if (prior)
    $report.parse_enum_bound(c, spelling, origin);
  if (exact) binding = c.sym.declare(NULL, key, context);
  else
    c.sym.bind_identity(NULL, binding, context.declaration_ast(binding));
  c.sym.declare_enumerator(key, <enumerator>);
  return initializer ? %(op = $binding $initializer) : binding;
}

/* Whether every enumerator of enum `type` fits in int, the width C gives an
   enum whose values do: each initializer has an integer type no wider than
   int, or is the enum itself. C requires an implicit value, the previous
   one plus one, to fit in int as well. */
static int _enum_fits_int(List type, List members) {
  foreach (List member, members) {
    match (member) {
      case %(binding *): continue;
      case %(op = ? (expr ?(Type value) *)):
        if (_fits_int(value, type)) continue;
    }
    return 0;
  }
  return 1;
}

static int _fits_int(Type value, List type) {
  if (value.equal(type)) return 1;
  X2CVarNumericInfo info;
  return Var.numeric_info(value.scalar_tag(), info) && !info.floating &&
         (info.bits < 32 || (info.bits == 32 && !info.unsigned_value));
}

/* Records how meta code computes each enumerator's value: its initializer,
   or the previous enumerator plus one, or zero for the first. */
static void Compiler._record_enum_values(Compiler c, List members) {
  Map facts = c.semantic_binding_facts();
  List rule = %(first);
  foreach (List member, members) {
    List binding = member;
    match (member) case %(op = ?target ?value): {
      binding = target;
      rule = %(value $value);
    }
    facts[%(enum-value $binding)] = rule;
    rule = %(next $binding);
  }
}

// declarators

static List Compiler._declarator_list(
  Compiler c, List type, List context, int row) {
  Array bindings = $auto([]);
  loop {
    bindings.push(c._declarator_init(type, context));
    if ((row && c._group_comma()) ||
        !c.test(<,>))
      return bindings;
  }
}

/* Install each declaration binding before resolving its initializer so later
   declarators and source-order dependency analysis share the same identity. */
static List Compiler._declarator_init(
  Compiler c, List type, List context) {
  // A Lisp-produced declarator name still needs ordinary binding.
  List slot = c.peek_macro_hole()
    ? c.try_parse_macro_slot(<decl-row>) : NULL;
  if (slot) {
    if (c.test(<=>)) return %(op = $slot ${c.parse_assignment()});
    return slot;
  }
  Token origin = c.token;
  List method = NULL;
  Token first = NULL, after = NULL;
  List bind = c._declarator(type, context, method, first, after);
  int preserved_self = 0;
  bind = c._install_declarator(type, context, bind, method, preserved_self);
  c.record_source_declaration(bind.cadr(), first, after);
  int function_arrow = !c.in_proto && c._at_function_arrow() &&
    %(declare $type (bindings $bind)).type_from_ast().is_function();
  if (!c.in_proto && !function_arrow && c.test(<=>))
    return c._initialized(type, bind, origin);
  return bind;
}

/* Collection skips an initializer. `init_tokens` records the declarator's
   first token, not the token where expression parsing finishes. */
static List Compiler._initialized(
  Compiler c, List type, List bind, Token origin) {
  List binding = bind.cadr();
  if (binding_identity_try_parts(binding, NULL, NULL)) {
    Token tokens = c.tokenizer.tokens;
    c.init_tokens[binding] = (int) (origin - tokens);
  }
  if (c.shallow) {
    c._skip_shallow_expression(1);
    return bind;
  }
  List init = c.parse_assignment();
  c.check_explicit_converter(
    init, %(declare $type (bindings $bind)).type_from_ast(), 0);
  return %( op = $bind $init );
}

static List Compiler._declarator(
  Compiler c, List type, List context, List &method_identity_out,
  Token &source_first, Token &source_after) {
  List ptr = c._pointer(), method_identity = NULL;
  List (key, infix) =
    c._direct_declarator(
      context, method_identity, source_first,
      source_after).cdr();
  List sfx = c._declarator_suffix();
  List modifiers = %( @infix @sfx @ptr );
  List ast = modifiers.append(type);
  // A parenthesized declarator is assembled twice. Preserve its raw key until
  // the outer call has the base type and can establish the binding once.
  List binding = key;
  c.bind_template_local(key, ast, context);
  method_identity_out = method_identity;
  return %( bind $binding $modifiers );
}

static List Compiler._pointer(Compiler c) {
  List ptr = NULL;
  loop {
    Symbol symbol = c.peek(0);
    if (symbol == <*> || symbol == <^> || symbol == <&> ||
        symbol.is_type_qualifier()) {
      c.next();
      int optional = symbol == <&> && c.peek(0) == <?>;
      ptr = cons(optional ? <opt-ref> : symbol, ptr);
      if (optional) c.next();
      continue;
    }
    Array quals = [];
    if (!c._prefix_macro_words(1, quals)) return ptr;
    foreach (Var qualifier, quals) ptr = cons(qualifier, ptr);
  }
}

static List Compiler._direct_declarator(
  Compiler c, Type context, List &method_identity, Token &source_first,
  Token &source_after) {
  // A member keeps its spelling in a template: C scopes it to its aggregate.
  int member = context.is_aggregate();
  if (c.peek(0) == <(>)
    return c._parenthesized(
      member ? context : NULL, method_identity, source_first,
      source_after);
  if (c.macro_holes) {
    List bind = c._template_declarator(member);
    if (bind) return bind;
  }
  if (!c.token.text.is_identifier()) return %(bind () ());
  // Identifier or typedef name or method-sugar target
  Token first = c.token;
  List ident = c._complex_identifier(method_identity);
  source_first = first;
  source_after = c.token;
  return %(bind $ident ());
}

macro Statement $report.parse_paren_unclosed(Expr $c) {
  $c.report_error(
    <parse>, "missing closing parenthesis",
    $c.token, NULL);
}

macro Statement $report.parse_type_unknown(Expr $c, Expr $first) {
  $c.report_error(
    <parse>, %"unknown type name '${$first.text}'",
    $first, %("name an imported package type through its alias"));
}

// Carries the source span across a nested declarator.
static List Compiler._parenthesized(
  Compiler c, List context, List &method_identity, Token &source_first,
  Token &source_after) {
  c.next();
  Token first = c.token;
  List decl = c._declarator(
    NULL, context, method_identity, source_first, source_after);
  if (c.peek(0) != <)>) {
    c.require_input();
    /* One identifier followed by another is a parameter list whose type
       this unit cannot see, such as a package type named without its
       import alias, not a parenthesized declarator. */
    if (first.type == <ident> && c.peek(0) == <ident>)
      $report.parse_type_unknown(c, first);
    else
      $report.parse_paren_unclosed(c);
  }
  c.next();
  return decl;
}

static List Compiler._declarator_suffix(Compiler c) {
  List type = NULL;
  loop {
    // An attribute after a declarator modifies that declarator alone.
    String attribute = c._attribute();
    if (attribute)
      type = %( @type ($attribute) );
    else if (c.peek(0) == <[>)
      type = %( @type  @{c._array_suffix()} );
    else if (c.peek(0) == <:>) {
      c.next();
      List expr = c.parse_primary();
      type = %( @type (bitfield $expr) );
    }
    else if (c.peek(0) == <(>) {
      List params = c._function_parameters();
      params = %( params @params );
      type = type ? %(fnmod $params $type) : %((fnmod $params));
    }
    else break;
  }
  return type;
}

macro Statement $report.parse_dimension_close(
  Expr $c, Expr $expr, Expr $unexpected) {
  $c.report_error(
    <parse>, "expected ']'",
    $c.token, %("dimension:" ${$expr.str()} "symbol:" ${$unexpected.str()}));
}

static List Compiler._array_suffix(Compiler c) {
  c.next();
  if (c.peek(0) == <]>) {
    c.next();
    return %((dim));
  }
  List expr = c.parse_expression();
  if (c.peek(0) != <]>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    $report.parse_dimension_close(c, expr, unexpected);
  }
  c.next();
  return %((dim $expr));
}

/** Parses one declarator row for a macro argument without installing it.
    Its enclosing declaration supplies the base type when expanded. */
List Compiler.parse_declarator_argument(Compiler c) {
  List slot = c.try_parse_macro_slot(<decl-row>);
  if (slot) return slot;
  List method = NULL;
  Token first = NULL, after = NULL;
  List bind = c._declarator(NULL, NULL, method, first, after);
  if (c.test(<=>)) return %(op = $bind ${c.parse_assignment()});
  return bind;
}

/* template declarators

   In a macro template a declarator may name its binding through a Lisp
   slot, a Name hole, a member hole, or a name each expansion introduces. A
   method's owner may be a literal type or a type hole. */

// Returns NULL for another token, which takes the ordinary identifier path.
static List Compiler._template_declarator(Compiler c, int member) {
  List method = c._literal_method();
  if (!method) method = c._hole_method();
  if (method) return method;
  switch (c.peek(0)) {
    case <"$(">: {
      List slot = c.try_parse_macro_slot(<name>);
      return %(bind $slot ());
    }
    case <$>:
      return %(bind ${member ? c.try_parse_macro_member()
                             : c.try_parse_macro_slot(<name>)} ());
    case <ident>: {
      String spelling = c.token.text;
      int shadows_with = !!c.with_binding();
      c.next();
      if (member) return %(bind ($spelling) ());
      if (shadows_with) c.sym.define(%($spelling), NULL);
      return %(bind ${c.macro_introduced_name(spelling)} ());
    }
  }
  return NULL;
}

macro Statement $report.parse_method_name(Expr $c) {
  $c.report_error(
    <parse>, "expected method name",
    $c.token, NULL);
}

// `Type.member`, where the member may be a Name hole.
static List Compiler._literal_method(Compiler c) {
  Symbol owner_token = c.peek(0), String owner_spelling = c.token.text;
  Type owner_type =
    owner_spelling ? c.sym.get(%($owner_spelling)) : NULL;
  int literal_owner =
    owner_token.is_builtin_type() ||
    owner_token.is_type_modifier() ||
    (owner_token == <ident> &&
     (owner_type.is_typedef() || c.peek(1) == <.>));
  if (!literal_owner || c.peek(1) != <.> ||
      (c.peek(2) != <$> && c.peek(2) != <ident>))
    return NULL;
  c.next();
  c.expect(<.>);
  Var member;
  if (c.peek(0) == <$>) member = c.try_parse_macro_slot(<name>);
  else {
    if (!c.token.text.is_identifier())
      $report.parse_method_name(c);
    member = c.token.text;
    c.next();
  }
  return %(bind (($owner_spelling) $member) ());
}

macro Statement $report.parse_macro_member(Expr $c) {
  $c.report_error(
    <parse>, "macro method declaration requires a member name",
    $c.token, NULL);
}

// `$T.member`, where `$T` is a type hole.
static List Compiler._hole_method(Compiler c) {
  List owner_hole = c.peek_macro_hole();
  if (!owner_hole || owner_hole.assoc(<kind>) != <type> ||
      c.peek(2) != <.>)
    return NULL;
  List owner = c.try_parse_macro_slot(<type>);
  c.expect(<.>);
  Var member;
  if (c.peek(0) == <$>) member = c.try_parse_macro_slot(<name>);
  else if (c.token.text.is_identifier()) {
    member = c.token.text;
    c.next();
  }
  else
    $report.parse_macro_member(c);
  return %(bind (($owner) $member) ());
}

/** Installs a definition-local template binding or typedef provisionally.
    Later template types name a local typedef by its identity, so each
    expansion refers to that expansion's private typedef.
*/
void Compiler.bind_template_local(
  Compiler c, List key, List type, List context) {
  Var local = c.macro_holes && key ? c.macro_definition_locals()[key] : void;
  if (c.macro_holes && local is <string> &&
      (!context || context === %(typedef))) {
    if (context === %(typedef)) {
      c.sym.set(%($local), %(typedef $local));
      c.sym.set(%(typedef $local), %($key));
    }
    else c.sym.bind_identity(
      NULL, key,
      %(declare (<macro-expr>) (bindings (bind $key ()))));
  }
}

/* declarator installation

   A declarator's name is an exact spelling, a constructed binding identity,
   or a method's owner and member. Installation binds it in the current
   scope, records the method it declares, and resolves its initializer. */

static List Compiler._install_declarator(
  Compiler c, List base, List context, List declarator,
  List method_identity, int &preserved_self) {
  if (c.macro_holes) return declarator;
  Var name = void;
  List mods = NULL, initializer = NULL;
  match (declarator) {
    case %(op = (bind ?captured_name ?captured_mods) ?value):
      name = captured_name, mods = captured_mods, initializer = value;
    case %(bind ?captured_name ?captured_mods):
      name = captured_name, mods = captured_mods;
  }
  int exact_name = 0;
  name = c._declared_name(name, exact_name);
  List declaration = %(declare $base (bindings (bind () $mods)));
  List prior = name is <list> ? name : NULL;
  List method = method_identity ? method_identity
              : prior ? c._method_identity(prior) : NULL;
  List self_signature = prior ? c._method_self_signature(prior) : NULL;
  Type declared_type = mods.append(base);
  name = c._method_spelling(name, declared_type, method, exact_name);
  String exact = _syntax_exact_name(name);
  c._check_rebinding(exact, exact_name, declaration);
  List binding = exact ? c.sym.declare(context, %($exact), declared_type)
               : name is <list> ? name.list() : NULL;
  if (binding && !exact) c._bind_identity(context, binding, declaration);
  if (binding)
    c._method_facts(binding, method, self_signature, preserved_self);
  List bound = %(bind $binding $mods);
  if (initializer) initializer = c.resolve_expression(initializer, c.token);
  return initializer ? %(op = $bound $initializer) : bound;
}

// A name after its macro slot; `("x2c.ident" NAME)` is an exact spelling.
static Var Compiler._declared_name(Compiler c, Var name, int &exact_name) {
  name = c.evaluate_macro_slot(name);
  match (name)
    case %("x2c.ident" ?(String exact)):
      name = exact, exact_name = 1;
  return name;
}

macro Statement $report.type_method_owner(Expr $c) {
  $c.report_error(
    <type>, "method name has no concrete owner",
    $c.token, NULL);
}

/* Folds a literal owner and its member into the C spelling and records
   the method. A constructed source owner is no concrete owner, so only a
   static method declares its member as an exact spelling. */
static Var Compiler._method_spelling(
  Compiler c, Var name, Type declared_type, List &method, int &exact_name) {
  match (name) {
    case %(((!or (!is ?owner type string)
                  (!is ?owner type symbol)
                  ((!is ?owner type string))))
           ?(String member)): {
      String owner_name =
        owner is <symbol> ? owner.symbol() : owner.str();
      name = %"${owner_name}_$member";
      if (c.package) {
        String prefix = %"${c.package}__";
        if (owner_name.startswith(prefix))
          owner_name = owner_name[prefix.len():];
      }
      method = %($owner_name $member);
    }
    case %((!or
              (src (source (!is ? type string) ? ?) ?)
              (construct
                (src (source (!is ? type string) ? ?) ?)))
           ?(String member)):
      if (declared_type.is_static()) {
        name = member;
        exact_name = 1;
      }
      else $report.type_method_owner(c);
    case %((!is ? type list) (!is ? type string)):
      $report.type_method_owner(c);
  }
  return name;
}

macro Statement $report.parse_decl_bound(Expr $c, Expr $exact) {
  $c.report_error(
    <parse>, %"declaration '${$exact}' is already bound",
    $c.token, %("prior binding: '${$exact}'"));
}

/* An exact spelling, or a name a parameter holds, may be declared again only
   as another prototype of a function. */
static void Compiler._check_rebinding(
  Compiler c, String exact, int exact_name, List declaration) {
  List existing = exact ? c.sym.current_binding(%($exact)) : NULL;
  if (exact_name || (existing &&
      c.semantic_binding_facts().contains(%(parameter $existing)))) {
    Var prior = existing
              ? c.sym.current_symbols()[%($exact)] : void;
    if (prior is <list>) {
      Type prior_type = prior;
      Type candidate = declaration.type_from_ast();
      if (!candidate.is_function() || !prior_type.is_function())
        $report.parse_decl_bound(c, exact);
    }
  }
}

// Binds a constructed identity unless it is already its spelling's binding.
static void Compiler._bind_identity(
  Compiler c, List context, List binding, List declaration) {
  String spelling = binding_identity_spelling(binding);
  List visible = c.sym.lookup(%($spelling), NULL);
  if (visible != binding) c.sym.bind_identity(context, binding, declaration);
}

/* Records the method a binding declares, or drops a stale one, and keeps
   the Self signature an earlier declaration recorded. */
static void Compiler._method_facts(
  Compiler c, List binding, List method, List self, int &preserved_self) {
  if (method) c.semantic_binding_facts()[%(method $binding)] = method;
  else c.semantic_binding_facts().del(%(method $binding));
  if (!self) return;
  c.semantic_binding_facts()[%(self $binding)] = self;
  preserved_self = 1;
}

// parameters

macro Statement $report.parse_params_close(
  Expr $c, Expr $params, Expr $unexpected) {
  $c.report_error(
    <parse>, "expected ')'",
    $c.token, %("parameters:" ${$params.str()}
      "symbol:" ${$unexpected.str()}));
}

macro Statement $report.parse_params_empty(Expr $c) {
  $c.report_error(
    <parse>, "empty parameter list; use (void)",
    $c.token, NULL);
}

/* Parameter declarations bind into a temporary scope. The declarator cannot
   yet know whether a body follows, so keep that scope in `params`; finishing
   a definition replays it around the body, while a prototype never pushes
   the captured scope. */
static List Compiler._function_parameters(Compiler c) {
  c.next();
  c.__complete_here(<type>, _type_keywords());
  if (c.peek(0) == <)>)
    $report.parse_params_empty(c);
  SymScope saved = c.params, parsed;
  int complete = 0;
  defer { if (!complete) c.params = saved; }
  List params;
  c.sym.push_new_scope();
  {
    defer parsed = c.sym.pop_scope();
    params = c.parse_parameter_list();
  }
  if (c.peek(0) != <)>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    $report.parse_params_close(c, params, unexpected);
  }
  else c.next();
  c.params = parsed;
  complete = 1;
  return params;
}

/** Parses a nonempty comma-separated parameter `List` in source order.
    The caller owns the parameter scope; the first non-comma delimiter remains
    current.
*/
List Compiler.parse_parameter_list(Compiler c) {
  Array parameters = $auto([]);
  while (1) {
    c.__complete_here(<type>, _type_keywords());
    List parameter = c.try_parse_macro_slot(<param>);
    if (!parameter) parameter = c.parse_parameter();
    parameters.push(parameter);
    if (c.peek(0) != <,>) break;
    c.expect(<,>);
  }
  return parameters;
}

/** Parses one parameter and returns `(param TYPE DECLARATOR)` or `(...)`.
    Outside macro-template parsing, a named parameter is installed in the
    current `Sym` scope. The following delimiter remains current.
*/
List Compiler.parse_parameter(Compiler c) {
  if (c.test(<...>)) return %(...);
  List qual = c._type_qualifiers();
  List spec = c._type_specifier(), type = %( @qual @spec );
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = c._declarator(type, NULL, method, first, after);
  return c._finish_parameter(type, declarator, method, first, after);
}

static List Compiler._finish_parameter(
  Compiler c, List base, List declarator, List method_identity,
  Token source_first, Token source_after) {
  base = c._finish_type(base);
  int preserved_self = 0;
  declarator = c._install_declarator(
    base, NULL, declarator,
    method_identity, preserved_self);
  c.record_source_declaration(declarator.cadr(), source_first, source_after);
  List modifiers = NULL;
  base = _declaration_base(base, modifiers);
  declarator = _append_modifiers(declarator, modifiers);
  List parameter = %(param $base $declarator);
  match (declarator)
    case %(bind ?binding ?):
      if (!c.macro_holes) c._parameter_facts(binding, parameter);
  return parameter;
}

// Records a parameter binding and whether it is a reference, or optional.
static void Compiler._parameter_facts(
  Compiler c, Var binding, List parameter) {
  if (binding) c.semantic_binding_facts()[%(parameter $binding)] = 1;
  Type type = parameter.type_from_ast();
  if (type.is_reference())
    c.semantic_binding_facts()[%(reference-param $binding)] = 1;
  if (type.car() == <opt-ref>)
    c.semantic_binding_facts()[%(optional-reference-param $binding)] = 1;
}

// identifiers

/** Parses the current identifier or dotted owner/member as a one-item name.
    Package aliases and imported method spellings are folded through the
    current `Sym`, and all accepted tokens are consumed.
*/
List Compiler.parse_complex_identifier(Compiler c) =>
  c._complex_identifier(NULL);

/* Accept one of two forms of dotted identifiers: TYPE.IDENTIFIER or
   IDENTIFIER.TYPE. Preserve the explicit owner/member pair for declarations
   whose mangled spellings alone would be ambiguous. */
static List Compiler._complex_identifier(
  Compiler c, List &?method_identity) {
  if (method_identity) method_identity = NULL;
  String ident = c._package_alias_member(), Symbol toktype = c.token.type;
  /* Only a declarator asks for the method identity, and there the name is
     being defined. A `with` spelling must not fold, because the declaration
     belongs to this unit and shadows the binding. */
  if (!ident && toktype == <ident> && !method_identity)
    ident = c.package_member_spelling(c.token.text);
  if (!ident) ident = c.token.text;
  Type idtype = c.sym.get(%( $ident ));
  c.next();
  if ((toktype.is_builtin_type() || toktype.is_type_modifier() ||
       (toktype == <ident> && idtype.is_typedef())) && c.test(<.>))
    return c._member_name(ident, method_identity);
  return %($ident);
}

macro Statement $report.parse_method_member(Expr $c, Expr $owner) {
  $c.report_error(
    <parse>, "expected method name after dot",
    $c.token, %( "typedef:" ${$owner} "token:" ${$c.token.text}  ));
}

/* The member after `TYPE.` spells a method, which a declarator records as
   its owner and member. Elsewhere an imported package may have declared
   the method on one of its own header's types: the header spells the type,
   and the package spells the method. */
static List Compiler._member_name(
  Compiler c, String owner, List &?method_identity) {
  // a weaker test that accepts anything that looks like an identifier
  if (!c.token.text.is_identifier())
    $report.parse_method_member(c, owner);
  String member = c.token.text, ident = %"${owner}_$member";
  if (method_identity) method_identity = %($owner $member);
  if (!method_identity && !c.sym.get_exact(%($ident))) {
    String imported = c.imported_spelling(ident);
    if (imported) ident = imported;
  }
  c.next();
  return %( $ident );
}

/* Consume `alias .` and return the folded spelling. The member token stays
   current, so every caller continues down its identifier path. */
static String Compiler._package_alias_member(Compiler c) {
  String spelling = c.package_alias_spelling();
  if (!spelling) return NULL;
  String package = c.package_aliases[c.token.text];
  c.next();
  c.next();
  if (!c.sym.get_exact(%($spelling)))
    $report.parse_package_member(c, c.token, package, c.token.text);
  return spelling;
}

/** Returns the folded package-member spelling at the current token, or NULL.
    The token must be an unshadowed imported alias followed by `.` and an
    identifier. This lookahead does not consume tokens.
*/
String Compiler.package_alias_spelling(Compiler c) {
  if (!c.package_aliases.len()) return NULL;
  if (c.peek(0) != <ident> || c.peek(1) != <.>) return NULL;
  String alias = c.token.text;
  Var package = c.package_aliases[alias];
  if (package is void || c.sym.get_exact(%($alias))) return NULL;
  Token member = Token.skip_trivia(Token.skip_trivia(c.token + 1) + 1);
  return member.text.is_identifier()
       ? %"${package}__${member.text}" : NULL;
}

/** Consumes one `ident` token and returns its spelling as a one-item `List`.
*/
List Compiler.parse_basic_identifier(Compiler c) {
  String ident = c.token.text;
  c.expect(<ident>);
  return %($ident);
}

/** Consumes and returns the current identifier, or NULL without consuming. */
List Compiler.parse_optional_identifier(Compiler c) {
  if (c.peek(0) != <ident>) return NULL;
  String ident = c.token.text;
  c.expect(<ident>);
  return %($ident);
}

static String _syntax_exact_name(Var value) {
  if (value is <string>) return value;
  if (value is not <list>) return NULL;
  match (value) {
    case %(?(String exact)): return exact;
    case %("x2c.ident" ?(String exact)): return exact;
  }
  return NULL;
}

// function definitions

macro Statement $report.parse_function_body(Expr $c) {
  $c.report_error(
    <parse>, "Function macro argument requires a function body",
    $c.token, NULL);
}

/** Parses one function declaration and its required compound body.
    The parameter bindings are active while the body is parsed, and the first
    token after the closing brace remains current.
*/
List Compiler.parse_function_definition(Compiler c) {
  Token tokens = c.tokenizer.tokens, start = c.token;
  List declaration = c.parse_simple_declaration();
  if (c.peek(0) != <"{"> && !c._at_function_arrow())
    $report.parse_function_body(c);
  int first = start - tokens, body = c.token - tokens;
  List function = c._finish_function(declaration, NULL);
  if (!c.macro_holes)
    c._definition_source(function, start.line, NULL, %($first $body));
  return function;
}

/** Parses one function decorator target and returns its resulting AST.
    A compatible unit macro at the current token is expanded first; otherwise
    an ordinary function definition is required.
*/
List Compiler.parse_function_target(Compiler c) {
  List macro = c.try_parse_macro_target_at(AST_UNIT);
  if (!macro) return c.parse_function_definition();
  match (macro) case %(seq ?function): return function;
  return macro;
}

// Complete a token-parsed or generated function in its parameter scope.
static List Compiler._finish_function(
  Compiler c, List declaration, List syntax) {
  match (declaration)
    case %(declare ?rtype
           (bindings
             (!set ?declarator (bind ?binding ?)))):
      return c._finish_function_parts(
        declaration, rtype, declarator, binding,
        syntax);
  return NULL;
}

static List Compiler._finish_function_parts(
  Compiler c, List declaration, List rtype, List declarator,
  List binding, List syntax) {
  defer {
    c.params.symbols = NULL;
    c.params.bindings = NULL;
    c.params.enumerators = NULL;
    c.params.macros = NULL;
  }
  /* Validate lifecycle ownership before the body, but publish `init_fn` and
     `fini_fn` only after the parameter scope and body finish successfully.
     A caller's `SymTxn` can still roll those names back if a later generated
     sibling fails. */
  String initializer_owner = NULL, shutdown_owner = NULL;
  String name = c._prepare_lifecycle(
    declaration, binding, initializer_owner, shutdown_owner);
  List body = c._function_body(declaration, name, syntax);
  c._publish_lifecycle(name, initializer_owner, shutdown_owner);
  return %(function $rtype $declarator $body);
}

/* The body parses, or a constructed body binds, in the parameter scope with
   the function's return type and name current. */
static List Compiler._function_body(
  Compiler c, List declaration, String name, List syntax) {
  int expression_body = !syntax && c._at_function_arrow();
  if (!syntax && !expression_body) c.expect(<"{">);
  Type old_return = c.return_type, declared_return = NULL;
  match (declaration.type_from_ast())
    case %((func *) *result): declared_return = result.type().declared();
  c.return_type = declared_return;
  String old_fn = c.fn_name;
  c.fn_name = name;
  c.sym.push_scope(c.params);
  List body = NULL;
  {
    defer {
      c.sym.pop_scope();
      c.return_type = old_return;
      c.fn_name = old_fn;
    }
    if (syntax) body = c.bind_callable_body(syntax, c.return_type);
    else if (expression_body) body = c._expression_body();
    else body = c.parse_callable_body();
  }
  return body;
}

macro Statement $report.parse_shutdown_duplicate(Expr $c, Expr $name) {
  $c.report_error(
    <parse>, "translation unit has more than one type shutdown",
    $c.token, %( "shutdown:" ${$name} ));
}

macro Statement $report.parse_init_duplicate(Expr $c, Expr $name) {
  $c.report_error(
    <parse>, "translation unit has more than one type initializer",
    $c.token, %( "initializer:" ${$name} ));
}

static String Compiler._prepare_lifecycle(
  Compiler c, List declaration, List binding, String &initializer_owner,
  String &shutdown_owner) {
  String name = binding_identity_spelling(binding);
  initializer_owner = name
    ? c._lifecycle_owner(binding, "initialize") : NULL;
  shutdown_owner = name
    ? c._lifecycle_owner(binding, "shutdown") : NULL;
  if (initializer_owner) {
    c._require_signature(declaration, name, "initializer");
    if (c.init_fn && c.init_fn != name)
      $report.parse_init_duplicate(c, name);
  }
  if (shutdown_owner) {
    c._require_signature(declaration, name, "shutdown");
    if (c.fini_fn && c.fini_fn != name)
      $report.parse_shutdown_duplicate(c, name);
  }
  return name;
}

static String Compiler._lifecycle_owner(
  Compiler c, List binding, String member) {
  List method = c._method_identity(binding);
  if (!method) return NULL;
  match (method)
    case %(?name $member): {
      String owner = name, Type owner_type = c.sym.get(%($owner));
      return owner_type.is_typedef() ? owner : NULL;
    }
  return NULL;
}

macro Statement $report.parse_lifecycle_signature(
  Expr $c, Expr $role, Expr $name) {
  {
    String message = $role == "initializer"
      ? "type initializer must have signature void TYPE.initialize(void)"
      : "type shutdown must have signature void TYPE.shutdown(void)";
    $c.report_error(<parse>, message, $c.token, %("${$role}: ${$name}"));
  }
}

static void Compiler._require_signature(
  Compiler c, List decl, String name, String role) {
  match (decl)
    case %(declare (void)
           (bindings
             (bind ?
               ((fnmod (params (param (void) (bind () ())))))))):
      return;
  $report.parse_lifecycle_signature(c, role, name);
}

static void Compiler._publish_lifecycle(
  Compiler c, String name, String initializer_owner,
  String shutdown_owner) {
  if (initializer_owner) c.init_fn = name;
  if (shutdown_owner) c.fini_fn = name;
}

static List Compiler._expression_body(Compiler c) {
  with c {
    _.expect(<=>);
    _.expect(<">">);
    Token origin = _.token;
    _.sym.push_new_scope();
    List result = NULL;
    {
      defer _.sym.pop_scope();
      List expression = _.parse_expression();
      _.expect(<;>);
      /* A `void` result has no value to return, and C rejects a returned
         value there, so the expression stands as the body's statement. */
      result = _.return_type === %(void)
             ? %(stmnt $expression) : _.finish_return_statement(expression);
    }
    return %(block ${_.anchor_origin(result, origin)});
  }
}

// managed declarations

/** Lowers managed block declarations to declaration/defer pairs in source
    order, preserving their installed bindings and the enclosing lifetime.
*/
List Compiler.finish_managed_declaration(
  Compiler c, List declaration, Token origin) {
  if (c.macro_holes || !_has_managed(declaration))
    return declaration;
  Array output = [];
  c._append_managed(declaration, output, origin);
  return %(seq @{output.list_free()});
}

static int _has_managed(List declaration) {
  match (declaration) {
    case %(seq *rows):
      foreach (List row, rows)
        if (_has_managed(row)) return 1;
    case %(declare ? (bindings *declarators)):
      foreach (List declarator, declarators)
        match (declarator)
          case %(op = (bind ? ?) ?value):
            if (_managed_initializer(value)) return 1;
  }
  return 0;
}

/* Only the complete initializer admits management. Parentheses and typed
   expression shells preserve that position; operators do not. */
static List _managed_initializer(List syntax) {
  match (syntax) {
    case %(managed-init ?value): return value;
    case %(expr ? ?inner):
      return _managed_initializer(inner);
    case $source_content_pattern($grouped, %(?inner)):
      return _managed_initializer(inner);
  }
  return NULL;
}

macro open Statement $managed_cleanup(Expr $receiver) {
  defer $receiver.cleanup();
}

static void Compiler._append_managed(
  Compiler c, List declaration, Array output, Token origin) {
  match (declaration) {
    case %(seq *rows): {
      foreach (List row, rows)
        c._append_managed(row, output, origin);
      return;
    }
    case %(declare ?base (bindings *declarators)): {
      c._append_managed_rows(base, declarators, output, origin);
      return;
    }
  }
  output.push(declaration);
}

/* A managed declarator ends the declaration of the ordinary declarators
   before it and is followed by its deferred cleanup. */
static void Compiler._append_managed_rows(
  Compiler c, Var base, List declarators, Array output, Token origin) {
  Array ordinary = $auto([]);
  foreach (List declarator, declarators) {
    List initializer = NULL, binding = NULL, modifiers = NULL;
    match (declarator)
      case %(op = (bind ?name ?mods) ?value): {
        initializer = _managed_initializer(value);
        binding = name;
        modifiers = mods;
      }
    if (!initializer) {
      ordinary.push(declarator);
      continue;
    }
    Type type = modifiers.append(base).type().declared();
    c._require_cleanup(base, type, origin);
    if (ordinary.len()) {
      output.push(%(declare $base (bindings @{ordinary})));
      ordinary.clear();
    }
    output.push(
      %(declare $base
        (bindings (op = (bind $binding $modifiers) $initializer))));
    output.push(c._cleanup_statement(type, binding));
  }
  if (ordinary.len())
    output.push(%(declare $base (bindings @{ordinary})));
}

macro Statement $report.protocol_managed_cleanup(
  Expr $c, Expr $origin, Expr $type) {
  $c.report_error(
    <protocol>, "managed initializer requires Cleanup participation",
    $origin, %("type: ${$type.repr()}"));
}

macro Statement $report.parse_managed_storage(Expr $c, Expr $origin) {
  $c.report_error(
    <parse>, "managed initializer requires automatic local storage",
    $origin, NULL);
}

static void Compiler._require_cleanup(
  Compiler c, Var base, Type type, Token origin) {
  match (base)
    case %(* (!or static extern threaded) *):
      $report.parse_managed_storage(c, origin);
  if (!c.protocol_members_for(type, %("Cleanup")))
    $report.protocol_managed_cleanup(c, origin, type);
}

static List Compiler._cleanup_statement(Compiler c, Type type, List binding) {
  List receiver = %(expr $type (ident $binding));
  Macro cleanup = $managed_cleanup;
  return c.bind_syntax(cleanup(receiver), AST_STATEMENT, c.return_type);
}

// constructed syntax

macro Statement $report.parse_syntax_expected(Expr $c) {
  $c.report_error(
    <parse>, "expected syntax",
    $c.token, NULL);
}

/** Binds parser-shaped `syntax` at `context` into current compiler state.
    The input must evaluate to a nonempty AST `List` valid for the requested
    `AstPos`. Bindings, types, scopes, and expressions are resolved in source
    order; `return_type` applies only while descendants are bound. This method
    mutates `Sym` and does not open a semantic transaction.
*/
List Compiler.bind_syntax(
  Compiler c, Var syntax, AstPos context, Type return_type) {
  int pending = syntax is <list> && syntax.list().car() == "x2c.template";
  if (c._take_staged(syntax)) return syntax;
  syntax = c.evaluate_macro_slot(syntax);
  if (c._take_staged(syntax)) return syntax;
  if (syntax is not <list>)
    $report.parse_syntax_expected(c);
  List input = syntax;
  if (!input) $report.parse_syntax_expected(c);
  List enumerator =
    context == AST_ENUMERATOR ? c._bind_enumerator(input) : NULL;
  if (enumerator) return enumerator;
  if (context == AST_MAP_ENTRY && input.car() != <seq> &&
      input.car() != Atom.intern("macro-invoke"))
    return c.resolve_map_entry(input, c.token);
  $let(c.return_type, return_type)
    return c._bind_form(input, context, pending);
}

/* Replaces `syntax` with a staged code value and reports whether that
   value is a retained result, which binds no further. */
static int Compiler._take_staged(Compiler c, Var &syntax) {
  Var staged;
  int retained;
  if (!c.macro_application || !c.take_code_value(syntax, staged, retained))
    return 0;
  syntax = staged;
  return retained;
}

/* Publishes a name, a declarator, or an initialized one at an enumerator
   position as an enumerator of the aggregate being bound. Other forms go
   to the dispatcher, so this returns NULL for them. */
static List Compiler._bind_enumerator(Compiler c, List input) {
  match (input) {
    case %(!or
           (binding ? (!is ? type string))
           ((!is ? type string))
           ("x2c.ident" (!is ? type string))):
      return c._publish_enumerator(input, c.aggregate_type, c.token);
    case %(!set ?node
           (bind ? ?)):
      return c._publish_enumerator(node, c.aggregate_type, c.token);
    case %(!set ?node
           (op =
             (!or
               (binding ? (!is ? type string))
               ((!is ? type string))
               ("x2c.ident" (!is ? type string))
               (bind ? ?))
             ?)):
      return c._publish_enumerator(node, c.aggregate_type, c.token);
  }
  return NULL;
}

/* Parsed templates and compile-time Lisp are the intended producers. There
   is no separate validation pass before or after expansion. The structural
   match below enforces `AstPos`: a form that no arm admits at its position
   leaves the match for `_construction_error`. Existing expression types and
   binding identities are trusted, and strings are never reparsed.

   Binding mutates the current `Sym` in visitation order. Macro invocation
   opens the surrounding `SymTxn`, allowing earlier siblings to be visible to
   later ones while preserving whole-expansion rollback on failure. */
static List Compiler._bind_form(
  Compiler c, List input, AstPos context, int pending) {
  Macro if_then = $if_then, if_else = $if_else;
  Macro while_loop = $while_loop, do_loop = $do_loop, for_loop = $for_loop;
  Macro switched = $switched, expression_statement = $expression_statement;
  Macro return_empty = $return_empty, return_value = $return_value;
  Macro deferred = $deferred;
  Macro matched = $matched;
  Macro tried = $tried, caught = $caught;
  int unit = context == AST_UNIT, block = context == AST_BLOCK;
  int statement = block || context == AST_STATEMENT;
  match (input) {
    case %(macro-invoke ?definition ?arguments ?invocation):
      return c._bind_invocation(
        definition, arguments, invocation, context, pending);
    case %(macro-slot ? ? *): if (c.macro_holes) return input;
    case %(src ? ?syntax):
      return c.bind_syntax(syntax, context, c.return_type);
    case %(api-source ?line ?doc ?syntax):
      if (unit) return c._bind_api_source(line, doc, syntax);
    case %(named-type ?(String name) ?type):
      if (unit) return c._bind_named_type(name, type);
    case %(declaration-bundle (rows *rows)):
      if (unit) return c._bind_bundle(rows);
    case %(syntax-recipe ?callback ?arguments):
      return c._bind_recipe(callback, arguments, context);
    case %(declaration-recipe ?callback ?arguments):
      if (unit) return c._bind_decl_recipe(callback, arguments);
    case %(default-forward ?child ?parent ?member *fallback):
      if (unit) return %(declaration-forward $child $parent $member
                         $fallback ${c.source_private});
    case %(default ?function): if (unit) return c._bind_default(function);
    case %(declaration-function
             (declare ?return_type (bindings ?declarator))
             ?body ?construction):
      if (unit) return c._bind_collected_function(
        input, return_type, declarator, body, construction);
    case %(seq *items): return c._bind_items(items, context);
    case %(args *arguments):
      if (context == AST_EXPRESSION) return c._bind_args(arguments);
    case %(c-assert ?condition ?message):
      if (unit || block || context == AST_FIELD)
        return c._bind_assert(condition, message);
    case %(falias ?declaration ?native_syntax):
      if (unit) return c._bind_alias(declaration, native_syntax);
    case %(!set ?initializer (managed-init ?)):
      if (context == AST_EXPRESSION)
        return c._resolve(%(expr () $initializer));
    case %(!set ?expression (expr *)):
      if (context == AST_EXPRESSION) return c._resolve(expression);
    case %((!set ?tag (!or declare decl typedef))
           ?base (bindings *declarators)):
      return c._bind_declaration(tag, base, declarators, context);
    case %(dstrdecl ?base (targets *targets) ?source):
      if (block) return c._bind_targets(base, targets, source);
    case %(dstrdecl (params *parameters) ?source):
      if (block) return c._bind_typed_targets(parameters, source);
    case %(!set ?function
           (function ?return_type
             (bind ?function_name
               ((fnmod (params *parameter_values)) *return_modifiers))
             ?body)):
      if (unit)
        return c._bind_function(
          return_type, function_name, parameter_values,
          return_modifiers, body);
    case %(!set ?node ((!or protocol adopt meta-protocol) *)):
      if (unit) return c.publish_protocol_node(node, c.token, NULL);
    case %(!set ?definition (macrodef *)):
      return c._bind_macrodef(definition, context);
    case %(preproc ?(String directive)):
      if (unit || block) return c._bind_preproc(input);
    case %(at ?origin ?node):
      return c._anchor(origin, c.bind_syntax(node, context, c.return_type));
    case return_empty(): if (statement) return c.finish_return_statement(NULL);
    case return_value(?expression):
      if (statement) return c.finish_return_statement(expression);
    case %((!or break continue default empty)): if (statement) return input;
    case %(case ?expression):
      if (statement) return %(case ${c._resolve(expression)});
    case %((!set ?tag (!or goto label)) ?name):
      if (statement) return %($tag $name);
    case expression_statement(?expression):
      if (statement) return %(stmnt ${c._resolve(expression)});
    case deferred(?body):
      if (statement) return %(defer ${c._bind_statement(body)});
    case do_loop(?body, ?condition):
      if (statement) return c._bind_do(body, condition);
    case while_loop(?condition, ?body):
      if (statement) return c._bind_while(condition, body);
    case switched(?expression, ?body):
      if (statement) return c._bind_switch(expression, body);
    case if_then(?condition, ?ontrue):
      if (statement) return c._bind_if(condition, ontrue);
    case if_else(?condition, ?ontrue, ?onfalse):
      if (statement) return c._bind_if_else(condition, ontrue, onfalse);
    case for_loop(?init, ?condition, ?increment, ?body):
      if (statement) return c._bind_for(init, condition, increment, body);
    case %(raise ?code (args *details)):
      if (statement) return c._bind_raise(code, details);
    case %(catchcases ?arms *handler):
      if (context == AST_STATEMENT) return c._bind_catchcases(arms, handler);
    case caught(?body, ?cleanup, *arms):
      if (statement) return c._bind_try(body, input.caddr(), cleanup);
    case tried(?body, ?cleanup):
      if (statement) return c._bind_try(body, NULL, cleanup);
    case matched(?subject, *cases):
      if (statement) return c._bind_match(subject, cases);
    case $source_block_content(%(*children)):
      if (statement) return c._bind_block(input);
    case %(group *children): if (statement) return c._bind_group(children);
  }
  return c._construction_error();
}

/* Reports a constructed form at a position that does not admit it.
   `report_error` never returns, so a caller may return this call. */
static List Compiler._construction_error(Compiler c) {
  $report.parse_syntax_position(c, c.token);
}

static List Compiler._resolve(Compiler c, List expr) =>
  c.resolve_expression(expr, c.token);

static List Compiler._bind_statement(Compiler c, Var stmt) =>
  c.bind_syntax(stmt, AST_STATEMENT, c.return_type);

/* A macro invocation expands at the position that holds it. A Macro value
   applied directly owns the transaction that covers the effects its
   producers request, and stands for one statement or unit item. */
static List Compiler._bind_invocation(
  Compiler c, Var definition, Var arguments, Var invocation, AstPos context,
  int pending) {
  Token site = c.macro_invocation_site(invocation);
  if (invocation != <m-invoke>)
    return c.expand_macro_invocation_node(
      definition, arguments, site, context);
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    List bound = c.expand_macro_invocation_node(
      definition, arguments, site, context);
    transaction.commit();
    if (pending && (context == AST_BLOCK || context == AST_STATEMENT ||
                    context == AST_UNIT))
      match (bound) case %(seq ?item): return item;
    return bound;
  }
}

/* An anchor keeps a lone bound item, and a macro's origin marker becomes
   the compiler's current origin. */
static List Compiler._anchor(Compiler c, Var origin, List bound) {
  match (bound) case %(seq ?only): bound = only;
  Var anchor = origin == <m-origin> ? c.origin : origin;
  return %(at $anchor $bound);
}

// constructed file-scope forms

/* A definition an API source form wraps keeps its line and doc comment,
   or those of the invocation that expands it. */
static List Compiler._bind_api_source(
  Compiler c, Var line, Var doc, Var syntax) {
  List bound = c.bind_syntax(syntax, AST_UNIT, c.return_type);
  Token invocation = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
  String invocation_doc = invocation ? c.definition_doc(invocation) : NULL;
  c._definition_source(
    bound, invocation ? invocation.line : line,
    invocation_doc ? invocation_doc : doc, NULL);
  return bound;
}

static List Compiler._bind_named_type(Compiler c, String name, Var type) {
  List key = %($name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (!type.list()) return %(seq);
  List declaration = type.type().declaration_ast(key);
  match (declaration)
    case %(declare ?base ?bindings):
      return c.bind_syntax(%(typedef $base $bindings), AST_UNIT, NULL);
  return c._construction_error();
}

/* Binds a declaration bundle's rows in order. Collection first runs the
   pending declaration effects and returns the rows as a bundle. */
static List Compiler._bind_bundle(Compiler c, List rows) {
  if (c.shallow) {
    c.declaration_produced = 1;
    c.run_declaration_effects();
  }
  $let(c.declaration_projection, c.declaration_projection + 1) {
    Array projected = [];
    foreach (List row, rows) {
      List bound = c.bind_syntax(row, AST_UNIT, c.return_type);
      _append_rows(projected, bound);
    }
    List items = projected.list_free();
    return c.shallow ? %(declaration-bundle (rows @items)) : %(seq @items);
  }
}

static void _append_rows(Array output, List syntax) {
  match (syntax) {
    case %(seq *rows):
      foreach (List row, rows) _append_rows(output, row);
    case %(declaration-bundle (rows *rows)):
      foreach (List row, rows) _append_rows(output, row);
    default: output.push(syntax);
  }
}

static List Compiler._bind_recipe(
  Compiler c, Var callback, Var arguments, AstPos context) {
  Var syntax = c.evaluate_declaration_recipe(callback, arguments);
  return c.bind_syntax(syntax, context, c.return_type);
}

/* Collection keeps a declaration recipe pending with the macro stack that
   constructed it; the full parse evaluates it. */
static List Compiler._bind_decl_recipe(
  Compiler c, Var callback, Var arguments) {
  if (c.shallow)
    return %(declaration-pending $callback $arguments
              ${c.freeze_macro_stack()} ${c.source_private});
  return c._bind_recipe(callback, arguments, AST_UNIT);
}

static List Compiler._bind_default(Compiler c, Var function) {
  if (c.shallow)
    return %(declaration-default $function ${c.freeze_macro_stack()}
              ${c.source_private});
  return c.bind_syntax(function, AST_UNIT, c.return_type);
}

/* Binds a local macro definition in a block and publishes any other one
   at file scope. */
static List Compiler._bind_macrodef(
  Compiler c, Var definition, AstPos context) {
  List macro = definition;
  int local = macro.assoc(<local>).int();
  if (local && context == AST_BLOCK) {
    c.sym.define_macro(macro.assoc(<name>), macro);
    return %(seq);
  }
  if (!local && context == AST_UNIT)
    return c.publish_macro_definition_node(macro);
  return c._construction_error();
}

static List Compiler._bind_preproc(Compiler c, List directive) {
  c.update_source_visibility(%($directive));
  return directive;
}

static List Compiler._bind_alias(Compiler c, Var declaration, Var native) {
  List bound = c.bind_syntax(declaration, AST_UNIT, c.return_type);
  return c.finish_foreign_alias(bound, native);
}

// constructed functions

/* Collection binds a constructed function's declaration and keeps its body
   (see `_collected_function`). The full parse binds the whole function
   under the macro stack that constructed it, as a declaration default. */
static List Compiler._bind_collected_function(
  Compiler c, List input, Var return_type, Var declarator, Var body,
  Var construction) {
  if (c.shallow) return input;
  match (declarator) case %(bind ?binding *):
    c.semantic_binding_facts()[
      %(declaration-default ${binding_identity_spelling(binding)})] = 1;
  $let(c.macro_stack, c.thaw_declaration_syntax(construction)) {
    return c.bind_syntax(
      %(function $return_type $declarator $body), AST_UNIT, c.return_type);
  }
}

/* Binds a constructed function's parameters in a fresh prototype scope,
   which becomes its parameter scope, and then its declaration. */
static List Compiler._bind_function(
  Compiler c, Var return_type, Var function_name, List parameter_values,
  List return_modifiers, Var body) {
  List parameter_list = c._bind_parameters(parameter_values);
  List declarator = %(
    bind $function_name
      ((fnmod (params @parameter_list)) @return_modifiers)
  );
  List declaration = c.bind_syntax(
    %(declare $return_type (bindings $declarator)), AST_UNIT, c.return_type);
  if (c.shallow) return c._collected_function(declaration, body);
  return c._finish_function(declaration, body);
}

static List Compiler._bind_parameters(Compiler c, List values) {
  Array parameters = [];
  c.sym.push_new_scope();
  {
    defer c.params = c.sym.pop_scope();
    foreach (Var value, values)
      foreach (Var row, c.evaluate_macro_rows(value)) match (row) {
        case %(...): parameters.push(row);
        case %(param ?base (!set ?declarator (bind ? ?))):
          parameters.push(
            c._finish_parameter(base, declarator, NULL, NULL, NULL));
      }
  }
  return parameters.list_free();
}

/* Collection publishes a constructed function's declaration and keeps its
   body for the full parse. */
static List Compiler._collected_function(
  Compiler c, List declaration, Var body) {
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ?))): {
      String name = binding_identity_spelling(binding);
      // A static definition stays in its unit, as in source.
      if (type.type().is_static())
        c.sym.mark_static(%(function $name));
      else c.fn_defs[name] = 1;
      c.record_declaration_visibility(declaration);
    }
  return %(declaration-function $declaration $body ${c.freeze_macro_stack()});
}

// constructed declarations and expressions

macro Statement $report.parse_statement_single(Expr $c) {
  $c.report_error(
    <parse>, "expected one statement",
    $c.token, NULL);
}

/* A statement position admits a sequence of one statement. Elsewhere the
   items bind in order, and a nested sequence contributes its items. */
static List Compiler._bind_items(Compiler c, List items, AstPos context) {
  if (context == AST_STATEMENT) {
    match (items) case %(?only):
      return c.bind_syntax(only, context, c.return_type);
    $report.parse_statement_single(c);
  }
  Array bound = [];
  foreach (Var item, items)
    _push_items(bound, c.bind_syntax(item, context, c.return_type));
  return %(seq @{bound.list_free()});
}

static List Compiler._bind_args(Compiler c, List arguments) {
  Array bound = [];
  foreach (List argument, arguments) bound.push(c._resolve(argument));
  return %(args @{bound.list_free()});
}

static List Compiler._bind_assert(Compiler c, Var condition, Var message) =>
  %(c-assert ${c._resolve(condition)} ${c._resolve(message)});

/* Completes a constructed declaration's base type, then installs each
   declarator as the parser does. Only a field may declare a bit-field. */
static List Compiler._bind_declaration(
  Compiler c, Var tag, Var base, List declarators, AstPos context) {
  if (!_declaration_legal(tag, context)) return c._construction_error();
  base = c._finish_type(base);
  List field_context = context == AST_FIELD ? c.aggregate_type : NULL;
  List declaration_context = tag == <typedef> ? %(typedef) : field_context;
  Array output = [];
  int preserved_self = 0;
  foreach (List declarator, declarators) {
    declarator = c._finish_fnmods(declarator);
    if (context != AST_FIELD && _has_bitfield(declarator))
      return c._construction_error();
    List installed = c._install_declarator(
      base, declaration_context, declarator, NULL, preserved_self);
    output.push(installed);
  }
  List decl = c._finish_declaration(
    tag, base, output.list_free(), preserved_self);
  if (context == AST_UNIT) c.record_declaration_visibility(decl);
  if (context == AST_BLOCK && tag == <declare>)
    return c.finish_managed_declaration(decl, c.token);
  return decl;
}

/* A typedef stands in a unit or a block, a `decl` only in a block, and any
   other declaration also in an aggregate. */
static int _declaration_legal(Var tag, AstPos context) {
  if (tag == <typedef>) return context == AST_UNIT || context == AST_BLOCK;
  if (tag == <decl>) return context == AST_BLOCK;
  return context == AST_UNIT || context == AST_BLOCK || context == AST_FIELD;
}

static int _has_bitfield(List declarator) {
  List syntax = declarator;
  match (syntax) case %(op = ?binding ?): syntax = binding;
  match (syntax)
    case %(bind ? ?modifiers): {
      Type mods = modifiers;
      return mods.is_bitfield();
    }
  return 0;
}

/* Destructuring targets share one base type, so they bind as one
   declaration before the source resolves. */
static List Compiler._bind_targets(
  Compiler c, Var base, List targets, Var source) {
  Array declarators = [];
  foreach (Var target, targets) declarators.push(%(bind $target ()));
  List declaration = c.bind_syntax(
    %(declare $base
        (bindings @{declarators.list_free()})),
    AST_BLOCK, c.return_type
  );
  match (declaration)
    case %(declare ?bound_base (bindings *bindings)): {
      Array bound_targets = [];
      foreach (List binding, bindings)
        match (binding)
          case %(bind ?name ?): bound_targets.push(name);
      return %(dstrdecl $bound_base
               (targets @{bound_targets.list_free()})
               ${c._resolve(source)});
    }
  return c._construction_error();
}

/* Each typed target contributes one bound declaration. */
static List Compiler._bind_typed_targets(
  Compiler c, List parameters, Var source) {
  Array bound_parameters = [];
  foreach (List parameter, parameters)
    match (parameter)
      case %(param ?base (!set ?declarator (bind ? ?))): {
        List declaration = c.bind_syntax(
          %(declare $base (bindings $declarator)), AST_BLOCK, c.return_type);
        match (declaration)
          case %(declare ?bound_base (bindings ?binding)):
            bound_parameters.push(%( param $bound_base $binding ));
      }
  return %(dstrdecl (params @{bound_parameters.list_free()})
           ${c._resolve(source)});
}

// constructed statements

static List Compiler._bind_do(Compiler c, Var body, Var condition) =>
  %(do ${c._bind_statement(body)} ${c._resolve(condition)});

static List Compiler._bind_while(Compiler c, Var condition, Var body) =>
  %(while ${c._resolve(condition)} ${c._bind_statement(body)});

static List Compiler._bind_switch(Compiler c, Var expr, Var body) =>
  %(switch ${c._resolve(expr)} ${c._bind_statement(body)});

/* Binds the arm where an optional-reference test holds with the reference
   present, and marks it present after the `if` when the other arm cannot
   fall through. */
static List Compiler._bind_if(Compiler c, Var condition, Var ontrue) {
  List test = c._resolve(condition);
  int true_is_present = 1;
  List binding = c.optional_reference_test(test, true_is_present);
  List yes = c._bind_branch(ontrue, binding, true_is_present);
  c.settle_reference(binding, true_is_present, yes, NULL);
  return %(if $test $yes);
}

static List Compiler._bind_if_else(
  Compiler c, Var condition, Var ontrue, Var onfalse) {
  List test = c._resolve(condition);
  int true_is_present = 1;
  List binding = c.optional_reference_test(test, true_is_present);
  List yes = c._bind_branch(ontrue, binding, true_is_present);
  List no = c._bind_branch(onfalse, binding, !true_is_present);
  c.settle_reference(binding, true_is_present, yes, no);
  return %(if $test $yes $no);
}

static List Compiler._bind_branch(
  Compiler c, Var arm, List binding, int present) {
  if (!binding) return c._bind_statement(arm);
  List before = c.present_references();
  if (present) c.mark_reference_present(binding);
  List bound = c._bind_statement(arm);
  c.restore_reference_presence(before);
  return bound;
}

static List Compiler._bind_for(
  Compiler c, Var init, Var condition, Var increment, Var body) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  if (init is <list>) {
    List node = init;
    init = node.car() == <decl>
         ? c.bind_syntax(node, AST_BLOCK, c.return_type)
         : c._resolve(node);
  }
  if (condition is <list>) condition = c._resolve(condition);
  if (increment is <list>) increment = c._resolve(increment);
  return %(for $init $condition $increment ${c._bind_statement(body)});
}

static List Compiler._bind_raise(Compiler c, Var code, List details) {
  Array bound = [];
  foreach (List detail, details) bound.push(c._resolve(detail));
  return %(raise ${c._resolve(code)} (args @{bound.list_free()}));
}

/* Binds each catch arm's pattern names in a scope of its own, with the
   arm's binder declarations before its body. */
static List Compiler._bind_catchcases(Compiler c, Var arms, List handler) {
  List handle = handler ? handler.car().list()
    : c.sym.introduce(c.fresh_name("error_handler"));
  Array bound = [];
  foreach (List arm, arms.list()) {
    List pattern = arm.car();
    List bindings = c.begin_catch_arm(pattern, c.token);
    {
      defer c.sym.pop_scope();
      bound.push(
        %(
          $pattern
          (block
            @{c.catch_binder_declarations(bindings, handle)}
            ${c._bind_statement(arm.cadr())})
        ));
    }
  }
  return %(catchcases ${bound.list_free()} $handle);
}

static List Compiler._bind_try(
  Compiler c, List body, List catches, List cleanup) {
  if (catches) catches = c._bind_statement(catches);
  if (cleanup) cleanup = c._bind_statement(cleanup);
  body = c._bind_statement(body);
  Macro tried = $tried, caught = $caught;
  List statement = catches
    ? caught(body, cleanup, catches.cadr()) : tried(body, cleanup);
  List rebuilt = c.rebuild_statement(statement).cadr();
  return catches
    ? retain_catch_handle(rebuilt, catches.caddr()) : rebuilt;
}

/* Binds each `match` arm's captures in a scope of its own. */
static List Compiler._bind_match(Compiler c, Var subject, List cases) {
  Array bound = [];
  foreach (List row, cases) {
    if (row.car() == <preproc>) {
      bound.push(row);
      continue;
    }
    List pattern = row.car();
    int binds = pattern !== %(*);
    if (binds) pattern = c._resolve(pattern);
    c.begin_match_arm(pattern, c.token, binds);
    {
      defer c.sym.pop_scope();
      List body = c._bind_arm_body(row.cadr());
      bound.push(%($pattern $body));
    }
  }
  return %(match ${c._resolve(subject)} ${bound.list_free()});
}

static List Compiler._bind_arm_body(Compiler c, List body) {
  match (body) {
    case %(guarded ?statements):
      body = %(guarded ${c._bind_statement(statements)});
    default: body = c._bind_statement(body);
  }
  return body;
}

/* A constructed block opens its own scope; a callable's outer block binds
   in its parameter scope instead. */
static List Compiler._bind_block(Compiler c, List block) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  return c.bind_callable_body(block, c.return_type);
}

static List Compiler._bind_group(Compiler c, List children) {
  Array items = [];
  foreach (Var child, children)
    items.push(c.bind_syntax(child, AST_BLOCK, c.return_type));
  return %(group @{items.list_free()});
}

/** Binds a callable's outer block in its active parameter scope. Ordinary
    constructed blocks open their own scope before using this operation.
*/
List Compiler.bind_callable_body(Compiler c, List syntax, Type return_type) {
  match (syntax) {
    case %(at ?origin ?body):
      return c._anchor(origin, c.bind_callable_body(body, return_type));
    case $source_block_content(%(*children)): {
      Array stmts = [];
      List present_before = c.present_references();
      defer c.restore_reference_presence(present_before);
      foreach (Var child, children)
        _push_items(stmts, c.bind_syntax(child, AST_BLOCK, return_type));
      return %(block @{stmts.list_free()});
    }
  }
  return c.bind_syntax(syntax, AST_BLOCK, return_type);
}

// constructed types

static List Compiler._finish_type(Compiler c, List type) {
  Var whole = c._finish_type_spec(type);
  // Binding an already constructed aggregate can preserve its whole form.
  if (whole != type || type.car() == <struct> ||
      type.car() == <union> || type.car() == <enum>) {
    List constructed = whole;
    Type finished = constructed.car() == <seq>
                  ? constructed.cdr() : constructed;
    return c.sym.local_type(finished);
  }
  Array bound = [];
  foreach (Var spec, type) {
    Var finished = c._finish_type_spec(spec);
    if (finished is <list> && !finished.is_nil() &&
        finished.car() == <seq>)
      foreach (Var item, finished.list().cdr()) bound.push(item);
    else bound.push(finished);
  }
  Type resolved = bound.list_free();
  return c.sym.local_type(resolved);
}

static Var Compiler._finish_type_spec(Compiler c, Var spec) {
  int slot = spec is <list> && !spec.is_nil() &&
             spec.car() == <macro-slot>;
  spec = c.evaluate_macro_slot(spec);
  if (slot && spec is <list>) {
    Type type = spec.type().canonicalize();
    return %(seq @type);
  }
  if (spec is not <list>) return spec;
  match (spec) {
    case %((!set ?tag (!or struct union)) ?name):
      return %($tag ${c._finish_tag_name(name)});
    case %((!set ?tag (!or struct union)) ?name (fields *members)):
      return c._finish_aggregate_type(tag, name, members);
    case %(enum ?name):
      return %(enum ${c._finish_tag_name(name)});
    case %(enum ?name (*members)):
      return c._finish_aggregate_type(<enum>, name, members);
    // Semantic types name an expanded template typedef by its spelling.
    case %(binding ? ?(String name)): return name;
  }
  return spec;
}

static Var Compiler._finish_tag_name(Compiler c, Var name) {
  name = c.evaluate_macro_slot(name);
  String exact = _syntax_exact_name(name);
  return exact ? exact : name;
}

static List Compiler._finish_aggregate_type(
  Compiler c, Symbol tag, Var name, List members) {
  name = c._finish_tag_name(name);
  // Each constructed anonymous body defines a distinct type.
  match (name) case %(gensym ? ?): name = c.gensym().car();
  if (tag != <enum>) name = c.aggregate_name(tag, name, 1);
  List type = %($tag $name);
  Array bound = [];
  AstPos position = tag == <enum> ? AST_ENUMERATOR : AST_FIELD;
  $let(c.aggregate_type, type) {
    foreach (List member, members)
      foreach (Var row, c.evaluate_macro_rows(member))
        bound.push(c.bind_syntax(row, position, c.return_type));
  }
  return c._publish_aggregate_type(tag, name, bound.list_free(), c.token);
}

/* Constructed function modifiers have not passed through the parameter
   parser. Bind their parameter types in the same temporary prototype scope. */
static List Compiler._finish_fnmods(Compiler c, List declarator) {
  match (declarator) {
    case %(op = ?binding ?value):
      return %(op = ${c._finish_fnmods(binding)} $value);
    case %(bind ?binding ?modifiers): {
      Array output = [];
      foreach (Var modifier, modifiers.list())
        output.push(c._finish_fnmod(modifier));
      return %(bind $binding (@{output.list_free()}));
    }
  }
  return declarator;
}

static Var Compiler._finish_fnmod(Compiler c, Var modifier) {
  match (modifier)
    case %(fnmod (params *parameters)):
      return %(fnmod (params @{c._finish_prototype(parameters)}));
  return modifier;
}

static List Compiler._finish_prototype(Compiler c, List parameters) {
  Array params = [];
  c.sym.push_new_scope();
  {
    defer c.sym.pop_scope();
    foreach (List parameter, parameters) match (parameter) {
      case %(param ?base ?declarator):
        params.push(
          c._finish_parameter(
            base, c._finish_fnmods(declarator), NULL, NULL, NULL));
      default: params.push(parameter);
    }
  }
  return params.list_free();
}

// foreign aliases

macro Statement $report.parse_alias_target(Expr $c) {
  $c.report_error(
    <parse>, "foreign alias target must be one direct function declaration",
    $c.token, NULL);
}

macro Statement $report.parse_alias_body(Expr $c) {
  $c.report_error(
    <parse>, "foreign alias declaration cannot have a body",
    $c.token, NULL);
}

/** Constructs a foreign alias from one direct function declaration and target.
    `native_syntax` must resolve to a different direct identifier and, when
    typed, a function. Storage is limited to `static` or `inline`, when
    present, and variadic parameters are rejected.
*/
List Compiler.finish_foreign_alias(
  Compiler c, List declaration, List native_syntax) {
  match (declaration) {
    case %(function *):
      $report.parse_alias_body(c);
    /* A function returning a pointer puts its pointer modifiers after the
       fnmod. The trailing modifiers are the return type's pointer depth; the
       declaration is still one direct function. */
    case %(declare (!set ?base (*))
           (bindings
             (bind ?binding ((fnmod (params *parameters)) *)))): {
      c._alias_storage(base);
      c._alias_parameters(parameters);
      return c._alias_target(declaration, binding, native_syntax);
    }
  }
  $report.parse_alias_target(c);
}

macro Statement $report.parse_alias_storage(Expr $c) {
  $c.report_error(
    <parse>, "foreign alias has invalid storage class",
    $c.token, %("allowed storage: static or inline"));
}

static void Compiler._alias_storage(Compiler c, Var base) {
  foreach (Var part, base) {
    if (part is not <symbol>) continue;
    Symbol specifier = part;
    if (specifier.is_storage_class() && specifier != <static>)
      $report.parse_alias_storage(c);
  }
}

macro Statement $report.parse_alias_variadic(Expr $c) {
  $c.report_error(
    <parse>, "foreign alias cannot be variadic",
    $c.token, NULL);
}

static void Compiler._alias_parameters(Compiler c, List parameters) {
  foreach (Var parameter, parameters)
    match (parameter) case %(...):
      $report.parse_alias_variadic(c);
}

macro Statement $report.parse_alias_identifier(Expr $c) {
  $c.report_error(
    <parse>, "foreign alias native target must be a direct identifier",
    $c.token, NULL);
}

macro Statement $report.parse_alias_self(Expr $c) {
  $c.report_error(
    <parse>, "foreign alias cannot name itself",
    $c.token, NULL);
}

macro Statement $report.type_alias_function(Expr $c, Expr $native_type) {
  $c.report_error(
    <type>, "foreign alias native target is not a function",
    $c.token, %("type: ${$native_type.repr()}"));
}

static List Compiler._alias_target(
  Compiler c, List declaration, Var binding, List native_syntax) {
  List native = c.resolve_expression(native_syntax, c.token);
  match (native)
    case %(expr (!set ?native_type (*)) ${$source_identifier_content(
        %(?native_binding))}): {
      if (native_type && !native_type.type().is_function())
        $report.type_alias_function(c, native_type);
      if (List.equal(binding, native_binding))
        $report.parse_alias_self(c);
      return %(falias $declaration $native_binding);
    }
  $report.parse_alias_identifier(c);
}
