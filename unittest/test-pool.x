/*  test-pool.x -- unit tests for nested interning pools */

#include "test-support.x"
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>

typedef struct PoolThreadProbe {
  Pool parent;
  atomic_int started;
  atomic_int stop;
  int allocations;
} PoolThreadProbe;

static void *_pool_parent_allocator(void *data) {
  PoolThreadProbe *probe = data;
  atomic_store(&probe->started, 1);
  while (!atomic_load(&probe->stop)) {
    void *allocation = probe->parent.malloc(16);
    probe->parent.free(allocation);
    Scope scratch = Scope.new();
    Scope.malloc_in(&scratch, 16);
    Scope.destroy(scratch);
    probe->allocations++;
  }
  x2c_thread_state_release();
  return NULL;
}

static int pool_probe_hash_calls;

typedef struct PoolProbe {
  long value;
} PoolProbe;


static unsigned _pool_probe_hash(Var value) {
  pool_probe_hash_calls++;
  PoolProbe *probe = value;
  return (unsigned) probe.value;
}


static int _pool_probe_equal(Var a, Var b) {
  PoolProbe *left = a, *right = b;
  return left.value == right.value;
}

static void pool_lookup_shadows_outward(void) {
  Pool root = Pool.retain_named(NULL, "test-pool-root");
  EXPECT_STR_EQ(Scope.name(root.scope), "test-pool-root");
  EXPECT_TRUE(root.table.scope == &root.scope);
  String alpha = %"pool-alpha";
  Pool.insert(root, alpha);
  Pool child = Pool.retain_named(root, "test-pool-child");
  EXPECT_STR_EQ(Scope.name(child.scope), "test-pool-child");
  EXPECT_TRUE(child.table.scope == &child.scope);
  Var from_parent = alpha;
  EXPECT_TRUE(Pool.lookup(child, alpha) == from_parent);
  String beta = %"pool-beta";
  Pool.insert(child, beta);
  Var from_child = beta;
  EXPECT_TRUE(Pool.lookup(child, beta) == from_child);
  EXPECT_TRUE(Pool.lookup(root, beta) is void);
  EXPECT_TRUE(Pool.owns(child, beta));
  EXPECT_FALSE(Pool.owns(child, alpha));
  EXPECT_TRUE(Pool.owns(root, alpha));
  PoolStats stats = Pool.stats(child);
  EXPECT_INT_EQ(stats.depth, 2);
  EXPECT_INT_EQ(stats.interned, 1);
  child = Pool.release(child);
  EXPECT_TRUE(child == root);
  Pool.release(root);
}


static void pool_intern_uses_one_probe(void) {
  VarMethods methods = {
    .hash = _pool_probe_hash,
    .equal = _pool_probe_equal
  };
  EXPECT_TRUE(x2c_try_register_descriptor(%"pprobe", methods));

  Pool root = Pool.retain_named(NULL, "test-pool-one-probe");
  PoolProbe *first = Pool.malloc(root, sizeof(PoolProbe));
  first.value = 17;
  Var candidate = Var.new(<pprobe>, first);
  pool_probe_hash_calls = 0;
  Var canonical = Pool.intern(root, candidate, first);
  EXPECT_TRUE(canonical.same(candidate));
  EXPECT_INT_EQ(pool_probe_hash_calls, 1);
  EXPECT_INT_EQ(Pool.stats(root).interned, 1);

  ScopeStats before_duplicate = Scope.stats();
  PoolProbe *duplicate = Pool.malloc(root, sizeof(PoolProbe));
  duplicate.value = 17;
  Var repeated = Var.new(<pprobe>, duplicate);
  pool_probe_hash_calls = 0;
  Var existing = Pool.intern(root, repeated, duplicate);
  ScopeStats after_duplicate = Scope.stats();
  EXPECT_TRUE(existing.same(candidate));
  EXPECT_INT_EQ(pool_probe_hash_calls, 1);
  EXPECT_INT_EQ(after_duplicate.live_allocations,
                before_duplicate.live_allocations);
  EXPECT_INT_EQ(Pool.stats(root).interned, 1);

  Pool child = Pool.retain_named(root, "test-pool-child-one-probe");
  PoolProbe *fresh = Pool.malloc(child, sizeof(PoolProbe));
  fresh.value = 23;
  Var fresh_candidate = Var.new(<pprobe>, fresh);
  pool_probe_hash_calls = 0;
  Var child_canonical = Pool.intern(child, fresh_candidate, fresh);
  EXPECT_TRUE(child_canonical.same(fresh_candidate));
  // One ancestor probe plus one innermost lookup-or-insert probe.
  EXPECT_INT_EQ(pool_probe_hash_calls, 2);
  EXPECT_INT_EQ(Pool.stats(child).interned, 1);
  Pool.release(Pool.release(child));
}


