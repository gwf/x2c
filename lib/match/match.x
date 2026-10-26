/*  match.x -- pattern matching and transformation utilities for lists

    Copyright (c) 2025 Gary William Flake

    Match owns the pattern vocabulary, capture layouts, and the execution of
    plans that `plan.x` prepares and `cache.x` retains. Core
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
#include "scan.x"

/** Owns an exact-sized immutable frozen wordcode program.

    One allocation holds this header followed by aligned code, constant, and
    binder sections. The copied Var and Atom bits do not own their pointees.
    The program contains no execution state and never changes after freeze.
*/
class MachineProgram struct {
  int length, const_count, binder_count, root;
} *;

module {
  "wordcode.x",
  "types.x",
  "machine.x",
  "plan.x",
  "cache.x",
  "layout.x",
  "execution.x",
  "templates.x",
  "traversal.x",
  "sites.x",
  "operations.x",
}
