/*  scope.x -- memory allocation scope management

    Copyright (c) 2025 Gary William Flake

    `Scope` owns groups of individually managed allocations. Callers may use
    the active scope, target an explicit scope slot, or retain and release a
    nested lifetime. Explicit free and realloc remain valid for allocations
    returned by `Scope.malloc`, `Scope.calloc`, and `Scope.memdup`, and
    `Scope.move`
    relinks one allocation onto another scope without copying it.

    `Scope.initialize` owns runtime initialization, while public operations
    also
    initialize safely when called before the runtime aggregator. Shutdown
    hooks run in reverse registration order, after which the module enters a
    terminal state.  `Scope.stats` remains available after shutdown so callers
    and tests can inspect the final state.
 */

#pragma once
$(import "error-macros.xmacro")
#include <stddef.h>
#include <stdatomic.h>

#include "common.x"

/** Intrusive header stored immediately before each `Scope`-owned allocation.
    Its links are allocator-managed; callers must not construct or mutate it.
*/
typedef struct ScopeAlloc {
  struct ScopeAlloc *prev, *next;
} *ScopeAlloc;

/** Handle for a region and any retained regions linked below it.
    The layout is public; only `Scope` operations create or mutate valid
    allocation and region links.
*/
typedef struct Scope {
  ScopeAlloc first;
  struct Scope *down, *up;
} *Scope;

/** Value snapshot of process-wide `Scope` allocation and lifetime counters.
    It owns no storage; live counts are derived when the snapshot is taken.
*/
typedef struct ScopeStats {
  size_t allocation_calls, reallocation_calls, free_calls, live_allocations;
  size_t scope_creations, scope_destructions, live_scopes, requested_bytes;
  size_t largest_request;
} ScopeStats;

#include <stdlib.h>
#pragma private

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Native allocation alignment leaves the low pointer bit clear. At a list
   head, `prev` stores the owning Scope with that bit set; every other `prev`
   is the untagged preceding ScopeAlloc. Free, move, realloc, and owner lookup
   all rely on relinking without losing this one in-band ownership marker. */
#define PTR_ALLOC(p)      ((ScopeAlloc) ((char *) (p) - sizeof(struct ScopeAlloc)))
#define ALLOC_PTR(a)      ((void *) ((char *) (a) + sizeof(struct ScopeAlloc)))
#define TAG_POINTER(p)    ((void *) ((uintptr_t) (p) | (uintptr_t) 1))
#define UNTAG_POINTER(p)  ((void *) ((uintptr_t) (p) & ~(uintptr_t) 1))
#define IS_TAGGED(p)      ((uintptr_t) (p) & (uintptr_t) 1)

/* A finalized allocation keeps its destructor in a prefix ahead of the
   public header, so the header layout and payload alignment are unchanged
   and only finalized blocks pay for the field. Bit 0 of `next` marks one;
   every read or write of `next` goes through NEXT and SET_NEXT. */
typedef struct ScopeFinalizer {
  void (*drop)(void *);
  void *pad;
} ScopeFinalizer;

#define IS_FINALIZED(a)   ((uintptr_t) (a)->next & (uintptr_t) 1)
#define NEXT(a)           ((ScopeAlloc) UNTAG_POINTER((a)->next))
#define SET_NEXT(a, n) \
  ((a)->next = (ScopeAlloc) ((uintptr_t) (n) | IS_FINALIZED(a)))
#define ALLOC_BASE(a) \
  ((void *) ((char *) (a) - (IS_FINALIZED(a) ? sizeof(ScopeFinalizer) : 0)))
#define ALLOC_DROP(a)     (((ScopeFinalizer *) (a))[-1].drop)

typedef struct ScopeName {
  Scope scope, char *name, struct ScopeName *next;
} *ScopeName;

typedef struct ScopeRetain {
  Scope scope, *slot;
} ScopeRetain;

typedef struct ScopeThreadState {
  Scope root, *active, **stack, int stack_size, stack_capacity;
  ScopeRetain *retains;
  int retain_count, retain_capacity;
} *ScopeThreadState;

static threaded struct ScopeThreadState scope_thread;

static ScopeThreadState _thread(void) {
  ScopeThreadState state = &scope_thread;
  if (!state.active) state.active = &state.root;
  return state;
}

static Symbol scope_state = <uninit>;
static void(**hooks)(void);
static int hook_count, hook_capacity;
static ScopeName scope_names;
static atomic_size_t scope_allocation_calls, scope_reallocation_calls;
static atomic_size_t scope_free_calls, scope_creations, scope_destructions;
static atomic_size_t scope_requested_bytes, scope_largest_request;
static atomic_size_t raw_alloc_count, raw_free_count;
static pthread_mutex_t scope_metadata_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

