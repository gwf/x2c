/*  test-scope.x -- unit tests for scope allocator */

#include "test-support.x"
#include <stdint.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int _scope_rejected(void (*action)(void)) {
  pid_t pid = fork();
  if (pid < 0) return 0;
  if (pid == 0) {
    freopen("/dev/null", "w", stderr);
    action();
    _exit(0);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) != pid) return 0;
  return WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT;
}

static void _destroy_active_root(void) {
  Scope.retain();
  Scope.destroy(*Scope.top());
}

static void _destroy_active_pushed(void) {
  Scope slot = Scope.new();
  Scope.push(&slot);
  Scope.destroy(slot);
}

static void _destroy_outer_stack_slot(void) {
  Scope outer = Scope.new(), inner = Scope.new();
  Scope.push(&outer);
  Scope.push(&inner);
  Scope.destroy(outer);
}

static void _destroy_attached_lower(void) {
  Scope slot = NULL;
  Scope.push(&slot);
  Scope.retain();
  Scope lower = slot;
  Scope.retain();
  Scope.pop();
  Scope.destroy(lower);
}

static void _release_without_retain(void) {
  Scope.release();
}

static void _release_wrong_slot(void) {
  Scope.retain();
  Scope slot = NULL;
  Scope.push(&slot);
  Scope.release();
}

static void _malloc_overflow(void) {
  Scope.malloc(SIZE_MAX);
}

static void _calloc_overflow(void) {
  Scope.calloc(SIZE_MAX, 2);
}

static void _realloc_overflow(void) {
  void *allocation = Scope.malloc(8);
  Scope.realloc(allocation, SIZE_MAX);
}

static void fill(char *dst, const char *src) {
  strcpy(dst, src);
}

static void scope_alloc_release(void) {
  Scope.retain();
  char *buf = Scope.malloc(8);
  EXPECT_NOT_NULL(buf);
  if (buf) {
    fill(buf, "x2c");
    EXPECT_STR_EQ(buf, "x2c");
  }
  Scope.release();
}

static void scope_push_pop_destroy(void) {
  Scope.retain();
  Scope outer = Scope.new(), inner = Scope.new(), *initial = Scope.top();
  Scope.push(&outer);
  char *outer_mem = Scope.malloc(6);
  fill(outer_mem, "outer");
  Scope.push(&inner);
  Scope.malloc(6);

  EXPECT_TRUE(Scope.top() == &inner);
  EXPECT_STR_EQ(outer_mem, "outer");
  Scope.pop();
  EXPECT_TRUE(Scope.top() == &outer);
  Scope.destroy(inner);
  EXPECT_STR_EQ(outer_mem, "outer");
  Scope.pop();
  EXPECT_TRUE(Scope.top() == initial);
  Scope.destroy(outer);
  Scope.release();
}

static void scope_realloc_grows_and_shrinks(void) {
  Scope.retain();
  char *buf = Scope.malloc(8);
  fill(buf, "1234");
  char *bigger = Scope.realloc(buf, 32);
  EXPECT_NOT_NULL(bigger);
  if (bigger) EXPECT_STR_EQ(bigger, "1234");
  char *smaller = Scope.realloc(bigger, 6);
  EXPECT_NOT_NULL(smaller);
  if (smaller) {
    smaller[4] = '\0';
    EXPECT_STR_EQ(smaller, "1234");
    EXPECT_NULL(Scope.realloc(smaller, 0));
  }
  Scope.release();
}

static void scope_free_unlinks_any_position(void) {
  Scope.retain();
  char *tail = Scope.memdup("tail", 5);
  char *middle = Scope.memdup("middle", 7);
  char *head = Scope.memdup("head", 5);

  Scope.free(head);
  EXPECT_STR_EQ(middle, "middle");
  EXPECT_STR_EQ(tail, "tail");
  Scope.free(tail);
  EXPECT_STR_EQ(middle, "middle");
  Scope.free(middle);
  Scope.free(NULL);
  Scope.release();
}