static void pool_reuses_child_table_capacity(void) {
  Pool root = Pool.retain_named(NULL, "test-pool-sized-root");
  Pool child = Pool.retain_named(root, "test-pool-sized-child");
  for (int i = 0; i < 40; i++) Pool.insert(child, i + 1);
  unsigned learned = child.table.capacity;
  EXPECT_TRUE(learned > 2);
  child = Pool.release(child);
  EXPECT_TRUE(child == root);

  Pool next = Pool.retain_named(root, "test-pool-sized-next");
  EXPECT_INT_EQ(next.table.capacity, learned);
  Pool.release(Pool.release(next));
}

static void pool_release_reclaims_wholesale(void) {
  Pool root = Pool.retain_named(NULL, "test-reclaim-root");
  Pool child = Pool.retain_named(root, "test-reclaim-child");
  PoolStats before = Pool.stats(child);
  for (int i = 0; i < 100; i++) {
    char *cell = Pool.malloc(child, 32);
    EXPECT_NOT_NULL(cell);
    snprintf(cell, 32, "cell-%d", i);
  }
  PoolStats during = Pool.stats(child);
  EXPECT_INT_EQ(during.allocation_calls - before.allocation_calls, 100);
  EXPECT_INT_EQ(during.requested_bytes - before.requested_bytes, 3200);
  EXPECT_TRUE(during.active_blocks > before.active_blocks);
  EXPECT_TRUE(during.active_bytes > before.active_bytes);
  Pool.release(child);
  PoolStats after = Pool.stats(root);
  EXPECT_TRUE(after.depot_blocks > during.depot_blocks);
  EXPECT_TRUE(after.depot_bytes > during.depot_bytes);
  EXPECT_TRUE(after.backing_bytes >= during.backing_bytes);
  Pool.release(root);
}


static void pool_reuses_small_slots_and_blocks(void) {
  Pool root = Pool.retain_named(NULL, "test-reuse-root");
  Pool child = Pool.retain_named(root, "test-reuse-child");
  PoolProbe *candidate = Pool.malloc(child, sizeof(PoolProbe));
  candidate.value = 101;
  Var value = Var.new(<pprobe>, candidate);
  EXPECT_TRUE(Pool.intern(child, value, candidate).same(value));

  PoolProbe *duplicate = Pool.malloc(child, sizeof(PoolProbe));
  duplicate.value = 101;
  Var repeated = Var.new(<pprobe>, duplicate);
  EXPECT_TRUE(Pool.intern(child, repeated, duplicate).same(value));
  PoolStats before_slot = Pool.stats(child);
  PoolProbe *reused = Pool.malloc(child, sizeof(PoolProbe));
  PoolStats after_slot = Pool.stats(child);
  EXPECT_TRUE(reused == duplicate);
  EXPECT_INT_EQ(after_slot.slot_reuses, before_slot.slot_reuses + 1);

  Pool.release(child);
  PoolStats before_block = Pool.stats(root);
  Pool next = Pool.retain_named(root, "test-reuse-next");
  EXPECT_NOT_NULL(Pool.malloc(next, sizeof(PoolProbe)));
  PoolStats after_block = Pool.stats(next);
  EXPECT_INT_EQ(after_block.block_allocations, before_block.block_allocations);
  EXPECT_INT_EQ(after_block.block_reuses, before_block.block_reuses + 1);
  EXPECT_TRUE(after_block.active_bytes > before_block.active_bytes);
  EXPECT_TRUE(after_block.depot_bytes < before_block.depot_bytes);
  Pool.release(Pool.release(next));
}


static void pool_promote_is_pointer_stable(void) {
  Pool root = Pool.retain_named(NULL, "test-promote-root");
  Pool child = Pool.retain_named(root, "test-promote-child");
  char *buf = Pool.malloc(child, 32);
  strcpy(buf, "survivor");
  String key = %"pool-promote-key";
  Pool.insert(child, key);
  EXPECT_FALSE(Pool.promote(root, key, buf));  // root has no parent
  EXPECT_FALSE(Pool.promote(child, %"pool-promote-miss", buf));
  EXPECT_TRUE(Pool.promote(child, key, buf));
  PoolStats promoted = Pool.stats(child);
  EXPECT_INT_EQ(promoted.promoted, 1);
  Pool released = Pool.release(child);
  EXPECT_TRUE(released == root);
  EXPECT_STR_EQ(buf, "survivor");
  EXPECT_TRUE(Pool.owns(root, key));
  PoolStats stats = Pool.stats(root);
  EXPECT_INT_EQ(stats.depth, 1);
  Pool.release(root);
}


