/*  list.x -- linked list with `Var` elements

    Copyright (c) 2025 Gary William Flake

    List owns canonical immutable cons chains. A car holds any non-void Var
    and a cdr is nil or another List; identity is the car's exact bits plus
    the canonical tail, so mutating an Array or Map stored in a car leaves the
    identity of its cell unchanged.

    Construction searches the requested pool and its ancestors: an existing
    cell keeps its ancestor's lifetime, and a miss belongs to the requested
    pool. Releasing a nested pool invalidates its unpromoted cells, while
    promotion keeps whole canonical List, String, and long-Atom structure at
    the same addresses. `void` is a terminal sentinel and never List data.
*/

#pragma once

#include "error-macros.x"
#include "common.x"
#include "var/var.x"

/** Names an immutable canonical cons cell, or `nil` as NULL.
    A nonnull cell is borrowed from the pool that owns its exact car and tail
    identity; callers neither mutate nor free it. The car is never `void`, and
    the tail is `nil` or another live canonical `List`.
*/
typedef struct List {
  Var car;
  struct List *cdr;
} *List;

/* Builds a canonical cell in the given pool without changing the process-wide
   active List pool. Error uses this to keep diagnostic values out of
   application pool brackets. */
/** Returns the canonical cell for `head` and `tail` in `pool`'s chain.
    An ancestor hit keeps that ancestor's ownership; a miss is owned by `pool`.
    A null pool or `void` head returns `nil` without allocating. Any
    pool-managed graph reachable through `head` or `tail` is borrowed and must
    remain live for at least as long as the result.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while installing a
    new cell.
*/
List List.cons_in(Pool pool, Var head, List tail) {
  if (!pool || head is void) return NULL;
  /* Compiler construction is canonical-hit-heavy. One stack-query probe of
     the whole chain answers a hit without allocating and leaves the miss
     path the innermost insert alone. */
  struct List query = { head, tail };
  Var existing = pool.lookup((List) &query);
  if (existing is not void) return existing;
  List cell = pool.malloc(sizeof(struct List));
  cell.car = head;
  cell.cdr = tail;
  return pool.intern_new(cell, cell);
}

#include "symbol.x"
#include "atom.x"
#include "block.x"
#include "buffer.x"
#include "exception.x"
#include "func/func.x"
#include "map/map.x"
#include "scope/scope.x"
#include "pool/pool.x"
#include "string/string.x"
#include "iter.x"
#include "array/array.x"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <limits.h>

module {
  "cells.x",
  "traversal.x",
  "building.x",
  "transformations.x",
  "rendering.x",
}
