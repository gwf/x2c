/*  scope-shutdown.x -- subprocess probes for terminal Scope behavior */

#include "x2c.x"

#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int hook_order[2], hook_count;

static void hook_one(void) { hook_order[hook_count++] = 1; }
static void hook_two(void) {
  Scope.retain();
  xmalloc(8);
  Scope.release();
  hook_order[hook_count++] = 2;
}

typedef struct LiveThreadInput {
  atomic_int *ready;
} LiveThreadInput;

static Var live_match_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(LiveThreadInput)) return void;
  const LiveThreadInput *state = input;
  int matched = 0;
  match (%(worker 47)) {
    case %(worker ?value): matched = value.int() == 47;
  }
  atomic_store(state.ready, matched);
  while (atomic_load(state.ready)) sched_yield();
  return matched;
}

static void print_drop(void *ptr) {
  (void) ptr;
  puts("drop");
}

static Var finalizer_worker(const void *input, size_t input_size) {
  (void) input;
  (void) input_size;
  Scope.malloc_finalized(8, print_drop);
  return 1;
}

static Var completed_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(LiveThreadInput)) return void;
  const LiveThreadInput *state = input;
  atomic_store(state.ready, 1);
  return 47;
}

static int accounting_drops;

static void accounting_drop(void *ptr) {
  (void) ptr;
  accounting_drops++;
}

static int zero_stats(ScopeStats stats) =>
  !(stats.allocation_calls | stats.reallocation_calls | stats.free_calls |
    stats.live_allocations | stats.scope_creations | stats.scope_destructions |
    stats.live_scopes | stats.requested_bytes | stats.largest_request |
    stats.live_requested_bytes | stats.peak_live_requested_bytes);

static int accounting_mode(int enabled) {
  if (Scope.accounting_enabled() != enabled) return 1;
  ScopeStats before = Scope.stats();
  if (!enabled && !zero_stats(before)) return 1;
  char name[] = "accounting probe";
  Scope work = Scope.new_named(name);
  name[0] = 'x';
  if (strcmp(work.name(), "accounting probe")) return 1;
  Scope unnamed = Scope.new(), neighbor = Scope.new_named("neighbor");
  if (Scope.name(NULL) || unnamed.name()) return 1;
  unnamed.destroy();
  neighbor.destroy();
  if (strcmp(work.name(), "accounting probe")) return 1;
  void *ptr = Scope.malloc_finalized_in(&work, 8, accounting_drop);
  ptr = xrealloc(ptr, 16);
  if (!ptr) return 1;
  setenv("X2C_SCOPE_ACCOUNTING", enabled ? "0" : "1", 1);
  Scope.initialize();
  if (Scope.accounting_enabled() != enabled) return 1;
  work.destroy();
  ScopeStats after = Scope.stats();
  if (accounting_drops != 1) return 1;
  if (enabled) {
    if (after.allocation_calls != before.allocation_calls + 1 ||
        after.reallocation_calls != before.reallocation_calls + 1 ||
        after.free_calls != before.free_calls + 1 ||
        after.scope_creations != before.scope_creations + 3 ||
        after.scope_destructions != before.scope_destructions + 3 ||
        after.requested_bytes != before.requested_bytes + 24 ||
        after.live_requested_bytes != before.live_requested_bytes)
      return 1;
  }
  else if (!zero_stats(after)) return 1;
  Scope_shutdown();
  return Scope.accounting_enabled() != enabled;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  if (!strcmp(argv[1], "accounting-off")) return accounting_mode(0);
  if (!strcmp(argv[1], "accounting-on")) return accounting_mode(1);

  if (!strcmp(argv[1], "clean")) {
    Scope.retain();
    xmalloc(8);
    Scope.release();
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations ||
           stats.live_requested_bytes;
  }

  if (!strcmp(argv[1], "leak")) {
    Scope leaked = Scope.new_named("probe leak");
    Scope.malloc_in(&leaked, 8);
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes != 1 || stats.live_allocations != 1 ||
           stats.live_requested_bytes != 8;
  }

  if (!strcmp(argv[1], "repeat")) {
    Scope_shutdown();
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations ||
           stats.live_requested_bytes;
  }

  if (!strcmp(argv[1], "thread-state")) {
    (void) Scope.top();
    (void) Error.ready();
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    if (stats.live_scopes || stats.live_allocations ||
        stats.live_requested_bytes) return 1;
    x2c_thread_state_release();
    stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations ||
           stats.live_requested_bytes;
  }

  if (!strcmp(argv[1], "hooks")) {
    Scope.shutdown_hook(hook_one);
    Scope.shutdown_hook(hook_two);
    Scope_shutdown();
    return hook_count != 2 || hook_order[0] != 2 || hook_order[1] != 1;
  }

  if (!strcmp(argv[1], "overflow")) {
    int caught = 0;
    try {
      xmalloc(SIZE_MAX);
    }
    catch %(size-limit *): caught++;
    try {
      xcalloc(SIZE_MAX, 2);
    }
    catch %(size-limit *): caught++;
    Scope_shutdown();
    return caught != 2;
  }

  if (!strcmp(argv[1], "after")) {
    Scope_shutdown();
    xmalloc(8);
    return 1;
  }

  if (!strcmp(argv[1], "push-null")) {
    int caught = 0;
    try {
      Scope.push(NULL);
    }
    catch %(bad-arg *): caught++;
    return caught != 1;
  }

  if (!strcmp(argv[1], "slot-null")) {
    int caught = 0;
    try {
      Scope.malloc_in(NULL, 8);
    }
    catch %(bad-arg *): caught++;
    return caught != 1;
  }

  if (!strcmp(argv[1], "hook-null")) {
    int caught = 0;
    try {
      Scope.shutdown_hook(NULL);
    }
    catch %(bad-arg *): caught++;
    return caught != 1;
  }

  if (!strcmp(argv[1], "live-thread-match")) {
    atomic_int ready = 0;
    LiveThreadInput input = { &ready };
    Thread thread = Thread.start_raw(
      live_match_worker, &input, sizeof(input)
    );
    while (!atomic_load(&ready)) sched_yield();
    (void) thread;
    Scope_shutdown();
    return 1;
  }

  if (!strcmp(argv[1], "finalizer-shutdown")) {
    Scope.malloc_finalized(8, print_drop);
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations ||
           stats.live_requested_bytes;
  }

  if (!strcmp(argv[1], "finalizer-thread")) {
    Thread thread = Thread.start_raw(finalizer_worker, NULL, 0);
    Var result = Thread.join(thread);
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return result.int() != 1 || stats.live_scopes || stats.live_allocations ||
           stats.live_requested_bytes;
  }

  if (!strcmp(argv[1], "completed-thread")) {
    atomic_int ready = 0;
    LiveThreadInput input = { &ready };
    Thread thread = Thread.start_raw(
      completed_worker, &input, sizeof(input)
    );
    Thread.wait_any([thread]);
    Scope_shutdown();
    return 1;
  }

  return 2;
}
