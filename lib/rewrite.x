/* Macro-pattern registration for compiler rewrites. */
#pragma once
#include "meta.x"
#include "macro-value.x"

/** Registers the decorated translator with its macro and hole patterns. */
meta Code register_rewrite(Code function, Code pattern, List holes) {
  Macro shape = pattern.value();
  Array patterns = [];
  foreach (Code hole, holes) patterns.push(hole.value());
  return function.register_rewrite(shape, patterns.list_free());
}

/** Tests the full macro pattern at its derived compiler operation. User
    translators run in registration order before builtin defaults. Returning
    void, null, or the input itself declines the rewrite. */
macro Decorator $rewrite(Unit $function, Expr $pattern, Expr @holes) {
  @register_rewrite($function, $pattern, $holes)
}

/** Registers the decorated translator for member calls that find no member
    on a receiver whose aggregate declares a field with the keyword `mark`. */
meta Code register_marked_rewrite(
  Code function, Code mark, Code pattern, List holes) {
  Array patterns = [];
  foreach (Code hole, holes) patterns.push(hole.value());
  return function.register_marked_rewrite(
    mark.value(), pattern.value(), patterns.list_free());
}

/** Tests the full member call pattern on calls that find no member on a
    receiver whose aggregate declares a field with `mark`, such as
    `<delegate>`. Returning void, null, or the input itself declines. */
macro Decorator $rewrite_marked(
    Unit $function, Expr $mark, Expr $pattern, Expr @holes) {
  @register_marked_rewrite($function, $mark, $pattern, $holes)
}

/** Registers the decorated translator for the operator its macro pattern
    spells applied to an operand of `type`. */
meta Code register_typed_rewrite(
  Code function, List type, Code pattern, List holes) {
  Array patterns = [];
  foreach (Code hole, holes) patterns.push(hole.value());
  return function.register_typed_rewrite(
    type, pattern.value(), patterns.list_free());
}

/** Tests the full macro pattern on dynamic operations, those with an
    operand of `type`, which must be `Var` or an alias of it. Returning
    void, null, or the input itself declines the rewrite. */
macro Decorator $rewrite_typed(
    Unit $function, Type $type, Expr $pattern, Expr @holes) {
  @register_typed_rewrite($function, $type, $pattern, $holes)
}