static void scope_realloc_updates_any_position(void) {
  Scope.retain();
  char *tail = Scope.memdup("tail", 5);
  char *middle = Scope.memdup("middle", 7);
  char *head = Scope.memdup("head", 5);

  middle = Scope.realloc(middle, 64);
  EXPECT_NOT_NULL(middle);
  if (middle) EXPECT_STR_EQ(middle, "middle");
  head = Scope.realloc(head, 64);
  EXPECT_NOT_NULL(head);
  if (head) EXPECT_STR_EQ(head, "head");
  EXPECT_STR_EQ(tail, "tail");
  Scope.release();
}

static void scope_named_direct_allocation(void) {
  ScopeStats before = Scope.stats();
  Scope *active = Scope.top();
  char name[] = "named-test";
  Scope named = Scope.new_named(name);
  name[0] = 'x';
  char *copy = Scope.memdup_in(&named, "copy", 5);
  int *zeroes = Scope.calloc_in(&named, 4, sizeof(int));

  EXPECT_TRUE(Scope.top() == active);
  EXPECT_STR_EQ(Scope.name(named), "named-test");
  EXPECT_STR_EQ(copy, "copy");
  EXPECT_NOT_NULL(zeroes);
  if (zeroes) for (int i = 0; i < 4; i++) EXPECT_INT_EQ(zeroes[i], 0);

  ScopeStats during = Scope.stats();
  EXPECT_INT_EQ(during.allocation_calls, before.allocation_calls + 2);
  EXPECT_INT_EQ(during.live_scopes, before.live_scopes + 1);
  EXPECT_INT_EQ(during.live_allocations, before.live_allocations + 2);
  EXPECT_INT_EQ(during.requested_bytes, before.requested_bytes + 21);
  Scope.destroy(named);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.free_calls, before.free_calls + 2);
  EXPECT_INT_EQ(after.scope_creations, before.scope_creations + 1);
  EXPECT_INT_EQ(after.scope_destructions, before.scope_destructions + 1);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

static void scope_allocator_edge_behavior(void) {
  Scope.retain();
  void *zero = Scope.malloc(0);
  void *zeroed = Scope.calloc(0, sizeof(int));
  void *from_null = Scope.realloc(NULL, 8);

  EXPECT_NOT_NULL(zero);
  EXPECT_NOT_NULL(zeroed);
  EXPECT_NOT_NULL(from_null);
  EXPECT_NULL(Scope.memdup(NULL, 4));
  EXPECT_NULL(Scope.memdup("x", 0));
  EXPECT_NULL(Scope.realloc(from_null, 0));
  Scope.free(zero);
  Scope.free(zeroed);
  Scope.release();
}

static void scope_size_limits_are_terminal(void) {
  EXPECT_TRUE(_scope_rejected(_malloc_overflow));
  EXPECT_TRUE(_scope_rejected(_calloc_overflow));
  EXPECT_TRUE(_scope_rejected(_realloc_overflow));
}

