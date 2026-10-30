/*  storage.x -- pool storage */

static keyword loop $private.loop;

/* storage

   A request through 512 bytes takes a slot of the smallest size class that
   holds it. A block carries the slots of one class after a 64-byte header,
   and a released block waits in the depot for its next lease. */

static enum PoolStorageConstant {
  POOL_CLASS_COUNT = 10,
  POOL_DEPOT_COUNT = 5,
  POOL_KEEP_WORDS = 1
};

static typedef struct PoolBlock {
  struct PoolBlock *next, *registry_next, struct Pool *owner, void *free;
  size_t used, unsigned class_index, keep_count, bytes;
  uint64_t keep[POOL_KEEP_WORDS];
} *PoolBlock;

static typedef struct PoolPromotion {
  PoolBlock block, unsigned slot, struct PoolPromotion *next;
} *PoolPromotion;

static enum PoolBlockConstant {
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
   in the depot retains its immutable backing extent. */
static typedef struct PoolIndexSlot {
  uintptr_t page;
  PoolBlock block;
} PoolIndexSlot;

static enum PoolIndexConstant {
  POOL_INDEX_PAGE_SHIFT = 12,
  POOL_INDEX_FIRST_SLOTS = 256
};

static PoolBlock pool_registry;
static typedef struct PoolIndex {
  struct PoolIndex *previous;
  unsigned slots;
  PoolIndexSlot entries[];
} *PoolIndex;

static PoolIndex pool_index;
static unsigned pool_index_used;
static size_t pool_index_version;
static pthread_mutex_t pool_index_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
/* The index establishes absence conclusively only while it holds every
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

// allocation

/** Allocates object storage owned by `inner`.
    Requests through 512 bytes use a size-class region; larger requests retain
    ordinary `Scope` ownership.

    Raises: `<bad-arg>` when `inner` is NULL, `<size-limit>` when a large
    request overflows `Scope` storage, or `<alloc-fail>` when storage cannot
    be allocated.
*/
void *Pool.malloc(Pool inner, size_t size) {
  if (!inner) raise %(bad-arg (operation "Pool.malloc"));
  int class_index = _size_class(size);
  if (class_index >= 0) return _small_malloc(inner, class_index, size);
  if (Scope.accounting_enabled()) {
    _record_request(size);
  }
  _lock(inner);
  defer _unlock(inner);
  return Scope.malloc_in(&inner.scope, size);
}

/** Releases a losing or transient allocation from `inner`'s pool chain.
    Region slots become immediately reusable; large allocations use
    `Scope.free`. A canonical allocation still present in a table must not be
    freed this way. A null allocation does nothing.
    Raises: `<bad-arg>` when `inner` is NULL and `alloc` is not.
*/
void Pool.free(Pool inner, void *alloc) {
  if (!alloc) return;
  if (!inner) raise %(bad-arg (operation "Pool.free"));
  PoolBlock block = _find_block(alloc);
  Pool owner = block ? __atomic_load_n(&block.owner, __ATOMIC_ACQUIRE) : inner;
  _lock(owner);
  defer _unlock(owner);
  if (Scope.accounting_enabled())
    __atomic_fetch_add(&pool_free_calls, 1, __ATOMIC_RELAXED);
  if (block) _free_slot(block, alloc);
  else xfree(alloc);
}

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
  return _promote_level(inner, object, alloc, _block_of(alloc));
}

