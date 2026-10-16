/*  callables.x -- callable values lowered to C helpers

    Copyright (c) 2026 Gary William Flake.

    A callable value that C cannot spell directly becomes a static helper
    queued with `Compiler.add_early`. Every `Func` helper shares one
    `FuncAdapter` ABI: arguments are read in index order from the argument
    vector, and the result is boxed into a `Var`.
    `src/components/component-lambdas.x`
    lowers lambdas.
*/

#pragma once
#include "compiler.x"

#include "adapter-memo.x"
#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "protocol.x"
#include "transform.x"
#include "lambdas.x"

module {
  "callables/adapters.x",
  "callables/values.x",
  "callables/callbacks.x",
}
