/*  scope.x -- memory allocation scope management

    Copyright (c) 2025 Gary William Flake

    A `Scope` owns a group of individually managed allocations. Callers use
    the active scope, target an explicit scope slot, or retain and release a
    nested lifetime. Any block can still be freed, resized, or relinked onto
    another scope without copying.

    Public operations initialize the module on first use, so they are safe
    before the runtime calls `Scope.initialize`. Shutdown runs its hooks
    newest first and leaves the module terminal. Allocation accounting is
    enabled at initialization by `X2C_SCOPE_ACCOUNTING=1`; otherwise counters
    and automatic leak reporting are disabled.
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
    allocation and region links. Callers provide exclusive access to those
    links, including ownership parents, during allocation and lifetime changes.
*/
typedef struct Scope {
  ScopeAlloc first;
  struct Scope *down, *up;
  struct Scope *parent, *children, *previous, *next;
} *Scope;

/** Value snapshot of process-wide `Scope` allocation and lifetime counters.
    It owns no storage; live object and scope counts are derived when the
    snapshot is taken. Every field is zero when accounting is disabled.
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

/* scope records

   Each thread owns its root scope, the slot that allocation charges, the
   stack of pushed slots, and one record per open retain. Named scopes share
   one process-wide registry. */

module typedef struct ScopeRetain {
  Scope scope, *slot;
} ScopeRetain;

module typedef struct ScopeName {
  Scope scope, char *name, struct ScopeName *next;
} *ScopeName;

/* Valid handles point to this first member. The immutable name membership
   stays private, leaving the public Scope layout unchanged. */
module typedef struct ScopeRecord {
  struct Scope scope;
  ScopeName name;
} *ScopeRecord;

module typedef struct ScopeThreadState {
  Scope root, *active, **stack, int stack_size, stack_capacity;
  ScopeRetain *retains;
  int retain_count, retain_capacity;
} *ScopeThreadState;

module int scope_accounting;
module atomic_size_t scope_creations, scope_destructions;

// backing storage

module atomic_size_t raw_alloc_count, raw_free_count;

#include <pthread.h>

module {
  "allocation.x",
  "regions.x",
  "accounting.x",
  "runtime.x",
}

// C-style allocation names

/** Allocates uninitialized bytes in the active scope through `Scope.malloc`.
    The signature, ownership, zero-size behavior, and raised errors are the
    same. Release the result with `xfree` or let its scope reclaim it.
    See: Scope.malloc
*/
$x2c.foreign.alias(Scope.malloc)
meta native void *xmalloc(size_t size);

/** Allocates zeroed objects in the active scope through `Scope.calloc`.
    The count overflow check, zero-size behavior, and raised errors are the
    same. Release the result with `xfree` or let its scope reclaim it.
    See: Scope.calloc
*/
$x2c.foreign.alias(Scope.calloc)
meta native void *xcalloc(size_t count, size_t size);

/** Resizes scope-owned memory through `Scope.realloc`, preserving its owner.
    A NULL pointer allocates in the active scope, including for size zero.
    A nonnull pointer with size zero is freed and returns NULL.
    The signature and raised errors are the same as `Scope.realloc`.
    See: Scope.realloc
*/
$x2c.foreign.alias(Scope.realloc)
meta native void *xrealloc(void *ptr, size_t size);

/** Frees scope-owned memory through `Scope.free`; NULL does nothing.
    Native allocations, including buffers from `getline`, require native
    `free`. Passing them to `xfree` is undefined behavior.
    See: Scope.free
*/
$x2c.foreign.alias(Scope.free)
meta native void xfree(void *ptr);

/** Copies bytes into the active scope through `Scope.memdup`.
    A NULL source or zero size returns NULL without allocating. Copy a
    string's terminator too. The signature and raised errors are unchanged.
    See: Scope.memdup
*/
$x2c.foreign.alias(Scope.memdup)
meta native void *xmemdup(const void *ptr, size_t size);
