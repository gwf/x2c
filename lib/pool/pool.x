/*  pool.x -- nested interning pools with region-backed object storage

    Copyright (c) 2026 Gary William Flake

    Pool owns canonical identity for a stack of nested levels. Lookup walks
    outward and a miss lands in the innermost level; release returns empty
    blocks to one process-wide depot and moves promoted survivors to the
    parent at the same address. Threads start at one shared process root and
    may open their own child levels. `String` and `List` lookup follows the
    active thread's chain of child and ancestor levels.
*/

#pragma once

#include "error-macros.x"
#include "private-keywords.x"

#include <stddef.h>
#include "common.x"
#include "scope/scope.x"
#include "var/var.x"

/** Maps each canonical value of one `Pool` level to itself.
    A bucket stores the value once, beside its 32-bit hash, so the table costs
    12 bytes per bucket where a `Map` costs 20. It belongs to the level's
    `Scope`.
*/
typedef struct PoolTable {
  Scope scope, Bytes hashes, entries;
  unsigned used, capacity, mask;
} *PoolTable;

/** Holds one level of canonical values and their backing storage.
    Pools are released from child to parent. Their handles and unpromoted
    allocations become invalid at release; promoted identities retain their
    pointers under the parent.
*/
typedef struct Pool {
  Scope scope, PoolTable table, struct Pool *up, pthread_mutex_t mutex;
  unsigned child_capacity;  // last released direct child's table capacity
  size_t interned, promoted, void *blocks, *current[10], *promotions;
} *Pool;

/** Reports one pool level's activity and process-wide storage counters.
    Allocation/free calls, requested bytes, and slot reuse require
    `X2C_SCOPE_ACCOUNTING=1` at startup and are zero otherwise. Block and
    backing-storage metrics remain available. The snapshot owns no storage;
    `requested_bytes` saturates at `SIZE_MAX`.
*/
typedef struct PoolStats {
  int depth, size_t interned, promoted, allocation_calls, free_calls;
  size_t requested_bytes, block_allocations, block_reuses, slot_reuses;
  size_t backing_bytes, active_blocks, active_bytes, depot_blocks, depot_bytes;
} PoolStats;

#include <stdint.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "block.x"
#include "exception.x"
#include "mutex.x"
#include "map/map.x"

module unsigned long value_epoch;

/* A process that has never started a worker cannot contend for a pool, and
   the compiler is such a process: locking added a seventh to translation
   time for nothing. `Thread.start_raw` sets this before `pthread_create`, so
   the worker sees it and every lock taken afterwards is real. It never clears,
   because a value interned while it was clear was published without one. */
module int pool_multithreaded;

String x2c_pool_lookup_string(
  Pool inner, const char *bytes, int length, unsigned hash);

module {
  "interning.x",
  "storage.x",
  "threads.x",
}
