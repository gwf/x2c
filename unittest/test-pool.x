/*  test-pool.x -- unit tests for nested interning pools */

#include "test-support.x"
#include "test-macros.x"
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>

typedef struct PoolThreadProbe {
  Pool parent;
  atomic_int started;
  atomic_int stop;
  int allocations;
} PoolThreadProbe;

static void *_pool_parent_allocator(void *data) {
  PoolThreadProbe *probe = data;
  atomic_store(&probe.started, 1);
  while (!atomic_load(&probe.stop)) {
    void *allocation = probe.parent.malloc(16);
    probe.parent.free(allocation);
    Scope scratch = Scope.new();
    Scope.malloc_in(&scratch, 16);
    scratch.destroy();
    probe.allocations++;
  }
  x2c_thread_state_release();
  return NULL;
}

static int pool_probe_hash_calls;
static Pool pool_probe_root;
static int pool_probe_grow, pool_probe_fail;

static String _root_text(Pool pool, const char *bytes) =>
  String.new_in(pool, bytes, strlen(bytes));

typedef struct PoolProbe {
  long value;
} PoolProbe;


static unsigned _pool_probe_hash(Var value) {
  pool_probe_hash_calls++;
  PoolProbe *probe = value;
  return (unsigned) probe.value;
}


static int _pool_probe_equal(Var a, Var b) {
  if (pool_probe_grow) {
    pool_probe_grow = 0;
    unsigned count = pool_probe_root.table.capacity;
    for (unsigned i = 0; i < count; i++) {
      char text[80];
      snprintf(text, sizeof(text), "root-reentrant-%u-%u", count, i);
      _root_text(pool_probe_root, text);
    }
  }
  if (pool_probe_fail) raise %(bad-arg (operation "root equality test"));
  PoolProbe *left = a, *right = b;
  return left.value == right.value;
}

static void pool_lookup_shadows_outward(void) {
  Pool root = Pool.retain_named(NULL, "test-pool-root");
  EXPECT_STR_EQ(root.scope.name(), "test-pool-root");
  EXPECT_TRUE(root.table.scope == root.scope);
  String alpha = "pool-alpha";
  root.insert(alpha);
  Pool child = root.retain_named("test-pool-child");
  EXPECT_STR_EQ(child.scope.name(), "test-pool-child");
  EXPECT_TRUE(child.table.scope == child.scope);
  Var from_parent = alpha;
  EXPECT_TRUE(child.lookup(alpha) == from_parent);
  String beta = "pool-beta";
  child.insert(beta);
  Var from_child = beta;
  EXPECT_TRUE(child.lookup(beta) == from_child);
  EXPECT_TRUE(root.lookup(beta) is void);
  EXPECT_TRUE(child.owns(beta));
  EXPECT_FALSE(child.owns(alpha));
  EXPECT_TRUE(root.owns(alpha));
  PoolStats stats = child.stats();
  EXPECT_INT_EQ(stats.depth, 2);
  EXPECT_INT_EQ(stats.interned, 1);
  child = child.release();
  EXPECT_TRUE(child == root);
  root.release();
}


