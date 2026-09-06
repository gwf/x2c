/*  test-match-cache.x -- unit tests for the private Match plan cache

    The cache stores immutable prepared programs only.  These tests pin
    the lifetime contract: admission before any table work, positive
    memoization with raw-key-zero rejection, conservative bypasses for
    Strings and wide boxes, deterministic LRU eviction, pins during
    active leases, generation validation, prepared scalar entries,
    and adapter parity with the recursive oracle for every public consumer,
    including the approved malformed form. */

#include "test-support.x"

static Var _keyed_pattern(int index) {
  Var value = index;
  return %(cache-key $value ?value);
}

static List _keyed_input(int index) {
  Var value = index;
  return %(cache-key $value ok);
}

static void cache_lifecycle_failures_transfer(void) {
  int caught = 0;
  try MatchCache.new(0);
  catch %(bad-arg *): caught++;

  try MatchLease.release(NULL);
  catch %(bad-arg *): caught++;

  MatchLease invalid = {
    .transient_plan = (MatchPlan) 1,
    .active = 1
  };
  try MatchLease.release(&invalid);
  catch %(bad-state *): caught++;
  EXPECT_TRUE(invalid.active);

  MatchCache cache = MatchCache.new(1);
  MatchLease stale = {
    .cache = cache,
    .slot = -1,
    .active = 1
  };
  try MatchLease.release(&stale);
  catch %(bad-state *): caught++;
  EXPECT_TRUE(stale.active);

  MatchLease held;
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(1), &held),
                MACHINE_PREPARED);
  try MatchCache.dispose(cache);
  catch %(bad-state *): caught++;
  MatchLease.release(&held);
  EXPECT_FALSE(held.active);
  MatchCache.dispose(cache);
  EXPECT_INT_EQ(caught, 5);
}

static void cache_admission_and_bypass(void) {
  MatchCache cache = MatchCache.new(4);
  MatchLease lease;

  // Canonical graphs retain the same cached generation.
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(1), &lease),
                MACHINE_PREPARED);
  unsigned long generation = lease.generation;
  int slot = lease.slot;
  MatchLease.release(&lease);
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(1), &lease),
                MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == generation);
  EXPECT_INT_EQ(lease.slot, slot);
  MatchLease.release(&lease);

  // Canonical long Atoms are raw-identity values and remain admissible.
  Var long_pattern = %(cache-key ?VeryLongIdentifierValue);
  EXPECT_INT_EQ(MatchCache.acquire(cache, long_pattern, &lease),
                MACHINE_PREPARED);
  generation = lease.generation;
  slot = lease.slot;
  MatchLease.release(&lease);
  EXPECT_INT_EQ(MatchCache.acquire(cache, long_pattern, &lease),
                MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == generation);
  EXPECT_INT_EQ(lease.slot, slot);
  MatchLease.release(&lease);

  // A String the outermost pool owns is process-lifetime, so a pattern
  // holding one is admitted like any other canonical graph.
  Var text_pattern = %(tag "needle" ?v);
  EXPECT_TRUE(String.is_permanent(%"needle"));
  EXPECT_INT_EQ(MatchCache.acquire(cache, text_pattern, &lease),
                MACHINE_PREPARED);
  generation = lease.generation;
  slot = lease.slot;
  MatchLease.release(&lease);
  EXPECT_INT_EQ(MatchCache.acquire(cache, text_pattern, &lease),
                MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == generation);
  EXPECT_INT_EQ(lease.slot, slot);
  MatchLease.release(&lease);

  // A String a nested pool can still reclaim stays bypassed: a transient
  // program executes and is released with its lease.
  String.pool_retain_named("match-cache-nested-values");
  String nested = String.new("match-cache-nested-needle");
  EXPECT_FALSE(String.is_permanent(nested));
  EXPECT_INT_EQ(MatchCache.acquire(cache, %(tag $nested ?v), &lease),
                MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == 0);
  MatchLease.release(&lease);
  EXPECT_NULL(lease.transient_plan);
  String.pool_release();

  // Wide boxes carry value semantics across allocations: bypassed.
  long wide_value = 42;
  Var wide = wide_value;
  EXPECT_INT_EQ(MatchCache.acquire(cache, %(tag $wide ?v),
                                   &lease), MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == 0);
  MatchLease.release(&lease);

  // Raw key zero is the inadmissible null-pointer Var: it must bypass
  // both times, never echoing out of the zero-filled memo.
  Var zero = Var.new(<p48>, NULL);
  EXPECT_TRUE(zero.u64 == 0);
  for (int i = 0; i < 2; i++) {
    EXPECT_INT_EQ(MatchCache.acquire(cache, zero, &lease), MACHINE_PREPARED);
    EXPECT_TRUE(lease.generation == 0);
    MatchLease.release(&lease);
  }

  // Admissible atoms retain their prepared cache entry.
  Var atom = Var.new(<symbol>, <draft>);
  EXPECT_INT_EQ(MatchCache.acquire(cache, atom, &lease), MACHINE_PREPARED);
  generation = lease.generation;
  slot = lease.slot;
  MatchLease.release(&lease);
  EXPECT_INT_EQ(MatchCache.acquire(cache, atom, &lease), MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == generation);
  EXPECT_INT_EQ(lease.slot, slot);
  MatchLease.release(&lease);

  MatchCache.dispose(cache);
}

