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
  Compiler c, Var stored, List arguments, Token invocation, AstPos position) {
  Expansion x = {
    .c = c, .definition = c._stored_definition(stored, invocation),
    .input = arguments, .invocation = invocation};
  int block_scope = x.definition.assoc(<kind>) == <decorator> &&
                    x.definition.assoc(<target>) == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  $let(c.token, invocation) {
    x.check();
    List result = NULL;
    $let(c.expansion_floor,
         c.macro_stack ? c.expansion_floor : c.names.next_binding)
    $let(c.macro_stack, c.macro_stack) {
      result = x.bind(position);
    }
    return result;
  }
}

/* The definition a node names: a visible macro, a local macro, or a Macro
   value whose references bind in this unit. */
static List Compiler._stored_definition(
  Compiler c, Var stored, Token invocation) {
  List definition = NULL;
  if (stored.is_atom())
    definition = c._lookup(Atom.intern(stored.str()), invocation);
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
static void Expansion.check(Expansion &x) {
  Compiler c = x.c;
  int leaf = x.definition.assoc(<leaf>) == 1;
  if (!leaf)
    foreach (List active, c.macro_stack) {
      (List prior, List prior_input, Var bindings, Var site) = active;
      (void) bindings, (void) site;
      if (prior == x.definition && prior_input == x.input)
        x.recursion();
    }
  if (c.macro_stack.len() >= 64) x.too_deep();
  if (leaf || !x.invocation) return;
  if (c.macro_count >= 10000)
    $report.macro.expansion_count(c, x.invocation);
  c.macro_count++;
}

static void Expansion.recursion(Expansion &x) {
  Atom name = x.definition.assoc(<name>);
  String spelling = name.str();
  List captured = x.input.search_replace(
    %(capture (source ?syntax) *), <?syntax>);
  Var shown = _source_unwrap(captured);
  $report.macro.expansion_recursive(
    x.c,
    spelling, x.invocation, _definition_note(x.definition), shown);
}

static void Expansion.too_deep(Expansion &x) {
  /* Compiler-generated applications can have no invocation token. */
  List first = x.c.macro_stack.last().list().car();
  $report.macro.expansion_depth(
    x.c,
    x.invocation, _definition_note(x.definition), _definition_note(first));
}

/* Pushes this expansion's frame on the macro stack, fills the template,
   and binds the result. A failed match binds nothing. */
static List Expansion.bind(Expansion &x, AstPos position) {
  Compiler c = x.c;
  List old_stack = c.macro_stack;
  x.template = x.definition.assoc(<template>);
  /* An application compiler code makes has no invocation token. What it
     authors belongs to the source being lowered, so it carries no anchors
     of its own. */
  if (!x.invocation)
    x.template = x.template.search_replace(%(at m-origin ?node), <?node>);
  List fresh_input = x.fresh_names(old_stack);
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
  Ast constructed = matched ? x.construct(template_bindings) : NULL;
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
static List Expansion.fresh_names(Expansion &x, List old_stack) {
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
      List binding = c._introduced_binding(spelling.str(), owner);
      List hole = _hole(binder, <name>, 0);
      fresh_values.push(c._capture_row_project(hole, %($binding), 0));
    }
    else
      x.direct = cons(
        %($binder ${c._private_name(spelling.str(), owner)}), x.direct);
  }
  List members = c._member_bindings(x.definition.assoc(<parameters>), x.input);
  x.direct = x.direct.append(members);
  return fresh_values.list_free();
}

/* A Name hole in a member position supplies the captured spelling, so a
   template local passed there keeps the spelling its source wrote. */
static List Compiler._member_bindings(
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
      %($member ${c._member_spelling(capture.assoc(<value>))}), bindings);
  }
  return bindings;
}

/* The spelling a Name hole's value supplies in a member position: the
   source spelling of a renamed local or a binding, or an `x2c_ident`
   value's own. */
static Var Compiler._member_spelling(Compiler c, Var value) {
  Var spelling;
  match (value) case %("x2c.ident" (!is ?name type string)): return name;
  if (value is not <list>) return value;
  if (c.semantic_binding_facts().try_get(%(source-spelling $value), spelling))
    return spelling;
  String name = binding_identity_spelling(value);
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
static Ast Expansion.construct(Expansion &x, List bindings) {
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

static List Compiler._introduced_binding(
  Compiler c, String source, Token root) =>
  c.sym.introduce(
    root ? c._file_scope_name(root, source)
         : c.fresh_name(%"macro_$source"));

/* A template local's name, which keeps its source spelling. */
static List Compiler._private_name(Compiler c, String source, Token root) {
  List binding = c._introduced_binding(source, root);
  c.set_fact(%(source-spelling $binding), source);
  return binding;
}

/* The spelling names the owning unit and the root invocation's offset, and
   counts repeats of the same name there. */
static String Compiler._file_scope_name(
  Compiler c, Token root, String source) {
  String key = %"macro:${c._scope_owner()}:${root.pos}:$source";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  c.names.counters[key] = count + 1;
  c.names.issued++;
  String digest = "%08x".printf(%"$key:$count".hash());
  return %"_x2c_macro_${source}_$digest";
}

/* The unit's owner spelling, cached per file and package. */
static String Compiler._scope_owner(Compiler c) {
  String owner = NULL;
  $memo(c.names.file_scope_owners, %(${c.filename} ${c.package}), owner) {
    owner = c.filename ? c._owner_spelling() : "";
  }
  return owner;
}

/* Home and package paths stay portable; other paths use their canonical
   absolute identity. */
static String Compiler._owner_spelling(Compiler c) {
  String path = c.canonical_path(Path.absolute(c.filename));
  String owner = home_portable_path(path);
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
  d.head();
  d.naming();
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  // A rejected signature must not leave later declarations as templates.
  $let(c.macro_holes, {}) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    d.using = [];
    d.signature();
    d.arrow();
    d.announce();
    d.body();
  }
  d.finish();
  return d.publish();
}

/* Reads the result kind. A local definition names itself without `$`, and
   an anonymous one has no name to read. */
static void Definition.head(Definition &d) {
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
  d.kind = c._result_kind_token(token);
}

static Symbol Compiler._result_kind_token(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (!category || !category.result)
    $report.parse.macro_unknown_kind(c, token.text, token);
  return category.result;
}

static void Definition.naming(Definition &d) {
  Compiler c = d.c;
  if (d.anonymous) d.name = Atom.intern(c.fresh_name("anonymous_macro"));
  else if (d.local) {
    d.name = Atom.intern(c.token.text);
    c.next();
  }
  else d.name = c._name();
  String spelling = d.name.str();
  if (d.local && d.name == <with>)
    $report.macro.name_with(c, d.start);
  if (spelling.startswith("x2c.") && !c.builtin_defs)
    $report.parse.macro_reserved(c, spelling, d.start);
}

/* Reads the parameter holes, then a `using` clause. A decorator's first
   parameter is its target. */
static void Definition.signature(Definition &d) {
  Compiler c = d.c;
  Array params = [];
  c.expect(<(>);
  if (!c.test(<)>)) {
    do d.parameter(params, c._signature_hole()); while (c.test(<,>));
    c.expect(<)>);
  }
  d.parameters = params.list_free();
  d.check_signature();
  if (c.take_word("using")) c._using_clause(d.using);
  if (c.peek(0) == <:>)
    $report.parse.macro_kind_order(c);
}

static void Definition.parameter(Definition &d, Array params, List hole) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target) d.take_target(hole);
  else params.push(hole);
  if (hole.assoc(<sequence>).int() && c.peek(0) == <,>)
    $report.parse.hole_final(c);
}

/* A Unit target's source stays visible to compile-time Lisp, whose
   template slots find the target hole under `(target)`. */
static void Definition.take_target(Definition &d, List hole) {
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
static void Definition.check_signature(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target)
    $report.parse.decorator_target(c, d.start);
  if (!d.local) return;
  if (d.kind == <unit> || d.kind == <decl-unit>) {
    String result_spelling = _kind_spelling(d.kind);
    $report.macro.local_result(c, result_spelling, d.start);
  }
  if (d.kind != <decorator>) return;
  Symbol kind = d.target_kind();
  if (kind == <function> || kind == <unit> || kind == <named-type>) {
    String target = _kind_spelling(kind);
    $report.macro.local_target(c, target, d.start);
  }
}

/* An Expression result, or a decorator of an expression, has an `=>`
   body. A Stmt result has a braced body or an `=>` expression statement.
   Every other result has a braced body after an optional `=>`. */
static void Definition.arrow(Definition &d) {
  Compiler c = d.c;
  if (d.has_expression_body()) {
    if (c.peek(0) == <"{">) d.body_error();
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
  if (c.peek(0) != <"{">) d.body_error();
}

static int Definition.has_expression_body(Definition &d) =>
  d.kind == <expression> ||
  (d.kind == <decorator> && d.target_kind() == <expr>);

static Symbol Definition.target_kind(Definition &d) {
  if (!d.target) return 0;
  return d.target.assoc(<kind>);
}

/* Reports the body forms the result kind accepts. */
static void Definition.body_error(Definition &d) {
  String form = d.has_expression_body() ? "'=> expression;'"
              : d.kind == <block-item> ? "'{ ... }' or '=> expression;'"
              : "'{ ... }'";
  $report.parse.macro_body(d.c, _kind_spelling(d.kind), form);
}

/* Records where the definition stands and shows its signature, so an
   invocation inside the body names this macro. */
static void Definition.announce(Definition &d) {
  Compiler c = d.c;
  (void) c.record_origin(d.start);
  d.origin = c.token_location(d.start);
  d.file = home_portable_path(c.source_path(c.filename));
  d.show(d.node());
}

/* Reads the body in its own scope, with the kinds it infers for the holes.
   A local macro records the outer names its body captures. A `return` in
   the body is typed where the expansion lands, as at file scope; a
   retained rebuild keeps the type a `return` records. Collection reads the
   whole template, initializers included, as the full parse does. */
static void Definition.body(Definition &d) {
  Compiler c = d.c;
  $let(c.shallow, 0)
  $let(c.return_type, NULL)
  $let(c.runtime_literals, c.runtime_literals || d.anonymous)
  $let(c.local_macro_captures, d.local ? {} : NULL)
  $let(c.local_macro_capture_scopes, c.sym.scope_count()) {
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    d.template = d.read_body();
    if (d.quotation) d.parameters = _quoted_holes(c);
    d.parameters = c._parameter_rows(d.parameters);
    d.captures = _recorded(c.local_macro_captures);
  }
}

/* A Stmt result's body after `=>` is one arrow statement. */
static List Definition.read_body(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <type> || d.kind == <param>) return d.part_body();
  if (d.has_expression_body()) return d.expression_body();
  if (c.peek(0) == <"{">) return c._parse_body(d.body_kind(), d.using);
  return c._arrow_statement(d.anonymous);
}

/* A Stmt arrow's statement is a Stmt macro or decorator invocation, or else
   an expression statement. An anonymous macro's statement omits its `;`,
   which ends the enclosing declaration, and so does a decorator's target
   there. */
static List Compiler._arrow_statement(Compiler c, int open) {
  List macro = c._target_at(AST_STATEMENT, open);
  if (macro) return macro;
  List expression = c.parse_expression();
  if (!open) c.expect(<;>);
  return %(seq (stmnt $expression));
}

/* The legacy form is parenthesized, and a quotation's body is a
   parenthesized or braced group. The canonical form ends at `;`, which an
   anonymous macro omits. */
