/*  macros.x -- source macros and the compile-time calls they run

    This module owns macro expansion. Expansion fills a definition's
    template from an invocation's captures and binds the result through the
    operations that bind parsed source. A definition is a compiler-only
    `macrodef` List: its holes, a Match pattern over an invocation's
    capture rows, and a template of the binders that pattern captures.
    A template's meta-call slots, `$name(...)` and `@name(...)`, run native
    `meta` functions through the unit's `MetaBindings`.
*/

#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "grammar.x"
#include "ast-rewrite.x"
#include "compiler/compiler.x"
#include "adapter-memo.x"
#include "fields.x"
#include "expressions/expressions.x"
#include "builtins.x"
#include "linked-meta.x"
#include "literals/literals.x"
#include "lambdas.x"
#include "stage.x"
#include "meta-group/meta-group.x"
#include "meta-helper-client.x"
#include "meta-native/meta-native.x"
#include "meta-sdk/meta-sdk.x"
#include "meta.x"
#include "parse/parse.x"
#include "regions/regions.x"
#include "statements.x"
#include "digest.x"
#include "utils.x"
#include "toolchain.x"
#include <dlfcn.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "expressions-reports.x"

module {
  "diagnostics.x",
  "definitions/definitions.x",
  "expansion.x",
  "rewrites.x",
  "invocations/invocations.x",
  "templates.x",
  "values.x",
  "aliases.x",
}
