/*  regions.x -- scope regions */

static threaded struct ScopeThreadState scope_thread;

static pthread_mutex_t scope_links_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

module void _links_lock(void) {
  if (pthread_mutex_lock(&scope_links_mutex))
    _raw_fatal("could not lock scope links");
}

module void _links_unlock(void) {
  if (pthread_mutex_unlock(&scope_links_mutex))
    _raw_fatal("could not unlock scope links");
}

module ScopeThreadState _thread(void) {
  ScopeThreadState state = &scope_thread;
  if (!state.active) state.active = &state.root;
  return state;
}

// the active slot

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
meta native void Scope.push(Scope *scope) {
  _require_running();
  if (!scope) raise %(bad-arg);
  ScopeThreadState state = _thread();
  state.stack = _raw_grow(
    state.stack, state.stack_size, state.stack_capacity,
    sizeof(*state.stack));
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
meta native void Scope.pop(void) {
  _require_running();
  ScopeThreadState state = _thread();
  if (!state.stack_size) raise %(bad-state);
  state.stack_size--;
  state.active = state.stack_size ? state.stack[state.stack_size - 1]
                                 : &state.root;
}

// retained regions

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
meta native void Scope.retain(void) {
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
meta native void Scope.release(void) {
  _require_running();
  ScopeThreadState state = _thread();
  with state.active as active {
    if (!*active || !_forget_retain((*active), active)) raise %(bad-state);
    Scope top = *active;
    /* Restore and detach the surviving lower region before destruction, so
       the active slot never names freed storage and `_destroy_chain`
       cannot follow `down` into the surrounding lifetime. */
    if ((*active = top.down)) (*active).up = NULL;
    top.down = NULL;
    _destroy_chain(top);
  }
}

static void _record_retain(Scope scope, Scope *slot) {
  ScopeThreadState state = _thread();
  state.retains = _raw_grow(
    state.retains, state.retain_count, state.retain_capacity,
    sizeof(*state.retains));
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

/* Popping the head keeps the list valid while a finalizer runs, so scratch
   it allocates into the dying scope is reclaimed by the same loop. */
static void _destroy_chain(Scope scope) {
  while (scope) {
    Scope down = scope.down;
    _links_lock();
    _detach_scope(scope);
    _links_unlock();
    while (1) {
      _links_lock();
      Scope child = scope.children;
      if (child) _detach_scope(child);
      ScopeAlloc alloc = child ? NULL : scope.first;
      if (alloc) _detach(alloc);
      _links_unlock();
      if (child) _destroy_chain(child);
      else if (alloc) _release(alloc);
      else break;
    }
    _unregister_name(scope);
    atomic_fetch_add(&scope_destructions, 1);
    free(scope);
    scope = down;
  }
}

// detached scopes

/** Creates a detached, unnamed scope and returns it.
    A detached scope sits in no slot and is not active, so nothing is charged
    to it until you allocate through `Scope.malloc_in` and friends or make it
    active with `Scope.push`. End it with `Scope.destroy`. Prefer
    `Scope.new_named` for anything long-lived; the name appears in the
    exit-time leak report.
    Raises: `<alloc-fail>` when the scope cannot be allocated. Before `Error`
    initialization it terminates at the error floor.
*/
meta native Scope Scope.new(void) {
  _require_running();
  return _new_scope(NULL);
}

/** Creates a storage scope owned by the active allocation scope.
    Its allocations and adopted children are reclaimed with its owner unless
    explicitly transferred or destroyed first. No object graph is traversed.
    Raises: `<alloc-fail>` while creating the scope or its initial owner.
*/
Scope Scope.child(void) {
  _require_running();
  Scope *active = Scope.top();
  if (!*active) *active = _new_scope(NULL);
  Scope child = _new_scope(NULL);
  child.transfer(*active);
  return child;
}

/** Returns this scope's lifetime parent, or NULL for a detached scope.
    This is independent of the active allocation stack and retained regions.
*/
Scope Scope.parent(Scope scope) {
  if (!scope) return NULL;
  _links_lock();
  Scope parent = scope.parent;
  _links_unlock();
  return parent;
}

/** Reparents this storage scope and its adopted descendants without copying.
    The source must be an inactive storage scope and the destination live. The
    destination must not be the source or one of its descendants. Callers
    exclude destruction during use and coordinate access to referenced data.
    Transfer does not follow payload references or revoke aliases.
    Raises: `<bad-arg>` for a NULL destination.
*/
void Scope.transfer(Scope scope, Scope destination) {
  if (!scope) return;
  if (!destination) raise %(bad-arg);
  _links_lock();
  if (scope.parent != destination) {
    _detach_scope(scope);
    scope.parent = destination;
    if (destination) {
      scope.next = destination.children;
      if (scope.next) scope.next.previous = scope;
      destination.children = scope;
    }
  }
  _links_unlock();
}

static void _detach_scope(Scope scope) {
  if (scope.previous) scope.previous.next = scope.next;
  else if (scope.parent) scope.parent.children = scope.next;
  if (scope.next) scope.next.previous = scope.previous;
  scope.parent = scope.previous = scope.next = NULL;
}

/** Reports whether `scope` owns `candidate` through lifetime parent links.
    A scope contains itself. Both handles must remain live during the query.
    This walks scope parents, never object references.
*/
int Scope.contains(Scope scope, Scope candidate) {
  if (!scope || !candidate) return 0;
  _links_lock();
  while (candidate && candidate != scope) candidate = candidate.parent;
  int found = candidate == scope;
  _links_unlock();
  return found;
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
meta native Scope Scope.new_named(const char *name) {
  _require_running();
  return _new_scope(name);
}

/** Destroys a scope and frees its allocations and adopted child scopes.
    An adopted scope first detaches from its lifetime parent. This ends a
    scope you hold in a variable, and is the counterpart to
    `Scope.new` and `Scope.new_named`. It frees the scope's allocations and
    discards its name; pointers into it are dangling afterwards, and nothing
    diagnoses their use. Any regions still linked below it, from retains that
    were never released, are destroyed with it.

    `Scope.destroy` refuses a scope that is still in use: the active root
    scope, a slot still on the pushed stack (pop it first), and a scope that
    a later `Scope.retain` layered another region on top of, which the
    runtime reports as an attached lower scope. The handle is a pointer into
    the destroyed scope, so destroying it again is undefined behavior.
    Raises: `<bad-state>` for the active root, a pushed slot, or an attached
    lower scope. The failure leaves the scope intact. A NULL `scope` does
    nothing. Before `Error` initialization it terminates at the error floor.
*/
meta native void Scope.destroy(Scope scope) {
  if (!scope) return;
  _require_running();
  ScopeThreadState state = _thread();
  if (scope == state.root) raise %(bad-state);
  for (int i = 0; i < state.stack_size; i++)
    if (scope == *state.stack[i]) raise %(bad-state);
  if (scope.up) raise %(bad-state);
  _forget_retains(scope);
  _destroy_chain(scope);
}

/** Ends the owned lifetime when a managed local leaves its block. */
meta native void Scope.cleanup(Scope value) { value.destroy(); }

module Scope _new_scope(const char *name) {
  Scope scope = _data_malloc(sizeof(struct Scope));
  *scope = (struct Scope) {0};
  _register_name(scope, name);
  atomic_fetch_add(&scope_creations, 1);
  return scope;
}

static void _forget_retains(Scope scope) {
  ScopeThreadState state = _thread();
  for (Scope cur = scope; cur; cur = cur.down)
    for (int i = state.retain_count - 1; i >= 0; i--)
      if (state.retains[i].scope == cur)
        state.retains[i] = state.retains[--state.retain_count];
}

/** Destroys this thread's `Scope` chain and its push and retain stacks.
    It runs last in `x2c_thread_state_release` and repeats harmlessly; a
    thread that never created a `Scope` has nothing to destroy.
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