static void pool_intern_uses_one_probe(void) {
  VarMethods methods = {
    .hash = _pool_probe_hash,
    .equal = _pool_probe_equal
  };
  EXPECT_TRUE(x2c_try_register_descriptor("pprobe", methods));

  Pool root = Pool.retain_named(NULL, "test-pool-one-probe");
  PoolProbe *first = root.malloc(sizeof(PoolProbe));
  first.value = 17;
  Var candidate = Var.new(<pprobe>, first);
  pool_probe_hash_calls = 0;
  Var canonical = root.intern(candidate, first);
  EXPECT_TRUE(canonical.same(candidate));
  EXPECT_INT_EQ(pool_probe_hash_calls, 1);
  EXPECT_INT_EQ(root.stats().interned, 1);

  ScopeStats before_duplicate = Scope.stats();
  PoolProbe *duplicate = root.malloc(sizeof(PoolProbe));
  duplicate.value = 17;
  Var repeated = Var.new(<pprobe>, duplicate);
  pool_probe_hash_calls = 0;
  Var existing = root.intern(repeated, duplicate);
  ScopeStats after_duplicate = Scope.stats();
  EXPECT_TRUE(existing.same(candidate));
  EXPECT_INT_EQ(pool_probe_hash_calls, 1);
  EXPECT_INT_EQ(after_duplicate.live_allocations,
                before_duplicate.live_allocations);
  EXPECT_INT_EQ(root.stats().interned, 1);

  Pool child = root.retain_named("test-pool-child-one-probe");
  PoolProbe *fresh = child.malloc(sizeof(PoolProbe));
  fresh.value = 23;
  Var fresh_candidate = Var.new(<pprobe>, fresh);
  pool_probe_hash_calls = 0;
  Var child_canonical = child.intern(fresh_candidate, fresh);
  EXPECT_TRUE(child_canonical.same(fresh_candidate));
  // One ancestor probe plus one innermost lookup-or-insert probe.
  EXPECT_INT_EQ(pool_probe_hash_calls, 2);
  EXPECT_INT_EQ(child.stats().interned, 1);
  Pool.release(child.release());
}


static void pool_reuses_child_table_capacity(void) {
  Pool root = Pool.retain_named(NULL, "test-pool-sized-root");
  Pool child = root.retain_named("test-pool-sized-child");
  for (int i = 0; i < 40; i++) child.insert(i + 1);
  unsigned learned = child.table.capacity;
  EXPECT_TRUE(learned > 2);
  child = child.release();
  EXPECT_TRUE(child == root);

  Pool next = root.retain_named("test-pool-sized-next");
  EXPECT_INT_EQ(next.table.capacity, learned);
  Pool.release(next.release());
}

static void pool_release_reclaims_wholesale(void) {
  Pool root = Pool.retain_named(NULL, "test-reclaim-root");
  Pool child = root.retain_named("test-reclaim-child");
  PoolStats before = child.stats();
  for (int i = 0; i < 100; i++) {
    char *cell = child.malloc(32);
    EXPECT_NOT_NULL(cell);
    snprintf(cell, 32, "cell-%d", i);
  }
  PoolStats during = child.stats();
  EXPECT_INT_EQ(during.allocation_calls - before.allocation_calls,
                Scope.accounting_enabled() ? 100 : 0);
  EXPECT_INT_EQ(during.requested_bytes - before.requested_bytes,
                Scope.accounting_enabled() ? 3200 : 0);
  EXPECT_TRUE(during.active_blocks > before.active_blocks);
  EXPECT_TRUE(during.active_bytes > before.active_bytes);
  child.release();
  PoolStats after = root.stats();
  EXPECT_TRUE(after.depot_blocks > during.depot_blocks);
  EXPECT_TRUE(after.depot_bytes > during.depot_bytes);
  EXPECT_TRUE(after.backing_bytes >= during.backing_bytes);
  root.release();
}


static void pool_reuses_small_slots_and_blocks(void) {
  Pool root = Pool.retain_named(NULL, "test-reuse-root");
  Pool child = root.retain_named("test-reuse-child");
  PoolProbe *candidate = child.malloc(sizeof(PoolProbe));
  candidate.value = 101;
  Var value = Var.new(<pprobe>, candidate);
  EXPECT_TRUE(child.intern(value, candidate).same(value));

  PoolProbe *duplicate = child.malloc(sizeof(PoolProbe));
  duplicate.value = 101;
  Var repeated = Var.new(<pprobe>, duplicate);
  EXPECT_TRUE(child.intern(repeated, duplicate).same(value));
  PoolStats before_slot = child.stats();
  PoolProbe *reused = child.malloc(sizeof(PoolProbe));
  PoolStats after_slot = child.stats();
  EXPECT_TRUE(reused == duplicate);
  EXPECT_INT_EQ(after_slot.slot_reuses,
                before_slot.slot_reuses + Scope.accounting_enabled());

  child.release();
  PoolStats before_block = root.stats();
  Pool next = root.retain_named("test-reuse-next");
  EXPECT_NOT_NULL(next.malloc(sizeof(PoolProbe)));
  PoolStats after_block = next.stats();
  EXPECT_INT_EQ(after_block.block_allocations, before_block.block_allocations);
  EXPECT_INT_EQ(after_block.block_reuses, before_block.block_reuses + 1);
  EXPECT_TRUE(after_block.active_bytes > before_block.active_bytes);
  EXPECT_TRUE(after_block.depot_bytes < before_block.depot_bytes);
  Pool.release(next.release());
}


