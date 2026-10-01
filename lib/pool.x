/*  pool.x -- nested interning pools with region-backed object storage

    Copyright (c) 2026 Gary William Flake

    Pool owns canonical identity for a stack of nested levels. Lookup walks
    outward and a miss lands in the innermost level; release returns empty
    blocks to one process-wide depot and moves promoted survivors to the
    parent at the same address. Levels have no sibling branches, so the
    active chain holds one canonical pointer per equal value. `String` and
    `List` intern into one such stack per thread.
*/

#pragma once

$(import "error-macros.xmacro")
$(import "private-keywords.xmacro")

#include <stddef.h>
#include "common.x"
#include "scope.x"
#include "var.x"
#include "map.x"

/** Holds one level of canonical values and their backing storage.
    Pools are released from child to parent. Their handles and unpromoted
    allocations become invalid at release; promoted identities retain their
    pointers under the parent.
*/
typedef struct Pool {
  Scope scope, Map table, struct Pool *up, pthread_mutex_t mutex;
  unsigned child_capacity;  // last released direct child's table capacity
  size_t interned, promoted, void *blocks, *current[10], *promotions;
} *Pool;

/** Reports one pool level's activity and process-wide storage counters.
    The snapshot owns no storage; `requested_bytes` saturates at `SIZE_MAX`.
*/
typedef struct PoolStats {
  int depth, size_t interned, promoted, allocation_calls, free_calls;
  size_t requested_bytes, block_allocations, block_reuses, slot_reuses;
  size_t backing_bytes, active_blocks, active_bytes, depot_blocks, depot_bytes;
} PoolStats;

#pragma private

#include <stdint.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exception.x"
#include "mutex.x"

/* storage

   A request through 512 bytes takes a slot of the smallest size class that
   holds it. A block carries the slots of one class after a 64-byte header,
   and a released block waits in the depot for its next lease. */

enum PoolStorageConstant {
  POOL_CLASS_COUNT = 10,
  POOL_DEPOT_COUNT = 5,
  POOL_KEEP_WORDS = 1
};

typedef struct PoolBlock {
  struct PoolBlock *next, *registry_next, struct Pool *owner, void *free;
  size_t used, unsigned class_index, keep_count, bytes;
  uint64_t keep[POOL_KEEP_WORDS];
} *PoolBlock;

typedef struct PoolPromotion {
  PoolBlock block, unsigned slot, struct PoolPromotion *next;
} *PoolPromotion;

enum PoolBlockConstant {
  POOL_BLOCK_DATA_OFFSET = 64
};

_Static_assert(
  sizeof(struct PoolBlock) == 64, "the pool block header is 64 bytes");

static const unsigned pool_class_sizes[POOL_CLASS_COUNT] = {
  16, 32, 48, 64, 96, 128, 192, 256, 384, 512
};

static const unsigned pool_block_sizes[POOL_CLASS_COUNT] = {
  512, 1024, 2048, 2048, 4096, 4096, 4096, 4096, 4096, 4096
};

/* Blocks are found from an interior pointer often enough that walking the
   registry dominates translation, so the registry also carries an index from
   the page a block occupies to the block. A block never moves and is freed
   only at shutdown, so entries are placed once and never removed; a block
   sitting in the depot is rejected by its null owner. */
typedef struct PoolIndexSlot {
  uintptr_t page;
  PoolBlock block;
} PoolIndexSlot;

enum PoolIndexConstant {
  POOL_INDEX_PAGE_SHIFT = 12,
  POOL_INDEX_FIRST_SLOTS = 256
};

static PoolBlock pool_registry;
static PoolIndexSlot *pool_index;
static unsigned pool_index_slots, pool_index_used;
/* The index answers a miss authoritatively only while it holds every
   registered block. A table that cannot grow loses that permanently. */
static int pool_index_complete = 1;
static PoolBlock pool_depot[POOL_DEPOT_COUNT];
static int pool_storage_ready;
static size_t pool_allocation_calls, pool_free_calls, pool_requested_bytes;
static size_t pool_block_allocations, pool_block_reuses;
static size_t pool_slot_reuses, pool_backing_bytes;
static size_t pool_active_blocks, pool_active_bytes;
static size_t pool_depot_blocks, pool_depot_bytes;
static pthread_mutex_t pool_storage_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

// process state

typedef struct PoolValueThreadState {
  Pool current;
} *PoolValueThreadState;

static Pool value_root;
static unsigned long value_epoch;
static threaded struct PoolValueThreadState value_thread;

