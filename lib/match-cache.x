/*  match-cache.x -- caches of prepared Match plans

    Copyright (c) 2026 Gary William Flake.

    A MatchCache keeps immutable prepared plans under the canonical identity
    of their patterns and lends them through leases. The `List.match` family
    runs through the active default cache, which is Context-local while a
    Context is open and otherwise thread-local.
*/

#pragma once

$(import "error-macros.xmacro")
#include "match.x"

/** Cache pressure is the acquire status beyond MachinePrepare: every slot is
    leased, so none can be recycled.
*/
#define MATCH_CACHE_PRESSURE 3

/** Names an explicit cache of immutable prepared Match plans.
    A cache is not synchronized. Its caller must serialize access, keep every
    admitted pattern value alive until disposal, and dispose it when no lease
    remains active.
*/
typedef struct MatchCache *MatchCache;

/** Represents one acquired use of a cached or transient Match plan.
    A cached lease pins its entry; a transient lease owns its plan. Initialize
    it only through `MatchCache.acquire` and call `MatchLease.release` on every
    exit after acquisition returns, including a pressure result.
*/
typedef struct MatchLease {
  MatchCache cache;
  MatchPlan transient_plan;
  unsigned long generation;
  int slot, active;
} MatchLease;

#pragma private

#include <assert.h>
#include <string.h>
#include "pool.x"
#include "scope.x"

/* the plan cache

   The cache owns immutable prepared programs only, never execution state.
   It keys an admitted pattern by its canonical identity, which `Context`
   and the owning pool guarantee for the cache's lifetime; that is why the
   cache is Context-local and is closed before its Context's canonical pool.

   Entries are recycled by deterministic LRU; positive entries are pinned
   while leased, so eviction can never free a program under an active
   execution, and leases carry the entry generation so a stale lease can
   never validate a recycled slot. Raw key zero (the inadmissible null-pointer
   Var) is rejected before the admission memos, whose direct-mapped
   collisions force a fresh admission walk, never a false admission. A
   refusal is memoized as well; refusing only sends a pattern through a
   transient plan, so a stale refusal costs nothing but that preparation. */

#define MATCH_ADMITTED_MEMO 256

typedef struct MatchCacheEntry {
  unsigned long key;
  MatchPlan plan;
  unsigned long generation;
  int occupied, pin_count, bucket_next, lru_prev, lru_next;
} MatchCacheEntry;

struct MatchCache {
  Scope scope;
  MatchCacheEntry *entries;
  int *buckets;
  int capacity, bucket_count, size, lru_head, active_leases;
  unsigned long next_generation, pool_epoch;
  unsigned long admitted_memo[MATCH_ADMITTED_MEMO];
  unsigned long refused_memo[MATCH_ADMITTED_MEMO];
};

/** Acquires a lease for a cached prepared pattern.
    `cache` and `lease` must be nonnull, and `owner` names the operation a
    fence diagnostic should report. The lease is initialized on every
    returning path. An admitted pattern reuses or creates an LRU entry; an
    inadmissible pattern gets a transient plan owned by the lease. Returns the
    plan's `MachinePrepare` status, or `MATCH_CACHE_PRESSURE` when every entry
    is pinned. Release the lease after any returned status; releasing the
    inactive pressure lease is a no-op.
    Raises: `<size-limit>` when `pattern` exceeds a lowering limit. Such a
    pattern compiles to no program, so it is never cached and never leased.
    `<alloc-fail>` may also be raised while preparing or growing storage.
*/
int MatchCache.acquire(
  MatchCache m, Var pattern, MatchLease &lease, const char *owner) {
  lease = (MatchLease) {.slot = -1};
  if (!m._admitted(pattern)) return m._transient(pattern, &lease, owner);
  unsigned long key = pattern.u64;
  int slot = m._find(key);
  if (slot >= 0) {
    m._touch(slot);
    m._activate(slot, &lease);
    return m.entries[slot].plan.status;
  }
  slot = m.size < m.capacity ? m._free_slot() : m._victim();
  if (slot < 0) return MATCH_CACHE_PRESSURE;
  MatchPlan plan = m._prepare(pattern, owner);
  if (m.entries[slot].occupied) m._remove(slot);
  m._insert(slot, key, plan);
  m._activate(slot, &lease);
  return plan.status;
}

