/*  meta-sdk.x -- the compiler's answers to `lib/meta.x` operations

    Copyright (c) 2026 Gary William Flake.

    Compile-time code asks the compiler about syntax, types, names, and
    source through the operations `lib/meta.x` declares, and the built-in
    macros ask through their own entries here. A native operation has no
    Compiler parameter, so each answer reads the running call's
    `MetaContext`, which the evaluations in `macros.x` install for their
    extent. An operation that cannot answer reports at the active
    invocation and never returns.
*/

#pragma once
#include "compiler/compiler.x"

/** What the running compile-time call answers from. `expander` is the
    compiler of the active macro expansion, `definition_file` the source of
    its definition, `captures` its complete captured syntax by identity, and
    `has_bindings` whether it bound captured values. `evaluator` is the
    compiler running the call and `site` where the call stands. Each
    evaluation installs its part with `with`, so a captured entry is valid
    only while its expansion is active.
*/
typedef struct MetaContext {
  Compiler expander, evaluator;
  String definition_file;
  Map captures;
  int has_bindings;
  Token site;
} MetaContext;

#include "grammar.x"
#include "macros/macros.x"
#include "meta.x"
#include <limits.h>
#include <stdint.h>
#include <sys/stat.h>

module {
  "context.x",
  "types.x",
  "syntax.x",
  "rewrites.x",
  "sources.x",
  "primitives.x",
}
