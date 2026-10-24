/*  regions.x -- values that can outlive the region that allocated them

    Copyright (c) 2026 Gary William Flake.

    A region is an `auto` block, a `Scope.retain` and `Scope.release`
    pair, a `auto(&slot)` push, a `Pool.open` bracket, an initializer `auto`
    local, a Scope local that `Scope.destroy` ends, or the function's own
    storage, which an address taken with `&` borrows. The pass reads the
    typed forms the parser produced, before the transform driver rewrites
    them, so a region is still the call that opens it and the `defer` beside
    it that closes it. It warns when a value born in a region reaches storage
    that outlives the region and when a local is read after it was freed.

    A function's summary is two facts: which owner supplies fresh returned
    storage, and where each parameter is sunk. The unit's functions reach a
    fixpoint over their summaries. A call into another unit has a summary
    only through the runtime table, so warnings do not depend on which units
    were translated before it. A `meta` function is walked when it is
    defined, against the summaries of the `meta` functions before it, and a
    finding there is an error, because a compile-time call frees its locals
    when it returns.

    The warnings name departures from the lexical pattern. Raw C stores,
    pointer arithmetic, callbacks, and storage the runtime did not allocate
    stay outside them.
*/

#pragma once
#include "compiler/compiler.x"

#include "meta.x"
#include "grammar.x"

#include "ast.x"
#include "stage.x"
#include "type.x"

// walk state

/* Aliases share a stable value's scheduled cleanup, independently of the
   allocator that owns it. Mutable defer targets keep binding-local facts. */
module typedef struct Acquired {
  struct Region *cleanup;
} *Acquired;

/* An open or closed region. `kind` is scope, pool, slot, auto, local: the
   storage of a Scope local whose end has not been seen, or frame: the
   storage of the function's locals and parameters. `depth` is the
   block depth it belongs to, `origin` the statement that opened it, `slot`
   the Scope local a pushed slot names, and `outer` the next open region.
   A Scope's storage also ends when its acquired handle is cleaned. */
module typedef struct Region {
  Symbol kind;
  int depth, origin, closed;
  struct Fact *slot;
  struct Region *outer;
  Acquired acquired;
} *Region;

/* What the walk knows about one local or parameter: the block depth that
   declares it, its parameter index or -1, whether it holds storage born in
   this function, whether a free or a realloc ended it (`ending` while the
   expression that ends it is walked), the region its value belongs to
   (and the Pool alternative of a mixed result), the region a Scope local's
   own storage forms, and for a pointer taken
   with `&`, the local and place it names. `born` records a scoped or pooled
   result, including when the allocation has no local region. `constant`
   marks a stable cleanup target; `empty` distinguishes a NULL handle from
   the value its slot may later acquire. */
module typedef struct Fact {
  int depth, origin, param, born, constant, empty;
  Symbol dead, ending;
  struct Region *region, *other, *owner;
  struct Fact *points;
  List place;
  Acquired acquired;
} *Fact;

/* The walk state for one unit. `facts` maps a binding to its Fact, `open`
   is the innermost open region, `frame` is the region of the function's
   own storage, and `restored` holds the places a `$let` or another `defer`
   puts back before its block ends. `fresh` and `sinks` accumulate the
   current function's summary, `warnings` holds the current walk's, and
   `pending` and `freed` are the expression walk's stacks. `readers` maps a
   function name to the positions of the functions whose walks read its
   summary, `stale` marks the positions to walk again, and `current` is the
   position being walked. `meta` is set while a `meta` definition is
   walked. */
module typedef struct Walk {
  Compiler c;
  Map summaries, facts, sinks, restored, effects, readers;
  Array warnings, pending, freed, stale;
  Region open, frame;
  String function;
  int depth, origin, fresh, changed, meta, audit, current;
} Walk;

module {
  "runtime.x",
  "values.x",
  "flows.x",
  "walk.x",
  "analysis.x",
}
