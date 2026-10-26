/*  expressions.x -- expression syntax and its resolution

    The parser reads expressions with C precedence and resolves each node as
    it builds it; constructed syntax enters the same resolver. Resolution
    gives a node its type and binding, and its last step converts the value
    to the type its destination declares. That conversion lives here; the
    walk of a brace initializer over its subobjects lives in
    `initializers.x`.
*/
#pragma once
#include "private-keywords.x"
#include "compiler/compiler.x"
#include "type.x"

/** A printf-family function: its spelling, format and first-value argument
    indexes, and whether recognition requires an unresolved callee.
*/
typedef struct PrintfFn {
  const char *name, int fmt_arg, first_arg, unresolved;
} PrintfFn;

#include "ast-rewrite.x"
#include "grammar.x"
#include "parse/parse.x"
#include "literals/literals.x"
#include "protocol/protocol.x"
#include "transform/transform.x"
#include "stage.x"
#include "initializers/initializers.x"
#include "macros/macros.x"

static macro Stmt $fail.expressions_dynamic_const(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "dynamic update cannot target a const object", $site, NULL);

static macro Stmt $fail.expressions_dynamic_address(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "dynamic update requires an addressable object", $site, NULL);

#include "expressions-reports.x"

/* The semantic context of one expression resolution; handlers share its
   original input, expected type and diagnostic origin. */
module typedef struct Resolve {
  Compiler c;
  List input;
  Type type;
  Token origin;
} Resolve;

module {
  "syntax.x",
  "resolution.x",
  "identifiers.x",
  "access.x",
  "calls.x",
  "operators.x",
  "conversions.x",
}
