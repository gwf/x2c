/*  transform.x -- x2c AST transformation pipeline

    Lowers typed expressions, literals, and statements into the AST forms
    consumed by C emission. One recursive normalizer rewrites each node
    where it is produced, and children enter the same operation, so a unit
    is walked once. `callables.x` lowers the `Func` conversions it meets,
    shipped components lower the forms the kernel no longer lowers, and
    `cleanup.x` lowers each completed function's cleanup regions. The
    active Compiler reports errors.
*/

#pragma once

/* CPP ignores pragma once in its main input. Define the cycle guard only
   during symbol preprocessing, so generated C keeps its declarations. */
#ifndef X2C_TRANSFORM_SOURCE
#ifdef X2CCPP
#define X2C_TRANSFORM_SOURCE
#endif

#include "compiler/compiler.x"

#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

#include "ast.x"
#include "type.x"
#include "parse/parse.x"
#include "expressions/expressions.x"
#include "string/string.x"
#include "symbol.x"
#include "var/var.x"
#include "list/list.x"
#include "protocol/protocol.x"
#include "regions/regions.x"
#include "callables/callables.x"
#include "cleanup/cleanup.x"

/* transform diagnostics. */

static macro Stmt $fail.transform_slice_unsupported(
  Expr $c, Expr $site, Expr $type, Expr $notes) =>
  $c.report_error(
    <xform>, %"type ${$type} does not support slicing",
    $site, $notes);

static macro Stmt $fail.transform_no_shipped_rule(
  Expr $c, Expr $site, Expr $form) =>
  $c.report_error(
    <xform>, %"no rule lowers this ${$form}",
    $site, %("the shipped component that owns it is not linked or failed to "
            "collect; rebuild the compiler from the current prelude sources"));

static macro Stmt $fail.transform_slice_assignment(Expr $c, Expr $site) =>
  $c.report_error(
    <xform>, "slice expressions are not assignable",
    $site, %("call the collection's setslice method explicitly"));

static macro Stmt $fail.transform_string_compound(Expr $c, Expr $site) =>
  $c.report_error(
    <xform>, "String compound assignment supports only String +=",
    $site, NULL);

static macro Stmt $fail.transform_container_compound(
  Expr $c, Expr $site, Expr $lhs_type) {
  {
    String type = $lhs_type.repr();
    $c.report_error(
      <xform>, %"container type $type does not support compound assignment",
      $site, %("update an indexed element instead"));
  }
}

module {
  "traversal.x",
  "expressions.x",
  "operators.x",
  "literals.x",
}

#endif
