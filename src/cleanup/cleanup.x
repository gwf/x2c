/*  cleanup.x -- cleanup regions and the transfers that leave them

    Copyright (c) 2026 Gary William Flake.

    A cleanup region is a `defer` body, a region of a landing form such as
    a `try` body or catch arm, or the rest of a block after a static local
    whose initializer runs at runtime. Normalization turns each `defer`
    statement into a region. When a function is complete, each `try` takes
    the landing form its component returns, and one walk places each
    region's exits on every transfer that leaves it, rejects a jump into a
    region, and keeps the locals a `sigsetjmp` landing reads either
    `volatile` or escaped.
*/

#pragma once
#include "compiler/compiler.x"

#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

#include "ast.x"
#include "type.x"
#include "parse/parse.x"
#include "callables/callables.x"

/* The locals of one function that a transfer may leave stale: the names to
   qualify `volatile`, the pointers written through and those whose pointee
   needs the qualifier too, and the locals whose address escapes instead. */
module typedef struct Preserve {
  Compiler c;
  Map names, holders, pointers, escaped;
  int expression_landings;
} Preserve;

module {
  "transfers.x",
  "statics.x",
  "preservation.x",
  "defer.x",
}
