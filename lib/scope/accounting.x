/*  accounting.x -- scope accounting */

static typedef struct ScopeName {
  Scope scope, char *name, struct ScopeName *next;
} *ScopeName;

/** Returns the diagnostic name of `scope`, or NULL if it has none.
    The string belongs to the allocator's name registry and stays valid until
    the scope is destroyed; do not free it. A scope from `Scope.new`, and one
    the runtime created implicitly for the first allocation into an empty
    slot, both have no name.
*/
const char *Scope.name(Scope scope) {
  _require_running();
  ScopeName node = _find_name(scope);
  return node ? node.name : NULL;
}

/* scope names

   Named scopes share one registry, guarded by the metadata mutex. The
   exit-time leak report lists each registered name with its allocation
   count. */

static ScopeName scope_names;

static pthread_mutex_t scope_metadata_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

module void _register_name(Scope scope, const char *name) {
  if (!name) return;
  size_t length = strlen(name);
  if (length == SIZE_MAX) raise %(size-limit);
  ScopeName node = _raw_malloc(sizeof(struct ScopeName));
  char *copy = _raw_malloc(length + 1);
  memcpy(copy, name, length + 1);
  node.scope = scope;
  node.name = copy;
  _metadata_lock();
  node.next = scope_names;
  scope_names = node;
  _metadata_unlock();
}

static ScopeName _find_name(Scope scope) {
  _metadata_lock();
  ScopeName node = scope_names;
  while (node && node.scope != scope) node = node.next;
  _metadata_unlock();
  return node;
}

module void _unregister_name(Scope scope) {
  _metadata_lock();
  ScopeName *link = &scope_names;
  while (*link && (*link).scope != scope) link = &(*link).next;
  ScopeName node = *link;
  if (node) {
    *link = node.next;
    _raw_free(node.name);
    _raw_free(node);
  }
  _metadata_unlock();
}

static void _metadata_lock(void) {
  if (pthread_mutex_lock(&scope_metadata_mutex))
    _raw_fatal("could not lock metadata");
}

static void _metadata_unlock(void) {
  if (pthread_mutex_unlock(&scope_metadata_mutex))
    _raw_fatal("could not unlock metadata");
}

// statistics

static atomic_size_t scope_allocation_calls, scope_reallocation_calls;
static atomic_size_t scope_free_calls;
static atomic_size_t scope_requested_bytes, scope_largest_request;
static atomic_size_t scope_live_requested_bytes;
static atomic_size_t scope_peak_live_requested_bytes;

/** Returns a snapshot of the allocator's counters.
    `live_allocations` and `live_scopes` are derived from the call counts, so
    read them before and after a routine to check that it leaves nothing
    behind. The snapshot also carries
    `allocation_calls`, `reallocation_calls`, `free_calls`,
    `scope_creations`, `scope_destructions`, `requested_bytes`,
    `largest_request`, `live_requested_bytes`, and
    `peak_live_requested_bytes`. Requested bytes are cumulative traffic;
    live requested bytes are the exact current managed payload total. Stats
    remain valid after shutdown.

    ```x2c
    ~int main(void) {
    size_t before = Scope.stats().live_allocations;
    Scope.retain();
    char *scratch = xmalloc(128);
    scratch[0] = 0;
    Scope.release();
    printf("reclaimed = %d\n", Scope.stats().live_allocations == before);
    ~  return 0;
    ~}
    ```
*/
ScopeStats Scope.stats(void) {
  ScopeStats stats = {
    .reallocation_calls = atomic_load(&scope_reallocation_calls),
    .requested_bytes = atomic_load(&scope_requested_bytes),
    .largest_request = atomic_load(&scope_largest_request),
    .live_requested_bytes = atomic_load(&scope_live_requested_bytes),
    .peak_live_requested_bytes =
      atomic_load(&scope_peak_live_requested_bytes)
  };
  do {
    stats.allocation_calls = atomic_load(&scope_allocation_calls);
    stats.free_calls = atomic_load(&scope_free_calls);
  } while (stats.free_calls > stats.allocation_calls);
  do {
    stats.scope_creations = atomic_load(&scope_creations);
    stats.scope_destructions = atomic_load(&scope_destructions);
  } while (stats.scope_destructions > stats.scope_creations);
  stats.live_allocations = stats.allocation_calls - stats.free_calls;
  stats.live_scopes = stats.scope_creations - stats.scope_destructions;
  return stats;
}

module void _record_allocation(size_t size) {
  atomic_fetch_add(&scope_allocation_calls, 1);
  _record_request(size);
  _record_live_add(size);
}

module void _record_resize(size_t old_size, size_t size) {
  atomic_fetch_add(&scope_reallocation_calls, 1);
  _record_request(size);
  if (size >= old_size) _record_live_add(size - old_size);
  else _record_live_remove(old_size - size);
}

module void _record_free(size_t size) {
  atomic_fetch_add(&scope_free_calls, 1);
  _record_live_remove(size);
}

static void _record_request(size_t size) {
  atomic_fetch_add_explicit(
    &scope_requested_bytes, size, memory_order_relaxed);
  size_t largest = atomic_load(&scope_largest_request);
  while (size > largest && !atomic_compare_exchange_weak(
    &scope_largest_request, &largest, size)) {}
}

static void _record_live_add(size_t size) {
  size_t live = atomic_fetch_add_explicit(
    &scope_live_requested_bytes, size, memory_order_relaxed) + size;
  size_t peak = atomic_load(&scope_peak_live_requested_bytes);
  while (live > peak && !atomic_compare_exchange_weak(
    &scope_peak_live_requested_bytes, &peak, live)) {}
}

static void _record_live_remove(size_t size) {
  atomic_fetch_sub_explicit(
    &scope_live_requested_bytes, size, memory_order_relaxed);
}

module void _report_leaks(void) {
  ScopeStats stats = Scope.stats();
  if (!stats.live_scopes && !stats.live_allocations &&
      atomic_load(&raw_alloc_count) == atomic_load(&raw_free_count))
    return;
  fprintf(stderr, "Scope leak detected:\n");
  fprintf(stderr, "\tlive_scopes: %zu\n", stats.live_scopes);
  fprintf(stderr, "\tlive_allocations: %zu\n", stats.live_allocations);
  for (ScopeName node = scope_names; node; node = node.next)
    fprintf(
      stderr, "\tscope \"%s\": %zu allocations\n", node.name,
      _allocation_count(node.scope));
  size_t raw_allocs = atomic_load(&raw_alloc_count);
  size_t raw_frees = atomic_load(&raw_free_count);
  if (raw_allocs != raw_frees)
    fprintf(
      stderr, "\tlive_backing_allocations: %zu\n", raw_allocs - raw_frees);
}

static size_t _allocation_count(Scope s) {
  size_t count = 0;
  for (ScopeAlloc alloc = s ? s.first : NULL; alloc;
       alloc = alloc.next)
    count++;
  return count;
}

module void _free_name_registry(void) {
  while (scope_names) {
    ScopeName next = scope_names.next;
    _raw_free(scope_names.name);
    _raw_free(scope_names);
    scope_names = next;
  }
}