static void _metadata_lock(void) {
  if (pthread_mutex_lock(&scope_metadata_mutex))
    _raw_fatal("could not lock metadata");
}

static void _metadata_unlock(void) {
  if (pthread_mutex_unlock(&scope_metadata_mutex))
    _raw_fatal("could not unlock metadata");
}

static void _record_request(size_t size) {
  atomic_fetch_add_explicit(
    &scope_requested_bytes, size, memory_order_relaxed);
  size_t old = atomic_load(&scope_largest_request);
  while (size > old && !atomic_compare_exchange_weak(
    &scope_largest_request, &old, size)) {}
}

static void _raw_fatal(const char *message) {
  fprintf(stderr, "Scope: %s\n", message);
  abort();
}

static void *_raw_malloc(size_t size) {
  void *ptr = malloc(size);
  if (!ptr) raise %(alloc-fail);
  atomic_fetch_add(&raw_alloc_count, 1);
  return ptr;
}

static void _raw_free(void *ptr) {
  if (!ptr) return;
  atomic_fetch_add(&raw_free_count, 1);
  free(ptr);
}

static void *_raw_realloc(void *ptr, size_t size) {
  void *result = realloc(ptr, size);
  if (!result) raise %(alloc-fail);
  return result;
}

static void _initialize(void) {
  if (scope_state == <running> || scope_state == <shutting>) return;
  if (scope_state == <shutdown>)
    _raw_fatal("operation attempted after shutdown");
  ScopeThreadState state = _thread();
  state.active = &state.root;
  scope_state = <running>;
  if (atexit(Scope_shutdown))
    _raw_fatal("could not register shutdown handler");
}

static void _ensure_running(void) {
  if (scope_state == <uninit>) _initialize();
  else if (scope_state == <shutdown>)
    _raw_fatal("operation attempted after shutdown");
}

static void _require_running(void) {
  if (scope_state != <running>) _ensure_running();
}

static void *_data_malloc(size_t size) {
  void *ptr = malloc(size);
  if (!ptr) raise %(alloc-fail);
  return ptr;
}

static void *_data_realloc(void *ptr, size_t size) {
  void *result = realloc(ptr, size);
  if (!result) raise %(alloc-fail);
  return result;
}

static ScopeName _find_name(Scope scope) {
  _metadata_lock();
  for (ScopeName node = scope_names; node; node = node.next)
    if (node.scope == scope) {
      _metadata_unlock();
      return node;
    }
  _metadata_unlock();
  return NULL;
}