/* A process that has never started a worker cannot contend for a pool, and
   the compiler is such a process: locking added a seventh to translation
   time for nothing. `Thread.start` sets this before `pthread_create`, so the
   worker sees it and every lock taken afterwards is real. It never clears,
   because a value interned while it was clear was published without one. */
static int pool_multithreaded;

// interning

/** Returns the first value equal to `key` from `inner` outward, or `void`.
    The returned identity remains owned by the level where it was found.
*/
Var Pool.lookup(Pool inner, Var key) {
  /* Every level probes the same key, so it is hashed once here for the whole
     chain. An empty chain probes nothing and hashes nothing, so a void key
     raises only when a level is probed. */
  if (!inner) return void;
  unsigned key_hash = key.hash();
  /* `Map.get_hashed` raises for any cause from custom equality, so the
     branch mutex is released through one hoisted `defer`. A per-iteration
     `defer` measured 4% of a translation against 3% for this form. `locked`
     is the level whose mutex this call still holds. */
  Pool locked = NULL;
  defer locked._unlock();
  for (Pool pool = inner; pool; pool = pool.up) {
    pool._lock();
    locked = pool;
    Var found = pool.table.get_hashed(key, key_hash);
    pool._unlock();
    locked = NULL;
    if (found is not void) return found;
  }
  return void;
}

/** Returns the canonical value equal to `object`, installing it when absent.
    A miss lands in `inner`. `alloc` is the object's `Pool`-owned allocation;
    a hit releases that losing candidate immediately. A failed insertion
    leaves the candidate owned by the caller so its existing cleanup boundary
    runs.

    Ancestors are checked before the innermost fused `Map` operation. `Pool`'s
    single-canonical-pointer invariant makes that order equivalent to outward
    shadowing while allowing the innermost table to be probed exactly once.
    A caller that has already searched the chain uses `Pool.intern_new`.

    Raises: `<bad-arg>` when `inner` or `alloc` is NULL. `Map` lookup and
    insertion causes propagate.
*/
Var Pool.intern(Pool inner, Var object, void *alloc) {
  if (!inner || !alloc) raise %(bad-arg (owner "Pool.intern"));
  Var canonical;
  int discard = 0;
  {
    inner._lock();
    defer inner._unlock();
    Var existing = Pool.lookup(inner.up, object);
    if (existing is not void) {
      canonical = existing;
      discard = 1;
    }
    else canonical = inner._intern_locked(object, discard);
  }
  // See Pool.intern_new: the losing candidate is freed outside the lock.
  if (discard) inner.free(alloc);
  return canonical;
}

/* Probes and installs in `inner` alone, with the pool locked. Sets `discard`
   when a concurrent equal entry already holds the level. */
static Var Pool._intern_locked(Pool inner, Var object, int &discard) {
  unsigned before = inner.table.len();
  Var stored = inner.table.setdefault(object, object);
  if (inner.table.len() != before) inner.interned++;
  else discard = 1;
  return stored;
}

/** Returns the canonical value equal to `object`, installing it in `inner`.
    This is `Pool.intern` for a caller that has already searched the whole
    chain from `inner` outward and found nothing, so only the innermost level
    is probed. The fused `Map` operation still decides the identity, which
    keeps one canonical pointer per equal value in `inner` even when another
    worker interns the same value first.

    Raises: `<bad-arg>` when `inner` or `alloc` is NULL. `Map` insertion
    causes propagate and leave the object unregistered.
*/
Var Pool.intern_new(Pool inner, Var object, void *alloc) {
  if (!inner || !alloc) raise %(bad-arg (owner "Pool.intern_new"));
  Var canonical;
  int discard = 0;
  {
    inner._lock();
    defer inner._unlock();
    canonical = inner._intern_locked(object, discard);
  }
  // Pool.free takes storage before the pool. Do not call it while holding
  // the pool mutex or another worker can complete the opposite lock order.
  if (discard) inner.free(alloc);
  return canonical;
}

/** Installs `object` as its own canonical value in exactly `inner`.
    The caller must have ruled out an equal identity in this pool chain; this
    primitive neither searches ancestors nor takes ownership of separate
    object storage.
    Raises: `<bad-arg>` when `inner` is NULL. Map insertion causes propagate
    and leave the object unregistered.
*/
void Pool.insert(Pool inner, Var object) {
  if (!inner) raise %(bad-arg (owner "Pool.insert"));
  inner._lock();
  defer inner._unlock();
  inner._insert_locked(object);
}