/* An inadmissible pattern gets a plan its lease owns. */
static int MatchCache._transient(
  MatchCache cache, Var pattern, MatchLease *lease, const char *owner) {
  MatchPlan plan = _unfenced(MatchPlan.prepare(pattern), owner);
  lease.cache = cache;
  lease.transient_plan = plan;
  lease.active = 1;
  cache.active_leases++;
  return plan.status;
}

/* Prepares an entry's plan in the cache's scope. An unusable plan never
   reaches an entry or occupies a cache slot. */
static MatchPlan MatchCache._prepare(
  MatchCache cache, Var pattern, const char *owner) {
  MatchPlan plan = NULL;
  $scope(&cache.scope) { plan = MatchPlan.prepare(pattern); }
  return _unfenced(plan, owner);
}

/* Frees a fenced plan and raises its fence; returns any other plan. */
static MatchPlan _unfenced(MatchPlan plan, const char *owner) {
  if (plan.status == MACHINE_INELIGIBLE) {
    const char *reason = plan.reason;
    plan.free();
    MatchPlan.raise_ineligible(reason, owner);
  }
  return plan;
}

/* Installs `plan` under `key` as the most recent entry, with a fresh
   generation. */
static void MatchCache._insert(
  MatchCache cache, int slot, unsigned long key, MatchPlan plan) {
  MatchCacheEntry *entry = &cache.entries[slot];
  entry.key = key;
  entry.plan = plan;
  entry.occupied = 1;
  entry.generation = ++cache.next_generation;
  int bucket = cache._bucket(key);
  entry.bucket_next = cache.buckets[bucket];
  cache.buckets[bucket] = slot;
  cache._link_mru(slot);
  cache.size++;
}

static int MatchCache._admitted(MatchCache cache, Var pattern) {
  unsigned long key = pattern.u64;
  if (!key) return 0;
  // a level was released under this table; nothing it held can be trusted
  if (!cache._resync()) return 0;
  int slot = _memo_slot(key);
  if (cache.admitted_memo[slot] == key) return 1;
  if (cache.refused_memo[slot] == key) return 0;
  // an entry borrows its pattern only until its level is released
  if (!MatchPlan.borrowable(pattern, 0)) {
    cache.refused_memo[slot] = key;
    return 0;
  }
  cache.admitted_memo[slot] = key;
  return 1;
}

/* Drops every entry a released level could have invalidated and adopts the
   new epoch. A pinned entry is still executing, so the table keeps its
   contents and stays refused until a later call finds no lease outstanding. */
static int MatchCache._resync(MatchCache cache) {
  unsigned long epoch = Pool.epoch();
  if (cache.pool_epoch == epoch) return 1;
  if (cache.active_leases) return 0;
  for (int slot = 0; slot < cache.capacity; slot++)
    if (cache.entries[slot].occupied) cache._remove(slot);
  memset(cache.admitted_memo, 0, sizeof(cache.admitted_memo));
  memset(cache.refused_memo, 0, sizeof(cache.refused_memo));
  cache.pool_epoch = epoch;
  return 1;
}

/* The memo indexes through its own small fold of the raw bits so
   admission consults no cache-table state and the table hash is
   computed only after admission succeeds. */
static int _memo_slot(unsigned long key) =>
  (int) ((key * 0x9e3779b97f4a7c15UL >> 48) & (MATCH_ADMITTED_MEMO - 1));

/* cache entries

   Each bucket chains its entries through `bucket_next`. The LRU ring links
   every entry: its head is the most recent entry, and the head's
   predecessor the least recent. */

static int MatchCache._find(MatchCache cache, unsigned long key) {
  for (int slot = cache.buckets[cache._bucket(key)]; slot >= 0;
       slot = cache.entries[slot].bucket_next)
    if (cache.entries[slot].occupied && cache.entries[slot].key == key)
      return slot;
  return -1;
}

static int MatchCache._bucket(MatchCache cache, unsigned long key) =>
  (int) (_cache_mix(key) % (unsigned long) cache.bucket_count);

static unsigned long _cache_mix(unsigned long key) {
  key ^= key >> 33;
  key *= 0xff51afd7ed558ccdUL;
  key ^= key >> 33;
  key *= 0xc4ceb9fe1a85ec53UL;
  return key ^ (key >> 33);
}

static void MatchCache._touch(MatchCache cache, int slot) {
  int head = cache.lru_head;
  if (head == slot) return;
  if (cache.entries[head].lru_prev == slot) {
    cache.lru_head = slot;
    return;
  }
  cache._unlink(slot);
  cache._link_mru(slot);
}

