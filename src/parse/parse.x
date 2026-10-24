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
#include "compiler/compiler.x"
#include "type.x"
#include "parse-reports.x"
#include "grammar.x"
#include "statements.x"
#include "expressions/expressions.x"
#include "literals/literals.x"
#include "collect/collect.x"
#include "macros/macros.x"
#include "protocol/protocol.x"
#include "utils.x"

/* parse diagnostics. */

static macro Stmt $fail.parse_decorator_top(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "top-level decorators are not supported",
    $site, %( "module initialization: void TYPE.initialize(void)" ));

static macro Stmt $fail.parse_body_expected(
  Expr $c, Expr $site, Expr $unexpected) =>
  $c.report_error(
    <parse>, "expected ';', '{', or '=>'",
    $site, %("token:" ${$c.token.text} "symbol:" ${$unexpected.str()}));

static macro Stmt $fail.parse_meta_function(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "a native meta declaration must be a function",
    $origin, NULL);

static macro Stmt $fail.parse_unit_single(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "submit one top-level item at a time",
    $site, NULL);

static macro Stmt $fail.parse_package_identifier(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "package name must be a C identifier",
    $origin, NULL);

static macro Stmt $fail.parse_import_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected a quoted package name after 'import'",
    $site, NULL);

static macro Stmt $fail.parse_import_local(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected a local name after 'as'",
    $site, NULL);

static macro Stmt $fail.parse_import_member(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected a package member name after 'with'",
    $site, NULL);

static macro Stmt $fail.parse_function_row(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "a function definition cannot share a declaration row",
    $site, NULL);

static macro Stmt $fail.parse_meta_constructed(
  Expr $c, Expr $origin, Expr $name) =>
  $c.report_error(
    <parse>, %"meta function '${$name}' cannot be produced by a macro",
    $origin, %( "move it to a source file and call it from the macro" ));

static macro Stmt $fail.parse_decl_function(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "Decl macro argument cannot be a function declaration",
    $site, NULL);

static macro Stmt $fail.parse_decl_typedef(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "Decl macro argument cannot be a typedef",
    $site, NULL);

static macro Stmt $fail.parse_destructure_init(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "destructuring declaration requires an initializer",
    $site, NULL);

static macro Stmt $fail.parse_destructure_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected identifier in destructuring declaration",
    $site, %("destructuring targets must be simple identifiers"));

static macro Stmt $fail.parse_scalar_invalid(
  Expr $c, Expr $origin, Expr $source) =>
  $c.report_error(
    <type>, $source ? %"invalid scalar type ${$source}"
                 : "expected scalar type",
    $origin, NULL);

static macro Stmt $fail.parse_attribute_packed(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "packed attributes are unsupported",
    $origin, NULL);

static macro Stmt $fail.parse_delegate_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "delegate field requires a name",
    $site, NULL);

static macro Stmt $fail.parse_named_type_abstract(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "named type requires an abstract type after its name",
    $origin, NULL);

static macro Stmt $fail.parse_enum_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected enumerator identifier",
    $site, NULL);

static macro Stmt $fail.parse_enum_bound(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <parse>, %"enumerator '${$spelling}' is already bound in this scope",
    $origin, %("prior binding: '${$spelling}'"));

static macro Stmt $fail.parse_syntax_position(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "syntax cannot be constructed at this position",
    $origin, NULL);

static macro Stmt $fail.parse_paren_unclosed(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "missing closing parenthesis",
    $site, NULL);

static macro Stmt $fail.parse_type_unknown(Expr $c, Expr $first) =>
  $c.report_error(
    <parse>, %"unknown type name '${$first.text}'",
    $first, %("name an imported package type through its alias"));

static macro Stmt $fail.parse_dimension_close(
  Expr $c, Expr $site, Expr $expr, Expr $unexpected) =>
  $c.report_error(
    <parse>, "expected ']'",
    $site, %("dimension:" ${$expr.str()} "symbol:" ${$unexpected.str()}));

static macro Stmt $fail.parse_macro_member(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "macro method declaration requires a member name",
    $site, NULL);

static macro Stmt $fail.parse_method_owner(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "method name has no concrete owner",
    $site, NULL);

static macro Stmt $fail.parse_params_close(
  Expr $c, Expr $site, Expr $params, Expr $unexpected) =>
  $c.report_error(
    <parse>, "expected ')'",
    $site, %("parameters:" ${$params.str()}
      "symbol:" ${$unexpected.str()}));

