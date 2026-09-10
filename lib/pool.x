/*  pool.x -- nested interning pools with region-backed object storage

    Copyright (c) 2026 Gary William Flake

    A Pool pairs a control `Scope` and canonical `Map` with
    size-class regions for
    small objects. Regions reuse losing intern candidates and lease backing
    blocks from one process-wide depot; large objects retain `Scope` ownership.

    Lookup walks outward. An ancestor hit retains that ancestor's ownership;
    only a new identity lands in the requested pool. Release returns empty
    blocks to the depot and transfers promoted survivors to the parent without
    changing object pointers. Pools form a stack rather than a tree, preserving
    one canonical pointer per equal value across the active chain.
*/

#pragma once

$(import "error-macros.xmacro")
$(import "private-keywords.xmacro")

#include <stddef.h>
#include "common.x"
#include "scope.x"
#include "var.x"
#include "map.x"

/* Holds one internal level of canonical values and their backing storage.
   Pools are released from child to parent. Their handles and unpromoted
   allocations become invalid at release; promoted identities retain their
   pointers under the parent. */
typedef struct Pool {
  Scope scope, Map table, struct Pool *up, pthread_mutex_t mutex;
  unsigned child_capacity;  // last released direct child's table capacity
  size_t interned, promoted, void *blocks, *current[10], *promotions;
} *Pool;

/* Reports one pool level's activity and process-wide storage counters.
   The snapshot owns no storage; `requested_bytes` saturates rather than
   wraps. */
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

enum PoolStorageConstant {
  POOL_CLASS_COUNT = 10,
  POOL_DEPOT_COUNT = 5,
  POOL_KEEP_WORDS = 1
};

typedef struct PoolBlock {
  struct PoolBlock *next, *registry_next, struct Pool *owner, void *free;
  size_t used;
  unsigned class_index;
  unsigned keep_count;
  unsigned bytes;
  uint64_t keep[POOL_KEEP_WORDS];
} *PoolBlock;

typedef struct PoolPromotion {
  PoolBlock block;
  unsigned slot;
  struct PoolPromotion *next;
} *PoolPromotion;

enum PoolBlockConstant {
  POOL_BLOCK_DATA_OFFSET = 64
};

_Static_assert(sizeof(struct PoolBlock) == 64,
               "the pool block header is 64 bytes");

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

typedef struct PoolValueThreadState {
  Pool current;
} *PoolValueThreadState;

static Pool value_root;
static threaded struct PoolValueThreadState value_thread;

/* A process that has never started a worker cannot contend for a pool, and
   the compiler is such a process: locking added a seventh to translation
   time for nothing. `Thread.start` sets this before `pthread_create`, so the
   worker sees it and every lock taken afterwards is real. It never clears,
   because a value interned while it was clear was published without one. */
static int pool_multithreaded;

/* Makes Pool lock from here on, for a process about to start a worker. */
void x2c_pool_thread_start(void) {
  pool_multithreaded = 1;
}

/* Operations needing both locks take storage first, then child, then parent.
   No potentially failing allocation runs while storage is locked. */

static void _storage_lock(void) {
  if (!pool_multithreaded) return;
  if (pthread_mutex_lock(&pool_storage_mutex)) {
    fprintf(stderr, "Pool: could not lock storage mutex\n");
    abort();
  }
}

/* Accounts for one satisfied request. The caller holds the storage lock, so
   the small-class path takes no lock of its own. */
static void _record_request(size_t size) {
  pool_allocation_calls++;
  if (SIZE_MAX - pool_requested_bytes < size) pool_requested_bytes = SIZE_MAX;
  else pool_requested_bytes += size;
}

static void _storage_unlock(void) {
  if (!pool_multithreaded) return;
  if (pthread_mutex_unlock(&pool_storage_mutex)) {
    fprintf(stderr, "Pool: could not unlock storage mutex\n");
    abort();
  }
}

static void _lock(Pool pool) {
  if (!pool_multithreaded) return;
  if (pool && pthread_mutex_lock(&pool.mutex)) {
    fprintf(stderr, "Pool: could not lock branch mutex\n");
    abort();
  }
}

static void _unlock(Pool pool) {
  if (!pool_multithreaded) return;
  if (pool && pthread_mutex_unlock(&pool.mutex)) {
    fprintf(stderr, "Pool: could not unlock branch mutex\n");
    abort();
  }
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
  pool_depot_blocks = 0;
  pool_depot_bytes = 0;
  pool_storage_ready = 0;
}

