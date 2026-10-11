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
module keyword loop $private.loop;
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

module macro Stmt $report.macro.expansion_count(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "macro expansion count exceeds 10000",
    $origin, NULL);

module macro Stmt $report.macro.expansion_recursive(
  Expr $c, Expr $spelling, Expr $origin,
  Expr $definition_note, Expr $shown) =>
  $c.report_error(
    <macro>, %"identical recursive expansion of '${$spelling}'",
    $origin, %(${$definition_note} "input: ${$shown.repr()}"));

module macro Stmt $report.macro.expansion_depth(
  Expr $c, Expr $origin, Expr $definition_note, Expr $first_note) {
  {
    String first_note = %"first expansion: ${$first_note}";
    $c.report_error(
      <macro>, "macro expansion depth exceeds 64", $origin,
      %(${$definition_note} $first_note));
  }
}

module macro Stmt $report.parse.macro_kind(Expr $c) =>
  $c.report_error(
    <parse>, "expected macro result kind before '$'",
    $c.token, NULL);

module macro Stmt $report.parse.macro_result(Expr $c) =>
  $c.report_error(
    <parse>, "macro definition requires a result kind before '$'",
    $c.token, %("write the result kind between 'macro' and the macro name"));

module macro Stmt $report.parse.macro_unknown_kind(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"unknown macro result kind '${$spelling}'",
    $origin, NULL);

module macro Stmt $report.parse.macro_reserved(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"macro name '${$spelling}' is reserved",
    $origin, %("x2c.* is reserved for compiler facilities"));

module macro Stmt $report.macro.name_with(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "'with' cannot be a local macro name",
    $origin, NULL);

module macro Stmt $report.parse.macro_kind_order(Expr $c) =>
  $c.report_error(
    <parse>, "macro result kind belongs after 'macro', before the '$' name",
    $c.token, NULL);

module macro Stmt $report.parse.hole_final(Expr $c) =>
  $c.report_error(
    <parse>, "sequence macro hole must be the final argument",
    $c.token, NULL);

module macro Stmt $report.parse.decorator_singular(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator target parameter must be singular",
    $origin, NULL);

module macro Stmt $report.parse.decorator_kind(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator first parameter has invalid target kind",
    $origin, %("expected Expression, Function, Stmt, Field, Unit,"
      "or NamedType"));

module macro Stmt $report.macro.local_target(
  Expr $c, Expr $target, Expr $origin) =>
  $c.report_error(
    <macro>, %"local decorators cannot target ${$target} syntax",
    $origin, NULL);

module macro Stmt $report.macro.local_result(
  Expr $c, Expr $result_spelling, Expr $origin) =>
  $c.report_error(
    <macro>, %"local macros cannot have ${$result_spelling} results",
    $origin, NULL);

module macro Stmt $report.parse.decorator_target(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator requires a first target parameter",
    $origin, NULL);

module macro Stmt $report.parse.macro_paren_body(Expr $c) =>
  $c.report_error(
    <parse>, "parenthesized macro body requires Expression result or target",
    $c.token, NULL);

module macro Stmt $report.parse.macro_body(Expr $c, Expr $kind, Expr $form) =>
  $c.report_error(
    <parse>, %"${$kind} macro body requires ${$form}", $c.token, NULL);

module macro Stmt $report.parse.hole_untyped(
  Expr $c, Expr $hole_spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"macro hole '${$hole_spelling}' has no inferred kind",
    $origin, %("annotate holes used only by compile-time Lisp"));

module macro Stmt $report.parse.hole_unknown_kind(Expr $c, Expr $spelling) =>
  $c.report_error(
    <parse>, %"unknown macro hole kind '${$spelling}'",
    $c.token, NULL);

module macro Stmt $report.parse.hole_name(Expr $c) =>
  $c.report_error(
    <parse>, "expected macro hole name after '$' or '@'",
    $c.token, NULL);

module macro Stmt $report.parse.hole_duplicate(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"duplicate macro hole '${$spelling}'",
    $origin, NULL);

module macro Stmt $report.parse.splice_expr(Expr $c) =>
  $c.report_error(
    <parse>, "sequence insertion is not legal in an expression slot",
    $c.token, NULL);

module macro Stmt $report.parse.splice_position(Expr $c) =>
  $c.report_error(
    <parse>, "sequence insertion is not legal in this syntax slot",
    $c.token, NULL);

module macro Stmt $report.parse.typed_quotation(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "this quotation cannot declare a name or apply a template",
    $origin,
    %("a typed, Type, or Param quotation builds where it is written"));

module macro Stmt $report.parse.typed_quotation_nested(Expr $c, Expr $origin) {
  {
    String note = "write ${$!T{ ... }} to insert the code it builds";
    $c.report_error(
      <parse>, "typed quotation inside a quotation must be written as a hole",
      $origin, %($note));
  }
}

module macro Stmt $report.parse.hole_ambiguous(
  Expr $c, Expr $spelling, Expr $origin, Expr $first, Expr $also) =>
  $c.report_error(
    <parse>, %"macro hole '${$spelling}' has ambiguous kind",
    $origin, %("first: ${$first}"
      "also: ${$also}"));

module macro Stmt $report.parse.hole_cardinality(
  Expr $c, Expr $sequence, Expr $spelling, Expr $origin) {
  {
    String message = $sequence
      ? %"singular macro hole '${$spelling}' cannot be spliced"
      : %"sequence macro hole '${$spelling}' requires '@'";
    $c.report_error(<parse>, message, $origin, NULL);
  }
}

