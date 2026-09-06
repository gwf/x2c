/*  scope-shutdown.x -- subprocess probes for terminal Scope behavior */

#include "x2c.x"

#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

static int hook_order[2], hook_count;

static void hook_one(void) { hook_order[hook_count++] = 1; }
static void hook_two(void) {
  Scope.retain();
  Scope.malloc(8);
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

static Var completed_worker(const void *input, size_t input_size) {
  if (input_size != sizeof(LiveThreadInput)) return void;
  const LiveThreadInput *state = input;
  atomic_store(state.ready, 1);
  return 47;
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;

  if (!strcmp(argv[1], "clean")) {
    Scope.retain();
    Scope.malloc(8);
    Scope.release();
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations;
  }

  if (!strcmp(argv[1], "leak")) {
    Scope leaked = Scope.new_named("probe leak");
    Scope.malloc_in(&leaked, 8);
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes != 1 || stats.live_allocations != 1;
  }

  if (!strcmp(argv[1], "repeat")) {
    Scope_shutdown();
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations;
  }

  if (!strcmp(argv[1], "thread-state")) {
    (void) Scope.top();
    (void) Error.ready();
    Scope_shutdown();
    ScopeStats stats = Scope.stats();
    if (stats.live_scopes || stats.live_allocations) return 1;
    x2c_thread_state_release();
    stats = Scope.stats();
    return stats.live_scopes || stats.live_allocations;
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
      Scope.malloc(SIZE_MAX);
    }
    catch %(size-limit *): caught++;
    try {
      Scope.calloc(SIZE_MAX, 2);
    }
    catch %(size-limit *): caught++;
    Scope_shutdown();
    return caught != 2;
  }

  if (!strcmp(argv[1], "after")) {
    Scope_shutdown();
    Scope.malloc(8);
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
    Thread thread = Thread.start(
      live_match_worker, &input, sizeof(input)
    );
    while (!atomic_load(&ready)) sched_yield();
    (void) thread;
    Scope_shutdown();
    return 1;
  }

  if (!strcmp(argv[1], "completed-thread")) {
    ScopeStats before = Scope.stats();
    atomic_int ready = 0;
    LiveThreadInput input = { &ready };
    Thread thread = Thread.start(
      completed_worker, &input, sizeof(input)
    );
    while (!atomic_load(&ready)) sched_yield();
    while (Scope.stats().live_scopes != before.live_scopes + 2)
      sched_yield();
    (void) thread;
    Scope_shutdown();
    return 1;
  }

  return 2;
}