static void MatchCache._unlink(MatchCache cache, int slot) {
  MatchCacheEntry *entry = &cache.entries[slot];
  cache.entries[entry.lru_prev].lru_next = entry.lru_next;
  cache.entries[entry.lru_next].lru_prev = entry.lru_prev;
  if (cache.lru_head == slot)
    cache.lru_head = entry.lru_next == slot ? -1 : entry.lru_next;
}

static void MatchCache._link_mru(MatchCache cache, int slot) {
  MatchCacheEntry *entry = &cache.entries[slot];
  int head = cache.lru_head;
  entry.lru_next = head < 0 ? slot : head;
  entry.lru_prev = head < 0 ? slot : cache.entries[head].lru_prev;
  cache.entries[entry.lru_prev].lru_next = slot;
  cache.entries[entry.lru_next].lru_prev = slot;
  cache.lru_head = slot;
}

static int MatchCache._free_slot(MatchCache m) {
  for (int i = 0; i < m.capacity; i++) if (!m.entries[i].occupied) return i;
  return -1;
}

/* The least recent entry that no lease pins, or -1. */
static int MatchCache._victim(MatchCache cache) {
  int slot = cache.entries[cache.lru_head].lru_prev;
  for (int i = 0; i < cache.size; i++) {
    if (!cache.entries[slot].pin_count) return slot;
    slot = cache.entries[slot].lru_prev;
  }
  return -1;
}

static void MatchCache._remove(MatchCache cache, int slot) {
  MatchCacheEntry *entry = &cache.entries[slot];
  assert(entry.occupied && !entry.pin_count);
  int *link = &cache.buckets[cache._bucket(entry.key)];
  while (*link >= 0 && *link != slot) link = &cache.entries[*link].bucket_next;
  assert(*link == slot);
  *link = entry.bucket_next;
  cache._unlink(slot);
  entry.plan.free();
  entry.occupied = 0;
  cache.size--;
}

// leases

/* Pins `slot` for `lease`, which records the entry's generation. */
static void MatchCache._activate(MatchCache m, int slot, MatchLease *lease) {
  MatchCacheEntry *entry = &m.entries[slot];
  lease.cache = m;
  lease.generation = entry.generation;
  lease.slot = slot;
  lease.active = 1;
  m.active_leases++;
  entry.pin_count++;
}

/** Releases the prepared program held by `lease`.
    Releasing an inactive lease has no effect. A successful release destroys a
    transient plan or unpins its cached entry and makes the lease inactive.
    Raises: `<bad-arg>` when lease is NULL and `<bad-state>` when its cache or
    entry state is inconsistent. The failure leaves the lease active.
*/
void MatchLease.release(MatchLease *lease) {
  if (!lease) raise %(bad-arg (owner "MatchLease.release"));

  if (!lease.active) return;
  if (lease.transient_plan) {
    if (!lease.cache || lease.cache.active_leases <= 0)
      raise %(bad-state (owner "MatchLease.release"));

    lease.transient_plan.free();
    lease.transient_plan = NULL;
    lease.cache.active_leases--;
    lease.active = 0;
    return;
  }
  MatchCacheEntry *entry = lease._entry();
  if (!entry || lease.cache.active_leases <= 0 || entry.pin_count <= 0)
    raise %(bad-state (owner "MatchLease.release"));

  lease.cache.active_leases--;
  entry.pin_count--;
  lease.active = 0;
}

/* The plan a lease holds while its acquisition stays active. */
static MatchPlan MatchLease._plan(MatchLease *lease) =>
  lease.transient_plan ? lease.transient_plan
                       : lease.cache.entries[lease.slot].plan;

/* The entry an active cached lease pins, or NULL once the slot is empty or
   recycled under a newer generation. */
static MatchCacheEntry *MatchLease._entry(MatchLease *lease) {
  MatchCache cache = lease.cache;
  if (!cache || lease.slot < 0 || lease.slot >= cache.capacity) return NULL;
  MatchCacheEntry *entry = &cache.entries[lease.slot];
  return entry.occupied && entry.generation == lease.generation ? entry : NULL;
}

/* cached consumers

   Each adapter preserves its consumer's result and executes only a prepared
   program. Malformed, cache-pressure, and machine-error cases do not match;
   a fenced pattern raised out of `acquire` and never reaches an adapter. */

