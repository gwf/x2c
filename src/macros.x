/*  macros.x -- source macros and the compile-time Lisp they run

    This module owns macro expansion. Expansion fills a definition's
    template from an invocation's captures and binds the result through the
    operations that bind parsed source. A definition is a compiler-only
    `macrodef` List: its holes, a Match pattern over an invocation's
    capture rows, and a template of the binders that pattern captures.
    Template slots and `$(...)` forms run in the unit's compile-time Lisp
    session, a child of the shared library session filled once per target.
*/

#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "grammar.x"
#include "ast-rewrite.x"
#include "compiler.x"
#include "adapter-memo.x"
#include "fields.x"
#include "expressions.x"
#include "builtins.x"
#include "linked-meta.x"
#include "literals.x"
#include "lambdas.x"
#include "stage.x"
#include "meta-group.x"
#include "meta-helper-client.x"
#include "meta-native.x"
#include "meta-sdk.x"
#include "meta.x"
#include "parse.x"
#include "regions.x"
#include "statements.x"
#include "digest.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <dlfcn.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "expressions-reports.x"

/* macros diagnostics. */

static macro Stmt $report.rewrite.result_type(
  Expr $c, Expr $site, Expr $expected, Expr $actual) =>
  $c.report_error(
    <type>, "indexed rewrite must preserve the getter result type", $site,
    %("expected: ${$expected.repr()}" "actual: ${$actual.repr()}"
      "return an explicitly converted expression"));

static macro Stmt $report.macro.expansion_count(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "macro expansion count exceeds 10000",
    $origin, NULL);

static macro Stmt $report.macro.expansion_recursive(
  Expr $c, Expr $spelling, Expr $origin,
  Expr $definition_note, Expr $shown) =>
  $c.report_error(
    <macro>, %"identical recursive expansion of '${$spelling}'",
    $origin, %(${$definition_note} "input: ${$shown.repr()}"));

static macro Stmt $report.macro.expansion_depth(
  Expr $c, Expr $origin, Expr $definition_note, Expr $first_note) {
  {
    String first_note = %"first expansion: ${$first_note}";
    $c.report_error(
      <macro>, "macro expansion depth exceeds 64", $origin,
      %(${$definition_note} $first_note));
  }
}

static macro Stmt $report.parse.macro_kind(Expr $c) =>
  $c.report_error(
    <parse>, "expected macro result kind before '$'",
    $c.token, NULL);

static macro Stmt $report.parse.macro_result(Expr $c) =>
  $c.report_error(
    <parse>, "macro definition requires a result kind before '$'",
    $c.token, %("write the result kind between 'macro' and the macro name"));

static macro Stmt $report.parse.macro_unknown_kind(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"unknown macro result kind '${$spelling}'",
    $origin, NULL);

static macro Stmt $report.parse.macro_reserved(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"macro name '${$spelling}' is reserved",
    $origin, %("x2c.* is reserved for compiler facilities"));

static macro Stmt $report.macro.name_with(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "'with' cannot be a local macro name",
    $origin, NULL);

static macro Stmt $report.parse.macro_kind_order(Expr $c) =>
  $c.report_error(
    <parse>, "macro result kind belongs after 'macro', before the '$' name",
    $c.token, NULL);

static macro Stmt $report.parse.hole_final(Expr $c) =>
  $c.report_error(
    <parse>, "sequence macro hole must be the final argument",
    $c.token, NULL);

static macro Stmt $report.parse.decorator_singular(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator target parameter must be singular",
    $origin, NULL);

static macro Stmt $report.parse.decorator_kind(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator first parameter has invalid target kind",
    $origin, %("expected Expression, Function, Stmt, Field, Unit,"
      "or NamedType"));

static macro Stmt $report.macro.local_target(
  Expr $c, Expr $target, Expr $origin) =>
  $c.report_error(
    <macro>, %"local decorators cannot target ${$target} syntax",
    $origin, NULL);

static macro Stmt $report.macro.local_result(
  Expr $c, Expr $result_spelling, Expr $origin) =>
  $c.report_error(
    <macro>, %"local macros cannot have ${$result_spelling} results",
    $origin, NULL);

static macro Stmt $report.parse.decorator_target(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator requires a first target parameter",
    $origin, NULL);

static macro Stmt $report.parse.macro_paren_body(Expr $c) =>
  $c.report_error(
    <parse>, "parenthesized macro body requires Expression result or target",
    $c.token, NULL);

static macro Stmt $report.parse.macro_body(Expr $c, Expr $kind, Expr $form) =>
  $c.report_error(
    <parse>, %"${$kind} macro body requires ${$form}", $c.token, NULL);

static macro Stmt $report.parse.hole_untyped(
  Expr $c, Expr $hole_spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"macro hole '${$hole_spelling}' has no inferred kind",
    $origin, %("annotate holes used only by compile-time Lisp"));

static macro Stmt $report.parse.hole_unknown_kind(Expr $c, Expr $spelling) =>
  $c.report_error(
    <parse>, %"unknown macro hole kind '${$spelling}'",
    $c.token, NULL);

static macro Stmt $report.parse.hole_name(Expr $c) =>
  $c.report_error(
    <parse>, "expected macro hole name after '$' or '@'",
    $c.token, NULL);

static macro Stmt $report.parse.hole_duplicate(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"duplicate macro hole '${$spelling}'",
    $origin, NULL);

static macro Stmt $report.parse.splice_expr(Expr $c) =>
  $c.report_error(
    <parse>, "sequence insertion is not legal in an expression slot",
    $c.token, NULL);

static macro Stmt $report.parse.splice_position(Expr $c) =>
  $c.report_error(
    <parse>, "sequence insertion is not legal in this syntax slot",
    $c.token, NULL);

static macro Stmt $report.parse.typed_quotation(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "this quotation cannot declare a name or apply a template",
    $origin,
    %("a typed, Type, or Param quotation builds where it is written"));

static macro Stmt $report.parse.typed_quotation_nested(Expr $c, Expr $origin) {
  {
    String note = "write ${$!T{ ... }} to insert the code it builds";
    $c.report_error(
      <parse>, "typed quotation inside a quotation must be written as a hole",
      $origin, %($note));
  }
}

static macro Stmt $report.parse.hole_ambiguous(
  Expr $c, Expr $spelling, Expr $origin, Expr $first, Expr $also) =>
  $c.report_error(
    <parse>, %"macro hole '${$spelling}' has ambiguous kind",
    $origin, %("first: ${$first}"
      "also: ${$also}"));

static macro Stmt $report.parse.hole_cardinality(
  Expr $c, Expr $sequence, Expr $spelling, Expr $origin) {
  {
    String message = $sequence
      ? %"singular macro hole '${$spelling}' cannot be spliced"
      : %"sequence macro hole '${$spelling}' requires '@'";
    $c.report_error(<parse>, message, $origin, NULL);
  }
}

static macro Stmt $report.macro.keyword_internal(
  Expr $c, Expr $spelling, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"keyword alias cannot name internal macro kind '${$spelling}'",
    $origin, %(${$definition_note}));

static macro Stmt $report.macro.keyword_builtin(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "built-in keyword alias cannot be replaced",
    $origin, NULL);

static macro Stmt $report.parse.keyword_name(Expr $c) =>
  $c.report_error(
    <parse>, "keyword alias requires an identifier",
    $c.token, NULL);

static macro Stmt $report.parse.macro_name(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, $c.peek(1) == <ident>
      ? "expected macro name component after '.'"
      : "expected macro name after '$'",
    $origin, NULL);

static macro Stmt $report.parse.macro_unbound(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"unknown or forward-referenced macro '${$spelling}'",
    $origin, NULL);

static macro Stmt $report.parse.macro_extra_args(Expr $c) =>
  $c.report_error(
    <parse>, "macro invocation has too many arguments",
    $c.token, NULL);

static macro Stmt $report.parse.macro_missing_args(Expr $c) =>
  $c.report_error(
    <parse>, "macro invocation has too few arguments",
    $c.token, NULL);

static macro Stmt $report.macro.argument_contract(Expr $c) =>
  $c.report_error(
    <macro>, "macro argument has no parsing contract",
    $c.token, NULL);

static macro Stmt $report.parse.name_identifier(Expr $c) =>
  $c.report_error(
    <parse>, "Name macro argument requires an identifier",
    $c.token, NULL);

static macro Stmt $report.macro.result_position(
  Expr $c, Expr $spelling, Expr $result,
  Expr $description, Expr $origin) {
  {
    String message =
      %"macro '${$spelling}' has result kind ${$result} and cannot be " +
      %"invoked at ${$description}";
    $c.report_error(<macro>, message, $origin, NULL);
  }
}

static macro Stmt $report.macro.decorator_position(
  Expr $c, Expr $name, Expr $kind, Expr $origin) =>
  $c.report_error(
    <macro>,
    %"decorator '${$name}' targets ${$kind} syntax and cannot be used here",
    $origin, NULL);

static macro Stmt $report.macro.decorator_target(
  Expr $c, Expr $spelling, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"decorator '${$spelling}' requires a following target",
    $origin, %(${$definition_note}));

static macro Stmt $report.macro.decorator_semicolon(
  Expr $c, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, "decorator application must not end with ';'",
    $origin, %(${$definition_note}));

static macro Stmt $report.macro.result_expr(
  Expr $c, Expr $kind, Expr $spelling, Expr $origin, Expr $definition_note) {
  {
    String subject = $kind == <decorator>
      ? %"decorator '${$spelling}'"
      : %"macro '${$spelling}'";
    $c.report_error(
      <macro>, %"$subject cannot be invoked in an expression", $origin,
      $kind == <decorator> ? %(${$definition_note}) : NULL);
  }
}

static macro Stmt $report.macro.decorator_expr(
  Expr $c, Expr $spelling, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"decorator '${$spelling}' requires a following expression",
    $origin, %(${$definition_note}));

static macro Stmt $report.parse.macro_pattern_arity(
  Expr $c, Expr $name, Expr $expected, Expr $origin) =>
  $c.report_error(
    <parse>,
    %"macro pattern '${$name}' takes ${$expected} argument patterns",
    $origin, NULL);

static macro Stmt $report.parse.lisp_unclosed(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "unterminated compile-time Lisp form",
    $origin, NULL);

static macro Stmt $report.macro.lisp_expr(
  Expr $c, Expr $origin, Expr $value) =>
  $c.report_error(
    <macro>, "compile-time Lisp result cannot fill an expression slot",
    $origin, %( "value:" ${$value.repr()} ));

static macro Stmt $report.macro.type_name(
  Expr $c, Expr $message, Expr $origin) =>
  $c.report_error(<macro>, $message, $origin, NULL);

static macro Stmt $report.macro.import_cycle(
  Expr $c, Expr $path, Expr $origin) {
  {
    String display = $c.display_path($path);
    Array notes = [ %"import: $display" ];
    Array parents = $c.import_stack;
    for (int i = 0; i < parents.len(); i++) {
      Var parent = parents[i];
      notes.push(%"from: ${$c.display_path(parent)}");
    }
    $c.report_error(
      <macro>, "compile-time import cycle", $origin, notes.list_free());
  }
}

static macro Stmt $report.macro.import_extension(
  Expr $c, Expr $origin, Expr $path_note) =>
  $c.report_error(
    <macro>, "compile-time import requires .xlisp",
    $origin, $path_note);

static macro Stmt $report.macro.placement(Expr $c, Expr $where) =>
  $c.report_error(
    <macro>, "unknown placement", $c.token, %("where: ${$where.repr()}"));

static macro Stmt $report.macro.builtin_form(Expr $c) =>
  $c.report_error(
    <macro>, "unexpected form in built-in macro source",
    $c.token, NULL);

static macro Stmt $report.macro.lisp_failed(
  Expr $c, Expr $origin, Expr $source, Expr $error) {
  {
    String form_note = %"form: ${$source}",
      error_note = %"error: ${$error.repr()}";
    $c.report_error(
      <macro>, "compile-time Lisp evaluation failed", $origin,
      %($form_note $error_note));
  }
}

static macro Stmt $report.parse.variable_unbound(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"unbound replacement variable '${$spelling}'",
    $origin, NULL);

/* expansion

   Expanding an invocation node matches its capture rows against the
   definition's pattern, adds a binding for each fresh name and member
   hole, fills the template, and binds the result at the invocation's
   position with the invocation as its origin. */

/* One expansion. `direct` holds the bindings that fresh names and member
   holes add to the pattern's captures. */
static typedef struct Expansion {
  Compiler c, List definition, input, template, direct, Token invocation;
} Expansion;

/** Expands canonical macro capture rows and binds the result at `position`.
    `stored` is a `macrodef` or visible macro name. The active expansion stack
    supplies Lisp bindings, source location, and recursion checks; the
    definition's fresh rows allocate invocation-local names. This method does
    not begin a semantic transaction.
*/
List Compiler.expand_macro_invocation_node(
  Compiler c, Var stored, List arguments, Token invocation, Symbol position) {
  Expansion x = {
    .c = c, .definition = _stored_definition(c, stored, invocation),
    .input = arguments, .invocation = invocation};
  int block_scope = x.definition.assoc(<kind>) == <decorator> &&
                    x.definition.assoc(<target>) == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  $let(c.token, invocation) {
    _check(x);
    List result = NULL;
    $let(c.expansion_floor,
         c.macro_stack ? c.expansion_floor : c.names.next_binding)
    $let(c.macro_stack, c.macro_stack) {
      result = _bind_expansion(x, position);
    }
    return result;
  }
}

/* The definition a node names: a visible macro, a local macro, or a Macro
   value whose references bind in this unit. */
static List _stored_definition(
  Compiler c, Var stored, Token invocation) {
  List definition = NULL;
  if (stored.is_atom())
    definition = _lookup(c, Atom.intern(stored.str()), invocation);
  else match (stored)
    case %(local-macro ?name):
      definition = c.sym.lookup_macro(Atom.intern(name.str()));
  return definition ? definition : stored;
}

/* An identical recursive expansion, nesting deeper than 64, or more than
   10000 expansions stops the compile. A leaf template's application
   cannot recurse, so it is neither compared nor counted. An application
   compiler code makes has no invocation token. It lowers the program, so
   it is not counted either. */
static void _check(Expansion &x) {
  Compiler c = x.c;
  int leaf = x.definition.assoc(<leaf>) == 1;
  if (!leaf)
    foreach (List active, c.macro_stack) {
      (List prior, List prior_input, Var bindings, Var site) = active;
      (void) bindings, (void) site;
      if (prior == x.definition && prior_input == x.input)
        _recursion(x);
    }
  if (c.macro_stack.len() >= 64) _too_deep(x);
  if (leaf || !x.invocation) return;
  if (c.macro_count >= 10000)
    $report.macro.expansion_count(c, x.invocation);
  c.macro_count++;
}

static void _recursion(Expansion &x) {
  Atom name = x.definition.assoc(<name>);
  String spelling = name.str();
  List captured = x.input.search_replace(
    %(capture (source ?syntax) *), <?syntax>);
  Var shown = _source_unwrap(captured);
  $report.macro.expansion_recursive(
    x.c,
    spelling, x.invocation, _definition_note(x.definition), shown);
}

static void _too_deep(Expansion &x) {
  /* Compiler-generated applications can have no invocation token. */
  List first = x.c.macro_stack.last().list().car();
  $report.macro.expansion_depth(
    x.c,
    x.invocation, _definition_note(x.definition), _definition_note(first));
}

/* Pushes this expansion's frame on the macro stack, fills the template,
   and binds the result. A failed match binds nothing. */
static List _bind_expansion(Expansion &x, Symbol position) {
  Compiler c = x.c;
  List old_stack = c.macro_stack;
  x.template = x.definition.assoc(<template>);
  /* An application compiler code makes has no invocation token. What it
     authors belongs to the source being lowered, so it carries no anchors
     of its own. */
  if (!x.invocation)
    x.template = x.template.search_replace(%(at m-origin ?node), <?node>);
  List fresh_input = _fresh_names(x, old_stack);
  List match_input = fresh_input
    ? x.input.append(%((fresh @fresh_input))) : x.input;
  List replacement_bindings = match_input.match(
    x.definition.assoc(<pattern>));
  int matched = !!replacement_bindings;
  replacement_bindings = replacement_bindings.append(x.direct);
  List template_bindings = NULL;
  List lisp_bindings = _lisp_bindings(
    replacement_bindings, template_bindings);
  c.macro_stack = %(
    (${x.definition} ${x.input} $lisp_bindings ${x.invocation}) @old_stack
  );
  int expansion_origin = c.record_origin(x.invocation);
  int placed = c.placements.len();
  Ast constructed = matched ? _construct(x, template_bindings) : NULL;
  List result = NULL;
  $let(c.origin, expansion_origin) {
    result = c.bind_syntax(
      matched ? constructed : void,
      position, c.return_type);
  }
  c.close_placements(placed, result);
  return result;
}

/* Allocates each fresh name of the definition. A name compile-time Lisp
   reads joins the match input as a Name capture row; the others, with the
   member holes, bind directly. Returns the Name rows. */
static List _fresh_names(Expansion &x, List old_stack) {
  Compiler c = x.c;
  Map file_locals = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = old_stack ? old_stack.last().list()[3] : x.invocation;
  if (c.sym.at_file_scope()) _file_scope_locals(%(${x.template}), file_locals);
  Array fresh_values = [];
  foreach (List fresh, x.definition.assoc(<fresh>).list()) {
    Var (binder, spelling, lisp) = fresh;
    Token owner = binder in file_locals ? root : NULL;
    if (lisp.int()) {
      List binding = _introduced_binding(c, spelling.str(), owner);
      List hole = _hole(binder, <name>, 0);
      fresh_values.push(_capture_row_project(c, hole, %($binding), 0));
    }
    else
      x.direct = cons(
        %($binder ${_private_name(c, spelling.str(), owner)}), x.direct);
  }
  List members = _member_bindings(
    c, x.definition.assoc(<parameters>), x.input);
  x.direct = x.direct.append(members);
  return fresh_values.list_free();
}

/* A Name hole in a member position supplies the captured spelling, so a
   template local passed there keeps the spelling its source wrote. */
static List _member_bindings(
  Compiler c, List parameters, List input) {
  List captures = NULL, bindings = NULL;
  match (input) {
    case %(args *rows): captures = rows;
    case %(target (args *rows) ?): captures = rows;
  }
  foreach (List parameter, parameters) {
    List capture = captures.car();
    captures = captures.cdr();
    if (parameter.assoc(<kind>) != <name> ||
        parameter.assoc(<sequence>).int())
      continue;
    Var member = _hole_key(parameter, "member");
    bindings = cons(
      %($member ${_member_spelling(c, capture.assoc(<value>))}), bindings);
  }
  return bindings;
}

/* The spelling a Name hole's value supplies in a member position: the
   source spelling of a renamed local or a binding, or an `x2c_ident`
   value's own. */
static Var _member_spelling(Compiler c, Var value) {
  Var spelling;
  match (value) case %("x2c.ident" (!is ?name type string)): return name;
  if (value is not <list>) return value;
  if (c.semantic_binding_facts().try_get(%(source-spelling $value), spelling))
    return spelling;
  String name = Ast.binding_spelling(value);
  return name ? name : value;
}

/* The bindings compile-time Lisp sees: the author's binders. The template
   receives the `__macro_` binders the compiler makes, so an author binder
   spelled in a template literal, such as a catch pattern's `?cause`, stays
   literal. */
static List _lisp_bindings(List bindings, List &template_bindings) {
  Array lisp = [], compiler = [];
  foreach (List pair, bindings) {
    Var binder = pair.car();
    if (binder.is_binder() &&
        !binder.str().startswith("?__macro_") &&
        !binder.str().startswith("*__macro_"))
      lisp.push(pair);
    else
      compiler.push(pair);
  }
  template_bindings = compiler.list_free();
  return lisp.list_free();
}

/* Declaration results and collected Unit results retain their declarations
   in one bundle, as does a NamedType decorator. */
static Ast _construct(Expansion &x, List bindings) {
  List definition = x.definition;
  Ast constructed = x.template.replace(bindings);
  if (constructed &&
      (definition.assoc(<kind>) == <decl-unit> ||
       (x.c.shallow && definition.assoc(<kind>) == <unit>) ||
       definition.assoc(<target>) == <named-type>)) {
    List rows = constructed.car() == <seq>
              ? constructed.cdr() : %($constructed);
    constructed = %(declaration-bundle (rows @rows));
  }
  return constructed;
}

/** Resolves a stored macro invocation marker to its source token.
    Nested template markers use the active expansion's invocation; unresolved
    markers return NULL.
*/
Token Compiler.macro_invocation_site(Compiler c, Var site) {
  if (site is <token>) return site;
  if (site != <m-invoke> || !c.macro_stack) return NULL;
  List active = c.macro_stack.car();
  (Var definition, Var input, Var bindings, Token invocation) = active;
  (void) definition, (void) input, (void) bindings;
  return invocation;
}

/* expansion names

   A fresh name gets a private spelling. At file scope a declaration with
   external or no linkage can reach another unit through a header or an
   interface, so its spelling is stable: collection and full parsing expand
   the same invocation to the same spelling. */

static List _introduced_binding(
  Compiler c, String source, Token root) =>
  c.sym.introduce(
    root ? _file_scope_name(c, root, source)
         : c.fresh_name(%"macro_$source"));

/* A template local's name, which keeps its source spelling. */
static List _private_name(Compiler c, String source, Token root) {
  List binding = _introduced_binding(c, source, root);
  c.set_fact(%(source-spelling $binding), source);
  return binding;
}

/* The spelling names the owning unit and the root invocation's offset, and
   counts repeats of the same name there. */
static String _file_scope_name(
  Compiler c, Token root, String source) {
  String key = %"macro:${_scope_owner(c)}:${root.pos}:$source";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  c.names.counters[key] = count + 1;
  c.names.issued++;
  String digest = "%08x".printf(%"$key:$count".hash());
  return %"_x2c_gensym_macro_${source}_$digest";
}

/* The unit's owner spelling, cached per file and package. */
static String _scope_owner(Compiler c) {
  String owner = NULL;
  $memo(c.names.file_scope_owners, %(${c.filename} ${c.package}), owner) {
    owner = c.filename ? _owner_spelling(c) : "";
  }
  return owner;
}

/* Home and package paths stay portable; other paths use their canonical
   absolute identity. */
static String _owner_spelling(Compiler c) {
  String path = c.canonical_path(Path.absolute(c.filename));
  String owner = Compiler.portable_path(path);
  Var package_root = c.package ? c.package_roots[c.package] : void;
  if (package_root is not <string>) return owner;
  String prefix = %"${c.canonical_path(Path.absolute(package_root))}/";
  if (!path.startswith(prefix)) return owner;
  return %"package:${c.package}/${path[prefix.len():]}";
}

/* Collects the template locals that a file-scope row declares with external
   linkage or none: objects, functions, typedefs, tags, and enumerators,
   including those a nested invocation declares from this template's names. */
static void _file_scope_locals(List rows, Map locals) {
  foreach (Var row, rows) match (row) {
    case %((!or at src) ? ?inner): _file_scope_locals(%($inner), locals);
    case %(api-source ? ? ?inner): _file_scope_locals(%($inner), locals);
    case %(seq *inner): _file_scope_locals(inner, locals);
    case %(macro-invoke ((!quote !quote) ?(List definition))
           ?(List input) ?): {
      Map declared = {};
      _file_scope_locals(%(${definition.assoc(<template>)}), declared);
      List bindings = NULL;
      input.try_match(definition.assoc(<pattern>), bindings);
      foreach (List pair, bindings)
        if (pair.car() in declared && pair.cadr().is_binder())
          locals[pair.cadr()] = 1;
    }
    case %(function ?type (bind ?binder ?) ?):
      if (binder.is_binder() && !type.type().is_static()) locals[binder] = 1;
    case %((!set ?kind (!or declare typedef)) ?type (bindings *rows)): {
      match (type) case %(* (!or struct union enum) ?tag *):
        if (tag.is_binder()) locals[tag] = 1;
      match (type) case %(* enum ? (*members) *):
        _file_scope_declarators(members, locals);
      if (kind == <typedef> || !type.type().is_static())
        _file_scope_declarators(rows, locals);
    }
  }
}

static void _file_scope_declarators(List declarators, Map locals) {
  foreach (Var declarator, declarators) match (declarator)
    case $source_declarator_row(%(?binder ?)):
      if (binder.is_binder()) locals[binder] = 1;
}

/* macro definitions

   Reading a definition takes its result kind, name, signature holes, and
   body. Its signature is visible before the body is read, so the body can
   invoke the macro it defines. */

/* One definition while it is read. `nested` marks a definition inside a
   template, which stays syntax until the template's expansion binds it.
   `locals` holds the template's own declarations, newest first under
   `<order>`, and `captures` the outer names a local macro's body reads. */
static typedef struct Definition {
  Compiler c, Token start;
  Atom name, Symbol kind;
  List target, parameters, template, fresh, captures, pattern, rebuild, type;
  List origin, String file, Map locals, Array using;
  int anonymous, local, nested, quotation, leaf, storage;
} Definition;

/** Parses the macro definition at the current token into a `macrodef` `List`.
    A source-level definition is published immediately; a definition inside a
    template remains syntax for later binding at its expansion site.
*/
List Compiler.parse_macro_definition(Compiler c) {
  Definition d = {.c = c, .start = c.token};
  d.storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  _head(d);
  _naming(d);
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  // A rejected signature must not leave later declarations as templates.
  $let(c.macro_holes, {}) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    d.using = [];
    _signature(d);
    _arrow(d);
    _announce(d);
    _body(d);
  }
  _finish(d);
  return _publish(d);
}

/* Reads the result kind. A local definition names itself without `$`, and
   an anonymous one has no name to read. */