/* Map insertion causes propagate and leave the object unregistered. */
static void Pool._insert_locked(Pool inner, Var object) {
  inner.table.setindex(object, object);
  inner.interned++;
}

/** Reports whether this exact level stores `key` as its canonical identity.
    Ancestors are not searched, and a null pool reports zero.
*/
int Pool.owns(Pool pool, Var key) {
  if (!pool) return 0;
  pool._lock();
  defer pool._unlock();
  return pool._owns_locked(key);
}

static int Pool._owns_locked(Pool pool, Var key) {
  Var found = pool.table[key];
  return found is not void && found === key;
}

// allocation

/** Allocates object storage owned by `inner`.
    Requests through 512 bytes use a size-class region; larger requests retain
    ordinary `Scope` ownership.

    Raises: `<bad-arg>` when `inner` is NULL, `<size-limit>` when a large
    request overflows `Scope` storage, or `<alloc-fail>` when storage cannot
    be allocated.
*/
void *Pool.malloc(Pool inner, size_t size) {
  if (!inner) raise %(bad-arg (owner "Pool.malloc"));
  int class_index = _size_class(size);
  if (class_index >= 0) return inner._small_malloc(class_index, size);
  _storage_lock();
  _record_request(size);
  _storage_unlock();
  inner._lock();
  defer inner._unlock();
  return Scope.malloc_in(&inner.scope, size);
}

/* Takes a slot from the class's current block, leasing another block when
   that one is full. When the depot has no block to lease, a fresh one is
   allocated with no lock held and offered to the next attempt. */
static void *Pool._small_malloc(Pool inner, int class_index, size_t size) {
  PoolBlock fresh = NULL;
  loop {
    _storage_lock();
    inner._lock();
    PoolBlock block = inner._block_with_room(class_index);
    if (!block) block = inner._block_lease(class_index, fresh);
    if (block) {
      if (block == fresh) fresh = NULL;
      void *slot = block._take_slot(class_index);
      _record_request(size);
      inner._unlock();
      _storage_unlock();
      free(fresh);
      return slot;
    }
    inner._unlock();
    _storage_unlock();
    fresh = inner._fresh_block(class_index);
  }
}

static int _size_class(size_t size) {
  for (int i = 0; i < POOL_CLASS_COUNT; i++)
    if (size <= pool_class_sizes[i]) return i;
  return -1;
}

static PoolBlock Pool._block_with_room(Pool pool, int class_index) {
  PoolBlock current = pool.current[class_index];
  return current._has_room() ? current : NULL;
}

static int PoolBlock._has_room(PoolBlock block) {
  if (!block) return 0;
  if (block.free) return 1;
  unsigned size = pool_class_sizes[block.class_index];
  return block.used + size <= block.bytes - POOL_BLOCK_DATA_OFFSET;
}

/* Reuses a freed slot, or else hands out the next slot never used. */
static void *PoolBlock._take_slot(PoolBlock block, int class_index) {
  void *slot = block.free;
  if (slot) {
    block.free = *(void **) slot;
    pool_slot_reuses++;
    return slot;
  }
  slot = block._data() + block.used;
  block.used += pool_class_sizes[class_index];
  return slot;
}

/* Allocates with no lock held, so the failure can enter Error without
   reentering the storage mutex. */
static PoolBlock Pool._fresh_block(Pool inner, int class_index) {
  PoolBlock fresh = malloc(inner._block_bytes(class_index));
  if (fresh) return fresh;
  if (x2c_error_runtime_ready)
    raise %(alloc-fail (owner "Pool backing block"));
  _fatal("backing block allocation failed");
}

/** Releases a losing or transient allocation from `inner`'s pool chain.
    Region slots become immediately reusable; large allocations use
    `Scope.free`. A canonical allocation still present in a table must not be
    freed this way. A null allocation does nothing.
    Raises: `<bad-arg>` when `inner` is NULL and `alloc` is not.
*/
void Pool.free(Pool inner, void *alloc) {
  if (!alloc) return;
  if (!inner) raise %(bad-arg (owner "Pool.free"));
  _storage_lock();
  defer _storage_unlock();
  inner._lock();
  defer inner._unlock();
  PoolBlock block = _find_block(alloc);
  pool_free_calls++;
  if (block) block._free_slot(alloc);
  else Scope.free(alloc);
}

/* The freed slot is reused first, from a block that becomes its class's
   current one. */
static void PoolBlock._free_slot(PoolBlock block, void *ptr) {
  block._push_free(ptr);
  block.owner.current[block.class_index] = block;
}

