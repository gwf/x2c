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
#include "private-keywords.x"
static keyword loop $private.loop;
#include "compiler.x"
#include "type.x"
#include "parse-report-macros.x"
#include "grammar.x"
#include "statements.x"
#include "expressions.x"
#include "literals.x"
#include "collect.x"
#include "macros.x"
#include "protocol.x"
#include "utils.x"

/* parse diagnostics. */

static macro Stmt $report.parse.decorator_top(Expr $c) =>
  $c.report_error(
    <parse>, "top-level decorators are not supported",
    $c.token, %( "module initialization: void TYPE.initialize(void)" ));

static macro Stmt $report.parse.body_expected(Expr $c, Expr $unexpected) =>
  $c.report_error(
    <parse>, "expected ';', '{', or '=>'",
    $c.token, %("token:" ${$c.token.text} "symbol:" ${$unexpected.str()}));

static macro Stmt $report.parse.meta_function(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "a native meta declaration must be a function",
    $origin, NULL);

static macro Stmt $report.parse.unit_single(Expr $c) =>
  $c.report_error(
    <parse>, "submit one top-level item at a time",
    $c.token, NULL);

static macro Stmt $report.parse.package_identifier(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "package name must be a C identifier",
    $origin, NULL);

static macro Stmt $report.parse.import_name(Expr $c) =>
  $c.report_error(
    <parse>, "expected a quoted package name after 'import'",
    $c.token, NULL);

static macro Stmt $report.parse.import_local(Expr $c) =>
  $c.report_error(
    <parse>, "expected a local name after 'as'",
    $c.token, NULL);

static macro Stmt $report.parse.import_member(Expr $c) =>
  $c.report_error(
    <parse>, "expected a package member name after 'with'",
    $c.token, NULL);

static macro Stmt $report.parse.function_row(Expr $c) =>
  $c.report_error(
    <parse>, "a function definition cannot share a declaration row",
    $c.token, NULL);

static macro Stmt $report.parse.meta_constructed(
  Expr $c, Expr $name, Expr $origin) =>
  $c.report_error(
    <parse>, %"meta function '${$name}' cannot be produced by a macro",
    $origin, %( "move it to a source file and call it from the macro" ));

static macro Stmt $report.parse.decl_function(Expr $c) =>
  $c.report_error(
    <parse>, "Decl macro argument cannot be a function declaration",
    $c.token, NULL);

static macro Stmt $report.parse.decl_typedef(Expr $c) =>
  $c.report_error(
    <parse>, "Decl macro argument cannot be a typedef",
    $c.token, NULL);

static macro Stmt $report.parse.destructure_init(Expr $c) =>
  $c.report_error(
    <parse>, "destructuring declaration requires an initializer",
    $c.token, NULL);

static macro Stmt $report.parse.destructure_name(Expr $c) =>
  $c.report_error(
    <parse>, "expected identifier in destructuring declaration",
    $c.token, %("destructuring targets must be simple identifiers"));

static macro Stmt $report.type.scalar_invalid(
  Expr $c, Expr $source, Expr $origin) =>
  $c.report_error(
    <type>, $source ? %"invalid scalar type ${$source}"
                 : "expected scalar type",
    $origin, NULL);

static macro Stmt $report.parse.attribute_packed(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "packed attributes are unsupported",
    $origin, NULL);

static macro Stmt $report.parse.delegate_name(Expr $c) =>
  $c.report_error(
    <parse>, "delegate field requires a name",
    $c.token, NULL);

static macro Stmt $report.parse.named_type_abstract(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "named type requires an abstract type after its name",
    $origin, NULL);

static macro Stmt $report.parse.enum_name(Expr $c) =>
  $c.report_error(
    <parse>, "expected enumerator identifier",
    $c.token, NULL);

static macro Stmt $report.parse.enum_bound(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"enumerator '${$spelling}' is already bound in this scope",
    $origin, %("prior binding: '${$spelling}'"));

static macro Stmt $report.parse.syntax_position(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "syntax cannot be constructed at this position",
    $origin, NULL);

static macro Stmt $report.parse.paren_unclosed(Expr $c) =>
  $c.report_error(
    <parse>, "missing closing parenthesis",
    $c.token, NULL);

static macro Stmt $report.parse.type_unknown(Expr $c, Expr $first) =>
  $c.report_error(
    <parse>, %"unknown type name '${$first.text}'",
    $first, %("name an imported package type through its alias"));

static macro Stmt $report.parse.dimension_close(
  Expr $c, Expr $expr, Expr $unexpected) =>
  $c.report_error(
    <parse>, "expected ']'",
    $c.token, %("dimension:" ${$expr.str()} "symbol:" ${$unexpected.str()}));

static macro Stmt $report.parse.macro_member(Expr $c) =>
  $c.report_error(
    <parse>, "macro method declaration requires a member name",
    $c.token, NULL);

static macro Stmt $report.type.method_owner(Expr $c) =>
  $c.report_error(
    <type>, "method name has no concrete owner",
    $c.token, NULL);

static macro Stmt $report.parse.decl_bound(Expr $c, Expr $exact) =>
  $c.report_error(
    <parse>, %"declaration '${$exact}' is already bound",
    $c.token, %("prior binding: '${$exact}'"));

static macro Stmt $report.parse.params_close(
  Expr $c, Expr $params, Expr $unexpected) =>
  $c.report_error(
    <parse>, "expected ')'",
    $c.token, %("parameters:" ${$params.str()}
      "symbol:" ${$unexpected.str()}));

static macro Stmt $report.parse.params_empty(Expr $c) =>
  $c.report_error(
    <parse>, "empty parameter list; use (void)",
    $c.token, NULL);

static macro Stmt $report.parse.method_member(Expr $c, Expr $owner) =>
  $c.report_error(
    <parse>, "expected method name after dot",
    $c.token, %( "typedef:" ${$owner} "token:" ${$c.token.text}  ));

static macro Stmt $report.parse.function_body(Expr $c) =>
  $c.report_error(
    <parse>, "Function macro argument requires a function body",
    $c.token, NULL);

static macro Stmt $report.parse.shutdown_duplicate(Expr $c, Expr $name) =>
  $c.report_error(
    <parse>, "translation unit has more than one type shutdown",
    $c.token, %( "shutdown:" ${$name} ));

static macro Stmt $report.parse.init_duplicate(Expr $c, Expr $name) =>
  $c.report_error(
    <parse>, "translation unit has more than one type initializer",
    $c.token, %( "initializer:" ${$name} ));

static macro Stmt $report.parse.lifecycle_signature(
  Expr $c, Expr $role, Expr $name) {
  {
    String message = $role == "initializer"
      ? "type initializer must have signature void TYPE.initialize(void)"
      : "type shutdown must have signature void TYPE.shutdown(void)";
    $c.report_error(<parse>, message, $c.token, %("${$role}: ${$name}"));
  }
}

static macro Stmt $report.parse.init_incomplete(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>,
    "managed initializer requires a complete block-local initializer",
    $origin, NULL);

static macro Stmt $report.parse.placement_repeated(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "code placed after a declarator repeats an earlier placement",
    $origin, %("a managed initializer cannot manage another one"));

static macro Stmt $report.parse.placement_item(Expr $c) =>
  $c.report_error(
    <macro>, "code placed after a statement needs an enclosing block item",
    $c.token, NULL);

static macro Stmt $report.parse.placement_function(Expr $c) =>
  $c.report_error(
    <macro>, "code placed at function entry needs an enclosing function",
    $c.token, NULL);

/* Reported at the lowering origin when one is set. */
static macro Stmt $report.parse.placement_finalizer(Expr $c) =>
  $c.report_error(
    <macro>, "code placed at function entry cannot land in a defer finalizer",
    NULL,
    %("a finalizer runs as its own callback; place after a statement"));

static macro Stmt $report.parse.syntax_expected(Expr $c) =>
  $c.report_error(
    <parse>, "expected syntax",
    $c.token, NULL);

static macro Stmt $report.parse.statement_single(Expr $c) =>
  $c.report_error(
    <parse>, "expected one statement",
    $c.token, NULL);

static macro Stmt $report.parse.alias_target(Expr $c) =>
  $c.report_error(
    <parse>, "foreign alias target must be one direct function declaration",
    $c.token, NULL);

static macro Stmt $report.parse.alias_body(Expr $c) =>
  $c.report_error(
    <parse>, "foreign alias declaration cannot have a body",
    $c.token, NULL);

static macro Stmt $report.parse.alias_storage(Expr $c) =>
  $c.report_error(
    <parse>, "foreign alias has invalid storage class",
    $c.token, %("allowed storage: static or inline"));

static macro Stmt $report.parse.alias_variadic(Expr $c) =>
  $c.report_error(
    <parse>, "foreign alias cannot be variadic",
    $c.token, NULL);

static macro Stmt $report.parse.alias_identifier(Expr $c) =>
  $c.report_error(
    <parse>, "foreign alias native target must be a direct identifier",
    $c.token, NULL);

static macro Stmt $report.parse.alias_self(Expr $c) =>
  $c.report_error(
    <parse>, "foreign alias cannot name itself",
    $c.token, NULL);

static macro Stmt $report.type.alias_function(Expr $c, Expr $native_type) =>
  $c.report_error(
    <type>, "foreign alias native target is not a function",
    $c.token, %("type: ${$native_type.repr()}"));

static macro Stmt $report.type.reference_placement(Expr $c) =>
  $c.report_error(
    <type>, "transparent references are only supported on parameters",
    NULL, NULL);

static macro Stmt $report.type.binder_conflict(
  Expr $c, Expr $role, Expr $origin, Expr $name) =>
  $c.report_error(
    <type>, %"${$role} binder has conflicting capture kinds",
    $origin, %( "binder:" ${$name} "use either '?' or '*' consistently"));

static macro Stmt $report.type.binder_unassigned(
  Expr $c, Expr $role, Expr $origin, Expr $binder) =>
  $c.report_error(
    <type>, %"${$role} binder is not definitely assigned",
    $origin, %( "binder:" ${$binder.str()}
                "bind it in every alternative and never under !not"));

// top-level forms