static void _head(Definition &d) {
  Compiler c = d.c;
  if (c.peek(0) == <$>)
    $report.parse.macro_result(c);
  d.anonymous = c.peek(0) == <ident> && c.peek(1) == <(>;
  d.local = d.anonymous || (c.peek(0) == <ident> &&
            c.peek(1) == <ident> && c.peek(2) == <(>);
  if (c.peek(0) != <ident> || (!d.local && c.peek(1) != <$>))
    $report.parse.macro_kind(c);
  Token token = c.token;
  c.next();
  d.kind = _result_kind_token(c, token);
}

static Symbol _result_kind_token(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (!category || !category.result)
    $report.parse.macro_unknown_kind(c, token.text, token);
  return category.result;
}

static void _naming(Definition &d) {
  Compiler c = d.c;
  if (d.anonymous) d.name = Atom.intern(c.fresh_name("anonymous_macro"));
  else if (d.local) {
    d.name = Atom.intern(c.token.text);
    c.next();
  }
  else d.name = _name(c);
  String spelling = d.name.str();
  if (d.local && d.name == <with>)
    $report.macro.name_with(c, d.start);
  if (spelling.startswith("x2c.") && !c.builtin_defs &&
      !Compiler.is_prelude_source(c.source_path(c.filename)))
    $report.parse.macro_reserved(c, spelling, d.start);
}

/* Reads the parameter holes, then a `using` clause. A decorator's first
   parameter is its target. */
static void _signature(Definition &d) {
  Compiler c = d.c;
  Array params = [];
  c.expect(<(>);
  if (!c.test(<)>)) {
    do _parameter(d, params, _signature_hole(c)); while (c.test(<,>));
    c.expect(<)>);
  }
  d.parameters = params.list_free();
  _check_signature(d);
  if (c.take_word("using")) _using_clause(c, d.using);
  if (c.peek(0) == <:>)
    $report.parse.macro_kind_order(c);
}

static void _parameter(Definition &d, Array params, List hole) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target) _take_target(d, hole);
  else params.push(hole);
  if (hole.assoc(<sequence>).int() && c.peek(0) == <,>)
    $report.parse.hole_final(c);
}

/* A Unit target's source stays visible to compile-time Lisp, whose
   template slots find the target hole under `(target)`. */
static void _take_target(Definition &d, List hole) {
  Compiler c = d.c;
  if (!_decorator_target(hole.assoc(<kind>)))
    $report.parse.decorator_kind(c, d.start);
  if (hole.assoc(<sequence>).int())
    $report.parse.decorator_singular(c, d.start);
  d.target = hole;
  if (hole.assoc(<kind>) != <unit>) return;
  c.macro_holes[%(source ${hole.assoc(<binder>)})] = 1;
  c.macro_holes[%(target)] = hole;
}

/* A local macro produces no file-scope syntax, directly or through the
   target it decorates. */
static void _check_signature(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target)
    $report.parse.decorator_target(c, d.start);
  if (!d.local) return;
  if (d.kind == <unit> || d.kind == <decl-unit>) {
    String result_spelling = _kind_spelling(d.kind);
    $report.macro.local_result(c, result_spelling, d.start);
  }
  if (d.kind != <decorator>) return;
  Symbol kind = _target_kind(d);
  if (kind == <function> || kind == <unit> || kind == <named-type>) {
    String target = _kind_spelling(kind);
    $report.macro.local_target(c, target, d.start);
  }
}

/* An Expression result, or a decorator of an expression, has an `=>`
   body. A Stmt result has a braced body or an `=>` expression statement.
   Every other result has a braced body after an optional `=>`. */
static void _arrow(Definition &d) {
  Compiler c = d.c;
  if (_has_expression_body(d)) {
    if (c.peek(0) == <"{">) _body_error(d);
    c.expect(<=>);
    c.expect(<">">);
    return;
  }
  if (c.peek(0) == <=>) {
    c.expect(<=>);
    c.expect(<">">);
    if (d.kind == <block-item>) return;
  }
  if (c.peek(0) == <(>)
    $report.parse.macro_paren_body(c);
  if (c.peek(0) != <"{">) _body_error(d);
}

static int _has_expression_body(Definition &d) =>
  d.kind == <expression> ||
  (d.kind == <decorator> && _target_kind(d) == <expr>);

static Symbol _target_kind(Definition &d) {
  if (!d.target) return 0;
  return d.target.assoc(<kind>);
}

/* Reports the body forms the result kind accepts. */
static void _body_error(Definition &d) {
  String form = _has_expression_body(d) ? "'=> expression;'"
              : d.kind == <block-item> ? "'{ ... }' or '=> expression;'"
              : "'{ ... }'";
  $report.parse.macro_body(d.c, _kind_spelling(d.kind), form);
}

/* Records where the definition stands and shows its signature, so an
   invocation inside the body names this macro. */
static void _announce(Definition &d) {
  Compiler c = d.c;
  (void) c.record_origin(d.start);
  d.origin = c.token_location(d.start);
  d.file = Compiler.portable_path(c.source_path(c.filename));
  _show(d, _definition_node(d));
}

/* Reads the body in its own scope, with the kinds it infers for the holes.
   A local macro records the outer names its body captures. A `return` in
   the body is typed where the expansion lands, as at file scope; a
   retained rebuild keeps the type a `return` records. Collection reads the
   whole template, initializers included, as the full parse does. */
static void _body(Definition &d) {
  Compiler c = d.c;
  $let(c.shallow, 0)
  $let(c.return_type, NULL)
  $let(c.runtime_literals, c.runtime_literals || d.anonymous)
  $let(c.local_macro_captures, d.local ? {} : NULL)
  $let(c.local_macro_capture_scopes, c.sym.scope_count()) {
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    d.template = _read_body(d);
    if (d.quotation) d.parameters = _quoted_holes(c);
    d.parameters = _parameter_rows(c, d.parameters);
    d.captures = _recorded(c.local_macro_captures);
  }
}

/* A Stmt result's body after `=>` is one arrow statement. */
static List _read_body(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <type> || d.kind == <param>) return _part_body(d);
  if (_has_expression_body(d)) return _expression_body(d);
  if (c.peek(0) == <"{">) return _parse_body(c, _body_kind(d), d.using);
  return _arrow_statement(c, d.anonymous);
}

/* A Stmt arrow's statement is a Stmt macro or decorator invocation, or else
   an expression statement. An anonymous macro's statement omits its `;`,
   which ends the enclosing declaration, and so does a decorator's target
   there. */
static List _arrow_statement(Compiler c, int open) {
  List macro = _target_at(c, <statement>, open);
  if (macro) return macro;
  List expression = c.parse_expression();
  if (!open) c.expect(<;>);
  return %(seq (stmnt $expression));
}

/* The legacy form is parenthesized, and a quotation's body is a
   parenthesized or braced group. The canonical form ends at `;`, which an
   anonymous macro omits. */
static List _expression_body(Definition &d) {
  Compiler c = d.c;
  if (d.quotation || _legacy_expression_body(c)) {
    int braced = d.quotation && c.peek(0) == <"{">;
    c.expect(braced ? <"{"> : <(>);
    List replacement = c.parse_expression();
    c.expect(braced ? <"}"> : <)>);
    return replacement;
  }
  List replacement = c.parse_expression();
  if (!d.anonymous) c.expect(<;>);
  return replacement;
}

/* A Type quotation's body is a type name, and a Param quotation's body is
   one parameter. */
static List _part_body(Definition &d) {
  Compiler c = d.c;
  c.expect(<"{">);
  List body = NULL;
  if (d.kind == <param>) {
    body = c.try_parse_macro_slot(<param>);
    if (!body) body = c.parse_parameter();
  }
  else c.parse_type_operand(&body);
  c.expect(<"}">);
  return body;
}

/* A decorator's body produces what its target is, and a Function or
   Block target's body is block items. */
static Symbol _body_kind(Definition &d) {
  if (d.kind != <decorator>) return d.kind;
  Symbol target = _target_kind(d);
  return target == <function> || target == <block> ? <block-item> : target;
}

/* The entries a map lists under `<order>`, oldest first, or NULL. */
static List _recorded(Map m) {
  Var order = m != NULL ? m[<order>] : void;
  return order is <list> ? order.list().reverse() : NULL;
}

/* definition templates

   Finishing a definition turns its body into the stored template, derives
   the rows an invocation needs, and makes the `macrodef` visible. */

/* Turns the body into the stored template, then derives the fresh rows
   and pattern an invocation needs. Parsed literal names carry
   definition-only identities, so the template stores binders instead and
   each expansion allocates one fresh identity per literal spelling. */
static void _finish(Definition &d) {
  d.template = _slot_binders(_wrap(d));
  Map bindings = {};
  if (_target_kind(d) == <unit>) _constructed_names(d, bindings);
  Array locals = _local_binders(d, bindings);
  d.template = _replace_bindings(d.template, bindings);
  _check_kinds(d);
  d.fresh = _fresh_rows(d, locals);
  d.pattern = _invocation_pattern(d);
  Map uses = _binder_uses(d.template);
  if (!(void *) uses) return;
  d.rebuild = %(${_rebuild_template(d)} ${_rebuild_keys(d, uses)});
  d.leaf = !d.nested && _uses_holes_once(d, uses);
}

/* A Function decorator's body becomes a function with the target's return
   type and declarator, and an Expression decorator's body a parenthesized
   expression. */
static List _wrap(Definition &d) {
  List replacement = d.template;
  if (d.kind != <decorator>) return replacement;
  Symbol target = _target_kind(d);
  if (target == <expr>) return %(expr (<macro-expr>) (parens $replacement));
  if (target != <function>) return replacement;
  Var return_binder = _hole_key(d.target, "return");
  Var declarator_binder = _hole_key(d.target, "declarator");
  match (replacement)
    case %(seq *body):
      return %(
        seq
          (function $return_binder $declarator_binder (block @body))
      );
  return replacement;
}

/* Each nested `(macro-bind BINDER)` slot becomes its binder. A whole slot
   keeps a List shell: `expr` for an expression, `macro-bind` otherwise. */
static List _slot_binders(List replacement) {
  match (replacement) case %(macro-bind ?): return replacement;
  List bindings;
  Var expression_slot = %(
    expr (<macro-expr>) (macro-bind ?binder)
  );
  if (replacement.try_match(expression_slot, bindings))
    return replacement.search_replace(%(macro-bind ?binder), <?binder>);
  return replacement.search_replace(
    %(!or
      (expr (<macro-expr>) (macro-bind ?binder))
      (macro-bind ?binder)),
    <?binder>
  );
}

/* A Unit target requires construction, which each Name hole's value
   carries. */
static void _constructed_names(Definition &d, Map bindings) {
  Var required = _hole_key(d.target, "construction");
  foreach (List parameter, d.parameters)
    if (parameter.assoc(<kind>) == <name>) {
      Var name = Macro.binder(parameter.assoc(<binder>), "value", 0);
      bindings[name] = %($required $name);
    }
}

/* Binds each template local to its binder and returns the locals that get
   fresh names. A tag the template only references keeps its public
   spelling. */
static Array _local_binders(Definition &d, Map bindings) {
  Array fresh = [];
  foreach (Var identity, _recorded(d.locals)) {
    if (%(provisional $identity) in d.locals) {
      bindings[identity] = d.locals[identity];
      continue;
    }
    bindings[identity] = _local_binder(
      identity, %(tag-local $identity) in d.locals);
    fresh.push(identity);
  }
  return fresh;
}

static void _check_kinds(Definition &d) {
  foreach (List hole, d.parameters)
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      $report.parse.hole_untyped(d.c, hole_spelling, d.start);
    }
}

/* Each `using` hole and each template local gets a fresh name per
   expansion; the last field marks the names compile-time Lisp reads. */
static List _fresh_rows(Definition &d, Array locals) {
  Array fresh = [];
  foreach (Var binder, d.using.list_free())
    fresh.push(%($binder ${binder.str()[1:]} 1));
  foreach (Var identity, locals) {
    Var spelling = d.locals[identity];
    Atom binder = _local_binder(
      identity, %(tag-local $identity) in d.locals);
    fresh.push(%($binder $spelling 0));
  }
  return fresh.list_free();
}

/* The number of uses of each binder in a template, or NULL when the
   template can apply templates: it holds a slot, a nested invocation or
   definition, or a Macro value. Such a template has no rebuild row, so a
   definition holds no second copy of another definition. */
static Map _binder_uses(List template) {
  Map uses = {};
  List syntax;
  $ast.walk(template, syntax) {
    match (syntax)
      case %((!or macro-invoke macro-slot meta-call tpl-call macro-value
                  "x2c.template" macrodef syntax-recipe declaration-recipe)
             *):
        return NULL;
    foreach (Var item, syntax)
      if (item.is_binder()) uses[item] = uses.getdefault(item, 0) + 1;
  }
  return uses;
}

/* The template a rebuild fills. An Expr hole's binder stands for its whole
   expression, without the `(expr (<macro-expr>) ...)` shell, and no
   template-origin wrapper remains, because a rebuild opens no invocation. */
static List _rebuild_template(Definition &d) {
  Map expressions = {};
  foreach (List hole, d.parameters)
    if (hole.assoc(<kind>) == <expr>)
      expressions[_hole_key(hole, "expression")] = 1;
  return _rebuild_syntax(d.template, expressions);
}

static Var _rebuild_syntax(Var syntax, Map expressions) {
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    case %(at m-origin ?node): return _rebuild_syntax(node, expressions);
    case %(expr (<macro-expr>) ?binder):
      if (binder in expressions) return binder;
  }
  List child;
  $ast.rewrite_children(
    syntax.list(), child, _rebuild_syntax(child, expressions));
}

/* For each hole, the target's last, the binders of the projections the
   template uses, in capture-row order: source, value, expression, and
   splice, then a Function value's return type and declarator. `?` marks a
   projection the template does not use. */
static List _rebuild_keys(Definition &d, Map uses) {
  List holes = d.target ? d.parameters.append(%(${d.target})) : d.parameters;
  Array keys = [];
  foreach (List hole, holes) {
    Array used = [];
    foreach (String projection,
             %("source" "value" "expression" "splice" "return" "declarator"))
      used.push(_used(uses, hole, projection, <?>));
    keys.push(used.list_free());
  }
  return keys.list_free();
}

/* Whether the template uses each hole, the target's included, at most
   once. A leaf template applies no templates and uses each hole once, so
   its application cannot recurse or multiply the applications its
   arguments hold. A definition inside a template is never a leaf, because
   its template can hold the enclosing template's holes. */
static int _uses_holes_once(Definition &d, Map uses) {
  List holes = d.target ? cons(d.target, d.parameters) : d.parameters;
  foreach (List hole, holes) {
    int count = 0;
    foreach (String projection,
             %("source" "value" "expression" "splice" "member" "return"
               "declarator" "construction"))
      count += uses.getdefault(_hole_key(hole, projection), 0).int();
    if (count > 1) return 0;
  }
  return 1;
}

/* Makes the finished definition visible in place of its signature. */
static List _publish(Definition &d) {
  List node = _definition_node(d);
  $let(d.c.token, d.start) _show(d, node);
  return node;
}

/* A named local macro is visible in its scope, and a global one unless a
   template holds it. */
static void _show(Definition &d, List node) {
  if (d.local && !d.anonymous) d.c.sym.define_macro(d.name, node);
  else if (!d.local && !d.nested) d.c.publish_macro_definition_node(node);
}

static List _definition_node(Definition &d) {
  Compiler c = d.c;
  List definition = %(
    macrodef
    (name ${d.name})
    (kind ${d.kind})
    (target ${_target_kind(d)})
    (targetp ${d.target})
    (parameters ${d.parameters})
    (fresh ${d.fresh})
    (captures ${d.captures})
    (pattern ${d.pattern})
    (template ${d.template})
    (rebuild ${d.rebuild})
    (leaf ${d.leaf})
    (origin ${d.origin})
    (file ${d.file})
    (builtin ${c.builtin_defs})
    (local ${d.local})
    (static ${d.storage})
  );
  return definition;
}

/* signature holes

   A signature declares each hole's binder, its optional kind, and whether
   it takes a sequence. A `using` hole is a Name that compile-time Lisp
   fills with a fresh identifier. */

/* A parameter: an optional kind, `$NAME` or sequence `@NAME`. */
static List _signature_hole(Compiler c) {
  Symbol kind = 0;
  if (c.peek(0) == <ident> && (c.peek(1) == <$> || c.peek(1) == <@>))
    kind = _hole_kind(c);
  int sequence = c.peek(0) == <@>;
  Token token = _hole_name_token(c, sequence ? <@> : <$>);
  return _declare_hole(c, token, kind, sequence);
}

static Symbol _hole_kind(Compiler c) {
  const MacroCategory *category = _category(c.token.text);
  Symbol kind = category ? category.hole : 0;
  if (!kind) {
    String spelling = c.token.text;
    $report.parse.hole_unknown_kind(c, spelling);
  }
  c.next();
  return kind;
}

static Token _hole_name_token(Compiler c, Symbol prefix) {
  c.expect(prefix);
  if (c.peek(0) != <ident>)
    $report.parse.hole_name(c);
  Token name = c.token;
  c.next();
  return name;
}

static List _declare_hole(
  Compiler c, Token token, Symbol kind, int sequence) {
  String spelling = token.text;
  if (_hole_record(c, Atom.intern(spelling)))
    $report.parse.hole_duplicate(c, spelling, token);
  return _record_hole(c, spelling, kind, sequence);
}

static List _record_hole(
  Compiler c, String spelling, Symbol kind, int sequence) {
  List hole = _hole(
    Atom.intern(sequence ? %"*$spelling" : %"?$spelling"),
    kind, sequence);
  c.macro_holes[Atom.intern(spelling)] = hole;
  return hole;
}

static void _using_holes(Compiler c, Array binders) {
  do binders.push(_using_hole(c).assoc(<binder>)); while (c.test(<,>));
}

static List _using_hole(Compiler c) =>
  _declare_hole(c, _hole_name_token(c, <$>), <name>, 0);

static List _hole(Atom binder, Symbol kind, int sequence) => %(
    macro-param
    (binder $binder)
    (kind $kind)
    (sequence $sequence)
  );

static List _hole_record(Compiler c, Atom name) {
  Var stored;
  if (!c.macro_holes.try_get(name, stored)) return NULL;
  return stored;
}

/* The final hole records, with the kinds the body inferred. */
static List _parameter_rows(Compiler c, List parameters) {
  Array rows = [];
  foreach (List parameter, parameters)
    rows.push(_hole_record(c, _hole_name(parameter)));
  return rows.list_free();
}

static Atom _hole_name(List hole) {
  String binder = hole.assoc(<binder>).str();
  return Atom.intern(binder[1:]);
}

/* macro categories

   Every syntactic category a definition names, as a hole kind, a result
   kind, or a decorator target, with the kinds each spelling selects.
   Spellings match without regard to case. `named` marks the row whose
   spelling names its hole or result kind in diagnostics. */

static typedef struct MacroCategory {
  const char *spelling;
  Symbol hole, result;
  int target, Symbol named;
} MacroCategory;

static const MacroCategory macro_categories[] = {
  { "Expr",          <expr>,       <expression>, 1, <hole> },
  { "Expression",    <expr>,       <expression>, 1, <result> },
  { "Stmt",          <block>,      <block-item>, 1, <both> },
  { "Field",         <field>,      <field>,      1, <both> },
  { "Entry",         <map-entry>,  <map-entry>,  0, <both> },
  { "Enumerator",    <enumerator>, <enumerator>, 0, <both> },
  { "Unit",          <unit>,       <unit>,       1, <both> },
  { "Declaration",   0,            <decl-unit>,  0, <result> },
  { "Decorator",     0,            <decorator>,  0, <result> },
  { "Function",      <function>,   0,            1, <hole> },
  { "NamedType",     <named-type>, 0,            1, <hole> },
  { "Type",          <type>,       0,            0, <hole> },
  { "Decl",          <decl>,       0,            0, <hole> },
  { "DeclaratorRow", <decl-row>,   0,            0, <hole> },
  { "Name",          <name>,       0,            0, <hole> },
  { "Literal",       <literal>,    0,            0, <hole> },
  { "Param",         <param>,      0,            0, <hole> },
  { "Catch",         <catch>,      0,            0, <hole> },
  { "Captures",      <captures>,   0,            0, <hole> },
  { "MatchRow",      <match-row>,  0,            0, <hole> }
};

#define MACRO_CATEGORY_COUNT \
  (int) (sizeof(macro_categories) / sizeof(macro_categories[0]))

static const MacroCategory *_category(String spelling) {
  String key = spelling.lower();
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++)
    if (key == String.new(macro_categories[i].spelling).lower())
      return &macro_categories[i];
  return NULL;
}

static int _decorator_target(Symbol hole) {
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++)
    if (macro_categories[i].hole == hole) return macro_categories[i].target;
  return 0;
}

static String _kind_spelling(Symbol kind) {
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++) {
    const MacroCategory *category = &macro_categories[i];
    if ((category.hole == kind && category.named != <result>) ||
        (category.result == kind && category.named != <hole>))
      return category.spelling;
  }
  return kind.str().capitalize();
}

/* definition bodies

   A braced body opens with any `using` lines and reads the items its
   result kind produces as a `seq`. */

static List _parse_body(Compiler c, Symbol result_kind, Array using) {
  c.expect(<"{">);
  _parse_body_using(c, using);
  if (result_kind == <block-item>)
    return cons(<seq>, c.parse_block_items(0).cdr());
  if (result_kind == <field>)
    return _closed_seq(
      c, c.peek(0) == <"}"> ? NULL : c.parse_fields(%(struct ())));
  if (result_kind == <enumerator>)
    return _closed_seq(c, c.parse_enumerators(%(enum ())));
  if (result_kind == <map-entry>) return _closed_seq(c, c.parse_map_entries());
  return _closed_seq(c, _unit_items(c));
}

/* `using $name;` makes a fresh private name for each expansion. `using
   name;` keeps the file-scope declaration `name` has where the macro is
   written, wherever the expansion lands. */
static void _parse_body_using(Compiler c, Array binders) {
  while (c.at_word("using") &&
         (c.peek(1) == <$> || c.peek(1) == <ident>)) {
    c.next();
    _using_clause(c, binders);
    c.expect(<;>);
  }
}

/* One `using` list: fresh names, or file-scope names. An Expression
   macro, which has no braced body, writes it after its signature. */
static void _using_clause(Compiler c, Array binders) {
  if (c.peek(0) == <$>) _using_holes(c, binders);
  else _using_names(c);
}

static void _using_names(Compiler c) {
  do {
    String spelling = c.token.text;
    c.expect(<ident>);
    /* A name no x2c declaration supplies is a native name left to C. */
    List binding = c.sym.reference_global(%($spelling));
    c.macro_holes[%(using ${Ast.binding_spelling(binding)})] = binding;
  } while (c.test(<,>));
}

static List _closed_seq(Compiler c, List rows) {
  c.expect(<"}">);
  return %(seq @rows);
}