static void pool_promote_transfers_partial_blocks(void) {
  Pool root = Pool.retain_named(NULL, "test-partial-root");
  Pool child = Pool.retain_named(root, "test-partial-child");
  char *kept = Pool.malloc(child, 16), *garbage = Pool.malloc(child, 16);
  strcpy(kept, "kept");
  strcpy(garbage, "gone");
  String key = %"pool-partial-key";
  Pool.insert(child, key);
  EXPECT_TRUE(Pool.promote(child, key, kept));
  Pool.release(child);
  EXPECT_STR_EQ(kept, "kept");
  EXPECT_TRUE(Pool.owns(root, key));
  EXPECT_TRUE(Pool.malloc(root, 16) == garbage);
  Pool.release(root);
}


static void pool_promote_tracks_a_full_bitmap(void) {
  Pool root = Pool.retain_named(NULL, "test-bitmap-root");
  Pool child = Pool.retain_named(root, "test-bitmap-child");
  char *kept[30];
  for (int i = 0; i < 30; i++) {
    kept[i] = Pool.malloc(child, 32);
    snprintf(kept[i], 32, "bitmap-%d", i);
    Pool.insert(child, i + 1);
    EXPECT_TRUE(Pool.promote(child, i + 1, kept[i]));
  }
  Pool.release(child);
  for (int i = 0; i < 30; i++) {
    char expected[32];
    snprintf(expected, sizeof expected, "bitmap-%d", i);
    EXPECT_STR_EQ(kept[i], expected);
  }
  Pool.release(root);
}


static void pool_promote_crosses_multiple_levels(void) {
  Pool root = Pool.retain_named(NULL, "test-multi-root");
  Pool middle = Pool.retain_named(root, "test-multi-middle");
  Pool inner = Pool.retain_named(middle, "test-multi-inner");
  char *kept = Pool.malloc(inner, 32);
  strcpy(kept, "multi-level survivor");
  String key = %"pool-multi-key";
  Pool.insert(inner, key);
  EXPECT_TRUE(Pool.promote(inner, key, kept));
  EXPECT_TRUE(Pool.promote(middle, key, kept));
  Pool.release(inner);
  EXPECT_STR_EQ(kept, "multi-level survivor");
  Pool.release(middle);
  EXPECT_STR_EQ(kept, "multi-level survivor");
  EXPECT_TRUE(Pool.owns(root, key));
  Pool.release(root);
}


static void pool_large_promotion_retains_scope_path(void) {
  Pool root = Pool.retain_named(NULL, "test-large-root");
  Pool child = Pool.retain_named(root, "test-large-child");
  char *kept = Pool.malloc(child, 1024);
  strcpy(kept, "large survivor");
  String key = %"pool-large-key";
  Pool.insert(child, key);
  EXPECT_TRUE(Pool.promote(child, key, kept));
  Pool.release(child);
  EXPECT_STR_EQ(kept, "large survivor");
  Pool.release(root);
}


static void pool_release_balances_scope_stats(void) {
  ScopeStats before = Scope.stats();
  Pool root = Pool.retain_named(NULL, "test-balance-root");
  Pool child = Pool.retain(root);
  Pool.malloc(child, 64);
  Pool.malloc(root, 64);
  Pool.release(Pool.release(child));
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
  String.pool_retain_named("test-string-bracket");
  String kept = NULL;
  for (int i = 0; i < 200; i++) {
    String transient = String.printf("pool-transient-%d", i);
    if (i == 137) kept = transient;
  }
  ScopeStats during = Scope.stats();
  String promoted = String.promote(kept);
  EXPECT_TRUE(promoted == kept);  // promotion is pointer-stable
  String.pool_release();
  ScopeStats after = Scope.stats();
  EXPECT_TRUE(after.live_allocations < during.live_allocations);
  EXPECT_STR_EQ(kept, "pool-transient-137");
  // The survivor stays canonical: re-interning is a hit, not an alloc.
  PoolStats before_hit = Pool.stats(NULL);
  EXPECT_TRUE(String.new("pool-transient-137") == kept);
  PoolStats after_hit = Pool.stats(NULL);
  EXPECT_INT_EQ(after_hit.allocation_calls, before_hit.allocation_calls);
  // Wiped garbage lost its identity: re-interning allocates afresh.
  String again = String.new("pool-transient-0");
  PoolStats after_miss = Pool.stats(NULL);
  EXPECT_TRUE(after_miss.allocation_calls > after_hit.allocation_calls);
  EXPECT_STR_EQ(again, "pool-transient-0");
}