/** Parses one top-level form and applies its source-ordered compiler effects.
    Returns its AST, or NULL when a keyword definition, top-level Lisp form,
    linkage brace, or compile-time-only `meta` function only updates compiler
    state, with the first following token current. With `skip_body`,
    collection uses the same classifier and bound declarations but skips
    runtime bodies.
    This continuation is independent of the compiler's shallow-parse state.
*/
List Compiler.parse_top_level_mode(Compiler c, int skip_body) {
  _leading_directives(c, skip_body);
  if (c.skip_linkage_brace()) return NULL;
  if (skip_body && c.skip_collected_script_statement()) return NULL;
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = skip_body ? NULL : c.try_parse_macro_slot(<unit>);
  if (slot) return slot;
  if (c.keyword_form_is_definition()) return _keyword_definition(c, skip_body);
  if (_module_storage_form(c)) {
    c.token.type = <static>;
    $let(c.module_declaration, 1) return c.parse_top_level_mode(skip_body);
  }
  if (_static_interface_form(c)) {
    c.next();
    $let(c.source_private, 1) {
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
      return c.parse_import_declaration();
    case <"$(">:   return _top_level_lisp(c, skip_body);
    case <@>:      return _top_level_decorator(c);
  }
  if (c.macro_form_is_definition()) return c.parse_macro_definition();
  return _declaration_form(c, skip_body);
}

/* Static storage also applies to source types and compile-time effects. */
static int _static_interface_form(Compiler c) {
  if (c.peek(0) != <static>) return 0;
  Token next = Token.skip_trivia(c.token + 1);
  return c.peek(1) == <typedef> ||
         (c.peek(1) == <"$("> && !c.macro_holes) ||
         c.peek(1) == <protocol> || next.text == "class";
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

/* Top-level Lisp updates compiler state without emitting a runtime form. */
static List _top_level_lisp(Compiler c, int skip_body) {
  if (c.signature_only && !c.macro_holes) {
    c.token = c.token.group_close().after_group();
    return NULL;
  }
  if (skip_body) c.parse_macro_lisp_shallow();
  else c.parse_macro_lisp_top_level();
  return NULL;
}

static List _top_level_decorator(Compiler c) {
  $report.parse.decorator_top(c);
}

/* A declaration row after any `meta` marker. Collection records it; the
   full parse completes a declaration at `;` or a definition at its body. */
static List _declaration_form(Compiler c, int skip_body) {
  Token meta = NULL;
  int native = 0;
  if (c.meta_form_is_declaration()) meta = c.take_meta_marker(native);
  Token first = c.token;
  List decl;
  $let(c.shallow, c.shallow || c.public_bodies)
  $let(c.macro_holes, c.signature_only && !c.macro_holes
         ? {} : c.macro_holes)
    decl = c.parse_declaration_row();
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
    $report.parse.meta_function(c, meta);
  if (c.test(<;>)) return _declared(c, decl, meta, first);
  if (body) return _defined(c, decl, meta, native, first);
  c.require_input();
  Symbol unexpected = c.peek(0);
  $report.parse.body_expected(c, unexpected);
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
    $report.parse.unit_single(c);
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
  if (_module_storage_form(c)) return 0;
  if (c.test_static_assert() || c.keyword_form_is_definition() ||
      c.macro_form_is_definition() || c.meta_form_is_declaration() ||
      c.protocol_form_starts())
    return 0;
  if (c.at_word("with")) return 1;
  if (c.macro_starts_target_at(<unit>)) return !c.macro_targets_unit();
  return !c.test_declaration() || !_declaration_stays(c);
}

/* A declaration in a script unit stays at file scope when a body follows
   its declarator, `{` for a function or aggregate and `=>` for an
   expression-bodied function, or when it ends right after a parameter list
   as a prototype does. An initialized or plain object declaration belongs
   to `main`. */
static int _declaration_stays(Compiler c) {
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
  String name = _package_name(c), alias = _import_alias(c, name);
  c.collect_package(name, start);
  c.register_package_alias(name, alias, start);
  List members = c.take_word("with") ? _import_members(c, name) : NULL;
  c.install_compile_time_effects(c.package_effects[name]);
  c.expect(<;>);
  if (c.shallow)
    c.sym.set(
      %("source-node" (package-import
        ${Compiler.portable_path(Path.absolute(c.filename))} ${start.pos})),
      %(package-import $name $alias $members));
  return %(import $name $alias);
}

// Rejects unquoted package names before parsing their identifier.
static String _package_name(Compiler c) {
  if (c.peek(0) != <lit-char*>)
    $report.parse.import_name(c);
  Token name_token = c.token;
  String name = String.new_len(
    c.token.text + 1, c.token.len - 2).unescape();
  if (!name.is_identifier())
    $report.parse.package_identifier(c, name_token);
  c.next();
  return name;
}

static String _import_alias(Compiler c, String name) {
  if (!c.take_word("as")) return name;
  if (c.peek(0) != <ident>)
    $report.parse.alias_name(c);
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
      $report.parse.import_member(c);
    Token member_token = c.token, local_token = member_token;
    String member = c.token.text, local = member;
    c.next();
    if (c.take_word("as")) {
      if (c.peek(0) != <ident>)
        $report.parse.import_local(c);
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
static List _declared(
  Compiler c, List decl, Token meta, Token first) {
  _record_meta_hash(c, decl, first, 0);
  if (meta && decl.type_from_ast().is_function())
    c.install_native_meta_function(decl, meta);
  else if (meta) c.install_meta_declaration(decl, meta);
  c.record_declaration_visibility(decl);
  if (meta)
    _definition_source(c, decl, meta.line, c.definition_doc(meta), NULL);
  else
    match (decl)
      case %(declare ? (bindings (bind (binding ? ?(String name)) *))):
        if (decl.type_from_ast().is_function()) c.meta_comptime.del(name);
  return decl;
}

/* A definition's body follows its declarator. A staged `meta` body parses
   as compile-time code, and a `meta` function that reaches a `Meta`
   operation exists only inside the compiler, with no runtime form. */
static List _defined(
  Compiler c, List decl, Token meta, int native, Token first) {
  match (decl) case %(seq *):
    $report.parse.function_row(c);
  List function;
  Token tokens = c.tokenizer.tokens;
  int start = (meta ? meta : first) - tokens;
  int body = c.token - tokens;
  Token staged = native ? NULL : meta;
  if (staged) _reject_expanded_meta(c, decl, meta);
  if (native) c.install_native_meta_function(decl, meta);
  $let(c.meta_body, staged != NULL) function = _finish_function(c, decl, NULL);
  _record_meta_hash(c, function, first, 0);
  _publish_definition(c, decl, function, meta, staged);
  if (staged && c.capture_unit && c.shallow)
    c.record_project_meta_effect(decl, staged);
  if (!c.capture_unit && staged && c.meta_is_comptime_only(function))
    return NULL;
  if (c.macro_holes)
    return %(api-source ${first.line} ${c.definition_doc(first)} $function);
  _definition_source(c, function, first.line, NULL, %($start $body));
  return function;
}

/* A macro expansion cannot produce a bodied `meta` function: the project
   meta build extracts meta code from source files, not from expansions. */
static void _reject_expanded_meta(Compiler c, List decl, Token meta) {
  if (!c.macro_holes) return;
  String name = "";
  match (decl)
    case %(declare ? (bindings (bind (binding ? ?(String own)) *))):
      name = own;
  $report.parse.meta_constructed(c, name, meta);
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
  foreach (List row, rows) _record_meta_hash(c, row, first, collected_body);
}

static void _record_meta_bindings(
  Compiler c, Var spec, List bindings, Token first, int collected_body) {
  foreach (Var bind, bindings)
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

static void _store_meta_hash(
  Compiler c, String name, Var body, Token first) {
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
  Array pending = $auto([]);
  List rest = %($node);
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
  if (!meta)
    match (function)
      case %(function ? (bind (binding ? ?(String name)) *) ?):
        c.meta_comptime.del(name);
}

/* A generated default that completes a documented `meta` prototype
   publishes the prototype's prose. */
static void _definition_source(
  Compiler c, List function, int line, String doc, List declarator) {
  match (function) {
    case %(function ? (bind ?binding ?) ?):
      c.set_fact(%(api-definition $binding), %($line $doc $declarator));
    case %(declare ? (bindings (bind ?binding ?))):
      if (doc && function.type_from_ast().is_function())
        c.set_fact(
          %(api-definition $binding), %($line $doc $declarator));
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
  List rows = _declaration_rows(c);
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

static List _declaration_rows(Compiler c) {
  Array declarations = [];
  loop {
    declarations.push(_declaration_group(c, 1));
    if (!_group_comma(c)) break;
    c.next();
  }
  return declarations.list_free();
}

/** Parses one declaration group and leaves its terminating token current.
    Declared names are installed in `Sym` as their declarators are completed;
    the result is one `declare`, `typedef`, or initialized `dstrdecl` AST.
*/
List Compiler.parse_simple_declaration(Compiler c) => _declaration_group(c, 0);

/** Parses a declaration that sits inside an expression or a `for` header,
    such as a cast's type name, and returns it as one `(decl ...)` node.
    When `type` is not null, it receives the declared `Type`.
*/
List Compiler.parse_type_operand(Compiler c, Type *type) {
  List declaration = c.parse_simple_declaration();
  if (type) *type = declaration.type_from_ast();
  return %(decl @{declaration.cdr()});
}

static List _declaration_group(Compiler c, int row) {
  List storage = _storage_class(c);
  if (storage === %(typedef)) return _typedef(c, storage, row);
  List (type, binding_type) = _declaration_types(c, storage);
  if (_destructure_starts(c))
    return _destructure_declaration(c, type, binding_type, 0);
  List bindings = _declarator_list(c, binding_type, NULL, row);
  return _finish_declaration(c, <declare>, type, bindings, 0);
}

static List _typedef(Compiler c, List context, int row) {
  Token first = c.token;
  // An imported `typedef const char *(*fn)(int)` names a qualified type
  // like an object declaration does, so read the qualifiers first.
  List quals = _type_qualifiers(c);
  List spec = quals.append(_type_specifier(c));
  spec = c.sym.local_type(spec);
  List bindings = _declarator_list(c, spec, context, row);
  /* A typedef's own alignment changes every record field that names it,
     even when the record declaration has no attribute of its own. */
  if (_layout_attribute_since(c, first))
    foreach (List declarator, bindings) {
      String name = Ast.binding_spelling(declarator.cadr());
      if (name) c.sym.set(%($name "layout-attribute"), %(unknown));
    }
  return _finish_declaration(c, <typedef>, spec, bindings, 0);
}

/* Reads the qualifiers, the type specifier, and any storage macro after it,
   `int LOCAL f(void)`, and returns the declared type and the type its names
   are bound to. Source specifier text, such as `("_Noreturn")`, is written
   with the declaration but is no part of the bound type. An aggregate binds
   its short tag; the declared type keeps the body. */
static List _declaration_types(Compiler c, List storage) {
  List quals = _type_qualifiers(c);
  Type spec = _type_specifier(c);
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
    if (!_prefix_macro_words(c, 0, trailing)) break;
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

/** Parses one non-function, non-typedef `Decl` macro argument.
    Returns a single declaration without consuming the invocation delimiter;
    flat destructuring may omit an initializer in this position.
*/
List Compiler.parse_declaration_argument(Compiler c) {
  List storage = _storage_class(c);
  if (storage === %(typedef))
    $report.parse.decl_typedef(c);
  List (type, binding_type) = _declaration_types(c, storage);
  if (_destructure_starts(c))
    return _destructure_declaration(c, type, binding_type, 1);
  List binding = _declarator_init(c, binding_type, NULL);
  List declaration = _finish_declaration(c, <declare>, type, %($binding), 0);
  if (declaration.type_from_ast().is_function())
    $report.parse.decl_function(c);
  return declaration;
}

/** Reports whether the current identifier starts a C static assertion. */
int Compiler.test_static_assert(Compiler c) =>
  c.at_word("_Static_assert");

/** Parses a C assertion declaration; native C owns constant-expression
    checks. */
List Compiler.parse_static_assert(Compiler c) {
  if (c.shallow) {
    _x2c_skip_shallow_expression(c, 0);
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
int Compiler.test_declaration(Compiler c) => _test_declaration_start(c, 0);

static int _test_declaration_start(
  Compiler c, int require_declarator) {
  Symbol sym = c.peek(0);
  if (c.macro_holes && sym == <"$(">)
    return c.macro_lisp_starts_declaration();
  if (c.macro_holes && sym == <$>) return _hole_starts(c);
  if (sym.is_storage_class() || sym.is_type_qualifier() ||
      sym.is_builtin_type() || sym == <inline>) return 1;
  if (sym != <ident>) return 0;
  // A leading attribute belongs to a declaration in every position.
  if (c.token.text == "__attribute__" && _attribute_starts(c)) return 1;
  /* A prefix macro contributes declaration specifiers, so `LOCAL int x = 1;`
     is a declaration wherever it is written. */
  Var definition;
  if (c.object_macros.try_get(c.token.text, definition) &&
      (definition is <list> || definition == <wrapper>))
    return 1;
  return _type_name_starts(c, require_declarator);
}

/* A type hole starts a declaration, and so does a hole of no declared kind
   that a name follows. */
static int _hole_starts(Compiler c) {
  List hole = c.peek_macro_hole();
  if (!hole) return c.macro_lisp_starts_declaration();
  Symbol kind = hole.assoc(<kind>);
  if (kind) return kind == <type>;
  Symbol next = c.after_hole().type;
  return next == <ident> || next == <$> || next == <@> ||
         next == <"$("> || next == <"@(">;
}

/* An identifier that names no object starts a declaration when the token
   after it, or after a package alias's member, can follow a type name. */
static int _type_name_starts(Compiler c, int require_declarator) {
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
  int attribute = _attribute_starts(c);
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
static int _group_comma(Compiler c) {
  if (c.peek(0) != <,>) return 0;
  Token comma = c.token;
  c.next();
  int result = _test_declaration_start(c, 1);
  c.token = comma;
  return result;
}

// destructuring declarations

/* Distinguish '(ident, ...)' from an ordinary parenthesized declarator and
   from the parameters of a type name such as `Var (Var, Var)`. */
static int _destructure_starts(Compiler c) {
  Token token = c.token;
  if (token.type != <(>) return 0;
  token = Token.skip_trivia(token + 1);
  if (token.type != <ident>) return 0;
  token = Token.skip_trivia(token + 1);
  return token.type == <,> && !_parameters_follow(c);
}

static List _destructure_declaration(
  Compiler c, List type, List binding_type, int allow_uninitialized) {
  c.check_reference_placement(binding_type);
  Token origin_token = c.token;
  List bindings = _destructure_targets(c, binding_type);
  /* A foreach destructures each element rather than an initializer, so the
     same `(a, b)` spelling stands without `=`. It reduces to the
     multi-binding declaration a `for` header already knows how to
     carry across `in`. */
  if (allow_uninitialized || c.peek(0) == <in>)
    return %(declare $type (bindings @{_destructure_binds(bindings)}));
  if (!c.test(<=>))
    $report.parse.destructure_init(c);
  List source = c.parse_assignment();
  List result = %(dstrdecl $type (targets @bindings) $source);
  return c.anchor_origin(result, origin_token);
}

// ( ident, ident, ... ), each declared with the destructured type.
static List _destructure_targets(Compiler c, List binding_type) {
  Array targets = [];
  c.expect(<(>);
  loop {
    if (c.peek(0) != <ident>)
      $report.parse.destructure_name(c);
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

/** Rejects transparent references in object and function-result types.
    References inside a function's parameter list remain supported. */
void Compiler.check_reference_placement(Compiler c, Type type) {
  type = c.sym.normalize_declared_type(type);
  if (<&> in type || <opt-ref> in type)
    $report.type.reference_placement(c);
}

/* A file-scope function declared again with `extern` or no storage keeps the
   internal linkage of its earlier `static` declaration, as in C, so the
   declaration emits `static`. An object so declared has external linkage
   and conflicts, which C reports. */
static List _linked_static_base(Compiler c, List base, List declarators) {
  Type type = base;
  if (!c.sym.at_file_scope() || type.is_static() ||
      !declarators)
    return base;
  foreach (List declarator, declarators) {
    Type declared = %(declare $base (bindings $declarator)).type_from_ast();
    List bound = declarator;
    match (declarator) case %(op = ?target ?): bound = target;
    if (!declared.is_function() || !c.sym.is_file_static(bound.cadr()))
      return base;
  }
  return %(static @{base.filter(%!(item) => item != <extern>)});
}

static List _finish_declaration(
  Compiler c, Symbol tag, List base, List declarators,
  int preserved_self) {
  if (tag == <typedef> && c.source_private > 0 &&
      !base.type().is_static()) base = %(static @base);
  if (tag == <declare>) base = _linked_static_base(c, base, declarators);
  List modifiers = NULL;
  base = Type.declaration_base(base, modifiers);
  if (modifiers) {
    Array bound = [];
    foreach (List declarator, declarators)
      bound.push(Ast.append_modifiers(declarator, modifiers));
    declarators = bound.list_free();
  }
  if (tag == <declare> || tag == <decl>)
    foreach (List declarator, declarators) {
      Type type = %(declare $base (bindings $declarator)).type_from_ast();
      c.check_reference_placement(type);
    }
  List declaration = %($tag $base (bindings @declarators));
  return tag == <declare> && !preserved_self
    ? _lower_self_declaration(c, declaration)
    : declaration;
}

/* Keep Self only in method metadata. The binding and AST receive the
   declaring owner, so direct calls and generated C retain the existing
   function signature. */
static List _lower_self_declaration(Compiler c, List declaration) {
  List binding = NULL;
  match (declaration) {
    case %(? ? (bindings (op = (? ?name *) ?))): binding = name;
    case %(? ? (bindings (? ?name *))): binding = name;
  }
  if (!binding) return declaration;
  List method = c.fact(%(method $binding));
  if (!method) return declaration;
  Type owner = _self_owner_type(c, method);
  if (!owner) return declaration;
  List lowered = declaration.search_replace(<self>, owner.car());
  if (lowered == declaration) {
    c.drop_fact(%(self $binding));
    return declaration;
  }
  Type signature = declaration.type_from_ast();
  if (!signature.is_function()) return declaration;
  String spelling = Ast.binding_spelling(binding);
  Type relative = signature.declared();
  Type concrete = lowered.type_from_ast().declared();
  c.set_fact(%(self $binding), relative);
  c.sym.set(%($spelling), concrete);
  c.sym.set(%(self $spelling), relative);
  _lower_parameter_self(c, owner.car());
  return lowered;
}

static Type _self_owner_type(Compiler c, List method) {
  String source = method.car();
  Type declared = c.sym.get(%($source));
  if (declared.is_typedef())
    return %(${_type_reference(c, 0, source)});
  Symbol builtin = Atom.intern(source);
  return builtin.is_builtin_type() ? %($builtin) : NULL;
}

static void _lower_parameter_self(Compiler c, Var replacement) {
  Map symbols = c.params.symbols;
  if (!symbols) return;
  foreach (Var (key, value), symbols) {
    List original = value;
    List lowered = original.search_replace(<self>, replacement);
    if (lowered != original) {
      c.sym.put(symbols, key, lowered);
      Var binding;
      if (c.params.bindings.try_get(key, binding))
        c.set_fact(%(type $binding), lowered);
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
static List _storage_class(Compiler c) {
  Array storage = [], text = [], int seen_threaded = 0, seen_ordinary = 0;
  defer { storage.free(); text.free(); }
  loop {
    Symbol symbol = c.peek(0);
    String attribute = _attribute(c);
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
    else if (!_prefix_macro_words(c, 0, storage)) break;
  }
  return %( @{storage.list()} @{text.list()} );
}

static String _attribute(Compiler c) {
  if (!_attribute_starts(c)) return NULL;
  Token first = c.token, last = Token.skip_trivia(first + 1).group_close();
  c.token = last.after_group();
  return String.new_len(c.text + first.pos, last.pos + last.len - first.pos);
}

/* A GNU attribute or an attribute macro is kept as its source text. */
static int _attribute_starts(Compiler c) {
  Var definition;
  return c.peek(0) == <ident> && c.peek(1) == <(> &&
         (c.token.text == "__attribute__" ||
          (c.object_macros.try_get(c.token.text, definition) &&
           definition == <annotation>));
}

/* Source is read before preprocessing, so a macro whose body is declaration
   specifiers and attributes, such as an export annotation, still sits in a
   declaration. A specifier position of `rank`, 0 for storage classes and
   `inline`, 1 for qualifiers, and 2 for builtin types, leaves a macro with
   words of a later rank to that position; otherwise it consumes the macro
   and takes all of its words into `words`, so `int LOCAL f(void)` keeps the
   `static` of `#define LOCAL static`. */
static int _prefix_macro_words(Compiler c, int rank, Array words) {
  Var definition;
  if (c.peek(0) != <ident>) return 0;
  if (!c.object_macros.try_get(c.token.text, definition)) {
    if (rank || !_unseen_prefix(c)) return 0;
    c.next();
    return 1;
  }
  if (definition == <wrapper> && c.peek(1) == <(>) {
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
static int _unseen_prefix(Compiler c) {
  Symbol next = c.peek(1);
  return c.shallow && c.filename.endswith(".h") &&
         (next.is_builtin_type() || next.is_type_modifier() ||
          next.is_type_qualifier() || next.is_storage_class() ||
          next.is_inline());
}

static List _type_qualifiers(Compiler c) {
  Array quals = $auto([]);
  loop {
    _x2c_complete_here(c, <type>, _type_keywords());
    Symbol symbol = c.peek(0);
    if (symbol.is_type_qualifier()) {
      quals.push(symbol);
      c.next();
    }
    else if (!_prefix_macro_words(c, 1, quals)) break;
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
  List qualifiers = _type_qualifiers(c);
  List specifier = _type_specifier(c);
  List pointers = _pointer(c);
  Type type = %( @pointers @qualifiers @specifier );
  return c.sym.local_type(type);
}

static List _type_specifier(Compiler c) {
  c.require_input();
  List slot = c.try_parse_macro_slot(<type>);
  if (slot) return %($slot);
  List syntax = NULL;
  switch (c.peek(0)) {
    case <struct>: case <union>: case <enum>:
      syntax = _tagged_type(c); break;
    case <ident>:
      if (c.token.text == "Self") {
        c.next();
        syntax = %(self);
        break;
      }
      Array words = [];
      _prefix_macro_words(c, 2, words);
      syntax = words.list_free();
      if (!syntax) syntax = _typedef_name(c);
      break;
    default:
      syntax = _primitive_type(c);
  }
  return syntax;
}

static List _primitive_type(Compiler c) {
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
  $report.type.scalar_invalid(c, source, start);
}

static int _is_scalar_specifier(Symbol symbol) {
  switch (symbol)
    case <signed>: case <unsigned>: case <short>: case <long>:
    case <char>: case <int>: case <float>: case <double>: case <void>:
      return 1;
  return 0;
}

static List _typedef_name(Compiler c) {
  String name = _package_alias_member(c);
  if (!name) name = c.package_member_spelling(c.token.text);
  if (!name) name = c.token.text;
  c.next();
  if (c.package || c.line_markers) name = _type_reference(c, 0, name);
  return %($name);
}

/* Module and package files spell their own file-scope type names bare. A
   block-scope typedef or tag of the name shadows every file-scope one;
   then the current module file's static of that name comes first. In
   package mode a bare-key miss with a prefixed hit re-spells the
   reference. ASTs carry raw strings and emit literally. */
static String _type_reference(Compiler c, Symbol tag, String name) {
  List bare = tag ? %($tag $name) : %($name);
  if (c.sym.has_local(bare)) return name;
  String own = c.scoped_spelling(c.file_prefix(), name);
  if (own != name && c.sym.get_exact(tag ? %($tag $own) : %($own)))
    return own;
  String prefixed = c.package_spelling(name);
  if (prefixed == name) return name;
  if (c.sym.get_exact(bare)) return name;
  List hit = tag ? %($tag $prefixed) : %($prefixed);
  return c.sym.get_exact(hit) ? prefixed : name;
}

// aggregates

static List _tagged_type(Compiler c) {
  Token first = c.token;
  Symbol tag = c.peek(0);
  c.next();
  _skip_attributes(c);
  List name = _tag_name(c);
  if (name && (c.package || c.line_markers))
    name = _scoped_aggregate_name(c, tag, name);
  int defines = c.peek(0) == <"{"> ||
    (c.peek(0) == <;> && (tag != <enum> || c.macro_holes));
  Var used = c.aggregate_name(tag, (name ? name : c.gensym()).car(), defines);
  List type = %($tag $used), members = NULL;
  if (c.test(<"{">)) {
    members = tag == <enum> ? c.parse_enumerators(type) : c.parse_fields(type);
    c.expect(<"}">);
    _skip_attributes(c);
    if (!c.macro_holes)
      return _publish_aggregate_type(c, tag, used, members, first);
    if (tag != <enum>) members = cons(<fields>, members);
  }
  return members ? type.append(%($members)) : type;
}

/* C places an aggregate's own attributes after its keyword and after its
   closing brace, written out or through a macro whose body is attributes.
   Collection skips them: attribute text is no part of a collected type, and
   the layout marks hold any layout they change (see Compiler.tokenize). */
static void _skip_attributes(Compiler c) {
  if (!c.shallow) return;
  loop {
    Var definition;
    if (_attribute(c)) continue;
    if (c.peek(0) != <ident> ||
        !c.object_macros.try_get(c.token.text, definition) ||
        definition != %())
      return;
    c.next();
  }
}

/* A template may spell a tag through a Name hole or compile-time Lisp,
   which publishes it; a literal tag there is a template local. */
static List _tag_name(Compiler c) {
  List slot = c.try_parse_macro_slot(<name>);
  return slot ? %($slot) : c.parse_optional_identifier();
}

/* An aggregate definition takes the prefix its declaration key carries, so
   the tag, its member keys, and the pointee spellings recorded for it agree
   in the shallow collection an importing unit reads and in the full parse. */
static List _scoped_aggregate_name(Compiler c, Symbol tag, List name) {
  // A template's tag slot supplies its exact spelling where it expands.
  if (name.car() is not <string>) return name;
  String spelling = name.car();
  if (c.peek(0) == <"{">)
    return %(${c.declared_spelling(c.private_prefix(NULL), spelling)});
  return %(${_type_reference(c, tag, spelling)});
}

/* Publishes an aggregate whose tokens start at `first`. A constructed
   aggregate passes the current token, so its attributes are in its form. An
   enum with a layout attribute can be narrower than int, so it has no int
   layout. */
static List _publish_aggregate_type(
  Compiler c, Symbol tag, Var name, List members, Token first) {
  int layout = _layout_attribute_since(c, first);
  int packed = _attribute_since(c, first, c.packed_marks);
  if (tag == <struct> && packed && c.source_private >= 0)
    $report.parse.attribute_packed(c, first);
  List type = %($tag $name);
  List body = tag == <enum> ? members : %(fields @members);
  if (name is <list> && name.car() == <binding>)
    c.sym.bind_identity(%($tag), name, %($tag $body));
  else
    c.sym.declare_resolved(
      NULL, type, tag == <enum> ? %(enum) : %($tag $body));
  if (tag != <enum>) {
    c.sym.declare_field_order(type, members);
    if (layout) c.sym.set(%(@type "layout-attribute"), %(unknown));
    // Meta code lays out only the records x2c units define.
    if (c.source_private >= 0 && !c.filename.endswith(".h"))
      c.sym.set(%(@type "x2c-record"), %(x2c));
  }
  else {
    c.sym.set(%(@type "enumerators"), %(@type $members).type_from_ast());
    if (!layout && _enum_fits_int(type, members)) {
      c.sym.set(%(@type "int-range"), %(int));
      _record_enum_values(c, members);
    }
  }
  return %($tag $name $body);
}

static int _layout_attribute_since(Compiler c, Token first) =>
  _attribute_since(c, first, c.layout_marks);

/* Reports a layout attribute between `first` and the current token. Tokens
   outside this unit's input, such as a constructed form's, have no marks. */
static int _attribute_since(Compiler c, Token first, Array marks) {
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
      ? _field(c, context, 1) : c.parse_field(context);
    _push_items(fields, field);
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
  List macro = _member_macro(c, context, <field>);
  if (macro) return macro;
  return _field(c, context, 0);
}

/* A macro invocation may stand for an aggregate member. It expands with
   the aggregate as the current aggregate type. */
static List _member_macro(Compiler c, List context, Symbol position) {
  if (c.peek(0) != <$> && c.peek(0) != <ident>) return NULL;
  $let(c.aggregate_type, context)
    return c.try_parse_macro_target_at(position);
}

static List _field(Compiler c, List context, int delegated) {
  List rows = _field_row(c, context);
  if (delegated) _declare_delegates(c, context, rows);
  c.expect(<;>);
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

// Each declarator of a delegate field must name the field.
static void _declare_delegates(Compiler c, List context, List rows) {
  foreach (List declaration, rows)
    match (declaration)
      case %(declare ? (bindings *declarators)): {
        if (!declarators)
          $report.parse.delegate_name(c);
        foreach (List declarator, declarators)
          match (declarator)
            case %(bind ?binding ?): _declare_delegate(c, context, binding);
      }
}

static void _declare_delegate(Compiler c, List context, Var binding) {
  String name = Ast.binding_spelling(binding);
  if (!name)
    $report.parse.delegate_name(c);
  if (!c.macro_holes) c.sym.mark_field(context, <delegate>, name);
}

static List _field_row(Compiler c, List context) {
  Array declarations = [];
  loop {
    declarations.push(_field_group(c, context));
    if (!_group_comma(c)) break;
    c.next();
  }
  return declarations.list_free();
}

static List _field_group(Compiler c, List context) {
  List storage = _storage_class(c);
  List (type, binding_type) = _declaration_types(c, storage);
  List binds = _declarator_list(c, binding_type, context, 1);
  return _finish_declaration(c, <declare>, type, binds, 0);
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
  String name = c.declared_spelling(c.private_prefix(NULL), c.token.text);
  c.expect(<ident>);
  List key = %($name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (c.test(<;>)) return %(named-type $name ());
  List qualifiers = _type_qualifiers(c);
  List base = qualifiers.append(
    _record_follows(c) ? _record_body(c, name, start) : _type_specifier(c));
  Type type = _declare_named_type(c, key, base, start);
  return %(named-type $name $type);
}

/* A named type may define its record in place, with or without `struct`
   or `union` before the brace. */
static int _record_follows(Compiler c) =>
  c.peek(0) == <"{"> ||
  ((c.peek(0) == <struct> || c.peek(0) == <union>) && c.peek(1) == <"{">);

static List _record_body(Compiler c, String name, Token start) {
  Symbol tag = c.peek(0) == <union> ? <union> : <struct>;
  if (c.peek(0) != <"{">) c.next();
  c.expect(<"{">);
  List fields = c.peek(0) == <"}">
              ? NULL : c.parse_fields(%($tag $name));
  c.expect(<"}">);
  return c.macro_holes ? %($tag $name (fields @fields))
                       : _publish_aggregate_type(c, tag, name, fields, start);
}

/* Completes a named type from the abstract declarator after its base. The
   type keeps an aggregate's body in place of its tag. */
static Type _declare_named_type(
  Compiler c, List key, List base, Token start) {
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = _declarator(c, base, NULL, method, first, after);
  List modifiers = NULL;
  match (declarator) {
    case %(bind () ?captured): modifiers = captured;
    default: $report.parse.named_type_abstract(c, start);
  }
  c.expect(<;>);
  Type type = %(declare $base (bindings (bind () $modifiers)))
                .type_from_ast();
  if (!c.macro_holes) c.sym.declare_resolved(%(typedef), key, type);
  Type specifier = base.type().base_type();
  if (specifier.is_aggregate_tag_body())
    type = type.list()[:type.len() - type.base_type().len()]
      .append(specifier);
  return type;
}

// enumerations

/** Parses comma-separated enumerators up to the current closing brace.
    Returns their flat source-order `List` and leaves the brace unconsumed.
*/
List Compiler.parse_enumerators(Compiler c, List context) {
  Array enumerators = [];
  while (c.peek(0) != <"}">) {
    if (c.shallow && c.macro_starts_target_at(<enumerator>))
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

/** Parses one enumerator for enum type `context` and returns its AST.
    Outside macro-template parsing, its binding is published immediately so
    later initializers and enumerators can resolve it.
*/
List Compiler.parse_enumerator(Compiler c, Type context) {
  List slot = c.try_parse_macro_slot(<enumerator>);
  if (slot) return slot;
  List macro = _member_macro(c, context, <enumerator>);
  if (macro) return macro;
  if (c.macro_holes) return _template_enumerator(c, context);
  if (c.peek(0) != <ident>)
    $report.parse.enum_name(c);
  String spelling = c.token.text;
  Token origin = c.token;
  c.next();
  List binding = %($spelling), syntax = binding;
  if (c.test(<=>)) {
    List value = c.parse_conditional();
    syntax = %(op = $binding $value);
  }
  return _publish_enumerator(c, syntax, context, origin);
}

/* A template's enumerator is named by a hole, a Lisp slot, or a name each
   expansion introduces. */
static List _template_enumerator(Compiler c, Type context) {
  List name = _enumerator_name(c, context);
  List target = %(bind $name ());
  if (c.test(<=>)) return %(op = $target ${c.parse_conditional()});
  return target;
}

static List _enumerator_name(Compiler c, Type context) {
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
      $report.parse.enum_name(c);
  }
}

static List _publish_enumerator(
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
  String spelling = exact ? exact : Ast.binding_spelling(binding);
  if (!spelling)
    $report.parse.syntax_position(c, origin);
  List key = %($spelling);
  if (exact) key = c.sym.declared_key(NULL, key, context);
  Symbol prior = c.sym.enumerator_owner(key);
  if (prior && binding) {
    List existing = c.sym.lookup(key, NULL);
    if (existing && existing == binding) return input;
  }
  if (prior)
    $report.parse.enum_bound(c, spelling, origin);
  if (exact) binding = c.sym.declare(NULL, %($exact), context);
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
  if (value == type) return 1;
  X2CVarNumericInfo info;
  return Var.numeric_info(value.scalar_tag(), info) && !info.floating &&
         (info.bits < 32 || (info.bits == 32 && !info.unsigned_value));
}

/* Records how meta code computes each enumerator's value: its initializer,
   or the previous enumerator plus one, or zero for the first. */
static void _record_enum_values(Compiler c, List members) {
  List rule = %(first);
  foreach (List member, members) {
    List binding = member;
    match (member) case %(op = ?target ?value): {
      binding = target;
      rule = %(value $value);
    }
    c.set_fact(%(enum-value $binding), rule);
    rule = %(next $binding);
  }
}

// declarators

static List _declarator_list(
  Compiler c, List type, List context, int row) {
  Array bindings = $auto([]);
  loop {
    bindings.push(_declarator_init(c, type, context));
    if ((row && _group_comma(c)) ||
        !c.test(<,>))
      return bindings;
  }
}

/* Install each declaration binding before resolving its initializer so later
   declarators and source-order dependency analysis share the same identity. */
static List _declarator_init(
  Compiler c, List type, List context) {
  // A Lisp-produced declarator name still needs ordinary binding.
  List slot = c.peek_macro_hole() || c.peek(0) == <@> || c.peek(0) == <"@(">
    ? c.try_parse_macro_slot(<decl-row>) : NULL;
  if (slot) {
    if (c.test(<=>)) return %(op = $slot ${c.parse_assignment()});
    return slot;
  }
  Token origin = c.token;
  List method = NULL;
  Token first = NULL, after = NULL;
  List bind = _declarator(c, type, context, method, first, after);
  int preserved_self = 0;
  bind = _install_declarator(c, type, context, bind, method, preserved_self);
  c.record_source_declaration(bind.cadr(), first, after);
  int function_arrow = !c.in_proto && _x2c_at_function_arrow(c) &&
    %(declare $type (bindings $bind)).type_from_ast().is_function();
  if (!c.in_proto && !function_arrow && c.test(<=>))
    return _initialized(c, type, bind, origin);
  return bind;
}

/* Collection skips an initializer. `init_tokens` records the declarator's
   first token, not the token where expression parsing finishes. */
static List _initialized(
  Compiler c, List type, List bind, Token origin) {
  List binding = bind.cadr();
  if (Ast.try_binding(binding, NULL, NULL)) {
    Token tokens = c.tokenizer.tokens;
    c.init_tokens[binding] = origin - tokens;
  }
  if (c.shallow && !c.capture_unit) {
    _x2c_skip_shallow_expression(c, 1);
    return bind;
  }
  c.enter((Ancestor){ .what = <declarator>, .base = type, .node = bind });
  List init = c.parse_assignment();
  c.ancestors.pop();
  c.check_explicit_converter(
    init, %(declare $type (bindings $bind)).type_from_ast(), 0);
  return %( op = $bind $init );
}

static List _declarator(
  Compiler c, List type, List context, List &method_identity_out,
  Token &source_first, Token &source_after) {
  List ptr = _pointer(c), method_identity = NULL;
  List (key, infix) =
    _direct_declarator(
      c, context, method_identity, source_first,
      source_after).cdr();
  List sfx = _declarator_suffix(
    c, c.load_source && !c.return_type && key == %("main"));
  List modifiers = %( @infix @sfx @ptr );
  List ast = modifiers.append(type);
  // A parenthesized declarator is assembled twice. Preserve its raw key until
  // the outer call has the base type and can establish the binding once.
  List binding = key;
  c.bind_template_local(key, ast, context);
  method_identity_out = method_identity;
  return %( bind $binding $modifiers );
}

static List _pointer(Compiler c) {
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
    if (c.peek(0) != <ident> || !(c.token.text in c.object_macros))
      return ptr;
    Array quals = $auto([]);
    if (!_prefix_macro_words(c, 1, quals)) return ptr;
    foreach (Var qualifier, quals) ptr = cons(qualifier, ptr);
  }
}

static List _direct_declarator(
  Compiler c, Type context, List &method_identity, Token &source_first,
  Token &source_after) {
  // A member keeps its spelling in a template: C scopes it to its aggregate.
  int member = context.is_aggregate();
  if (c.peek(0) == <(> && _parameters_follow(c)) return %(bind () ());
  if (c.peek(0) == <(>)
    return _parenthesized(
      c, member ? context : NULL, method_identity, source_first,
      source_after);
  if (c.macro_holes) {
    List bind = _template_declarator(c, member);
    if (bind) return bind;
  }
  if (!c.token.text.is_identifier()) return %(bind () ());
  // Identifier or typedef name or method-sugar target
  Token first = c.token;
  List ident = _complex_identifier(c, method_identity);
  source_first = first;
  source_after = c.token;
  return %(bind $ident ());
}

/* Whether the `(` at the cursor opens the parameters of a declarator with
   no name, as in the type name `int (int)`: a `)`, or a type that is no
   name to declare, follows it. As in C, a typedef name there is a type. */
static int _parameters_follow(Compiler c) {
  Token head = c.token;
  c.next();
  Symbol next = c.peek(0);
  Type lookup = c.sym.get(%(${c.token.text}));
  int named = next == <ident> && !lookup.is_typedef() &&
              !(c.signature_only && c.test_declaration());
  int parameters = next == <)> || (!named && c.test_declaration());
  c.token = head;
  return parameters;
}

// Carries the source span across a nested declarator.
static List _parenthesized(
  Compiler c, List context, List &method_identity, Token &source_first,
  Token &source_after) {
  c.next();
  Token first = c.token;
  List decl = _declarator(
    c, NULL, context, method_identity, source_first, source_after);
  if (c.peek(0) != <)>) {
    c.require_input();
    /* One identifier followed by another is a parameter list whose type
       this unit cannot see, such as a package type named without its
       import alias, not a parenthesized declarator. */
    if (first.type == <ident> && c.peek(0) == <ident>)
      $report.parse.type_unknown(c, first);
    else
      $report.parse.paren_unclosed(c);
  }
  c.next();
  return decl;
}

static List _declarator_suffix(Compiler c, int loaded_main) {
  List type = NULL;
  loop {
    // An attribute after a declarator modifies that declarator alone.
    String attribute = _attribute(c);
    if (attribute)
      type = %( @type ($attribute) );
    else if (c.peek(0) == <[>)
      type = %( @type  @{_array_suffix(c)} );
    else if (c.peek(0) == <:>) {
      c.next();
      List expr = c.parse_primary();
      type = %( @type (bitfield $expr) );
    }
    else if (c.peek(0) == <(>) {
      List params = _function_parameters(c, loaded_main);
      params = %( params @params );
      type = type ? %(fnmod $params $type) : %((fnmod $params));
    }
    else break;
  }
  return type;
}

static List _array_suffix(Compiler c) {
  c.next();
  if (c.peek(0) == <]>) {
    c.next();
    return %((dim));
  }
  List expr = c.parse_expression();
  if (c.peek(0) != <]>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    $report.parse.dimension_close(c, expr, unexpected);
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
  List bind = _declarator(c, NULL, NULL, method, first, after);
  if (c.test(<=>)) return %(op = $bind ${c.parse_assignment()});
  return bind;
}

/* template declarators

   In a macro template a declarator may name its binding through a Lisp
   slot, a Name hole, a member hole, or a name each expansion introduces. A
   method's owner may be a literal type or a type hole. */

// Returns NULL for another token, which takes the ordinary identifier path.
static List _template_declarator(Compiler c, int member) {
  List method = _literal_method(c);
  if (!method) method = _hole_method(c);
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

// `Type.member`, where the member may be a Name hole.
static List _literal_method(Compiler c) {
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
  return %(bind (($owner_spelling) ${_method_member(c)}) ());
}

// `$T.member`, where `$T` is a type hole.
static List _hole_method(Compiler c) {
  List owner_hole = c.peek_macro_hole();
  if (!owner_hole || owner_hole.assoc(<kind>) != <type> ||
      c.after_hole().type != <.>)
    return NULL;
  List owner = c.try_parse_macro_slot(<type>);
  return %(bind (($owner) ${_method_member(c)}) ());
}

// The member after a method owner's `.`: a Name hole or an identifier.
static Var _method_member(Compiler c) {
  c.expect(<.>);
  if (c.peek(0) == <$>) return c.try_parse_macro_slot(<name>);
  if (!c.token.text.is_identifier()) $report.parse.macro_member(c);
  String member = c.token.text;
  c.next();
  return member;
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
   scope, records the method it declares, and resolves its initializer
   outside collection. */

static List _install_declarator(
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
  name = _declared_name(c, name, exact_name);
  List declaration = %(declare $base (bindings (bind () $mods)));
  List prior = name is <list> ? name : NULL;
  List method = method_identity ? method_identity
              : prior ? c.fact(%(method $prior)) : NULL;
  List self_signature = prior ? c.fact(%(self $prior)) : NULL;
  Type declared_type = mods.append(base);
  name = _method_spelling(c, name, declared_type, method, exact_name);
  String exact = _syntax_exact_name(name);
  _check_rebinding(c, exact, exact_name, declaration);
  List binding = exact ? c.sym.declare(context, %($exact), declared_type)
               : name is <list> ? name.list() : NULL;
  if (binding && !exact) _bind_identity(c, context, binding, declaration);
  if (binding)
    _method_facts(c, binding, method, self_signature, preserved_self);
  if (binding && method && c.token && !declared_type.is_static()) {
    String path = Compiler.portable_path(Path.absolute(c.filename));
    String owner = c.package_spelling(method.car());
    c.sym.set(
      %("source-node" (interface-types $path ${c.token.pos} $exact)),
      %(interface-types $exact (($owner))));
  }
  List bound = %(bind $binding $mods);
  if (initializer && !c.shallow) {
    c.enter((Ancestor){ .what = <declarator>, .base = base, .node = bound });
    initializer = c.resolve_expression(initializer, c.token);
    c.ancestors.pop();
  }
  return initializer ? %(op = $bound $initializer) : bound;
}

// A name after its macro slot; `("x2c.ident" NAME)` is an exact spelling.
static Var _declared_name(Compiler c, Var name, int &exact_name) {
  name = c.evaluate_macro_slot(name);
  match (name)
    case %("x2c.ident" ?(String exact)):
      name = exact, exact_name = 1;
  return name;
}

/* Folds a literal owner and its member into the C spelling and records
   the method. A constructed source owner is no concrete owner, so only a
   static method declares its member as an exact spelling. */
static Var _method_spelling(
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
      else $report.type.method_owner(c);
    case %((!is ? type list) (!is ? type string)):
      $report.type.method_owner(c);
  }
  return name;
}

/* An exact spelling, or a name a parameter holds, may be declared again only
   as another prototype of a function. */
static void _check_rebinding(
  Compiler c, String exact, int exact_name, List declaration) {
  List existing = exact ? c.sym.current_binding(%($exact)) : NULL;
  if (exact_name || (existing &&
      %(parameter $existing) in c.semantic_binding_facts())) {
    Var prior = existing
              ? c.sym.current_symbols()[%($exact)] : void;
    if (prior is <list>) {
      Type prior_type = prior;
      Type candidate = declaration.type_from_ast();
      if (!candidate.is_function() || !prior_type.is_function())
        $report.parse.decl_bound(c, exact);
    }
  }
}

// Binds a constructed identity unless it is already its spelling's binding.
static void _bind_identity(
  Compiler c, List context, List binding, List declaration) {
  String spelling = Ast.binding_spelling(binding);
  List visible = c.sym.lookup(%($spelling), NULL);
  if (visible != binding) c.sym.bind_identity(context, binding, declaration);
}

/* Records the method a binding declares, or drops a stale one, and keeps
   the Self signature an earlier declaration recorded. */
static void _method_facts(
  Compiler c, List binding, List method, List self, int &preserved_self) {
  if (method) c.set_fact(%(method $binding), method);
  else c.drop_fact(%(method $binding));
  if (!self) return;
  c.set_fact(%(self $binding), self);
  preserved_self = 1;
}

// parameters

/* Parameter declarations bind into a temporary scope. The declarator cannot
   yet know whether a body follows, so keep that scope in `params`; finishing
   a definition replays it around the body, while a prototype never pushes
   the captured scope. */
static List _function_parameters(Compiler c, int loaded_main) {
  c.next();
  _x2c_complete_here(c, <type>, _type_keywords());
  if (c.peek(0) == <)> && !loaded_main)
    $report.parse.params_empty(c);
  SymScope saved = c.params, parsed;
  int complete = 0;
  defer { if (!complete) c.params = saved; }
  List params;
  c.sym.push_new_scope();
  {
    defer parsed = c.sym.pop_scope();
    params = c.peek(0) == <)> ? %((param (void) (bind () ())))
                            : c.parse_parameter_list();
  }
  if (c.peek(0) != <)>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    $report.parse.params_close(c, params, unexpected);
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
    _x2c_complete_here(c, <type>, _type_keywords());
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
  List qual = _type_qualifiers(c);
  List spec = _type_specifier(c), type = %( @qual @spec );
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = _declarator(c, type, NULL, method, first, after);
  return _finish_parameter(c, type, declarator, method, first, after);
}

/** Binds one constructed parameter in the current scope, including nested
    function modifiers and reference parameter facts. */
List Compiler.bind_parameter(Compiler c, List base, List declarator) =>
  _finish_parameter(c, base, _finish_fnmods(c, declarator), NULL, NULL, NULL);

static List _finish_parameter(
  Compiler c, List base, List declarator, List method_identity,
  Token source_first, Token source_after) {
  base = _finish_type(c, base);
  int preserved_self = 0;
  declarator = _install_declarator(
    c, base, NULL, declarator,
    method_identity, preserved_self);
  c.record_source_declaration(declarator.cadr(), source_first, source_after);
  List modifiers = NULL;
  base = Type.declaration_base(base, modifiers);
  declarator = Ast.append_modifiers(declarator, modifiers);
  List parameter = %(param $base $declarator);
  match (declarator)
    case %(bind ?binding ?):
      if (!c.macro_holes) _parameter_facts(c, binding, parameter);
  return parameter;
}

// Records a parameter binding and whether it is a reference, or optional.
static void _parameter_facts(
  Compiler c, Var binding, List parameter) {
  if (binding) c.set_fact(%(parameter $binding), 1);
  Type type = parameter.type_from_ast();
  if (type.is_reference())
    c.set_fact(%(reference-param $binding), 1);
  if (type.car() == <opt-ref>)
    c.set_fact(%(optional-reference-param $binding), 1);
}

// identifiers

/** Parses the current identifier or dotted owner/member as a one-item name.
    Package aliases and imported method spellings are folded through the
    current `Sym`, and all accepted tokens are consumed.
*/
List Compiler.parse_complex_identifier(Compiler c) =>
  _complex_identifier(c, NULL);

/* Accept one of two forms of dotted identifiers: TYPE.IDENTIFIER or
   IDENTIFIER.TYPE. Preserve the explicit owner/member pair for declarations
   whose mangled spellings alone would be ambiguous. */
static List _complex_identifier(
  Compiler c, List &?method_identity) {
  if (method_identity) method_identity = NULL;
  String ident = _package_alias_member(c), Symbol toktype = c.token.type;
  /* Only a declarator asks for the method identity, and there the name is
     being defined. A `with` spelling must not fold, because the declaration
     belongs to this unit and shadows the binding. */
  if (!ident && toktype == <ident> && !method_identity)
    ident = c.package_member_spelling(c.token.text);
  if (!ident) ident = c.token.text;
  Type idtype = c.sym.get(%( $ident ));
  c.next();
  if ((toktype.is_builtin_type() || toktype.is_type_modifier() ||
       (toktype == <ident> &&
        (idtype.is_typedef() || (c.signature_only && method_identity)))) &&
      c.test(<.>))
    return _member_name(c, ident, method_identity);
  return %($ident);
}

/* The member after `TYPE.` spells a method, which a declarator records as
   its owner and member. Elsewhere an imported package may have declared
   the method on one of its own header's types: the header spells the type,
   and the package spells the method. */
static List _member_name(
  Compiler c, String owner, List &?method_identity) {
  // a weaker test that accepts anything that looks like an identifier
  if (!c.token.text.is_identifier())
    $report.parse.method_member(c, owner);
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
static String _package_alias_member(Compiler c) {
  String spelling = c.package_alias_spelling();
  if (!spelling) return NULL;
  String package = c.package_aliases[c.token.text];
  c.next();
  c.next();
  if (!c.sym.get_exact(%($spelling)))
    $report.parse.package_member(c, c.token, package, c.token.text);
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
List Compiler.parse_optional_identifier(Compiler c) =>
  c.peek(0) == <ident> ? c.parse_basic_identifier() : NULL;

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

/** Parses one function declaration and its required compound body.
    The parameter bindings are active while the body is parsed, and the first
    token after the closing brace remains current.
*/
List Compiler.parse_function_definition(Compiler c) {
  Token tokens = c.tokenizer.tokens, start = c.token;
  List declaration = c.parse_simple_declaration();
  if (c.peek(0) != <"{"> && !_x2c_at_function_arrow(c))
    $report.parse.function_body(c);
  int first = start - tokens, body = c.token - tokens;
  List function = _finish_function(c, declaration, NULL);
  if (!c.macro_holes)
    _definition_source(c, function, start.line, NULL, %($first $body));
  return function;
}

/** Parses one function decorator target and returns its resulting AST.
    A compatible unit macro at the current token is expanded first; otherwise
    an ordinary function definition is required.
*/
List Compiler.parse_function_target(Compiler c) {
  List macro = c.try_parse_macro_target_at(<unit>);
  if (!macro) return c.parse_function_definition();
  match (macro) case %(seq ?function): return function;
  return macro;
}

// Complete a token-parsed or generated function in its parameter scope.
static List _finish_function(
  Compiler c, List declaration, List syntax) {
  match (declaration)
    case %(declare ?rtype
           (bindings
             (!set ?declarator (bind ?binding ?)))):
      return _finish_function_parts(
        c, declaration, rtype, declarator, binding,
        syntax);
  return NULL;
}

static List _finish_function_parts(
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
  String name = _prepare_lifecycle(
    c, declaration, binding, initializer_owner, shutdown_owner);
  List body = _function_body(c, declaration, name, syntax);
  _publish_lifecycle(c, name, initializer_owner, shutdown_owner);
  return %(function $rtype $declarator $body);
}

/* The body parses, or a constructed body binds, in the parameter scope with
   the function's return type and name current. */
static List _function_body(
  Compiler c, List declaration, String name, List syntax) {
  int expression_body = !syntax && _x2c_at_function_arrow(c);
  if (!syntax && !expression_body) c.expect(<"{">);
  Type old_return = c.return_type;
  c.return_type = Ast.declared_return(declaration);
  String old_fn = c.fn_name;
  c.fn_name = name;
  c.sym.push_scope(c.params);
  int depth = c.ancestors.len(), placed = c.placements.len();
  c.enter((Ancestor){ .what = <function>, .node = declaration });
  List body = NULL;
  {
    // A failed body leaves no rows or placements of its own behind.
    defer {
      c.ancestors.truncate(depth);
      c.placements.resize(placed);
      c.sym.pop_scope();
      c.return_type = old_return;
      c.fn_name = old_fn;
    }
    if (syntax) body = c.bind_callable_body(syntax, c.return_type);
    else if (expression_body) body = _expression_body(c);
    else body = c.parse_callable_body();
    body = c.prepend_setup(body, _entry_code(c, depth));
  }
  return body;
}

/** The declared result type of the function `declaration`, which its
    `return` statements convert to, or NULL. */
Type Ast.declared_return(List declaration) {
  match (declaration.type_from_ast())
    case %((func *) *result): return result.type().declared();
  return NULL;
}

/* The code placed at the entry of the function whose row is at `depth`,
   bound in its parameter scope once its body is complete. */
static List _entry_code(Compiler c, int depth) {
  Array items = [];
  foreach (List row, _take_placements(c, depth))
    _push_items(items, c.bind_syntax(row[3], <block>, c.return_type));
  return items.list_free();
}

static String _prepare_lifecycle(
  Compiler c, List declaration, List binding, String &initializer_owner,
  String &shutdown_owner) {
  String name = Ast.binding_spelling(binding);
  initializer_owner = name
    ? _lifecycle_owner(c, binding, "initialize") : NULL;
  shutdown_owner = name
    ? _lifecycle_owner(c, binding, "shutdown") : NULL;
  if (initializer_owner) {
    _require_signature(c, declaration, name, "initializer");
    if (c.init_fn && c.init_fn != name)
      $report.parse.init_duplicate(c, name);
  }
  if (shutdown_owner) {
    _require_signature(c, declaration, name, "shutdown");
    if (c.fini_fn && c.fini_fn != name)
      $report.parse.shutdown_duplicate(c, name);
  }
  return name;
}

static String _lifecycle_owner(
  Compiler c, List binding, String member) {
  List method = c.fact(%(method $binding));
  if (!method) return NULL;
  match (method)
    case %(?name $member): {
      String owner = name, Type owner_type = c.sym.get(%($owner));
      return owner_type.is_typedef() ? owner : NULL;
    }
  return NULL;
}

static void _require_signature(
  Compiler c, List decl, String name, String role) {
  match (decl)
    case %(declare (void)
           (bindings
             (bind ?
               ((fnmod (params (param (void) (bind () ())))))))):
      return;
  $report.parse.lifecycle_signature(c, role, name);
}

static void _publish_lifecycle(
  Compiler c, String name, String initializer_owner,
  String shutdown_owner) {
  if (initializer_owner) c.init_fn = name;
  if (shutdown_owner) c.fini_fn = name;
}

static List _expression_body(Compiler c) {
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

// placement and ancestry

/** Enters `row` as the innermost syntax `Compiler.enclosing` answers. Its
    owner leaves it with `Block.pop`, or with `Compiler.leave_item` for a
    block item. */
void Compiler.enter(Compiler c, Ancestor row) {
  c.ancestors.push(&row);
}

/** Returns the innermost `what` around the parser, or around the function
    body the transform lowers, as captured code, or NULL when there is none:
    the declarator whose initializer is being parsed directly in the current
    block item, as its one-declarator declaration; the block item, or the
    one the transform lowers, as its origin anchor; the function, as a
    definition whose body is still the empty `(seq)`; or the unit, as a
    `String` expression of its path. */
List Compiler.enclosing(Compiler c, Symbol what) {
  if (what == <unit>) {
    String path = c.filename ? c.display_path(c.filename) : "<stdin>";
    return $!String{ $path };
  }
  Ancestor *rows = c.ancestors.bytes;
  for (int i = (int) c.ancestors.len() - 1; i >= 0; i--) {
    Ancestor row = rows[i];
    if (row.what == what) return _ancestor_code(c, row);
    if (row.lowering && what == <statement>) return %(at ${c.origin} (seq));
    if (what == <declarator> || row.what == <function>) return NULL;
  }
  return NULL;
}

static List _ancestor_code(Compiler c, Ancestor row) {
  if (row.what == <declarator>)
    return %(declare ${row.base} (bindings ${row.node}));
  if (row.what == <function>)
    match (row.node) case %(declare ?type (bindings ?declarator)):
      return %(function $type $declarator (seq));
  int origin = row.origin ? row.origin : c.record_origin(row.token);
  return %(at $origin (seq));
}

/** Reports whether the transform is lowering a function body, whose
    local scopes the symbol table no longer holds. */
int Compiler.lowering_body(Compiler c) {
  Ancestor *rows = c.ancestors.bytes;
  for (int i = (int) c.ancestors.len() - 1; i >= 0; i--)
    if (rows[i].what == <function>) return rows[i].lowering;
  return 0;
}

/** Enters the function definition `declaration`, whose body the
    transform lowers next, so a rule lowering that body places code at its
    entry. Returns the row's depth for `Compiler.leave_function`. */
int Compiler.enter_function(Compiler c, List declaration, int callback) {
  int depth = c.ancestors.len();
  Ancestor row = {
    .what = <function>, .node = declaration, .lowering = 1,
    .callback = callback};
  c.enter(row);
  return depth;
}

/** Returns the code placed at the entry of the function row at `depth`
    since it was entered or last asked, in placement order, or NULL. The
    code binds in a scope of its own with the function's result type; its
    caller lowers it while the row is still entered, so a placement that
    lowering makes lands at the entry too. */
List Compiler.function_entry(Compiler c, int depth) {
  if (!c.placements.len()) return NULL;
  List declaration = ((Ancestor *) c.ancestors.bytes)[depth].node;
  c.sym.push_new_scope();
  List entry;
  $let(c.return_type, Ast.declared_return(declaration))
    entry = _entry_code(c, depth);
  c.sym.pop_scope();
  return entry;
}

/** Leaves the function row at `depth` that `Compiler.enter_function`
    began. */
void Compiler.exit_function(Compiler c, int depth) {
  c.ancestors.truncate(depth);
}

/** Records `code` for the entry of the innermost function definition,
    after its parameters bind and before its first statement. While parsing,
    a lambda body is inside the definition that holds it; while lowering, a
    lambda body is the body of its own lifted function, and a finalizer the
    kernel wrote as a callback has no entry a program can place at. */
void Compiler.place_entry(Compiler c, Var code) {
  Ancestor *rows = c.ancestors.bytes;
  int depth = (int) c.ancestors.len() - 1;
  while (depth >= 0 && rows[depth].what != <function>) depth--;
  if (depth < 0) $report.parse.placement_function(c);
  if (rows[depth].callback) $report.parse.placement_finalizer(c);
  c.placements.push(%($depth () () $code));
}

/** Records `code` to follow the innermost block item, or the initialized
    declarator whose initializer is being parsed directly in it. The
    expansion that placed it gives it its result when it finishes. */
void Compiler.place_after(Compiler c, Var code) {
  Ancestor *rows = c.ancestors.bytes;
  int depth = (int) c.ancestors.len() - 1;
  List binding = NULL;
  if (depth >= 0 && rows[depth].what == <declarator>)
    binding = rows[depth--].node.cadr();
  if (depth < 0 || rows[depth].what != <statement>)
    $report.parse.placement_item(c);
  c.placements.push(%($depth $binding () $code));
}

/** Gives the placements made since `first` the `result` of the expansion
    that made them. */
void Compiler.close_placements(Compiler c, int first, List result) {
  for (int i = first; i < (int) c.placements.len(); i++) {
    (int depth, List binding, List placed, Var code) = c.placements[i].list();
    if (!placed) c.placements[i] = %($depth $binding $result $code);
  }
}

/** Leaves the block item `enter` began and returns the code placed after
    it, bound in its block, or NULL. A declarator in the item that placed
    code is incomplete unless its block declaration took that code. */
List Compiler.leave_item(Compiler c) {
  int depth = (int) c.ancestors.len() - 1;
  Ancestor row = ((Ancestor *) c.ancestors.bytes)[depth];
  c.ancestors.pop();
  List placed = _take_placements(c, depth);
  if (!placed) return NULL;
  Array items = [];
  foreach (List placement, placed) {
    (Var anchor, List binding, Var result, Var code) = placement;
    (void) anchor, (void) result;
    if (binding)
      $let(c.origin, row.origin ? row.origin : c.origin)
        $report.parse.init_incomplete(c, row.token);
    _push_items(items, c.bind_syntax(code, <block>, c.return_type));
  }
  return items.list_free();
}

/* Removes the placements anchored at the ancestor row `depth` and returns
   them in placement order. */
static List _take_placements(Compiler c, int depth) {
  if (!c.placements.len()) return NULL;
  Array taken = [];
  int kept = 0;
  for (int i = 0; i < (int) c.placements.len(); i++) {
    List row = c.placements[i];
    if (row.car().int() == depth) taken.push(row);
    else c.placements[kept++] = row;
  }
  c.placements.resize(kept);
  return taken.list_free();
}

/** Lowers block declarations whose declarators placed code after
    themselves, or that an after-initialization rewrite follows, to
    declarations followed by that code in source order, preserving their
    installed bindings and the enclosing lifetime.
*/
List Compiler.finish_initializers(
  Compiler c, List declaration, Token origin) {
  if (c.macro_holes ||
      (!c.placements.len() && !c.has_rewrites(<decl>, <init>)))
    return declaration;
  Array output = [];
  _append_managed(c, declaration, output, origin);
  return %(seq @{output.list_free()});
}

static void _append_managed(
  Compiler c, List declaration, Array output, Token origin) {
  match (declaration) {
    case %(seq *rows): {
      foreach (List row, rows)
        _append_managed(c, row, output, origin);
      return;
    }
    case %(declare ?base (bindings *declarators)): {
      _append_managed_rows(c, base, declarators, output, origin);
      return;
    }
  }
  output.push(declaration);
}

/* A declarator followed by code ends the declaration of the ordinary
   declarators before it, is declared alone, and is followed by its code. */
static void _append_managed_rows(
  Compiler c, Var base, List declarators, Array output, Token origin) {
  Array ordinary = $auto([]);
  Var source_base = base;
  size_t remaining = declarators.len();
  foreach (List declarator, declarators) {
    remaining--;
    List after = _after_declarator(c, source_base, declarator, origin);
    if (!after) {
      ordinary.push(declarator);
      continue;
    }
    if ((remaining || ordinary.len()) && base.type().base_type().body())
      base = _share_declaration_type(c, base, output);
    if (ordinary.len()) {
      output.push(%(declare $base (bindings @{ordinary})));
      ordinary.clear();
    }
    output.push(%(declare $base (bindings $declarator)));
    _push_items(output, after);
  }
  if (ordinary.len())
    output.push(%(declare $base (bindings @{ordinary})));
}

/* The code placed after an initialized `declarator`, which then takes the
   placing expansion's result as its initializer, or else the items an
   after-initialization rewrite adds, or NULL. */
static List _after_declarator(
  Compiler c, Var base, List &declarator, Token origin) {
  match (declarator)
    case %(op = (bind ?name ?mods) ?value): {
      List result = NULL;
      List placed = _take_placed(c, name, value, result, origin);
      if (placed) {
        declarator = %(op = (bind $name $mods) $result);
        return placed;
      }
      return c.rewrite(
        <decl>, <init>, %(declare $base (bindings $declarator)), <block>,
        c.return_type, origin);
    }
  return NULL;
}

/* Takes the placements anchored at `binding` and returns their code bound
   in the block, or NULL. Each placing expansion's result must be the
   complete initializer `value`, and becomes the declarator's initializer. */
static List _take_placed(
  Compiler c, List binding, List value, List &result, Token origin) {
  if (!c.placements.len()) return NULL;
  Array kept = [], code = [];
  foreach (List row, c.placements) {
    (Var depth, List anchor, List placed, Var item) = row;
    (void) depth;
    if (anchor !== binding) {
      kept.push(row);
      continue;
    }
    if (!_complete(value, placed))
      $report.parse.init_incomplete(c, origin);
    if (item in code) $report.parse.placement_repeated(c, origin);
    result = placed;
    code.push(item);
  }
  if (!code.len()) return NULL;
  c.placements = kept;
  Array items = [];
  foreach (Var item, code)
    _push_items(items, c.bind_syntax(item, <block>, c.return_type));
  return %(seq @{items.list_free()});
}

/* Parentheses and typed expression shells preserve the position of a
   complete initializer; operators do not. */
static int _complete(List syntax, List result) {
  if (syntax === result) return 1;
  match (syntax) {
    case %(expr ? ?inner): return _complete(inner, result);
    case $source_content_pattern($grouped, %(?inner)):
      return _complete(inner, result);
  }
  return 0;
}

/* A split declaration still defines its shared type once. An ordinary local
   typedef retains qualified aggregate and enum identity without copying the
   definition into each emitted declaration. Variable storage stays outside. */
static Type _share_declaration_type(
  Compiler c, Type base, Array output) {
  List name = c.sym.introduce(c.fresh_name("declaration_type"));
  Type value = base.declared();
  List alias =
    c.bind_syntax($!{ typedef $value $name; }, <block>, c.return_type);
  _push_items(output, alias);
  Array storage = [];
  foreach (Var item, base)
    if (item is <symbol> && item.symbol().is_storage_class())
      storage.push(item);
  return %(@{storage.list_free()} $name);
}

// constructed syntax

/** Binds parser-shaped `syntax` at `context` into current compiler state.
    `context` is `<unit>`, `<block>`, `<field>`, `<enumerator>`, `<map-entry>`,
    `<statement>`, or `<expression>`.
    The input must evaluate to a nonempty AST `List` valid for the requested
    position. Bindings, types, scopes, and expressions are resolved in source
    order; `return_type` applies only while descendants are bound. This method
    mutates `Sym` and does not open a semantic transaction.
*/
List Compiler.bind_syntax(
  Compiler c, Var syntax, Symbol context, Type return_type) {
  int pending = syntax is <list> && syntax.list().car() == "x2c.template";
  if (_take_staged(c, syntax)) return syntax;
  syntax = c.evaluate_macro_slot(syntax);
  if (_take_staged(c, syntax)) return syntax;
  match (syntax) case %("x2c.quoted" ?(List fresh) ?quoted):
    return c.land_quotation(fresh, quoted, context, return_type);
  if (syntax is not <list>)
    $report.parse.syntax_expected(c);
  List input = syntax;
  if (!input) $report.parse.syntax_expected(c);
  List enumerator =
    context == <enumerator> ? _bind_enumerator(c, input) : NULL;
  if (enumerator) return enumerator;
  if (context == <map-entry> && input.car() != <seq> &&
      input.car() != Atom.intern("macro-invoke"))
    return c.resolve_map_entry(input, c.token);
  $let(c.return_type, return_type)
    return _bind_form(c, input, context, pending);
}

/* Replaces `syntax` with a staged code value and reports whether that
   value is a retained result, which binds no further. */
static int _take_staged(Compiler c, Var &syntax) {
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
static List _bind_enumerator(Compiler c, List input) {
  match (input) {
    case %(!or
           (binding ? (!is ? type string))
           ((!is ? type string))
           ("x2c.ident" (!is ? type string))):
      return _publish_enumerator(c, input, c.aggregate_type, c.token);
    case %(!set ?node
           (bind ? ?)):
      return _publish_enumerator(c, node, c.aggregate_type, c.token);
    case %(!set ?node
           (op =
             (!or
               (binding ? (!is ? type string))
               ((!is ? type string))
               ("x2c.ident" (!is ? type string))
               (bind ? ?))
             ?)):
      return _publish_enumerator(c, node, c.aggregate_type, c.token);
  }
  return NULL;
}

/* Parsed templates and compile-time Lisp are the intended producers. There
   is no separate validation pass before or after expansion. The structural
   match below enforces the position: a form that no arm admits there leaves
   the match for `_construction_error`. Existing expression types and
   binding identities are trusted, and strings are never reparsed.

   Binding mutates the current `Sym` in visitation order. Macro invocation
   opens the surrounding `SymTxn`, allowing earlier siblings to be visible to
   later ones while preserving whole-expansion rollback on failure. */
static List _bind_form(
  Compiler c, List input, Symbol context, int pending) {
  Macro caught = $caught;
  int unit = context == <unit>, block = context == <block>;
  int statement = block || context == <statement>;
  match (input) {
    case %(macro-invoke ?def ?args ?site):
      return _bind_invocation(c, def, args, site, context, pending);
    case %(macro-slot ? ? *) if (c.macro_holes): return input;
    case %(code-value ? ? ?):
      return c.bind_code_value(input, context, c.return_type);
    case %(src ? ?syntax):
      return c.bind_syntax(syntax, context, c.return_type);
    case %(api-source ?line ?doc ?syntax) if (unit):
      return _bind_api_source(c, line, doc, syntax);
    case %(named-type ?(String name) ?type) if (unit):
      return _bind_named_type(c, name, type);
    case %(declaration-bundle (rows *rows)) if (unit):
      return _bind_bundle(c, rows);
    case %(syntax-recipe ?callback ?args):
      return _bind_recipe(c, callback, args, context);
    case %(declaration-recipe ?callback ?args) if (unit):
      return _bind_decl_recipe(c, callback, args);
    case %(default-forward ?own ?base ?name *form) if (unit):
      return %(declaration-forward $own $base $name $form ${c.source_private});
    case %(default ?function) if (unit): return _bind_default(c, function);
    case %(declaration-function
             (declare ?type (bindings ?decl)) ?body ?source) if (unit):
      return _bind_collected_function(c, input, type, decl, body, source);
    case %(declaration-initialized ?decl ?source) if (unit):
      return _bind_collected_initializers(c, input, decl, source);
    case %(seq *items): return _bind_items(c, items, context);
    case %(args *args) if (context == <expression>):
      return _bind_args(c, args);
    case %(c-assert ?test ?message) if (unit || block || context == <field>):
      return _bind_assert(c, test, message);
    case %(falias ?decl ?native_syntax) if (unit):
      return _bind_alias(c, decl, native_syntax);
    case %(!set ?expr (expr *)) if (context == <expression>):
      return _resolve(c, expr);
    case %((!set ?tag (!or declare decl typedef))
           ?base (bindings *declarators)):
      return _bind_declaration(c, tag, base, declarators, context);
    case %(dstrdecl ?base (targets *targets) ?source) if (block):
      return _bind_targets(c, base, targets, source);
    case %(dstrdecl (params *parameters) ?source) if (block):
      return _bind_typed_targets(c, parameters, source);
    case %(function ?type
             (bind ?name ((fnmod (params *params)) *mods)) ?body) if (unit):
      return _bind_function(c, type, name, params, mods, body);
    case %(!set ?node ((!or protocol adopt meta-protocol) *)) if (unit):
      return c.publish_protocol_node(node, c.token, NULL);
    case %(!set ?def (macrodef *)): return _bind_macrodef(c, def, context);
    case %(preproc ?(String directive)) if (unit || block):
      return _bind_preproc(c, input);
    case %(at ?origin ?node) if (block): return _bind_item(c, origin, node);
    case %(at ?origin ?node):
      return _anchor(c, origin, c.bind_syntax(node, context, c.return_type));
    case $return_empty() if (statement):
      return c.finish_return_statement(NULL);
    case $return_value(?expr) if (statement):
      return c.finish_return_statement(expr);
    case %((!or break continue default empty)) if (statement): return input;
    case %(case ?expr) if (statement): return %(case ${_resolve(c, expr)});
    case %((!set ?tag (!or goto label)) ?name) if (statement):
      return %($tag $name);
    case $expression_statement(?expr) if (statement):
      return _bind_expression_statement(c, expr, context);
    case $deferred(?body) if (statement):
      return %(defer ${_bind_statement(c, body)});
    case $do_loop(?body, ?test) if (statement): return _bind_do(c, body, test);
    case $while_loop(?test, ?body) if (statement):
      return _bind_while(c, test, body);
    case $switched(?expr, ?body) if (statement):
      return _bind_switch(c, expr, body);
    case $if_then(?test, ?ontrue) if (statement):
      return _bind_if(c, test, ontrue);
    case $if_else(?test, ?ontrue, ?onfalse) if (statement):
      return _bind_if_else(c, test, ontrue, onfalse);
    case $for_loop(?init, ?test, ?next, ?body) if (statement):
      return _bind_for(c, init, test, next, body);
    case %(raise ?code (args *details)) if (statement):
      return _bind_raise(c, code, details);
    case %(catchcases ?arms *handler) if (context == <statement>):
      return _bind_catchcases(c, arms, handler);
    case caught(?body, ?cleanup, *arms) if (statement):
      return _bind_try(c, body, input.caddr(), cleanup);
    case $tried(?body, ?cleanup) if (statement):
      return _bind_try(c, body, NULL, cleanup);
    case $matched(?subject, *cases) if (statement):
      return _bind_match(c, subject, cases);
    case $source_block_content(%(*children)) if (statement):
      return _bind_block(c, input);
    case %(group *children) if (statement): return _bind_group(c, children);
  }
  return _construction_error(c);
}

/* Reports a constructed form at a position that does not admit it.
   `report_error` never returns, so a caller may return this call. */
static List _construction_error(Compiler c) {
  $report.parse.syntax_position(c, c.token);
}

/* A meta call written as a whole statement may return a statement. */
static List _bind_expression_statement(
  Compiler c, List expression, Symbol context) {
  match (expression) case %(expr ? (meta-call *)):
    if (!c.meta_body && !c.macro_holes)
      return c.evaluate_meta_statement(expression, context, c.token);
  return %(stmnt ${_resolve(c, expression)});
}

static List _resolve(Compiler c, List expr) =>
  c.resolve_expression(expr, c.token);

/* A source clause parses, already bound, when the binder reaches it. */
static List _bind_statement(Compiler c, Var stmt) {
  Symbol kind = _source_clause_kind(stmt);
  if (kind) return c.parse_source_clause(kind);
  List bound = c.bind_syntax(stmt, <statement>, c.return_type);
  c.rebound(stmt, bound);
  return bound;
}

static List _bind_clause(Compiler c, Var expr) {
  Symbol kind = _source_clause_kind(expr);
  if (kind) return c.parse_source_clause(kind);
  return _resolve(c, expr);
}

/* A macro invocation expands at the position that holds it. A Macro value
   applied directly stands for one statement or unit item. Inside a
   recovery boundary it owns the transaction that covers the effects its
   producers request; outside one, an error exits and nothing rolls back. */
static List _bind_invocation(
  Compiler c, Var definition, Var arguments, Var invocation, Symbol context,
  int pending) {
  Token site = c.macro_invocation_site(invocation);
  if (invocation != <m-invoke>)
    return c.expand_macro_invocation_node(
      definition, arguments, site, context);
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    List bound = c.expand_macro_invocation_node(
      definition, arguments, site, context);
    transaction.commit();
    if (pending && (context == <block> || context == <statement> ||
                    context == <unit>))
      match (bound) case %(seq ?item): return item;
    return bound;
  }
}

/* An anchor keeps a lone bound item, and a macro's origin marker becomes
   the compiler's current origin. */
static List _anchor(Compiler c, Var origin, List bound) {
  match (bound) case %(seq ?only): bound = only;
  Var anchor = origin == <m-origin> ? c.origin : origin;
  return %(at $anchor $bound);
}

/* An anchored block item is followed by the code placed after it. */
static List _bind_item(Compiler c, Var origin, List node) {
  int anchor = origin == <m-origin> ? c.origin : origin.int();
  c.enter((Ancestor){ .what = <statement>, .origin = anchor });
  List bound =
    _anchor(c, origin, c.bind_syntax(node, <block>, c.return_type));
  List after = c.leave_item();
  return after ? %(seq $bound @after) : bound;
}

// constructed file-scope forms

/* A definition an API source form wraps keeps its line and doc comment,
   or those of the invocation that expands it. */
static List _bind_api_source(
  Compiler c, Var line, Var doc, Var syntax) {
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
  foreach (List frame, c.macro_stack)
    foreach (List binding, frame[2])
      match (binding)
        case %(? (src (source ?(String path) ?(int begin) ?(int end))
                      ?syntax)):
          if (c.text && path == file)
            written[syntax] = String.new_len(c.text + begin, end - begin);
  foreach (List binding, c.macro_stack.car().list()[2]) {
    (Var binder, Var value) = binding;
    Var syntax = value;
    match (value) case %(src ? ?captured): syntax = captured;
    Var spelling = syntax is <string> ? syntax : void;
    match (value)
      case %(src (source ?(String path) ?(int begin) ?(int end)) ?):
        if (spelling is void && c.text && path == file)
          spelling = String.new_len(c.text + begin, end - begin);
    if (spelling is void) spelling = written[syntax];
    if (spelling is not void) spellings[binder.str()[1:]] = spelling;
  }
  return spellings;
}

static List _bind_named_type(Compiler c, String name, Var type) {
  List key = %($name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (!type.list_payload()) return %(seq);
  List declaration = type.type().declaration_ast(key);
  match (declaration)
    case %(declare ?base ?bindings):
      return c.bind_syntax(%(typedef $base $bindings), <unit>, NULL);
  return _construction_error(c);
}

/* Binds a declaration bundle's rows in order. Collection first runs the
   pending declaration effects and returns the rows as a bundle. */
static List _bind_bundle(Compiler c, List rows) {
  if (c.shallow) {
    c.declaration_produced = 1;
    c.run_declaration_effects();
  }
  Array projected = [];
  foreach (List row, rows) {
    List bound = c.bind_syntax(row, <unit>, c.return_type);
    _append_rows(projected, bound);
  }
  List items = projected.list_free();
  return c.shallow ? %(declaration-bundle (rows @items)) : %(seq @items);
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

static List _bind_recipe(
  Compiler c, Var callback, Var arguments, Symbol context) {
  Var syntax = c.evaluate_declaration_recipe(callback, arguments);
  return c.bind_syntax(syntax, context, c.return_type);
}

/* Collection keeps a declaration recipe pending with the macro stack that
   constructed it; the full parse evaluates it. */
static List _bind_decl_recipe(
  Compiler c, Var callback, Var arguments) {
  if (c.shallow)
    return %(declaration-pending $callback $arguments
              ${c.macro_stack} ${c.source_private});
  return _bind_recipe(c, callback, arguments, <unit>);
}

static List _bind_default(Compiler c, Var function) {
  if (c.shallow)
    return %(declaration-default $function ${c.macro_stack}
              ${c.source_private});
  return c.bind_syntax(function, <unit>, c.return_type);
}

/* Binds a local macro definition in a block and publishes any other one
   at file scope. */
static List _bind_macrodef(
  Compiler c, Var definition, Symbol context) {
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

static List _bind_preproc(Compiler c, List directive) {
  c.note_preprocessor_macros(%($directive));
  return directive;
}

static List _bind_alias(Compiler c, Var declaration, Var native) {
  List bound = c.bind_syntax(declaration, <unit>, c.return_type);
  return c.finish_foreign_alias(bound, native);
}

// constructed functions

/* Collection binds a constructed function's declaration and keeps its body
   (see `_collected_function`). The full parse binds the whole function
   under the macro stack that constructed it, as a declaration default. */
static List _bind_collected_function(
  Compiler c, List input, Var return_type, Var declarator, Var body,
  Var construction) {
  if (c.shallow) return input;
  Type type = %(declare $return_type (bindings $declarator)).type_from_ast();
  if (c.public_bodies &&
      (!type.is_inline() || type.is_static() || c.source_private)) return NULL;
  $let(c.macro_stack, construction) {
    Token invocation = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
    $let(c.origin, invocation ? c.record_origin(invocation) : c.origin)
    return c.bind_syntax(
      %(function $return_type $declarator $body), <unit>, c.return_type);
  }
}

/* Collection installs a constructed declaration's names and keeps its
   initializers (see `_bind_declaration`). The full parse resolves them
   under the macro stack that constructed them. */
static List _bind_collected_initializers(
  Compiler c, List input, Var declaration, Var construction) {
  if (c.shallow) return input;
  $let(c.macro_stack, construction) {
    return c.bind_syntax(declaration, <unit>, c.return_type);
  }
}

/* Binds a constructed function's parameters in a fresh prototype scope,
   which becomes its parameter scope, and then its declaration. */
static List _bind_function(
  Compiler c, Var return_type, Var function_name, List parameter_values,
  List return_modifiers, Var body) {
  List parameter_list = _bind_parameters(c, parameter_values);
  List declarator = %(
    bind $function_name
      ((fnmod (params @parameter_list)) @return_modifiers)
  );
  List declaration = c.bind_syntax(
    %(declare $return_type (bindings $declarator)), <unit>, c.return_type);
  if (c.shallow) return _collected_function(c, declaration, body);
  Type type = declaration.type_from_ast();
  if (c.public_bodies &&
      (!type.is_inline() || type.is_static() || c.source_private)) return NULL;
  return _finish_function(c, declaration, body);
}

static List _bind_parameters(Compiler c, List values) {
  Array parameters = [];
  c.sym.push_new_scope();
  {
    defer c.params = c.sym.pop_scope();
    foreach (Var value, values)
      foreach (Var row, c.evaluate_macro_rows(value)) match (row) {
        case %(...): parameters.push(row);
        case %(param ?base (!set ?declarator (bind ? ?))):
          parameters.push(
            _finish_parameter(c, base, declarator, NULL, NULL, NULL));
      }
  }
  return parameters.list_free();
}

/* Collection publishes a constructed function's declaration and keeps its
   body for the full parse. */
static List _collected_function(
  Compiler c, List declaration, Var body) {
  c.record_inline_function(declaration);
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ?modifiers))): {
      String name = Ast.binding_spelling(binding);
      // A static definition stays in its unit, as in source.
      if (type.type().is_static())
        c.sym.mark_static(%(function $name));
      else c.fn_defs[name] = 1;
      c.record_declaration_visibility(declaration);
      List method = c.fact(%(method $binding));
      if (method) {
        // Replay the resolved owner with this declaration's own member.
        String member = method.cadr();
        String owner = name[:name.len() - member.len() - 1];
        declaration = %(declare $type
          (bindings (bind (($owner) $member) $modifiers)));
      }
      else {
        /* Renamed locals keep their identity; exact names complete
           prototypes. */
        Var source;
        if (!c.semantic_binding_facts().try_get(
          %(source-spelling $binding), source) || source == name)
          declaration = %(declare $type (bindings (bind $name $modifiers)));
      }
    }
  return %(declaration-function $declaration $body ${c.macro_stack});
}

// constructed declarations and expressions

/* A statement position admits a sequence of one statement. Elsewhere the
   items bind in order, and a nested sequence contributes its items. */
static List _bind_items(Compiler c, List items, Symbol context) {
  if (context == <statement>) {
    match (items) case %(?only):
      return c.bind_syntax(only, context, c.return_type);
    $report.parse.statement_single(c);
  }
  Array bound = [];
  foreach (Var item, items)
    _push_items(bound, c.bind_syntax(item, context, c.return_type));
  return %(seq @{bound.list_free()});
}

static List _bind_args(Compiler c, List arguments) {
  Array bound = [];
  foreach (List argument, arguments) bound.push(_resolve(c, argument));
  return %(args @{bound.list_free()});
}

static List _bind_assert(Compiler c, Var condition, Var message) =>
  %(c-assert ${_resolve(c, condition)} ${_resolve(c, message)});

/* Completes a constructed declaration's base type, then installs each
   declarator as the parser does. Only a field may declare a bit-field.
   Collection keeps file-scope initializers for the full parse, with the
   macro stack that constructed them. */
static List _bind_declaration(
  Compiler c, Var tag, Var base, List declarators, Symbol context) {
  int shallow = c.shallow;
  if (c.public_bodies && context == <unit>) c.shallow = 1;
  defer c.shallow = shallow;
  if (!_declaration_legal(tag, context)) return _construction_error(c);
  base = _finish_type(c, base);
  List field_context = context == <field> ? c.aggregate_type : NULL;
  List declaration_context = tag == <typedef> ? %(typedef) : field_context;
  Array output = [];
  int preserved_self = 0, initializes = 0;
  foreach (Var value, declarators)
    foreach (List declarator, c.evaluate_macro_rows(value)) {
      declarator = _finish_fnmods(c, declarator);
      if (context != <field> && _has_bitfield(declarator))
        return _construction_error(c);
      match (declarator) case %(op = * *): initializes = 1;
      List installed = _install_declarator(
        c, base, declaration_context, declarator, NULL, preserved_self);
      output.push(installed);
    }
  List decl = _finish_declaration(
    c, tag, base, output.list_free(), preserved_self);
  if (context == <unit>) c.record_declaration_visibility(decl);
  if (c.shallow && context == <unit> && initializes)
    return %(declaration-initialized $decl ${c.macro_stack});
  if (context == <block> && tag == <declare>)
    return c.finish_initializers(decl, c.token);
  return decl;
}

/* A typedef stands in a unit or a block, a `decl` only in a block, and any
   other declaration also in an aggregate. */
static int _declaration_legal(Var tag, Symbol context) {
  if (tag == <typedef>) return context == <unit> || context == <block>;
  if (tag == <decl>) return context == <block>;
  return context == <unit> || context == <block> || context == <field>;
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
static List _bind_targets(
  Compiler c, Var base, List targets, Var source) {
  Array declarators = [];
  foreach (Var target, targets) declarators.push(%(bind $target ()));
  List declaration = c.bind_syntax(
    %(declare $base
        (bindings @{declarators.list_free()})),
    <block>, c.return_type
  );
  match (declaration)
    case %(declare ?bound_base (bindings *bindings)): {
      Array bound_targets = [];
      foreach (List binding, bindings)
        match (binding)
          case %(bind ?name ?): bound_targets.push(name);
      return %(dstrdecl $bound_base
               (targets @{bound_targets.list_free()})
               ${_resolve(c, source)});
    }
  return _construction_error(c);
}

/* Each typed target contributes one bound declaration. */
static List _bind_typed_targets(
  Compiler c, List parameters, Var source) {
  Array bound_parameters = [];
  foreach (List parameter, parameters)
    match (parameter)
      case %(param ?base (!set ?declarator (bind ? ?))): {
        List declaration = c.bind_syntax(
          %(declare $base (bindings $declarator)), <block>, c.return_type);
        match (declaration)
          case %(declare ?bound_base (bindings ?binding)):
            bound_parameters.push(%( param $bound_base $binding ));
      }
  return %(dstrdecl (params @{bound_parameters.list_free()})
           ${_resolve(c, source)});
}

// constructed statements

/* A source `if`, `while`, `do`, `for`, `match`, or `try` binds here with a
   Token Var into this table for each clause, which the binder parses when it
   reaches it, so its scopes and optional-reference facts govern that parse.
   Syntax from a template or compile-time Lisp cannot hold these addresses.
   Each entry's type names its clause. */
static struct Token source_clauses[] = {
  { .type = <test> }, { .type = <then> }, { .type = <else> },
  { .type = <body> }, { .type = <do> },   { .type = <init> },
  { .type = <cond> }, { .type = <next> }, { .type = <arms> },
  { .type = <arm> },  { .type = <try> },  { .type = <catches> },
  { .type = <catch> }, { .type = <finally> }
};

/** The source clause `kind`, which the binder parses when it reaches it. */
Var Compiler.source_clause(Symbol kind) {
  Token clause = source_clauses;
  while (clause.type != kind) clause++;
  return Token.var(clause);
}

// Any value other than a table entry is constructed syntax, kind 0.
static Symbol _source_clause_kind(Var value) {
  if (value is not <token>) return 0;
  Token clause = value;
  Token end =
    source_clauses + sizeof(source_clauses) / sizeof(*source_clauses);
  return clause >= source_clauses && clause < end ? clause.type : 0;
}

/** Binds the source `if`, `while`, `do`, `for`, `match`, or `try` at the
    cursor through the same binders as constructed syntax.
*/
List Compiler.bind_source_statement(Compiler c) {
  Symbol keyword = c.peek(0);
  c.next();
  switch (keyword) {
    case <if>:
      return _bind_if_else(
        c, Compiler.source_clause(<test>), Compiler.source_clause(<then>),
        Compiler.source_clause(<else>));
    case <while>:
      return _bind_while(
        c, Compiler.source_clause(<test>), Compiler.source_clause(<body>));
    case <do>:
      return _bind_do(
        c, Compiler.source_clause(<do>), Compiler.source_clause(<test>));
    case <match>:
      return _bind_match(
        c, Compiler.source_clause(<test>), Compiler.source_clause(<arms>));
    case <try>:
      return _bind_try(
        c, Compiler.source_clause(<try>), Compiler.source_clause(<catches>),
        Compiler.source_clause(<finally>));
  }
  return _bind_for(
    c, Compiler.source_clause(<init>), Compiler.source_clause(<cond>),
    Compiler.source_clause(<next>), Compiler.source_clause(<body>));
}

static List _bind_do(Compiler c, Var body, Var condition) {
  List bound = _bind_statement(c, body);
  return %(do $bound ${_bind_clause(c, condition)});
}

static List _bind_while(Compiler c, Var condition, Var body) {
  List test = _bind_clause(c, condition);
  return %(while $test ${_bind_statement(c, body)});
}

static List _bind_switch(Compiler c, Var expr, Var body) =>
  %(switch ${_resolve(c, expr)} ${_bind_statement(c, body)});

/* Binds the arm where an optional-reference test holds with the reference
   present, and marks it present after the `if` when the other arm cannot
   fall through. */
static List _bind_if(Compiler c, Var condition, Var ontrue) {
  List test = _bind_clause(c, condition);
  int true_is_present = 1;
  List binding = c.optional_reference_test(test, true_is_present);
  List yes = _bind_branch(c, ontrue, binding, true_is_present);
  c.settle_reference(binding, true_is_present, yes, NULL);
  return %(if $test $yes);
}

static List _bind_if_else(
  Compiler c, Var condition, Var ontrue, Var onfalse) {
  List test = _bind_clause(c, condition);
  int true_is_present = 1;
  List binding = c.optional_reference_test(test, true_is_present);
  List yes = _bind_branch(c, ontrue, binding, true_is_present);
  List no = _bind_branch(c, onfalse, binding, !true_is_present);
  c.settle_reference(binding, true_is_present, yes, no);
  // A source `if` without `else` parses no false arm.
  return no ? %(if $test $yes $no) : %(if $test $yes);
}

static List _bind_branch(
  Compiler c, Var arm, List binding, int present) {
  if (!binding) return _bind_statement(c, arm);
  List before = c.present_references();
  if (present) c.mark_reference_present(binding);
  List bound = _bind_statement(c, arm);
  c.restore_reference_presence(before);
  return bound;
}

static List _bind_for(
  Compiler c, Var init, Var condition, Var increment, Var body) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  init = _bind_header(c, init);
  condition = _bind_header(c, condition);
  increment = _bind_header(c, increment);
  return %(for $init $condition $increment ${_bind_statement(c, body)});
}

/* A header clause may be absent. The resolver binds a declaring
   initializer as a block declaration. */
static Var _bind_header(Compiler c, Var clause) {
  Symbol kind = _source_clause_kind(clause);
  if (kind) return c.parse_source_clause(kind);
  return clause is <list> ? _resolve(c, clause) : clause;
}

static List _bind_raise(Compiler c, Var code, List details) {
  Array bound = [];
  foreach (List detail, details) bound.push(_resolve(c, detail));
  return %(raise ${_resolve(c, code)} (args @{bound.list_free()}));
}

/* Binds each catch arm's pattern names in a scope of its own. */
static List _bind_catchcases(Compiler c, Var arms, List handler) {
  List handle = handler ? handler.car().list()
    : c.sym.introduce(c.fresh_name("error_handler"));
  /* The lowering declares the handle after its readers bind, so they keep
     its identity rather than reading a template local's source spelling. */
  c.set_fact(%(type $handle), %("ErrorHandler"));
  Array bound = [];
  foreach (Var value, arms.list())
    foreach (List arm, c.evaluate_macro_rows(value)) {
      List pattern = arm.car();
      if (pattern) pattern = _resolve(c, pattern);
      bound.push(c.bind_catch_arm(pattern, arm.cadr(), c.token, handle));
    }
  return %(catchcases ${bound.list_free()} $handle);
}

/** Binds one catch arm's `body` in a scope of its own, with declarations of
    the definite binders of `pattern`, read through `handle`, before it.
    Binder diagnostics use `start`. A source arm's body parses here, and a
    template's declares its binders where its expansion binds it. A parsed
    arm's body already begins with them, so it binds unchanged.
*/
List Compiler.bind_catch_arm(
  Compiler c, List pattern, Var body, Token start, List handle) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  List bindings = NULL;
  if (pattern) {
    _check_binders(c, pattern, start, "catch");
    bindings = c.define_pattern_binders(pattern);
  }
  List statement = _bind_statement(c, body);
  if (_declares_binders(body, bindings))
    return %($pattern $statement);
  return %($pattern (block
    @{c.pattern_binder_declarations(bindings, handle)} $statement));
}

/* Rejects the two ways a match or catch pattern can name a binder it does
   not reliably bind. `role` is the keyword the diagnostics name. */
static void _check_binders(
  Compiler c, List pattern, Token start, String role) {
  List possible = NULL;
  List definite = c.match_pattern_binders(pattern, possible);
  foreach (Var binder, possible) {
    if (!(binder in definite))
      $report.type.binder_unassigned(c, role, start, binder);
    String name = binder.str()[1:];
    foreach (Var other, possible) {
      if (other == binder || other.str()[1:] != name) continue;
      $report.type.binder_conflict(c, role, start, name);
    }
  }
}

/* Whether an arm already carries its ordinary capture declarations: its
   body reads every capture slot, as the declarations do even after a
   rewrite moves a binder into a lambda cell. A nested match or catch reads
   slots of its own. */
static int _declares_binders(List body, List bindings) {
  if (!bindings) return 0;
  Map read = {};
  List node;
  $ast.walk(body, node) match (node) {
    case %(!or (match *) (catchcases *)): continue;
    case %(call "x2c_error_catch_capture" (args ? (expr ? (literal ? ?n)))):
      read[%(catch $n)] = 1;
    case %(?(String slot)): read[slot] = 1;
  }
  int index = 0;
  foreach (List binding, bindings) {
    String n = %"${index++}";
    String slot = %"_x2c_gensym_match_${
      binding.car().is_list_binder() ? "list" : "value"}_$n";
    if (!(slot in read || %(catch $n) in read)) return 0;
  }
  return 1;
}

// Source clauses parse here, so body, arms, and finalizer go in token order.
static List _bind_try(
  Compiler c, Var body, Var catches, Var cleanup) {
  List bound = _bind_statement(c, body);
  List arms = catches ? _bind_statement(c, catches) : NULL;
  List finalizer = cleanup ? _bind_statement(c, cleanup) : NULL;
  Macro tried = $tried, caught = $caught;
  List statement = arms
    ? caught(bound, finalizer, arms.cadr()) : tried(bound, finalizer);
  List rebuilt = c.rebuild_statement(statement).cadr();
  return arms ? source_retain_catch_handle(rebuilt, arms.caddr()) : rebuilt;
}

/* Binds each `match` arm's captures in a scope of its own. A source
   subject parses before the arms, and source arms parse as they bind. */
static List _bind_match(Compiler c, Var subject, Var cases) {
  Symbol kind = _source_clause_kind(subject);
  if (kind) subject = c.parse_source_clause(kind);
  kind = _source_clause_kind(cases);
  List rows = kind ? c.parse_source_clause(kind) : _bind_rows(c, cases);
  return %(match ${_resolve(c, subject)} $rows);
}

static List _bind_rows(Compiler c, List cases) {
  Array bound = [];
  foreach (Var value, cases)
    foreach (List row, c.evaluate_macro_rows(value)) {
      if (row.car() == <preproc>) {
        bound.push(row);
        continue;
      }
      List pattern = row.car();
      int binds = pattern !== %(*);
      if (binds) pattern = _resolve(c, pattern);
      bound.push(c.bind_match_arm(pattern, row.cadr(), c.token, binds, NULL));
    }
  return bound.list_free();
}

/** Binds one match arm's `body` in a scope of its own, which defines the
    definite binders of `pattern` when the arm `binds`. Binder diagnostics
    use `start`. A source arm's body parses here with the typed captures
    `types` that its pattern recorded.
*/
List Compiler.bind_match_arm(
  Compiler c, List pattern, Var body, Token start, int binds, List types) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  List bindings = NULL;
  if (binds) {
    _check_binders(c, pattern, start, "match");
    bindings = c.define_pattern_binders(pattern);
  }
  List statement = _bind_arm_body(c, body, types);
  if (!bindings || _declares_binders(body, bindings))
    return %($pattern $statement);
  List declarations = c.pattern_binder_declarations(bindings, NULL);
  match (statement)
    case %(guarded ?inner):
      return %($pattern (guarded (block @declarations $inner)));
  return %($pattern (block @declarations $statement));
}

static List _bind_arm_body(Compiler c, Var body, List types) {
  if (_source_clause_kind(body)) return c.parse_case_body(types);
  match (body) case %(guarded ?statements):
    return %(guarded ${_bind_statement(c, statements)});
  return _bind_statement(c, body);
}

/* A constructed block opens its own scope; a callable's outer block binds
   in its parameter scope instead. */
static List _bind_block(Compiler c, List block) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  return c.bind_callable_body(block, c.return_type);
}

static List _bind_group(Compiler c, List children) {
  Array items = [];
  foreach (Var child, children)
    items.push(c.bind_syntax(child, <block>, c.return_type));
  return %(group @{items.list_free()});
}

/** Binds a callable's outer block in its active parameter scope. Ordinary
    constructed blocks open their own scope before using this operation.
*/
List Compiler.bind_callable_body(Compiler c, List syntax, Type return_type) {
  match (syntax) {
    case %(at ?origin ?body):
      return _anchor(c, origin, c.bind_callable_body(body, return_type));
    case $source_block_content(%(*children)): {
      Array stmts = [];
      List present_before = c.present_references();
      defer c.restore_reference_presence(present_before);
      foreach (Var child, children)
        _push_items(stmts, c.bind_syntax(child, <block>, return_type));
      return %(block @{stmts.list_free()});
    }
  }
  return c.bind_syntax(syntax, <block>, return_type);
}

// constructed types

static List _finish_type(Compiler c, List type) {
  List base = type;
  Array storage = [];
  while (base.car() is <symbol> &&
         (base.car().symbol().is_type_qualifier() ||
          base.car().symbol().is_storage_class())) {
    storage.push(base.car());
    base = base.cdr();
  }
  if (base != type &&
      (base.car() == <struct> || base.car() == <union> ||
       base.car() == <enum>))
    return c.sym.local_type(
      %(@{storage.list_free()} @{_finish_type(c, base)}));
  storage.free();
  Var whole = _finish_type_spec(c, type);
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
    Var finished = _finish_type_spec(c, spec);
    if (finished is <list> && !finished.is_nil() &&
        finished.car() == <seq>)
      foreach (Var item, finished.list().cdr()) bound.push(item);
    else bound.push(finished);
  }
  Type resolved = bound.list_free();
  return c.sym.local_type(resolved);
}

static Var _finish_type_spec(Compiler c, Var spec) {
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
      return %($tag ${_finish_tag_name(c, name)});
    case %((!set ?tag (!or struct union)) ?name (fields *members)):
      return _finish_aggregate_type(c, tag, name, members);
    case %(enum ?name):
      return %(enum ${_finish_tag_name(c, name)});
    case %(enum ?name (*members)):
      return _finish_aggregate_type(c, <enum>, name, members);
    // Semantic types name an expanded template typedef by its spelling.
    case %(binding ? ?(String name)): return name;
  }
  return spec;
}

static Var _finish_tag_name(Compiler c, Var name) {
  name = c.evaluate_macro_slot(name);
  String exact = _syntax_exact_name(name);
  return exact ? exact : name;
}

static List _finish_aggregate_type(
  Compiler c, Symbol tag, Var name, List members) {
  name = _finish_tag_name(c, name);
  // Each constructed anonymous body defines a distinct type.
  match (name) case %(gensym ? ?): name = c.gensym().car();
  if (tag != <enum>) name = c.aggregate_name(tag, name, 1);
  List type = %($tag $name);
  Array bound = [];
  Symbol position = tag == <enum> ? <enumerator> : <field>;
  $let(c.aggregate_type, type) {
    foreach (List member, members)
      foreach (Var row, c.evaluate_macro_rows(member))
        _push_items(bound, c.bind_syntax(row, position, c.return_type));
  }
  return _publish_aggregate_type(c, tag, name, bound.list_free(), c.token);
}

/* Constructed function modifiers have not passed through the parameter
   parser. Bind their parameter types in the same temporary prototype scope. */
static List _finish_fnmods(Compiler c, List declarator) {
  match (declarator) {
    case %(op = ?binding ?value):
      return %(op = ${_finish_fnmods(c, binding)} $value);
    case %(bind ?binding ?modifiers): {
      Array output = [];
      foreach (Var modifier, modifiers.list())
        output.push(_finish_fnmod(c, modifier));
      return %(bind $binding (@{output.list_free()}));
    }
  }
  return declarator;
}

static Var _finish_fnmod(Compiler c, Var modifier) {
  match (modifier)
    case %(fnmod (params *parameters)):
      return %(fnmod (params @{_finish_prototype(c, parameters)}));
  return modifier;
}

static List _finish_prototype(Compiler c, List parameters) {
  Array params = [];
  c.sym.push_new_scope();
  {
    defer c.sym.pop_scope();
    foreach (List parameter, parameters) match (parameter) {
      case %(param ?base ?declarator):
        params.push(c.bind_parameter(base, declarator));
      default: params.push(parameter);
    }
  }
  return params.list_free();
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
      $report.parse.alias_body(c);
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
  $report.parse.alias_target(c);
}

static void _alias_storage(Compiler c, Var base) {
  foreach (Var part, base) {
    if (part is not <symbol>) continue;
    Symbol specifier = part;
    if (specifier.is_storage_class() && specifier != <static>)
      $report.parse.alias_storage(c);
  }
}

static void _alias_parameters(Compiler c, List parameters) {
  foreach (Var parameter, parameters)
    match (parameter) case %(...):
      $report.parse.alias_variadic(c);
}

static List _alias_target(
  Compiler c, List declaration, Var binding, List native_syntax) {
  List native = c.resolve_expression(native_syntax, c.token);
  match (native)
    case %(expr (!set ?native_type (*)) ${$source_identifier_content(
        %(?native_binding))}): {
      if (native_type && !native_type.type().is_function())
        $report.type.alias_function(c, native_type);
      if (List.equal(binding, native_binding))
        $report.parse.alias_self(c);
      return %(falias $declaration $native_binding);
    }
  $report.parse.alias_identifier(c);
}
