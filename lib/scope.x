/*  scope.x -- memory allocation scope management

    Copyright (c) 2025 Gary William Flake

    A `Scope` owns a group of individually managed allocations. Callers use
    the active scope, target an explicit scope slot, or retain and release a
    nested lifetime. Any block can still be freed, resized, or relinked onto
    another scope without copying.

    Public operations initialize the module on first use, so they are safe
    before the runtime calls `Scope.initialize`. Shutdown runs its hooks
    newest first and leaves the module terminal; `Scope.stats` still reports
    the final counts.
*/

#pragma once
#include "error-macros.x"
#include <stddef.h>
#include <stdatomic.h>

#include "common.x"

/** Intrusive header stored immediately before each `Scope`-owned allocation.
    Its links are allocator-managed; callers must not construct or mutate it.
*/
typedef struct ScopeAlloc {
  struct ScopeAlloc *prev, *next;
} *ScopeAlloc;

/** Handle for a region and any retained regions linked below it.
    The layout is public; only `Scope` operations create or mutate valid
    allocation and region links.
*/
typedef struct Scope {
  ScopeAlloc first;
  struct Scope *down, *up;
} *Scope;

/** Value snapshot of process-wide `Scope` allocation and lifetime counters.
    It owns no storage; live object and scope counts are derived when the
    snapshot is taken.
    Live and peak requested bytes count public payload only, excluding Scope
    metadata, native allocator overhead, and Pool's direct small-object blocks.
*/
typedef struct ScopeStats {
  size_t allocation_calls, reallocation_calls, free_calls, live_allocations;
  size_t scope_creations, scope_destructions, live_scopes, requested_bytes;
  size_t largest_request, live_requested_bytes, peak_live_requested_bytes;
} ScopeStats;

#include <stdlib.h>
protocol Cleanup(Scope);

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>



static typedef struct ScopeRetain {
  Scope scope, *slot;
} ScopeRetain;


static typedef struct ScopeThreadState {
  Scope root, *active, **stack, int stack_size, stack_capacity;
  ScopeRetain *retains;
  int retain_count, retain_capacity;
} *ScopeThreadState;

static atomic_size_t scope_creations, scope_destructions;


// backing storage

static atomic_size_t raw_alloc_count, raw_free_count;

module {
  "scope/allocation.x",
  "scope/regions.x",
  "scope/accounting.x",
  "scope/runtime.x",
}