static void _storage_initialize(void) {
  if (pool_storage_ready) return;
  Scope.shutdown_hook(_storage_shutdown);
  pool_storage_ready = 1;
}

static inline char *_block_data(PoolBlock block) =>
  (char *) block + POOL_BLOCK_DATA_OFFSET;

static inline void *_block_slot(PoolBlock block, unsigned slot) =>
  _block_data(block) + slot * pool_class_sizes[block.class_index];

static int _class(size_t size) {
  for (int i = 0; i < POOL_CLASS_COUNT; i++)
    if (size <= pool_class_sizes[i]) return i;
  return -1;
}

static int _block_contains(PoolBlock block, const void *ptr) {
  if (!block || !ptr || !block.owner) return 0;
  const char *data = _block_data(block), *candidate = ptr;
  unsigned size = pool_class_sizes[block.class_index];
  if (candidate < data || candidate >= data + block.used) return 0;
  return (size_t) (candidate - data) % size == 0;
}

static unsigned _index_start(uintptr_t page, unsigned slots) =>
  (unsigned) ((page * 0x9E3779B97F4A7C15ull) >> 32) & (slots - 1);

static void _index_place(
  PoolIndexSlot *table, unsigned slots, uintptr_t page, PoolBlock block) {
  unsigned at = _index_start(page, slots);
  while (table[at].block) at = (at + 1) & (slots - 1);
  table[at].page = page;
  table[at].block = block;
}

/* Keeps the table under half full so a lookup always meets a free slot. */
static int _index_grow(void) {
  unsigned slots = pool_index_slots * 2;
  if (!slots) slots = POOL_INDEX_FIRST_SLOTS;
  PoolIndexSlot *table = calloc(slots, sizeof(PoolIndexSlot));
  if (!table) return 0;
  for (unsigned at = 0; at < pool_index_slots; at++)
    if (pool_index[at].block)
      _index_place(
        table, slots, pool_index[at].page, pool_index[at].block);
  free(pool_index);
  pool_index = table;
  pool_index_slots = slots;
  return 1;
}

/* A block spans at most two pages, so it takes at most two slots. Growth is
   the one allocation here and it disables the index instead of failing, which
   keeps `_block_lease` free of a failure path while storage is locked. */
static void _index_register(PoolBlock block, unsigned bytes) {
  if (!pool_index_complete) return;
  uintptr_t last = ((uintptr_t) block + bytes - 1) >> POOL_INDEX_PAGE_SHIFT;
  for (uintptr_t page = (uintptr_t) block >> POOL_INDEX_PAGE_SHIFT;
       page <= last; page++) {
    if ((pool_index_used + 1) * 2 > pool_index_slots && !_index_grow()) {
      pool_index_complete = 0;
      return;
    }
    _index_place(pool_index, pool_index_slots, page, block);
    pool_index_used++;
  }
}

static PoolBlock _find_registered_block(const void *ptr) {
  if (!pool_index_complete) {
    for (PoolBlock block = pool_registry; block; block = block.registry_next)
      if (_block_contains(block, ptr)) return block;
    return NULL;
  }
  if (!pool_index_slots) return NULL;
  uintptr_t page = (uintptr_t) ptr >> POOL_INDEX_PAGE_SHIFT;
  unsigned at = _index_start(page, pool_index_slots);
  while (pool_index[at].block) {
    if (pool_index[at].page == page &&
        _block_contains(pool_index[at].block, ptr))
      return pool_index[at].block;
    at = (at + 1) & (pool_index_slots - 1);
  }
  return NULL;
}