/* Directives between the items stay in the body. */
static List _unit_items(Compiler c) {
  Array items = [];
  while (c.peek(0) != <"}">) {
    foreach (Var directive, c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  return items.list_free();
}

static int _legacy_expression_body(Compiler c) {
  if (c.peek(0) != <(>) return 0;
  Token after = c.token.after_group();
  return after.type != <;> && !_extends_expression(after);
}

/* A leading parenthesized group is the complete legacy expression body when
   the following token cannot extend that expression. A semicolon always
   selects the canonical form. */
static int _extends_expression(Token token) {
  Symbol type = token.type;
  return type.binary_precedence() || type.is_assignment_op() ||
         type in operand_continuations ||
         (type == <ident> && (token.text == "is" || token.text == "in"));
}

/* After a complete operand, a postfix operator, a brace initializer, the
   conditional, or a comma continues the expression. */
static const SymbolSet operand_continuations =
  %<<"[" "(" "{" "->" "." "++" "--" "?" ",">>;

/* template holes

   A named hole, Lisp slot, or computed call fills a syntax role. `$` inserts
   one value and `@` splices a sequence. The first role an untyped hole fills
   gives it its kind. */

/** Parses a macro hole or Lisp slot for `role` while reading a template.
    Returns role-shaped syntax containing `(macro-bind ...)` or
    `(macro-slot ...)`, or NULL when ordinary grammar owns the current tokens;
    successful parsing advances the cursor.
*/
List Compiler.try_parse_macro_slot(Compiler c, Symbol role) {
  if (!c.macro_holes) return NULL;
  if (c.peek(0) == <@> && !c.peek_macro_hole())
    return _meta_call_slot(c, role);
  String name;
  if (role != <expression> && role != <statement> &&
      c.peek(0) == <$> && _scan_name(c, name).type == <(> &&
      !c.peek_macro_hole() && !_peek_invocation(c))
    return _meta_call_slot(c, role);
  if (c.peek(0) == <"$("> || c.peek(0) == <"@(">)
    return _lisp_slot(c, role);
  return _hole_slot(c, role);
}

/* The callable supplies syntax in the requested insertion position. */
static List _meta_call_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <@>;
  if (sequence && !(role in sequence_roles))
    $report.parse.splice_position(c);
  if (!sequence && (role == <block> || role in declaration_roles))
    return NULL;
  List definition = _peek_invocation(c);
  if (sequence && definition && _result_kind(definition) != <expression>)
    return _target_at(c, _slot_position(role), 1);
  List call = c.try_parse_macro_expression();
  return %(macro-slot $sequence $call);
}

/* A result macro keeps the ordinary position's kind and decorator rules. */
static Symbol _slot_position(Symbol role) =>
  role in %<<unit block field enumerator map-entry>> ? role : <expression>;

/* A Lisp slot fills a declaration slot only when @ splices it. A block
   item that continues into a declaration, and a statement, keep the
   ordinary grammar. */
static List _lisp_slot(Compiler c, Symbol role) {
  int splice = c.peek(0) == <"@(">;
  if (splice && !(role in sequence_roles))
    $report.parse.splice_position(c);
  if (role in declaration_roles && !splice) return NULL;
  if (!splice && role == <block> && c.macro_lisp_starts_declaration())
    return NULL;
  if (role == <statement>) return NULL;
  if (role == <expression>) return c.parse_macro_lisp_expression();
  return _parse_lisp_slot(c, role);
}

/* A hole fills a slot whose role its kind accepts. A sequence hole of no
   kind takes the slot's kind. */
static List _hole_slot(Compiler c, Symbol role) {
  List hole = c.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && c.after_hole().type == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    $report.parse.splice_expr(c);
  if (!(role in untyped_roles)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && c.peek(0) != <@> && c.peek(0) != <"@{"> &&
        !_quoted_role(c, role))
      return NULL;
    if (kind && !_kind_accepts_role(kind, role)) return NULL;
  }
  List syntax = _parse_hole(c, role);
  return syntax && role == <expression>
       ? %(expr (<macro-expr>) $syntax) : syntax;
}

static const SymbolSet declaration_roles =
  %<<field enumerator map-entry unit>>;
static const SymbolSet sequence_roles =
  %<<argument block field enumerator map-entry param unit catch match-row
     decl-row>>;
static const SymbolSet untyped_roles = %<<expression argument type>>;
static const SymbolSet quoted_roles = %<<statement block name param>>;

/** Returns the registered hole descriptor for a named or expression hole.
    `$NAME` and `${expression}` insert one value; `@NAME` and `@{expression}`
    splice a sequence. Returns NULL without consuming a non-hole spelling.
*/
List Compiler.peek_macro_hole(Compiler c) {
  Symbol prefix = c.peek(0);
  if (prefix == <"@{">) return _expression_hole(c, c.token);
  if (prefix != <$> && prefix != <@>) return NULL;
  if (c.peek(1) == <"{">) return _expression_hole(c, c.token);
  if (c.peek(1) != <ident>) return NULL;
  Token name = Token.skip_trivia(c.token + 1);
  List hole = _hole_record(c, Atom.intern(name.text));
  return hole ? hole : _quoted_hole(c, name.text, c.token);
}

/** Returns the token after the named or expression hole at the cursor.
    Consumes neither its `$` or `@` prefix nor its optional braces.
*/
Token Compiler.after_hole(Compiler c) {
  if (c.peek(0) == <"@{">) return c.token.after_group();
  Token next = Token.skip_trivia(c.token + 1);
  return next.type == <"{"> ? next.after_group()
                           : Token.skip_trivia(next + 1);
}

/* quotations

   `$!( expression )`, `$!{ items }`, and `$!Kind{ ... }` are anonymous
   macros applied where they are written. A `$name` in the body names the
   visible local `name`: its first use declares a hole, and the quotation
   applies to that local's value. An `@name` splices the local's sequence.
   `${expression}` and `@{expression}` declare hidden locals before building
   the code, for singular and sequence insertion. A typed
   quotation, `$!T{ expression }` or `$!(T){ expression }`, builds its code
   where it is written (see "typed quotations"), and so do
   `$!Type{ type-name }` and `$!Param{ parameter }`. */

/** Parses a quotation at `$!` into the code it builds from the locals its
    body names. */
List Compiler.parse_macro_quotation(Compiler c) {
  Token start = c.token;
  c.expect(<$>);
  c.expect(<!>);
  int typed = _typed_quotation(c);
  Symbol kind = typed || c.peek(0) == <(> ? <expression> : <block-item>;
  if (!typed && c.peek(0) == <ident>) {
    kind = _quotation_kind(c, c.token);
    c.next();
  }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  Map holes = {};
  List locals = NULL, type = NULL;
  if (typed) {
    if (c.macro_holes && %(quotation) in c.macro_holes)
      $report.parse.typed_quotation_nested(c, start);
    if (c.macro_holes) $report.parse.typed_quotation(c, start);
    if (c.peek(0) == <(>) locals = _expression_holes(c, holes);
    type = _quoted_type(c, holes);
  }
  if (!c.macro_holes) locals = locals.append(_expression_holes(c, holes));
  List built = _quotation(c, start, kind, holes, type);
  if (typed && !(%(dynamic) in holes) && c.folded_constant(built) is not void)
    return built;
  return locals
       ? %(expr ("List") (parens (block @locals (stmnt $built))))
       : built;
}

/* The kind a quotation builds: one a result kind names, or a type or one
   parameter, which only a hole kind names. */
static Symbol _quotation_kind(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (category && (category.hole == <type> || category.hole == <param>))
    return category.hole;
  return _result_kind_token(c, token);
}

/* Whether the quotation after `$!` states its type: `T{` where the
   identifier `T` names no kind, or a group that a brace follows. A type
   keyword such as `int` is an identifier here. */
static int _typed_quotation(Compiler c) {
  if (c.token.text.is_identifier())
    return c.peek(1) == <"{"> && !_category(c.token.text);
  return c.peek(0) == <(> && c.token.after_group().type == <"{">;
}

/* Declares a hidden local for each `${expression}` or `@{expression}` in
   the body, in source order, and records its name under the sigil's position.
   A nested quotation's holes are its own, and `case ${$name(...)}` is
   a macro pattern. */
static List _expression_holes(Compiler c, Map holes) {
  Token saved = c.token, close = c.token.group_close();
  Array locals = [];
  Symbol last = 0;
  for (Token t = Token.skip_trivia(saved + 1); t < close;
       t = Token.skip_trivia(t + 1)) {
    Token brace = t + 1, next = Token.skip_trivia(brace);
    if (t.type == <$> && next.type == <!>) {
      next = Token.skip_trivia(next + 1);
      if (next.text.is_identifier()) next = Token.skip_trivia(next + 1);
      t = next.group_close();
      Token typed = next.after_group();
      if (next.type == <(> && typed.type == <"{">) t = typed.group_close();
    }
    else if ((t.type == <@> || t.type == <$>) && brace.type == <"{"> &&
             (last != <case> || Token.skip_trivia(brace + 1).type != <$>)) {
      c.token = brace;
      locals.push(_hole_local(c, holes, t.pos));
      t = brace.group_close();
    }
    last = t.type;
  }
  c.token = saved;
  return locals.list_free();
}

/* The declaration of the hidden local that `{expression}` at the cursor
   initializes. The local takes the expression's type, and the quotation
   boxes its value, so an expression without an x2c type reports where it
   is written. */
static List _hole_local(Compiler c, Map holes, int position) {
  c.expect(<"{">);
  Token origin = c.token;
  List value = c.parse_expression();
  if (!value.cadr()) $report.type.var_unresolved(c, origin);
  c.expect(<"}">);
  String name = c.fresh_name("hole");
  holes[%(expression $position)] = name;
  Var constant = c.folded_constant(value);
  if (constant is void) holes[%(dynamic)] = 1;
  else holes[%(constant $name)] = constant;
  return c.bind_syntax(
    %(declare ${value.cadr()}
      (bindings (op = (bind ${c.sym.introduce(name)} ()) $value))),
    <block>, c.return_type);
}

/* Returns NULL if the quotation registered no expression at this offset. */
static List _expression_hole(Compiler c, Token prefix) {
  Var name;
  if (!c.macro_holes ||
      !c.macro_holes.try_get(%(expression ${prefix.pos}), name))
    return NULL;
  List hole = _hole_record(c, Atom.intern(name));
  return hole ? hole : _quoted_hole(c, name, prefix);
}

/* The expression that computes a typed quotation's type: the identifier at
   the cursor, or the group there, which holds a type or a `$name` local or
   `${expression}` hole whose value is the type. */
static List _quoted_type(Compiler c, Map holes) {
  if (c.peek(0) != <(>) return _quoted_type_name(c);
  c.expect(<(>);
  Token origin = c.token;
  List type = NULL;
  if (c.peek(0) == <$>) {
    Var name = c.peek(1) == <"{">
             ? holes[%(expression ${c.token.pos})]
             : Token.skip_trivia(c.token + 1).text;
    c.token = c.after_hole();
    type = _checked_type(
      c,
      c.resolve_expression(%(expr () (ident ${name.str()})), origin), origin);
  }
  else type = _quoted_type_name(c);
  c.expect(<)>);
  return type;
}

/* The `Type` expression `type`, which a `meta` function checks names its
   type with a String before a typed quotation inserts it:
   `type_name_error(type) ? (x2c_diagnostic_fail(...), type) : type`. */
static List _checked_type(Compiler c, List type, Token origin) {
  if (!c.meta_body) return type;
  List error = _runtime_call(c, "type_name_error", %($type), origin);
  List fail = _runtime_call(
    c, "x2c_diagnostic_fail", %($error (expr ("List") (nil))), origin);
  return c.resolve_expression(
    %(expr () (op ? $error
      (expr ("Type") ${source_commas_content(%($fail $type))}) $type)),
    origin);
}

static List _quoted_type_name(Compiler c) {
  Type parsed = NULL;
  c.parse_type_operand(&parsed);
  return c.cache_literal_list(parsed);
}

static List _quotation(
  Compiler c, Token start, Symbol kind, Map holes, List type) {
  Definition d = {
    .c = c, .start = start, .kind = kind, .anonymous = 1, .local = 1,
    .quotation = 1, .type = type};
  _naming(d);
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  $let(c.macro_holes, holes) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    c.macro_holes[%(quotation)] = 1;
    d.using = [];
    _announce(d);
    _body(d);
  }
  _finish(d);
  List built = _construction(d, holes);
  if (built) return built;
  /* Each local supplies one hole, a sequence included, so the quotation
     builds its pending invocation with the values already grouped. */
  List values = %(expr ("List") (nil));
  foreach (List hole, d.parameters.reverse())
    values = _quoted_cons(
      c, %(expr () (ident ${_hole_name(hole).str()})), values, start);
  List definition = c.capture_macro_value(_publish(d));
  List empty = %(expr ("List") (nil));
  return _quoted_cons(
    c, $!String{ ${"x2c.template"} }, _quoted_cons(
      c, definition, _quoted_cons(c, values, empty, start), start), start);
}

/* `head` consed onto the List expression `tail`. */
static List _quoted_cons(
  Compiler c, List head, List tail, Token origin) {
  List value = c.convert_expression(
    c.resolve_expression(head, origin), %("Var"));
  return %(expr ("List") (cons $value $tail));
}

/* A quotation whose template applies no other template builds its syntax
   where it is written (see "quoted syntax"). Any other quotation, or one
   whose template uses a projection only an expansion makes, returns NULL
   and keeps its definition. */
static List _construction(Definition &d, Map holes) {
  Compiler c = d.c;
  if (d.type) return _typed_construction(d, holes);
  if (d.kind == <type> || d.kind == <param>) return _part_construction(d);
  if (!d.rebuild || d.nested || d.kind == <decl-unit> || c.runtime_literals)
    return NULL;
  Map keys = {}, file_locals = {};
  _file_scope_locals(%(${d.template}), file_locals);
  Array fresh = [];
  foreach (List row, d.fresh) {
    Var binder = row.car();
    keys[binder] = 1;
    fresh.push(%($binder ${row.cadr()} ${binder in file_locals ? 1 : 0}));
  }
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  /* Cached pattern literals retain their values across producer sessions. */
  List quoted = %(
    "x2c.quoted" ${fresh.list_free()}
    ${c.freeze_declaration_syntax(_macro_value_names(d.template))}
  );
  List cells = _built_cells(c, quoted, keys, d.start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* The List cells that build `items`: constant syntax from the literal
   cache, and a hole for each projection `keys` maps. NULL for a binder a
   quotation cannot project where it is written. */
static List _built_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = _built_cells(c, items.cdr(), keys, start);
  List head = tail ? _built_item(c, items.car(), keys, start) : NULL;
  return head ? c.literal_cell(head, tail) : NULL;
}

/* An Expr hole's expression in an expression position replaces its whole
   shell, which a rebuild leaves out. */
static List _built_item(
  Compiler c, Var item, Map keys, Token start) {
  Var row;
  if (item.is_binder() && keys.try_get(item, row))
    return row is <list> ? _built_hole(c, row, 0, start)
                         : c.cache_literal_var(item);
  if (item.is_binder() && item.str()[1:].startswith("__macro_")) return NULL;
  if (item is not <list> || item.is_nil()) return c.cache_literal_var(item);
  match (item) {
    case %(at m-origin ?node): item = %("x2c.at" $node);
    case %(expr (<macro-expr>) ?binder):
      if (keys.try_get(binder, row) && row is <list>)
        match (row) case %((macro-param ? (kind expr) ?) expression):
          return _built_hole(c, row, 1, start);
  }
  List cells = _built_cells(c, item, keys, start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* `("x2c.hole" HOLE PROJECTION VALUE)`, where VALUE is the hole's local
   and HOLE keeps only the hole's kind and cardinality. */
static List _built_hole(
  Compiler c, List row, int shell, Token start) {
  (List hole, Symbol projection) = row;
  List local = c.convert_expression(
    c.resolve_expression(
      %(expr () (ident ${_hole_name(hole).str()})), start), %("Var"));
  List cells = c.literal_cell(local, %(nil));
  Symbol selected = shell ? <shell> : projection;
  List shape = %(
    macro-param
    (kind ${hole.assoc(<kind>)})
    (sequence ${hole.assoc(<sequence>)})
  );
  foreach (Var constant, %($selected $shape "x2c.hole"))
    cells = c.literal_cell(c.cache_literal_var(constant), cells);
  return %(expr ("List") $cells);
}

/* typed quotations

   `$!T{ expression }`, where `T` names no kind, and
   `$!(T){ expression }` build `(expr T CONTENT)` where they are written,
   from the template a rebuild fills: constant syntax from the literal
   cache, and each hole's value inserted as a rebuild inserts it. A typed
   quotation binds nothing, so it may declare no name and apply no
   template. */

static List _typed_construction(Definition &d, Map holes) {
  Compiler c = d.c;
  Map keys = _written_keys(d);
  match (d.rebuild.car()) case %(expr ? *content):
    return c.literal_cell(
      c.cache_literal_var(<expr>),
      c.literal_cell(d.type, _typed_cells(c, content, keys, d.start)));
  /* The rebuild template of an expression that is one hole is empty; the
     definition's template names the hole, which `Macro.typed` inserts. */
  List hole = keys[d.template.last()].list().car();
  // Constant interpolation uses the same constructor without a runtime local.
  Var type = c.folded_constant(d.type), constant;
  if (type is <list> &&
      holes.try_get(%(constant ${_hole_name(hole).str()}), constant))
    return c.cache_literal_list(Macro.typed(type, constant));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_typed")), d.start);
  List value = _hole_value(c, hole, d.start);
  return c.resolve_expression(
    %(expr ("List") (call $callee (args ${d.type} $value))), d.start);
}

/* `$!Type{ type-name }` and `$!Param{ parameter }` build their List where
   they are written, as a typed quotation builds its expression. */
static List _part_construction(Definition &d) {
  Map keys = _written_keys(d);
  match (d.rebuild.car()) case %(macro-bind ?binder):
    return _typed_hole(d.c, keys[binder], d.start);
  return %(expr ("List") ${_typed_cells(d.c, d.rebuild.car(), keys, d.start)});
}

/* The hole projections a quotation built where it is written fills. Such a
   quotation binds nothing, so it may declare no name and apply no
   template. */
static Map _written_keys(Definition &d) {
  if (!d.rebuild || d.fresh) $report.parse.typed_quotation(d.c, d.start);
  Map keys = {};
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  return keys;
}

/* The List cells that build `items`. A sequence or splice hole
   contributes its items to the List that holds it. */
static List _typed_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = _typed_cells(c, items.cdr(), keys, start);
  Var item = items.car(), row;
  if (item is <list> && !item.is_nil())
    return c.literal_cell(
      %(expr ("List") ${_typed_cells(c, item, keys, start)}), tail);
  if (!item.is_binder() || !item.str()[1:].startswith("__macro_"))
    return c.literal_cell(c.cache_literal_var(item), tail);
  if (!keys.try_get(item, row)) $report.parse.typed_quotation(c, start);
  (List hole, Symbol projection) = row.list();
  List value = _typed_hole(c, row, start);
  if (projection == <splice> || hole.assoc(<sequence>).int())
    value = %(splice $value);
  return c.literal_cell(value, tail);
}

/* One use of a hole: its local, which `Macro.inserted` lifts in an
   expression hole, makes an identifier where code takes an expression, and
   makes a spelling in a Name hole's member position. A Name hole that
   declares inserts the name `Macro.declared` makes. An expression sequence
   lifts each item as `Macro.inserted_items` does. A type inserts its
   syntax once it is checked, and other syntax inserts as it is. */
static List _typed_hole(Compiler c, List row, Token start) {
  (List hole, Symbol projection) = row;
  List local = _hole_value(c, hole, start);
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  int expression = projection == <expression>;
  if (kind == <type>) return _checked_type(c, local, start);
  if (hole.assoc(<sequence>).int())
    return lifts ? _runtime_call(c, "Macro_inserted_items", %($local), start)
                 : local;
  if (kind == <name> && projection == <value>)
    return _runtime_call(c, "Macro_declared", %($local), start);
  if (!lifts && !expression && kind != <name>) return local;
  return _runtime_call(
    c, "Macro_inserted",
    %($local ${$!int{ $lifts }} ${$!int{ $expression }}), start);
}

static List _runtime_call(
  Compiler c, String name, List arguments, Token start) {
  List callee = c.resolve_expression(%(expr () (ident $name)), start);
  return c.resolve_expression(
    %(expr () (call $callee (args @arguments))), start);
}

static List _hole_value(Compiler c, List hole, Token start) =>
  c.resolve_expression(%(expr () (ident ${_hole_name(hole).str()})), start);

/* A quotation's hole takes its kind from a name position, or from a
   parameter or statement position where it stands alone, which no
   annotation can give it. A hole that a declarator follows is a parameter's
   type, and one that an operator, `;`, or a postfix form follows is an
   expression. */
static int _quoted_role(Compiler c, Symbol role) {
  if (!(%(quotation) in c.macro_holes) || !(role in quoted_roles)) return 0;
  if (role == <name>) return 1;
  Token after = c.after_hole();
  if (role == <param>)
    return after.type == <,> || after.type == <)> || after.type == <"}">;
  return after.type != <;> && !_extends_expression(after);
}

/* A `$name` or `@name` in a quotation's body that names a visible local
   declares a singular or sequence hole. A local declared `Type` fills a type
   hole, which no position can tell from a statement before a name. */
static List _quoted_hole(
  Compiler c, String spelling, Token prefix) {
  if (!c.macro_holes || !(%(quotation) in c.macro_holes)) return NULL;
  Type type = NULL;
  List local = c.sym.lookup(%($spelling), type);
  if (!local || !c.sym.binding_is_local(local)) return NULL;
  Symbol kind = c.sym.is_named_value_type(type, "Type") ? <type> : 0;
  int sequence = prefix.type == <@> || prefix.type == <"@{">;
  List hole = _record_hole(c, spelling, kind, sequence);
  Var quoted = c.macro_holes[%(quoted)];
  c.macro_holes[%(quoted)] =
    cons(hole, quoted is <list> ? quoted.list() : NULL);
  return hole;
}

/* A quotation's holes in the order its body first names them. */
static List _quoted_holes(Compiler c) {
  Var quoted = c.macro_holes[%(quoted)];
  return quoted is <list> ? quoted.list().reverse() : NULL;
}

/* Consumes a hole filling `role` and returns its projection. */
static List _parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  List hole = c.peek_macro_hole();
  if (!hole) _unbound(c, _hole_name_token(c, token.type).text, token);
  c.token = c.after_hole();
  Atom name = _hole_name(hole);
  int sequence = token.type == <@> ||
                 token.type == <"@{">;
  if (sequence != hole.assoc(<sequence>).int())
    _cardinality_error(c, name.str(), sequence, token);
  if (sequence && !(role in sequence_roles))
    $report.parse.splice_position(c);
  Symbol inferred = _role_kind(role), kind = hole.assoc(<kind>);
  if (!kind) {
    hole = hole.search_replace(%(kind ?prior), %(kind $inferred));
    c.macro_holes[name] = hole;
  }
  else if (!_kind_accepts_role(kind, role)) {
    String spelling = name.str();
    $report.parse.hole_ambiguous(
      c,
      spelling, token, _kind_spelling(kind), _kind_spelling(inferred));
  }
  String projection = _hole_projection(c, hole, role, sequence);
  return %(macro-bind ${_hole_key(hole, projection)});
}

static void _cardinality_error(
  Compiler c, String spelling, int sequence, Token token) {
  $report.parse.hole_cardinality(c, sequence, spelling, token);
}

static Symbol _role_kind(Symbol role) {
  if (role == <expression> || role == <argument>) return <expr>;
  return role == <statement> ? <block> : role;
}

/* A decorator's Unit target projects its source; a sequence, a type, or
   a captures list projects its splice; other holes project their
   expression or value. */
static String _hole_projection(
  Compiler c, List hole, Symbol role, int sequence) {
  Var binder = hole.assoc(<binder>);
  if (%(source $binder) in c.macro_holes) return "source";
  if (sequence || role == <type> || role == <captures>) return "splice";
  return role in %(expression argument expr) ? "expression" : "value";
}

static const SymbolSet value_kinds = %<<expr name literal>>;

static int _kind_accepts_role(Symbol kind, Symbol role) {
  Symbol expected = role == <statement> ? <block> : role;
  if (expected == <expression> || expected == <argument>)
    return kind in value_kinds;
  return kind == expected ||
    (expected == <field> && kind == <decl>) ||
    (expected == <block> && kind == <decl>) ||
    (expected == <unit> &&
     (kind == <decl> || kind == <function> || kind == <named-type>));
}

/** Returns whether tokens after a Lisp form or explicit meta call continue
    a declaration. The balanced argument group is inspected without moving
    the compiler cursor; a visible source macro retains its own grammar.
*/
int Compiler.macro_lisp_starts_declaration(Compiler c) {
  Token opening = c.token;
  if (opening.type == <$>) {
    if (_peek_invocation(c)) return 0;
    String name;
    opening = _scan_name(c, name);
    if (opening.type != <(>) return 0;
  }
  Token token = opening.after_group();
  return token.type == <$> || token.type == <ident> ||
         token.type == <*> || token.type == <(>;
}

/** Parses a member name in a template. A singular `Name` hole there
    supplies the spelling it captured, without hygienic renaming.
*/
List Compiler.try_parse_macro_member(Compiler c) {
  List hole = c.peek_macro_hole();
  List slot = c.try_parse_macro_slot(<name>);
  // A quotation's first use of a hole gives the hole its kind.
  if (hole) hole = _hole_record(c, _hole_name(hole));
  if (!slot || !hole || hole.assoc(<kind>) != <name> ||
      hole.assoc(<sequence>).int())
    return slot;
  return %(macro-bind ${_hole_key(hole, "member")});
}

/* A Lisp slot carries its form and the construction binders its Unit holes
   need. A slot inside a Unit decorator also carries the target's. */
static List _parse_lisp_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <"@(">;
  String form = _lisp_form(c);
  Var target = c.macro_holes[%(target)];
  List construction = _lisp_construction(c, form);
  if (target is <list>) {
    Var required = _hole_key(target, "construction");
    if (role == <name>)
      construction = construction.append(%((target $required)));
    else if (role == <unit>) construction = construction.append(%($required));
  }
  return %(
    macro-slot $sequence $form
    @construction
  );
}

/* The construction binder of each Unit hole the form names, once each. */
static List _lisp_construction(Compiler c, String form) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = [];
  Map seen = {};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>)
        _unit_construction(c, name, construction, seen);
      token = name;
    }
    token = tokenizer.next();
  }
  return construction.list_free();
}

static void _unit_construction(
  Compiler c, Token name, Array construction, Map seen) {
  List hole = _hole_record(c, Atom.intern(name.text));
  if (!hole || hole.assoc(<kind>) != <unit>) return;
  Var binder = _hole_key(hole, "construction");
  if (binder in seen) return;
  seen[binder] = 1;
  construction.push(binder);
}

/* template binders

   Each hole projection has a binder whose prefix gives its cardinality, and
   each declaration a template makes has a binder numbered in the order the
   template declares it. */

static Atom _hole_key(List hole, String projection) =>
  Macro.binder(hole.assoc(<binder>), projection, hole.assoc(<sequence>));

/* A template binder names one lexical declaration, including its namespace.
   Its ordinal keeps same-spelled declarations distinct within a template. */
static Atom _local_binder(Var identity, int tag) {
  int number = 0;
  (void) Ast.try_binding(identity, number, NULL);
  int ordinal = INT_MAX - number;
  return Atom.intern(%"?__macro_${tag ? "tag" : "local"}_${ordinal}");
}

/* Introduces one declaration in the current lexical scope. */
static List _definition_local(Compiler c, String spelling, int tag) {
  Map locals = c.macro_definition_locals();
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = Ast.binding(identity, spelling);
  c.set_fact(%(known $identity), spelling);
  locals[<order>] = cons(introduced, order is <list> ? order : NULL);
  locals[introduced] = spelling;
  if (tag) locals[%(tag-local $introduced)] = 1;
  return introduced;
}

/** Returns the current declaration's definition-local identity. An active
    macro-definition locals map is required. */
List Compiler.macro_introduced_name(Compiler c, String spelling) {
  Map locals = c.macro_definition_locals();
  List current = c.sym.current_binding(%($spelling));
  if (current && current in locals) return current;
  return _definition_local(c, spelling, 0);
}

/** Returns a template's local binding for tag `name` of `kind`, or NULL
    when it names a visible public tag. A tag the template defines or
    declares is a template local, apart from ordinary names of the same
    spelling. A tag it only references keeps its public spelling unless the
    template later defines or declares it.
*/
List Compiler.macro_tag_name(
  Compiler c, Symbol kind, String name, int definition) {
  Map locals = c.macro_definition_locals();
  List key = %(tag $name);
  List current = c.sym.current_binding(key);
  if (current && current in locals) {
    if (definition) locals.del(%(provisional $current));
    return current;
  }
  if (!definition) {
    List visible = c.sym.lookup(key, NULL);
    if (visible && visible in locals) return visible;
    /* A name the body passed to a nested macro's Name hole is the body's
       own in every namespace, including the tag that macro declares. */
    Var named = locals[%(name-argument $name)];
    if (named is <list>) return named;
    if (c.sym.get_exact(%($kind $name))) return NULL;
  }
  List local = _definition_local(c, name, 1);
  c.sym.bind_identity(%(tag), local, %($kind $local));
  if (!definition) locals[%(provisional $local)] = 1;
  return local;
}

/* Replaces each binder or binding identity that `bindings` maps. A List
   none of whose children change stays the same List, and only a changed
   List is copied. */
static Var _replace_bindings(Var value, Map bindings) {
  Var replacement;
  if (value is not <list> || value.is_nil())
    return value.is_binder() && bindings.try_get(value, replacement)
      ? replacement : value;
  if (Ast.try_binding(value, NULL, NULL) &&
      bindings.try_get(value, replacement))
    return replacement;
  List original = value;
  Array items = NULL;
  for (List cursor = original; cursor; cursor = cursor.cdr()) {
    Var child = cursor.car(), item = _replace_bindings(child, bindings);
    if (!(void *) items && item !== child) {
      items = [];
      for (List prefix = original; prefix != cursor; prefix = prefix.cdr())
        items.push(prefix.car());
    }
    if ((void *) items) items.push(item);
  }
  return (void *) items ? items.list_free().var() : value;
}

/* invocation patterns

   An invocation's capture rows match the definition's pattern: an `args`
   row per parameter, a decorator's target row, and a Name row for each
   fresh name compile-time Lisp reads. Each row binds only the projections
   the template uses. */

static List _invocation_pattern(Definition &d) {
  Map binders = {};
  _template_binders(d.template, binders);
  Array arguments = [];
  foreach (List parameter, d.parameters)
    arguments.push(_capture_pattern(parameter, binders));
  List invocation = d.kind == <decorator>
    ? %(
      target (args @{arguments.list_free()})
      ${_capture_pattern(d.target, binders)}
    ) : %(args @{arguments.list_free()});
  List captures = _fresh_patterns(d.fresh, binders);
  return captures ? invocation.append(%((fresh @captures))) : invocation;
}

static void _template_binders(Var value, Map binders) {
  if (value.is_binder()) {
    binders[value] = 1;
    return;
  }
  if (value is not <list>) return;
  foreach (Var child, value.list()) _template_binders(child, binders);
}

static List _fresh_patterns(List fresh, Map binders) {
  Array fresh_patterns = [];
  foreach (Var row, fresh) {
    Var (binder, spelling, lisp) = row;
    (void) spelling;
    if (lisp.int())
      fresh_patterns.push(_capture_pattern(_hole(binder, <name>, 0), binders));
  }
  return fresh_patterns.list_free();
}

/* A hole has source, value, expression, and splice projections. A singular
   Function hole also has return and declarator projections, while a Unit hole
   may carry construction requirements. The stored Match pattern binds only
   projections used by the template; the author binder exposes the captured
   value to compile-time Lisp. */
static List _capture_pattern(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  int sequence = hole.assoc(<sequence>);
  Var one = sequence ? <*>.var() : <?>.var();
  Var source = _used(binders, hole, "source", one);
  Var value = _used(binders, hole, "value", one);
  Var expression = _used(binders, hole, "expression", one);
  Var splice = _used(binders, hole, "splice", <*>);
  if (!sequence && hole.assoc(<kind>) == <function>)
    value = %(
      !and $value
      (function
        ${_used(binders, hole, "return", <?>)}
        ${_used(binders, hole, "declarator", <?>)}
        ?)
    );
  List trailing = NULL;
  if (hole.assoc(<kind>) == <unit>) trailing = _unit_trailing(hole, binders);
  return _capture_layout(
    sequence,
    %(!and (source $author) (source $source)),
    sequence ? %(!and (value $value) (value $expression) (value $splice))
             : %(value $value),
    %(expression $expression), %(splice $splice), trailing);
}

/* The binder of a projection the template uses, or `otherwise`. */
static Var _used(Map binders, List hole, String projection, Var otherwise) {
  Var binder = _hole_key(hole, projection);
  return binder in binders ? binder : otherwise;
}

/* A Unit hole's row carries its construction binder when the template
   reads the hole or its construction. */
static List _unit_trailing(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  Var construction = _hole_key(hole, "construction");
  int used = author in binders || construction in binders;
  foreach (String role, %("source" "value" "splice"))
    used |= _hole_key(hole, role) in binders;
  return used ? %($construction) : NULL;
}

/* A scalar capture has source, value, expression, and splice fields; a
   sequence capture has source and value. Any Unit construction requirements
   follow. Patterns and rows share this layout. */
static List _capture_layout(
  int sequence, List source, List value, List expression, List splice,
  List trailing) =>
  sequence ? %(capture $source $value @trailing)
           : %(capture $source $value $expression $splice @trailing);

// definition forms and keyword aliases

/** Publishes a canonical `macrodef` in source order and returns `node`.
    A later definition with the same name affects only later invocations.
*/
List Compiler.publish_macro_definition_node(Compiler c, List node) {
  c.macros[node.assoc(<name>)] = node;
  if (c.shallow && !c.macro_holes &&
      !node.assoc(<static>).equal(1) && !node.assoc(<local>).int())
    c.record_compile_time_effect(
      %(compile-time macrodef ${c.freeze_declaration_syntax(node)}), c.token);
  return node;
}

/** Records a public source effect where its completed definition stands. */
void Compiler.record_compile_time_effect(
  Compiler c, List row, Token start) {
  if (!c.shallow || c.source_private || c.macro_holes ||
      !c.sym.at_file_scope() ||
      c.builtin_defs || !c.filename ||
      c.filename.startswith("<builtin:")) return;
  String source = Compiler.portable_path(Path.absolute(c.filename));
  List key = %("source-node" (compile-time $source ${start.pos}));
  List previous = c.sym.get(key);
  if (previous) row = %(compile-time effects $previous $row);
  c.sym.set(key, row);
}

/** Installs included compile-time definitions in their source order.
    Keyword aliases retain the definition visible when their source declared
    them, even if a later macro definition uses the same name.
*/
void Compiler.install_compile_time_effects(Compiler c, List rows) {
  foreach (List row, rows) match (row) {
    case %(compile-time effects *effects):
      c.install_compile_time_effects(effects);
    case %(compile-time macrodef ?definition): {
      Var name = c.thaw_declaration_syntax(definition.list().assoc(<name>));
      c.macros[name] = %(imported-macro $definition);
    }
    case %(compile-time keyword ?alias ?definition): {
      if (!c.kw_aliases) c.kw_aliases = {};
      c.kw_aliases[alias] = %(imported-macro $definition);
    }
    case %(compile-time rewrite *): _install_rewrite(c, row);
    case %(compile-time lisp ?form (source ?path ?site)): {
      Token token = c.thaw_declaration_syntax(site);
      String file = Compiler.absolute_home_path(path), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL) {
        if (c.shallow) c.queue_declaration_effect(form, token, NULL);
        else c.evaluate_declaration_effect(form, token);
      }
    }
    case %(compile-time import ?path (source ?source ?site)): {
      Token token = c.thaw_declaration_syntax(site);
      String file = Compiler.absolute_home_path(source), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL)
        _import(c, Compiler.absolute_home_path(path), token);
    }
    case %(project-meta *): c.install_project_meta_effect(row);
  }
}

/** Returns whether the current tokens have macro-definition introducer form.
    This query does not consume tokens.
*/
int Compiler.macro_form_is_definition(Compiler c) {
  Token token = c.token;
  int offset = c.peek(0) == <static>;
  if (offset) token = Token.skip_trivia(token + 1);
  if (c.peek(offset) != <ident> || token.text != "macro") return 0;
  if (c.peek(offset + 1) == <$>) return 1;
  return c.peek(offset + 1) == <ident> &&
    (c.peek(offset + 2) == <$> ||
     (c.peek(offset + 2) == <ident> && c.peek(offset + 3) == <$>));
}

/** Returns whether the current tokens begin a local macro definition.
    This query does not consume tokens.
*/
int Compiler.local_macro_form_is_definition(Compiler c) {
  /* The `<(>` literal keeps this body braced: the API reference generator
     reads it as an unbalanced parenthesis and drops the rest of the file. */
  return c.at_word("macro") && c.peek(1) == <ident> &&
         c.peek(2) == <ident> && c.peek(3) == <(>;
}

/** Returns whether the current tokens begin a `keyword NAME $macro` alias.
    This query does not consume tokens.
*/
int Compiler.keyword_form_is_definition(Compiler c) {
  Token token = c.token;
  int offset = c.peek(0) == <static>;
  if (offset) token = Token.skip_trivia(token + 1);
  return c.peek(offset) == <ident> && token.text == "keyword" &&
         c.peek(offset + 2) == <$>;
}

/** Parses and installs one source-local `keyword` alias.
    The named macro must already be visible; the alias captures that definition
    and consumes its terminating semicolon. Returns the alias.
*/
Atom Compiler.parse_keyword_definition(Compiler c) {
  Token declaration = c.token;
  int storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  if (c.peek(0) != <ident>)
    $report.parse.keyword_name(c);
  Atom alias = Atom.intern(c.token.text);
  c.next();
  if (_fixed_alias(c, alias))
    $report.macro.keyword_builtin(c, declaration);
  Token reference = c.token;
  List definition = _lookup(c, _name(c), reference);
  Symbol kind = definition.assoc(<kind>);
  if (!(kind in alias_kinds)) {
    String spelling = _kind_spelling(kind);
    $report.macro.keyword_internal(
      c,
      spelling, declaration, _definition_note(definition));
  }
  c.expect(<;>);
  c.kw_aliases[alias] = definition;
  if (!storage)
    c.record_compile_time_effect(
      %(compile-time keyword $alias
        ${c.freeze_declaration_syntax(definition)}), declaration);
  return alias;
}

/* Only the built-in sources define `with` or replace a built-in alias. */
static int _fixed_alias(Compiler c, Atom alias) {
  Var existing;
  return !c.builtin_defs &&
    (alias == <with> ||
     (_try_macro(c, c.kw_aliases, alias, existing) &&
      existing.list().assoc(<builtin>).int()));
}

static const SymbolSet alias_kinds =
  %<<expression block-item field enumerator map-entry unit decorator>>;

/* Parses one keyword alias of `c`'s source into `aliases`. */
static void _record_alias(Compiler c, Map aliases) {
  Atom alias = c.parse_keyword_definition();
  aliases[alias] = c.kw_aliases[alias];
}

static typedef struct RewriteRule {
  String name;
  Symbol point;
  Var kind;
  MacroMatcher matcher;
  int builtin, prepared;
} *RewriteRule;

static Var RewriteRule.var(RewriteRule rule) => Var.new(<p48>, rule);
static RewriteRule Var.rewrite_rule(Var value) => value.pointer();

/* A rule derives a macro's matcher now, or else on the first probe of its
   family; a Match pattern is its own. */
static RewriteRule _rewrite_rule(
  Symbol point, Var kind, String name, List pattern, List holes,
  int builtin, int prepared) {
  RewriteRule rule = Scope.calloc(1, sizeof(struct RewriteRule));
  MacroMatcher matcher = {NULL, NULL, pattern};
  if (pattern.car() == <macrodef>) {
    Macro shape = pattern;
    matcher = prepared ? shape.matcher(holes) : (MacroMatcher){shape, holes};
  }
  *rule = (struct RewriteRule){name, point, kind, matcher, builtin, prepared};
  return rule;
}

/* Rules the compiler prelude installs, by frozen row. Each is thawed once
   per process and shared by every unit; its matcher is derived on the first
   probe of its family. A row whose thawing records a cache key, binding, or
   origin in its unit is thawed for each unit instead. */
static Map shipped_rules = NULL, static Scope shipped_scope = NULL;

static void _shipped_shutdown(void) {
  shipped_scope.destroy();
  shipped_scope = NULL;
  shipped_rules = NULL;
}

/* Registers an installed rewrite row. A prelude rule whose translator
   this compiler does not link was added after it was built, so the form
   keeps this compiler's own lowering, as a prelude component added after
   it would. */
static void _install_rewrite(Compiler c, List row) {
  Var shared = shipped_rules ? shipped_rules[row] : void;
  if (shared is void && c.builtin_defs) shared = _ship_rewrite(c, row);
  if (shared is <p48>) {
    _register_rewrite(c, shared.rewrite_rule());
    return;
  }
  match (row) case %(compile-time rewrite ?point ?kind ?name ?shape ?holes): {
    if (c.builtin_defs && !Compiler.links_meta_function(name)) return;
    RewriteRule rule = _rewrite_rule(
      point, c.thaw_declaration_syntax(kind), name,
      c.thaw_declaration_syntax(shape), c.thaw_declaration_syntax(holes),
      c.builtin_defs, 1);
    _register_rewrite(c, rule);
  }
}

/* The shared rule for a prelude row, or 0 when the row is bound to its
   unit or names a translator the compiler does not link. The shared rule
   derives its matcher on first use. */
static Var _ship_rewrite(Compiler c, List row) {
  $scope(&shipped_scope) {
    if (!shipped_rules) {
      Scope.shutdown_hook(_shipped_shutdown);
      shipped_rules = {};
    }
    _require_owned(row.try_own());
    Var shared = 0;
    match (row)
      case %(compile-time rewrite ?point ?kind ?name ?shape ?holes): {
        if (_unit_bound(row) || !Compiler.links_meta_function(name)) break;
        List thawed = %(${c.thaw_declaration_syntax(kind)}
          ${c.thaw_declaration_syntax(shape)}
          ${c.thaw_declaration_syntax(holes)});
        _require_owned(thawed.try_own());
        Var (own_kind, own_shape, own_holes) = thawed;
        shared = _rewrite_rule(
          point, own_kind, name, own_shape, own_holes, 1, 0);
      }
    shipped_rules[row] = shared;
    return shared;
  }
}

static void _require_owned(int owned) {
  if (owned) return;
  fprintf(stderr, "x2c: could not retain a shipped rewrite rule\n");
  abort();
}

static int _unit_bound(Var syntax) {
  if (syntax is not <list>) return 0;
  match (syntax)
    case %((!or declaration-cache declaration-binding declaration-origin) *):
      return 1;
  foreach (Var child, syntax.list()) if (_unit_bound(child)) return 1;
  return 0;
}

/* The first probe of a shared rule's family derives its matcher with the
   process lifetime of the rule. */
static MacroMatcher *_prepared_matcher(RewriteRule rule) {
  if (!rule.prepared && rule.matcher.shape) {
    $scope(&shipped_scope) {
      MacroMatcher matcher = rule.matcher.shape.matcher(rule.matcher.holes);
      _require_owned(matcher.pattern.try_own());
      rule.matcher = matcher;
    }
    rule.prepared = 1;
  }
  return &rule.matcher;
}

/* A coarse category selects candidates; each retained pattern decides whether
   the translator applies. Only the active translator is excluded while its
   replacement binds, so independent translations can compose. User rules
   retain registration order ahead of builtin defaults. */
static void _register_rewrite(Compiler c, RewriteRule rule) {
  if (!c.rewrite_rules) c.rewrite_rules = {};
  Var stored;
  Map kinds;
  if (c.rewrite_rules.try_get(rule.point, stored)) kinds = stored;
  else c.rewrite_rules[rule.point] = kinds = {};
  List rows = kinds.try_get(rule.kind, stored) ? stored.list() : NULL;
  foreach (RewriteRule prior, rows)
    if (prior.name == rule.name &&
        prior.matcher.shape == rule.matcher.shape &&
        prior.matcher.holes == rule.matcher.holes &&
        (rule.matcher.shape || prior.matcher.pattern == rule.matcher.pattern))
      return;
  Array ordered = [];
  int inserted = 0;
  foreach (RewriteRule prior, rows) {
    if (!rule.builtin && prior.builtin && !inserted) {
      ordered.push(rule);
      inserted = 1;
    }
    ordered.push(prior);
  }
  if (!inserted) ordered.push(rule);
  kinds[rule.kind] = ordered.list_free();
}

static List _rewrite_candidates(Compiler c, Symbol point, Var kind) {
  Var stored;
  if (!c.rewrite_rules || !c.rewrite_rules.try_get(point, stored)) return NULL;
  Map kinds = stored;
  return kinds.try_get(kind, stored) ? stored.list() : NULL;
}

/** Matches the member rules registered for each field keyword that
    `aggregate` declares a field with, as `Compiler.rewrite` matches those
    keyed by a receiver type. */
List Compiler.marked_rewrite(
  Compiler c, Type aggregate, List source, Token site) {
  Var stored;
  if (!c.rewrite_rules.try_get(<member>, stored)) return NULL;
  foreach (Var (mark, _), stored.map()) {
    if (mark is not <symbol> || !c.sym.get(%(@aggregate $mark))) continue;
    List rewritten = c.rewrite(
      <member>, mark, source, <expression>, NULL, site);
    if (rewritten) return rewritten;
  }
  return NULL;
}

/** Tests one operation's registry without invoking a translator. */
int Compiler.has_rewrites(Compiler c, Symbol point, Var kind) =>
  !!_rewrite_candidates(c, point, kind);

/** Matches registered patterns for one operation, then binds the first
    replacement. A translator declines with void, null, or its input itself.
    Active rules cannot re-enter. A statement of the same kind that a
    statement replacement writes or copies, such as its source, takes the
    rules after the one that replaced it. */
List Compiler.rewrite(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site) =>
  _rewrite(c, point, kind, source, position, expected, site, 0);

/** Matches registered patterns for the statement `source`, which the
    transform has lowered, then binds the first replacement as
    `Compiler.rewrite` does. Binding keeps the source, and each part of it
    the replacement holds, as lowered. */
List Compiler.rewrite_lowered(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site) =>
  _rewrite(c, point, kind, source, position, expected, site, -1);

/** Lowers `replacement`, which `Compiler.rewrite_lowered` bound for the
    lowered statement `source`, and keeps each part of `source` it holds as
    it is, so no statement rule is offered that part again. */
List Compiler.lower_replacement(Compiler c, List replacement, List source) {
  Array parts = $auto([]);
  _held_parts(source, <node>, parts);
  struct SlotWatch kept = {parts.list(), [], []};
  kept.kept = 1;
  $let(c.slot_watch, &kept) return c.normalize(replacement);
}

/** Binds the replacement a shipped rule gives the lowered statement
    `source` of `kind`, which the kernel wrote while lowering, as
    `Compiler.rewrite_lowered` does. A statement the kernel writes is not
    source, so no program rule sees it. */
List Compiler.rewrite_written(
  Compiler c, Symbol kind, List source, Type expected) {
  struct SlotWatch written = {.shipped = 1};
  $let(c.slot_watch, &written)
    return c.rewrite_lowered(
      <node>, kind, source, <statement>, expected, NULL);
}

/** Binds and lowers a replacement while its rule remains active. The
    source expressions the replacement holds lower outside the rule, so a
    nested use of the rule applies again. A statement replacement, or a
    lowered one, also lowers the statements its source held outside the
    rule, and lowers once, so a new statement it writes stays outside the
    rule. Code a shipped rule's replacement writes, such as the support call
    an interpolated String or a collection literal lowers to, is not source,
    so only shipped rules see it. An expression retains the result type
    already established for its parent. A replacement whose template and
    slot signatures an earlier use in the unit prepared lowers only its
    captured values. */
List Compiler.lower_rewrite(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site) =>
  _rewrite(c, point, kind, source, position, expected, site, 1);

/* `lower` is 1 to lower the replacement, 0 to bind it, and -1 to bind it
   around a lowered source. */
static List _rewrite(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, Token site, int lower) {
  // A meta body still completes and formats the calls it makes.
  if (c.macro_holes || (c.meta_body && point != <member> && point != <call>))
    return NULL;
  // Code that a shipped rule or the kernel writes is not source.
  int shipped = c.slot_watch && c.slot_watch.shipped;
  foreach (RewriteRule rule, _rewrite_candidates(c, point, kind)) {
    if (c.active_rewrites.contains(rule) || (shipped && !rule.builtin))
      continue;
    if (lower > 0 && rule.builtin && point == <function>) {
      List lifted = c.lift_lambda_types(source);
      if (lifted !== source)
        $let(c.applying, cons(rule, c.active_rewrites))
          return _lowered_definition(c, lifted);
    }
    MacroMatcher *matcher = _prepared_matcher(rule);
    if (matcher.shape ? !c.matches_macro(*matcher, source)
                      : !source.match(matcher.pattern)) continue;
    Var result = _applied(c, rule, source, site);
    if (result is void ||
        (result is <list> && (!result.list() || result.list() === source)))
      continue;
    $let(c.active_rewrites, cons(rule, c.active_rewrites)) {
      if (lower <= 0)
        return _bound(
          c, point, kind, source, result, position, expected, site, lower);
      if (position == <unit>) return _lowered_definition(c, result);
      int held = point == <node>;
      match (result) case %(code-value "lowered" *): held = 1;
      if (held) {
        Array parts = $auto([]);
        _held_parts(source, point, parts);
        return _watched(c, result, parts, position, expected, site);
      }
      return _prepared(c, source, result, position, expected, site);
    }
  }
  return NULL;
}

/* What `rule` answers for `source`. The code its meta function places
   while it runs is that rule's, as its replacement is. */
static Var _applied(
  Compiler c, RewriteRule rule, List source, Token site) {
  $let(c.applying, cons(rule, c.active_rewrites))
    return c.apply_meta_function(rule.name, %($source), site);
}

/* Pushes the parts of `source` that its replacement may hold onto
   `found`, to lower outside its rule: each expression, or for a statement
   each statement and outermost expression beneath it, such as a match's
   subject, patterns, and arm bodies. A nested statement of the same kind
   in one of them applies the rule again. */
static void _held_parts(List source, Symbol point, Array found) {
  if (point != <node>) {
    foreach (Var part, source) _expression_nodes(part, found);
    return;
  }
  List node;
  $ast.walk(source.cdr(), node) {
    if (node.car() is <symbol>) found.push(node);
    if (node.car() == <expr>) continue;
  }
}

/* A replacement bound without lowering. A statement of the rule's kind
   that a statement replacement holds, such as its source, and that is not
   a part its source held, takes the rules after this one now, so lowering
   never offers it to this rule again. With `lower` -1 the source is
   lowered, so binding keeps it and the parts of it the replacement holds.
   File-scope code that a shipped rule gives is written. */
static List _bound(
  Compiler c, Symbol point, Var kind, List source, Var result,
  Symbol position, Type expected, Token site, int lower) {
  if (point != <node>)
    return _bind_replacement(c, result, position, expected);
  Array parts = $auto([]);
  _held_parts(source, point, parts);
  if (lower) result = _kept_lowered(result, source, parts);
  List bound = _bind_replacement(c, result, position, expected);
  if (position == <unit>) bound = c.written_support(bound);
  struct SlotWatch held = {parts.list()};
  return _bound_held(c, &held, kind, bound, position, expected, site, lower);
}

/* Binds a replacement at `position`. Outside any local scope, as when the
   transform lowers a function, a statement or expression replacement
   declares its names in a scope of its own, so no other function sees
   them. */
static List _bind_replacement(
  Compiler c, Var result, Symbol position, Type expected) {
  int own = position != <unit> && c.sym.at_file_scope();
  if (own) c.sym.push_new_scope();
  defer if (own) c.sym.pop_scope();
  return c.bind_syntax(result, position, expected);
}

/* `result` with `source` and each of its `parts` that it holds marked as
   lowered code, which binding keeps as it is. A lowered carrier binds as it
   is already. */
static Var _kept_lowered(Var result, List source, Array parts) {
  match (result) case %(code-value "lowered" *): return result;
  Map kept = $auto({});
  kept[(void *) source] = Code.lowered(source, NULL);
  foreach (List part, parts) kept[(void *) part] = Code.lowered(part, NULL);
  return Ast.replace_nodes(result, kept);
}

static Var _bound_held(
  Compiler c, SlotWatch held, Symbol kind, Var ast, Symbol position,
  Type expected, Token site, int lower) {
  if (!Ast.contains_head(ast, kind) || _find_slot(held, ast) >= 0) return ast;
  List node = ast;
  if (node.car() == kind) {
    List rewritten =
      _rewrite(c, <node>, kind, node, position, expected, site, lower);
    return rewritten ? rewritten : node;
  }
  Var child;
  $ast.rewrite_children(
    node, child,
    _bound_held(c, held, kind, child, position, expected, site, lower));
}

/* A replacement definition binds at file scope and lowers as written,
   unless it is a lowered carrier. It lowers outside the watch that chose
   its rule, as any definition does, and a shipped rule's is written. */
static List _lowered_definition(Compiler c, Var result) {
  List bound = c.bind_syntax(result, <unit>, NULL);
  match (bound) case %(seq ?only): bound = only;
  match (result) case %(code-value "lowered" *): return bound;
  $let(c.slot_watch, NULL) return c.normalize(c.written_support(bound));
}

/** The bound file-scope code `bound` that the rule now writing gives,
    written as the kernel's when that rule is shipped. A rule writes while
    its meta function runs, until a rule it reaches binds, and while its
    replacement binds and lowers. What a program writes, or a placement
    outside any rule, is source. */
List Compiler.written_support(Compiler c, List bound) {
  List writers = c.applying && c.applying.cdr() === c.active_rewrites
    ? c.applying : c.active_rewrites;
  RewriteRule writer = writers ? writers.car() : NULL;
  return writer && writer.builtin ? Ast.written_definitions(bound) : bound;
}

/** Whether the rule whose meta function now runs is shipped, so that the
    names it calls resolve to the copies the compiler links. */
int Compiler.applying_shipped(Compiler c) {
  RewriteRule applying = c.applying ? c.applying.car() : NULL;
  return applying && applying.builtin;
}

/* Binds, converts, and lowers a replacement as written. */
static List _lowered(
  Compiler c, Var result, Symbol position, Type expected, Token site) {
  List bound = _bind_replacement(c, result, position, expected);
  if (position == <expression>) {
    bound = c.convert_expression(bound, expected);
    Type actual = bound.cadr();
    if (actual.canonicalize() != expected.canonicalize())
      $report.rewrite.result_type(c, site, expected, actual);
  }
  return c.normalize(bound);
}

/* prepared replacements

   A translator's replacement is its quotation's template filled with Code
   values it captured from the source, which are already bound, typed when
   they resolved, as an undeclared C function's name does not.
   Binding, conversion, and lowering treat the template's own syntax alike
   for every use with the same template and slot signatures, so the first
   lowering in a unit keeps that syntax as a skeleton with a slot for each
   captured value. A later use lowers only its values and fills the slots.
   A slot's signature is its value's type and the part of its content that
   conversion and lowering read (`_slot_shape`). The skeleton holds the
   unit's binding identities, so it lives with the unit, as a shipped rule
   whose row is bound to its unit does; a lowering inside a semantic
   transaction prepares nothing.

   The first lowering watches the captured values. Lowering must reach each
   exactly once through `Compiler.normalize`, the result must hold that
   lowering's output exactly once, and the template's own syntax must
   introduce no binding and add no generated name, origin, pending code,
   placement, or diagnostic. A template whose lowering adds such state
   tries again on its next use; one that fails otherwise, or that holds
   pending code or a carrier, lowers as written on every use. A lowered
   carrier holds no template to prepare, so it lowers as written at once. */

/** Counts compiler state that lowering adds and a skipped lowering would
    not add. A name a scope resolves binds once, so it is not counted. */
static typedef struct Effects {
  int bindings, names, origins, pending, placements, diagnostics;
} Effects;

/** Records the values a replacement's lowering watches and what lowering
    each produced, in the order lowering reached them. A watched value is
    source the translator captured, so it lowers under the `outer` rules,
    those active outside the translator's own. A first lowering `prepares`
    a skeleton from what it records. A replacement lowered as written
    within another's has that one as its `parent`, whose source it may hold
    as well. A shipped rule's replacement, a statement the kernel wrote,
    and any replacement lowered within either are `shipped`, as is a
    written definition while its function rules are chosen: their own
    code is not source, so no user rule sees it, while the values the
    watch holds are. A watch whose values are
    lowered already has them `kept` as they are. */
struct SlotWatch {
  List values;
  Array outputs, order;
  Effects inner;
  int repeated, prepares, shipped, kept;
  List outer;
  SlotWatch parent;
};

static Effects _effects(Compiler c) {
  PendingMark mark = c.pending.checkpoint();
  int pending = 0;
  for (int i = 0; i < PENDING_AREAS; i++) pending += mark.lengths[i];
  return (Effects){
    c.sym.introduced(), c.names.issued, c.origins.len(), pending,
    c.placements.len(), c.diagnostics.entries.len()};
}

static Effects _since(Effects after, Effects before) => (Effects){
  after.bindings - before.bindings, after.names - before.names,
  after.origins - before.origins, after.pending - before.pending,
  after.placements - before.placements,
  after.diagnostics - before.diagnostics};

static Effects _add(Effects a, Effects b) => (Effects){
  a.bindings + b.bindings, a.names + b.names, a.origins + b.origins,
  a.pending + b.pending, a.placements + b.placements,
  a.diagnostics + b.diagnostics};

static int _same(Effects a, Effects b) =>
  !memcmp(&a, &b, sizeof(Effects));

/* Lowers `result` from the skeleton its template and slot signatures
   prepared in this unit, preparing one on their first use. The source's
   own expressions lower outside the active rule, as they would have
   without it, so a rule applies again to a nested use. A carrier, such as
   a lowered result, never prepares and lowers as written. */
static List _prepared(
  Compiler c, List source, Var result, Symbol position, Type expected,
  Token site) {
  Array sources = $auto([]), values = $auto([]);
  _expression_nodes(source, sources);
  match (result) case %(code-value *):
    return _watched(c, result, sources, position, expected, site);
  int refused = 0;
  Var shape = _template(c, result, sources, values, refused);
  if (refused) return _watched(c, result, sources, position, expected, site);
  RewriteRule rule = c.active_rewrites.car();
  List key = %(${(int) position} ${rule.builtin} $expected $shape);
  if (!c.prepared_rewrites) c.prepared_rewrites = {};
  Var stored;
  if (c.prepared_rewrites.try_get(key, stored))
    return stored is <list>
      ? _fill_values(c, stored, values)
      : _watched(c, result, sources, position, expected, site);
  if (_carries(shape)) {
    c.prepared_rewrites[key] = 0;
    return _watched(c, result, sources, position, expected, site);
  }
  if (c.sym.transacting())
    return _watched(c, result, sources, position, expected, site);
  struct SlotWatch watch = {values.list(), [], []};
  watch.outer = c.active_rewrites.cdr();
  watch.prepares = 1;
  watch.shipped = rule.builtin;
  foreach (Var value, values) watch.outputs.push(NULL);
  Effects before = _effects(c);
  List lowered;
  $let(c.slot_watch, &watch)
    lowered = _lowered(c, result, position, expected, site);
  // A memo the template fills adds state only on its first lowering.
  if (!_same(_since(_effects(c), before), watch.inner)) return lowered;
  List skeleton = !watch.repeated && watch.order.len() == values.len()
    ? _skeleton(lowered, watch.outputs) : NULL;
  c.prepared_rewrites[key] =
    skeleton ? %($skeleton ${watch.order.list()}) : 0;
  return lowered;
}

/* Lowers `result` as written, with the source parts in it lowered outside
   the active rule. */
static List _watched(
  Compiler c, Var result, Array sources, Symbol position, Type expected,
  Token site) {
  struct SlotWatch watch = {sources.list(), [], []};
  watch.outer = c.active_rewrites.cdr();
  if (c.slot_watch && !c.slot_watch.prepares) watch.parent = c.slot_watch;
  RewriteRule rule = c.active_rewrites.car();
  watch.shipped = rule.builtin || (watch.parent && watch.parent.shipped);
  foreach (Var value, sources) watch.outputs.push(NULL);
  $let(c.slot_watch, &watch)
    return _lowered(c, result, position, expected, site);
}

/* Pushes each expression within `source`, which a translator may insert
   whole, onto `found`. A chain nests as deeply as it is long, so the walk
   keeps its pending work off the C stack. */
static void _expression_nodes(List source, Array found) {
  List syntax;
  $ast.walk(source, syntax)
    if (syntax !== source && syntax.car() == <expr>) found.push(syntax);
}

/* `node` with each expression from `sources` replaced by its slot
   signature `("x2c.slot" TYPE SHAPE)` and pushed onto `values`. A literal
   stays in the template, which then lowers it as written. Sets
   `refused` for a value inserted twice or a value whose content conversion
   or lowering reads beyond its signature. */
static Var _template(
  Compiler c, Var node, Array sources, Array values, int &refused) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  match (syntax) case %(expr ?type ?content):
    foreach (List value, sources)
      if (value === syntax)
        return _capture_slot(c, syntax, type, content, values, refused);
  Var child;
  $ast.rewrite_children(
    syntax, child, _template(c, child, sources, values, refused));
}

static Var _capture_slot(
  Compiler c, List value, Var type, Var content, Array values,
  int &refused) {
  match (content) case %(literal *): return value;
  Var shape = _slot_shape(c, content);
  foreach (List prior, values) if (prior === value) shape = void;
  if (shape is void) {
    refused = 1;
    return value;
  }
  values.push(value);
  return %("x2c.slot" $type $shape);
}

/* What conversion and lowering read of a slot value's content besides its
   type: a literal's value, whether a name is a lambda's snapshot, an
   operator with its single operand or a member access with its base, a
   group's content, or else the content's head. Void for content they read
   further, such as a conditional or a composite. */
static Var _slot_shape(Compiler c, Var content) {
  match (content) {
    case %(literal *): return content;
    case %(ident ?binding):
      return %(lambda-snapshot $binding) in c.semantic_binding_facts()
        ? %(ident snapshot) : <ident>;
    case %((!set ?head (!or call index getindex postfix cast cache)) *):
      return head;
    case %(parens (expr ? ?inner)): return _nested_shape(c, <parens>, inner);
    case %(op . (expr ? ?base) ?): return _nested_shape(c, %(op .), base);
    case %(op ?operator (expr ? ?operand)):
      return _nested_shape(c, %(op $operator), operand);
    case %(op ?operator ? ?):
      return operator == <,> ? void : %(op $operator);
  }
  return void;
}

/* `prefix` followed by the shape of `content`, or void when it has none. */
static Var _nested_shape(Compiler c, Var prefix, Var content) {
  Var shape = _slot_shape(c, content);
  return shape is void ? void : %($prefix $shape);
}

/* Whether a template holds pending code or a carrier, which binding expands
   with its slot values. */
static int _carries(Var shape) {
  if (shape is not <list>) return 0;
  match (shape)
    case %((!or code-value macro-invoke "x2c.template" "x2c.quoted") *):
      return 1;
  foreach (Var child, shape.list()) if (_carries(child)) return 1;
  return 0;
}

/* `lowered` with each watched output replaced by its `("x2c.slot" I)`
   marker, or NULL unless each occurs exactly once and the code holds no
   anchor, block, sequence, statement, or declaration, whose lowering gives
   a slot a context that lowering the value alone would not. */
static List _skeleton(List lowered, Array outputs) {
  Array found = $auto([]);
  foreach (Var output, outputs) found.push(0);
  int refused = 0;
  List skeleton = _marked(lowered, outputs, found, refused);
  foreach (Var count, found) if (count.int() != 1) refused = 1;
  return refused ? NULL : skeleton;
}

static Var _marked(Var node, Array outputs, Array found, int &refused) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  for (int i = 0; i < (int) outputs.len(); i++)
    if (outputs[i].list() === syntax) {
      found[i] = found[i].int() + 1;
      return %("x2c.slot" $i);
    }
  match (syntax)
    case %((!or at block seq stmnt decl declare) *): refused = 1;
  List child;
  $ast.rewrite_children(
    syntax, child, _marked(child, outputs, found, refused));
}