static void PoolBlock._push_free(PoolBlock block, void *slot) {
  *(void **) slot = block.free;
  block.free = slot;
}

// blocks

/* Called with storage and pool locked. `fresh` is a block `Pool._fresh_block`
   allocated for an earlier attempt, or NULL. */
static PoolBlock Pool._block_lease(Pool p, int class_index, PoolBlock fresh) {
  unsigned bytes = p._block_bytes(class_index);
  PoolBlock block = _depot_pop(bytes);
  if (!block) {
    if (!fresh) return NULL;
    block = _registry_add(fresh, bytes);
  }
  pool_active_blocks++;
  pool_active_bytes += bytes;
  block._reset(p);
  block.class_index = class_index;
  block.bytes = bytes;
  block._link(p);
  return block;
}

/* A nested pool's smallest class leases 256-byte blocks. */
static unsigned Pool._block_bytes(Pool pool, int class_index) =>
  class_index == 0 && pool.up ? 256 : pool_block_sizes[class_index];

static PoolBlock _depot_pop(unsigned bytes) {
  int depot_index = _depot_index(bytes);
  PoolBlock block = pool_depot[depot_index];
  if (!block) return NULL;
  pool_depot[depot_index] = block.next;
  pool_depot_blocks--;
  pool_depot_bytes -= bytes;
  pool_block_reuses++;
  return block;
}

static PoolBlock _registry_add(PoolBlock block, unsigned bytes) {
  block.registry_next = pool_registry;
  pool_registry = block;
  _index_add(block, bytes);
  pool_block_allocations++;
  pool_backing_bytes += bytes;
  return block;
}

/* Empties `block` under `owner`: no slot handed out or free, and none kept. */
static void PoolBlock._reset(PoolBlock block, Pool owner) {
  block.owner = owner;
  block.free = NULL;
  block.used = 0;
  block.keep_count = 0;
  memset(block.keep, 0, sizeof block.keep);
}

/* Makes `block` the newest block of `pool` and its class's current one. */
static void PoolBlock._link(PoolBlock block, Pool pool) {
  block.next = pool.blocks;
  pool.blocks = block;
  pool.current[block.class_index] = block;
}

static void _depot_push(PoolBlock block) {
  int depot_index = _depot_index(block.bytes);
  block._reset(NULL);
  block.next = pool_depot[depot_index];
  pool_depot[depot_index] = block;
  pool_active_blocks--;
  pool_active_bytes -= block.bytes;
  pool_depot_blocks++;
  pool_depot_bytes += block.bytes;
}

static int _depot_index(unsigned bytes) {
  switch (bytes) {
    case 256:  return 0;
    case 512:  return 1;
    case 1024: return 2;
    case 2048: return 3;
    default:   return 4;
  }
}

static inline char *PoolBlock._data(PoolBlock block) =>
  (char *) block + POOL_BLOCK_DATA_OFFSET;

static inline void *PoolBlock._slot(PoolBlock block, unsigned slot) =>
  block._data() + slot * pool_class_sizes[block.class_index];

static inline unsigned PoolBlock._slot_index(PoolBlock block, void *alloc) =>
  ((char *) alloc - block._data()) / pool_class_sizes[block.class_index];

static int PoolBlock._contains(PoolBlock block, const void *ptr) {
  if (!block || !ptr || !block.owner) return 0;
  const char *data = block._data(), *candidate = ptr;
  unsigned size = pool_class_sizes[block.class_index];
  if (candidate < data || candidate >= data + block.used) return 0;
  return (size_t) (candidate - data) % size == 0;
}

// block index

/* The registered block holding `ptr`, or NULL. Storage must be locked. */
static PoolBlock _find_block(const void *ptr) =>
  pool_index_complete ? _index_find(ptr) : _registry_find(ptr);

static PoolBlock _index_find(const void *ptr) {
  if (!pool_index_slots) return NULL;
  uintptr_t page = (uintptr_t) ptr >> POOL_INDEX_PAGE_SHIFT;
  unsigned at = _index_start(page, pool_index_slots);
  while (pool_index[at].block) {
    if (pool_index[at].page == page &&
        pool_index[at].block._contains(ptr))
      return pool_index[at].block;
    at = (at + 1) & (pool_index_slots - 1);
  }
  return NULL;
}

static PoolBlock _registry_find(const void *ptr) {
  for (PoolBlock block = pool_registry; block; block = block.registry_next)
    if (block._contains(ptr)) return block;
  return NULL;
}