static void scope_nested_stats_restore(void) {
  ScopeStats before = Scope.stats();
  Scope.retain();
  Scope.retain();
  Scope.malloc(16);
  ScopeStats nested = Scope.stats();
  EXPECT_INT_EQ(nested.live_scopes, before.live_scopes + 2);
  EXPECT_INT_EQ(nested.live_allocations, before.live_allocations + 1);
  Scope.release();
  Scope.release();
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

static void scope_release_requires_matching_retain(void) {
  EXPECT_TRUE(_scope_rejected(_release_without_retain));
  EXPECT_TRUE(_scope_rejected(_release_wrong_slot));
  Scope.retain();
  Scope.release();
  EXPECT_TRUE(1);
}

static void scope_stack_grows_and_restores(void) {
  Scope slots[20] = { NULL }, *before = Scope.top();
  for (int i = 0; i < 20; i++) {
    Scope.push(&slots[i]);
    Scope.malloc(1);
  }
  EXPECT_TRUE(Scope.top() == &slots[19]);
  for (int i = 19; i >= 0; i--) {
    Scope.pop();
    Scope.destroy(slots[i]);
  }
  EXPECT_TRUE(Scope.top() == before);
}

static void _move_without_slot(void) {
  Scope.retain();
  void *ptr = Scope.malloc(4);
  Scope.move(ptr, NULL);
}

static void scope_move_between_scopes(void) {
  ScopeStats before = Scope.stats();
  Scope from = Scope.new_named("move-from"), to = Scope.new_named("move-to");
  char *a = Scope.malloc_in(&from, 16);
  char *b = Scope.malloc_in(&from, 16);
  char *c = Scope.malloc_in(&from, 16);
  fill(a, "alpha");
  fill(b, "beta");
  fill(c, "gamma");
  Scope.move(b, &to);  // middle of the source list
  Scope.move(c, &to);  // head of the source list
  Scope.destroy(from);
  EXPECT_STR_EQ(b, "beta");
  EXPECT_STR_EQ(c, "gamma");
  Scope.destroy(to);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls + 3);
  EXPECT_INT_EQ(after.free_calls, before.free_calls + 3);
  EXPECT_TRUE(_scope_rejected(_move_without_slot));
}

static void scope_move_materializes_and_self_moves(void) {
  ScopeStats before = Scope.stats();
  Scope.move(NULL, NULL);  // NULL pointer is a no-op even without a slot
  Scope slot = NULL;
  Scope.retain();
  char *a = Scope.malloc(8);
  fill(a, "kept");
  Scope.move(a, &slot);  // materializes the destination scope
  Scope.release();
  EXPECT_NOT_NULL(slot);
  EXPECT_STR_EQ(a, "kept");
  Scope.move(a, &slot);  // self-move while at the head
  char *b = Scope.malloc_in(&slot, 8);
  fill(b, "second");
  Scope.move(a, &slot);  // self-move while not at the head
  EXPECT_STR_EQ(a, "kept");
  EXPECT_STR_EQ(b, "second");
  Scope.destroy(slot);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
}

static void scope_destroy_detached_contract(void) {
  ScopeStats before = Scope.stats();
  Scope.destroy(NULL);
  ScopeStats after_null = Scope.stats();
  EXPECT_INT_EQ(after_null.scope_destructions, before.scope_destructions);

  Scope slot = NULL;
  Scope.push(&slot);
  Scope.retain();
  Scope.malloc(4);
  Scope.retain();
  Scope.malloc(8);
  Scope.pop();
  Scope.destroy(slot);

  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.scope_creations, before.scope_creations + 2);
  EXPECT_INT_EQ(after.scope_destructions, before.scope_destructions + 2);
  EXPECT_INT_EQ(after.free_calls, before.free_calls + 2);

  EXPECT_TRUE(_scope_rejected(_destroy_active_root));
  EXPECT_TRUE(_scope_rejected(_destroy_active_pushed));
  EXPECT_TRUE(_scope_rejected(_destroy_outer_stack_slot));
  EXPECT_TRUE(_scope_rejected(_destroy_attached_lower));
}

static int drop_count;
static void *drop_order[4];

static void _count_drop(void *ptr) {
  drop_order[drop_count < 4 ? drop_count : 3] = ptr;
  drop_count++;
}

static Scope dying_scope;

static void _scratch_drop(void *ptr) {
  (void) ptr;
  Scope.malloc_in(&dying_scope, 8);
  drop_count++;
}

static void _finalize_without_drop(void) {
  Scope.retain();
  Scope.malloc_finalized(8, NULL);
}