static void cache_eviction_is_deterministic(void) {
  MatchCache cache = MatchCache.new(2);
  MatchLease lease;
  unsigned long generations[2];
  for (int i = 1; i <= 2; i++) {
    EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(i), &lease),
                  MACHINE_PREPARED);
    generations[i - 1] = lease.generation;
    MatchLease.release(&lease);
  }
  // Inserting a third pattern evicts the least recently used first.
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(3), &lease),
                MACHINE_PREPARED);
  MatchLease.release(&lease);
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(2), &lease),
                MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation == generations[1]);
  MatchLease.release(&lease);
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(1), &lease),
                MACHINE_PREPARED);
  EXPECT_TRUE(lease.generation != generations[0]);
  MatchLease.release(&lease);

  // Churn through a working set wider than capacity replaces a generation
  // on every acquire.
  unsigned long last_generation = lease.generation;
  for (int round = 0; round < 3; round++)
    for (int i = 10; i < 14; i++) {
      EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(i),
                                       &lease), MACHINE_PREPARED);
      EXPECT_TRUE(lease.generation > last_generation);
      last_generation = lease.generation;
      MatchLease.release(&lease);
    }
  MatchCache.dispose(cache);
}

static void cache_pins_protect_active_leases(void) {
  MatchCache cache = MatchCache.new(1);
  MatchLease held;
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(1), &held),
                MACHINE_PREPARED);

  // The only slot is pinned: a new pattern reports pressure rather
  // than evicting the program under execution.
  MatchLease blocked;
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(2), &blocked),
                MATCH_CACHE_PRESSURE);
  MatchLease.release(&blocked);

  // The pinned lease still protects its program.
  MatchLease stale = held;
  MatchLease.release(&held);

  // Released, the slot recycles and invalidates the old generation.
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(2), &blocked),
                MACHINE_PREPARED);
  MatchLease.release(&blocked);
  int caught = 0;
  try MatchLease.release(&stale);
  catch %(bad-state *): caught++;
  EXPECT_INT_EQ(caught, 1);
  stale.active = 0;
  MatchCache.dispose(cache);
}

static void cache_scalar_lease_survives_eviction(void) {
  MatchCache cache = MatchCache.new(2);

  // Acquire and hold a prepared scalar entry: it must stay pinned.
  Var atom = Var.new(<symbol>, <draft>);
  MatchLease held;
  EXPECT_INT_EQ(MatchCache.acquire(cache, atom, &held), MACHINE_PREPARED);

  // Fill the remaining slot, then force an eviction with a third
  // pattern: the held scalar entry must never be chosen as victim.
  MatchLease l1;
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(1), &l1),
                MACHINE_PREPARED);
  MatchLease.release(&l1);

  MatchLease l2;
  EXPECT_INT_EQ(MatchCache.acquire(cache, _keyed_pattern(2), &l2),
                MACHINE_PREPARED);
  MatchLease.release(&l2);

  // Releasing the held scalar lease must not assert/crash even
  // though the cache has since evicted and reused every other slot.
  MatchLease.release(&held);
  MatchCache.dispose(cache);
}