static void pool_promote_is_pointer_stable(void) {
  Pool root = Pool.retain_named(NULL, "test-promote-root");
  Pool child = root.retain_named("test-promote-child");
  char *buf = child.malloc(32);
  strcpy(buf, "survivor");
  String key = "pool-promote-key";
  child.insert(key);
  EXPECT_FALSE(root.promote(key, buf));  // root has no parent
  EXPECT_FALSE(child.promote("pool-promote-miss", buf));
  EXPECT_TRUE(child.promote(key, buf));
  PoolStats promoted = child.stats();
  EXPECT_INT_EQ(promoted.promoted, 1);
  Pool released = child.release();
  EXPECT_TRUE(released == root);
  EXPECT_STR_EQ(buf, "survivor");
  EXPECT_TRUE(root.owns(key));
  PoolStats stats = root.stats();
  EXPECT_INT_EQ(stats.depth, 1);
  root.release();
}


static void pool_promote_transfers_partial_blocks(void) {
  Pool root = Pool.retain_named(NULL, "test-partial-root");
  Pool child = root.retain_named("test-partial-child");
  char *kept = child.malloc(16), *garbage = child.malloc(16);
  strcpy(kept, "kept");
  strcpy(garbage, "gone");
  String key = "pool-partial-key";
  child.insert(key);
  EXPECT_TRUE(child.promote(key, kept));
  child.release();
  EXPECT_STR_EQ(kept, "kept");
  EXPECT_TRUE(root.owns(key));
  EXPECT_TRUE(root.malloc(16) == garbage);
  root.release();
}


static void pool_promote_tracks_a_full_bitmap(void) {
  Pool root = Pool.retain_named(NULL, "test-bitmap-root");
  Pool child = root.retain_named("test-bitmap-child");
  char *kept[30];
  for (int i = 0; i < 30; i++) {
    kept[i] = child.malloc(32);
    snprintf(kept[i], 32, "bitmap-%d", i);
    child.insert(i + 1);
    EXPECT_TRUE(child.promote(i + 1, kept[i]));
  }
  child.release();
  for (int i = 0; i < 30; i++) {
    char expected[32];
    snprintf(expected, sizeof expected, "bitmap-%d", i);
    EXPECT_STR_EQ(kept[i], expected);
  }
  root.release();
}


static void pool_promote_crosses_multiple_levels(void) {
  Pool root = Pool.retain_named(NULL, "test-multi-root");
  Pool middle = root.retain_named("test-multi-middle");
  Pool inner = middle.retain_named("test-multi-inner");
  char *kept = inner.malloc(32);
  strcpy(kept, "multi-level survivor");
  String key = "pool-multi-key";
  inner.insert(key);
  EXPECT_TRUE(inner.promote(key, kept));
  EXPECT_TRUE(middle.promote(key, kept));
  inner.release();
  EXPECT_STR_EQ(kept, "multi-level survivor");
  middle.release();
  EXPECT_STR_EQ(kept, "multi-level survivor");
  EXPECT_TRUE(root.owns(key));
  root.release();
}


static void pool_large_promotion_retains_scope_path(void) {
  Pool root = Pool.retain_named(NULL, "test-large-root");
  Pool child = root.retain_named("test-large-child");
  char *kept = child.malloc(1024);
  strcpy(kept, "large survivor");
  String key = "pool-large-key";
  child.insert(key);
  EXPECT_TRUE(child.promote(key, kept));
  child.release();
  EXPECT_STR_EQ(kept, "large survivor");
  root.release();
}


