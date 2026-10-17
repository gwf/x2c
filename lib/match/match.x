/*  match.x -- pattern matching and transformation utilities for lists

    Copyright (c) 2025 Gary William Flake

    Match owns the pattern vocabulary, capture layouts, and the execution of
    plans that `match-plan.x` prepares and `match-cache.x` retains. Core
    matching runs only prepared plans; `unittest/match-recursive.x` is the
    reference matcher of the differential tests. An invocation commits
    captures to caller-owned storage only after the whole match succeeds.

    Association-List results are published from committed captures. New
    Lists canonicalize through the active pool chain; a result may belong to
    an ancestor and lives until its owning pool is released.
 */

#pragma once

#include "error-macros.x"
#include "common.x"
#include "machine.x"

/** Describes the canonical binder slots and preparation status of a pattern.
    `binders` points into the layout allocation and lists each distinct named
    binder in lexical preorder. `definite` and `possible` select those slots.
    `normalized` and the binder `Atom`s are borrowed canonical values. The
    caller owns the layout returned by `MatchCaptureLayout.analyze` and must
    free it before those values or its allocating `Scope` expire.
*/
typedef struct MatchCaptureLayout {
  Atom *binders;
  Var normalized;
  unsigned long definite, possible;
  int binder_count, Symbol status, const char *reason;
} *MatchCaptureLayout;

/** Supplies caller-owned positional storage for one `Match` invocation.
    `values` has `capacity` elements. On success `present` identifies the
    elements `Match` wrote; presence is separate from a captured `void` value.
    A miss or error leaves `values` and `present` unchanged. Captured values
    are borrowed and keep their ordinary `Var`, `List`, and pool lifetimes.
*/
typedef struct MatchCaptureBuffer {
  Var *values;
  unsigned long present;
  int capacity;
} MatchCaptureBuffer;

/** Describes one way an input a plan matches can begin: its first element
    equals `head` and, when `index` is nonzero, its element at `index`
    equals `inner`, or is a List whose first element does when `nested` is
    set. Both values are borrowed pattern constants.
*/
typedef struct MatchKey {
  Var head, inner;
  int index, nested;
} MatchKey;

enum { MATCH_KEY_MAX = 8 };

/** Holds one reusable immutable compiled `Match` pattern.
    A prepared plan owns `program` and `layout`; malformed and ineligible plans
    have no executable program and retain their categorized `status` and
    static `reason`. A prepared plan whose pattern fixes how a matching input
    begins lists the `keys` it may begin with; `key_bits` says that raw bits
    compare them. Pattern constants are borrowed, so the caller must free
    the plan before their canonical pools or other owners expire.
*/
typedef struct MatchPlan {
  MachineProgram program;
  MatchCaptureLayout layout;
  Symbol status, const char *reason;
  int key_count, key_bits;
  MatchKey keys[MATCH_KEY_MAX];
} *MatchPlan;

/** Stores the process-lifetime plan for one compiler-emitted `Match` site.
    The object must be zero-initialized static storage. Its first admissible
    pattern binds it permanently; `Match` shutdown frees the plan and clears
    the site. Direct callers must not reuse a site for another pattern.
*/
typedef struct MatchCaptureSite {
  MatchPlan plan;
  int refused;
} MatchCaptureSite;

#include <pthread.h>
#include <stdlib.h>
#include <stddef.h>
#include <assert.h>
#include "var/var.x"
#include "list/list.x"
#include "atom.x"
#include "exception.x"
#include "symbol.x"
#include "scope/scope.x"
#include "block.x"
#include "match-machine.x"
#include "match-plan.x"
#include "match-cache.x"
#include "scan.x"

module {
  "layout.x",
  "execution.x",
  "templates.x",
  "traversal.x",
  "sites.x",
  "operations.x",
}