static void cache_adapters_match_oracle(void) {
  MatchCache cache = MatchCache.new(16);

  // The frozen six-family fixture through the try_match adapter.
  List inputs[6];
  Var patterns[6];
  inputs[0] = %(alpha beta gamma);
  patterns[0] = %(alpha beta gamma);
  inputs[1] = %(alpha beta gamma);
  patterns[1] = %(?a ?b ?c);
  inputs[2] = %(alpha beta gamma);
  patterns[2] = %(!and ?whole (!not missing) (!set ?whole ?));
  inputs[3] = %(alpha beta gamma delta epsilon);
  patterns[3] = %(*left delta ?last);
  inputs[4] = %(alpha beta gamma delta epsilon);
  patterns[4] = %(*left missing ?last);
  inputs[5] = %(tree ((node 3 4)) leaf);
  patterns[5] = %(tree ((node ?a ?b)) ?rest);
  for (int round = 0; round < 2; round++)
    for (int i = 0; i < 6; i++) {
      List oracle = %(sentinel), candidate = %(sentinel);
      int oracle_status =
        test_match_oracle_try_match(inputs[i], patterns[i], &oracle);
      int matched = MatchCache.try_match(
        cache, inputs[i], patterns[i], &candidate
      );
      EXPECT_INT_EQ(matched, oracle_status);
      EXPECT_TRUE(candidate == (oracle_status ? oracle : %(sentinel)));
    }

  // The approved malformed form never matches and never falls back.
  List bindings = %(sentinel);
  EXPECT_FALSE(MatchCache.try_match(
    cache, %(foo), %(!or *whole missing), &bindings
  ));
  EXPECT_TRUE(bindings == %(sentinel));
  MatchCache.dispose(cache);
}

static void cache_product_pipeline_matches_oracle(void) {
  MatchCache cache = MatchCache.new(16);
  List document = %((document
                      (header (title "Guide") (version "1"))
                      (release (status draft))
                      (notes "first" "second")
                      (actor "gary")
                      (again (actor "avery"))));
  List document_node = car(document);
  Var direct_pattern =
    %(document (header (title ?title) *header) *sections);
  Var status_pattern = %(status ?state);
  Var notes_pattern = %(notes *items);
  Var actor_pattern = %(actor ?who);
  Var status_template = %(status reviewed (was ?state));
  Var actor_template = %(reviewer ?who);
  Var draft_pattern = <draft>;

  // Oracle pipeline.
  List oracle_direct;
  EXPECT_TRUE(test_match_oracle_try_match(document_node, direct_pattern,
                                         &oracle_direct));
  Var oracle_first_match;
  List oracle_first_bindings;
  EXPECT_TRUE(test_match_oracle_try_search(document, status_pattern,
                                          &oracle_first_match,
                                          &oracle_first_bindings));
  List oracle_full = test_match_oracle_search(document, notes_pattern);
  Var oracle_replacement;
  EXPECT_TRUE(test_match_oracle_try_match_replace(
    oracle_first_match, status_pattern, status_template,
    &oracle_replacement));
  List oracle_rewrite = test_match_oracle_search_replace(
    document, actor_pattern, actor_template);
  List oracle_draft = test_match_oracle_search(document, draft_pattern);

  // Candidate pipeline through the cached adapters.
  List direct;
  EXPECT_TRUE(MatchCache.try_match(
    cache, document_node, direct_pattern, &direct
  ));
  EXPECT_TRUE(direct == oracle_direct);

  Var first_match;
  List first_bindings;
  EXPECT_TRUE(MatchCache.try_search(
    cache, document, status_pattern, &first_match, &first_bindings
  ));
  EXPECT_TRUE(first_match == oracle_first_match);
  EXPECT_TRUE(first_bindings == oracle_first_bindings);
  EXPECT_FALSE(MatchCache.try_search(
    cache, document, %(missing), &first_match, &first_bindings));
  EXPECT_TRUE(first_match == oracle_first_match);
  EXPECT_TRUE(first_bindings == oracle_first_bindings);

  List full;
  EXPECT_TRUE(MatchCache.search(cache, document, notes_pattern, &full));
  EXPECT_TRUE(full == oracle_full);

  Var replacement;
  EXPECT_TRUE(MatchCache.try_match_replace(
    cache, first_match, status_pattern, status_template, &replacement
  ));
  EXPECT_TRUE(replacement == oracle_replacement);
  EXPECT_FALSE(MatchCache.try_match_replace(
    cache, first_match, %(missing), status_template, &replacement));
  EXPECT_TRUE(replacement == oracle_replacement);

  List rewrite;
  EXPECT_TRUE(MatchCache.search_replace(
    cache, document, actor_pattern, actor_template, &rewrite
  ));
  EXPECT_TRUE(rewrite == oracle_rewrite);

  // Bare atoms compile as ordinary cached plans.
  List draft;
  EXPECT_TRUE(MatchCache.search(cache, document, draft_pattern, &draft));
  EXPECT_TRUE(draft == oracle_draft);

  // Reentrancy: an adapter call while another lease is held.
  MatchLease held;
  EXPECT_INT_EQ(MatchCache.acquire(cache, status_pattern, &held),
                MACHINE_PREPARED);
  List nested;
  EXPECT_TRUE(MatchCache.search(cache, document, notes_pattern, &nested));
  EXPECT_TRUE(nested == oracle_full);
  MatchLease.release(&held);

  MatchCache.dispose(cache);
}


