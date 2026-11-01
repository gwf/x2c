/*  threads.x -- pool threads */

// process state

static typedef struct PoolValueThreadState {
  Pool current;
} *PoolValueThreadState;

static threaded struct PoolValueThreadState value_thread;

/* locks

   Owner locks run child to parent. Shared snapshots take index publication
   before depot; neither shared lock waits for an owner. */

/** Makes `Pool` lock from here on, for a process about to start a worker.
    `Thread.start_raw` calls this before `pthread_create`. It never clears.
*/
void Pool.thread_start(void) {
  pool_multithreaded = 1;
}

/** Borrows a pool for one runtime callback and returns the previous pool.
    The owner keeps the pool and its ancestors alive. Exchanging the
    thread-local pointer transfers no ownership; restore it after the callback.
*/
Pool x2c_pool_exchange(Pool pool) {
  Pool previous = Pool.current();
  value_thread.current = pool;
  return previous;
}

/** Installs the existing process root in a newly created worker thread.
    The root must already exist; otherwise the process aborts.
*/
void Pool.thread_initialize(void) {
  if (value_thread.current) return;
  if (!value_root) _fatal("canonical value root is not initialized");
  value_thread.current = value_root;
}

/** Releases this thread's open brackets and then the process root.
    Call it only after every worker has stopped and no canonical value is
    still in use. A repeat call after the root is gone does nothing.
*/
void Pool.shutdown(void) {
  while (value_thread.current && value_thread.current != value_root)
    value_thread.current = value_thread.current.release();
  while (value_root) value_root = value_root.release();
  value_thread.current = NULL;
}

/** Opens a child of the shared `String` and `List` canonical-value pool.
    New canonical misses enter the child, while equal ancestor values retain
    their existing owner. Promote anything that must outlive the bracket with
    `String.promote` or `List.promote`: unpromoted values are discarded and
    their identities no longer resolve. Brackets nest. The caller must match
    this with one `Pool.close` or detach it for transfer.
    Raises: `<alloc-fail>` while opening the pool.
    See: Pool.close, Pool.open_named, List.promote
*/
Pool Pool.open(void) => Pool.open_named(NULL);

/** Opens and returns a named child of the pool active on this thread.
    New canonical misses enter the child; an equal ancestor value keeps its
    existing owner and lifetime. The caller must match this with one
    `Pool.close` or detach it for transfer. The name appears in `Scope`
    diagnostics.
    Raises: `<alloc-fail>` while opening the pool.
    See: Pool.open, Pool.close
*/
Pool Pool.open_named(const char *name) {
  Pool nested = Pool.current().retain_named(name);
  value_thread.current = nested;
  return nested;
}

/** Closes the innermost open bracket and makes its parent active.
    Canonical `String`s, `List`s, and transient `String` buffers owned by that
    pool are reclaimed unless promoted; ancestor-owned values remain live.
    Raises: `<bad-state>` when no bracket is open. The failure leaves the
    active pool unchanged.
*/
void Pool.close(void) {
  if (!Pool.current().up) raise %(bad-state (operation "Pool.close"));
  value_thread.current = value_thread.current.release();
}

/** Removes the innermost open bracket without destroying it.
    The returned pool remains owned by the caller until explicitly released.
    Keep it and its ancestors alive while its values are in use. `Thread.join`
    does not copy values or transfer pool ownership.
    Raises: `<bad-state>` when no bracket is open. The failure leaves the
    active pool unchanged.
*/
Pool Pool.detach(void) {
  Pool detached = Pool.current();
  if (!detached.up) raise %(bad-state (operation "Pool.detach"));
  value_thread.current = detached.up;
  return detached;
}

/* the thread's pool

   String and List share one stack because their immutable values freely
   contain one another. The public bracket below operates on that one stack;
   the instance methods above build a pool without making it thread-active. */

/** Returns the borrowed canonical-value pool active on this thread.
    The process root is installed lazily on first use, so the result is never
    NULL. The pool is borrowed: do not release it with `Pool.release`.
*/
Pool Pool.current(void) {
  if (!value_thread.current) Pool.initialize();
  return value_thread.current;
}

/** Creates the process-wide canonical-value root and makes it active here.
    `x2c_initialize` calls this once; a repeat call does nothing.
    Raises: `<alloc-fail>` if the root cannot be constructed. Native mutex
    initialization failure aborts.
*/
void Pool.initialize(void) {
  if (value_thread.current) return;
  if (!value_root) {
    value_root = Pool.retain_named(NULL, "canonical values");
    _root_initialize(value_root.table);
  }
  value_thread.current = value_root;
}

/** Reports whether the process root owns `value` as its canonical identity.
    Nothing is promoted, and no open bracket can reclaim a value for which this
    returns one.
*/
int Pool.is_permanent(Var value) => value_root && value_root.owns(value);

/** Returns a counter that changes whenever any pool level is destroyed.
    A cache that borrows canonical identities reads this before trusting an
    entry: a released level's addresses can be reused, so identities admitted
    under an earlier value prove nothing. The counter only advances, so a
    reader needs no lock to tell that something was released.
*/
unsigned long Pool.epoch(void) =>
  __atomic_load_n(&value_epoch, __ATOMIC_ACQUIRE);