/* Lowers each slot's value, outside the active rule, in the order the
   first lowering reached them and fills the skeleton with the results. */
static List _fill_values(Compiler c, List prepared, Array values) {
  (List skeleton, List order) = prepared;
  Array lowered = $auto(values.copy());
  $let(c.active_rewrites, c.active_rewrites.cdr())
    foreach (Var slot, order)
      lowered[slot.int()] = c.normalize(values[slot.int()]);
  return _filled(skeleton, lowered);
}

static Var _filled(Var node, Array lowered) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  Var head = syntax.car();
  if (head is <string> && head == "x2c.slot")
    return lowered[syntax.cadr().int()];
  Var child;
  $ast.rewrite_children(syntax, child, _filled(child, lowered));
}

/* The index of `ast` among the values `watch` watches, or -1. A statement
   that binding the replacement built again from a value keeps the value's
   origin. */
static int _find_slot(SlotWatch watch, Ast ast) {
  int slot = 0, at = ast.car() == <at>;
  for (List v = watch.values; v; v = v.cdr(), slot++) {
    List value = v.car();
    if (value === ast ||
        (at && value.car() == <at> && value.cadr() == ast.cadr()))
      return slot;
  }
  return -1;
}

/** Records that binding built the statement `bound` again from `source`,
    a value the active lowering watches, so it watches `bound` as well. A
    statement without an origin, such as an unbraced body, keeps nothing
    else that identifies it when a binder it uses binds again. */