static int _block_available(PoolBlock block) {
  if (!block) return 0;
  if (block.free) return 1;
  unsigned size = pool_class_sizes[block.class_index];
  return block.used + size <= block.bytes - POOL_BLOCK_DATA_OFFSET;
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

/* Called with storage and pool locked. `fresh` was allocated with neither
   lock held, so allocation failure can enter Error without reentering the
   storage mutex. */
static PoolBlock _block_lease(
  Pool pool, int class_index, PoolBlock fresh) {
  unsigned bytes = pool_block_sizes[class_index];
  if (class_index == 0 && pool.up) bytes = 256;
  int depot_index = _depot_index(bytes);
  PoolBlock block = pool_depot[depot_index];
  if (block) {
    pool_depot[depot_index] = block.next;
    pool_depot_blocks--;
    pool_depot_bytes -= bytes;
    pool_block_reuses++;
  }
  else {
    if (!fresh) return NULL;
    block = fresh;
    block.registry_next = pool_registry;
    pool_registry = block;
    _index_register(block, bytes);
    pool_block_allocations++;
    pool_backing_bytes += bytes;
  }
  pool_active_blocks++;
  pool_active_bytes += bytes;
  block.next = pool.blocks;
  block.owner = pool;
  block.free = NULL;
  block.used = 0;
  block.class_index = class_index;
  block.keep_count = 0;
  block.bytes = bytes;
  memset(block.keep, 0, sizeof block.keep);
  pool.blocks = block;
  pool.current[class_index] = block;
  return block;
}

static void _block_return(PoolBlock block) {
  int depot_index = _depot_index(block.bytes);
  block.owner = NULL;
  block.free = NULL;
  block.used = 0;
  block.keep_count = 0;
  memset(block.keep, 0, sizeof block.keep);
  block.next = pool_depot[depot_index];
  pool_depot[depot_index] = block;
  pool_active_blocks--;
  pool_active_bytes -= block.bytes;
  pool_depot_blocks++;
  pool_depot_bytes += block.bytes;
}

static PoolBlock _available_block(Pool pool, int class_index) {
  PoolBlock current = pool.current[class_index];
  if (_block_available(current)) return current;
  return NULL;
}

static void *_small_malloc(Pool pool, int class_index) {
  PoolBlock block = _available_block(pool, class_index);
  if (block.free) {
    void *result = block.free;
    block.free = *(void **) result;
    pool_slot_reuses++;
    return result;
  }
  void *result = _block_data(block) + block.used;
  block.used += pool_class_sizes[class_index];
  return result;
}

static void _small_free(PoolBlock block, void *ptr) {
  *(void **) ptr = block.free;
  block.free = ptr;
  block.owner.current[block.class_index] = block;
}

static void _mark_slot(PoolBlock block, unsigned slot) {
  uint64_t mask = (uint64_t) 1 << (slot % 64), *word = &block.keep[slot / 64];
  if (*word & mask) return;
  *word |= mask;
  block.keep_count++;
}

static void _mark_survivor(PoolPromotion promotion) {
  _mark_slot(promotion.block, promotion.slot);
}

static int _slot_kept(PoolBlock block, unsigned slot) {
  uint64_t mask = (uint64_t) 1 << (slot % 64);
  return (block.keep[slot / 64] & mask) != 0;
}

static void _block_transfer(PoolBlock p, Pool parent) {
  unsigned count = p.used / pool_class_sizes[p.class_index];
  p.free = NULL;
  for (unsigned slot = count; slot > 0; slot--) {
    unsigned index = slot - 1;
    if (_slot_kept(p, index)) continue;
    void *ptr = _block_slot(p, index);
    *(void **) ptr = p.free;
    p.free = ptr;
  }
  p.owner = parent;
  p.keep_count = 0;
  memset(p.keep, 0, sizeof p.keep);
  p.next = parent.blocks;
  parent.blocks = p;
  parent.current[p.class_index] = p;
}

static void _release_blocks(Pool inner) {
  for (PoolPromotion promotion = inner.promotions; promotion;
       promotion = promotion.next)
    _mark_survivor(promotion);

  PoolBlock block = inner.blocks;
  while (block) {
    PoolBlock next = block.next;
    if (inner.up && block.keep_count) _block_transfer(block, inner.up);
    else _block_return(block);
    block = next;
  }
  inner.blocks = NULL;
  for (int i = 0; i < POOL_CLASS_COUNT; i++) inner.current[i] = NULL;
}

/* Returns a new child of `inner` without making it thread-active. The child
   owns its control Scope, Map, and mutex and must be released before `inner`.
   A transfer destroys partial child resources and leaves `inner` unchanged;
   native mutex initialization failure aborts. */
Pool Pool.retain_named(Pool inner, const char *name) {
  _storage_lock();
  _storage_initialize();
  _storage_unlock();
  unsigned capacity = 2;
  if (inner) {
    _lock(inner);
    capacity = inner.child_capacity;
    _unlock(inner);
  }
  Scope scope = Scope.new_named(name), Pool pool = NULL;
  int mutex_ready = 0, pushed = 0, finished = 0;
  defer if (!finished) {
    if (pushed) Scope.pop();
    if (mutex_ready) pthread_mutex_destroy(&pool.mutex);
    Scope.destroy(scope);
  }
  pool = Scope.malloc_in(&scope, sizeof(struct Pool));
  /* The branch mutex must stay recursive. Pool.lookup holds it across
     Map.getindex, whose Var hash and equality reach the descriptor dispatch,
     which builds Strings, which re-enter Pool.lookup on this same pool.
     Re-entry arrives through arbitrary callbacks, so this file cannot
     enumerate the paths. */
  pthread_mutexattr_t attributes;
  if (pthread_mutexattr_init(&attributes) ||
      pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE) ||
      pthread_mutex_init(&pool.mutex, &attributes)) {
    fprintf(stderr, "Pool: could not initialize branch mutex\n");
    abort();
  }
  pthread_mutexattr_destroy(&attributes);
  mutex_ready = 1;
  pool.scope = scope;
  Scope.push(&pool.scope);
  pushed = 1;
  Map table = Map.new_capacity(capacity);
  Scope.pop();
  pushed = 0;
  pool.table = table;
  pool.up = inner;
  pool.child_capacity = 2;
  pool.interned = pool.promoted = 0;
  pool.blocks = NULL;
  for (int i = 0; i < POOL_CLASS_COUNT; i++) pool.current[i] = NULL;
  pool.promotions = NULL;
  finished = 1;
  return pool;
}

