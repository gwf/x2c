/*  interning.x -- pool interning */

static keyword loop $private.loop;

/* table

   `PoolTable` is the `Map` family over one-`Var` records: every entry maps a
   value to itself, so `key` and `val` name the same `Var`. */

static struct PoolRecord { union { Var key, val; }; };

$map.scaffold(
  PoolTable, struct PoolRecord, Var, Var,
  _record_key, _record_value, _reinsert_error, _insert_error,
  "PoolTable.reinsert", "PoolTable.insert");

$map.var.family(
  _table_hash, _table_key_equal, _table_value_equal, _table_value_valid);

$map.storage.family(
  PoolTable, struct PoolTable, Var, Var, unsigned, struct PoolRecord,
  _table_hash, _table_key_equal, _table_value_equal, _table_value_valid,
  _record_key, _record_value, _reinsert_error, _insert_error, 0);

/* The stored value equal to `key`, which hashes to `key_hash`, or `void`. */
static Var _get_hashed(
  PoolTable table, Var key, unsigned key_hash) {
  long index = table.find_hashed(&key, key_hash);
  return index < 0 ? void : *_record_key(table, (unsigned) index);
}

/* String construction already knows the bytes, length, and content hash.
   Probe the shared table without boxing a temporary String query. */
static String _get_string(
  PoolTable table, const char *bytes, int length, unsigned hash) {
  unsigned *hashes = table.hashes;
  unsigned mask = table.mask, start = hash & mask, capacity = table.capacity;
  for (unsigned distance = 0; distance < capacity; distance++) {
    unsigned index = (start + distance) & mask, stored = hashes[index];
    if (!stored) break;
    if (stored == hash) {
      Var entry = *_record_key(table, index);
      String string = entry.string_payload();
      if (string && strncmp(string, bytes, (size_t) length) == 0 &&
          ((const char *) string)[length] == '\0')
        return string;
    }
    if (((capacity + index - (stored & mask)) & mask) < distance) break;
  }
  return NULL;
}

/* Nonempty byte queries cannot match the null String. Native comparison
   cannot raise, so each acquired pool lock can be released directly. */
String x2c_pool_lookup_string(
  Pool inner, const char *bytes, int length, unsigned hash) {
  int threads_active = pool_multithreaded;
  for (Pool pool = inner; pool; pool = pool.up) {
    if (threads_active) _lock(pool);
    String found = _get_string(pool.table, bytes, length, hash);
    if (threads_active) _unlock(pool);
    if (found) return found;
  }
  return NULL;
}

/* The stored value equal to `object`, which is installed when absent. */
module Var _setdefault(
  PoolTable table, Var object, int &inserted) {
  return *table.get_or_insert(&object, &object, &inserted);
}

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
  /* Without workers no level can be contended, so the chain is probed
     without the locks and the `defer` that releases them. That registration
     measured 3% of a translation's instructions. */
  if (pool_multithreaded) return _lookup_locked(inner, key, key_hash);
  for (Pool pool = inner; pool; pool = pool.up) {
    Var found = _get_hashed(pool.table, key, key_hash);
    if (found is not void) return found;
  }
  return void;
}

/* `_get_hashed` raises for any cause from custom equality, so the
   branch mutex is released through one hoisted `defer`. A per-iteration
   `defer` measured 4% of a translation against 3% for this form. `locked` is
   the level whose mutex this call still holds. */
static Var _lookup_locked(Pool inner, Var key, unsigned key_hash) {
  Pool locked = NULL;
  defer _unlock(locked);
  for (Pool pool = inner; pool; pool = pool.up) {
    _lock(pool);
    locked = pool;
    Var found = _get_hashed(pool.table, key, key_hash);
    _unlock(pool);
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

    Ancestors are checked before the innermost fused table operation. `Pool`'s
    single-canonical-pointer invariant makes that order equivalent to outward
    shadowing while allowing the innermost table to be probed exactly once.
    A caller that has already searched the chain uses `Pool.intern_new`.

    Raises: `<bad-arg>` when `inner` or `alloc` is NULL. Table lookup and
    insertion causes propagate.
*/
Var Pool.intern(Pool inner, Var object, void *alloc) {
  if (!inner || !alloc) raise %(bad-arg (operation "Pool.intern"));
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
    else canonical = _intern_locked(inner, object, discard);
  }
  // See Pool.intern_new: the losing candidate is freed outside the lock.
  if (discard) inner.free(alloc);
  return canonical;
}

/* Probes and installs in `inner` alone, with the pool locked. Sets `discard`
   when a concurrent equal entry already holds the level. */
static Var _intern_locked(Pool inner, Var object, int &discard) {
  int inserted;
  Var stored = _setdefault(inner.table, object, inserted);
  if (inserted) inner.interned++;
  else discard = 1;
  return stored;
}

/** Returns the canonical value equal to `object`, installing it in `inner`.
    This is `Pool.intern` for a caller that has already searched the whole
    chain from `inner` outward and found nothing, so only the innermost level
    is probed. The fused table operation still decides the identity, which
    keeps one canonical pointer per equal value in `inner` even when another
    worker interns the same value first.

    Raises: `<bad-arg>` when `inner` or `alloc` is NULL. Table insertion
    causes propagate and leave the object unregistered.
*/
Var Pool.intern_new(Pool inner, Var object, void *alloc) {
  if (!inner || !alloc) raise %(bad-arg (operation "Pool.intern_new"));
  Var canonical;
  int discard = 0;
  {
    _lock(inner);
    defer _unlock(inner);
    canonical = _intern_locked(inner, object, discard);
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
    Raises: `<bad-arg>` when `inner` is NULL. Table insertion causes propagate
    and leave the object unregistered.
*/
void Pool.insert(Pool inner, Var object) {
  if (!inner) raise %(bad-arg (operation "Pool.insert"));
  _lock(inner);
  defer _unlock(inner);
  _insert_locked(inner, object);
}

/* Table insertion causes propagate and leave the object unregistered. */
static void _insert_locked(Pool inner, Var object) {
  inner.table.set_entry(&object, &object);
  inner.interned++;
}

/** Reports whether this exact level stores `key` as its canonical identity.
    Ancestors are not searched, and a null pool reports zero.
*/
int Pool.owns(Pool pool, Var key) {
  if (!pool) return 0;
  _lock(pool);
  defer _unlock(pool);
  return _owns_locked(pool, key);
}

module int _owns_locked(Pool pool, Var key) {
  Var found = _get_hashed(pool.table, key, key.hash());
  return found is not void && found.same(key);
}

// lifecycle

/** Returns a new named child of `inner` without making it thread-active.
    The child owns its control `Scope`, table, and mutex and must be released
    before `inner`. Use `Pool.open_named` instead to open a bracket that the
    canonical `String` and `List` operations allocate into.
    Raises: `<alloc-fail>` while building the child. A transfer destroys
    partial child resources and leaves `inner` unchanged; native mutex
    initialization failure aborts.
*/
Pool Pool.retain_named(Pool inner, const char *name) {
  _storage_initialize();
  unsigned capacity = _child_capacity(inner);
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
  $scope(&pool.scope)
    pool.table = PoolTable.new_table(NULL, capacity);
  finished = 1;
  return pool;
}

/* A child's table starts at the capacity the last released direct child's
   table reached. */
static unsigned _child_capacity(Pool inner) {
  if (!inner) return 2;
  _lock(inner);
  unsigned capacity = inner.child_capacity;
  _unlock(inner);
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