static void default_cache_recreates_without_new_shutdown_ownership(void) {
  for (int i = 0; i < 4; i++) {
    List bindings = %(sentinel);
    EXPECT_TRUE(%(cache $i ok).try_match(%(cache ?value ok), &bindings));
    EXPECT_INT_EQ(bindings.assoc(<?value>).int(), i);
    MatchCache.flush_default();
  }
}


typedef struct MatchThreadReleaseProbe {
  int had_state_before, has_state_after;
  size_t live_scopes_before, live_scopes_after;
  size_t live_allocations_before, live_allocations_after;
} MatchThreadReleaseProbe;


static void *_match_thread_release_probe(void *data) {
  MatchThreadReleaseProbe *probe = data;
  ScopeStats before = Scope.stats();
  List bindings;
  int matched = %(thread cache 47).try_match(
    %(thread cache ?value), &bindings
  );
  (void) matched;
  /* The default cache owns a named Scope, so its presence is visible in
     Scope.stats without reaching into Match's per-thread state. */
  ScopeStats cached = Scope.stats();
  x2c_thread_state_release();
  ScopeStats after = Scope.stats();
  probe.had_state_before = cached.live_scopes > before.live_scopes;
  probe.has_state_after = after.live_scopes > before.live_scopes;
  probe.live_scopes_before = before.live_scopes;
  probe.live_scopes_after = after.live_scopes;
  probe.live_allocations_before = before.live_allocations;
  probe.live_allocations_after = after.live_allocations;
  return NULL;
}


static void default_cache_releases_with_native_thread_state(void) {
  MatchThreadReleaseProbe probe = { 0 };
  pthread_t thread;
  EXPECT_INT_EQ(pthread_create(
    &thread, NULL, _match_thread_release_probe, &probe
  ), 0);
  EXPECT_INT_EQ(pthread_join(thread, NULL), 0);
  EXPECT_TRUE(probe.had_state_before);
  EXPECT_FALSE(probe.has_state_after);
  EXPECT_INT_EQ(probe.live_scopes_after, probe.live_scopes_before);
  EXPECT_INT_EQ(
    probe.live_allocations_after, probe.live_allocations_before
  );
}


$(import "test-macros.xmacro")

void match_cache_suite(void) {
  $test.run(cache_lifecycle_failures_transfer);
  $test.run(cache_admission_and_bypass);
  $test.run(cache_eviction_is_deterministic);
  $test.run(cache_pins_protect_active_leases);
  $test.run(cache_scalar_lease_survives_eviction);
  $test.run(cache_adapters_match_oracle);
  $test.run(cache_product_pipeline_matches_oracle);
  $test.run(default_cache_recreates_without_new_shutdown_ownership);
  $test.run(default_cache_releases_with_native_thread_state);
}