void Compiler.rebound(Compiler c, Var source, List bound) {
  SlotWatch watch = c.slot_watch;
  if (!watch || watch.prepares || bound === source ||
      _find_slot(watch, source) < 0)
    return;
  watch.values = watch.values.append(%($bound));
  watch.outputs.push(NULL);
}

/** Lowers `ast` when it is a value the active first lowering watches and
    records what its lowering produced; NULL otherwise. A value that an
    enclosing replacement's source held as well lowers outside that
    replacement's rule too, and that replacement still watches its own
    values within it. */
Ast Compiler.watched_step(Compiler c, Ast ast) {
  SlotWatch watch = c.slot_watch, owner = watch;
  int slot = _find_slot(watch, ast);
  if (slot < 0) return NULL;
  while (owner.parent && _find_slot(owner.parent, ast) >= 0)
    owner = owner.parent;
  if (owner.kept) return ast;
  Effects before = _effects(c);
  Ast lowered;
  $let(c.slot_watch, owner.parent) $let(c.active_rewrites, owner.outer)
    lowered = c.normalize(ast);
  watch.inner = _add(watch.inner, _since(_effects(c), before));
  if (watch.outputs[slot].list_payload()) watch.repeated = 1;
  watch.outputs[slot] = lowered;
  watch.order.push(slot);
  return lowered;
}

/* invocation recognition

   At each syntax position the parser asks whether the tokens start an
   invocation it should claim. Recognition consumes nothing; a claimed
   invocation's name is consumed once its definition is known. */

/** Returns whether the parser claims the macro invocation at the cursor for
    `position`. A bare keyword alias is claimed only where its result fits.
    This query does not consume tokens.
*/
int Compiler.macro_starts_target_at(Compiler c, Symbol position) =>
  _claims(c, _peek_invocation(c), position);

/* An invocation is claimed where its result fits. A statement or map entry
   that does not fit parses as an expression. Elsewhere a `$` name, or an
   identifier with arguments, is claimed so that its target parser reports
   the position diagnostic; a local expression macro at block scope remains
   an expression statement. */
static int _claims(Compiler c, List definition, Symbol position) {
  Symbol kind = definition ? _result_kind(definition) : 0;
  if (kind == _position(position).kind) return 1;
  if (position == <statement> || position == <map-entry>) return 0;
  if (!definition) {
    if (c.peek(0) == <$> && (position == <block> || c.macro_holes) &&
        _meta_callee(c).is_function())
      return 0;
    return c.peek(0) == <$>;
  }
  return !_bare(c.token, definition) &&
    (position != <block> || kind != <expression> ||
     !definition.assoc(<local>).int());
}

/* Returns the type of the identifier a `$` meta call reads, as in
   `$Code.type(value)`, when that identifier spans the whole `$` name.
   Consumes no tokens. A missing package member is left to the invocation
   diagnostic. */
static Type _meta_callee(Compiler c) {
  Token start = c.token;
  String name;
  Token end = _scan_name(c, name);
  c.next();
  String member = c.package_alias_spelling();
  List callee = name && (!member || c.sym.get_exact(%($member)))
              ? c.parse_complex_identifier() : NULL;
  Type type = callee && c.token == end ? c.sym.get(callee) : NULL;
  c.token = start;
  return type;
}

static typedef struct MacroPos {
  Symbol kind, const char *description, int semicolon;
} MacroPos;

static const SymbolSet macro_positions =
  %<<unit block field enumerator map-entry statement expression>>;

static const MacroPos macro_position_info[] = {
  { <unit>,       "file scope",    1 },
  { <block-item>, "block scope",   1 },
  { <field>,      "field scope",   1 },
  { <enumerator>, "an enum body",  0 },
  { <map-entry>,  "a map literal", 0 },
  { <block-item>, "block scope",   1 },
  { <expression>, "an expression", 0 }
};

static const MacroPos *_position(Symbol position) =>
  &macro_position_info[macro_positions.index(position)];

static Symbol _result_kind(List definition) {
  Symbol kind = definition.assoc(<kind>);
  if (kind != <decorator>) return kind;
  Symbol target = definition.assoc(<target>);
  if (target == <function> || target == <unit> || target == <named-type>)
    return <unit>;
  if (target == <block>) return <block-item>;
  if (target == <expr>) return <expression>;
  return target;
}

/* Returns the definition invoked at the cursor without consuming tokens, or
   NULL. A `$` name invokes its visible definition. An identifier invokes the
   innermost local macro of that name, or else its keyword alias, when an
   argument list follows or the invocation is bare. */
static List _peek_invocation(Compiler c) {
  Var stored;
  if (c.peek(0) == <$> || c.peek(0) == <@>) {
    String spelling;
    _scan_name(c, spelling);
    if (!spelling ||
        !_try_definition(c, Atom.intern(spelling), !c.shallow, stored))
      return NULL;
    return stored;
  }
  if (c.peek(0) != <ident>) return NULL;
  Atom name = Atom.intern(c.token.text);
  List definition = c.sym.has_local_macros()
                  ? c.sym.lookup_macro(name) : NULL;
  if (!definition && _try_macro(c, c.kw_aliases, name, stored))
    definition = stored;
  return definition && (c.peek(1) == <(> || _bare(c.token, definition))
       ? definition : NULL;
}

/* Scans the dotted name after the current `$` without consuming tokens.
   A component after a dot may be a keyword, as in `$error.arg.void`.
   Returns the token after the name, or the token where a name component is
   missing with `spelling` set to NULL. */
static Token _scan_name(Compiler c, String &spelling) {
  Token token = c.token, String name = NULL;
  do {
    token = Token.skip_trivia(token + 1);
    if (token.type != <ident> &&
        !(name && scan_keyword_type(token.text, token.text.len()))) {
      name = NULL;
      break;
    }
    name = name ? %"$name.${token.text}" : token.text;
    token = Token.skip_trivia(token + 1);
  } while (token.type == <.>);
  spelling = name;
  return token;
}

/* An identifier invoking a decorator without explicit parameters has no
   argument list. */
static int _bare(Token invocation, List definition) =>
  invocation.type != <$> && invocation.type != <@> &&
  definition.assoc(<kind>) == <decorator> &&
  !definition.assoc(<parameters>).list();

/* Consumes the name of an invocation claimed at `position` and returns its
   definition, or returns NULL without consuming tokens. A `$` name that is
   neither visible nor followed by arguments is a replacement variable
   missing from a template. */
static List _take_invocation(Compiler c, Symbol position) {
  List definition = _peek_invocation(c);
  if (!_claims(c, definition, position)) return NULL;
  if (c.peek(0) != <$> && c.peek(0) != <@>) {
    c.next();
    return definition;
  }
  Token invocation = c.token;
  Atom name = _name(c);
  Var existing;
  if (c.macro_holes && c.peek(0) != <(> &&
      !_try_definition(c, name, 1, existing))
    _unbound(c, name.str(), invocation);
  return _lookup(c, name, invocation);
}

static Atom _name(Compiler c) {
  String spelling;
  Token end = _scan_name(c, spelling);
  if (!spelling)
    $report.parse.macro_name(c, end);
  c.token = end;
  return Atom.intern(spelling);
}

static List _lookup(Compiler c, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!_try_definition(c, name, 1, stored))
    $report.parse.macro_unbound(c, spelling, invocation);
  return stored;
}

/* With `install_lisp`, a `lisp.` name records the Lisp binding macros as a
   dependency and installs them when the name is not yet defined. */
static int _try_definition(
  Compiler c, Atom name, int install_lisp, Var &stored) {
  int found = _try_macro(c, c.macros, name, stored);
  String spelling = name.str();
  if (!install_lisp || !spelling.startswith("lisp.")) return found;
  _use_lisp_bindings(c, !found);
  return found || _try_macro(c, c.macros, name, stored);
}

/* Includes publish names immediately. Decode a template into this unit's
   bindings only when it is used, keeping the result in the same name map. */
static int _try_macro(
  Compiler c, Map definitions, Atom name, Var &stored) {
  if (!definitions.try_get(name, stored)) return 0;
  match (stored) case %(imported-macro ?definition): {
    stored = _rebind_imported(c, c.thaw_declaration_syntax(definition));
    c.sym.put(definitions, name, stored);
  }
  return 1;
}

// shallow collection

/** Returns how collection treats the macro invocation at the cursor.
    `<required>` covers every file-scope `Unit` macro, declaration-unit macro,
    named-type decorator, and local `Unit` macro whose template contains
    protocol or adoption rows. `<tried>` covers Unit decorators and other
    local `Unit` macros. Other invocations return zero.
*/
Symbol Compiler.macro_invocation_collection(Compiler c) =>
  _collection(_peek_invocation(c));

static Symbol _collection(List definition) {
  if (!definition) return 0;
  if (definition.assoc(<kind>) == <decl-unit> ||
      definition.assoc(<target>) == <named-type>) return <required>;
  if (definition.assoc(<target>) == <unit>) return <tried>;
  if (definition.assoc(<kind>) != <unit>) return 0;
  if (!definition.assoc(<local>).int()) return <required>;
  List template = definition.assoc(<template>), bindings;
  Var matched;
  if (template.try_search(%(!or (protocol *) (adopt *)), matched, bindings))
    return <required>;
  return <tried>;
}

/** Consumes a macro invocation name and its balanced argument list.
    The invocation terminator or following decorator target remains current.
*/
void Compiler.skip_macro_invocation(Compiler c) {
  int bare = _bare(c.token, _peek_invocation(c));
  String spelling;
  if (c.peek(0) == <$>) c.token = _scan_name(c, spelling);
  else c.next();
  if (!bare && c.peek(0) == <(>) c.token = c.token.after_group();
}

/** Consumes a NamedType target already projected by owning-source collection.
    CPP scanning does not produce the declaration or parse its fields again.
*/
int Compiler.skip_named_type_declaration(Compiler c) {
  List definition = _peek_invocation(c);
  if (!definition || definition.assoc(<target>) != <named-type>) return 0;
  c.skip_macro_invocation();
  _x2c_skip_shallow_expression(c, 0);
  c.expect(<;>);
  return 1;
}

/** Reports whether the macro invocation at the cursor produces file-scope
    syntax, directly or through the target it decorates. A script unit keeps
    such an invocation at file scope. This query does not consume tokens.
*/
int Compiler.macro_targets_unit(Compiler c) {
  List definition = _peek_invocation(c);
  if (!definition) return 0;
  Symbol kind = _result_kind(definition);
  return kind == <unit> || kind == <decl-unit>;
}

/* invocation arguments

   Each parameter hole captures its arguments into one capture row, and a
   captured argument records the source span it was parsed from. */

static List _invocation_arguments(
  Compiler c, List definition, Token invocation) {
  if (_bare(invocation, definition)) return %(args);
  Array arguments = [];
  // The first Param hole opens one scope for the rest of the arguments.
  int parameter_scope = 0;
  defer { if (parameter_scope) c.sym.pop_scope(); }
  c.expect(<(>);
  List descriptors = definition.assoc(<parameters>);
  for (List nodes = descriptors; nodes; nodes = nodes.cdr()) {
    List hole = nodes.car();
    Symbol kind = hole.assoc(<kind>);
    if (kind == <param> && !parameter_scope) {
      c.sym.push_new_scope();
      parameter_scope = 1;
    }
    arguments.push(_argument_row(c, hole, kind));
    if (nodes.cdr() && c.peek(0) != <)>) _argument_separator(c, kind);
  }
  if (c.peek(0) != <)>) {
    if (c.peek(0) == <,>) c.next();
    $report.parse.macro_extra_args(c);
  }
  c.expect(<)>);
  return %(args @{arguments.list_free()});
}

/* The arguments one hole captures: one, or a comma-separated sequence. A
   MatchRow hole also takes the directives around its rows. */
static List _argument_row(Compiler c, List hole, Symbol kind) {
  int sequence = hole.assoc(<sequence>);
  Array captured = [];
  if (c.peek(0) == <)> && !sequence)
    $report.parse.macro_missing_args(c);
  if (c.peek(0) != <)>) loop {
    _row_directives(c, kind, captured);
    Token first = c.token;
    Var argument = _parse_argument(c, kind);
    if (kind != <name>)
      argument = _capture_source(c, argument, first, c.token);
    captured.push(argument);
    if (!sequence || !c.test(<,>)) break;
  }
  _row_directives(c, kind, captured);
  return _capture_row_project(c, hole, captured.list_free(), 0);
}

static void _row_directives(Compiler c, Symbol kind, Array captured) {
  if (kind == <match-row> && c.token != c.directives_taken)
    foreach (List directive, c.leading_preproc()) captured.push(directive);
}

/* `in` may separate a declaration from what follows, as in
   `foreach (String line in lines)`. Before a literal it scans as a name,
   which cannot follow a declaration either. */
static void _argument_separator(Compiler c, Symbol kind) {
  if (kind == <decl> && (c.peek(0) == <in> || c.at_word("in"))) c.next();
  else c.expect(<,>);
}

static Var _parse_argument(Compiler c, Symbol kind) {
  // Captures retain complete syntax even while collection skips other bodies.
  $let(c.shallow, 0) {
    if (!kind) return c.parse_assignment();
    switch (kind) {
      case <expr>:       return c.parse_assignment();
      case <type>:       return c.parse_type_name();
      case <named-type>: return c.parse_named_type();
      case <decl>:       return c.parse_declaration_argument();
      case <decl-row>:   return c.parse_declarator_argument();
      case <function>:   return c.parse_function_definition();
      case <param>:      return c.parse_parameter();
      case <block>:      return c.parse_block_item();
      case <field>:      return c.parse_field(%(struct ()));
      case <enumerator>: return c.parse_enumerator(c.aggregate_type);
      case <map-entry>:  return c.parse_map_entry();
      case <match-row>:  return c.parse_match_row_argument();
      case <unit>:       return c.parse_top_level();
      case <name>:       return _name_argument(c);
      case <literal>:    return _literal_argument(c);
    }
    $report.macro.argument_contract(c);
  }
}

/* A caller's name is a spelling, resolved where the expansion places it.
   A name a template writes is private to each expansion: a nested
   declaration made from it is that expansion's, and a reference that no
   such declaration reaches reads its spelling where the expansion lands. */