/* Declares `$plan`, the program `$cache` prepared for `$pattern`, leased
   until the scope exits, or NULL when acquisition prepared none. */
macro Stmt $match.plan(
  Name $plan, Expr $cache, Expr $pattern, Expr $owner) {
  MatchLease storage;
  MatchLease *lease = &storage;
  int status = $cache.acquire($pattern, *lease, $owner);
  defer lease.release();
  MatchPlan $plan = status == MACHINE_PREPARED ? lease._plan() : NULL;
}

/** Matches through `cache` into caller-owned positional storage.
    Returns 1 only after atomically committing a valid buffer. A miss,
    malformed pattern, invalid buffer, cache pressure, or machine error returns
    0 and leaves it unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or matching.
*/
int MatchCache.try_capture(
  MatchCache cache, List input, Var pattern, MatchCaptureBuffer &?captures,
  const char *owner) {
  $match.plan(plan, cache, pattern, owner);
  return plan && plan.try_capture(input, captures) == 1;
}

/** Matches through `cache`, writing bindings on success.
    `out_bindings` must be nonnull. Returns 0 and leaves it unchanged for a
    miss, malformed pattern, cache pressure, or machine error. Successful
    binding shape and order follow `MatchPlan.execute`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or publishing.
*/
int MatchCache.try_match(
  MatchCache cache, List input, Var pattern, List &?out_bindings,
  const char *owner) {
  $match.plan(plan, cache, pattern, owner);
  return plan && plan.try_match(input, out_bindings) == 1;
}

/** Searches through `cache`, writing the first match and bindings.
    Both outputs must be nonnull. Returns 0 and leaves them unchanged on a
    miss, malformed pattern, cache pressure, or machine error. Traversal order
    follows `MatchPlan.try_search`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or constructing bindings.
*/
int MatchCache.try_search(
  MatchCache cache, List input, Var pattern, Var &?out_match,
  List &?out_bindings, const char *owner) {
  $match.plan(plan, cache, pattern, owner);
  return plan && plan.try_search(input, out_match, out_bindings) == 1;
}

/** Searches through `cache`, writing every match.
    `out_results` must be nonnull. It receives the reverse-visitation result
    `List`, or `nil` when there are no matches, the pattern is malformed, cache
    pressure prevents execution, or the machine fails. Returns 1 exactly when
    that `List` is nonempty.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or constructing results.
*/
int MatchCache.search(
  MatchCache cache, List input, Var pattern, List &out_results,
  const char *owner) {
  $match.plan(plan, cache, pattern, owner);
  List results = NULL;
  if (plan) plan.search(input, results);
  out_results = results;
  return results != NULL;
}

/** `Match`-replaces through `cache`, writing the replacement on success.
    `out` must be nonnull. Returns 0 and leaves it unchanged on a miss,
    malformed pattern, cache pressure, or machine error. The successful result
    may be any `Var`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or replacing.
*/
int MatchCache.try_match_replace(
  MatchCache cache, List input, Var pattern, Var template, Var &?out,
  const char *owner) {
  $match.plan(plan, cache, pattern, owner);
  return plan && plan.try_match_replace(input, template, out) == 1;
}

/** Replaces every match through `cache` from the leaves upward.
    `out` must be nonnull. A completed prepared traversal returns 1 and writes
    its result even when nothing matched. A malformed pattern, cache pressure,
    or machine error returns 0 and writes `input` unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, traversing, or replacing.
*/
int MatchCache.search_replace(
  MatchCache cache, List input, Var pattern, Var template, List &out,
  const char *owner) {
  $match.plan(plan, cache, pattern, owner);
  List result = input;
  int answered = plan && plan.search_replace(input, template, result) >= 0;
  out = result;
  return answered;
}

/* default caches

   The active default cache is Context-local when a Context is open and
   otherwise thread-local, and it is created on first use. Entries may borrow
   runtime canonical identities, so a flush must precede the release of a
   pool that owns an admitted pattern. */

typedef struct MatchContextState {
  struct MatchContextState *prev, MatchCache cache;
} *MatchContextState;

static threaded struct {
  MatchCache plan_cache;
  MatchContextState context_top;
} match_thread;

/** Returns the active default `Match` cache, creating it on first use.
    Raises: `<alloc-fail>` when the cache cannot be created.
*/
MatchCache MatchCache.current(void) {
  MatchCache *slot = _default_slot();
  if (!*slot) *slot = MatchCache.new(256);
  x2c_match_initialize();
  return *slot;
}