/** Proves `object` safe beyond every pool in `inner`'s chain.
    It is promoted to the outermost pool when a pool in the chain owns it.
    `alloc` is the object's `Pool`-owned allocation. Returns one when the
    value is already outermost or reaches it, and zero when no pool in the
    chain owns it or a promotion fails. A null `inner` reports safe, since no
    pool can then reclaim the value. Promotion is not transactional across
    levels: an earlier level remains promoted if a later promotion transfers.
    A thread that loses a concurrent promotion of an equal value still gets
    one, though `Pool.is_permanent` returns zero for its surviving copy.

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
    if (!_promote_level(owner, object, alloc, block)) return 0;
    owner = owner.up;
  }
  return 1;
}

// statistics

/** Returns this level's canonical counts plus process-wide storage counters.
    A null pool reports depth and per-level counts as zero. The counters are a
    snapshot; nothing in the result stays live with the pool.
*/
PoolStats Pool.stats(Pool inner) {
  _lock(inner);
  defer _unlock(inner);
  _index_lock();
  defer _index_unlock();
  _storage_lock();
  defer _storage_unlock();
  PoolStats stats = {
    .allocation_calls = __atomic_load_n(&pool_allocation_calls, __ATOMIC_RELAXED),
    .free_calls = __atomic_load_n(&pool_free_calls, __ATOMIC_RELAXED),
    .requested_bytes = __atomic_load_n(&pool_requested_bytes, __ATOMIC_RELAXED),
    .block_allocations = pool_block_allocations,
    .block_reuses = pool_block_reuses,
    .slot_reuses = __atomic_load_n(&pool_slot_reuses, __ATOMIC_RELAXED),
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

/* Prepare refill storage without holding an owner or shared lock. */
static void *_small_malloc(Pool inner, int class_index, size_t size) {
  int accounting = Scope.accounting_enabled();
  PoolBlock candidate = NULL;
  loop {
    _lock(inner);
    PoolBlock block = _block_with_room(inner, class_index);
    if (!block && candidate) {
      block = candidate;
      candidate = NULL;
      _reset(block, inner);
      block.class_index = class_index;
      _link(block, inner);
    }
    if (block) {
      void *slot = _take_slot(block, class_index, accounting);
      _unlock(inner);
      if (candidate) _return_block(candidate);
      if (accounting) _record_request(size);
      return slot;
    }
    _unlock(inner);
    candidate = _prepare_block(inner, class_index);
  }
}

static int _size_class(size_t size) {
  for (int i = 0; i < POOL_CLASS_COUNT; i++)
    if (size <= pool_class_sizes[i]) return i;
  return -1;
}

static PoolBlock _block_with_room(Pool pool, int class_index) {
  PoolBlock current = pool.current[class_index];
  return _has_room(current) ? current : NULL;
}

static int _has_room(PoolBlock block) {
  if (!block) return 0;
  if (block.free) return 1;
  unsigned size = pool_class_sizes[block.class_index];
  return block.used + size <= block.bytes - POOL_BLOCK_DATA_OFFSET;
}

/* Reuses a freed slot, or else hands out the next slot never used. */
static void *_take_slot(PoolBlock block, int class_index, int accounting) {
  void *slot = block.free;
  if (slot) {
    block.free = *(void **) slot;
    if (accounting) __atomic_fetch_add(&pool_slot_reuses, 1, __ATOMIC_RELAXED);
    return slot;
  }
  slot = _data(block) + block.used;
  block.used += pool_class_sizes[class_index];
  return slot;
}

/* Allocates with no lock held, so the failure can enter Error without
   reentering the storage mutex. */
static PoolBlock _fresh_block(Pool inner, int class_index) {
  PoolBlock fresh = malloc(_block_bytes(inner, class_index));
  if (fresh) {
    fresh.bytes = _block_bytes(inner, class_index);
    return fresh;
  }
  if (x2c_error_runtime_ready)
    raise %(alloc-fail (operation "Pool backing block"));
  _fatal("backing block allocation failed");
}

// blocks

static PoolBlock _prepare_block(Pool pool, int class_index) {
  unsigned bytes = _block_bytes(pool, class_index);
  _storage_lock();
  PoolBlock block = _depot_pop(bytes);
  if (block) {
    pool_active_blocks++;
    pool_active_bytes += bytes;
  }
  _storage_unlock();
  if (block) return block;
  block = _fresh_block(pool, class_index);
  _registry_add(block, bytes);
  _storage_lock();
  pool_active_blocks++;
  pool_active_bytes += bytes;
  _storage_unlock();
  return block;
}

static void _return_block(PoolBlock block) {
  _reset(block, NULL);
  _storage_lock();
  _depot_push(block);
  _storage_unlock();
}

/* A nested pool's smallest class leases 256-byte blocks. */
static unsigned _block_bytes(Pool pool, int class_index) =>
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
  loop {
    _index_prepare();
    _index_lock();
    PoolIndex index = __atomic_load_n(&pool_index, __ATOMIC_ACQUIRE);
    if (pool_index_complete &&
        (!index || (pool_index_used + 2) * 2 > index.slots)) {
      _index_unlock();
      continue;
    }
    block.registry_next = __atomic_load_n(&pool_registry, __ATOMIC_RELAXED);
    if (pool_index_complete) {
      uintptr_t first = (uintptr_t) block >> POOL_INDEX_PAGE_SHIFT;
      uintptr_t last = ((uintptr_t) block + bytes - 1) >> POOL_INDEX_PAGE_SHIFT;
      for (uintptr_t page = first; page <= last; page++) {
        _index_place(index.entries, index.slots, page, block);
        pool_index_used++;
      }
    }
    __atomic_store_n(&pool_registry, block, __ATOMIC_RELEASE);
    pool_block_allocations++;
    pool_backing_bytes += bytes;
    pool_index_version++;
    _index_unlock();
    return block;
  }
}

/* Empties `block` under `owner`: no slot handed out or free, and none kept. */
static void _reset(PoolBlock block, Pool owner) {
  __atomic_store_n(&block.owner, owner, __ATOMIC_RELEASE);
  block.free = NULL;
  block.used = 0;
  block.keep_count = 0;
  memset(block.keep, 0, sizeof block.keep);
}

/* Makes `block` the newest block of `pool` and its class's current one. */
static void _link(PoolBlock block, Pool pool) {
  block.next = pool.blocks;
  pool.blocks = block;
  pool.current[block.class_index] = block;
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

static inline char *_data(PoolBlock block) =>
  (char *) block + POOL_BLOCK_DATA_OFFSET;

// block index

/* Published versions and immutable registry links live until shutdown. */
static void _index_prepare(void) {
  loop {
    _index_lock();
    PoolIndex previous = __atomic_load_n(&pool_index, __ATOMIC_ACQUIRE);
    size_t version = pool_index_version;
    int needed = pool_index_complete &&
      (!previous || (pool_index_used + 2) * 2 > previous.slots);
    _index_unlock();
    if (!needed) return;
    unsigned slots = !previous ? POOL_INDEX_FIRST_SLOTS :
      previous.slots <= ~0u / 2 ? previous.slots * 2 : 0;
    PoolIndex candidate = slots ?
      calloc(1, sizeof(struct PoolIndex) + slots * sizeof(PoolIndexSlot)) : NULL;
    if (candidate) {
      candidate.slots = slots;
      candidate.previous = previous;
      if (previous)
        for (unsigned at = 0; at < previous.slots; at++) {
          PoolBlock block = __atomic_load_n(
            &previous.entries[at].block, __ATOMIC_ACQUIRE);
          if (block) _index_place(candidate.entries, slots,
            previous.entries[at].page, block);
        }
    }
    _index_lock();
    int unchanged = version == pool_index_version;
    if (unchanged) {
      if (candidate) __atomic_store_n(&pool_index, candidate, __ATOMIC_RELEASE);
      else __atomic_store_n(&pool_index_complete, 0, __ATOMIC_RELEASE);
      pool_index_version++;
    }
    _index_unlock();
    if (unchanged) return;
    free(candidate);
  }
}

static void _index_place(
  PoolIndexSlot *table, unsigned slots, uintptr_t page, PoolBlock block) {
  unsigned at = _index_start(page, slots);
  while (__atomic_load_n(&table[at].block, __ATOMIC_ACQUIRE))
    at = (at + 1) & (slots - 1);
  table[at].page = page;
  __atomic_store_n(&table[at].block, block, __ATOMIC_RELEASE);
}

static unsigned _index_start(uintptr_t page, unsigned slots) =>
  (unsigned) ((page * 0x9E3779B97F4A7C15ull) >> 32) & (slots - 1);

static void _index_lock(void) {
  if (pool_multithreaded && pthread_mutex_lock(&pool_index_mutex))
    _fatal("could not lock index mutex");
}

static void _index_unlock(void) {
  if (pool_multithreaded && pthread_mutex_unlock(&pool_index_mutex))
    _fatal("could not unlock index mutex");
}

module void _storage_lock(void) {
  if (pool_multithreaded && pthread_mutex_lock(&pool_storage_mutex))
    _fatal("could not lock storage mutex");
}

module void _storage_unlock(void) {
  if (pool_multithreaded && pthread_mutex_unlock(&pool_storage_mutex))
    _fatal("could not unlock storage mutex");
}

module void _lock(Pool pool) {
  if (pool_multithreaded && pool && pthread_mutex_lock(&pool.mutex))
    _fatal("could not lock branch mutex");
}

module void _unlock(Pool pool) {
  if (pool_multithreaded && pool && pthread_mutex_unlock(&pool.mutex))
    _fatal("could not unlock branch mutex");
}

/* Ends the process on a native failure that Error cannot report. */
module void _fatal(const char *message) {
  fprintf(stderr, "Pool: %s\n", message);
  abort();
}

/* Traffic counters are opt-in and do not acquire a shared mutex. */
static void _record_request(size_t size) {
  if (!Scope.accounting_enabled()) return;
  __atomic_fetch_add(&pool_allocation_calls, 1, __ATOMIC_RELAXED);
  size_t previous = __atomic_load_n(&pool_requested_bytes, __ATOMIC_RELAXED);
  loop {
    size_t next = SIZE_MAX - previous < size ? SIZE_MAX : previous + size;
    if (__atomic_compare_exchange_n(&pool_requested_bytes, &previous, next,
        1, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) return;
  }
}

/* The freed slot is reused first, from a block that becomes its class's
   current one. */
static void _free_slot(PoolBlock block, void *ptr) {
  _push_free(block, ptr);
  Pool owner = __atomic_load_n(&block.owner, __ATOMIC_ACQUIRE);
  owner.current[block.class_index] = block;
}

static void _push_free(PoolBlock block, void *slot) {
  *(void **) slot = block.free;
  block.free = slot;
}

/* A miss rechecks publication before concluding absence. */
static PoolBlock _find_block(const void *ptr) {
  loop {
    PoolIndex index = __atomic_load_n(&pool_index, __ATOMIC_ACQUIRE);
    PoolBlock block = _index_find(index, ptr);
    if (block) return block;
    if (!__atomic_load_n(&pool_index_complete, __ATOMIC_ACQUIRE))
      return _registry_find(ptr);
    if (index == __atomic_load_n(&pool_index, __ATOMIC_ACQUIRE)) return NULL;
  }
}

static PoolBlock _index_find(PoolIndex index, const void *ptr) {
  if (!index) return NULL;
  uintptr_t page = (uintptr_t) ptr >> POOL_INDEX_PAGE_SHIFT;
  unsigned at = _index_start(page, index.slots);
  PoolBlock block;
  while ((block = __atomic_load_n(&index.entries[at].block, __ATOMIC_ACQUIRE))) {
    if (index.entries[at].page == page && _contains(block, ptr)) return block;
    at = (at + 1) & (index.slots - 1);
  }
  return NULL;
}

static PoolBlock _registry_find(const void *ptr) {
  PoolBlock head = __atomic_load_n(&pool_registry, __ATOMIC_ACQUIRE);
  for (PoolBlock block = head; block; block = block.registry_next)
    if (_contains(block, ptr)) return block;
  return NULL;
}

static int _contains(PoolBlock block, const void *ptr) {
  uintptr_t candidate = (uintptr_t) ptr, first = (uintptr_t) _data(block);
  return candidate >= first &&
    candidate - first < block.bytes - POOL_BLOCK_DATA_OFFSET;
}

/* Moves `object` from `inner` to `inner.up`. `block` is the region block
   backing `alloc`, or NULL when Scope owns it. The caller supplies the block
   because a value promoted through several levels stays in the same one.
   Another thread's pool can promote an equal value first; that identity
   stays canonical, and `object` survives without replacing it. */
static int _promote_level(
  Pool inner, Var object, void *alloc, PoolBlock block) {
  _lock(inner);
  defer _unlock(inner);
  if (!_owns_locked(inner, object)) return 0;
  unsigned slot = block ? _slot_index(block, alloc) : 0;
  PoolPromotion promotion = NULL;
  if (block && __atomic_load_n(&block.owner, __ATOMIC_ACQUIRE) != inner) {
    promotion = Scope.malloc_in(&inner.scope, sizeof(struct PoolPromotion));
    promotion.block = block;
    promotion.slot = slot;
  }
  Pool up = inner.up;
  _lock(up);
  defer _unlock(up);
  int inserted;
  _setdefault(up, object, inserted);
  if (inserted) up.interned++;
  if (block && __atomic_load_n(&block.owner, __ATOMIC_ACQUIRE) == inner) _mark_slot(block, slot);
  else if (promotion) _push_promotion(inner, promotion);
  else Scope.move(alloc, &up.scope);
  inner.promoted++;
  return 1;
}

static inline unsigned _slot_index(PoolBlock block, void *alloc) =>
  ((char *) alloc - _data(block)) / pool_class_sizes[block.class_index];

/* Classification reads only immutable backing extents. */
static PoolBlock _block_of(void *alloc) => _find_block(alloc);

static void _mark_slot(PoolBlock block, unsigned slot) {
  uint64_t mask = (uint64_t) 1 << (slot % 64), *word = &block.keep[slot / 64];
  if (*word & mask) return;
  *word |= mask;
  block.keep_count++;
}

static void _push_promotion(Pool inner, PoolPromotion promotion) {
  promotion.next = inner.promotions;
  inner.promotions = promotion;
}

/* Recorded promotions mark their slots first, so each block's keep count is
   complete before the block moves to the parent or the depot. */
module void _release_blocks(Pool inner) {
  for (PoolPromotion p = inner.promotions; p; p = p.next)
    _mark_slot(p.block, p.slot);
  PoolBlock heads[POOL_DEPOT_COUNT] = {0}, tails[POOL_DEPOT_COUNT] = {0};
  size_t count = 0, bytes = 0;
  PoolBlock block = inner.blocks;
  while (block) {
    PoolBlock next = block.next;
    if (inner.up && block.keep_count) _transfer(block, inner.up);
    else {
      int index = _depot_index(block.bytes);
      _reset(block, NULL);
      block.next = heads[index];
      heads[index] = block;
      if (!tails[index]) tails[index] = block;
      count++;
      bytes += block.bytes;
    }
    block = next;
  }
  _storage_lock();
  for (int i = 0; i < POOL_DEPOT_COUNT; i++)
    if (heads[i]) {
      tails[i].next = pool_depot[i];
      pool_depot[i] = heads[i];
    }
  pool_active_blocks -= count;
  pool_active_bytes -= bytes;
  pool_depot_blocks += count;
  pool_depot_bytes += bytes;
  _storage_unlock();
  inner.blocks = NULL;
  for (int i = 0; i < POOL_CLASS_COUNT; i++) inner.current[i] = NULL;
}

static void _depot_push(PoolBlock block) {
  int depot_index = _depot_index(block.bytes);
  _reset(block, NULL);
  block.next = pool_depot[depot_index];
  pool_depot[depot_index] = block;
  pool_active_blocks--;
  pool_active_bytes -= block.bytes;
  pool_depot_blocks++;
  pool_depot_bytes += block.bytes;
}

static void _transfer(PoolBlock block, Pool parent) {
  _free_unkept(block);
  __atomic_store_n(&block.owner, parent, __ATOMIC_RELEASE);
  block.keep_count = 0;
  memset(block.keep, 0, sizeof block.keep);
  _link(block, parent);
}

/* Rebuilds the free list from the handed-out slots that are not kept,
   lowest slot first. */
static void _free_unkept(PoolBlock block) {
  unsigned count = block.used / pool_class_sizes[block.class_index];
  block.free = NULL;
  for (unsigned slot = count; slot-- > 0;)
    if (!_slot_kept(block, slot)) _push_free(block, _slot(block, slot));
}

static inline void *_slot(PoolBlock block, unsigned slot) =>
  _data(block) + slot * pool_class_sizes[block.class_index];

static int _slot_kept(PoolBlock block, unsigned slot) {
  uint64_t mask = (uint64_t) 1 << (slot % 64);
  return (block.keep[slot / 64] & mask) != 0;
}

module void _storage_initialize(void) {
  if (__atomic_load_n(&pool_storage_ready, __ATOMIC_ACQUIRE)) return;
  _storage_lock();
  defer _storage_unlock();
  if (__atomic_load_n(&pool_storage_ready, __ATOMIC_ACQUIRE)) return;
  Scope.shutdown_hook(_storage_shutdown);
  __atomic_store_n(&pool_storage_ready, 1, __ATOMIC_RELEASE);
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
  while (pool_index) {
    PoolIndex previous = pool_index.previous;
    free(pool_index);
    pool_index = previous;
  }
  pool_index_used = 0;
  pool_index_version = 0;
  pool_index_complete = 1;
  for (int i = 0; i < POOL_DEPOT_COUNT; i++) pool_depot[i] = NULL;
  pool_backing_bytes = 0;
  pool_active_blocks = pool_active_bytes = 0;
  pool_depot_blocks = pool_depot_bytes = 0;
  __atomic_store_n(&pool_storage_ready, 0, __ATOMIC_RELEASE);
}