/* A block spans at most two pages, so it takes at most two slots. Growth is
   the one allocation here and it disables the index instead of failing, which
   keeps `Pool._block_lease` free of a failure path while storage is locked. */
static void _index_add(PoolBlock block, unsigned bytes) {
  if (!pool_index_complete) return;
  uintptr_t first = (uintptr_t) block >> POOL_INDEX_PAGE_SHIFT;
  uintptr_t last = ((uintptr_t) block + bytes - 1) >> POOL_INDEX_PAGE_SHIFT;
  for (uintptr_t page = first; page <= last; page++) {
    if ((pool_index_used + 1) * 2 > pool_index_slots && !_index_grow()) {
      pool_index_complete = 0;
      return;
    }
    _index_place(pool_index, pool_index_slots, page, block);
    pool_index_used++;
  }
}

/* Keeps the table under half full so a lookup always meets a free slot. */
static int _index_grow(void) {
  unsigned slots = pool_index_slots * 2;
  if (!slots) slots = POOL_INDEX_FIRST_SLOTS;
  PoolIndexSlot *table = calloc(slots, sizeof(PoolIndexSlot));
  if (!table) return 0;
  for (unsigned at = 0; at < pool_index_slots; at++)
    if (pool_index[at].block)
      _index_place(table, slots, pool_index[at].page, pool_index[at].block);
  free(pool_index);
  pool_index = table;
  pool_index_slots = slots;
  return 1;
}

static void _index_place(
  PoolIndexSlot *table, unsigned slots, uintptr_t page, PoolBlock block) {
  unsigned at = _index_start(page, slots);
  while (table[at].block) at = (at + 1) & (slots - 1);
  table[at].page = page;
  table[at].block = block;
}

static unsigned _index_start(uintptr_t page, unsigned slots) =>
  (unsigned) ((page * 0x9E3779B97F4A7C15ull) >> 32) & (slots - 1);

/* promotion

   A promoted identity keeps its address: its slot is kept, and release
   moves every block with a kept slot to the parent. A slot whose block
   still belongs to a deeper level is recorded as a PoolPromotion, which
   keeps it again when the promoting level is released. */

/** Publishes an identity owned by `inner` in its parent.
    `alloc` survives `inner`'s release without changing its address. When the
    parent already holds an equal identity, that one stays canonical and
    `object` only survives. Returns zero for a missing owner, root pool, or
    null allocation.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while recording
    the promotion; that transfer may happen before storage is marked or moved.
*/
int Pool.promote(Pool inner, Var object, void *alloc) {
  if (!inner || !inner.up || !alloc) return 0;
  return inner._promote_level(object, alloc, _block_of(alloc));
}

/** Proves `object` safe beyond every pool in `inner`'s chain.
    It is promoted to the outermost pool when a pool in the chain owns it.
    `alloc` is the object's `Pool`-owned allocation. Returns one when the
    value is already outermost or reaches it, and zero when no pool in the
    chain owns it or a promotion fails. A null `inner` reports safe, since no
    pool can then reclaim the value. Promotion is not transactional across
    levels: an earlier level remains promoted if a later promotion transfers.
    A thread that loses a concurrent promotion of an equal value still gets
    one, though `Pool.is_permanent` answers zero for its surviving copy.

    Raises: `<alloc-fail>` when promotion metadata cannot be allocated.
*/
int Pool.own(Pool inner, Var object, void *alloc) {
  if (!inner) return 1;
  Pool owner = inner;
  while (owner && !owner.owns(object)) owner = owner.up;
  if (!owner) return 0;
  if (!owner.up) return 1;
  if (!alloc) return 0;
  PoolBlock block = _block_of(alloc);
  while (owner.up) {
    if (!owner._promote_level(object, alloc, block)) return 0;
    owner = owner.up;
  }
  return 1;
}

/* Moves `object` from `inner` to `inner.up`. `block` is the region block
   backing `alloc`, or NULL when Scope owns it. The caller supplies the block
   because a value promoted through several levels stays in the same one.
   Another thread's pool can promote an equal value first; that identity
   stays canonical, and `object` survives without replacing it. */