/* Returns an unnamed child of `inner`; ownership follows `retain_named`. */
Pool Pool.retain(Pool inner) => inner.retain_named(NULL);

/* Destroys one pool and returns its parent, or returns NULL for NULL input.
   Promoted slots and large allocations survive under the parent with stable
   addresses; other identities, the table, and the control Scope are invalid.
   Children must already be released, and no caller may use `inner` afterward.
*/
Pool Pool.release(Pool inner) {
  if (!inner) return NULL;
  _storage_lock();
  _lock(inner);
  Pool up = inner.up;
  if (up) {
    _lock(up);
    up.child_capacity = inner.table.capacity;
    _unlock(up);
  }
  _release_blocks(inner);
  _unlock(inner);
  _storage_unlock();
  pthread_mutex_destroy(&inner.mutex);
  Scope.destroy(inner.scope);
  return up;
}

/* String and List share one stack because their immutable values freely
   contain one another. The public String.pool_* and List.pool_* entry points
   remain as names for this one stack. */
/* Returns the borrowed active canonical-value pool, lazily installing the
   process root in this thread when needed. */
Pool x2c_pool_values_current(void) {
  if (!value_thread.current) x2c_pool_values_initialize();
  return value_thread.current;
}

/* Installs the shared root as this thread's active pool, creating it once. */
void x2c_pool_values_initialize(void) {
  if (value_thread.current) return;
  if (!value_root) value_root = Pool.retain_named(NULL, "canonical values");
  value_thread.current = value_root;
}

/* Installs the existing process root in a worker; an absent root aborts. */
void x2c_pool_values_thread_initialize(void) {
  if (value_thread.current) return;
  if (!value_root) {
    fprintf(stderr, "Pool: canonical value root is not initialized\n");
    abort();
  }
  value_thread.current = value_root;
}

/* Releases this thread's nested chain, then the shared root. Process shutdown
   calls this only after workers stop and before Pool storage is destroyed. */
void x2c_pool_values_shutdown(void) {
  while (value_thread.current && value_thread.current != value_root)
    value_thread.current = value_thread.current.release();
  while (value_root) value_root = value_root.release();
  value_thread.current = NULL;
}

/* Pushes and returns a named child as this thread's active pool. */
Pool x2c_pool_values_retain_named(const char *name) {
  Pool nested = x2c_pool_values_current().retain_named(name);
  value_thread.current = nested;
  return nested;
}

/* Pushes and returns an unnamed child as this thread's active pool. */
Pool x2c_pool_values_retain(void) => x2c_pool_values_retain_named(NULL);

/* Releases the active pool and makes its parent active. The caller guarantees
   that the active pool is a child rather than the shared root. */
void x2c_pool_values_release(void) {
  value_thread.current = value_thread.current.release();
}

/* Removes and returns the active child without releasing it. Its parent
   becomes active, and the detached chain must remain sealed until release. */
Pool x2c_pool_values_detach(void) {
  Pool detached = value_thread.current;
  value_thread.current = detached.up;
  return detached;
}

/* Reports exact identity ownership by the process root without promotion. */
int x2c_pool_values_is_permanent(Var value) =>
  value_root && value_root.owns(value);