static void pool_release_balances_scope_stats(void) {
  ScopeStats before = Scope.stats();
  Pool root = Pool.retain_named(NULL, "test-balance-root");
  Pool child = root.retain();
  child.malloc(64);
  root.malloc(64);
  Pool.release(child.release());
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_TRUE(Pool.release(NULL) == NULL);
}

static void pool_null_owner_failures_are_handleable(void) {
  int caught = 0;
  try Pool.insert(NULL, 1);
  catch %(bad-arg *): caught++;
  try Pool.malloc(NULL, 16);
  catch %(bad-arg *): caught++;
  int local = 0;
  try Pool.free(NULL, &local);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 3);
}

static void pool_string_bracket_and_wipe(void) {
  Pool.open_named("test-string-bracket");
  String kept = NULL;
  for (int i = 0; i < 200; i++) {
    String transient = String.printf("pool-transient-%d", i);
    if (i == 137) kept = transient;
  }
  ScopeStats during = Scope.stats();
  String promoted = kept.promote();
  EXPECT_TRUE(promoted == kept);  // promotion is pointer-stable
  Pool.close();
  ScopeStats after = Scope.stats();
  if (Scope.accounting_enabled())
    EXPECT_TRUE(after.live_allocations < during.live_allocations);
  else EXPECT_INT_EQ(after.live_allocations, 0);
  EXPECT_STR_EQ(kept, "pool-transient-137");
  // The survivor stays canonical: re-interning is a hit, not an alloc.
  PoolStats before_hit = Pool.stats(NULL);
  EXPECT_TRUE(String.new("pool-transient-137") == kept);
  PoolStats after_hit = Pool.stats(NULL);
  EXPECT_INT_EQ(after_hit.allocation_calls, before_hit.allocation_calls);
  // Wiped garbage lost its identity: re-interning allocates afresh.
  String again = String.new("pool-transient-0");
  PoolStats after_miss = Pool.stats(NULL);
  if (Scope.accounting_enabled())
    EXPECT_TRUE(after_miss.allocation_calls > after_hit.allocation_calls);
  else EXPECT_INT_EQ(after_miss.allocation_calls, 0);
  EXPECT_STR_EQ(again, "pool-transient-0");
}


static void pool_string_free_reuses_small_slot(void) {
  String first = String.malloc(24);
  EXPECT_NOT_NULL(first);
  first.free();
  PoolStats before = Pool.stats(NULL);
  String reused = String.malloc(24);
  PoolStats after = Pool.stats(NULL);
  EXPECT_TRUE(reused == first);
  EXPECT_INT_EQ(after.slot_reuses,
                before.slot_reuses + Scope.accounting_enabled());
  reused.free();
}

static void pool_list_bracket_promotes_result(void) {
  Pool.open_named("test-list-bracket");
  for (int i = 0; i < 100; i++) {
    String garbage = String.printf("pool-garbage-%d", i);
    List cell = $(garbage, i);
    EXPECT_INT_EQ(cell.len(), 2);
  }
  String label = String.new("pool-keep-me");
  List nested = %(1 2 3);
  List result = $(label, 42, nested);
  List promoted = result.promote();
  EXPECT_TRUE(promoted == result);  // pointer stability
  Pool.close();
  EXPECT_INT_EQ(result.len(), 3);
  EXPECT_STR_EQ(result.car().string(), "pool-keep-me");
  Var answer = 42;
  EXPECT_VAR_EQ(result[1], answer);
  EXPECT_TRUE(result[2].list() == nested);
  // Ancestor-owned structure: promoting again is a harmless no-op.
  EXPECT_TRUE(result.promote() == result);
  // The nested tail stayed canonical through the wipe.
  EXPECT_TRUE(%(1 2 3) == nested);
}