static Var _name_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return _parse_hole(c, <name>);
  if (c.peek(0) != <ident>)
    $report.parse.name_identifier(c);
  String spelling = c.token.text;
  c.next();
  if (!c.macro_holes) return spelling;
  List visible = c.sym.lookup(%($spelling), NULL);
  if (visible && visible in c.macro_definition_locals()) return visible;
  List local = c.macro_introduced_name(spelling);
  c.bind_template_local(local, NULL, NULL);
  c.macro_definition_locals()[%(name-argument $spelling)] = local;
  return local;
}

static Var _literal_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c.parse_assignment();
  return c.parse_atomic_literal();
}

static Var _capture_source(
  Compiler c, Var syntax, Token first, Token after) {
  if (c.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = _previous_source_token(c, after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = c.source_path(c.filename ? c.filename : "<stdin>");
  List source = %(source $file ${first.pos} $end);
  return %(src $source $syntax);
}

static Token _previous_source_token(Compiler c, Token after) {
  Token first = (void *) c.tokenizer.tokens;
  if (!after || after <= first) return NULL;
  Token token = after - 1;
  while (token > first &&
         (token.type == <space> || token.type == <comment> ||
          token.type == <preproc>)) token--;
  return token;
}

/* A Block decorator's Name arguments are referenced in the block's scope,
   which opens before the arguments are read. */
static void _bind_name_arguments(
  Compiler c, List definition, List arguments) {
  List parameters = definition.assoc(<parameters>);
  List captures = arguments.cdr();
  while (parameters) {
    List parameter = parameters.car();
    if (parameter.assoc(<kind>) == <name>) {
      Var names = captures.car().list().assoc(<value>);
      List values = parameter.assoc(<sequence>).int()
                  ? names : %($names);
      foreach (Var value, values) {
        String name = value is <list>
          ? Ast.binding_spelling(value) : value;
        c.sym.reference(%($name), NULL);
      }
    }
    parameters = parameters.cdr();
    captures = captures.cdr();
  }
}

/* capture rows

   A capture row keeps an argument's exact source apart from its syntax
   projections. Forwarding a template's own projection rebuilds the row it
   came from, with its Unit construction requirements, and assigns no
   source text to generated syntax. */

/* `retain` keeps each source as the syntax it is and forwards nothing. */
static List _capture_row_project(
  Compiler c, List hole, List sources, int retain) =>
  hole.assoc(<sequence>).int()
    ? _sequence_row(c, sources, retain)
    : _scalar_row(c, sources, retain);

/* A forwarded projection contributes its own sources, values, and
   construction requirements. */
static List _sequence_row(Compiler c, List sources, int retain) {
  Array captured_sources = [], values = [], construction = [];
  foreach (Var captured, sources) {
    List forwarded = retain ? NULL : _forwarded_capture(c, captured);
    match (forwarded)
      case %(capture (source *forwarded_sources)
                     (value *forwarded_values) ? ? *required): {
        foreach (Var item, forwarded_sources) captured_sources.push(item);
        foreach (Var item, forwarded_values) values.push(item);
        foreach (Var item, required) construction.push(item);
        continue;
      }
    captured_sources.push(captured);
    values.push(retain ? captured : _source_unwrap(captured));
  }
  return _capture_layout(
    1, %(source @{captured_sources.list_free()}),
    %(value @{values.list_free()}), NULL, NULL, construction.list_free());
}

/* One source may be a forwarded projection. Any other number of sources
   keeps the sequence layout. */
static List _scalar_row(Compiler c, List sources, int retain) {
  int singular = sources && !sources.cdr();
  Var source = singular ? sources.car() : sources;
  if (singular && !retain) {
    List forwarded = _forwarded_capture(c, source);
    if (forwarded) return forwarded;
  }
  Var value = retain ? source : _source_unwrap(source);
  List values = value is <list> ? value : NULL;
  if (!singular)
    return _capture_layout(
      1, %(source @sources), %(value @values), NULL, NULL, NULL);
  Var expression = _identifier_expression(value);
  return _capture_layout(
    0, %(source $source), %(value $value), %(expression $expression),
    %(splice @values), NULL);
}

static Var _identifier_expression(Var value) {
  if (value is <string>) return %(expr () (ident $value));
  match (value) case %("x2c.ident" ?): return %(expr () (ident $value));
  if (value is <list> && !value.is_nil() &&
      Ast.try_binding(value, NULL, NULL))
    return %(expr () (ident $value));
  return value;
}

/* The row of a projection a template forwards as an argument. A Unit
   hole's source stands for each of its projections. */
static List _forwarded_capture(Compiler c, Var captured) {
  List hole = _forwarded_hole(c, captured);
  if (!hole) return NULL;
  Var source = _hole_key(hole, "source");
  Symbol kind = hole.assoc(<kind>);
  if (kind == <unit>)
    return _capture_layout(
      0, %(source $source), %(value $source), %(expression $source),
      %(splice), %(${_hole_key(hole, "construction")}));
  if (kind != <expr> && kind != <name>) return NULL;
  return _capture_layout(
    0, %(source $source), %(value ${_hole_key(hole, "value")}),
    %(expression ${_hole_key(hole, "expression")}),
    %(splice ${_hole_key(hole, "splice")}), NULL);
}

/* The hole whose projection binder `captured` is, when a template passes
   one of its own projections as an argument. */
static List _forwarded_hole(Compiler c, Var captured) {
  if (!c.macro_holes || captured is not <list> || captured.is_nil())
    return NULL;
  Var direct = void;
  match (captured) {
    case %(expr (<macro-expr>)
           (macro-bind ?slot)): direct = slot;
    case %(macro-bind ?): direct = captured.list().cadr();
  }
  if (direct is void) return NULL;
  String spelling = direct.str(), prefix = _forwarded_prefix(spelling);
  if (!prefix) return NULL;
  return _hole_record(c, Atom.intern(spelling[prefix.len():]));
}

static String _forwarded_prefix(String spelling) {
  foreach (String prefix, forwarded_prefixes)
    if (spelling.startswith(prefix)) return prefix;
  return NULL;
}

/* Forwarding recognizes the projection binders _capture_pattern creates, so
   the accepted prefixes come from Macro.binder; <?> supplies its
   empty author name. */
static List _forwarded_prefix_list(void) {
  Array prefixes = [];
  Map seen = {};
  foreach (String projection, %("expression" "value" "source" "splice"))
    for (int sequence = 0; sequence <= 1; sequence++) {
      String prefix = Macro.binder(<?>, projection, sequence).str();
      if (prefix in seen) continue;
      seen[prefix] = 1;
      prefixes.push(prefix);
    }
  return prefixes.list_free();
}

static List forwarded_prefixes = _forwarded_prefix_list();

/* `(src (source FILE BEGIN END) SYNTAX)` records one complete caller argument
   or decorator target. Constructed syntax can reproduce that List shape, so
   source access trusts only captured syntax identities registered for the
   active expansion. Forwarding preserves the registered capture. */
static int _source_capture_parts(Var value, List &?source, Var &?syntax) {
  match (value)
    case %(src ?record ?captured): {
      if (source) source = record;
      if (syntax) syntax = captured;
      return 1;
    }
  return 0;
}

/* `value` without its source wrappers. A pending invocation or quotation
   inside it keeps its own capture rows or holes, so nested applications
   unwrap each argument once. */
static Var _source_unwrap(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %(src ? ?syntax): return _source_unwrap(syntax);
    case %((!or macro-invoke "x2c.quoted") *): return value;
  }
  List child;
  $ast.rewrite_children(value.list(), child, _source_unwrap(child));
}

/* invocations at syntax positions

   A claimed invocation at file, block, statement, field, enumerator, or
   map-entry position parses its arguments; a decorator also parses the
   target that follows it. */

/** Parses a direct or keyword-alias macro at the requested syntax position.
    Returns NULL without consuming a macro hole or an invocation that
    `macro_starts_target_at` does not claim; template parsing returns a
    deferred `(seq (macro-invoke ...))`, and ordinary parsing returns the bound
    expansion.
*/
List Compiler.try_parse_macro_target_at(Compiler c, Symbol position) =>
  _target_at(c, position, 0);

/* An `open` statement omits its final `;`, as an anonymous Stmt arrow's
   statement does. */
static List _target_at(Compiler c, Symbol position, int open) {
  if (c.macro_holes && c.peek_macro_hole()) return NULL;
  Token invocation = c.token;
  List definition = _take_invocation(c, position);
  if (!definition) return NULL;
  if (definition.assoc(<kind>) == <decorator>)
    return _decorate(c, definition, invocation, position, open);
  _check_position(c, definition, invocation, position);
  return _invoke_definition(c, definition, invocation, position, open);
}

/* A macro's result must fit where it is invoked; a Declaration result also
   fits at file scope. */
static void _check_position(
  Compiler c, List definition, Token invocation, Symbol position) {
  Symbol kind = definition.assoc(<kind>);
  const MacroPos *place = _position(position);
  if (kind == place.kind || (kind == <decl-unit> && position == <unit>))
    return;
  Atom name = definition.assoc(<name>);
  String spelling = name.str(), result_kind = _kind_spelling(kind);
  $report.macro.result_position(
    c,
    spelling, result_kind, place.description, invocation);
}

/* Invocation parsing and expansion share one semantic transaction. Empty
   generated syntax and raised diagnostics therefore cannot leave provisional
   bindings, enumerators, statics, or generated-name state behind. */
static List _invoke_definition(
  Compiler c, List definition, Token invocation, Symbol position, int open) {
  int deferred = !!c.macro_holes;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  List input = _invocation_arguments(c, definition, invocation);
  if (_position(position).semicolon && !open) c.expect(<;>);
  List node = _invocation_node(c, definition, input, invocation);
  List result = deferred ? %(seq $node) :
    c.bind_syntax(node, position, c.return_type);
  if (result.car() != <seq> || result.len() != 1 ||
      transaction.local_macros_changed()) transaction.commit();
  return result;
}

/* Inside a template the node names its definition as the expansion will
   find it: a definition that is itself template syntax by value, a local
   macro by its local name, and any other macro by name. */
static List _invocation_node(
  Compiler c, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (c.macro_holes) {
    stored = _stored_reference(c, definition);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

/* A template names a visible local macro, so its expansion applies the
   definition published where it lands, with that expansion's names. */
static Var _stored_reference(Compiler c, List definition) {
  Atom name = definition.assoc(<name>);
  if (definition.assoc(<local>).int() &&
      c.sym.lookup_macro(name) == definition)
    return %(local-macro $name);
  if (definition.assoc(<template>)) return %(!quote $definition);
  return name;
}

/* decorators

   A decorator application parses the decorator's arguments and then its
   target. Parsing the target can publish symbols before the replacement is
   known, so one semantic transaction stages the target and the expansion
   and a rejection rolls both back. */

/* One decorator application. A Block decorator standing before a
   file-scope function decorates that function's body, so one spelling
   covers a statement and a whole function; `function` holds the function
   then. */
static typedef struct Decoration {
  Compiler c, List definition, function, Token invocation, start;
  Symbol position, Symbol kind, int open;
} Decoration;

static List _decorate(
  Compiler c, List definition, Token invocation, Symbol position, int open) {
  Decoration d = {
    .c = c, .definition = definition, .invocation = invocation,
    .position = position, .kind = definition.assoc(<target>), .open = open};
  int deferred = !!c.macro_holes;
  if (!_on_body(d) && _result_kind(definition) != _position(position).kind)
    _misplaced(d);
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  int block_scope = !c.macro_holes && d.kind == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  List node = _decoration_node(d, _arguments(d, block_scope));
  if (deferred) {
    transaction.commit();
    return %(seq $node);
  }
  List result = _bind_decoration(d, node);
  $let(c.token, invocation) {
    transaction.commit();
  }
  return result;
}

static int _on_body(Decoration &d) =>
  d.kind == <block> && d.position == <unit>;

static void _misplaced(Decoration &d) {
  Atom name = d.definition.assoc(<name>);
  String spelling = name.str(), target = _kind_spelling(d.kind);
  $report.macro.decorator_position(d.c, spelling, target, d.invocation);
}

static List _arguments(Decoration &d, int block_scope) {
  Compiler c = d.c;
  List definition = d.definition;
  List arguments = _invocation_arguments(c, definition, d.invocation);
  if (block_scope) _bind_name_arguments(c, definition, arguments);
  if (c.peek(0) == <;>)
    $report.macro.decorator_semicolon(
      c,
      d.invocation, _definition_note(definition));
  if (c.peek(0) == <eof>) {
    Atom name = definition.assoc(<name>);
    String spelling = name.str();
    $report.macro.decorator_target(
      c,
      spelling, d.invocation, _definition_note(definition));
  }
  return arguments;
}

static List _decoration_node(Decoration &d, List arguments) {
  Compiler c = d.c;
  d.start = c.token;
  List target = _target(d);
  if (d.position == <statement>) target = c.anchor_origin(target, d.start);
  List target_capture = _capture(d, target);
  List input = %(
    target $arguments
    $target_capture
  );
  return _invocation_node(c, d.definition, input, d.invocation);
}

static List _target(Decoration &d) {
  Compiler c = d.c;
  if (_on_body(d)) {
    d.function = c.parse_function_definition();
    match (d.function) case %(function ? ? ?body): return body;
    return NULL;
  }
  if (d.kind == <function>) return c.parse_function_target();
  if (d.kind == <named-type>) return c.parse_named_type();
  if (d.open) return _arrow_statement(c, 1);
  return _positional_target(c, d.position);
}

static List _positional_target(Compiler c, Symbol position) {
  switch (position) {
    case <unit>:
      $let(c.capture_unit, 1) return c.parse_top_level();
    case <block>: case <statement>:
      return c.parse_governed(position);
    case <field>:      return c.parse_field(c.aggregate_type);
    case <enumerator>: return c.parse_enumerator(c.aggregate_type);
    case <map-entry>:  return c.parse_map_entry();
    default: __builtin_unreachable();
  }
}

/* The target's capture row. A public Unit target of one item also carries
   that item as the construction the template requires. */
static List _capture(Decoration &d, List target) {
  Compiler c = d.c;
  List targets = target.car() == <seq> ? target.cdr() : %($target);
  Array captured_targets = [];
  foreach (Var item, targets)
    captured_targets.push(_capture_source(c, item, d.start, c.token));
  List captured = captured_targets.list_free();
  List target_capture =
    _capture_row_project(c, d.definition.assoc(<targetp>), captured, 0);
  if (d.kind == <unit> && !_private_target(c, target) &&
      captured && !captured.cdr())
    target_capture = target_capture.append(%((construct ${captured.car()})));
  return target_capture;
}

/* Visibility comes from a static declaration,
   seen through a lone `seq` and a foreign alias. */
static int _private_target(Compiler c, List target) {
  int private_target = c.source_private > 0;
  List visibility_target = target;
  match (visibility_target)
    case %(seq ?only): visibility_target = only;
  match (visibility_target)
    case %(falias ?declaration ?): visibility_target = declaration;
  match (visibility_target)
    case %((!or function declare typedef) ?type *):
      private_target |= type.type().is_static();
  return private_target;
}

static List _bind_decoration(Decoration &d, List node) {
  Compiler c = d.c;
  if (!_on_body(d)) return c.bind_syntax(node, d.position, c.return_type);
  return _bind_body(c, node, d.function);
}

/* The body was bound with the function's own result type; bind the
   produced items with it too, so a `return` that needs a conversion still
   gets one. */
static List _bind_body(Compiler c, List node, List decorated) {
  Type declared = _declared_result(decorated);
  List result = NULL;
  $let(c.return_type, declared) {
    result = c.bind_syntax(node, <block>, c.return_type);
  }
  List items = result.car() == <seq> ? result.cdr() : %($result);
  match (decorated) case %(function ?rtype ?declarator ?):
    result = %(seq (function $rtype $declarator (block @items)));
  return result;
}

static Type _declared_result(List decorated) {
  Type declared = NULL;
  match (decorated) case %(function ?rtype ?declarator ?): {
    List declaration = %(declare $rtype (bindings $declarator));
    match (declaration.type_from_ast())
      case %((func *) *result_type):
        declared = result_type.type().declared();
  }
  return declared;
}

/* expression invocations

   In an expression, a `$` name without arguments is a Macro value, and a
   `$` call of a function is an explicit meta call. An Expression macro or
   decorator becomes a `macro-invoke` node that binding expands. */

/** Parses and resolves a direct or keyword-alias expression macro.
    Returns NULL without consuming an identifier that is not an applicable
    alias; a direct `$` invocation must resolve to a visible expression form.
*/
List Compiler.try_parse_macro_expression(Compiler c) {
  Token invocation = c.token;
  if (c.peek(0) == <$>) {
    List value = _named_macro_value(c, invocation);
    if (value) return value;
  }
  if ((c.peek(0) == <$> || c.peek(0) == <@>) && !_peek_invocation(c))
    return _parse_meta_call(c, invocation);
  List definition = _take_invocation(c, <expression>);
  if (!definition) return NULL;
  return c.resolve_expression(
    _expression_invocation(c, definition, invocation), invocation);
}

/* Returns the Macro value a `$` name without arguments names. Otherwise the
   cursor returns to the `$`. */
static List _named_macro_value(Compiler c, Token invocation) {
  Atom name = _name(c);
  if (c.peek(0) != <(>) {
    List value = _macro_value(c, name);
    if (value) return value;
  }
  c.token = invocation;
  return NULL;
}

static List _parse_meta_call(Compiler c, Token invocation) {
  c.next();
  /* A meta function is called by its compile-time binding, even from a
     template, whose other free names bind where the expansion lands. */
  List callee = NULL;
  $let(c.macro_holes, NULL) callee = c.parse_variable();
  Type signature = callee.cadr();
  if (!signature.is_function()) {
    c.token = invocation;
    Atom name = _name(c);
    (void) _lookup(c, name, invocation);
  }
  Array arguments = _meta_arguments(c, signature.car().list().cadr());
  Type result = c.macro_holes ? %(<macro-expr>) : signature.cdr();
  /* Inside a `meta` body the whole body runs at compile time, so a `$`
     call there is an ordinary call, except in a pattern, whose binders
     come from its value. */
  Symbol head = c.meta_body && !c.macro_holes && !c.in_pattern
    ? <call> : <meta-call>;
  List call = %(expr $result ($head $callee
    (args @{arguments.list_free()})));
  return c.resolve_expression(call, invocation);
}

/* Each argument converts to its parameter's type, except in a template. */
static Array _meta_arguments(Compiler c, List parameters) {
  Array arguments = [];
  c.expect(<(>);
  if (c.peek(0) != <)>) loop {
    List argument = _meta_argument(c);
    if (parameters && !c.macro_holes)
      argument = c.convert_expression(argument, parameters.car());
    parameters = parameters.cdr();
    arguments.push(argument);
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return arguments;
}

/* A hole passed alone passes the value it captures, and a sequence hole
   passes its captured items as one List. */
static List _meta_argument(Compiler c) {
  List hole = c.peek_macro_hole();
  Symbol next = hole ? c.after_hole().type : 0;
  int direct = next == <,> || next == <)>;
  if (direct && hole.assoc(<sequence>).int()) {
    c.expect(<$>);
    c.next();
    return %(expr ("List") (meta-cap (${_hole_key(hole, "value")})));
  }
  Symbol kind = hole ? hole.assoc(<kind>) : 0;
  List argument = direct
    ? %(expr (<macro-expr>) ${_parse_hole(c, kind ? kind : <argument>)})
    : c.parse_assignment();
  if (hole && argument.match(%(expr ? (macro-bind ?)))) {
    Atom projection = Macro.binder(hole.assoc(<binder>), "value", 0);
    argument = %(expr ("List") (meta-cap $projection));
  }
  return argument;
}

static List _expression_invocation(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return _expression_decorator(c, definition, invocation);
  if (c.meta_body && (kind == <unit> || kind == <block-item>))
    return _template_call(c, definition);
  List arguments = _invocation_arguments(c, definition, invocation);
  if (kind != <expression>) _not_expression(c, definition, invocation);
  List node = _invocation_node(c, definition, arguments, invocation);
  return %(expr (<macro-expr>) $node);
}

/* In a `meta` body, invoking a Unit or Stmt macro is a template call,
   whose syntax the meta function builds when it runs. */
static List _template_call(Compiler c, List definition) {
  Array arguments = [];
  c.expect(<(>);
  foreach (List hole, definition.assoc(<parameters>).list()) {
    if (arguments.len()) c.expect(<,>);
    arguments.push(c.parse_assignment());
  }
  c.expect(<)>);
  Var stored = definition.assoc(<local>).int()
    ? definition : definition.assoc(<name>);
  return %(expr ("List") (tpl-call $stored
    (args @{arguments.list_free()})));
}

static void _not_expression(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  String spelling = definition.assoc(<name>).str();
  $report.macro.result_expr(
    c,
    kind, spelling, invocation, _definition_note(definition));
}

static List _expression_decorator(
  Compiler c, List definition, Token invocation) {
  List arguments = _invocation_arguments(c, definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    $report.macro.decorator_expr(
      c,
      spelling, invocation, _definition_note(definition));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    ${_capture_row_project(c, definition.assoc(<targetp>), %($target), 0)}
  );
  List node = _invocation_node(c, definition, input, invocation);
  return %(expr (<macro-expr>) $node);
}

/* template slots

   A slot in a template, `$(...)` or a meta call, runs while its expansion
   binds. Its value fills the slot, and a splice slot's List becomes rows. */

/** Evaluates an active template's `(macro-slot ...)` value, or a pending
    Macro value application into the invocation that expands it.
    Non-slots and slots outside an expansion are returned unchanged. A splice
    slot's `List` result is wrapped as `(seq ...)` for its syntax position.
*/
Var Compiler.evaluate_macro_slot(Compiler c, Var value) {
  if (value is not <list>) return value;
  List slot = value;
  if (slot.car() == "x2c.template") return _helper_result(c, value);
  if (slot.car() != <macro-slot>) return value;
  if (c.macro_holes || !c.macro_stack) return value;
  return _slot_value(c, slot);
}

/* A Lisp form evaluates with the active expansion's bindings, and a meta
   call runs. A construction requirement travels with an identifier the
   slot built, and a splice slot around a Unit target replaces the target
   among the items it produced. */
static Var _slot_value(Compiler c, List slot) {
  int splice = slot.cadr();
  Var form = slot.caddr();
  List active = c.macro_stack.car();
  (List definition, Var input, List bindings, Token invocation) = active;
  (void) input;
  String source_file = _definition_file(definition);
  Var required = slot.assoc(<construct>);
  Var result = form is <list>
    ? c.evaluate_meta_value(form, invocation, 1)
    : _eval_template_form(
      c, form, bindings, invocation, source_file, required);
  result = _helper_result(c, result);
  Var construction = slot.assoc(<target>);
  if (required is not void && splice) {
    construction = required;
    result = _replace_target(result, _source_unwrap(required), required);
  }
  if (construction is not void)
    result = _constructed_identifier(result, construction);
  return splice && result is <list> ? _slot_rows(result) : result;
}

static Var _constructed_identifier(Var result, Var construction) {
  String exact = NULL;
  match (result)
    case %("x2c.ident" ?(String spelling)):
      exact = spelling;
  if (exact) return %($construction $exact);
  return result;
}

static Var _slot_rows(Var result) {
  match (result) {
    case %(code-value ? ? ?): return result;
    case %(!or (macro-invoke ? ? ?) ("x2c.quoted" ? ?)):
      return %(seq $result);
    case %(seq *): return result;
  }
  return %(seq @{result});
}

/** Evaluates a macro slot and returns its syntax as a row sequence.
    `(seq ...)` contributes its children; every other result contributes one
    row.
*/
List Compiler.evaluate_macro_rows(Compiler c, Var value) {
  value = c.evaluate_macro_slot(value);
  return value is <list> && !value.is_nil() &&
         value.list().car() == <seq>
       ? value.list().cdr() : %($value);
}

/* Scratch names for one template evaluation. The count is process-wide: a
   shared parent session holds every name its filling bound, and a child
   cannot rebind an inherited one, so a count per compiler would refuse the
   second compiler that expanded the same macro. */
static unsigned long template_serial = 0;

/* Evaluates a template's Lisp form, which reads each captured binding
   through a scratch global. */
static Var _eval_template_form(
  Compiler c, String form, List bindings, Token invocation,
  String source_file, Var construction) {
  c.run_declaration_effects();
  c.ensure_macro_lisp();
  unsigned long serial = template_serial++;
  /* Provenance lookup uses captured Var identity. Structural equality must
     not let constructed or selected syntax acquire a caller's source text. */
  Map source_captures = _source_captures(bindings);
  List references = _bind_references(c, serial, bindings);
  if (references) form = _rewrite_references(form, references);
  if (construction is not void)
    form = _with_construction(c, serial, form, construction);
  MetaContext *context = MetaContext.current();
  $let(context.has_bindings, !!references)
  $let(context.captures, source_captures)
  $let(context.definition_file, source_file)
  $let(context.expander, c)
    return _eval_string(c, form, invocation);
}

/** Evaluates the explicit meta call `expression` at `site` with the active
    expansion's captures visible to the SDK. A nonzero `slot` marks a
    template slot, which reports a call the project meta build leaves. */
Var Compiler.evaluate_meta_value(
  Compiler c, List expression, Token site, int slot) {
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  List active = c.macro_stack ? c.macro_stack.car() : NULL;
  List bindings = active ? active.caddr() : NULL;
  String source_file = active ? _definition_file(active.car()) : c.filename;
  MetaContext *context = MetaContext.current();
  $let(context.has_bindings, !!bindings)
  $let(context.captures, _source_captures(bindings))
  $let(context.definition_file, source_file)
  $let(context.expander, c)
  $let(context.evaluator, c)
  $let(context.site, site)
    return c.run_meta_call(expression, site, slot);
}

/* Both entry forms expose source only for complete captures in the active
   expansion. The keys are the same unwrapped values passed to the helper. */
static Map _source_captures(List bindings) {
  Map captures = {};
  foreach (List pair, bindings) {
    List source;
    Var syntax;
    if (pair && _source_capture_parts(pair.cadr(), source, syntax))
      captures[((ulong) syntax.u64)] = source;
  }
  return captures;
}

/* Binds each captured value to a scratch global and returns the
   `(spelling global)` rows, newest first. */
static List _bind_references(
  Compiler c, unsigned long serial, List bindings) {
  List references = NULL;
  foreach (List pair, bindings) {
    if (!pair) continue;
    Var (binder, syntax) = pair;
    String spelling = binder.str()[1:];
    String temporary = %"_x2c_gensym_meta_${serial}_$spelling";
    Var unwrapped;
    if (!_source_capture_parts(syntax, NULL, unwrapped))
      unwrapped = _source_unwrap(syntax);
    c.macro_lisp.set_global(temporary, unwrapped);
    references = cons(%($spelling $temporary), references);
  }
  return references;
}

/* Replaces each `$name` the references bind with its scratch global. */
static String _rewrite_references(String form, List references) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Buffer rewritten = $auto(Buffer.new(0));
  int copied = 0;
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type != <$>) {
      token = tokenizer.next();
      continue;
    }
    Token name = tokenizer.next();
    Var replacement = name && name.type == <ident>
                    ? references.assoc(name.text) : void;
    String temporary = replacement is <string> ? replacement : NULL;
    if (temporary) {
      rewritten.write_len(form + copied, token.pos - copied);
      rewritten.write(temporary);
      copied = name.pos + name.len;
      name = tokenizer.next();
    }
    token = name;
  }
  rewritten.write_len(form + copied, form.len() - copied);
  return rewritten;
}

/* `x2c.ident` in the form builds a name that carries the construction
   requirement. */
static String _with_construction(
  Compiler c, unsigned long serial, String form, Var construction) {
  String temporary = %"_x2c_gensym_meta_${serial}_construction";
  c.macro_lisp.set_global(temporary, construction);
  return %"(let ((x2c.ident (lambda (name)
      (list $temporary name)))) $form)";
}

