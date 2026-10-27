/*  emit.x -- C tokens from normalized x2c ASTs

    This module owns emission: it turns a bound, typed, transform-normalized
    AST into the token `Array` that formatting prints as C. One stack-local
    Emitter holds the current function's name, static objects, and native
    aliases, so emission is reentrant and a failed translation cannot
    contaminate later units. `transform.x` has already placed each cleanup
    region's statements on the exits that leave it.
*/

#pragma once
#include "compiler/compiler.x"
#include <stdlib.h>
#include <stdio.h>
#include "string/string.x"
#include "var/var.x"
#include "ast.x"
#include "format.x"
#include "cleanup/cleanup.x"

// emission

/* `native_macros` holds the `#define` rows initializer choices need, and
   `static_support` records that a runtime static was emitted, so the unit
   includes its runtime headers. `out` holds the tokens written so far, and
   `held` the nodes that rendering placed code keeps as nodes. */
module typedef struct Emitter {
  delegate Compiler c;
  int origin, String fn_name, List native_aliases;
  Array native_macros;
  Map static_objects, cache_bindings;
  int static_support;
  Array out;
  Map held;
} Emitter;

// operator grouping

/* Canonical AST nesting already states how operators group, but C text
   regroups by precedence, so emission is the one place that restores the
   nesting with parentheses. Every producer therefore builds operator nodes by
   structure alone and none of them tracks grouping.

   Larger levels bind more tightly, matching the C grammar: member access with
   postfix, then unary and cast, the binary levels above the conditional,
   the conditional, and assignment. Level 0 means the emitter has no
   grouping rule for the operator, which leaves its text exactly as the
   other cases build it. */
static enum {
  EMIT_ASSIGNMENT  = 2,
  EMIT_CONDITIONAL = 3,
  EMIT_UNARY       = 14,
  EMIT_POSTFIX     = 15,
  EMIT_PRIMARY     = 16
};

module {
  "dispatch.x",
  "initialization.x",
  "expressions.x",
  "declarations.x",
}
