/*  initializers.x -- brace initializer conversion

    Copyright (c) 2026 Gary William Flake.

    A brace initializer converts each value for the subobject that C's
    initialization order gives it. This unit owns that walk over field
    order and array bounds. A bound only the native compiler knows becomes
    a condition on an unevaluated `*(T *) 0` target, and a value converts
    under each condition that can select it. `expressions.x` converts the
    single values.
*/

#pragma once
#include "private-keywords.x"
#include "compiler.x"
#include "type.x"

#include "grammar.x"
#include "adapter-memo.x"
#include "ast.x"
#include "expressions.x"
#include "macros.x"

module {
  "initializers/subobjects.x",
  "initializers/conversion.x",
}