/* The decorator target is a value to find among the produced items, so a
   comparison finds it. Interpolating it into a pattern would read a
   binder-shaped symbol inside it, such as the `*=` operator, as a sequence
   binder. A foreign alias wraps its target, so Match recognizes that
   wrapper and the comparison still owns the target. */
static Var _replace_target(Var produced, Var target, Var required) {
  if (produced is not <list>) return void;
  List produced_items = produced;
  Array items = $auto(produced_items);
  int at = produced_items.index(target);
  if (at >= 0) {
    items[at] = required;
    return items.list();
  }
  for (int i = 0; i < (int) items.len(); i++)
    match (items[i]) case %(falias ?found ?native):
      if (found == target) {
        items[i] = %(falias $required $native);
        return items.list();
      }
  return void;
}

/** Evaluates a declaration recipe after its owning source is collected.
    The callback is a Lisp name and arguments are retained canonical values.
*/
Var Compiler.evaluate_declaration_recipe(
  Compiler c, Atom callback, List arguments) {
  Token invocation = c.token;
  match (c.macro_stack)
    case %((? ? ? ?token) *): invocation = token;
  c.run_declaration_effects();
  return c.apply_meta_function(callback.str(), arguments, invocation);
}

/* template calls and rebuilds

   Compile-time code calls a template by name with its argument values, and
   the compiler rebuilds a pending Macro value application from bound
   children without binding them again. */

/** Returns the syntax that invokes the template `stored`, a macro name
    spelled as a String or a local definition, with `values`: what a template
    call in a staged `meta` body evaluates to. */
List x2c_template_call(Var stored, List values) =>
  _sdk_template_call(
    stored is <string> ? Atom.intern(stored.str()) : stored, values);

static List _sdk_template_call(Var stored, List values) {
  Compiler c = Compiler.expanding();
  Token site = MetaContext.current().site;
  List definition = stored.is_atom() ? _lookup(c, stored, site) : stored;
  return %(macro-invoke $stored
    ${_template_arguments(c, definition, values, site, 0)}
    m-invoke);
}

/* The capture rows of a template call's values. A scalar Lisp value in an
   Expr hole lifts to an expression first. */
static List _template_arguments(
  Compiler c, List definition, List values, Token invocation,
  int retain_syntax) {
  Array rows = [];
  List holes = definition.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), values = values.cdr())
    rows.push(
      _hole_row(c, holes.car(), values.car(), invocation, retain_syntax));
  return %(args @{rows.list_free()});
}

/* One hole's capture row of `value`. Each scalar Lisp value an Expr hole
   or sequence holds lifts to an expression first. A Type hole's type names
   its type with a String. */
static List _hole_row(
  Compiler c, List hole, Var value, Token invocation, int retain_syntax) {
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  String error = kind == <type> && value is <list>
               ? type_name_error(value) : NULL;
  if (error) $report.macro.type_name(c, error, invocation);
  if (!hole.assoc(<sequence>).int())
    return _capture_row_project(
      c,
      hole, %(${lifts ? _lifted(c, value, invocation) : value}),
      retain_syntax);
  List sources = value;
  if (lifts) {
    Array lifted = [];
    foreach (Var item, sources) lifted.push(_lifted(c, item, invocation));
    sources = lifted.list_free();
  }
  return _capture_row_project(c, hole, sources, retain_syntax);
}

/* A number, String, or Symbol becomes the literal expression that holds
   it; other values are already syntax. */
static Var _lifted(Compiler c, Var value, Token invocation) =>
  value.is_integer() || value.is_floating() || value is <string> ||
  value is <symbol> ? c.lift_macro_lisp_expression(value, invocation) : value;

/* A helper's result with each template call the helper left for the
   compiler replaced by its invocation. */
static Var _helper_result(Compiler c, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %((!or macrodef "x2c.quoted") *): return value;
    case %(code-value "lowered" *): return value;
    case $source_literal_content(%(*)): return value;
  }
  match (value) {
    case %("x2c.template" ?stored ?(List values)): {
      stored = _helper_result(c, stored);
      values = _helper_result(c, values);
      Token site = c.macro_invocation_site(<m-invoke>);
      if (!site) site = c.token;
      MetaContext *context = MetaContext.current();
      $let(context.expander, c)
      $let(context.site, site)
        return _sdk_template_call(
          stored is <string> ? Atom.intern(stored.str()) : stored, values);
    }
  }
  List child;
  $ast.rewrite_children(value.list(), child, _helper_result(c, child));
}

/** Rebuilds an expression from a pending Macro value application, preserving
    its established root `type`, child stage, and source wrappers. Binding,
    capture collection, hygiene, and effects do not run, and a statement
    expression's template-origin wrappers are omitted. */
List Compiler.rebuild_expression(Compiler c, Type type, List application) {
  List rebuilt = _rebuild(c, application, NULL);
  return %(expr $type @{rebuilt.cddr()});
}

/** Rebuilds a statement template as a canonical unbraced `seq`. Bound
    children keep their identities and origins; template-origin wrappers
    are omitted because this path does not open an invocation. */
List Compiler.rebuild_statement(Compiler c, List application) =>
  _rebuild(c, application, NULL);

/** Constructs a fresh function from a Unit template after lowering. The
    caller supplies its bound name and lowered children; binding does not
    run. */
List Compiler.rebuild_unit_function(Compiler c, List application) {
  List function = _rebuild(c, application, NULL).cadr();
  match (function) case %(api-source ? ? ?inner): return inner;
  return function;
}

/** Rebuilds a bound function through a Function decorator without binding it
    again. The template keeps the target's return type and declarator. */
List Compiler.rebuild_function(Compiler c, List target, List application) =>
  _rebuild(c, application, target).cadr();

/* Substitute bound syntax into a structural template without binding it.
   The caller supplies complete children and a template with no free names,
   computed slots, or nested applications. The definition's rebuild row
   holds the template and, for each hole, the binders of the projections
   it uses. Quoted syntax fills its own holes and keeps their values. */
static List _rebuild(
  Compiler c, List application, List target) {
  match (application) case %("x2c.quoted" ? ?syntax): {
    Landing landing = {.c = c, .site = c.token, .retain = 1};
    return _fill_syntax(landing, syntax);
  }
  (Var marker, List definition, List values) = application;
  (void) marker;
  List rebuild = definition.assoc(<rebuild>);
  (List template, List keys) = rebuild;
  List rows = _template_arguments(c, definition, values, c.token, 1).cdr();
  if (target)
    rows = rows.append(
      %(
        ${_capture_row_project(
          c, definition.assoc(<targetp>), %($target), 1)}));
  List bindings = NULL;
  foreach (List row, rows) {
    bindings = _row_bindings(keys.car(), row, bindings);
    keys = keys.cdr();
  }
  return template.replace(bindings);
}

static List _row_bindings(List keys, List row, List bindings) {
  List fields = _row_fields(row);
  foreach (Var binder, keys) {
    if (binder != <?>) bindings = %(($binder ${fields.car()}) @bindings);
    fields = fields.cdr();
  }
  return bindings;
}

/* A capture row's source, value, expression, splice, return, and
   declarator projections. A sequence's value stands for its expression
   and splice, and a singular Function hole's value also supplies its
   return type and declarator. */
static List _row_fields(List row) {
  match (row) {
    case %(capture (source *sources) (value *values)):
      return %($sources $values $values $values () ());
    case %(capture (source ?source) (value ?value) (expression ?expression)
                   (splice *splice)): {
      List result = NULL, declarator = NULL;
      match (value) case %(function ?returned ?declared ?): {
        result = returned;
        declarator = declared;
      }
      return %($source $value $expression $splice $result $declarator);
    }
  }
  return NULL;
}

/* quoted syntax

   A quotation whose template applies no other template builds that
   template where it is written, as `("x2c.quoted" FRESH SYNTAX)`. Each
   use of a hole is `("x2c.hole" HOLE PROJECTION VALUE)`, holding the
   local's value, and each origin anchor is `("x2c.at" NODE)`. A FRESH
   row is `(BINDER SPELLING FILE)`, where FILE marks a name that a
   file-scope row declares with linkage. Landing fills the syntax as an
   expansion fills its template: it names the private binders, projects
   each hole as a capture row would, and keeps anchors only where an
   invocation lands it. Recovery gives binding a semantic transaction.
   It counts no expansion, since the template applies nothing. */

/* One landing of quoted syntax. `retain` keeps each hole's value as the
   syntax it is, as a rebuild does. */
static typedef struct Landing {
  Compiler c, Map names, Token site, int anchored, retain;
} Landing;

/** Binds quoted `syntax` with its `fresh` rows at `position`, as the
    expansion of its quotation would. */
List Compiler.land_quotation(
  Compiler c, List fresh, Var syntax, Symbol position, Type return_type) {
  Token site = c.macro_invocation_site(<m-invoke>);
  Landing landing = {
    .c = c, .site = site ? site : c.token, .anchored = !!site};
  List bound = NULL;
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    landing.names = _private_names(c, fresh);
    Var filled = _fill_syntax(landing, c.thaw_declaration_syntax(syntax));
    $let(c.token, site)
    $let(c.origin, c.record_origin(site))
      bound = c.bind_syntax(filled, position, return_type);
    transaction.commit();
  }
  if (position == <block> || position == <statement> ||
      position == <unit>)
    match (bound) case %(seq ?item): return item;
  return bound;
}

/* Each fresh binder's private name. */
static Map _private_names(Compiler c, List fresh) {
  if (!fresh) return NULL;
  Map names = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
  int file_scope = c.sym.at_file_scope();
  foreach (List row, fresh) {
    (Var binder, Var spelling, Var file) = row;
    names[binder] = _private_name(
      c, spelling.str(), file_scope && file.int() ? root : NULL);
  }
  return names;
}

/* The filled syntax. A hole that is a sequence or a splice contributes
   its items to the List that holds it. */
static Var _fill_syntax(Landing &l, Var syntax) {
  Var name;
  if (syntax.is_binder())
    return (void *) l.names && l.names.try_get(syntax, name) ? name : syntax;
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  List node = syntax;
  // Only the quoted forms have a String head.
  if (node.car() is <string>)
    match (node) {
      case %("x2c.at" ?inner): {
        Var filled = _fill_syntax(l, inner);
        return l.anchored ? %(at m-origin $filled).var() : filled;
      }
      case %("x2c.hole" ?(List hole) ?projection ?value):
        return _project_hole(l, hole, projection, value);
    }
  Array items = NULL;
  int index = 0;
  foreach (Var item, node) {
    List spliced = NULL;
    int splices = _splices(l, item, spliced);
    Var filled = splices ? void : _fill_syntax(l, item);
    if (!(void *) items && (splices || filled != item)) {
      items = [];
      List prior = node;
      for (int i = 0; i < index; i++, prior = prior.cdr())
        items.push(prior.car());
    }
    if (splices) foreach (Var each, spliced) items.push(each);
    else if ((void *) items) items.push(filled);
    index++;
  }
  Var filled = (void *) items ? items.list_free().var() : syntax;
  return l.retain && node.car() == <declare>
    ? _retained_declaration(filled) : filled;
}

/* A retained declaration with its base's pointer, array, and function
   modifiers moved onto each declarator, as parsing moves them. */
static Var _retained_declaration(List declaration) {
  match (declaration) case %(declare ?specifiers (bindings *rows)): {
    List modifiers = NULL;
    List base = Type.declaration_base(specifiers, modifiers);
    if (!modifiers) return declaration;
    Array moved = [];
    foreach (List row, rows) moved.push(Ast.append_modifiers(row, modifiers));
    return %(declare $base (bindings @{moved.list_free()}));
  }
  return declaration;
}

/* Whether `item` is a sequence or splice hole, whose items it sets. */
static int _splices(Landing &l, Var item, List &spliced) {
  if (item is not <list> || item.is_nil() || item.list().car() is not <string>)
    return 0;
  match (item) case %("x2c.hole" ?(List hole) ?projection ?value):
    if (projection == <splice> || hole.assoc(<sequence>).int()) {
      spliced = _project_hole(l, hole, projection, value);
      return 1;
    }
  return 0;
}

/* A hole's projection of its value, as an expansion's capture row holds
   it. A shell is an Expr hole's expression in an expression position,
   which a rebuild leaves bare. */
static Var _project_hole(Landing &l, List hole, Symbol projection, Var value) {
  Compiler c = l.c;
  if (projection == <member>) return _member_spelling(c, value);
  if (!l.retain) value = _helper_result(c, value);
  List row = _hole_row(c, hole, value, l.site, l.retain);
  Symbol field = projection == <shell> ? <expression> : projection;
  Var projected = _row_fields(row)[
    %(source value expression splice).index(field)];
  if (projection != <shell> || l.retain) return projected;
  return %(expr (<macro-expr>) $projected);
}

/* macro values

   A `Macro` value carries a definition as run-time data, with its
   references named by spelling. Applying it binds those names in the
   applying unit, and a producer can return code with effects into the
   application. */

/** Returns the literal expression that carries `value`, a macro definition
    or one of its references, as run-time data. */
List Compiler.macro_value_literal(Compiler c, List value) =>
  c.cache_literal_list(_macro_value_names(value));

/* A Macro value names its references by spelling, so its literal does not
   depend on how this translation numbered bindings; each resolves where the
   value's expansion lands. */
static Var _macro_value_names(Var value) {
  if (value is not <list>) return value;
  String spelling = NULL;
  if (Ast.try_binding(value, NULL, spelling))
    return %(binding-name $spelling);
  List child;
  $ast.rewrite_children(value.list(), child, _macro_value_names(child));
}

/* NULL for a template's hole of that name or for an unknown macro. */
static List _macro_value(Compiler c, Atom name) {
  Var stored;
  if (c.macro_holes && _hole_record(c, name)) return NULL;
  if (!_try_definition(c, name, 1, stored)) return NULL;
  List cached = c.macro_value_literal(stored);
  return %(expr ("Macro") ${cached.caddr()});
}

/** Parses `case NAME(?a, *b)` where NAME selects a macro, as `$name` or as
    a `Macro` variable, into the pattern expression that recognizes code the
    macro builds. Returns NULL without consuming tokens for any other case.
*/
List Compiler.try_parse_macro_pattern(Compiler c) {
  if (c.peek(0) == <$> && c.peek(1) == <"{">) return NULL;
  Token saved = c.token;
  List expression = _pattern_macro(c);
  if (!expression || c.peek(0) != <(>) {
    c.token = saved;
    return NULL;
  }
  if (saved.type == <$> && !_simple_labels(c)) {
    c.token = saved;
    return c.try_parse_macro_subpattern(0);
  }
  List names = _pattern_labels(c);
  List labels = c.cache_literal_list(names);
  List shape = _case_shape(c, saved, names);
  if (shape)
    return c.resolve_expression(
      $!( Macro_case_shape($expression, $labels, $shape) ), saved);
  return c.resolve_expression(
    $!( Macro_case_pattern($expression, $labels) ), saved);
}

/* The pattern a `case` on the macro `$NAME` at `at` tests for `names`,
   cached, or NULL for a `Macro` variable or a pattern that resolves a
   reference against the subject of each call. */
static List _case_shape(Compiler c, Token at, List names) {
  String spelling = NULL;
  Var stored;
  if (!c.macro_pattern_at(at, spelling, stored)) return NULL;
  Macro shape = _macro_value_names(stored);
  List derived = shape.matcher(names).pattern;
  return derived ? c.cache_literal_list(derived) : NULL;
}

/* The Macro value a `$name` or a `Macro` variable at the cursor names. */
static List _pattern_macro(Compiler c) {
  if (c.peek(0) == <$>) return _macro_value(c, _name(c));
  if (c.peek(0) != <ident>) return NULL;
  Type type = NULL;
  List binding = c.sym.lookup(%(${c.token.text}), type);
  if (!binding || !c.sym.is_named_value_type(type, "Macro")) return NULL;
  List expression = c.resolve_expression(
    %(expr $type (ident $binding)), c.token);
  c.next();
  return expression;
}

/* The `?a` and `*b` capture labels between the parentheses. */
static List _pattern_labels(Compiler c) {
  c.expect(<(>);
  Array names = [];
  if (c.peek(0) != <)>) loop {
    int sequence = c.peek(0) == <*>;
    c.expect(sequence ? <*> : <?>);
    String name = c.token.text;
    c.expect(<ident>);
    names.push(Atom.intern(%"${sequence ? "*" : "?"}$name"));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return names.list_free();
}

/** Returns the `(` after a visible macro's `$NAME` at `at`, storing its
    spelling and definition, or NULL. The cursor does not move.
*/
Token Compiler.macro_pattern_at(
  Compiler c, Token at, String &spelling, Var &stored) {
  if (at.type != <$>) return NULL;
  Token saved = c.token;
  c.token = at;
  Token end = _scan_name(c, spelling);
  c.token = saved;
  if (!spelling || end.type != <(> ||
      !_try_definition(c, Atom.intern(spelling), 1, stored) ||
      stored is not <list> || stored.list().car() != <macrodef>)
    return NULL;
  return end;
}

/* Whether the parenthesized labels at the cursor are all `?name` or
   `*name` binders. */
static int _simple_labels(Compiler c) {
  int at = 1;
  if (c.peek(at) == <)>) return 1;
  loop {
    if ((c.peek(at) != <?> && c.peek(at) != <*>) ||
        c.peek(at + 1) != <ident>)
      return 0;
    if (c.peek(at + 2) == <)>) return 1;
    if (c.peek(at + 2) != <,>) return 0;
    at += 3;
  }
}

/** Parses `$NAME(P, ...)` in a pattern, where each argument is a pattern,
    into the pattern for code NAME builds with each argument pattern in its
    hole. It matches the shelled expression or its bare content; `content`
    selects the content alone, for a position whose pattern already writes
    the `(expr TYPE ...)` shell. Returns NULL without consuming tokens when
    no macro NAME is visible.
*/
List Compiler.try_parse_macro_subpattern(Compiler c, int content) {
  Token start = c.token;
  String spelling = NULL;
  Var stored;
  Token end = c.macro_pattern_at(start, spelling, stored);
  if (!end) return NULL;
  c.token = end;
  Macro shape = _macro_value_names(stored);
  List patterns = c.parse_macro_pattern_arguments();
  int expected = shape.assoc(<parameters>).list().len();
  if (patterns.len() != expected)
    $report.parse.macro_pattern_arity(c, spelling, expected, start);
  return c.cache_literal_list(_macro_subpattern(shape, patterns, content));
}

/* `shape`'s pattern with each argument pattern in its hole. A binder
   stands in its hole directly; any other pattern replaces a private binder
   there, spliced for a sequence or Type hole. */
static List _macro_subpattern(Macro shape, List patterns, int content) {
  Array names = [];
  Map replacements = {};
  List spelled = patterns.flatten_all();
  int index = 0;
  foreach (List hole, shape.assoc(<parameters>).list()) {
    Var pattern = patterns.car();
    patterns = patterns.cdr();
    if (pattern.is_binder()) {
      names.push(pattern);
      continue;
    }
    Symbol kind = hole.assoc(<kind>);
    int list = hole.assoc(<sequence>).int() || kind == <type> ||
               kind == <captures>;
    Atom binder = _unused_binder(list ? "*" : "?", spelled, index);
    names.push(binder);
    replacements[binder] = pattern;
  }
  List pattern = _substitute_binders(
    shape.pattern(names.list_free()), replacements);
  match (pattern)
    case %(expr ? ?body): return content ? body : %(!or $pattern $body);
  return pattern;
}

/* A private binder that no argument pattern spells with either sigil. */
static Atom _unused_binder(String sigil, List spelled, int &index) {
  loop {
    String name = %"__pattern_${index++}";
    if (!(Atom.intern("?" + name) in spelled) &&
        !(Atom.intern("*" + name) in spelled))
      return Atom.intern(sigil + name);
  }
}

/* Replaces each private binder with its argument pattern, splicing a List
   binder's elements, without interpreting the pattern's guards. */
static Var _substitute_binders(Var value, Map replacements) {
  if (value is not <list> || value.is_nil()) return value;
  Array items = [];
  foreach (Var child, value.list()) {
    Var replacement;
    if (child.is_binder() && replacements.try_get(child, replacement)) {
      if (child.str().startswith("*") && replacement is <list>)
        foreach (Var item, replacement.list()) items.push(item);
      else items.push(replacement);
    }
    else items.push(_substitute_binders(child, replacements));
  }
  return items.list_free();
}

/** Returns an anonymous macro definition as a `Macro` value. Macro values
    the body applies are captured where the literal is written, so a later
    application applies the same children.
*/
List Compiler.capture_macro_value(Compiler c, List definition) {
  List cached = c.macro_value_literal(definition);
  List literal = %(expr ("Macro") ${cached.caddr()});
  List rows = %(expr ("List") (nil));
  int captured = 0;
  foreach (List binding, definition.assoc(<captures>).list()) {
    Type type = c.semantic_binding_facts()[%(type $binding)];
    if (!c.sym.is_named_value_type(type, "Macro")) continue;
    List pair = _captured_pair(c, binding, type);
    rows = %(expr ("List")
      (cons ${c.convert_expression(pair, %("Var"))} $rows));
    captured = 1;
  }
  if (!captured) return literal;
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_close")), c.token);
  return c.resolve_expression(
    %(expr ("Macro") (call $callee (args $literal $rows))), c.token);
}

/* The `(identity value)` row of one captured Macro binding. */
static List _captured_pair(Compiler c, List binding, Type type) {
  List identity = c.macro_value_literal(binding);
  List value = c.resolve_expression(%(expr $type (ident $binding)), c.token);
  return %(expr ("List")
    (cons ${c.convert_expression(identity, %("Var"))}
      (expr ("List") (cons ${c.convert_expression(value, %("Var"))}
        (expr ("List") (nil))))));
}

/** Consumes a `(code-value STAGE CODE EFFECTS)` carrier a producer returned
    into a macro value application, or that `Compiler.bind_code_value`
    binds as one. Effects are applied in order under the application's
    transaction, and their tokens are replaced in the code.
    `retained` reports a bound or lowered stage, which ordinary binding
    leaves untouched. Lowered code is not searched for a leftover binder.
    Returns 0 for any other value.
*/
int Compiler.take_code_value(
  Compiler c, Var input, Var &value, int &retained) {
  match (input) case %(code-value ?(String stage) ?code ?effects): {
    Map replacements = _code_effects(c, effects);
    value = replacements.len() ? _replace_bindings(code, replacements) : code;
    retained = stage != "source";
    if (stage != "lowered") {
      Var binder = _carrier_binder(value);
      if (binder) _unbound(c, binder.str(), c.token);
    }
    return 1;
  }
  return 0;
}

/* Applies a carrier's effects in order and returns what replaces each
   effect's token in the code. */
static Map _code_effects(Compiler c, Var effects) {
  Map replacements = {};
  foreach (List effect, effects)
    match (effect) {
      case %(rewrite ?point ?kind ?name ?shape ?holes): {
        _register_rewrite(
          c, _rewrite_rule(point, kind, name, shape, holes, 0, 1));
        c.record_compile_time_effect(
          %(compile-time rewrite $point ${c.freeze_declaration_syntax(kind)}
            $name ${c.freeze_declaration_syntax(shape)}
            ${c.freeze_declaration_syntax(holes)}), c.token);
      }
      case %(new-name ?token ?(String role)):
        replacements[token] = c.sym.introduce(c.fresh_name(role));
      case %(cleanup ?token ?placed): {
        replacements[token] = placed;
        c.needs_exception = 1;
      }
      default:
        c.report_error(
          <macro>, "a meta call returned an unknown code effect", c.token,
          %("effect: ${effect.repr()}"));
    }
  return replacements;
}

/** Places `code` where `where` says, under the active expansion's
    transaction: `(after-statement)` after the enclosing block item or
    initialized declarator; `(block-exit)` on every exit from the enclosing
    block from that point on, as a `defer` placed after it;
    `(function-entry)` at the entry of the enclosing function, at parse or
    transform time, in placement order before its first statement;
    `(unit-support)` among the unit's support declarations, once per KEY
    with `(unit-support KEY)`; or `(unit-init)` in the unit's file
    initialization, in AREA with `(unit-init AREA)`. */
void Compiler.place(Compiler c, List where, Var code) {
  match (where) {
    case %(after-statement): c.place_after(code);
    case %(function-entry): c.place_entry(code);
    case %(block-exit): {
      Macro deferred = $deferred;
      c.place_after(deferred(code));
    }
    case %(unit-support): _place_support(c, code);
    case %(unit-support ?key): {
      Var placed;
      $adapter.memo(c, %(unit-support $key), placed) {
        _place_support(c, code);
        placed = 1;
      }
    }
    case %(unit-init):
      c.add_init(<finish>, c.bind_syntax(code, <block>, NULL));
    case %(unit-init (!set ?area (!or protocol prepare statics finish))):
      c.add_init(area, c.bind_syntax(code, <block>, NULL));
    default: $report.macro.placement(c, where);
  }
}

/* Adds the file-scope `code` a placement gives to the unit's support. It
   binds at file scope whatever local scope is open. */
static void _place_support(Compiler c, Var code) {
  Block local = c.sym.close_local_scopes();
  defer c.sym.reopen_scopes(local);
  c.add_support(c.written_support(c.bind_syntax(code, <unit>, NULL)));
}

/** Binds a code-value carrier that a meta call returned outside a macro
    value application as an application binds it, under a transaction that
    also covers its effects. */
List Compiler.bind_code_value(
  Compiler c, List carrier, Symbol position, Type return_type) {
  List bound = NULL;
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    bound = c.bind_syntax(carrier, position, return_type);
    transaction.commit();
  }
  return bound;
}