static macro Stmt $fail.parse_params_empty(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "empty parameter list; use (void)",
    $site, NULL);

static macro Stmt $fail.parse_method_member(
  Expr $c, Expr $site, Expr $owner) =>
  $c.report_error(
    <parse>, "expected method name after dot",
    $site, %( "typedef:" ${$owner} "token:" ${$c.token.text}  ));

static macro Stmt $fail.parse_function_body(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "Function macro argument requires a function body",
    $site, NULL);

static macro Stmt $fail.parse_shutdown_duplicate(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <parse>, "translation unit has more than one type shutdown",
    $site, %( "shutdown:" ${$name} ));

static macro Stmt $fail.parse_init_duplicate(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <parse>, "translation unit has more than one type initializer",
    $site, %( "initializer:" ${$name} ));

static macro Stmt $fail.parse_lifecycle_signature(
  Expr $c, Expr $site, Expr $role, Expr $name) {
  {
    String message = $role == "initializer"
      ? "type initializer must have signature void TYPE.initialize(void)"
      : "type shutdown must have signature void TYPE.shutdown(void)";
    $c.report_error(<parse>, message, $site, %("${$role}: ${$name}"));
  }
}

static macro Stmt $fail.parse_init_incomplete(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>,
    "managed initializer requires a complete block-local initializer",
    $origin, NULL);

static macro Stmt $fail.parse_auto_storage(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "auto requires an initialized block-local object declaration",
    $origin, NULL);

static macro Stmt $fail.parse_auto_combined(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "declaration auto cannot be combined with a managed initializer",
    $origin, NULL);

static macro Stmt $fail.parse_auto_inference(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "auto inference requires one initialized plain name with an object value",
    $origin, NULL);

static macro Stmt $fail.parse_placement_repeated(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "code placed after a declarator repeats an earlier placement",
    $origin, %("a managed initializer cannot manage another one"));

static macro Stmt $fail.parse_placement_item(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>, "code placed after a statement needs an enclosing block item",
    $site, NULL);

static macro Stmt $fail.parse_placement_function(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>, "code placed at function entry needs an enclosing function",
    $site, NULL);

/* Reported at the lowering origin when one is set. */
static macro Stmt $fail.parse_placement_finalizer(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>, "code placed at function entry cannot land in a defer finalizer",
    $site,
    %("a finalizer runs as its own callback; place after a statement"));

static macro Stmt $fail.parse_syntax_expected(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected syntax",
    $site, NULL);

static macro Stmt $fail.parse_statement_single(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected one statement",
    $site, NULL);

static macro Stmt $fail.parse_alias_target(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "foreign alias target must be one direct function declaration",
    $site, NULL);

static macro Stmt $fail.parse_alias_body(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "foreign alias declaration cannot have a body",
    $site, NULL);

static macro Stmt $fail.parse_alias_storage(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "foreign alias has invalid storage class",
    $site, %("allowed storage: static or inline"));

static macro Stmt $fail.parse_alias_variadic(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "foreign alias cannot be variadic",
    $site, NULL);

static macro Stmt $fail.parse_alias_identifier(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "foreign alias native target must be a direct identifier",
    $site, NULL);

static macro Stmt $fail.parse_alias_self(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "foreign alias cannot name itself",
    $site, NULL);

static macro Stmt $fail.parse_alias_function(
  Expr $c, Expr $site, Expr $native_type) =>
  $c.report_error(
    <type>, "foreign alias native target is not a function",
    $site, %("type: ${$native_type.repr()}"));

static macro Stmt $fail.parse_reference_placement(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "transparent references are only supported on parameters",
    $site, NULL);

static macro Stmt $fail.parse_binder_conflict(
  Expr $c, Expr $origin, Expr $role, Expr $name) =>
  $c.report_error(
    <type>, %"${$role} binder has conflicting capture kinds",
    $origin, %( "binder:" ${$name} "use either '?' or '*' consistently"));

static macro Stmt $fail.parse_binder_unassigned(
  Expr $c, Expr $origin, Expr $role, Expr $binder) =>
  $c.report_error(
    <type>, %"${$role} binder is not definitely assigned",
    $origin, %( "binder:" ${$binder.str()}
                "bind it in every alternative and never under !not"));

module {
  "units.x",
  "declarations.x",
  "types.x",
  "declarators.x",
  "auto.x",
  "functions.x",
  "placement.x",
  "binding.x",
}