static void _register_name(Scope scope, const char *name) {
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

static void _unregister_name(Scope scope) {
  _metadata_lock();
  ScopeName *link = &scope_names;
  while (*link) {
    ScopeName node = *link;
    if (node.scope == scope) {
      *link = node.next;
      _raw_free(node.name);
      _raw_free(node);
      _metadata_unlock();
      return;
    }
    link = &node.next;
  }
  _metadata_unlock();
}

static void _record_retain(Scope scope, Scope *slot) {
  ScopeThreadState state = _thread();
  if (!state.retains) {
    state.retain_capacity = 16;
    state.retains = _raw_malloc(
      state.retain_capacity * sizeof(*state.retains));
  }
  else if (state.retain_count == state.retain_capacity) {
    if (state.retain_capacity > INT_MAX / 2) raise %(size-limit);
    int new_capacity = state.retain_capacity * 2;
    state.retains = _raw_realloc(
      state.retains, new_capacity * sizeof(*state.retains));
    state.retain_capacity = new_capacity;
  }
  state.retains[state.retain_count++] =
    (ScopeRetain) { .scope = scope, .slot = slot };
}

static int _forget_retain(Scope scope, Scope *slot) {
  ScopeThreadState state = _thread();
  for (int i = state.retain_count - 1; i >= 0; i--) {
    if (state.retains[i].scope != scope ||
        state.retains[i].slot != slot) continue;
    state.retains[i] = state.retains[--state.retain_count];
    return 1;
  }
  return 0;
}

static void _forget_chain_retains(Scope scope) {
  ScopeThreadState state = _thread();
  for (Scope cur = scope; cur; cur = cur.down)
    for (int i = state.retain_count - 1; i >= 0; i--)
      if (state.retains[i].scope == cur)
        state.retains[i] = state.retains[--state.retain_count];
}

static Scope _new_scope(const char *name) {
  Scope scope = _data_malloc(sizeof(struct Scope));
  scope.up = scope.down = NULL;
  scope.first = NULL;
  _register_name(scope, name);
  atomic_fetch_add(&scope_creations, 1);
  return scope;
}

static void *_malloc_in(Scope *slot, size_t size, void (*drop)(void *)) {
  size_t extra = drop ? sizeof(ScopeFinalizer) : 0;
  if (!slot) raise %(bad-arg);
  if (size > SIZE_MAX - sizeof(struct ScopeAlloc) - extra) {
    if (x2c_error_runtime_ready) raise %(size-limit);
    _raw_fatal("allocation size overflow");
  }
  if (!*slot) *slot = _new_scope(NULL);
  Scope scope = *slot;
  char *base = _data_malloc(size + sizeof(struct ScopeAlloc) + extra);
  ScopeAlloc alloc = (ScopeAlloc) (base + extra);
  if (drop) {
    ScopeFinalizer *finalizer = (ScopeFinalizer *) base;
    finalizer.drop = drop;
    alloc.next = TAG_POINTER(scope.first);
  }
  else alloc.next = scope.first;
  alloc.prev = TAG_POINTER(scope);
  if (scope.first) scope.first.prev = alloc;
  scope.first = alloc;
  atomic_fetch_add(&scope_allocation_calls, 1);
  _record_request(size);
  return ALLOC_PTR(alloc);
}

static void *_calloc_in(Scope *slot, size_t count, size_t size) {
  if (count && size > SIZE_MAX / count) {
    if (x2c_error_runtime_ready) raise %(size-limit);
    _raw_fatal("calloc size overflow");
  }
  size_t total = count * size, void *ptr = _malloc_in(slot, total, NULL);
  if (ptr && total) memset(ptr, 0, total);
  return ptr;
}

static void *_memdup_in(Scope *slot, const void *ptr, size_t size) {
  if (!ptr || !size) return NULL;
  void *copy = _malloc_in(slot, size, NULL);
  memcpy(copy, ptr, size);
  return copy;
}

/* The block is already unlinked, so a drop that allocates or frees other
   storage sees a consistent list. */
static void _release_alloc(ScopeAlloc alloc) {
  void *base = ALLOC_BASE(alloc);
  atomic_fetch_add(&scope_free_calls, 1);
  if (IS_FINALIZED(alloc)) ALLOC_DROP(alloc)(ALLOC_PTR(alloc));
  free(base);
}

static void _free_alloc(ScopeAlloc old) {
  ScopeAlloc next = NEXT(old), prev = old.prev;
  if (IS_TAGGED(prev)) {
    Scope scope = UNTAG_POINTER(prev);
    scope.first = next;
  }
  else if (prev) SET_NEXT(prev, next);
  if (next) next.prev = prev;
  _release_alloc(old);
}

/* Popping the head keeps the list valid while a finalizer runs, so scratch
   it allocates into the dying scope is reclaimed by the same loop. */
static void _destroy_chain(Scope scope) {
  while (scope) {
    Scope down = scope.down;
    ScopeAlloc alloc;
    while ((alloc = scope.first)) {
      scope.first = NEXT(alloc);
      if (scope.first) scope.first.prev = TAG_POINTER(scope);
      _release_alloc(alloc);
    }
    _unregister_name(scope);
    atomic_fetch_add(&scope_destructions, 1);
    free(scope);
    scope = down;
  }
}

/** Destroys this thread's `Scope` chain and its push and retain stacks. It
    runs
    last in `x2c_thread_state_release` and repeats harmlessly; a thread that
    never created a `Scope` has nothing to destroy.
*/
void x2c_scope_thread_release(void) {
  ScopeThreadState state = &scope_thread;
  if (state.root) _destroy_chain(state.root);
  state.root = NULL;
  _raw_free(state.stack);
  state.stack = NULL;
  state.stack_size = state.stack_capacity = 0;
  _raw_free(state.retains);
  state.retains = NULL;
  state.retain_count = state.retain_capacity = 0;
  state.active = &state.root;
}

static size_t _allocation_count(Scope scope) {
  size_t count = 0;
  for (ScopeAlloc alloc = scope ? scope.first : NULL; alloc;
       alloc = NEXT(alloc))
    count++;
  return count;
}

static void _report_leaks(void) {
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

static void _free_name_registry(void) {
  while (scope_names) {
    ScopeName next = scope_names.next;
    _raw_free(scope_names.name);
    _raw_free(scope_names);
    scope_names = next;
  }
}

/** Initializes the process-wide `Scope` runtime owner. */
void Scope.initialize(void) {
  _initialize();
}

/** Creates a detached, unnamed scope and returns it.
    A detached scope sits in no slot and is not active, so nothing is charged
    to it until you allocate through `Scope.malloc_in` and friends or make it
    active with `Scope.push`. End it with `Scope.destroy`. Prefer
    `Scope.new_named` for anything long-lived; the name appears in the
    exit-time leak report.
    Raises: `<alloc-fail>` when the scope cannot be allocated. Before `Error`
    initialization it terminates at the error floor.
*/
Scope Scope.new(void) {
  _require_running();
  return _new_scope(NULL);
}

/** Creates a detached scope carrying a copy of `name` for diagnostics.
    The name is copied, so a temporary buffer is fine. `Scope.name` reports
    it, and the allocator prints it at exit if anything the scope owns is
    still alive, as a line like `scope "request": 3 allocations`. A NULL
    `name` behaves like `Scope.new`.

    ```x2c
    ~int main(void) {
    Scope work = Scope.new_named("request");
    char *copy = Scope.memdup_in(&work, "payload", 8);
    puts(copy);
    Scope.destroy(work);
    ~  return 0;
    ~}
    ```
    Raises: `<alloc-fail>` when the scope or name copy cannot be allocated,
    or `<size-limit>` when the name is too large. Before `Error`
    initialization these failures terminate the process.
*/
Scope Scope.new_named(const char *name) {
  _require_running();
  return _new_scope(name);
}

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

/** Returns a snapshot of the allocator's counters.
    `live_allocations` and `live_scopes` are derived from the call counts, so
    read them before and after a routine to check that it leaves nothing
    behind. The snapshot also carries
    `allocation_calls`, `reallocation_calls`, `free_calls`,
    `scope_creations`, `scope_destructions`, `requested_bytes`, and
    `largest_request`. Stats remain valid after shutdown.

    ```x2c
    ~int main(void) {
    size_t before = Scope.stats().live_allocations;
    Scope.retain();
    char *scratch = Scope.malloc(128);
    scratch[0] = 0;
    Scope.release();
    printf("reclaimed = %d\n", Scope.stats().live_allocations == before);
    ~  return 0;
    ~}
    ```
*/
ScopeStats Scope.stats(void) {
  ScopeStats result = {
    .reallocation_calls = atomic_load(&scope_reallocation_calls),
    .requested_bytes = atomic_load(&scope_requested_bytes),
    .largest_request = atomic_load(&scope_largest_request)
  };
  do {
    result.allocation_calls = atomic_load(&scope_allocation_calls);
    result.free_calls = atomic_load(&scope_free_calls);
  } while (result.free_calls > result.allocation_calls);
  do {
    result.scope_creations = atomic_load(&scope_creations);
    result.scope_destructions = atomic_load(&scope_destructions);
  } while (result.scope_destructions > result.scope_creations);
  result.live_allocations = result.allocation_calls - result.free_calls;
  result.live_scopes = result.scope_creations - result.scope_destructions;
  return result;
}

/** Destroys a detached scope and frees every allocation it owns.
    This ends a scope you hold in a variable, and is the counterpart to
    `Scope.new` and `Scope.new_named`. It frees the scope's allocations and
    discards its name; pointers into it are dangling afterwards, and nothing
    diagnoses their use. Any regions still linked below it, from retains that
    were never released, are destroyed with it.

    `Scope.destroy` refuses a scope that is still in use, so a double destroy
    or a mismatched push and pop raises instead of corrupting the allocation
    lists. The three refused cases are the active root scope, a slot still on
    the pushed stack (pop it first), and a scope that a later `Scope.retain`
    layered another region on top of, which the runtime reports as an attached
    lower scope.
    Raises: `<bad-state>` for the active root, a pushed slot, or an attached
    lower scope. The failure leaves the scope intact. A NULL `scope` does
    nothing. Before `Error` initialization it terminates at the error floor.
*/
void Scope.destroy(Scope scope) {
  if (!scope) return;
  _require_running();
  ScopeThreadState state = _thread();
  if (scope == state.root) raise %(bad-state);
  for (int i = 0; i < state.stack_size; i++)
    if (scope == *state.stack[i]) raise %(bad-state);
  if (scope.up) raise %(bad-state);
  _forget_chain_retains(scope);
  _destroy_chain(scope);
}

/** Registers `hook` to run during process-wide `Scope` shutdown.
    The function pointer is retained without being invoked. Shutdown invokes
    registrations once in reverse order while `Scope` storage is still
    available.

    Raises: `<bad-arg>` for a null hook, `<size-limit>` when the registry
    cannot grow, or `<alloc-fail>` when its storage cannot be allocated.
*/
void Scope.shutdown_hook(void (*hook)(void)) {
  _require_running();
  if (!hook) raise %(bad-arg);
  if (!hooks) {
    hook_capacity = 16;
    hooks = _raw_malloc(hook_capacity * sizeof(*hooks));
  }
  else if (hook_count == hook_capacity) {
    if (hook_capacity > INT_MAX / 2) raise %(size-limit);
    int new_capacity = hook_capacity * 2;
    hooks = _raw_realloc(hooks, new_capacity * sizeof(*hooks));
    hook_capacity = new_capacity;
  }
  hooks[hook_count++] = hook;
}

/** Makes the scope in `scope` active until a matching `Scope.pop`.
    `scope` is the address of a caller-owned `Scope` variable, and it may hold
    NULL: the slot is filled lazily by the first allocation that lands in it.
    Pushing lets several operations share one lifetime without threading a
    slot through every call. Slots stack, and each push needs one pop.

    ```x2c
    ~int main(void) {
    Scope work = NULL;
    Scope.push(&work);
    char *buffer = Scope.malloc(16);
    snprintf(buffer, 16, "in work");
    Scope.pop();
    puts(buffer);
    Scope.destroy(work);
    ~  return 0;
    ~}
    ```

    The pointer stays valid after the pop. Popping changes which slot is
    active; `work` still owns the allocation until it is destroyed. A pushed
    slot cannot be destroyed while it is on the stack.
    Raises: `<bad-arg>` when `scope` is NULL, `<size-limit>` when the stack
    cannot grow within its representation, or `<alloc-fail>` when its storage
    cannot be allocated. These failures leave the active slot unchanged.
    Before `Error` initialization they terminate at the error floor.
*/
void Scope.push(Scope *scope) {
  _require_running();
  if (!scope) raise %(bad-arg);
  ScopeThreadState state = _thread();
  if (!state.stack) {
    state.stack_capacity = 16;
    state.stack = _raw_malloc(state.stack_capacity * sizeof(*state.stack));
  }
  else if (state.stack_size == state.stack_capacity) {
    if (state.stack_capacity > INT_MAX / 2) raise %(size-limit);
    int new_capacity = state.stack_capacity * 2;
    state.stack = _raw_realloc(
      state.stack, new_capacity * sizeof(*state.stack));
    state.stack_capacity = new_capacity;
  }
  state.active = state.stack[state.stack_size++] = scope;
}

/** Returns the address of the active scope slot.
    The result is the slot, not the scope. Pass it to the `_in` allocators to
    name the active slot explicitly. Dereferencing it gives the scope, which
    may be NULL before anything has been allocated into the slot. It names the
    slot that was active at the call; a later `Scope.push`, `Scope.pop`,
    `Scope.retain`, or `Scope.release` changes which slot is active, so read
    it again instead of caching it.
*/
Scope *Scope.top(void) {
  _require_running();
  return _thread().active;
}

/** Restores the slot that was active before the matching `Scope.push`.
    Popping frees nothing. The popped slot keeps its scope and every
    allocation in it, so you can destroy that scope later or pass it
    elsewhere. With no pushes outstanding, the process root slot becomes
    active again.
    Raises: `<bad-state>` when the scope stack is empty, so a mismatched push
    and pop raises instead of redirecting allocations. The failure leaves the
    active slot unchanged. Before `Error` initialization it terminates at the
    error floor.
*/
void Scope.pop(void) {
  _require_running();
  ScopeThreadState state = _thread();
  if (!state.stack_size) raise %(bad-state);
  state.stack_size--;
  state.active = state.stack_size ? state.stack[state.stack_size - 1]
    : &state.root;
}

/** Opens a new scope in the active slot and makes it the current one.
    Allocations that follow are charged to the new scope. The scope that was
    there is linked below it and becomes current again on release, so retained
    regions nest. Open a nested region when a group of temporaries should die
    before the surrounding work does. Each `Scope.retain` must be paired with
    exactly one `Scope.release`.

    Pair them with `defer`. `Error` transfer does not release a scope. A raise
    that jumps past a plain `Scope.release` leaves that region live for the
    rest of the process, so use `defer` in any function that both retains and
    can raise.

    ```x2c
    ~static void report(int width) {
    Scope.retain();
    defer Scope.release();
    char *line = Scope.malloc(width + 1);
    snprintf(line, width + 1, "%d bytes", width);
    puts(line);
    ~}
    ~
    ~int main(void) {
    ~  report(16);
    ~  return 0;
    ~}
    ```

    A scope wrapped around nothing but canonical values does nothing, since
    those values already outlive it, and adds a release that is easy to omit.
    Raises: `<alloc-fail>` when the scope or its retain record cannot be
    allocated, or `<size-limit>` when that record cannot grow. Before `Error`
    initialization they terminate at the error floor.
*/
void Scope.retain(void) {
  _require_running();
  Scope scope = _new_scope(NULL);
  ScopeThreadState state = _thread();
  _record_retain(scope, state.active);
  if (*state.active) {
    scope.down = *state.active;
    (*state.active).up = scope;
  }
  *state.active = scope;
}

/** Destroys the scope in the active slot and frees everything it owns.
    Every allocation charged to that scope is freed: `Scope.malloc`,
    `Scope.calloc`, and `Scope.memdup` results, and the backing storage of the
    `Block`s, `Array`s, `Buffer`s, and boxed wide `Var`s built while it was
    active.
    The scope linked below it then becomes active again.

    Canonical values are not reclaimed. Interned `String`s, `List` cells, and
    `Symbol`s built inside the region remain valid after release.
    An allocation relinked with `Scope.move` now belongs to its new scope and
    survives. Anything owned by another scope or another slot is untouched,
    and memory from plain `malloc` is unaffected.

    The active region must be the one opened by a matching `Scope.retain` on
    this same slot. Releasing an empty slot, a directly allocated root, or a
    region retained on another pushed slot is an imbalance and raises. An
    extra release cannot destroy the surrounding region, and a retained empty
    scope still closes normally.

    A pointer into a released region is not diagnosed. Neither the compiler
    nor the runtime tracks it, and using it afterwards is undefined behavior.
    `Scope.stats` confirms that a routine leaves nothing live.
    Raises: `<bad-state>` when no matching retain owns the active region. The
    failure leaves the active region intact. Before `Error` initialization it
    terminates at the error floor.
*/
void Scope.release(void) {
  _require_running();
  ScopeThreadState state = _thread();
  with state.active as active {
    if (!*active || !_forget_retain(*active, active)) raise %(bad-state);
    Scope top = *active;
    /* Restore and detach the surviving lower region before destruction, so
       the active slot never names freed storage and `_destroy_chain` cannot
       follow `down` into the surrounding lifetime. */
    if ((*active = top.down)) (*active).up = NULL;
    top.down = NULL;
    _destroy_chain(top);
  }
}

/** Allocates `size` uninitialized bytes in the active scope.
    The result is managed memory. `Scope.realloc` resizes it, `Scope.free`
    ends its life early, `Scope.move` reassigns its owner, and
    `Scope.release` or `Scope.destroy` reclaims whatever is left. The active
    scope at the time of allocation owns the result; a later retain or push
    does not move it.
    Raises: `<size-limit>` when the size would overflow the allocation header,
    or `<alloc-fail>` when the underlying allocation fails. Before `Error`
    initialization they terminate at the error floor.
*/
void *Scope.malloc(size_t size) {
  _require_running();
  return _malloc_in(_thread().active, size, NULL);
}

/** Allocates `size` uninitialized bytes in the active scope with a finalizer.
    `drop` runs exactly once with the block's pointer when the block is
    reclaimed: by `Scope.free`, by `Scope.realloc` to size zero, by the
    release or destruction of its scope, or by thread and process shutdown.
    The finalizer follows the block through `Scope.move` and survives
    `Scope.realloc`, which passes `drop` the resized pointer. Blocks are
    reclaimed most recent first, so a finalizer sees older blocks still live.

    A wrapper for a native handle allocates its record this way and releases
    the handle from `drop`; an explicit early release that clears the field
    leaves nothing for the finalizer to do. `drop` runs on the thread that
    reclaims the block, with the block already unlinked, so it must not free
    or move the block itself. It must not raise. It may allocate into other
    scopes, and into the dying scope only for scratch the same destruction
    reclaims.
    Raises: `<bad-arg>` when `drop` is NULL, `<size-limit>` when the size
    would overflow the allocation header, or `<alloc-fail>` when the
    underlying allocation fails. Before `Error` initialization they
    terminate at the error floor.
*/
void *Scope.malloc_finalized(size_t size, void (*drop)(void *)) {
  _require_running();
  if (!drop) raise %(bad-arg);
  return _malloc_in(_thread().active, size, drop);
}

/** Allocates `size` uninitialized bytes in the scope held by `slot`.
    `slot` is the address of a `Scope` variable; if it holds NULL, a fresh
    unnamed scope is created and stored there. Targeting a slot does not
    touch the active-scope stack, so an intervening `Scope.retain` or
    `Scope.push` cannot redirect the allocation. Pass `Scope.top()` to name
    the active slot explicitly.
    Raises: `<bad-arg>` when `slot` is NULL, `<size-limit>` when the size
    overflows, or `<alloc-fail>` when allocation fails. Before `Error`
    initialization they terminate at the error floor.
*/
void *Scope.malloc_in(Scope *slot, size_t size) {
  _require_running();
  return _malloc_in(slot, size, NULL);
}

/** Allocates `size` bytes with finalizer `drop` in the scope held by `slot`.
    The slot-targeted form of `Scope.malloc_finalized`, with the same lazy
    scope creation as `Scope.malloc_in`; the active scope is left alone.
    Raises: `<bad-arg>` when `slot` or `drop` is NULL, `<size-limit>` when
    the size overflows, or `<alloc-fail>` when allocation fails. Before
    `Error` initialization they terminate at the error floor.
*/
void *Scope.malloc_finalized_in(
  Scope *slot, size_t size, void (*drop)(void *)
) {
  _require_running();
  if (!drop) raise %(bad-arg);
  return _malloc_in(slot, size, drop);
}

/** Allocates `count` objects of `size` bytes each, zeroed, in the active
    scope.
    The product is checked for overflow before anything is allocated, and the
    bytes are set to zero; in every other respect this behaves like
    `Scope.malloc`. A request that multiplies out to zero still returns a
    distinct pointer the scope owns, so it is not a failure signal.
    Raises: `<size-limit>` when the object count overflows, or `<alloc-fail>`
    when allocation fails. Before `Error` initialization they terminate at the
    error floor.
*/
void *Scope.calloc(size_t count, size_t size) {
  _require_running();
  return _calloc_in(_thread().active, count, size);
}

/** Allocates `count` zeroed objects of `size` bytes in the scope in `slot`.
    The slot-targeted form of `Scope.calloc`, with the same overflow check and
    the same lazy scope creation as `Scope.malloc_in`; the active scope is left
    alone.
    Raises: `<bad-arg>` when `slot` is NULL, `<size-limit>` when the object
    count overflows, or `<alloc-fail>` when allocation fails. Before `Error`
    initialization they terminate at the error floor.
*/
void *Scope.calloc_in(Scope *slot, size_t count, size_t size) {
  _require_running();
  return _calloc_in(slot, count, size);
}

/** Copies `size` bytes from `ptr` into a new allocation in the active scope.
    The copy is ordinary scope-owned memory, freed by `Scope.free` or by the
    release that ends the region. Nothing about the source is remembered, so
    duplicating a C string means copying its terminator too:
    `Scope.memdup(text, strlen(text) + 1)`.

    A NULL `ptr` or a zero `size` returns NULL rather than an empty
    allocation, so a duplicate of nothing is indistinguishable from failure;
    check the arguments yourself when that distinction matters.
    Raises: `<size-limit>` or `<alloc-fail>` from the underlying allocation.
    A NULL `ptr` or zero `size` returns NULL without raising.
*/
void *Scope.memdup(const void *ptr, size_t size) {
  _require_running();
  return _memdup_in(_thread().active, ptr, size);
}

/** Copies `size` bytes from `ptr` into the scope held by `slot`.
    The slot-targeted form of `Scope.memdup`, with the same NULL-for-nothing
    rule and the same lazy scope creation as `Scope.malloc_in`. It is the
    usual way to hand a snapshot of caller data to a scope that outlives the
    current region.
    Raises: `<bad-arg>` when `slot` is NULL, or `<size-limit>` or
    `<alloc-fail>` from the underlying allocation. A NULL `ptr` or zero
    `size` returns NULL without raising.
*/
void *Scope.memdup_in(Scope *slot, const void *ptr, size_t size) {
  _require_running();
  return _memdup_in(slot, ptr, size);
}

/** Frees one scope-owned allocation before its scope ends.
    `ptr` must be a pointer returned by `Scope.malloc`, `Scope.calloc`,
    `Scope.memdup`, one of their `_in` forms, or `Scope.realloc`. It is
    unlinked from whichever scope owns it now, which after a `Scope.move` may
    not be the active one.

    Shortening a lifetime this way is normal. Freeing anything else, such as a
    stack address, an interned `String`, or a plain `malloc` result, is
    undefined, as is freeing the same pointer twice. Nothing diagnoses
    either.

    A NULL `ptr` does nothing.
*/
void Scope.free(void *ptr) {
  _require_running();
  if (!ptr) return;
  _free_alloc(PTR_ALLOC(ptr));
}

/** Returns the `Scope` that currently owns `ptr`.
    `ptr` must be a live pointer returned by a `Scope` allocator. `Context`
    uses
    this to leave ancestor-owned objects where they are while moving results
    out of its own `Scope` chain. Passing any other nonnull pointer is
    undefined
    behavior, matching `Scope.free` and `Scope.move`.
*/
Scope Scope.owner(void *ptr) {
  _require_running();
  if (!ptr) return NULL;
  ScopeAlloc alloc = PTR_ALLOC(ptr);
  while (alloc && !IS_TAGGED(alloc.prev)) alloc = alloc.prev;
  return alloc ? UNTAG_POINTER(alloc.prev) : NULL;
}

/** Relinks one allocation onto the scope held by `slot`.
    The bytes are not copied and the pointer does not change; only ownership
    moves, so a temporary region can compute one result that outlives it. If
    `slot` holds NULL a fresh unnamed scope is created there, as the `_in`
    allocators do.

    ```x2c
    ~int main(void) {
    Scope keep = Scope.new_named("results");
    Scope.retain();
    char *text = Scope.memdup("survivor", 9);
    Scope.move(text, &keep);
    Scope.release();
    puts(text);
    Scope.destroy(keep);
    ~  return 0;
    ~}
    ```

    You do not need this for a `String`, a `List`, or a `Symbol`. Canonical
    values already outlive the scope that was active when they were built.
    Raises: `<bad-arg>` when `slot` is NULL, or `<alloc-fail>` when a new
    destination scope cannot be allocated. These failures leave ownership
    unchanged. A NULL `ptr` does nothing. Before `Error` initialization they
    terminate at the error floor.
*/
void Scope.move(void *ptr, Scope *slot) {
  _require_running();
  if (!ptr) return;
  if (!slot) raise %(bad-arg);
  if (!*slot) *slot = _new_scope(NULL);
  Scope scope = *slot;
  ScopeAlloc alloc = PTR_ALLOC(ptr), next = NEXT(alloc), prev = alloc.prev;
  if (IS_TAGGED(prev)) {
    Scope owner = UNTAG_POINTER(prev);
    owner.first = next;
  }
  else SET_NEXT(prev, next);
  if (next) next.prev = prev;
  SET_NEXT(alloc, scope.first);
  alloc.prev = TAG_POINTER(scope);
  if (scope.first) scope.first.prev = alloc;
  scope.first = alloc;
}

/** Resizes one scope-owned allocation and returns the new pointer.
    Ownership does not change: the allocation stays with the scope that
    already held it, even if that is not the active one. Two edge cases follow
    C's `realloc`: a NULL `ptr` allocates `size` bytes in the active scope, and
    a `size` of zero frees the allocation and returns NULL. A NULL result is
    not by itself a failure.

    As with C, the old pointer must be treated as dead once a resize succeeds.
    Raises: `<size-limit>` when the size overflows, or `<alloc-fail>` when
    allocation fails. Before `Error` initialization these failures terminate at
    the error floor.
*/
void *Scope.realloc(void *ptr, size_t size) {
  _require_running();
  if (!ptr) return _malloc_in(_thread().active, size, NULL);
  if (!size) {
    _free_alloc(PTR_ALLOC(ptr));
    return NULL;
  }
  ScopeAlloc old = PTR_ALLOC(ptr), next = NEXT(old), prev = old.prev;
  size_t extra = IS_FINALIZED(old) ? sizeof(ScopeFinalizer) : 0;
  if (size > SIZE_MAX - sizeof(struct ScopeAlloc) - extra)
    raise %(size-limit);
  char *base =
    _data_realloc(ALLOC_BASE(old), size + sizeof(struct ScopeAlloc) + extra);
  ScopeAlloc replacement = (ScopeAlloc) (base + extra);
  SET_NEXT(replacement, next);
  replacement.prev = prev;
  if (next) next.prev = replacement;
  if (IS_TAGGED(prev)) {
    Scope scope = UNTAG_POINTER(prev);
    scope.first = replacement;
  }
  else SET_NEXT(prev, replacement);
  atomic_fetch_add(&scope_reallocation_calls, 1);
  _record_request(size);
  return ALLOC_PTR(replacement);
}
/** Releases resources owned by `Scope`.
    `Scope` groups managed allocations by lifetime; balanced
    retain/release and push/pop boundaries remain caller
    responsibilities.
*/
void Scope_shutdown(void) {
  if (scope_state == <shutdown> || scope_state == <shutting>) return;
  if (scope_state == <uninit>) {
    scope_state = <shutdown>;
    return;
  }
  scope_state = <shutting>;
  /* Hooks close higher-level owners in reverse dependency order while Scope
     allocations still work. Thread-local regions then disappear before leak
     reporting reads the name registry, and shared thread state goes last. */
  for (int i = hook_count - 1; i >= 0; i--) hooks[i]();
  _raw_free(hooks);
  hooks = NULL;
  hook_count = hook_capacity = 0;
  x2c_scope_thread_release();
  _report_leaks();
  _free_name_registry();
  scope_state = <shutdown>;
  x2c_thread_state_release();
}