static void pool_unpromoted_identity_is_wiped(void) {
  // volatile seed keeps these cells out of the static literal machinery
  volatile int seed = 9100;
  Pool.open_named("test-list-wipe");
  List doomed = cons(seed + 1, cons(seed + 2, cons(seed + 3, NULL)));
  EXPECT_INT_EQ(doomed.len(), 3);
  Pool.close();
  PoolStats before = Pool.stats(NULL);
  List again = cons(seed + 1, cons(seed + 2, cons(seed + 3, NULL)));
  PoolStats after = Pool.stats(NULL);
  if (Scope.accounting_enabled())
    EXPECT_TRUE(after.allocation_calls > before.allocation_calls);
  else EXPECT_INT_EQ(after.allocation_calls, 0);
  EXPECT_INT_EQ(again.len(), 3);
}

static void pool_try_own_reports_lifetime_safety(void) {
  String permanent_string = "pool-permanent-string";
  List permanent_list = %(pool-permanent-list);
  EXPECT_TRUE(String.try_own(NULL));
  EXPECT_TRUE(List.try_own(NULL));
  EXPECT_TRUE(permanent_string.try_own());
  EXPECT_TRUE(permanent_list.try_own());

  String transient_string = String.malloc(16);
  strcpy(transient_string, "not interned");
  EXPECT_FALSE(transient_string.try_own());
  transient_string.free();

  List transient_list = xmalloc(sizeof(struct List));
  transient_list.car = 1;
  transient_list.cdr = NULL;
  EXPECT_FALSE(transient_list.try_own());

  Pool.open_named("test-own-values");
  EXPECT_TRUE(permanent_string.try_own());
  EXPECT_TRUE(permanent_list.try_own());
  String child_string = String.new("pool-child-string");
  List child_list = %($child_string pool-child-list);
  EXPECT_TRUE(child_string.try_own());
  EXPECT_TRUE(child_list.try_own());
  Pool.close();
  EXPECT_STR_EQ(child_string, "pool-child-string");
  EXPECT_TRUE(child_list == %("pool-child-string" pool-child-list));
}

static void string_is_permanent_asks_without_promoting(void) {
  String permanent = "pool-permanent-string";
  EXPECT_TRUE(String.is_permanent(NULL));
  EXPECT_TRUE(String.is_permanent(""));
  EXPECT_TRUE(permanent.is_permanent());

  String transient = String.malloc(16);
  strcpy(transient, "not interned");
  EXPECT_FALSE(transient.is_permanent());
  transient.free();

  Pool.open_named("test-is-permanent");
  String nested = String.new("pool-nested-string");
  EXPECT_FALSE(nested.is_permanent());
  EXPECT_TRUE(permanent.is_permanent());
  Pool.close();
}

static void pool_bracket_requires_an_open_child(void) {
  int caught = 0;
  try Pool.close();
  catch %(bad-state *): caught++;
  try Pool.detach();
  catch %(bad-state *): caught++;
  EXPECT_INT_EQ(caught, 2);
  // The failures left the root active, so the bracket still works.
  Pool root = Pool.current();
  Pool nested = Pool.open_named("test-bracket-guard");
  EXPECT_TRUE(Pool.current() == nested);
  EXPECT_TRUE(Pool.detach() == nested);
  EXPECT_TRUE(Pool.current() == root);
  nested.release();
}

static void pool_release_and_parent_allocation_do_not_deadlock(void) {
  Pool parent = Pool.retain_named(NULL, "concurrent parent");
  PoolThreadProbe probe = { .parent = parent };
  pthread_t worker;
  /* Thread.start_raw does this before pthread_create; without it Pool takes no
     lock at all and this test proves nothing about contention. */
  Pool.thread_start();
  int created = pthread_create(
    &worker, NULL, _pool_parent_allocator, &probe
  );
  EXPECT_INT_EQ(created, 0);
  if (created) {
    parent.release();
    return;
  }
  while (!atomic_load(&probe.started)) {}
  int stats_valid = 1;
  for (int i = 0; i < 5000; i++) {
    Pool child = parent.retain_named("concurrent child");
    void *allocation = child.malloc(16);
    if (i % 2) {
      child.insert(i);
      child.promote(i, allocation);
    }
    else child.free(allocation);
    child.release();
    ScopeStats stats = Scope.stats();
    if (stats.live_allocations > stats.allocation_calls ||
        stats.live_scopes > stats.scope_creations)
      stats_valid = 0;
  }
  atomic_store(&probe.stop, 1);
  EXPECT_INT_EQ(pthread_join(worker, NULL), 0);
  EXPECT_TRUE(probe.allocations > 0);
  EXPECT_TRUE(stats_valid);
  parent.release();
}