static List Definition.expression_body(Definition &d) {
  Compiler c = d.c;
  if (d.quotation || c._legacy_expression_body()) {
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
static List Definition.part_body(Definition &d) {
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
static Symbol Definition.body_kind(Definition &d) {
  if (d.kind != <decorator>) return d.kind;
  Symbol target = d.target_kind();
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
static void Definition.finish(Definition &d) {
  d.template = _slot_binders(d.wrap());
  Map bindings = {};
  if (d.target_kind() == <unit>) d.constructed_names(bindings);
  Array locals = d.local_binders(bindings);
  d.template = _replace_bindings(d.template, bindings);
  d.check_kinds();
  d.fresh = d.fresh_rows(locals);
  d.pattern = d.invocation_pattern();
  Map uses = _binder_uses(d.template);
  if (!(void *) uses) return;
  d.rebuild = %(${d.rebuild_template()} ${d.rebuild_keys(uses)});
  d.leaf = !d.nested && d.uses_holes_once(uses);
}

/* A Function decorator's body becomes a function with the target's return
   type and declarator, and an Expression decorator's body a parenthesized
   expression. */
static List Definition.wrap(Definition &d) {
  List replacement = d.template;
  if (d.kind != <decorator>) return replacement;
  Symbol target = d.target_kind();
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
static void Definition.constructed_names(Definition &d, Map bindings) {
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
static Array Definition.local_binders(Definition &d, Map bindings) {
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

static void Definition.check_kinds(Definition &d) {
  foreach (List hole, d.parameters)
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      $report.parse.hole_untyped(d.c, hole_spelling, d.start);
    }
}

/* Each `using` hole and each template local gets a fresh name per
   expansion; the last field marks the names compile-time Lisp reads. */
static List Definition.fresh_rows(Definition &d, Array locals) {
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
static List Definition.rebuild_template(Definition &d) {
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
static List Definition.rebuild_keys(Definition &d, Map uses) {
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
static int Definition.uses_holes_once(Definition &d, Map uses) {
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
static List Definition.publish(Definition &d) {
  List node = d.node();
  $let(d.c.token, d.start) d.show(node);
  return node;
}

/* A named local macro is visible in its scope, and a global one unless a
   template holds it. */
static void Definition.show(Definition &d, List node) {
  if (d.local && !d.anonymous) d.c.sym.define_macro(d.name, node);
  else if (!d.local && !d.nested) d.c.publish_macro_definition_node(node);
}

static List Definition.node(Definition &d) {
  Compiler c = d.c;
  List definition = %(
    macrodef
    (name ${d.name})
    (kind ${d.kind})
    (target ${d.target_kind()})
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
static List Compiler._signature_hole(Compiler c) {
  Symbol kind = 0;
  if (c.peek(0) == <ident> && (c.peek(1) == <$> || c.peek(1) == <@>))
    kind = c._hole_kind();
  int sequence = c.peek(0) == <@>;
  Token token = c._hole_name_token(sequence ? <@> : <$>);
  return c._declare_hole(token, kind, sequence);
}

static Symbol Compiler._hole_kind(Compiler c) {
  const MacroCategory *category = _category(c.token.text);
  Symbol kind = category ? category.hole : 0;
  if (!kind) {
    String spelling = c.token.text;
    $report.parse.hole_unknown_kind(c, spelling);
  }
  c.next();
  return kind;
}

static Token Compiler._hole_name_token(Compiler c, Symbol prefix) {
  c.expect(prefix);
  if (c.peek(0) != <ident>)
    $report.parse.hole_name(c);
  Token name = c.token;
  c.next();
  return name;
}

static List Compiler._declare_hole(
  Compiler c, Token token, Symbol kind, int sequence) {
  String spelling = token.text;
  if (c._hole_record(Atom.intern(spelling)))
    $report.parse.hole_duplicate(c, spelling, token);
  return c._record_hole(spelling, kind, sequence);
}

static List Compiler._record_hole(
  Compiler c, String spelling, Symbol kind, int sequence) {
  List hole = _hole(
    Atom.intern(sequence ? %"*$spelling" : %"?$spelling"),
    kind, sequence);
  c.macro_holes[Atom.intern(spelling)] = hole;
  return hole;
}

static void Compiler._using_holes(Compiler c, Array binders) {
  do binders.push(c._using_hole().assoc(<binder>)); while (c.test(<,>));
}

static List Compiler._using_hole(Compiler c) =>
  c._declare_hole(c._hole_name_token(<$>), <name>, 0);

static List _hole(Atom binder, Symbol kind, int sequence) => %(
    macro-param
    (binder $binder)
    (kind $kind)
    (sequence $sequence)
  );

static List Compiler._hole_record(Compiler c, Atom name) {
  Var stored;
  if (!c.macro_holes.try_get(name, stored)) return NULL;
  return stored;
}

/* The final hole records, with the kinds the body inferred. */
static List Compiler._parameter_rows(Compiler c, List parameters) {
  Array rows = [];
  foreach (List parameter, parameters)
    rows.push(c._hole_record(_hole_name(parameter)));
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

static enum { CATEGORY_HOLE_NAME = 1, CATEGORY_RESULT_NAME = 2 };

static typedef struct MacroCategory {
  const char *spelling;
  Symbol hole, result;
  int target, named;
} MacroCategory;

static const MacroCategory macro_categories[] = {
  { "Expr",          <expr>,       <expression>, 1, 1 },
  { "Expression",    <expr>,       <expression>, 1, 2 },
  { "Stmt",          <block>,      <block-item>, 1, 3 },
  { "Field",         <field>,      <field>,      1, 3 },
  { "Entry",         <map-entry>,  <map-entry>,  0, 3 },
  { "Enumerator",    <enumerator>, <enumerator>, 0, 3 },
  { "Unit",          <unit>,       <unit>,       1, 3 },
  { "Declaration",   0,            <decl-unit>,  0, 2 },
  { "Decorator",     0,            <decorator>,  0, 2 },
  { "Function",      <function>,   0,            1, 1 },
  { "NamedType",     <named-type>, 0,            1, 1 },
  { "Type",          <type>,       0,            0, 1 },
  { "Decl",          <decl>,       0,            0, 1 },
  { "DeclaratorRow", <decl-row>,   0,            0, 1 },
  { "Name",          <name>,       0,            0, 1 },
  { "Literal",       <literal>,    0,            0, 1 },
  { "Param",         <param>,      0,            0, 1 },
  { "Catch",         <catch>,      0,            0, 1 },
  { "Captures",      <captures>,   0,            0, 1 },
  { "MatchRow",      <match-row>,  0,            0, 1 }
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
    if ((category.hole == kind && category.named & CATEGORY_HOLE_NAME) ||
        (category.result == kind && category.named & CATEGORY_RESULT_NAME))
      return category.spelling;
  }
  return kind.str().capitalize();
}

/* definition bodies

   A braced body opens with any `using` lines and reads the items its
   result kind produces as a `seq`. */

static List Compiler._parse_body(Compiler c, Symbol result_kind, Array using) {
  c.expect(<"{">);
  c._parse_body_using(using);
  if (result_kind == <block-item>)
    return cons(<seq>, c.parse_block_items(0).cdr());
  if (result_kind == <field>)
    return c._closed_seq(
      c.peek(0) == <"}"> ? NULL : c.parse_fields(%(struct ())));
  if (result_kind == <enumerator>)
    return c._closed_seq(c.parse_enumerators(%(enum ())));
  if (result_kind == <map-entry>) return c._closed_seq(c.parse_map_entries());
  return c._closed_seq(c._unit_items());
}

/* `using $name;` makes a fresh private name for each expansion. `using
   name;` keeps the file-scope declaration `name` has where the macro is
   written, wherever the expansion lands. */
static void Compiler._parse_body_using(Compiler c, Array binders) {
  while (c.at_word("using") &&
         (c.peek(1) == <$> || c.peek(1) == <ident>)) {
    c.next();
    c._using_clause(binders);
    c.expect(<;>);
  }
}

/* One `using` list: fresh names, or file-scope names. An Expression
   macro, which has no braced body, writes it after its signature. */
static void Compiler._using_clause(Compiler c, Array binders) {
  if (c.peek(0) == <$>) c._using_holes(binders);
  else c._using_names();
}

static void Compiler._using_names(Compiler c) {
  do {
    String spelling = c.token.text;
    c.expect(<ident>);
    /* A name no x2c declaration supplies is a native name left to C. */
    List binding = c.sym.reference_global(%($spelling));
    c.macro_holes[%(using ${binding_identity_spelling(binding)})] = binding;
  } while (c.test(<,>));
}

static List Compiler._closed_seq(Compiler c, List rows) {
  c.expect(<"}">);
  return %(seq @rows);
}

/* Directives between the items stay in the body. */
static List Compiler._unit_items(Compiler c) {
  Array items = [];
  while (c.peek(0) != <"}">) {
    foreach (Var directive, c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  return items.list_free();
}

static int Compiler._legacy_expression_body(Compiler c) {
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
    return c._meta_call_slot(role);
  if (role != <expression> && role != <statement> &&
      c.peek(0) == <$> && c.peek(2) == <(> &&
      !c.peek_macro_hole() && !c._peek_invocation())
    return c._meta_call_slot(role);
  if (c.peek(0) == <"$("> || c.peek(0) == <"@(">)
    return c._lisp_slot(role);
  return c._hole_slot(role);
}

/* The callable supplies syntax in the requested insertion position. */
static List Compiler._meta_call_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <@>;
  if (sequence && !(role in sequence_roles))
    $report.parse.splice_position(c);
  if (!sequence && (role == <block> || role in declaration_roles))
    return NULL;
  List definition = c._peek_invocation();
  if (sequence && definition && _result_kind(definition) != <expression>)
    return c._target_at(_slot_position(role), 1);
  List call = c.try_parse_macro_expression();
  return %(macro-slot $sequence $call);
}

/* A result macro keeps the ordinary position's kind and decorator rules. */
static AstPos _slot_position(Symbol role) {
  switch (role) {
    case <unit>:       return AST_UNIT;
    case <block>:      return AST_BLOCK;
    case <field>:      return AST_FIELD;
    case <enumerator>: return AST_ENUMERATOR;
    case <map-entry>:  return AST_MAP_ENTRY;
    default:           return AST_EXPRESSION;
  }
}

/* A Lisp slot fills a declaration slot only when @ splices it. A block
   item that continues into a declaration, and a statement, keep the
   ordinary grammar. */
static List Compiler._lisp_slot(Compiler c, Symbol role) {
  int splice = c.peek(0) == <"@(">;
  if (splice && !(role in sequence_roles))
    $report.parse.splice_position(c);
  if (role in declaration_roles && !splice) return NULL;
  if (!splice && role == <block> && c.macro_lisp_starts_declaration())
    return NULL;
  if (role == <statement>) return NULL;
  if (role == <expression>) return c.parse_macro_lisp_expression();
  return c._parse_lisp_slot(role);
}

/* A hole fills a slot whose role its kind accepts. A sequence hole of no
   kind takes the slot's kind. */
static List Compiler._hole_slot(Compiler c, Symbol role) {
  List hole = c.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && c.after_hole().type == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    $report.parse.splice_expr(c);
  if (!(role in untyped_roles)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && c.peek(0) != <@> && c.peek(0) != <"@{"> &&
        !c._quoted_role(role))
      return NULL;
    if (kind && !_kind_accepts_role(kind, role)) return NULL;
  }
  List syntax = c._parse_hole(role);
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
  if (prefix == <"@{">) return c._expression_hole(c.token);
  if (prefix != <$> && prefix != <@>) return NULL;
  if (c.peek(1) == <"{">) return c._expression_hole(c.token);
  if (c.peek(1) != <ident>) return NULL;
  Token name = Token.skip_trivia(c.token + 1);
  List hole = c._hole_record(Atom.intern(name.text));
  return hole ? hole : c._quoted_hole(name.text, c.token);
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
  int typed = c._typed_quotation();
  Symbol kind = typed || c.peek(0) == <(> ? <expression> : <block-item>;
  if (!typed && c.peek(0) == <ident>) {
    kind = c._quotation_kind(c.token);
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
    if (c.peek(0) == <(>) locals = c._expression_holes(holes);
    type = c._quoted_type(holes);
  }
  if (!c.macro_holes) locals = locals.append(c._expression_holes(holes));
  List built = c._quotation(start, kind, holes, type);
  if (typed && !(%(dynamic) in holes) && c.folded_constant(built) is not void)
    return built;
  return locals
       ? %(expr ("List") (parens (block @locals (stmnt $built))))
       : built;
}

/* The kind a quotation builds: one a result kind names, or a type or one
   parameter, which only a hole kind names. */
static Symbol Compiler._quotation_kind(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (category && (category.hole == <type> || category.hole == <param>))
    return category.hole;
  return c._result_kind_token(token);
}

/* Whether the quotation after `$!` states its type: `T{` where the
   identifier `T` names no kind, or a group that a brace follows. A type
   keyword such as `int` is an identifier here. */
static int Compiler._typed_quotation(Compiler c) {
  if (c.token.text.is_identifier())
    return c.peek(1) == <"{"> && !_category(c.token.text);
  return c.peek(0) == <(> && c.token.after_group().type == <"{">;
}

/* Declares a hidden local for each `${expression}` or `@{expression}` in
   the body, in source order, and records its name under the sigil's position.
   A nested quotation's holes are its own, and `case ${$name(...)}` is
   a macro pattern. */
static List Compiler._expression_holes(Compiler c, Map holes) {
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
      locals.push(c._hole_local(holes, t.pos));
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
static List Compiler._hole_local(Compiler c, Map holes, int position) {
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
    AST_BLOCK, c.return_type);
}

/* Returns NULL if the quotation registered no expression at this offset. */
static List Compiler._expression_hole(Compiler c, Token prefix) {
  Var name;
  if (!c.macro_holes ||
      !c.macro_holes.try_get(%(expression ${prefix.pos}), name))
    return NULL;
  List hole = c._hole_record(Atom.intern(name));
  return hole ? hole : c._quoted_hole(name, prefix);
}

/* The expression that computes a typed quotation's type: the identifier at
   the cursor, or the group there, which holds a type or a `$name` local or
   `${expression}` hole whose value is the type. */
static List Compiler._quoted_type(Compiler c, Map holes) {
  if (c.peek(0) != <(>) return c._quoted_type_name();
  c.expect(<(>);
  Token origin = c.token;
  List type = NULL;
  if (c.peek(0) == <$>) {
    Var name = c.peek(1) == <"{">
             ? holes[%(expression ${c.token.pos})]
             : Token.skip_trivia(c.token + 1).text;
    c.token = c.after_hole();
    type = c._checked_type(
      c.resolve_expression(%(expr () (ident ${name.str()})), origin), origin);
  }
  else type = c._quoted_type_name();
  c.expect(<)>);
  return type;
}

/* The `Type` expression `type`, which a `meta` function checks names its
   type with a String before a typed quotation inserts it:
   `type_name_error(type) ? (x2c_diagnostic_fail(...), type) : type`. */
static List Compiler._checked_type(Compiler c, List type, Token origin) {
  if (!c.meta_body) return type;
  List error = c._runtime_call("type_name_error", %($type), origin);
  List fail = c._runtime_call(
    "x2c_diagnostic_fail", %($error (expr ("List") (nil))), origin);
  return c.resolve_expression(
    %(expr () (op ? $error
      (expr ("Type") ${source_commas_content(%($fail $type))}) $type)),
    origin);
}

static List Compiler._quoted_type_name(Compiler c) {
  Type parsed = NULL;
  c.parse_type_operand(&parsed);
  return c.cache_literal_list(parsed);
}

static List Compiler._quotation(
  Compiler c, Token start, Symbol kind, Map holes, List type) {
  Definition d = {
    .c = c, .start = start, .kind = kind, .anonymous = 1, .local = 1,
    .quotation = 1, .type = type};
  d.naming();
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  $let(c.macro_holes, holes) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    c.macro_holes[%(quotation)] = 1;
    d.using = [];
    d.announce();
    d.body();
  }
  d.finish();
  List built = d.construction(holes);
  if (built) return built;
  /* Each local supplies one hole, a sequence included, so the quotation
     builds its pending invocation with the values already grouped. */
  List values = %(expr ("List") (nil));
  foreach (List hole, d.parameters.reverse())
    values = c._quoted_cons(
      %(expr () (ident ${_hole_name(hole).str()})), values, start);
  List definition = c.capture_macro_value(d.publish());
  List empty = %(expr ("List") (nil));
  return c._quoted_cons(
    x2c_literal_string("x2c.template"), c._quoted_cons(
      definition, c._quoted_cons(values, empty, start), start), start);
}

/* `head` consed onto the List expression `tail`. */
static List Compiler._quoted_cons(
  Compiler c, List head, List tail, Token origin) {
  List value = c.convert_expression(
    c.resolve_expression(head, origin), %("Var"));
  return %(expr ("List") (cons $value $tail));
}

/* A quotation whose template applies no other template builds its syntax
   where it is written (see "quoted syntax"). Any other quotation, or one
   whose template uses a projection only an expansion makes, returns NULL
   and keeps its definition. */
static List Definition.construction(Definition &d, Map holes) {
  Compiler c = d.c;
  if (d.type) return d.typed_construction(holes);
  if (d.kind == <type> || d.kind == <param>) return d.part_construction();
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
  List cells = c._built_cells(quoted, keys, d.start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* The List cells that build `items`: constant syntax from the literal
   cache, and a hole for each projection `keys` maps. NULL for a binder a
   quotation cannot project where it is written. */
static List Compiler._built_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = c._built_cells(items.cdr(), keys, start);
  List head = tail ? c._built_item(items.car(), keys, start) : NULL;
  return head ? c.literal_cell(head, tail) : NULL;
}

/* An Expr hole's expression in an expression position replaces its whole
   shell, which a rebuild leaves out. */
static List Compiler._built_item(
  Compiler c, Var item, Map keys, Token start) {
  Var row;
  if (item.is_binder() && keys.try_get(item, row))
    return row is <list> ? c._built_hole(row, 0, start)
                         : c.cache_literal_var(item);
  if (item.is_binder() && item.str()[1:].startswith("__macro_")) return NULL;
  if (item is not <list> || item.is_nil()) return c.cache_literal_var(item);
  match (item) {
    case %(at m-origin ?node): item = %("x2c.at" $node);
    case %(expr (<macro-expr>) ?binder):
      if (keys.try_get(binder, row) && row is <list>)
        match (row) case %((macro-param ? (kind expr) ?) expression):
          return c._built_hole(row, 1, start);
  }
  List cells = c._built_cells(item, keys, start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* `("x2c.hole" HOLE PROJECTION VALUE)`, where VALUE is the hole's local
   and HOLE keeps only the hole's kind and cardinality. */
static List Compiler._built_hole(
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

static List Definition.typed_construction(Definition &d, Map holes) {
  Compiler c = d.c;
  Map keys = d.written_keys();
  match (d.rebuild.car()) case %(expr ? *content):
    return c.literal_cell(
      c.cache_literal_var(<expr>),
      c.literal_cell(d.type, c._typed_cells(content, keys, d.start)));
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
  List value = c._hole_value(hole, d.start);
  return c.resolve_expression(
    %(expr ("List") (call $callee (args ${d.type} $value))), d.start);
}

/* `$!Type{ type-name }` and `$!Param{ parameter }` build their List where
   they are written, as a typed quotation builds its expression. */
static List Definition.part_construction(Definition &d) {
  Map keys = d.written_keys();
  match (d.rebuild.car()) case %(macro-bind ?binder):
    return d.c._typed_hole(keys[binder], d.start);
  return %(expr ("List") ${d.c._typed_cells(d.rebuild.car(), keys, d.start)});
}

/* The hole projections a quotation built where it is written fills. Such a
   quotation binds nothing, so it may declare no name and apply no
   template. */
static Map Definition.written_keys(Definition &d) {
  if (!d.rebuild || d.fresh) $report.parse.typed_quotation(d.c, d.start);
  Map keys = {};
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  return keys;
}

/* The List cells that build `items`. A sequence or splice hole
   contributes its items to the List that holds it. */
static List Compiler._typed_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = c._typed_cells(items.cdr(), keys, start);
  Var item = items.car(), row;
  if (item is <list> && !item.is_nil())
    return c.literal_cell(
      %(expr ("List") ${c._typed_cells(item, keys, start)}), tail);
  if (!item.is_binder() || !item.str()[1:].startswith("__macro_"))
    return c.literal_cell(c.cache_literal_var(item), tail);
  if (!keys.try_get(item, row)) $report.parse.typed_quotation(c, start);
  (List hole, Symbol projection) = row.list();
  List value = c._typed_hole(row, start);
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
static List Compiler._typed_hole(Compiler c, List row, Token start) {
  (List hole, Symbol projection) = row;
  List local = c._hole_value(hole, start);
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  int expression = projection == <expression>;
  if (kind == <type>) return c._checked_type(local, start);
  if (hole.assoc(<sequence>).int())
    return lifts ? c._runtime_call("Macro_inserted_items", %($local), start)
                 : local;
  if (kind == <name> && projection == <value>)
    return c._runtime_call("Macro_declared", %($local), start);
  if (!lifts && !expression && kind != <name>) return local;
  return c._runtime_call(
    "Macro_inserted",
    %($local ${x2c_literal_int(lifts)} ${x2c_literal_int(expression)}), start);
}

static List Compiler._runtime_call(
  Compiler c, String name, List arguments, Token start) {
  List callee = c.resolve_expression(%(expr () (ident $name)), start);
  return c.resolve_expression(
    %(expr () (call $callee (args @arguments))), start);
}

static List Compiler._hole_value(Compiler c, List hole, Token start) =>
  c.resolve_expression(%(expr () (ident ${_hole_name(hole).str()})), start);

/* A quotation's hole takes its kind from a name position, or from a
   parameter or statement position where it stands alone, which no
   annotation can give it. A hole that a declarator follows is a parameter's
   type, and one that an operator, `;`, or a postfix form follows is an
   expression. */
static int Compiler._quoted_role(Compiler c, Symbol role) {
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
static List Compiler._quoted_hole(
  Compiler c, String spelling, Token prefix) {
  if (!c.macro_holes || !(%(quotation) in c.macro_holes)) return NULL;
  Type type = NULL;
  List local = c.sym.lookup(%($spelling), type);
  if (!local || !c.sym.binding_is_local(local)) return NULL;
  Symbol kind = c.sym.is_named_value_type(type, "Type") ? <type> : 0;
  int sequence = prefix.type == <@> || prefix.type == <"@{">;
  List hole = c._record_hole(spelling, kind, sequence);
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
static List Compiler._parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  List hole = c.peek_macro_hole();
  if (!hole) c._unbound(c._hole_name_token(token.type).text, token);
  c.token = c.after_hole();
  Atom name = _hole_name(hole);
  int sequence = token.type == <@> ||
                 token.type == <"@{">;
  if (sequence != hole.assoc(<sequence>).int())
    c._cardinality_error(name.str(), sequence, token);
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
  String projection = c._hole_projection(hole, role, sequence);
  return %(macro-bind ${_hole_key(hole, projection)});
}

static void Compiler._cardinality_error(
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
static String Compiler._hole_projection(
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
    if (c._peek_invocation()) return 0;
    opening = Token.skip_trivia(Token.skip_trivia(opening + 1) + 1);
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
  if (hole) hole = c._hole_record(_hole_name(hole));
  if (!slot || !hole || hole.assoc(<kind>) != <name> ||
      hole.assoc(<sequence>).int())
    return slot;
  return %(macro-bind ${_hole_key(hole, "member")});
}

/* A Lisp slot carries its form and the construction binders its Unit holes
   need. A slot inside a Unit decorator also carries the target's. */
static List Compiler._parse_lisp_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <"@(">;
  String form = c._lisp_form();
  Var target = c.macro_holes[%(target)];
  List construction = c._lisp_construction(form);
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
static List Compiler._lisp_construction(Compiler c, String form) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = [];
  Map seen = {};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>)
        c._unit_construction(name, construction, seen);
      token = name;
    }
    token = tokenizer.next();
  }
  return construction.list_free();
}

static void Compiler._unit_construction(
  Compiler c, Token name, Array construction, Map seen) {
  List hole = c._hole_record(Atom.intern(name.text));
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
  (void) binding_identity_try_parts(identity, number, NULL);
  int ordinal = INT_MAX - number;
  return Atom.intern(%"?__macro_${tag ? "tag" : "local"}_${ordinal}");
}

/* Introduces one declaration in the current lexical scope. */
static List Compiler._definition_local(Compiler c, String spelling, int tag) {
  Map locals = c.macro_definition_locals();
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = binding_identity_new(identity, spelling);
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
  return c._definition_local(spelling, 0);
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
  List local = c._definition_local(name, 1);
  c.sym.bind_identity(%(tag), local, %($kind $local));
  if (!definition) locals[%(provisional $local)] = 1;
  return local;
}

/* Replaces each binder or binding identity that `bindings` maps. A List
   none of whose children change stays the same List. */
static Var _replace_bindings(Var value, Map bindings) {
  int candidate = value.is_binder();
  if (!candidate && value is <list> && !value.is_nil())
    candidate = binding_identity_try_parts(value, NULL, NULL);
  Var replacement;
  if (candidate && bindings.try_get(value, replacement)) return replacement;
  if (value is not <list> || value.is_nil()) return value;
  Array items = $auto([]);
  int changed = 0;
  foreach (Var child, value.list()) {
    Var item = _replace_bindings(child, bindings);
    changed |= item != child;
    items.push(item);
  }
  return changed ? items.list().var() : value;
}

/* invocation patterns

   An invocation's capture rows match the definition's pattern: an `args`
   row per parameter, a decorator's target row, and a Name row for each
   fresh name compile-time Lisp reads. Each row binds only the projections
   the template uses. */

static List Definition.invocation_pattern(Definition &d) {
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
  String source = home_portable_path(Path.absolute(c.filename));
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
    case %(compile-time rewrite *): c._install_rewrite(row);
    case %(compile-time lisp ?form (source ?path ?site)): {
      Token token = c.thaw_declaration_syntax(site);
      String file = home_absolute_path(path), text = NULL;
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
      String file = home_absolute_path(source), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL)
        c._import(home_absolute_path(path), token);
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
    and consumes its terminating semicolon.
*/
void Compiler.parse_keyword_definition(Compiler c) {
  Token declaration = c.token;
  int storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  if (c.peek(0) != <ident>)
    $report.parse.keyword_name(c);
  Atom alias = Atom.intern(c.token.text);
  c.next();
  if (c._fixed_alias(alias))
    $report.macro.keyword_builtin(c, declaration);
  Token reference = c.token;
  List definition = c._lookup(c._name(), reference);
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
}

/* Only the built-in sources define `with` or replace a built-in alias. */
static int Compiler._fixed_alias(Compiler c, Atom alias) {
  Var existing;
  return !c.builtin_defs &&
    (alias == <with> ||
     (c._try_macro(c.kw_aliases, alias, existing) &&
      existing.list().assoc(<builtin>).int()));
}

static const SymbolSet alias_kinds =
  %<<expression block-item field enumerator map-entry unit decorator>>;

/* Parses one keyword alias of `c`'s source into `aliases`. */
static void Compiler._record_alias(Compiler c, Map aliases) {
  Token token = c.token;
  if (token.type == <static>) token = Token.skip_trivia(token + 1);
  token = Token.skip_trivia(token + 1);
  Atom alias = Atom.intern(token.text);
  c.parse_keyword_definition();
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

/* A rule derives its matcher now, or else on the first probe of its
   family. */
static RewriteRule _rewrite_rule(
  Symbol point, Var kind, String name, Macro shape, List holes,
  int builtin, int prepared) {
  RewriteRule rule = Scope.calloc(1, sizeof(struct RewriteRule));
  MacroMatcher matcher =
    prepared ? shape.matcher(holes) : (MacroMatcher){shape, holes, NULL};
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

/* Registers an installed rewrite row. */
static void Compiler._install_rewrite(Compiler c, List row) {
  Var shared = shipped_rules ? shipped_rules[row] : void;
  if (shared is void && c.builtin_defs) shared = c._ship_rewrite(row);
  if (shared is <p48>) {
    c._register_rewrite(shared.rewrite_rule());
    return;
  }
  match (row) case %(compile-time rewrite ?point ?kind ?name ?shape ?holes):
    c._register_rewrite(_rewrite_rule(
      point, c.thaw_declaration_syntax(kind), name,
      c.thaw_declaration_syntax(shape), c.thaw_declaration_syntax(holes),
      c.builtin_defs, 1));
}

/* The shared rule for a prelude row, or 0 when the row is bound to its
   unit. The shared rule derives its matcher on first use. */
static Var Compiler._ship_rewrite(Compiler c, List row) {
  $scope(&shipped_scope) {
    if (!shipped_rules) {
      Scope.shutdown_hook(_shipped_shutdown);
      shipped_rules = {};
    }
    _require_owned(row.try_own());
    Var shared = 0;
    match (row)
      case %(compile-time rewrite ?point ?kind ?name ?shape ?holes): {
        if (_unit_bound(row)) break;
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
static MacroMatcher *RewriteRule.prepared_matcher(RewriteRule rule) {
  if (!rule.prepared) {
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
static void Compiler._register_rewrite(Compiler c, RewriteRule rule) {
  if (!c.rewrite_rules) c.rewrite_rules = {};
  Var stored;
  Map kinds;
  if (c.rewrite_rules.try_get(rule.point, stored)) kinds = stored;
  else c.rewrite_rules[rule.point] = kinds = {};
  List rows = kinds.try_get(rule.kind, stored) ? stored.list() : NULL;
  foreach (RewriteRule prior, rows)
    if (prior.name == rule.name &&
        prior.matcher.shape == rule.matcher.shape &&
        prior.matcher.holes == rule.matcher.holes) return;
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

static List Compiler._rewrite_candidates(Compiler c, Symbol point, Var kind) {
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
      <member>, mark, source, AST_EXPRESSION, NULL, site);
    if (rewritten) return rewritten;
  }
  return NULL;
}

/** Tests one operation's registry without invoking a translator. */
int Compiler.has_rewrites(Compiler c, Symbol point, Var kind) =>
  !!c._rewrite_candidates(point, kind);

/** Matches registered patterns for one operation, then binds the first
    replacement. A translator declines with void, null, or its input itself.
    Active rules cannot re-enter. */
List Compiler.rewrite(
  Compiler c, Symbol point, Var kind, List source, AstPos position,
  Type expected, Token site) =>
  c._rewrite(point, kind, source, position, expected, site, 0);

/** Binds and lowers a replacement while its rule remains active. An
    expression retains the result type already established for its parent.
    A replacement whose template and slot signatures an earlier use in the
    unit prepared lowers only its captured values. */
List Compiler.lower_rewrite(
  Compiler c, Symbol point, Var kind, List source, AstPos position,
  Type expected, Token site) =>
  c._rewrite(point, kind, source, position, expected, site, 1);

static List Compiler._rewrite(
  Compiler c, Symbol point, Var kind, List source, AstPos position,
  Type expected, Token site, int lower) {
  // A meta body still completes the calls ordinary lookup misses.
  if (c.macro_holes || (c.meta_body && point != <member>)) return NULL;
  foreach (RewriteRule rule, c._rewrite_candidates(point, kind)) {
    if (c.active_rewrites.contains(rule) ||
        !c.matches_macro(*rule.prepared_matcher(), source)) continue;
    Var result = c.apply_meta_function(rule.name, %($source), site);
    if (result is void ||
        (result is <list> && (!result.list() || result.list() === source)))
      continue;
    $let(c.active_rewrites, cons(rule, c.active_rewrites)) {
      if (!lower) return c.bind_syntax(result, position, expected);
      return c._prepared(source, result, position, expected, site);
    }
  }
  return NULL;
}

/* Binds, converts, and lowers a replacement as written. */
static List Compiler._lowered(
  Compiler c, Var result, AstPos position, Type expected, Token site) {
  List bound = c.bind_syntax(result, position, expected);
  if (position == AST_EXPRESSION) {
    bound = c.convert_expression(bound, expected);
    Type actual = bound.cadr();
    if (actual.canonicalize() != expected.canonicalize())
      $report.rewrite.result_type(c, site, expected, actual);
  }
  return c.normalize(bound);
}

/* prepared replacements

   A translator's replacement is its quotation's template filled with Code
   values it captured from the source, which are already bound and typed.
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
   pending code or a carrier, lowers as written on every use. */

/** Counts compiler state that lowering adds and a skipped lowering would
    not add. A name a scope resolves binds once, so it is not counted. */
static typedef struct Effects {
  int bindings, names, origins, pending, placements, diagnostics;
} Effects;

/** Records the values a replacement's first lowering watches and what
    lowering each produced, in the order lowering reached them. */
struct SlotWatch {
  List values;
  Array outputs, order;
  Effects inner;
  int repeated;
};

static Effects Compiler._effects(Compiler c) {
  PendingMark mark = c.pending.checkpoint();
  int pending = 0;
  for (int i = 0; i < PENDING_AREAS; i++) pending += mark.lengths[i];
  return (Effects){
    c.sym.introduced(), c.names.issued, c.origins.len(), pending,
    c.placements.len(), c.diagnostics.entries.len()};
}

static Effects Effects.since(Effects after, Effects before) => (Effects){
  after.bindings - before.bindings, after.names - before.names,
  after.origins - before.origins, after.pending - before.pending,
  after.placements - before.placements,
  after.diagnostics - before.diagnostics};

static Effects Effects.add(Effects a, Effects b) => (Effects){
  a.bindings + b.bindings, a.names + b.names, a.origins + b.origins,
  a.pending + b.pending, a.placements + b.placements,
  a.diagnostics + b.diagnostics};

static int Effects.same(Effects a, Effects b) =>
  !memcmp(&a, &b, sizeof(Effects));

/* Lowers `result` from the skeleton its template and slot signatures
   prepared in this unit, preparing one on their first use. */
static List Compiler._prepared(
  Compiler c, List source, Var result, AstPos position, Type expected,
  Token site) {
  Array sources = $auto([]), values = $auto([]);
  _typed_nodes(source, sources);
  int refused = 0;
  Var shape = c._template(result, sources, values, refused);
  if (refused) return c._lowered(result, position, expected, site);
  List key = %(${(int) position} $expected $shape);
  if (!c.prepared_rewrites) c.prepared_rewrites = {};
  Var stored;
  if (c.prepared_rewrites.try_get(key, stored))
    return stored is <list>
      ? c._fill(stored, values)
      : c._lowered(result, position, expected, site);
  if (_carries(shape)) {
    c.prepared_rewrites[key] = 0;
    return c._lowered(result, position, expected, site);
  }
  if (c.sym.transacting()) return c._lowered(result, position, expected, site);
  struct SlotWatch watch = {values.list(), [], []};
  foreach (Var value, values) watch.outputs.push(NULL);
  Effects before = c._effects();
  List lowered;
  $let(c.slot_watch, &watch)
    lowered = c._lowered(result, position, expected, site);
  // A memo the template fills adds state only on its first lowering.
  if (!c._effects().since(before).same(watch.inner)) return lowered;
  List skeleton = !watch.repeated && watch.order.len() == values.len()
    ? _skeleton(lowered, watch.outputs) : NULL;
  c.prepared_rewrites[key] =
    skeleton ? %($skeleton ${watch.order.list()}) : 0;
  return lowered;
}

/* Pushes each typed expression in `node`, which a translator may insert
   whole, onto `found`. */
static void _typed_nodes(Var node, Array found) {
  if (node is not <list>) return;
  List syntax = node;
  if (syntax.car() == <expr> && syntax.cadr().list()) found.push(syntax);
  for (; syntax; syntax = syntax.cdr()) _typed_nodes(syntax.car(), found);
}

/* `node` with each typed expression from `sources` replaced by its slot
   signature `("x2c.slot" TYPE SHAPE)` and pushed onto `values`. A literal
   stays in the template, which then lowers it as written. Sets
   `refused` for a value inserted twice or a value whose content conversion
   or lowering reads beyond its signature. */
static Var Compiler._template(
  Compiler c, Var node, Array sources, Array values, int &refused) {
  if (node is not <list> || node.is_nil()) return node;
  List syntax = node;
  if (syntax.car() == <expr>)
    foreach (List value, sources)
      if (value === syntax) return c._slot(syntax, values, refused);
  return c._template_items(syntax, sources, values, refused);
}

static List Compiler._template_items(
  Compiler c, List items, Array sources, Array values, int &refused) {
  if (!items) return NULL;
  Var head = c._template(items.car(), sources, values, refused);
  List tail = c._template_items(items.cdr(), sources, values, refused);
  return head === items.car() && tail === items.cdr()
    ? items : cons(head, tail);
}

static Var Compiler._slot(
  Compiler c, List value, Array values, int &refused) {
  if (value.caddr().list().car() == <literal>) return value;
  Var shape = c._slot_shape(value.caddr());
  foreach (List prior, values) if (prior === value) shape = void;
  if (shape is void) {
    refused = 1;
    return value;
  }
  values.push(value);
  return %("x2c.slot" ${value.cadr()} $shape);
}

/* What conversion and lowering read of a slot value's content besides its
   type: a literal's value, whether a name is a lambda's snapshot, an
   operator with its single operand or a member access with its base, a
   group's content, or else the content's head. Void for content they read
   further, such as a conditional or a composite. */
static Var Compiler._slot_shape(Compiler c, Var content) {
  if (content is not <list>) return void;
  List parts = content;
  Var head = parts.car();
  if (head == <literal>) return content;
  if (head == <ident>)
    return %(lambda-snapshot ${parts.cadr()}) in c.semantic_binding_facts()
      ? %(ident snapshot) : head;
  if (head == <call> || head == <index> || head == <getindex> ||
      head == <postfix> || head == <cast>)
    return head;
  List operands = parts.cdr().cdr();
  if (head == <parens> && parts.cadr().list().car() == <expr>)
    return c._nested_shape(head, parts.cadr());
  if (head != <op>) return void;
  Var op = parts.cadr();
  if (op == <.>) return c._nested_shape(%(op .), operands.car());
  if (op == <?> || op == <,>) return void;
  if (!operands.cdr()) return c._nested_shape(%(op $op), operands.car());
  return %(op $op);
}

/* `prefix` followed by the shape of the typed expression `operand`'s
   content, or void when that content has none. */
static Var Compiler._nested_shape(Compiler c, Var prefix, Var operand) {
  Var shape = c._slot_shape(operand.list().caddr());
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

/* Lowers each slot's value in the order the first lowering reached them
   and fills the skeleton with the results. */
static List Compiler._fill(Compiler c, List prepared, Array values) {
  (List skeleton, List order) = prepared;
  Array lowered = $auto(values.copy());
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
  return _filled_items(syntax, lowered);
}

static List _filled_items(List items, Array lowered) {
  if (!items) return NULL;
  Var head = _filled(items.car(), lowered);
  List tail = _filled_items(items.cdr(), lowered);
  return head === items.car() && tail === items.cdr()
    ? items : cons(head, tail);
}

/** Lowers `ast` when it is a value the active first lowering watches and
    records what its lowering produced; NULL otherwise. */
Ast Compiler.watched_step(Compiler c, Ast ast) {
  SlotWatch watch = c.slot_watch;
  int slot = 0;
  for (List v = watch.values; v && v.car().list() !== ast; v = v.cdr())
    slot++;
  if (slot == (int) watch.outputs.len()) return NULL;
  Effects before = c._effects();
  Ast lowered;
  $let(c.slot_watch, NULL) lowered = c.normalize(ast);
  watch.inner = watch.inner.add(c._effects().since(before));
  if (watch.outputs[slot].list()) watch.repeated = 1;
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
int Compiler.macro_starts_target_at(Compiler c, AstPos position) =>
  c._claims(c._peek_invocation(), position);

/* An invocation is claimed where its result fits. A statement or map entry
   that does not fit parses as an expression. Elsewhere a `$` name, or an
   identifier with arguments, is claimed so that its target parser reports
   the position diagnostic; a local expression macro at block scope remains
   an expression statement. */
static int Compiler._claims(Compiler c, List definition, AstPos position) {
  Symbol kind = definition ? _result_kind(definition) : 0;
  if (kind == _position(position).kind) return 1;
  if (position == AST_STATEMENT || position == AST_MAP_ENTRY) return 0;
  if (!definition) {
    if (c.peek(0) == <$> && (position == AST_BLOCK || c.macro_holes)) {
      String name;
      c._scan_name(name);
      Type type = name ? c.sym.get(%($name)) : NULL;
      if (type.is_function()) return 0;
    }
    return c.peek(0) == <$>;
  }
  return !_bare(c.token, definition) &&
    (position != AST_BLOCK || kind != <expression> ||
     !definition.assoc(<local>).int());
}

static typedef struct MacroPos {
  Symbol kind, const char *description, int semicolon;
} MacroPos;

static const MacroPos macro_position_info[] = {
  { <unit>,       "file scope",    1 },
  { <block-item>, "block scope",   1 },
  { <field>,      "field scope",   1 },
  { <enumerator>, "an enum body",  0 },
  { <map-entry>,  "a map literal", 0 },
  { <block-item>, "block scope",   1 },
  { <expression>, "an expression", 0 }
};

static const MacroPos *_position(AstPos position) =>
  &macro_position_info[position];

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
static List Compiler._peek_invocation(Compiler c) {
  Var stored;
  if (c.peek(0) == <$> || c.peek(0) == <@>) {
    String spelling;
    c._scan_name(spelling);
    if (!spelling ||
        !c._try_definition(Atom.intern(spelling), !c.shallow, stored))
      return NULL;
    return stored;
  }
  if (c.peek(0) != <ident>) return NULL;
  Atom name = Atom.intern(c.token.text);
  List definition = c.sym.has_local_macros()
                  ? c.sym.lookup_macro(name) : NULL;
  if (!definition && c._try_macro(c.kw_aliases, name, stored))
    definition = stored;
  return definition && (c.peek(1) == <(> || _bare(c.token, definition))
       ? definition : NULL;
}

/* Scans the dotted name after the current `$` without consuming tokens.
   A component after a dot may be a keyword, as in `$error.arg.void`.
   Returns the token after the name, or the token where a name component is
   missing with `spelling` set to NULL. */
static Token Compiler._scan_name(Compiler c, String &spelling) {
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
static List Compiler._take_invocation(Compiler c, AstPos position) {
  List definition = c._peek_invocation();
  if (!c._claims(definition, position)) return NULL;
  if (c.peek(0) != <$> && c.peek(0) != <@>) {
    c.next();
    return definition;
  }
  Token invocation = c.token;
  Atom name = c._name();
  Var existing;
  if (c.macro_holes && c.peek(0) != <(> &&
      !c._try_definition(name, 1, existing))
    c._unbound(name.str(), invocation);
  return c._lookup(name, invocation);
}

static Atom Compiler._name(Compiler c) {
  String spelling;
  Token end = c._scan_name(spelling);
  if (!spelling)
    $report.parse.macro_name(c, end);
  c.token = end;
  return Atom.intern(spelling);
}

static List Compiler._lookup(Compiler c, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!c._try_definition(name, 1, stored))
    $report.parse.macro_unbound(c, spelling, invocation);
  return stored;
}

/* With `install_lisp`, a `lisp.` name records the Lisp binding macros as a
   dependency and installs them when the name is not yet defined. */
static int Compiler._try_definition(
  Compiler c, Atom name, int install_lisp, Var &stored) {
  int found = c._try_macro(c.macros, name, stored);
  String spelling = name.str();
  if (!install_lisp || !spelling.startswith("lisp.")) return found;
  c._use_lisp_bindings(!found);
  return found || c._try_macro(c.macros, name, stored);
}

/* Includes publish names immediately. Decode a template into this unit's
   bindings only when it is used, keeping the result in the same name map. */
static int Compiler._try_macro(
  Compiler c, Map definitions, Atom name, Var &stored) {
  if (!definitions.try_get(name, stored)) return 0;
  match (stored) case %(imported-macro ?definition): {
    stored = c._rebind_imported(c.thaw_declaration_syntax(definition));
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
  _collection(c._peek_invocation());

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
  int bare = _bare(c.token, c._peek_invocation());
  String spelling;
  if (c.peek(0) == <$>) c.token = c._scan_name(spelling);
  else c.next();
  if (!bare && c.peek(0) == <(>) c.token = c.token.after_group();
}

/** Consumes a NamedType target already projected by owning-source collection.
    CPP scanning does not produce the declaration or parse its fields again.
*/
int Compiler.skip_named_type_declaration(Compiler c) {
  List definition = c._peek_invocation();
  if (!definition || definition.assoc(<target>) != <named-type>) return 0;
  c.skip_macro_invocation();
  c._skip_shallow_expression(0);
  c.expect(<;>);
  return 1;
}

/** Reports whether the macro invocation at the cursor produces file-scope
    syntax, directly or through the target it decorates. A script unit keeps
    such an invocation at file scope. This query does not consume tokens.
*/
int Compiler.macro_targets_unit(Compiler c) {
  List definition = c._peek_invocation();
  if (!definition) return 0;
  Symbol kind = _result_kind(definition);
  return kind == <unit> || kind == <decl-unit>;
}

/* invocation arguments

   Each parameter hole captures its arguments into one capture row, and a
   captured argument records the source span it was parsed from. */

static List Compiler._invocation_arguments(
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
    arguments.push(c._argument_row(hole, kind));
    if (nodes.cdr() && c.peek(0) != <)>) c._argument_separator(kind);
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
static List Compiler._argument_row(Compiler c, List hole, Symbol kind) {
  int sequence = hole.assoc(<sequence>);
  Array captured = [];
  if (c.peek(0) == <)> && !sequence)
    $report.parse.macro_missing_args(c);
  if (c.peek(0) != <)>) loop {
    c._row_directives(kind, captured);
    Token first = c.token;
    Var argument = c._parse_argument(kind);
    if (kind != <name>) argument = c._capture_source(argument, first, c.token);
    captured.push(argument);
    if (!sequence || !c.test(<,>)) break;
  }
  c._row_directives(kind, captured);
  return c._capture_row_project(hole, captured.list_free(), 0);
}

static void Compiler._row_directives(Compiler c, Symbol kind, Array captured) {
  if (kind == <match-row> && c.token != c.directives_taken)
    foreach (List directive, c.leading_preproc()) captured.push(directive);
}

/* `in` may separate a declaration from what follows, as in
   `foreach (String line in lines)`. Before a literal it scans as a name,
   which cannot follow a declaration either. */
static void Compiler._argument_separator(Compiler c, Symbol kind) {
  if (kind == <decl> && (c.peek(0) == <in> || c.at_word("in"))) c.next();
  else c.expect(<,>);
}

static Var Compiler._parse_argument(Compiler c, Symbol kind) {
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
      case <name>:       return c._name_argument();
      case <literal>:    return c._literal_argument();
    }
    $report.macro.argument_contract(c);
  }
}

/* A caller's name is a spelling, resolved where the expansion places it.
   A name a template writes is private to each expansion: a nested
   declaration made from it is that expansion's, and a reference that no
   such declaration reaches reads its spelling where the expansion lands. */
static Var Compiler._name_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c._parse_hole(<name>);
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

static Var Compiler._literal_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c.parse_assignment();
  return c.parse_atomic_literal();
}

static Var Compiler._capture_source(
  Compiler c, Var syntax, Token first, Token after) {
  if (c.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = c._previous_source_token(after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = c.source_path(c.filename ? c.filename : "<stdin>");
  List source = %(source $file ${first.pos} $end);
  return %(src $source $syntax);
}

static Token Compiler._previous_source_token(Compiler c, Token after) {
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
static void Compiler._bind_name_arguments(
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
          ? binding_identity_spelling(value) : value;
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
static List Compiler._capture_row_project(
  Compiler c, List hole, List sources, int retain) =>
  hole.assoc(<sequence>).int()
    ? c._sequence_row(sources, retain)
    : c._scalar_row(sources, retain);

/* A forwarded projection contributes its own sources, values, and
   construction requirements. */
static List Compiler._sequence_row(Compiler c, List sources, int retain) {
  Array captured_sources = [], values = [], construction = [];
  foreach (Var captured, sources) {
    List forwarded = retain ? NULL : c._forwarded_capture(captured);
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
static List Compiler._scalar_row(Compiler c, List sources, int retain) {
  int singular = sources && !sources.cdr();
  Var source = singular ? sources.car() : sources;
  if (singular && !retain) {
    List forwarded = c._forwarded_capture(source);
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
      binding_identity_try_parts(value, NULL, NULL))
    return %(expr () (ident $value));
  return value;
}

/* The row of a projection a template forwards as an argument. A Unit
   hole's source stands for each of its projections. */
static List Compiler._forwarded_capture(Compiler c, Var captured) {
  List hole = c._forwarded_hole(captured);
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
static List Compiler._forwarded_hole(Compiler c, Var captured) {
  if (!c.macro_holes || captured is not <list> || captured.is_nil())
    return NULL;
  Var direct;
  match (captured) {
    case %(expr (<macro-expr>)
           (macro-bind ?slot)): direct = slot;
    case %(macro-bind ?): direct = captured.list().cadr();
  }
  if (direct is void) return NULL;
  String spelling = direct.str(), prefix = _forwarded_prefix(spelling);
  if (!prefix) return NULL;
  return c._hole_record(Atom.intern(spelling[prefix.len():]));
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
List Compiler.try_parse_macro_target_at(Compiler c, AstPos position) =>
  c._target_at(position, 0);

/* An `open` statement omits its final `;`, as an anonymous Stmt arrow's
   statement does. */
static List Compiler._target_at(Compiler c, AstPos position, int open) {
  if (c.macro_holes && c.peek_macro_hole()) return NULL;
  Token invocation = c.token;
  List definition = c._take_invocation(position);
  if (!definition) return NULL;
  if (definition.assoc(<kind>) == <decorator>)
    return c._decorate(definition, invocation, position, open);
  c._check_position(definition, invocation, position);
  return c._invoke_definition(definition, invocation, position, open);
}

/* A macro's result must fit where it is invoked; a Declaration result also
   fits at file scope. */
static void Compiler._check_position(
  Compiler c, List definition, Token invocation, AstPos position) {
  Symbol kind = definition.assoc(<kind>);
  const MacroPos *place = _position(position);
  if (kind == place.kind || (kind == <decl-unit> && position == AST_UNIT))
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
static List Compiler._invoke_definition(
  Compiler c, List definition, Token invocation, AstPos position, int open) {
  int deferred = !!c.macro_holes;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  List input = c._invocation_arguments(definition, invocation);
  if (_position(position).semicolon && !open) c.expect(<;>);
  List node = c._invocation_node(definition, input, invocation);
  List result = deferred ? %(seq $node) :
    c.bind_syntax(node, position, c.return_type);
  if (result.car() != <seq> || result.len() != 1 ||
      transaction.local_macros_changed()) transaction.commit();
  return result;
}

/* Inside a template the node names its definition as the expansion will
   find it: a definition that is itself template syntax by value, a local
   macro by its local name, and any other macro by name. */
static List Compiler._invocation_node(
  Compiler c, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (c.macro_holes) {
    stored = c._stored_reference(definition);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

/* A template names a visible local macro, so its expansion applies the
   definition published where it lands, with that expansion's names. */
static Var Compiler._stored_reference(Compiler c, List definition) {
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
  AstPos position, Symbol kind, int open;
} Decoration;

static List Compiler._decorate(
  Compiler c, List definition, Token invocation, AstPos position, int open) {
  Decoration d = {
    .c = c, .definition = definition, .invocation = invocation,
    .position = position, .kind = definition.assoc(<target>), .open = open};
  int deferred = !!c.macro_holes;
  if (!d.on_body() && _result_kind(definition) != _position(position).kind)
    d.misplaced();
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  int block_scope = !c.macro_holes && d.kind == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  List node = d.node(d.arguments(block_scope));
  if (deferred) {
    transaction.commit();
    return %(seq $node);
  }
  List result = d.bind(node);
  $let(c.token, invocation) {
    transaction.commit();
  }
  return result;
}

static int Decoration.on_body(Decoration &d) =>
  d.kind == <block> && d.position == AST_UNIT;

static void Decoration.misplaced(Decoration &d) {
  Atom name = d.definition.assoc(<name>);
  String spelling = name.str(), target = _kind_spelling(d.kind);
  $report.macro.decorator_position(d.c, spelling, target, d.invocation);
}

static List Decoration.arguments(Decoration &d, int block_scope) {
  Compiler c = d.c;
  List definition = d.definition;
  List arguments = c._invocation_arguments(definition, d.invocation);
  if (block_scope) c._bind_name_arguments(definition, arguments);
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

static List Decoration.node(Decoration &d, List arguments) {
  Compiler c = d.c;
  d.start = c.token;
  List target = d.target();
  if (d.position == AST_STATEMENT) target = c.anchor_origin(target, d.start);
  List target_capture = d.capture(target);
  List input = %(
    target $arguments
    $target_capture
  );
  return c._invocation_node(d.definition, input, d.invocation);
}

static List Decoration.target(Decoration &d) {
  Compiler c = d.c;
  if (d.on_body()) {
    d.function = c.parse_function_definition();
    match (d.function) case %(function ? ? ?body): return body;
    return NULL;
  }
  if (d.kind == <function>) return c.parse_function_target();
  if (d.kind == <named-type>) return c.parse_named_type();
  if (d.open) return c._arrow_statement(1);
  return c._positional_target(d.position);
}

static List Compiler._positional_target(Compiler c, AstPos position) {
  switch (position) {
    case AST_UNIT:
      $let(c.capture_unit, 1) return c.parse_top_level();
    case AST_BLOCK: case AST_STATEMENT:
      return c.parse_governed(position);
    case AST_FIELD:      return c.parse_field(c.aggregate_type);
    case AST_ENUMERATOR: return c.parse_enumerator(c.aggregate_type);
    case AST_MAP_ENTRY:  return c.parse_map_entry();
    default: __builtin_unreachable();
  }
}

/* The target's capture row. A public Unit target of one item also carries
   that item as the construction the template requires. */
static List Decoration.capture(Decoration &d, List target) {
  Compiler c = d.c;
  List targets = target.car() == <seq> ? target.cdr() : %($target);
  Array captured_targets = [];
  foreach (Var item, targets)
    captured_targets.push(c._capture_source(item, d.start, c.token));
  List captured = captured_targets.list_free();
  List target_capture =
    c._capture_row_project(d.definition.assoc(<targetp>), captured, 0);
  if (d.kind == <unit> && !c._private_target(target) &&
      captured && !captured.cdr())
    target_capture = target_capture.append(%((construct ${captured.car()})));
  return target_capture;
}

/* Visibility comes from a static declaration,
   seen through a lone `seq` and a foreign alias. */
static int Compiler._private_target(Compiler c, List target) {
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

static List Decoration.bind(Decoration &d, List node) {
  Compiler c = d.c;
  if (!d.on_body()) return c.bind_syntax(node, d.position, c.return_type);
  return c._bind_body(node, d.function);
}

/* The body was bound with the function's own result type; bind the
   produced items with it too, so a `return` that needs a conversion still
   gets one. */
static List Compiler._bind_body(Compiler c, List node, List decorated) {
  Type declared = _declared_result(decorated);
  List result = NULL;
  $let(c.return_type, declared) {
    result = c.bind_syntax(node, AST_BLOCK, c.return_type);
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
    List value = c._named_macro_value(invocation);
    if (value) return value;
  }
  if ((c.peek(0) == <$> || c.peek(0) == <@>) && !c._peek_invocation())
    return c._parse_meta_call(invocation);
  List definition = c._take_invocation(AST_EXPRESSION);
  if (!definition) return NULL;
  return c.resolve_expression(
    c._expression_invocation(definition, invocation), invocation);
}

/* Returns the Macro value a `$` name without arguments names. Otherwise the
   cursor returns to the `$`. */
static List Compiler._named_macro_value(Compiler c, Token invocation) {
  Atom name = c._name();
  if (c.peek(0) != <(>) {
    List value = c._macro_value(name);
    if (value) return value;
  }
  c.token = invocation;
  return NULL;
}

static List Compiler._parse_meta_call(Compiler c, Token invocation) {
  c.next();
  /* A meta function is called by its compile-time binding, even from a
     template, whose other free names bind where the expansion lands. */
  List callee = NULL;
  $let(c.macro_holes, NULL) callee = c.parse_variable();
  Type signature = callee.cadr();
  if (!signature.is_function()) {
    c.token = invocation;
    Atom name = c._name();
    (void) c._lookup(name, invocation);
  }
  Array arguments = c._meta_arguments(signature.car().list().cadr());
  Type result = c.macro_holes ? %(<macro-expr>) : signature.cdr();
  /* Inside a `meta` body the whole body runs at compile time, so a `$`
     call there is an ordinary call. */
  Symbol head = c.meta_body && !c.macro_holes ? <call> : <meta-call>;
  List call = %(expr $result ($head $callee
    (args @{arguments.list_free()})));
  return c.resolve_expression(call, invocation);
}

/* Each argument converts to its parameter's type, except in a template. */
static Array Compiler._meta_arguments(Compiler c, List parameters) {
  Array arguments = [];
  c.expect(<(>);
  if (c.peek(0) != <)>) loop {
    List argument = c._meta_argument();
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
static List Compiler._meta_argument(Compiler c) {
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
    ? %(expr (<macro-expr>) ${c._parse_hole(kind ? kind : <argument>)})
    : c.parse_assignment();
  if (hole && argument.match(%(expr ? (macro-bind ?)))) {
    Atom projection = Macro.binder(hole.assoc(<binder>), "value", 0);
    argument = %(expr ("List") (meta-cap $projection));
  }
  return argument;
}

static List Compiler._expression_invocation(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return c._expression_decorator(definition, invocation);
  if (c.meta_body && (kind == <unit> || kind == <block-item>))
    return c._template_call(definition);
  List arguments = c._invocation_arguments(definition, invocation);
  if (kind != <expression>) c._not_expression(definition, invocation);
  List node = c._invocation_node(definition, arguments, invocation);
  return %(expr (<macro-expr>) $node);
}

/* In a `meta` body, invoking a Unit or Stmt macro is a template call,
   whose syntax the meta function builds when it runs. */
static List Compiler._template_call(Compiler c, List definition) {
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

static void Compiler._not_expression(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  String spelling = definition.assoc(<name>).str();
  $report.macro.result_expr(
    c,
    kind, spelling, invocation, _definition_note(definition));
}

static List Compiler._expression_decorator(
  Compiler c, List definition, Token invocation) {
  List arguments = c._invocation_arguments(definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    $report.macro.decorator_expr(
      c,
      spelling, invocation, _definition_note(definition));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    ${c._capture_row_project(definition.assoc(<targetp>), %($target), 0)}
  );
  List node = c._invocation_node(definition, input, invocation);
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
  if (slot.car() == "x2c.template") return c._helper_result(value);
  if (slot.car() != <macro-slot>) return value;
  if (c.macro_holes || !c.macro_stack) return value;
  return c._slot_value(slot);
}

/* A Lisp form evaluates with the active expansion's bindings, and a meta
   call runs. A construction requirement travels with an identifier the
   slot built, and a splice slot around a Unit target replaces the target
   among the items it produced. */
static Var Compiler._slot_value(Compiler c, List slot) {
  int splice = slot.cadr();
  Var form = slot.caddr();
  List active = c.macro_stack.car();
  (List definition, Var input, List bindings, Token invocation) = active;
  (void) input;
  String source_file = _definition_file(definition);
  Var required = slot.assoc(<construct>);
  Var result = form is <list>
    ? c.evaluate_meta_value(form, invocation, 1)
    : c._eval_template_form(form, bindings, invocation, source_file, required);
  result = c._helper_result(result);
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
static Var Compiler._eval_template_form(
  Compiler c, String form, List bindings, Token invocation,
  String source_file, Var construction) {
  c.run_declaration_effects();
  c.ensure_macro_lisp();
  unsigned long serial = template_serial++;
  /* Provenance lookup uses captured Var identity. Structural equality must
     not let constructed or selected syntax acquire a caller's source text. */
  Map source_captures = _source_captures(bindings);
  List references = c._bind_references(serial, bindings);
  if (references) form = _rewrite_references(form, references);
  if (construction is not void)
    form = c._with_construction(serial, form, construction);
  MetaContext *context = MetaContext.current();
  $let(context.has_bindings, !!references)
  $let(context.captures, source_captures)
  $let(context.definition_file, source_file)
  $let(context.expander, c)
    return c._eval_string(form, invocation);
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
static List Compiler._bind_references(
  Compiler c, unsigned long serial, List bindings) {
  List references = NULL;
  foreach (List pair, bindings) {
    if (!pair) continue;
    Var (binder, syntax) = pair;
    String spelling = binder.str()[1:];
    String temporary = %"_x2c_meta_${serial}_$spelling";
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
static String Compiler._with_construction(
  Compiler c, unsigned long serial, String form, Var construction) {
  String temporary = %"_x2c_meta_${serial}_construction";
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
  return c._eval_template_form(
    "(apply (eval $callback) $arguments)",
    %((?callback $callback) (?arguments $arguments)),
    invocation, c.filename, void);
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
  List definition = stored.is_atom() ? c._lookup(stored, site) : stored;
  return %(macro-invoke $stored
    ${c._template_arguments(definition, values, site, 0)}
    m-invoke);
}

/* The capture rows of a template call's values. A scalar Lisp value in an
   Expr hole lifts to an expression first. */
static List Compiler._template_arguments(
  Compiler c, List definition, List values, Token invocation,
  int retain_syntax) {
  Array rows = [];
  List holes = definition.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), values = values.cdr())
    rows.push(
      c._hole_row(holes.car(), values.car(), invocation, retain_syntax));
  return %(args @{rows.list_free()});
}

/* One hole's capture row of `value`. Each scalar Lisp value an Expr hole
   or sequence holds lifts to an expression first. A Type hole's type names
   its type with a String. */
static List Compiler._hole_row(
  Compiler c, List hole, Var value, Token invocation, int retain_syntax) {
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  String error = kind == <type> && value is <list>
               ? type_name_error(value) : NULL;
  if (error) $report.macro.type_name(c, error, invocation);
  if (!hole.assoc(<sequence>).int())
    return c._capture_row_project(
      hole, %(${lifts ? c._lifted(value, invocation) : value}), retain_syntax);
  List sources = value;
  if (lifts) {
    Array lifted = [];
    foreach (Var item, sources) lifted.push(c._lifted(item, invocation));
    sources = lifted.list_free();
  }
  return c._capture_row_project(hole, sources, retain_syntax);
}

/* A number, String, or Symbol becomes the literal expression that holds
   it; other values are already syntax. */
static Var Compiler._lifted(Compiler c, Var value, Token invocation) =>
  value.is_integer() || value.is_floating() || value is <string> ||
  value is <symbol> ? c.lift_macro_lisp_expression(value, invocation) : value;

/* A helper's result with each template call the helper left for the
   compiler replaced by its invocation. */
static Var Compiler._helper_result(Compiler c, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %((!or macrodef "x2c.quoted") *): return value;
    case %(code-value "lowered" *): return value;
    case $source_literal_content(%(*)): return value;
  }
  match (value) {
    case %("x2c.template" ?stored ?(List values)): {
      stored = c._helper_result(stored);
      values = c._helper_result(values);
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
  $ast.rewrite_children(value.list(), child, c._helper_result(child));
}

/** Rebuilds an expression from a pending Macro value application, preserving
    its established root `type`, child stage, and source wrappers. Binding,
    capture collection, hygiene, and effects do not run, and a statement
    expression's template-origin wrappers are omitted. */
List Compiler.rebuild_expression(Compiler c, Type type, List application) {
  List rebuilt = c._rebuild(application, NULL);
  return %(expr $type @{rebuilt.cddr()});
}

/** Rebuilds a statement template as a canonical unbraced `seq`. Bound
    children keep their identities and origins; template-origin wrappers
    are omitted because this path does not open an invocation. */
List Compiler.rebuild_statement(Compiler c, List application) =>
  c._rebuild(application, NULL);

/** Constructs a fresh function from a Unit template after lowering. The
    caller supplies its bound name and lowered children; binding does not
    run. */
List Compiler.rebuild_unit_function(Compiler c, List application) {
  List function = c._rebuild(application, NULL).cadr();
  match (function) case %(api-source ? ? ?inner): return inner;
  return function;
}

/** Rebuilds a bound function through a Function decorator without binding it
    again. The template keeps the target's return type and declarator. */
List Compiler.rebuild_function(Compiler c, List target, List application) =>
  c._rebuild(application, target).cadr();

/* Substitute bound syntax into a structural template without binding it.
   The caller supplies complete children and a template with no free names,
   computed slots, or nested applications. The definition's rebuild row
   holds the template and, for each hole, the binders of the projections
   it uses. Quoted syntax fills its own holes and keeps their values. */
static List Compiler._rebuild(
  Compiler c, List application, List target) {
  match (application) case %("x2c.quoted" ? ?syntax): {
    Landing landing = {.c = c, .site = c.token, .retain = 1};
    return landing.fill(syntax);
  }
  (Var marker, List definition, List values) = application;
  (void) marker;
  List rebuild = definition.assoc(<rebuild>);
  (List template, List keys) = rebuild;
  List rows = c._template_arguments(definition, values, c.token, 1).cdr();
  if (target)
    rows = rows.append(
      %(${c._capture_row_project(
        definition.assoc(<targetp>), %($target), 1)}));
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
  Compiler c, List fresh, Var syntax, AstPos position, Type return_type) {
  Token site = c.macro_invocation_site(<m-invoke>);
  Landing landing = {
    .c = c, .site = site ? site : c.token, .anchored = !!site};
  List bound = NULL;
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    landing.names = c._private_names(fresh);
    Var filled = landing.fill(c.thaw_declaration_syntax(syntax));
    $let(c.token, site)
    $let(c.origin, c.record_origin(site))
      bound = c.bind_syntax(filled, position, return_type);
    transaction.commit();
  }
  if (position == AST_BLOCK || position == AST_STATEMENT ||
      position == AST_UNIT)
    match (bound) case %(seq ?item): return item;
  return bound;
}

/* Each fresh binder's private name. */
static Map Compiler._private_names(Compiler c, List fresh) {
  if (!fresh) return NULL;
  Map names = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
  int file_scope = c.sym.at_file_scope();
  foreach (List row, fresh) {
    (Var binder, Var spelling, Var file) = row;
    names[binder] = c._private_name(
      spelling.str(), file_scope && file.int() ? root : NULL);
  }
  return names;
}

/* The filled syntax. A hole that is a sequence or a splice contributes
   its items to the List that holds it. */
static Var Landing.fill(Landing &l, Var syntax) {
  Var name;
  if (syntax.is_binder())
    return (void *) l.names && l.names.try_get(syntax, name) ? name : syntax;
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  List node = syntax;
  // Only the quoted forms have a String head.
  if (node.car() is <string>)
    match (node) {
      case %("x2c.at" ?inner): {
        Var filled = l.fill(inner);
        return l.anchored ? %(at m-origin $filled).var() : filled;
      }
      case %("x2c.hole" ?(List hole) ?projection ?value):
        return l.hole(hole, projection, value);
    }
  Array items = NULL;
  int index = 0;
  foreach (Var item, node) {
    List spliced = NULL;
    int splices = l.splices(item, spliced);
    Var filled = splices ? void : l.fill(item);
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
  return (void *) items ? items.list_free().var() : syntax;
}

/* Whether `item` is a sequence or splice hole, whose items it sets. */
static int Landing.splices(Landing &l, Var item, List &spliced) {
  if (item is not <list> || item.is_nil() || item.list().car() is not <string>)
    return 0;
  match (item) case %("x2c.hole" ?(List hole) ?projection ?value):
    if (projection == <splice> || hole.assoc(<sequence>).int()) {
      spliced = l.hole(hole, projection, value);
      return 1;
    }
  return 0;
}

/* A hole's projection of its value, as an expansion's capture row holds
   it. A shell is an Expr hole's expression in an expression position,
   which a rebuild leaves bare. */
static Var Landing.hole(Landing &l, List hole, Symbol projection, Var value) {
  Compiler c = l.c;
  if (projection == <member>) return c._member_spelling(value);
  if (!l.retain) value = c._helper_result(value);
  List row = c._hole_row(hole, value, l.site, l.retain);
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
  if (binding_identity_try_parts(value, NULL, spelling))
    return %(binding-name $spelling);
  List child;
  $ast.rewrite_children(value.list(), child, _macro_value_names(child));
}

/* NULL for a template's hole of that name or for an unknown macro. */
static List Compiler._macro_value(Compiler c, Atom name) {
  Var stored;
  if (c.macro_holes && c._hole_record(name)) return NULL;
  if (!c._try_definition(name, 1, stored)) return NULL;
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
  List expression = c._pattern_macro();
  if (!expression || c.peek(0) != <(>) {
    c.token = saved;
    return NULL;
  }
  if (saved.type == <$> && !c._simple_labels()) {
    c.token = saved;
    return c.try_parse_macro_subpattern(0);
  }
  List labels = c.cache_literal_list(c._pattern_labels());
  return c.resolve_expression(
    $!( Macro_case_pattern($expression, $labels) ), saved);
}

/* The Macro value a `$name` or a `Macro` variable at the cursor names. */
static List Compiler._pattern_macro(Compiler c) {
  if (c.peek(0) == <$>) return c._macro_value(c._name());
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
static List Compiler._pattern_labels(Compiler c) {
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
  Token end = c._scan_name(spelling);
  c.token = saved;
  if (!spelling || end.type != <(> ||
      !c._try_definition(Atom.intern(spelling), 1, stored) ||
      stored is not <list> || stored.list().car() != <macrodef>)
    return NULL;
  return end;
}

/* Whether the parenthesized labels at the cursor are all `?name` or
   `*name` binders. */
static int Compiler._simple_labels(Compiler c) {
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
   stands in its hole directly; any other pattern, a bare `*` included,
   replaces a private binder there, spliced for a sequence or Type hole.
   Derivation quotes a `*` it finds, because a template's `*` is an
   operator, so a bare `*` goes in after it. */
static List _macro_subpattern(Macro shape, List patterns, int content) {
  Array names = [];
  Map replacements = {};
  List spelled = patterns.flatten_all();
  int index = 0;
  foreach (List hole, shape.assoc(<parameters>).list()) {
    Var pattern = patterns.car();
    patterns = patterns.cdr();
    if (pattern.is_binder() && pattern.str() != "*") {
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
    List pair = c._captured_pair(binding, type);
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
static List Compiler._captured_pair(Compiler c, List binding, Type type) {
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
    Map replacements = c._code_effects(effects);
    value = replacements.len() ? _replace_bindings(code, replacements) : code;
    retained = stage != "source";
    if (stage != "lowered") {
      Var binder = _carrier_binder(value);
      if (binder) c._unbound(binder.str(), c.token);
    }
    return 1;
  }
  return 0;
}

/* Applies a carrier's effects in order and returns what replaces each
   effect's token in the code. */
static Map Compiler._code_effects(Compiler c, Var effects) {
  Map replacements = {};
  foreach (List effect, effects)
    match (effect) {
      case %(rewrite ?point ?kind ?name ?shape ?holes): {
        c._register_rewrite(
          _rewrite_rule(point, kind, name, shape, holes, 0, 1));
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
      case %(early ?key ?binding ?declaration): {
        $adapter.memo(c, key, replacements[binding]) {
          c.add_early(c.bind_syntax(
            _replace_bindings(declaration, replacements), AST_UNIT, NULL));
        }
      }
      case %(place ?(List where) ?code): c.place(where, code);
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
    block from that point on, as a `defer` placed after it; `(unit-support)`
    among the unit's support declarations, once per KEY with
    `(unit-support KEY)`; or `(unit-init)` in the unit's file
    initialization, in AREA with `(unit-init AREA)`. */
void Compiler.place(Compiler c, List where, Var code) {
  match (where) {
    case %(after-statement): c.place_after(code);
    case %(block-exit): {
      Macro deferred = $deferred;
      c.place_after(deferred(code));
    }
    case %(unit-support): c.add_early(c.bind_syntax(code, AST_UNIT, NULL));
    case %(unit-support ?key): {
      Var placed;
      $adapter.memo(c, key, placed) {
        c.add_early(c.bind_syntax(code, AST_UNIT, NULL));
        placed = 1;
      }
    }
    case %(unit-init):
      c.add_init(<finish>, c.bind_syntax(code, AST_BLOCK, NULL));
    case %(unit-init (!set ?area (!or protocol prepare statics finish))):
      c.add_init(area, c.bind_syntax(code, AST_BLOCK, NULL));
    default: $report.macro.placement(c, where);
  }
}

/** Binds a code-value carrier that a meta call returned outside a macro
    value application as an application binds it, under a transaction that
    also covers its effects. */
List Compiler.bind_code_value(
  Compiler c, List carrier, AstPos position, Type return_type) {
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
   such as a lowered match pattern, and a bare `*` or `?` is syntax. */
static Var _carrier_binder(Var value) {
  if (value.is_binder()) return value.str().len() > 1 ? value : NULL;
  if (value is not <list>) return NULL;
  match (value) {
    case $source_identifier_content(%(?name *)):
      if (name.is_binder() && name.str().len() > 1) return name;
    case %(bind ?name *):
      if (name.is_binder() && name.str().len() > 1) return name;
    case $source_literal_content(%(*)): return NULL;
    case %((!or "x2c.template" "x2c.quoted" macro-invoke macrodef) *):
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
  foreach (Var (relative, message), _library_files())
    c._eval_library(ready, relative, message);
  if (!ready) c._install_native_operations();
}

static Var Compiler._eval_string(Compiler c, String source, Token invocation) {
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

static String Compiler._lisp_form(Compiler c) {
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
  int is_import = c._import_path(import_path);
  String form = c._lisp_form();
  if (is_import) return c._import(import_path, invocation);
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
  if (c._import_path(requested)) {
    if (!c.source_private) {
      String path = home_portable_path(c._canonical_path(requested, c.token));
      String source = home_portable_path(Path.absolute(c.filename));
      c.record_compile_time_effect(
        %(compile-time import $path
          (source $source ${c.freeze_declaration_syntax(c.token)})),
        c.token);
    }
    c.parse_macro_lisp_top_level();
    return;
  }
  Token first = c.token;
  String form = c._lisp_form();
  /* As in full parsing, the shared session already holds an inherited
     import's forms, and running one again would rebind an ancestor's name. */
  if (c.inherited_lisp) return;
  if (!c.source_private) {
    String path = home_portable_path(Path.absolute(c.filename));
    c.record_compile_time_effect(
      %(compile-time lisp $form
        (source $path ${c.freeze_declaration_syntax(first)})), first);
  }
  c.queue_declaration_effect(form, first, c.token);
}

/** Evaluates a queued source Lisp form with its original diagnostic site. */
void Compiler.evaluate_declaration_effect(
  Compiler c, String form, Token invocation) {
  List key = %(${home_portable_path(Path.absolute(c.filename))}
               ${invocation.pos} $form);
  if (key in c.evaluated_effects ||
      (!library_filling && library_imports && key in library_imports)) return;
  $let(c.collect_protocols, 1) {
    c.ensure_macro_lisp();
    c._eval_string(form, invocation);
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
  String form = c._lisp_form();
  if (c.macro_holes) return %(expr (<macro-expr>) (macro-slot 0 $form));
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  Var value = c._eval_string(form, invocation);
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
  if (identifier is not void) return %(expr () (ident $identifier));
  if (value is <list> && !value.is_nil())
    return c.bind_syntax(c._helper_result(value), AST_EXPRESSION, NULL);
  $report.macro.lisp_expr(c, invocation, value);
}

/** Binds a compile-time Lisp code `value` returned to a statement at
    `context`. */
List Compiler.bind_macro_lisp_statement(
  Compiler c, List value, AstPos context) {
  value = c._helper_result(value);
  return c._statement_expression(value)
    ? %(stmnt ${c.lift_macro_lisp_expression(value, c.token)})
    : c.bind_syntax(value, context, c.return_type);
}

/* The root inside a carrier determines whether the statement discards an
   expression or binds a statement. Ordinary binding consumes the carrier. */
static int Compiler._statement_expression(Compiler c, List value) {
  loop match (value) {
    case %((!or "x2c.quoted" src at) ? ?root): value = root;
    case %("x2c.at" ?root): value = root;
    case %(code-value ? ?root ?): value = root;
    case %(macro-invoke ?stored ? ?site):
      return _result_kind(
        c._stored_definition(
          stored, c.macro_invocation_site(site))) == <expression>;
    case %(expr *): return 1;
    default: return _sdk_identifier_result(value) is not void;
  }
}

static Var _sdk_identifier_result(Var value) {
  match (value)
    case %("x2c.ident" (!is ?spelling type string)): return spelling;
  return value is <list> &&
         binding_identity_try_parts(value, NULL, NULL) ? value : void;
}

static Var _lisp_import_hook(String path) {
  MetaContext *context = MetaContext.current();
  Compiler c = context.evaluator;
  if (!c) raise %(bad-state (operation "compile-time import"));
  c._import(path, context.site);
  return %();
}

/* Lisp files use the translation session and ordinary dependency tracking.
   Source declarations travel through #include and the selected interface. */

static List Compiler._import(Compiler c, String requested, Token invocation) {
  c.ensure_macro_lisp();
  String path = c._canonical_path(requested, invocation);
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
    $report.macro.import_extension(c, invocation, c._path_note(path));
  Map before = c.deps.copy();
  String text = c._read_source(
    path, "cannot open compile-time Lisp import", invocation);
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

static int Compiler._import_path(Compiler c, String &?path) {
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
static Var Compiler._rebind_imported(Compiler c, Var stored) {
  if (stored is not <list>) return stored;
  List definition = stored;
  if (definition.car() != <macrodef>) return definition;
  Map replacements = {};
  c._reference_bindings(definition, replacements);
  if (!replacements.len()) return definition;
  return _replace_bindings(definition, replacements);
}

static void Compiler._reference_bindings(
  Compiler c, List syntax, Map replacements) {
  match (syntax)
    case %(expr ? ${$source_identifier_content(%(?binding))}): {
      String spelling = NULL;
      if (binding_identity_try_parts(binding, NULL, spelling))
        replacements[binding] = c.sym.reference_global(%($spelling));
      return;
    }
  foreach (Var child, syntax)
    if (child is <list>) c._reference_bindings(child, replacements);
}

// source files

/* A relative import names a file beside the source that writes it at
   `site`, or else one under the home's `lib/`. */
static String Compiler._canonical_path(Compiler c, String path, Token site) {
  if (!path || path[0] == '/') return c.canonical_path(path);
  String local = %"${c._source_dir(site)}/$path";
  String system = %"${c.root_dir}/lib/$path";
  int use_system = !c.sources.exists(local) && c.sources.exists(system);
  return c.canonical_path(use_system ? system : local);
}

/* The importing macro file, or the file whose lines hold `site`. */
static String Compiler._source_dir(Compiler c, Token site) {
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
  return !file || file.startswith("<") ? file : home_absolute_path(file);
}

/* Reads a compile-time source and records its content hash as a
   dependency. */
static String Compiler._read_source(
  Compiler c, String path, String message, Token token) {
  String text = c._source_text(path, message, token, c._path_note(path));
  c.deps.merge_translation_dependency(path, "%08x".printf(text.hash()));
  return text;
}

/* An unreadable compile-time source is a located diagnostic. */
static String Compiler._source_text(
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
      return c._fill_library(shared);
  }
}

/* A failure while filling leaves no session, so each unit loads its own. */
static Lisp Compiler._fill_library(Compiler c, Lisp shared) {
  library_filling = 1;
  try {
    _install_builtins(shared);
    foreach (Var (relative, message), _library_files())
      c._eval_library(0, relative, message);
    c._install_native_operations();
  }
  catch %(? *): {
    library_filling = 0;
    return NULL;
  }
  return shared;
}

/* The four libraries and the message each failure reports, in the order a
   session needs them. */
static List _library_files(void) => %(
  ("etc/init.xlisp" "cannot open the compile-time Lisp environment")
  ("etc/lisp-values.xlisp" "cannot open the compile-time value operations")
  ("etc/compiler-sdk.xlisp" "cannot open the compile-time Lisp SDK")
  ("etc/builtin-core.xlisp" "cannot open the built-in macro support"));

/** Records the compile-time Lisp libraries as dependencies of `c`, as each
    use of its session does. */
void Compiler.add_library_dependencies(Compiler c) {
  foreach (List library, _library_files())
    c.add_translation_dependency(%"${c.root_dir}/${library.car()}");
}

/* A home Lisp library is evaluated once, when `loaded` is zero, but every use
   records it, so a file's dependencies do not depend on whether an earlier
   file loaded it. */
static void Compiler._eval_library(
  Compiler c, int loaded, String relative, String message) {
  String path = %"${c.root_dir}/$relative";
  c.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  if (loaded || Compiler.inherits_import(path)) return;
  String text = c._source_text(path, message, c.token, %("path:" $path));
  c._eval_string(text, c.token);
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
int macro_library_filling(void) => library_filling;

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
  c._install_source(
    builtin_macros, "<builtin:macros>", builtin_macros_marker, 1);
}

static void Compiler._install_source(
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
  Map aliases = child._read_definitions();
  c.macros[marker] = aliases;
}

/* A shipped source holds only definitions and keyword aliases. */
static Map Compiler._read_definitions(Compiler c) {
  Map aliases = {};
  while (c.peek(0) != <eof>) {
    if (c.keyword_form_is_definition()) c._record_alias(aliases);
    else if (c.macro_form_is_definition()) c.parse_macro_definition();
    else
      $report.macro.builtin_form(c);
  }
  return aliases;
}

/* Every `lisp.` lookup records the bindings file, which is installed only
   when `install` is nonzero and the bindings are not yet installed. */
static void Compiler._use_lisp_bindings(Compiler c, int install) {
  if (!lisp_bindings_marker) lisp_bindings_marker = "_x2c.lisp.bindings";
  int loaded =
    !install || lisp_bindings_marker in c.macros;
  if (!loaded) c.ensure_macro_lisp();
  c._eval_library(
    loaded, "etc/lisp-bindings.xlisp",
    "cannot open the native Lisp macro support");
  if (loaded) return;
  /* Signature imports may preload into the shared parent; group state starts
     only when this unit installs the binding macros. */
  c.macro_lisp.eval(
    %(begin (def lisp.binding.rows ()) (def lisp.binding.sealed ())));
  c._install_source(
    lisp_binding_macros, "<builtin:lisp-bindings>", lisp_bindings_marker, 0);
}

/* native operations

   Native operations read the active expansion's context, not the session
   that owns their callable, so the shared parent owns them once. */

static void Compiler._install_native_operations(Compiler c) {
  _bind_primitives(c.macro_lisp);
  foreach (Var (name, function), Compiler.compiler_targets()) {
    c.macro_lisp.set_global(name, function);
    Compiler.bind_meta_operation(c.macro_lisp, name, function);
  }
}

/* Cold declaration collection needs literals before the meta surface is
   parsed, so the runtime's own compiled builders come first. Internal
   primitives carry the `_x2c.` prefix. */
static void _bind_primitives(Lisp lisp) {
  $lisp.bind(lisp, "x2c_literal_string", x2c_literal_string);
  $lisp.bind(lisp, "x2c_literal_int", x2c_literal_int);
  $lisp.bind(lisp, "x2c_literal_symbol", x2c_literal_symbol);
  $lisp.bind(lisp, "_x2c.import-hook", _lisp_import_hook);
  Compiler.bind_sdk_primitives(lisp);
}

/* Binds the built-in macro algorithms into `lisp` under the names its
   compile-time Lisp calls; the native Lisp binding algorithms carry the
   `_x2c.` prefix of internal primitives. */
static void _install_builtins(Lisp lisp) {
  foreach (Var (name, function), builtin_targets()) {
    String spelling = name;
    lisp.set_global(
      spelling.startswith("binding_") ? %"_x2c.$spelling" : spelling,
      function);
  }
}

/** Binds `function`, the operation `lib/meta.x` declares as `name`, under
    its Lisp name in `lisp`. A predicate answers a Lisp truth value where the
    x2c spelling answers `int`. A definition the compile-time libraries
    already give that name wins, because it adapts the arguments.
*/
void Compiler.bind_meta_operation(Lisp lisp, String name, Var function) {
  String dotted = _meta_lisp_name(name);
  Var bound;
  if (lisp.try_get(dotted, bound)) return;
  if (name.startswith("x2c_type_is_"))
    function = lisp.eval(
      %(lambda (value) (if (eq? ((quote $function) value) 0) nil true)));
  lisp.set_global(dotted, function);
}

/* The Lisp name of the operation `lib/meta.x` declares as `name`: each `_`
   becomes `.`, a predicate `x2c_type_is_X` is `x2c.type.X?`, and two names
   keep the hyphen of their Lisp spelling. */
static String _meta_lisp_name(String name) {
  if (name == "x2c_type_tag_name") return "x2c.type.tag-name";
  if (name == "x2c_type_reverse_name") return "x2c.type.reverse-name";
  if (name.startswith("x2c_type_is_")) return %"x2c.type.${name[12:]}?";
  return name.replace("_", ".");
}

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

static List Compiler._path_note(Compiler c, String path) =>
  %("path: ${c.display_path(path)}");

/* A template names a hole, projection, or replacement variable that it
   does not bind. */
static void Compiler._unbound(Compiler c, String spelling, Token token) {
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
void macro_library_reset(void) {
  _library_shutdown();
  library_filling = 0;
}