module macro Stmt $report.macro.keyword_internal(
  Expr $c, Expr $spelling, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"keyword alias cannot name internal macro kind '${$spelling}'",
    $origin, %(${$definition_note}));

module macro Stmt $report.macro.keyword_builtin(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "built-in keyword alias cannot be replaced",
    $origin, NULL);

module macro Stmt $report.parse.keyword_name(Expr $c) =>
  $c.report_error(
    <parse>, "keyword alias requires an identifier",
    $c.token, NULL);

module macro Stmt $report.parse.macro_name(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, $c.peek(1) == <ident>
      ? "expected macro name component after '.'"
      : "expected macro name after '$'",
    $origin, NULL);

module macro Stmt $report.parse.macro_unbound(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <parse>, %"unknown or forward-referenced macro '${$spelling}'",
    $origin, NULL);

module macro Stmt $report.parse.macro_extra_args(Expr $c) =>
  $c.report_error(
    <parse>, "macro invocation has too many arguments",
    $c.token, NULL);

module macro Stmt $report.parse.macro_missing_args(Expr $c) =>
  $c.report_error(
    <parse>, "macro invocation has too few arguments",
    $c.token, NULL);

module macro Stmt $report.macro.argument_contract(Expr $c) =>
  $c.report_error(
    <macro>, "macro argument has no parsing contract",
    $c.token, NULL);

module macro Stmt $report.parse.name_identifier(Expr $c) =>
  $c.report_error(
    <parse>, "Name macro argument requires an identifier",
    $c.token, NULL);

module macro Stmt $report.macro.result_position(
  Expr $c, Expr $spelling, Expr $result,
  Expr $description, Expr $origin) {
  {
    String message =
      %"macro '${$spelling}' has result kind ${$result} and cannot be " +
      %"invoked at ${$description}";
    $c.report_error(<macro>, message, $origin, NULL);
  }
}

module macro Stmt $report.macro.decorator_position(
  Expr $c, Expr $name, Expr $kind, Expr $origin) =>
  $c.report_error(
    <macro>,
    %"decorator '${$name}' targets ${$kind} syntax and cannot be used here",
    $origin, NULL);

module macro Stmt $report.macro.decorator_target(
  Expr $c, Expr $spelling, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"decorator '${$spelling}' requires a following target",
    $origin, %(${$definition_note}));

module macro Stmt $report.macro.decorator_semicolon(
  Expr $c, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, "decorator application must not end with ';'",
    $origin, %(${$definition_note}));

module macro Stmt $report.macro.result_expr(
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

module macro Stmt $report.macro.decorator_expr(
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

module macro Stmt $report.macro.type_name(
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

/* One definition while it is read. `nested` marks a definition inside a
   template, which stays syntax until the template's expansion binds it.
   `locals` holds the template's own declarations, newest first under
   `<order>`, and `captures` the outer names a local macro's body reads. */
module typedef struct Definition {
  Compiler c, Token start;
  Atom name, Symbol kind;
  List target, parameters, template, fresh, captures, pattern, rebuild, type;
  List origin, String file, Map locals, Array using;
  int anonymous, local, nested, quotation, leaf, storage;
} Definition;

module {
  "macros/categories.x",
  "macros/definitions.x",
  "macros/expansion.x",
  "macros/quotations.x"
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

/* Registers an installed rewrite row. A prelude rule whose translator
   this compiler does not link was added after it was built, so the form
   keeps this compiler's own lowering, as a prelude component added after
   it would. */
module void Compiler._install_rewrite(Compiler c, List row) {
  Var shared = shipped_rules ? shipped_rules[row] : void;
  if (shared is void && c.builtin_defs) shared = c._ship_rewrite(row);
  if (shared is <p48>) {
    c._register_rewrite(shared.rewrite_rule());
    return;
  }
  match (row) case %(compile-time rewrite ?point ?kind ?name ?shape ?holes): {
    if (c.builtin_defs && !links_meta_function(name)) return;
    RewriteRule rule = _rewrite_rule(
      point, c.thaw_declaration_syntax(kind), name,
      c.thaw_declaration_syntax(shape), c.thaw_declaration_syntax(holes),
      c.builtin_defs, 1);
    c._register_rewrite(rule);
  }
}

/* The shared rule for a prelude row, or 0 when the row is bound to its
   unit or names a translator the compiler does not link. The shared rule
   derives its matcher on first use. */
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
        if (_unit_bound(row) || !links_meta_function(name)) break;
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
module Var _macro_value_names(Var value) {
  if (value is not <list>) return value;
  String spelling = NULL;
  if (binding_identity_try_parts(value, NULL, spelling))
    return %(binding-name $spelling);
  List child;
  $ast.rewrite_children(value.list(), child, _macro_value_names(child));
}

/* NULL for a template's hole of that name or for an unknown macro. */
module List Compiler._macro_value(Compiler c, Atom name) {
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
          List early = c.bind_syntax(
            _replace_bindings(declaration, replacements), AST_UNIT, NULL);
          c.add_early(early);
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

module Var Compiler._eval_string(Compiler c, String source, Token invocation) {
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

module String Compiler._lisp_form(Compiler c) {
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
  if (c.macro_holes || c.signature_only == SIGNATURE_DECLARATIONS)
    return %(expr (<macro-expr>) (macro-slot 0 $form));
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

module List Compiler._import(Compiler c, String requested, Token invocation) {
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
module Var Compiler._rebind_imported(Compiler c, Var stored) {
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
module String _definition_file(List definition) {
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
module void Compiler._use_lisp_bindings(Compiler c, int install) {
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

module String _definition_note(List definition) {
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
module void Compiler._unbound(Compiler c, String spelling, Token token) {
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