static void pool_string_free_reuses_small_slot(void) {
  String first = String.malloc(24);
  EXPECT_NOT_NULL(first);
  String.free(first);
  PoolStats before = Pool.stats(NULL);
  String reused = String.malloc(24);
  PoolStats after = Pool.stats(NULL);
  EXPECT_TRUE(reused == first);
  EXPECT_INT_EQ(after.slot_reuses, before.slot_reuses + 1);
  String.free(reused);
}

static void pool_list_bracket_promotes_result(void) {
  List.pool_retain_named("test-list-bracket");
  for (int i = 0; i < 100; i++) {
    String garbage = String.printf("pool-garbage-%d", i);
    List cell = %( $garbage $i );
    EXPECT_INT_EQ(cell.len(), 2);
  }
  String label = String.new("pool-keep-me");
  List nested = %(1 2 3);
  List result = %( $label 42 $nested );
  List promoted = List.promote(result);
  EXPECT_TRUE(promoted == result);  // pointer stability
  List.pool_release();
  EXPECT_INT_EQ(result.len(), 3);
  EXPECT_STR_EQ(result.car().string(), "pool-keep-me");
  Var answer = 42;
  EXPECT_VAR_EQ(result[1], answer);
  EXPECT_TRUE(result[2].list() == nested);
  // Ancestor-owned structure: promoting again is a harmless no-op.
  EXPECT_TRUE(List.promote(result) == result);
  // The nested tail stayed canonical through the wipe.
  EXPECT_TRUE(%(1 2 3) == nested);
}

static void pool_unpromoted_identity_is_wiped(void) {
  // volatile seed keeps these cells out of the static literal machinery
  volatile int seed = 9100;
  List.pool_retain_named("test-list-wipe");
  List doomed = cons(seed + 1, cons(seed + 2, cons(seed + 3, NULL)));
  EXPECT_INT_EQ(doomed.len(), 3);
  List.pool_release();
  PoolStats before = Pool.stats(NULL);
  List again = cons(seed + 1, cons(seed + 2, cons(seed + 3, NULL)));
  PoolStats after = Pool.stats(NULL);
  EXPECT_TRUE(after.allocation_calls > before.allocation_calls);
  EXPECT_INT_EQ(again.len(), 3);
}

static void pool_try_own_reports_lifetime_safety(void) {
  String permanent_string = %"pool-permanent-string";
  List permanent_list = %(pool-permanent-list);
  EXPECT_TRUE(String.try_own(NULL));
  EXPECT_TRUE(List.try_own(NULL));
  EXPECT_TRUE(String.try_own(permanent_string));
  EXPECT_TRUE(List.try_own(permanent_list));

  String transient_string = String.malloc(16);
  strcpy(transient_string, "not interned");
  EXPECT_FALSE(String.try_own(transient_string));
  String.free(transient_string);

  List transient_list = Scope.malloc(sizeof(struct List));
  transient_list.car = 1;
  transient_list.cdr = NULL;
  EXPECT_FALSE(List.try_own(transient_list));

  List.pool_retain_named("test-own-values");
  EXPECT_TRUE(String.try_own(permanent_string));
  EXPECT_TRUE(List.try_own(permanent_list));
  String child_string = String.new("pool-child-string");
  List child_list = %($child_string pool-child-list);
  EXPECT_TRUE(String.try_own(child_string));
  EXPECT_TRUE(List.try_own(child_list));
  List.pool_release();
  EXPECT_STR_EQ(child_string, "pool-child-string");
  EXPECT_TRUE(child_list == %("pool-child-string" pool-child-list));
}

static void string_is_permanent_asks_without_promoting(void) {
  String permanent = %"pool-permanent-string";
  EXPECT_TRUE(String.is_permanent(NULL));
  EXPECT_TRUE(String.is_permanent(""));
  EXPECT_TRUE(String.is_permanent(permanent));

  String transient = String.malloc(16);
  strcpy(transient, "not interned");
  EXPECT_FALSE(String.is_permanent(transient));
  String.free(transient);

  String.pool_retain_named("test-is-permanent");
  String nested = String.new("pool-nested-string");
  EXPECT_FALSE(String.is_permanent(nested));
  EXPECT_TRUE(String.is_permanent(permanent));
  String.pool_release();
}

static void pool_release_and_parent_allocation_do_not_deadlock(void) {
  Pool parent = Pool.retain_named(NULL, "concurrent parent");
  PoolThreadProbe probe = { .parent = parent };
  pthread_t worker;
  /* Thread.start does this before pthread_create; without it Pool takes no
     lock at all and this test proves nothing about contention. */
  x2c_pool_thread_start();
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
    child.free(allocation);
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

$(import "test-macros.xmacro")

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
  $test.run(pool_release_and_parent_allocation_do_not_deadlock);
}