static int Pool._promote_level(
  Pool inner, Var object, void *alloc, PoolBlock block) {
  inner._lock();
  defer inner._unlock();
  if (!inner._owns_locked(object)) return 0;
  unsigned slot = block ? block._slot_index(alloc) : 0;
  PoolPromotion promotion = NULL;
  if (block && block.owner != inner) {
    promotion = Scope.malloc_in(&inner.scope, sizeof(struct PoolPromotion));
    promotion.block = block;
    promotion.slot = slot;
  }
  Pool up = inner.up;
  up._lock();
  defer up._unlock();
  unsigned before = up.table.len();
  up.table.setdefault(object, object);
  if (up.table.len() != before) up.interned++;
  if (block && block.owner == inner) block._mark_slot(slot);
  else if (promotion) inner._push_promotion(promotion);
  else Scope.move(alloc, &up.scope);
  inner.promoted++;
  return 1;
}

/* Straight lock and unlock, with no defer: this runs on every promotion and
   nothing between the two calls can raise. */
static PoolBlock _block_of(void *alloc) {
  _storage_lock();
  PoolBlock block = _find_block(alloc);
  _storage_unlock();
  return block;
}

static void PoolBlock._mark_slot(PoolBlock block, unsigned slot) {
  uint64_t mask = (uint64_t) 1 << (slot % 64), *word = &block.keep[slot / 64];
  if (*word & mask) return;
  *word |= mask;
  block.keep_count++;
}

static void Pool._push_promotion(Pool inner, PoolPromotion promotion) {
  promotion.next = inner.promotions;
  inner.promotions = promotion;
}

/* Recorded promotions mark their slots first, so each block's keep count is
   complete before the block moves to the parent or the depot. */
static void Pool._release_blocks(Pool inner) {
  for (PoolPromotion p = inner.promotions; p; p = p.next)
    p.block._mark_slot(p.slot);
  PoolBlock block = inner.blocks;
  while (block) {
    PoolBlock next = block.next;
    if (inner.up && block.keep_count) block._transfer(inner.up);
    else _depot_push(block);
    block = next;
  }
  inner.blocks = NULL;
  for (int i = 0; i < POOL_CLASS_COUNT; i++) inner.current[i] = NULL;
}

static void PoolBlock._transfer(PoolBlock block, Pool parent) {
  block._free_unkept();
  block.owner = parent;
  block.keep_count = 0;
  memset(block.keep, 0, sizeof block.keep);
  block._link(parent);
}

/* Rebuilds the free list from the handed-out slots that are not kept,
   lowest slot first. */
static void PoolBlock._free_unkept(PoolBlock block) {
  unsigned count = block.used / pool_class_sizes[block.class_index];
  block.free = NULL;
  for (unsigned slot = count; slot-- > 0;)
    if (!block._slot_kept(slot)) block._push_free(block._slot(slot));
}

static int PoolBlock._slot_kept(PoolBlock block, unsigned slot) {
  uint64_t mask = (uint64_t) 1 << (slot % 64);
  return (block.keep[slot / 64] & mask) != 0;
}

/* locks

   Operations needing both locks take storage first, then child, then
   parent. No potentially failing allocation runs while storage is locked. */

/** Makes `Pool` lock from here on, for a process about to start a worker.
    `Thread.start` calls this before `pthread_create`. It never clears.
*/
void Pool.thread_start(void) {
  pool_multithreaded = 1;
}

static void _storage_lock(void) {
  if (pool_multithreaded && pthread_mutex_lock(&pool_storage_mutex))
    _fatal("could not lock storage mutex");
}

static void _storage_unlock(void) {
  if (pool_multithreaded && pthread_mutex_unlock(&pool_storage_mutex))
    _fatal("could not unlock storage mutex");
}

static void Pool._lock(Pool pool) {
  if (pool_multithreaded && pool && pthread_mutex_lock(&pool.mutex))
    _fatal("could not lock branch mutex");
}

static void Pool._unlock(Pool pool) {
  if (pool_multithreaded && pool && pthread_mutex_unlock(&pool.mutex))
    _fatal("could not unlock branch mutex");
}

/* Ends the process on a native failure that Error cannot report. */
static void _fatal(const char *message) {
  fprintf(stderr, "Pool: %s\n", message);
  abort();
}

// statistics

/* Accounts for one satisfied request. The caller holds the storage lock, so
   the small-class path takes no lock of its own. */
static void _record_request(size_t size) {
  pool_allocation_calls++;
  if (SIZE_MAX - pool_requested_bytes < size) pool_requested_bytes = SIZE_MAX;
  else pool_requested_bytes += size;
}