/* The top Context's cache when a Context is open, or else the thread's. */
static MatchCache *_default_slot(void) {
  MatchContextState top = match_thread.context_top;
  return top ? &top.cache : &match_thread.plan_cache;
}

/** Destroys the active `Context`-local or thread-local `Match` cache.
    A missing cache is ignored; the next `Match` recreates it lazily. Static
    compiler capture sites are unaffected.
    Raises: `<bad-state>` when a lease remains active. The failure leaves the
    cache installed.
*/
void MatchCache.flush_default(void) {
  MatchCache *slot = _default_slot();
  if (!*slot) return;
  (*slot).dispose();
  *slot = NULL;
}

/** Opens one `Context`-local default `Match`-cache state.
    The returned opaque token becomes the top of a thread-local LIFO stack;
    its cache is created only on first use. The token is allocated in the
    active `Scope` and must be passed to `MatchCache.context_close` before that
    `Scope` ends.
    Raises: `<alloc-fail>` when the state cannot be allocated.
*/
void *MatchCache.context_open(void) {
  MatchContextState state = Scope.malloc(sizeof(struct MatchContextState));
  state.prev = match_thread.context_top;
  state.cache = NULL;
  match_thread.context_top = state;
  return state;
}

/** Disposes and removes the top `Context`'s default `Match` cache.
    A null token is ignored. Successful close restores the previous default;
    the token storage remains owned by its `Context` `Scope`.
    Raises: `<bad-state>` when `token` is not the top state or its cache has an
    active lease. The failure leaves the state installed.
*/
void MatchCache.context_close(void *token) {
  MatchContextState state = token;
  if (!state) return;
  if (match_thread.context_top != state)
    raise %(bad-state (owner "MatchCache.context_close"));

  if (state.cache) state.cache.dispose();
  match_thread.context_top = state.prev;
}

/** Disposes this thread's default `Match` plan cache.
    `x2c_thread_state_release` calls it before `Scope` releases the `Scope`
    that holds that cache; a thread that never matched has no cache and
    nothing happens. All default-cache leases and `Context` states must
    already be closed.
    Raises: `<bad-state>` when a lease remains active.
*/
void x2c_match_thread_release(void) {
  if (!match_thread.plan_cache) return;
  match_thread.plan_cache.dispose();
  match_thread.plan_cache = NULL;
}

// lifecycle

/** Creates a `MatchCache` retaining up to `capacity` prepared patterns.
    The returned cache owns a named `Scope` and is not synchronized. It borrows
    admitted pattern identities, so dispose it before their owning canonical
    pools. `MatchCache.dispose` is required after every lease is released.
    Raises: `<bad-arg>` when capacity is not positive, `<size-limit>` when its
    storage dimensions cannot be represented, and `<alloc-fail>` when cache
    storage cannot be allocated.
*/
MatchCache MatchCache.new(int capacity) {
  if (capacity <= 0)
    raise %(bad-arg (owner "MatchCache.new") (capacity $capacity));
  if (capacity > (INT_MAX - 1) / 2)
    raise %(size-limit (owner "MatchCache.new") (capacity $capacity));

  Scope owner = Scope.new_named("Match plan cache");
  Scope.push(&owner);
  MatchCache cache = Scope.calloc(1, sizeof(struct MatchCache));
  cache.scope = owner;
  cache.capacity = capacity;
  cache.bucket_count = capacity * 2 + 1;
  cache.lru_head = -1;
  cache.pool_epoch = Pool.epoch();
  cache.entries = Scope.calloc(capacity, sizeof(MatchCacheEntry));
  cache.buckets = Scope.malloc(sizeof(int) * cache.bucket_count);
  for (int i = 0; i < cache.bucket_count; i++) cache.buckets[i] = -1;
  Scope.pop();
  return cache;
}

/** Destroys a `Match` cache with no active leases.
    A null cache is ignored. Disposal frees all plans and cache storage and
    invalidates every alias.
    Raises: `<bad-state>` when a lease remains active. The failure leaves the
    cache intact.
*/
void MatchCache.dispose(MatchCache cache) {
  if (!cache) return;
  if (cache.active_leases) raise %(bad-state (owner "MatchCache.dispose"));

  for (int i = 0; i < cache.capacity; i++) {
    assert(!cache.entries[i].pin_count);
    if (cache.entries[i].occupied) cache.entries[i].plan.free();
  }
  Scope.destroy(cache.scope);
}