static void scope_finalizer_runs_once(void) {
  ScopeStats before = Scope.stats();
  drop_count = 0;
  Scope.retain();
  char *a = Scope.malloc_finalized(16, _count_drop);
  fill(a, "finalized");
  EXPECT_INT_EQ(drop_count, 0);
  Scope.release();
  EXPECT_INT_EQ(drop_count, 1);
  EXPECT_TRUE(drop_order[0] == a);

  drop_count = 0;
  Scope.retain();
  char *b = Scope.malloc_finalized(16, _count_drop);
  char *c = Scope.malloc_finalized(16, _count_drop);
  Scope.free(b);
  EXPECT_INT_EQ(drop_count, 1);
  EXPECT_TRUE(Scope.realloc(c, 0) == NULL);
  EXPECT_INT_EQ(drop_count, 2);
  Scope.release();
  EXPECT_INT_EQ(drop_count, 2);

  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.free_calls, before.free_calls + 3);
  EXPECT_TRUE(_scope_rejected(_finalize_without_drop));
}

static void scope_finalizer_order_and_move(void) {
  ScopeStats before = Scope.stats();
  drop_count = 0;
  Scope from = Scope.new_named("finalize-from"), to = NULL;
  char *a = Scope.malloc_finalized_in(&from, 8, _count_drop);
  char *plain = Scope.malloc_in(&from, 8);
  char *b = Scope.malloc_finalized_in(&from, 8, _count_drop);
  char *c = Scope.malloc_finalized_in(&from, 8, _count_drop);
  fill(plain, "plain");
  Scope.move(b, &to);  // middle of the source list
  Scope.move(c, &to);  // head of the source list
  Scope.move(c, &to);  // self-move keeps the finalizer
  Scope.destroy(from);
  EXPECT_INT_EQ(drop_count, 1);
  EXPECT_TRUE(drop_order[0] == a);
  Scope.destroy(to);
  EXPECT_INT_EQ(drop_count, 3);
  EXPECT_TRUE(drop_order[1] == c);  // most recent block first
  EXPECT_TRUE(drop_order[2] == b);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
}

static void scope_finalizer_realloc_and_scratch(void) {
  ScopeStats before = Scope.stats();
  drop_count = 0;
  Scope.retain();
  Scope.malloc(8);
  char *a = Scope.malloc_finalized(8, _count_drop);
  Scope.malloc(8);
  fill(a, "grow");
  a = Scope.realloc(a, 4096);
  EXPECT_STR_EQ(a, "grow");
  a = Scope.realloc(a, 8);
  EXPECT_STR_EQ(a, "grow");
  Scope.release();
  EXPECT_INT_EQ(drop_count, 1);
  EXPECT_TRUE(drop_order[0] == a);

  dying_scope = Scope.new_named("finalize-scratch");
  Scope.malloc_finalized_in(&dying_scope, 8, _scratch_drop);
  Scope.destroy(dying_scope);
  dying_scope = NULL;
  EXPECT_INT_EQ(drop_count, 2);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
  EXPECT_INT_EQ(after.reallocation_calls, before.reallocation_calls + 2);
}

$(import "test-macros.xmacro")

void scope_suite(void) {
  $test.run(scope_alloc_release);
  $test.run(scope_push_pop_destroy);
  $test.run(scope_realloc_grows_and_shrinks);
  $test.run(scope_free_unlinks_any_position);
  $test.run(scope_realloc_updates_any_position);
  $test.run(scope_named_direct_allocation);
  $test.run(scope_allocator_edge_behavior);
  $test.run(scope_size_limits_are_terminal);
  $test.run(scope_nested_stats_restore);
  $test.run(scope_release_requires_matching_retain);
  $test.run(scope_move_between_scopes);
  $test.run(scope_move_materializes_and_self_moves);
  $test.run(scope_stack_grows_and_restores);
  $test.run(scope_destroy_detached_contract);
  $test.run(scope_finalizer_runs_once);
  $test.run(scope_finalizer_order_and_move);
  $test.run(scope_finalizer_realloc_and_scratch);
}