/** Returns this level's canonical counts plus process-wide storage counters.
    A null pool reports depth and per-level counts as zero. The counters are a
    snapshot; nothing in the result stays live with the pool.
*/
PoolStats Pool.stats(Pool inner) {
  _storage_lock();
  defer _storage_unlock();
  inner._lock();
  defer inner._unlock();
  PoolStats stats = {
    .allocation_calls = pool_allocation_calls,
    .free_calls = pool_free_calls, .requested_bytes = pool_requested_bytes,
    .block_allocations = pool_block_allocations,
    .block_reuses = pool_block_reuses, .slot_reuses = pool_slot_reuses,
    .backing_bytes = pool_backing_bytes,
    .active_blocks = pool_active_blocks, .active_bytes = pool_active_bytes,
    .depot_blocks = pool_depot_blocks, .depot_bytes = pool_depot_bytes};
  for (Pool pool = inner; pool; pool = pool.up) stats.depth++;
  if (inner) {
    stats.interned = inner.interned;
    stats.promoted = inner.promoted;
  }
  return stats;
}

// lifecycle

/** Returns a new named child of `inner` without making it thread-active.
    The child owns its control `Scope`, `Map`, and mutex and must be released
    before `inner`. Use `Pool.open_named` instead to open a bracket that the
    canonical `String` and `List` operations allocate into.
    Raises: `<alloc-fail>` while building the child. A transfer destroys
    partial child resources and leaves `inner` unchanged; native mutex
    initialization failure aborts.
*/
Pool Pool.retain_named(Pool inner, const char *name) {
  _storage_initialize();
  unsigned capacity = inner._child_capacity();
  Scope scope = Scope.new_named(name), Pool pool = NULL;
  int mutex_ready = 0, finished = 0;
  defer if (!finished) {
    if (mutex_ready) pthread_mutex_destroy(&pool.mutex);
    scope.destroy();
  }
  pool = Scope.malloc_in(&scope, sizeof(struct Pool));
  *pool = (struct Pool) {.scope = scope, .up = inner, .child_capacity = 2};
  Mutex.recursive_initialize(
    &pool.mutex, "Pool: could not initialize branch mutex");
  mutex_ready = 1;
  $scope(&pool.scope) pool.table = Map.new_capacity(capacity);
  finished = 1;
  return pool;
}

static void _storage_initialize(void) {
  _storage_lock();
  defer _storage_unlock();
  if (pool_storage_ready) return;
  Scope.shutdown_hook(_storage_shutdown);
  pool_storage_ready = 1;
}

/* A child's table starts at the capacity the last released direct child's
   table reached. */
static unsigned Pool._child_capacity(Pool inner) {
  if (!inner) return 2;
  inner._lock();
  unsigned capacity = inner.child_capacity;
  inner._unlock();
  return capacity;
}

/** Returns an unnamed child of `inner`, without making it thread-active.
    Ownership, failures, and the comparison with `Pool.open` follow
    `Pool.retain_named`.
*/
Pool Pool.retain(Pool inner) => inner.retain_named(NULL);

/** Destroys one pool and returns its parent, or returns NULL for NULL input.
    Promoted slots and large allocations survive under the parent with stable
    addresses; other identities, the table, and the control `Scope` become
    invalid. Children must already be released, and no caller may use `inner`
    afterward. Use `Pool.close` instead to end a bracket opened with
    `Pool.open`.
*/
Pool Pool.release(Pool inner) {
  if (!inner) return NULL;
  /* Published before any storage is freed, so a reader that sees the old
     value has not yet been able to observe a reused address. */
  __atomic_fetch_add(&value_epoch, 1, __ATOMIC_RELEASE);
  _storage_lock();
  inner._lock();
  Pool up = inner.up;
  if (up) {
    up._lock();
    up.child_capacity = inner.table.capacity;
    up._unlock();
  }
  inner._release_blocks();
  inner._unlock();
  _storage_unlock();
  pthread_mutex_destroy(&inner.mutex);
  Scope.destroy(inner.scope);
  return up;
}

/* String and List register their pool-release hooks after storage first asks
   Scope for this hook. Scope runs hooks in reverse, so their shared pools
   release before the depot and registry are freed here. Direct Pool callers
   remain responsible for releasing their own chains before shutdown. */
static void _storage_shutdown(void) {
  PoolBlock block = pool_registry;
  while (block) {
    PoolBlock next = block.registry_next;
    free(block);
    block = next;
  }
  pool_registry = NULL;
  free(pool_index);
  pool_index = NULL;
  pool_index_slots = pool_index_used = 0;
  pool_index_complete = 1;
  for (int i = 0; i < POOL_DEPOT_COUNT; i++) pool_depot[i] = NULL;
  pool_backing_bytes = 0;
  pool_active_blocks = pool_active_bytes = 0;
  pool_depot_blocks = pool_depot_bytes = 0;
  pool_storage_ready = 0;
}