/* Returns the first value equal to `key` from `inner` outward, or `void`.
   The returned identity remains owned by the level where it was found. */
Var Pool.lookup(Pool inner, Var key) {
  for (Pool pool = inner; pool; pool = pool.up) {
    _lock(pool);
    Var found = pool.table[key];
    _unlock(pool);
    if (found is not void) return found;
  }
  return void;
}

/* Map insertion causes propagate and leave the object unregistered. */
static void _insert_locked(Pool inner, Var object) {
  inner.table.setindex(object, object);
  inner.interned++;
}

/* Installs `object` as its own canonical value in exactly `inner`. The caller
   must have ruled out an equal identity in this pool chain; this primitive
   neither searches ancestors nor takes ownership of separate object
   storage. */
void Pool.insert(Pool inner, Var object) {
  if (!inner) raise %(bad-arg (owner "Pool.insert"));
  _lock(inner);
  defer _unlock(inner);
  _insert_locked(inner, object);
}

/* Returns the canonical value equal to `object`, installing `object` in the
   innermost table when absent. `alloc` is the object's Pool-owned allocation;
   a hit releases that losing candidate immediately. A failed insertion leaves
   the candidate owned by the caller so its existing cleanup boundary runs.

   Ancestors are checked before the innermost fused Map operation. Pool's
   single-canonical-pointer invariant makes that order equivalent to outward
   shadowing while allowing the innermost table to be probed exactly once.

   Raises: `<bad-arg>` when inner or alloc is NULL. Map lookup and insertion
   causes propagate. */
Var Pool.intern(Pool inner, Var object, void *alloc) {
  if (!inner || !alloc) raise %(bad-arg (owner "Pool.intern"));
  Var canonical;
  int discard = 0;
  {
    _lock(inner);
    defer _unlock(inner);
    Var existing = Pool.lookup(inner.up, object);
    if (existing is not void) {
      canonical = existing;
      discard = 1;
    }
    else {
      unsigned before = inner.table.len();
      Var stored = inner.table.setdefault(object, object);
      canonical = stored;
      if (inner.table.len() != before) inner.interned++;
      else discard = 1;
    }
  }
  // Pool.free takes storage before the pool. Do not call it while holding
  // the pool mutex or another worker can complete the opposite lock order.
  if (discard) inner.free(alloc);
  return canonical;
}

/* Allocates object storage owned by inner. Requests through 512 bytes use a
   size-class region; larger requests retain ordinary Scope ownership.

   Raises: `<bad-arg>` when inner is NULL, `<size-limit>` when a large request
   overflows Scope storage, or `<alloc-fail>` when storage cannot be
   allocated. */
void *Pool.malloc(Pool inner, size_t size) {
  if (!inner) raise %(bad-arg (owner "Pool.malloc"));
  int class_index = _class(size);
  if (class_index >= 0) {
    PoolBlock fresh = NULL;
    loop {
      _storage_lock();
      _lock(inner);
      PoolBlock block = _available_block(inner, class_index);
      if (!block) block = _block_lease(inner, class_index, fresh);
      if (block) {
        if (block == fresh) fresh = NULL;
        void *result = _small_malloc(inner, class_index);
        _record_request(size);
        _unlock(inner);
        _storage_unlock();
        free(fresh);
        return result;
      }
      _unlock(inner);
      _storage_unlock();

      unsigned bytes = pool_block_sizes[class_index];
      if (class_index == 0 && inner.up) bytes = 256;
      fresh = malloc(bytes);
      if (!fresh) {
        if (x2c_error_runtime_ready)
          raise %(alloc-fail (owner "Pool backing block"));
        fprintf(stderr, "Pool: backing block allocation failed\n");
        abort();
      }
    }
  }
  _storage_lock();
  _record_request(size);
  _storage_unlock();
  _lock(inner);
  defer _unlock(inner);
  return Scope.malloc_in(&inner.scope, size);
}

/* Releases a losing or transient allocation from `inner`'s Pool chain. Region
   slots become immediately reusable; large allocations use Scope.free. A
   canonical allocation still present in a table must not be freed this way. */
void Pool.free(Pool inner, void *alloc) {
  if (!alloc) return;
  if (!inner) raise %(bad-arg (owner "Pool.free"));
  _storage_lock();
  defer _storage_unlock();
  _lock(inner);
  defer _unlock(inner);
  PoolBlock block = _find_registered_block(alloc);
  pool_free_calls++;
  if (block) {
    _small_free(block, alloc);
    return;
  }
  Scope.free(alloc);
}