static void pool_free_from_child_uses_parent_owner(void) {
  Pool parent = Pool.retain(NULL), child = parent.retain();
  PoolThreadProbe probe = {.parent = parent};
  pthread_t worker;
  Pool.thread_start();
  int created = pthread_create(&worker, NULL, _pool_parent_allocator, &probe);
  EXPECT_INT_EQ(created, 0);
  if (!created) {
    while (!atomic_load(&probe.started)) {}
    for (int i = 0; i < 10000; i++) {
      void *allocation = parent.malloc(16);
      child.free(allocation);
    }
    atomic_store(&probe.stop, 1);
    EXPECT_INT_EQ(pthread_join(worker, NULL), 0);
    EXPECT_TRUE(probe.allocations > 0);
  }
  Pool.release(child.release());
}

typedef struct RootIndexTest {
  Pool root;
  String seed, *identities;
  List list;
  int count, promote;
  atomic_int started, stop, failed;
} RootIndexTest;

static void *_root_index_reader(void *data) {
  RootIndexTest *test = data;
  while (!atomic_load(&test.stop)) {
    if (_root_text(test.root, test.seed) !== test.seed ||
        !test.root.lookup(test.list).same(test.list) ||
        !test.root.owns(test.seed)) atomic_store(&test.failed, 1);
    atomic_store(&test.started, 1);
  }
  x2c_thread_state_release();
  return NULL;
}

static void *_root_index_writer(void *data) {
  RootIndexTest *test = data;
  Pool.thread_initialize();
  Pool child = test.promote ? test.root.retain() : NULL;
  Pool previous = child ? x2c_pool_exchange(child) : NULL;
  for (int i = 0; i < test.count; i++) {
    char bytes[80];
    snprintf(bytes, sizeof(bytes), "root-index-%s-%d",
      test.promote ? "promoted" : "racing", i);
    String value = _root_text(child ? child : test.root, bytes);
    if (child) {
      value.promote();
      cons(value, NULL).promote();
    }
    else test.identities[i] = value;
  }
  if (child) { x2c_pool_exchange(previous); child.release(); }
  x2c_thread_state_release();
  return NULL;
}