/* the thread's pool

   String and List share one stack because their immutable values freely
   contain one another. The public bracket below operates on that one stack;
   the instance methods above build a pool without making it thread-active. */

/** Returns the borrowed canonical-value pool active on this thread.
    The process root is installed lazily on first use, so the result is never
    NULL. The pool is borrowed: do not release it with `Pool.release`.
*/
Pool Pool.current(void) {
  if (!value_thread.current) Pool.initialize();
  return value_thread.current;
}

/** Creates the process-wide canonical-value root and makes it active here.
    `x2c_initialize` calls this once; a repeat call does nothing.
    Raises: `<alloc-fail>` if the root cannot be constructed. Native mutex
    initialization failure aborts.
*/
void Pool.initialize(void) {
  if (value_thread.current) return;
  if (!value_root) value_root = Pool.retain_named(NULL, "canonical values");
  value_thread.current = value_root;
}

/** Installs the existing process root in a newly created worker thread.
    The root must already exist; otherwise the process aborts.
*/
void Pool.thread_initialize(void) {
  if (value_thread.current) return;
  if (!value_root) _fatal("canonical value root is not initialized");
  value_thread.current = value_root;
}

/** Releases this thread's open brackets and then the process root.
    Call it only after every worker has stopped and no canonical value is
    still in use. A repeat call after the root is gone does nothing.
*/
void Pool.shutdown(void) {
  while (value_thread.current && value_thread.current != value_root)
    value_thread.current = value_thread.current.release();
  while (value_root) value_root = value_root.release();
  value_thread.current = NULL;
}

/** Opens and returns a named child of the pool active on this thread.
    New canonical misses enter the child; an equal ancestor value keeps its
    existing owner and lifetime. The caller must match this with one
    `Pool.close` or detach it for transfer. The name appears in `Scope`
    diagnostics.
    Raises: `<alloc-fail>` while opening the pool.
    See: Pool.open, Pool.close
*/
Pool Pool.open_named(const char *name) {
  Pool nested = Pool.current().retain_named(name);
  value_thread.current = nested;
  return nested;
}

/** Opens a child of the shared `String` and `List` canonical-value pool.
    New canonical misses enter the child, while equal ancestor values retain
    their existing owner. Promote anything that must outlive the bracket with
    `String.promote` or `List.promote`: unpromoted values are discarded and
    their identities no longer resolve. Brackets nest. The caller must match
    this with one `Pool.close` or detach it for transfer.
    Raises: `<alloc-fail>` while opening the pool.
    See: Pool.close, Pool.open_named, List.promote
*/
Pool Pool.open(void) => Pool.open_named(NULL);

/** Closes the innermost open bracket and makes its parent active.
    Canonical `String`s, `List`s, and transient `String` buffers owned by that
    pool are reclaimed unless promoted; ancestor-owned values remain live.
    Raises: `<bad-state>` when no bracket is open. The failure leaves the
    active pool unchanged.
*/
void Pool.close(void) {
  if (!Pool.current().up) raise %(bad-state (owner "Pool.close"));
  value_thread.current = value_thread.current.release();
}

/** Removes the innermost open bracket without destroying it.
    `Thread` keeps the detached pool sealed until join copies its survivors.
    The returned pool remains owned by the caller until that transfer or an
    explicit `Pool.release`.
    Raises: `<bad-state>` when no bracket is open. The failure leaves the
    active pool unchanged.
*/
Pool Pool.detach(void) {
  Pool detached = Pool.current();
  if (!detached.up) raise %(bad-state (owner "Pool.detach"));
  value_thread.current = detached.up;
  return detached;
}

/** Reports whether the process root owns `value` as its canonical identity.
    Nothing is promoted, and no open bracket can reclaim a value that answers
    one.
*/
int Pool.is_permanent(Var value) => value_root && value_root.owns(value);

/** Returns a counter that changes whenever any pool level is destroyed.
    A cache that borrows canonical identities reads this before trusting an
    entry: a released level's addresses can be reused, so identities admitted
    under an earlier value prove nothing. The counter only advances, so a
    reader needs no lock to tell that something was released.
*/
unsigned long Pool.epoch(void) =>
  __atomic_load_n(&value_epoch, __ATOMIC_ACQUIRE);