static int _owns_locked(Pool pool, Var key) {
  Var found = pool.table[key];
  return found is not void && found === key;
}

/* Reports whether this exact level stores `key` as its canonical identity.
   Ancestors are not searched. */
int Pool.owns(Pool pool, Var key) {
  if (!pool) return 0;
  _lock(pool);
  defer _unlock(pool);
  return _owns_locked(pool, key);
}

/* Moves `object` from `inner` to `inner.up`. `block` is the region block
   backing `alloc`, or NULL when Scope owns it. The caller supplies the block
   because a value promoted through several levels stays in the same one. */
static int _promote_block(
  Pool inner, Var object, void *alloc, PoolBlock block) {
  _lock(inner);
  defer _unlock(inner);
  if (!_owns_locked(inner, object)) return 0;
  PoolPromotion promotion = NULL;
  unsigned slot = 0;
  if (block)
    slot = ((char *) alloc - _block_data(block)) /
           pool_class_sizes[block.class_index];
  if (block && block.owner != inner) {
    promotion = Scope.malloc_in(&inner.scope, sizeof(struct PoolPromotion));
    promotion.block = block;
    promotion.slot = slot;
  }
  _lock(inner.up);
  defer _unlock(inner.up);
  _insert_locked(inner.up, object);
  if (block && block.owner == inner) _mark_slot(block, slot);
  else if (promotion) {
    promotion.next = inner.promotions;
    inner.promotions = promotion;
  }
  else Scope.move(alloc, &inner.up.scope);
  inner.promoted++;
  return 1;
}

/* Straight lock and unlock rather than a defer: this runs on every promotion
   and nothing between the two calls can raise. */
static PoolBlock _block_of(void *alloc) {
  _storage_lock();
  PoolBlock block = _find_registered_block(alloc);
  _storage_unlock();
  return block;
}

/* Publishes an identity owned by `inner` in its parent and preserves `alloc`
   across `inner`'s release without changing its address. Returns zero for a
   missing owner, root pool, or null allocation. Promotion metadata or parent
   table insertion may transfer before storage is marked or moved. */
int Pool.promote(Pool inner, Var object, void *alloc) {
  if (!inner || !inner.up || !alloc) return 0;
  return _promote_block(inner, object, alloc, _block_of(alloc));
}

/* Proves `object` safe beyond every pool in `inner`'s chain, promoting it to
   the outermost pool when a pool in the chain owns it. `alloc` is the
   object's Pool-owned allocation. Returns one when the value is already
   outermost or reaches it, and zero when no pool in the chain owns it or a
   promotion fails. A null `inner` reports safe, since no pool can then
   reclaim the value. Promotion is not transactional across levels: an earlier
   level remains promoted if a later promotion transfers.

   Raises: `<alloc-fail>` when promotion metadata cannot be allocated. */
int Pool.own(Pool inner, Var object, void *alloc) {
  if (!inner) return 1;
  Pool owner = inner;
  while (owner && !owner.owns(object)) owner = owner.up;
  if (!owner) return 0;
  if (!owner.up) return 1;
  if (!alloc) return 0;
  PoolBlock block = _block_of(alloc);
  while (owner.up) {
    if (!_promote_block(owner, object, alloc, block)) return 0;
    owner = owner.up;
  }
  return 1;
}

/* Returns this level's canonical counts plus process-wide storage counters.
   A null pool reports depth and per-level counts as zero. */
PoolStats Pool.stats(Pool inner) {
  _storage_lock();
  defer _storage_unlock();
  if (inner) _lock(inner);
  defer if (inner) _unlock(inner);
  PoolStats stats = { 0 };
  for (Pool pool = inner; pool; pool = pool.up) stats.depth++;
  if (inner) {
    stats.interned = inner.interned;
    stats.promoted = inner.promoted;
  }
  stats.allocation_calls = pool_allocation_calls;
  stats.free_calls = pool_free_calls;
  stats.requested_bytes = pool_requested_bytes;
  stats.block_allocations = pool_block_allocations;
  stats.block_reuses = pool_block_reuses;
  stats.slot_reuses = pool_slot_reuses;
  stats.backing_bytes = pool_backing_bytes;
  stats.active_blocks = pool_active_blocks;
  stats.active_bytes = pool_active_bytes;
  stats.depot_blocks = pool_depot_blocks;
  stats.depot_bytes = pool_depot_bytes;
  return stats;
}