static void pool_root_reads_and_concurrent_growth(void) {
  $test.scoped();
  Pool root = Pool.current();
  String seed = _root_text(root, "root-reader-seed");
  List list = List.cons_in(root, seed, NULL);
  unsigned capacity = root.table.capacity;
  int count = capacity / 2 + 32;
  RootIndexTest reader = {.root = root, .seed = seed, .list = list};
  pthread_t read_thread, writers[3];
  Pool.thread_start();
  pthread_mutex_lock(&root.mutex);
  int created = pthread_create(&read_thread, NULL, _root_index_reader, &reader);
  EXPECT_INT_EQ(created, 0);
  if (created) { pthread_mutex_unlock(&root.mutex); return; }
  for (int i = 0; i < 1000 && !atomic_load(&reader.started); i++) usleep(1000);
  int progressed = atomic_load(&reader.started);
  pthread_mutex_unlock(&root.mutex);
  EXPECT_TRUE(progressed);
  String *first = xcalloc(count, sizeof(String));
  String *second = xcalloc(count, sizeof(String));
  RootIndexTest jobs[3] = {
    {.root = root, .count = count, .identities = first},
    {.root = root, .count = count, .identities = second},
    {.root = root, .count = count, .promote = 1}
  };
  int launched = 0;
  for (int i = 0; i < 3; i++) {
    int error = pthread_create(&writers[i], NULL, _root_index_writer, &jobs[i]);
    EXPECT_INT_EQ(error, 0);
    if (error) break;
    launched++;
  }
  for (int i = 0; i < launched; i++)
    EXPECT_INT_EQ(pthread_join(writers[i], NULL), 0);
  atomic_store(&reader.stop, 1);
  EXPECT_INT_EQ(pthread_join(read_thread, NULL), 0);
  EXPECT_FALSE(atomic_load(&reader.failed));
  EXPECT_TRUE(root.table.capacity > capacity);
  if (launched >= 2) {
    int same = 1;
    for (int i = 0; i < jobs[0].count; i++)
      if (first[i] !== second[i]) same = 0;
    EXPECT_TRUE(same);
  }
  EXPECT_TRUE(_root_text(root, "root-reader-seed") === seed);
  EXPECT_TRUE(root.lookup(list).same(list));
  if (launched == 3) {
    String promoted = _root_text(root, "root-index-promoted-0");
    EXPECT_TRUE(root.owns(promoted));
    EXPECT_TRUE(root.owns(List.cons_in(root, promoted, NULL)));
  }
}

static void pool_root_callback_growth_and_error(void) {
  $test.scoped();
  Pool root = Pool.current();
  pool_probe_root = root;
  PoolProbe *first = root.malloc(sizeof(PoolProbe));
  first.value = 17;
  Var original = root.intern_new(Var.new(<pprobe>, first), first);
  PoolProbe *next = root.malloc(sizeof(PoolProbe));
  next.value = 17 + (1L << 32);
  Var candidate = Var.new(<pprobe>, next);
  unsigned capacity = root.table.capacity;
  pool_probe_grow = 1;
  EXPECT_TRUE(root.intern_new(candidate, next).same(candidate));
  EXPECT_TRUE(root.table.capacity > capacity);
  EXPECT_TRUE(root.lookup(original).same(original));
  EXPECT_TRUE(root.lookup(candidate).same(candidate));
  PoolProbe query = {.value = 17};
  int failed = 0;
  pool_probe_fail = 1;
  try root.lookup(Var.new(<pprobe>, &query));
  catch %(bad-arg *): failed = 1;
  finally pool_probe_fail = 0;
  EXPECT_TRUE(failed);
  EXPECT_TRUE(root.lookup(original).same(original));
  String after = _root_text(root, "root-after-callback-error");
  EXPECT_TRUE(root.owns(after));
}

void pool_suite(void) {
  $test.run(pool_lookup_shadows_outward);
  $test.run(pool_intern_uses_one_probe);
  $test.run(pool_reuses_child_table_capacity);
  $test.run(pool_release_reclaims_wholesale);
  $test.run(pool_reuses_small_slots_and_blocks);
  $test.run(pool_promote_is_pointer_stable);
  $test.run(pool_promote_transfers_partial_blocks);
  $test.run(pool_promote_tracks_a_full_bitmap);
  $test.run(pool_promote_crosses_multiple_levels);
  $test.run(pool_large_promotion_retains_scope_path);
  $test.run(pool_release_balances_scope_stats);
  $test.run(pool_null_owner_failures_are_handleable);
  $test.run(pool_string_bracket_and_wipe);
  $test.run(pool_string_free_reuses_small_slot);
  $test.run(pool_list_bracket_promotes_result);
  $test.run(pool_unpromoted_identity_is_wiped);
  $test.run(pool_try_own_reports_lifetime_safety);
  $test.run(string_is_permanent_asks_without_promoting);
  $test.run(pool_bracket_requires_an_open_child);
  $test.run(pool_release_and_parent_allocation_do_not_deadlock);
  $test.run(pool_free_from_child_uses_parent_owner);
  $test.run(pool_root_callback_growth_and_error);
  $test.run(pool_root_reads_and_concurrent_growth);
}
