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