/* A named binder left as a carrier's code, identifier, or declarator
   after its effects were applied, or NULL. Binders elsewhere are data,
   such as a lowered match pattern, and a bare `*` or `?` is syntax. A
   carrier the code holds is searched when it is taken. */
static Var _carrier_binder(Var value) {
  if (value.is_binder()) return value.str().len() > 1 ? value : NULL;
  if (value is not <list>) return NULL;
  match (value) {
    case $source_identifier_content(%(?name *)):
      if (name.is_binder() && name.str().len() > 1) return name;
    case %(bind ?name *):
      if (name.is_binder() && name.str().len() > 1) return name;
    case $source_literal_content(%(*)): return NULL;
    case %((!or "x2c.template" "x2c.quoted" macro-invoke macrodef
                code-value) *):
      return NULL;
  }
  foreach (Var child, value.list())
    if (child is <list>) {
      Var binder = _carrier_binder(child);
      if (binder) return binder;
    }
  return NULL;
}

/* compile-time Lisp

   Each Compiler initializes one Lisp session lazily, as a child of the
   shared library session when one is published. A `$(...)` form at file
   scope evaluates there, or imports a file; in an expression its value
   lifts into syntax. */

/** Opens the unit's compile-time Lisp session when it has none. An
    Each use records the library files as dependencies,
    and a session loads them once. */
void Compiler.ensure_macro_lisp(Compiler c) {
  int loaded = c.macro_lisp != NULL;
  int shared = library_session != NULL, ready = loaded || shared;
  if (!loaded) {
    c.macro_lisp = Lisp.kernel();
    c.macro_lisp.adopt(library_session);
  }
  if (!ready) _install_builtins(c.macro_lisp);
  foreach (Var (path, message), _library_files())
    _eval_library(c, ready, path, message);
  if (!ready) _install_native_operations(c);
}

static Var _eval_string(Compiler c, String source, Token invocation) {
  Var result;
  MetaContext *context = MetaContext.current();
  $let(context.site, invocation)
  $let(context.evaluator, c) {
    /* A compiler operation called from Lisp has already reported its
       failure; wrapping the transfer would report it a second time. */
    try result = c.macro_lisp.eval_string(source);
    catch %(malformed (category ?category)):
      raise %(malformed (category $category));
    catch %(?code *detail):
      c.report_lisp_failure(invocation, cons(code, detail), source);
  }
  return result;
}

static String _lisp_form(Compiler c) {
  Token start = c.token, close = start.group_close();
  if (close.type == <eof>)
    $report.parse.lisp_unclosed(c, start);
  c.token = close.after_group();
  int begin = start.pos + start.len;
  return %"(${String.new_len(c.text + begin, close.pos - begin)})";
}

/** Evaluates one source Lisp form or imports an .xlisp dependency. */
List Compiler.parse_macro_lisp_top_level(Compiler c) {
  Token invocation = c.token;
  String import_path = NULL;
  int is_import = _import_path(c, import_path);
  String form = _lisp_form(c);
  if (is_import) return _import(c, import_path, invocation);
  /* The shared session evaluated this file's forms once for the target and
     every unit inherits them, so evaluating this one again would only try to
     replace a name an ancestor binds. */
  if (c.inherited_lisp) return NULL;
  c.evaluate_declaration_effect(form, invocation);
  return NULL;
}

/** Loads import dependencies and queues source Lisp effects.
    Declaration projection forces preceding effects exactly once; otherwise
    full parsing keeps the ordinary source-order evaluation. */
void Compiler.parse_macro_lisp_shallow(Compiler c) {
  String requested = NULL;
  if (_import_path(c, requested)) {
    if (!c.source_private) {
      String path =
        Compiler.portable_path(_canonical_path(c, requested, c.token));
      c.record_compile_time_effect(
        %(compile-time import $path ${_effect_source(c, c.token)}), c.token);
    }
    c.parse_macro_lisp_top_level();
    return;
  }
  Token first = c.token;
  String form = _lisp_form(c);
  /* As in full parsing, the shared session already holds an inherited
     import's forms, and running one again would rebind an ancestor's name. */
  if (c.inherited_lisp) return;
  if (!c.source_private)
    c.record_compile_time_effect(
      %(compile-time lisp $form ${_effect_source(c, first)}), first);
  c.queue_declaration_effect(form, first, c.token);
}

/* An including unit replays a recorded effect in the own text of the file
   that holds its site, which for a module member is the member's file, so
   the site is recorded at its place in that file. */
static List _effect_source(Compiler c, Token site) {
  String file = NULL;
  Token placed = c.source_token(site, file);
  return %(source ${Compiler.portable_path(Path.absolute(file))}
    ${c.freeze_declaration_syntax(placed)});
}

/** Evaluates a queued source Lisp form with its original diagnostic site. */
void Compiler.evaluate_declaration_effect(
  Compiler c, String form, Token invocation) {
  List key = %(${Compiler.portable_path(Path.absolute(c.filename))}
               ${invocation.pos} $form);
  if (key in c.evaluated_effects ||
      (!library_filling && library_imports && key in library_imports)) return;
  $let(c.collect_protocols, 1) {
    c.ensure_macro_lisp();
    _eval_string(c, form, invocation);
  }
  c.evaluated_effects[key] = 1;
  if (library_filling) {
    key.try_own();
    $scope(&library_scope) library_imports[key] = 1;
  }
}

/** Parses a compile-time Lisp form in an expression position.
    Macro-definition parsing records a deferred slot; ordinary parsing
    evaluates the form in the translation unit's Lisp session and lifts it.
*/
List Compiler.parse_macro_lisp_expression(Compiler c) {
  Token invocation = c.token;
  String form = _lisp_form(c);
  if (c.macro_holes) return %(expr (<macro-expr>) (macro-slot 0 $form));
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  Var value = _eval_string(c, form, invocation);
  return c.lift_macro_lisp_expression(value, invocation);
}

/** Converts a compile-time Lisp value into a bound expression AST.
    Scalars, immutable values, representable Array/Map roots, compiler-issued
    identifiers, and nonempty code `List`s are accepted; `invocation` locates
    an unsupported result.
*/
List Compiler.lift_macro_lisp_expression(
  Compiler c, Var value, Token invocation) {
  List literal = c.meta_value_expression(NULL, value, invocation);
  if (literal) return literal;
  Var identifier = _sdk_identifier_result(value);
  if (identifier is not void)
    return c.resolve_expression(%(expr () (ident $identifier)), invocation);
  if (value is <list> && !value.is_nil())
    return c.bind_syntax(_helper_result(c, value), <expression>, NULL);
  $report.macro.lisp_expr(c, invocation, value);
}

/** Binds a compile-time Lisp code `value` returned to a statement at
    `context`. */
List Compiler.bind_macro_lisp_statement(
  Compiler c, List value, Symbol context) {
  value = _helper_result(c, value);
  return _statement_expression(c, value)
    ? %(stmnt ${c.lift_macro_lisp_expression(value, c.token)})
    : c.bind_syntax(value, context, c.return_type);
}

/* The root inside a carrier determines whether the statement discards an
   expression or binds a statement. Ordinary binding consumes the carrier. */
static int _statement_expression(Compiler c, List value) {
  loop match (value) {
    case %((!or "x2c.quoted" src at) ? ?root): value = root;
    case %("x2c.at" ?root): value = root;
    case %(code-value ? ?root ?): value = root;
    case %(macro-invoke ?stored ? ?site):
      return _result_kind(
        _stored_definition(
          c, stored, c.macro_invocation_site(site))) == <expression>;
    case %(expr *): return 1;
    default: return _sdk_identifier_result(value) is not void;
  }
}

static Var _sdk_identifier_result(Var value) {
  match (value)
    case %("x2c.ident" (!is ?spelling type string)): return spelling;
  return value is <list> &&
         Ast.try_binding(value, NULL, NULL) ? value : void;
}

static Var _lisp_import_hook(String path) {
  MetaContext *context = MetaContext.current();
  Compiler c = context.evaluator;
  if (!c) raise %(bad-state (operation "compile-time import"));
  _import(c, path, context.site);
  return %();
}

/* Lisp files use the translation session and ordinary dependency tracking.
   Source declarations travel through #include and the selected interface. */

static List _import(Compiler c, String requested, Token invocation) {
  c.ensure_macro_lisp();
  String path = _canonical_path(c, requested, invocation);
  c.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  Var dependencies;
  if (c.imports.try_get(path, dependencies)) {
    c.merge_translation_dependencies(dependencies);
    return NULL;
  }
  if (path in c.import_stack)
    $report.macro.import_cycle(c, path, invocation);
  if (!path.endswith(".xlisp"))
    $report.macro.import_extension(c, invocation, _path_note(c, path));
  Map before = c.deps.copy();
  String text = _read_source(
    c, path, "cannot open compile-time Lisp import", invocation);
  /* Collection queues the import itself, so only evaluation fills imports.
     A nested import runs while its importing effect is on import_stack. */
  if (c.shallow && !c.import_stack.len() && !library_filling) {
    c.queue_declaration_effect(%"(import ${path.repr()})", invocation, NULL);
    return NULL;
  }
  if (!Compiler.inherits_import(path)) {
    c.import_stack.push(path);
    defer c.import_stack.take_last();
    if (c.collect_protocols) c.evaluate_declaration_effect(text, invocation);
    else c.queue_declaration_effect(text, invocation, invocation);
  }
  Map added = {};
  foreach (Var (key, value), c.deps)
    if (before[key] != value) added[key] = value;
  c.imports[path] = added;
  return NULL;
}

static int _import_path(Compiler c, String &?path) {
  Token token = Token.skip_trivia(c.token + 1);
  /* The checked-in bootstrap still tokenizes `import` as an identifier, so
     both spellings of the same word open a compile-time import. */
  if ((token.type != <ident> && token.type != <import>) ||
      token.text != "import")
    return 0;
  token = Token.skip_trivia(token + 1);
  if (token.type != <lit-char*>) return 0;
  if (path) path = String.new_len(token.text + 1, token.len - 2).unescape();
  token = Token.skip_trivia(token + 1);
  return token.type == <)>;
}

/* Cached templates retain global references across symbol-table resets.
   Bind those names in the current global scope without replaying imports. */
static Var _rebind_imported(Compiler c, Var stored) {
  if (stored is not <list>) return stored;
  List definition = stored;
  if (definition.car() != <macrodef>) return definition;
  Map replacements = {};
  _reference_bindings(c, definition, replacements);
  if (!replacements.len()) return definition;
  return _replace_bindings(definition, replacements);
}

static void _reference_bindings(
  Compiler c, List syntax, Map replacements) {
  match (syntax)
    case %(expr ? ${$source_identifier_content(%(?binding))}): {
      String spelling = NULL;
      if (Ast.try_binding(binding, NULL, spelling))
        replacements[binding] = c.sym.reference_global(%($spelling));
      return;
    }
  foreach (Var child, syntax)
    if (child is <list>) _reference_bindings(c, child, replacements);
}

// source files

/* A relative import names a file beside the source that writes it at
   `site`, or else one under the home's `lib/`. */
static String _canonical_path(Compiler c, String path, Token site) {
  if (!path || path[0] == '/') return c.canonical_path(path);
  String local = %"${_source_dir(c, site)}/$path";
  String system = %"${c.root_dir}/lib/$path";
  int use_system = !c.sources.exists(local) && c.sources.exists(system);
  return c.canonical_path(use_system ? system : local);
}

/* The importing macro file, or the file whose lines hold `site`. */
static String _source_dir(Compiler c, Token site) {
  String filename = c.import_stack.len()
                  ? c.import_stack[-1]
                  : c.token_source(site ? site : c.token, NULL);
  return filename ? Path.dirname(filename) : ".";
}

/** Returns the canonical path of the source `file`. A relative name that
    is not a file resolves against the home. */
String Compiler.source_path(Compiler c, String file) {
  if (!file || file.startswith("<")) return file;
  String rooted = %"${c.root_dir}/$file";
  if (file[0] != '/' && !c.sources.exists(file) && c.sources.exists(rooted))
    file = rooted;
  return c.canonical_path(file);
}

/* An absolute path; the definition keeps the home-portable spelling. */
static String _definition_file(List definition) {
  String file = definition.assoc(<file>);
  return !file || file.startswith("<")
    ? file : Compiler.absolute_home_path(file);
}

/* Reads a compile-time source and records its content hash as a
   dependency. */
static String _read_source(
  Compiler c, String path, String message, Token token) {
  String text = _source_text(c, path, message, token, _path_note(c, path));
  c.deps.merge_translation_dependency(path, "%08x".printf(text.hash()));
  return text;
}

/* An unreadable compile-time source is a located diagnostic. */
static String _source_text(
  Compiler c, String path, String message, Token token, List notes) {
  String text = NULL;
  if (!c.read_source(path, text))
    c.report_error(<macro>, message, token, notes);
  return text;
}

/* the shared library session

   A build target fills one Lisp session with the home's compile-time
   libraries and native operations, freezes it, and makes it the parent of
   every unit's session. */

/* The paths whose top-level Lisp the shared session evaluated while it was
   being filled. A unit that reaches one of these registers the file's macro
   definitions as usual and leaves its Lisp alone: the shared session already
   holds those definitions, and a session cannot replace a name an ancestor
   binds. The key is the path the loader resolved, which is the identity the
   import cache itself uses, so a file that shadows a library name through
   another include path is a different key and evaluates normally. */
static Map library_imports = NULL, static int library_filling = 0;
static Map library_definitions = NULL;
/* The shared session's compile-time-only definitions, which have no
   runtime form in any unit that reads them. */
static Map library_comptime = NULL;

static Lisp library_session = NULL, static Scope library_scope = NULL;
static int library_hooked = 0;

/** Builds the shared compile-time session, leaving it open for the caller to
    fill and then publish. Returns the session, or null when this home cannot
    preload, in which case every unit falls back to its own load, which
    reports against the unit that needed it.

    The session is not published until `Compiler.publish_macro_library`, so a
    unit opened in between still builds its own.
*/
Lisp Compiler.open_macro_library(Compiler c) {
  if (library_session != NULL) return NULL;
  $scope(&library_scope) {
    if (!library_hooked) {
      Scope.shutdown_hook(_library_shutdown);
      library_hooked = 1;
    }
    Lisp shared = Lisp.kernel();
    library_imports = {};
    library_definitions = {};
    library_comptime = {};
    $let(c.macro_lisp, shared)
      return _fill_library(c, shared);
  }
}

/* A failure while filling leaves no session, so each unit loads its own. */
static Lisp _fill_library(Compiler c, Lisp shared) {
  library_filling = 1;
  try {
    _install_builtins(shared);
    foreach (Var (path, message), _library_files())
      _eval_library(c, 0, path, message);
    _install_native_operations(c);
  }
  catch %(? *): {
    library_filling = 0;
    return NULL;
  }
  return shared;
}

/* The three libraries' paths in the home and the message each failure
   reports, in the order a session needs them. Every use of a session
   records them, so the paths are joined once per process. */
static List library_files = NULL;

static List _library_files(void) {
  if (library_files) return library_files;
  Array rows = [];
  foreach (Var (relative, message), %(
      ("etc/init.xlisp" "cannot open the compile-time Lisp environment")
      ("etc/lisp-values.xlisp" "cannot open the compile-time value operations")
      ("etc/compiler-sdk.xlisp" "cannot open the compile-time Lisp SDK")))
    rows.push(%(${%"${x2c_get_root()}/$relative"} $message));
  List files = rows.list_free();
  _require_owned(files.try_own());
  return library_files = files;
}

/** Records the compile-time Lisp libraries as dependencies of `c`, as each
    use of its session does. */
void Compiler.add_library_dependencies(Compiler c) {
  foreach (List library, _library_files())
    c.add_translation_dependency(library.car());
}

/* A home Lisp library is evaluated once, when `loaded` is zero, but every use
   records it, so a file's dependencies do not depend on whether an earlier
   file loaded it. */
static void _eval_library(
  Compiler c, int loaded, String path, String message) {
  c.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  if (loaded || Compiler.inherits_import(path)) return;
  String text = _source_text(c, path, message, c.token, %("path:" $path));
  _eval_string(c, text, c.token);
}

/** Prepares and freezes the shared session and makes it every unit's parent.
    `shared` must be the session `Compiler.open_macro_library` returned.
*/
void Compiler.publish_macro_library(Compiler c, Lisp shared) {
  (void) c;
  library_filling = 0;
  /* A second preload for the same target finds the session published. */
  if (library_session) return;
  if (!shared) {
    library_imports = NULL;
    library_definitions = NULL;
    library_comptime = NULL;
    return;
  }
  shared.freeze();
  library_session = shared;
}

/** Whether the shared session evaluated the file at `path`. A unit that is
    that file, as when a library is linted, inherits its Lisp forms.
*/
int Compiler.inherits_import(String path) {
  /* An empty `Map` is false, so the test is for the allocation. */
  return !library_filling && library_imports != NULL &&
         path in library_imports;
}

/** Records that `name` is compile-time only in `c`, and in the shared
    session when it is being filled. */
void Compiler.record_comptime(Compiler c, String name) {
  c.meta_comptime[name] = 1;
  if (!library_filling || !(void *) library_comptime) return;
  $scope(&library_scope) library_comptime[name] = 1;
  name.try_own();
}

/** Marks the shared session's compile-time-only definitions in a fresh
    compiler pass, which reads them without defining them. */
void Compiler.inherit_library_comptime(Compiler c) {
  if (library_filling || library_comptime == NULL) return;
  foreach (String name, library_comptime.keys()) c.meta_comptime[name] = 1;
}

/** Answers whether the shared compile-time session is still being filled,
    before `lib/meta.x` has defined the syntax builders. */
int Compiler.library_filling(void) => library_filling;

/** Returns the published definition keys, or null before publication.
    The borrowed map is the shared session's source identity table.
*/
Map Compiler.shared_definitions(Compiler c) {
  (void) c;
  return library_session ? library_definitions : NULL;
}

/** Answers whether the published shared session already holds the
    definition of `name` from this file, which a unit reading the file again
    leaves alone. */
int Compiler.shares_meta_definition(Compiler c, String name) {
  if (library_filling || library_definitions == NULL || !c.filename) return 0;
  String key = %"${Path.absolute(c.filename)}#$name";
  return key in library_definitions;
}

/* built-in macros

   The compiler carries two macro sources in its own image: the built-in
   macros, and the Lisp binding macros that a `lisp.` name installs on
   first use. A unit parses each source once and keeps its aliases under a
   marker. */

static macro Expression $_embed_lisp_binding_macros() =>
  $(x2c.literal.string (x2c.embed.text "../etc/lisp-bindings.x"));

static macro Expression $_embed_builtin_macros() =>
  $(x2c.literal.string (x2c.embed.text "../etc/builtin-macros.x"));

static String lisp_binding_macros = $_embed_lisp_binding_macros();
static String lisp_bindings_marker = NULL;
static String builtin_macros = $_embed_builtin_macros();
static String builtin_macros_marker = NULL;

/** Installs the compiler-shipped source macros into `c` once. */
void Compiler.install_builtin_macros(Compiler c) {
  if (!builtin_macros_marker) builtin_macros_marker = "_x2c.builtin.macros";
  _install_source(
    c, builtin_macros, "<builtin:macros>", builtin_macros_marker, 1);
}

static void _install_source(
  Compiler c, String text, String filename, String marker,
  int builtin) {
  (void) marker.try_own();
  Var installed;
  if (c.macros.try_get(marker, installed)) {
    c.kw_aliases.merge(installed);
    return;
  }
  Compiler child = Compiler.new_shared(c);
  defer c.close_child(child);
  child.filename = filename;
  child.sym = c.sym;
  child.fn_defs = c.fn_defs;
  child.macros = c.macros;
  child.kw_aliases = c.kw_aliases;
  child.builtin_defs = builtin;
  child.tokenize(text);
  Map aliases = _read_definitions(child);
  c.macros[marker] = aliases;
}

/* A shipped source holds only definitions and keyword aliases. */
static Map _read_definitions(Compiler c) {
  Map aliases = {};
  while (c.peek(0) != <eof>) {
    if (c.keyword_form_is_definition()) _record_alias(c, aliases);
    else if (c.macro_form_is_definition()) c.parse_macro_definition();
    else
      $report.macro.builtin_form(c);
  }
  return aliases;
}

/* Every `lisp.` lookup records the bindings file, which is installed only
   when `install` is nonzero and the bindings are not yet installed. */
static void _use_lisp_bindings(Compiler c, int install) {
  if (!lisp_bindings_marker) lisp_bindings_marker = "_x2c.lisp.bindings";
  int loaded =
    !install || lisp_bindings_marker in c.macros;
  if (!loaded) c.ensure_macro_lisp();
  _eval_library(
    c, loaded, %"${c.root_dir}/etc/lisp-bindings.xlisp",
    "cannot open the native Lisp macro support");
  if (loaded) return;
  // Binding groups start with the macro state that installs their macros.
  c.binding_rows = c.binding_sealed = NULL;
  _install_source(
    c,
    lisp_binding_macros, "<builtin:lisp-bindings>", lisp_bindings_marker, 0);
}

/* native operations

   Native operations read the active expansion's context, not the session
   that owns their callable, so the shared parent owns them once. */

static void _install_native_operations(Compiler c) {
  _bind_primitives(c.macro_lisp);
  foreach (Var (name, function), Compiler.compiler_targets()) {
    c.macro_lisp.set_global(name, function);
    Compiler.bind_meta_operation(c.macro_lisp, name, function);
  }
}

/* The internal primitives, which carry the `_x2c.` prefix, come before the
   meta surface is parsed. */
static void _bind_primitives(Lisp lisp) {
  $lisp.bind(lisp, "_x2c.import-hook", _lisp_import_hook);
  Compiler.bind_sdk_primitives(lisp);
}

/* Binds the built-in macro algorithms into `lisp` under the names its
   compile-time Lisp calls. */
static void _install_builtins(Lisp lisp) {
  foreach (Var (name, function), Compiler.builtin_targets())
    lisp.set_global(name, function);
}

/** Binds `function`, the operation `lib/meta.x` declares as `name`, under
    its Lisp name in `lisp`. A definition the compile-time libraries
    already give that name wins, because it adapts the arguments.
*/
void Compiler.bind_meta_operation(Lisp lisp, String name, Var function) {
  String dotted = _meta_lisp_name(name);
  Var bound;
  if (!lisp.try_get(dotted, bound)) lisp.set_global(dotted, function);
}

/* The Lisp name of the operation `lib/meta.x` declares as `name`: a method
   `Owner_member` is `Owner.member`, as the Lisp value operations spell
   theirs, and in an `x2c_` helper each `_` becomes `.`. */
static String _meta_lisp_name(String name) =>
  name.startswith("x2c_") ? name.replace("_", ".")
                          : %"${name[:4]}.${name[5:]}";

// diagnostics

static String _definition_note(List definition) {
  List origin = definition.assoc(<origin>);
  String file = origin.assoc(<file>);
  int line = origin.assoc(<line>),
      column = origin.assoc(<column>);
  return %"definition: $file:$line:$column";
}

/** Reports that the compile-time Lisp `source` failed with `error` at
    `invocation`. */
void Compiler.report_lisp_failure(
  Compiler c, Token invocation, List error, String source) {
  $report.macro.lisp_failed(c, invocation, source, error);
}

static List _path_note(Compiler c, String path) =>
  %("path: ${c.display_path(path)}");

/* A template names a hole, projection, or replacement variable that it
   does not bind. */
static void _unbound(Compiler c, String spelling, Token token) {
  $report.parse.variable_unbound(c, spelling, token);
}

// lifecycle

static void _library_shutdown(void) {
  Lisp.destroy(library_session);
  library_session = NULL;
  library_imports = NULL;
  library_definitions = NULL;
  library_comptime = NULL;
  library_scope.destroy();
  library_scope = NULL;
}

/** Ends the shared compile-time library before its build-target Context is
    reclaimed. A later target creates a fresh session in its own Context. */
void Compiler.reset_macro_library(void) {
  _library_shutdown();
  library_filling = 0;
}
