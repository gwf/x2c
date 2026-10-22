/*  thread.x -- native workers with explicit result lifetimes

    Copyright (c) 2026 Gary William Flake.

    Thread copies input and result bits. Callbacks explicitly preserve any
    output that must outlive their private work storage. Errors are captured
    separately for join; parallel reducers borrow from parked workers.
*/

#pragma once

#include "common.x"

/** Computes a result from borrowed start-input bytes, valid during the call.
    The return copies bits without exporting or transferring storage. Preserve
    output explicitly before callback exit; temporary storage is then freed.
    Workers start in the shared canonical pool. Explicit private pools retain
    their own lifetime rules. An escaping Error becomes join-fail at join;
    policies that resume still resume inside the callback. */
typedef Var (*ThreadFn)(const void *input, size_t input_size);

/** Computes a result from borrowed Var input. Thread.start copies the return
    bits; retained storage must already outlive callback exit. ParallelMap
    instead keeps callback storage alive through its reducer, which explicitly
    transfers anything it retains. Input storage stays live through use. */
typedef Var (*ThreadValueFn)(Var input);

/** Scope-owned description of a bounded parallel mapping operation.
    Construction starts no workers. The source iterator storage and callback
    are borrowed until a consuming `ParallelMap.foldl` finishes. Use temporary
    iterator chains only when the fold is in the same full expression.
*/
typedef struct ParallelMap *ParallelMap;

/** A heap-owned native worker handle with one consuming join.
    A started `Thread` must be joined, including after its callback finishes,
    and then released with `Thread.free`.
*/
typedef struct Thread *Thread;

#include "context.x"
#include "dispatch.x"
#include "func.x"
#include "rewrite.x"
#include "error/error.x"
#include "error_init.x"
#include "exception.x"
#include "list/list.x"
#include "logger.x"
#include "match/match.x"
#include "pool/pool.x"
#include "scope/scope.x"
#include "string/string.x"

#include <errno.h>
#include <stddef.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static struct ParallelRun { Array ready; int stopping; };

static struct Thread {
  pthread_t native, ThreadFn function, size_t input_size, Scope error_scope;
  Pool error_pool;
  Var result;
  Var errors;
  void *policy;
  Symbol state;
  int finished;
  struct ParallelRun *parallel;
  int assigned;
  int stop_requested;
  pthread_cond_t *waiting;
};

static struct ThreadValueInput { ThreadValueFn function; Var value; };
static struct ParallelMap {
  Iter source;
  ThreadValueFn function;
  int workers;
};

static threaded Thread running_thread;
static threaded int stop_mask;

static int thread_live_count;
static pthread_mutex_t thread_completion_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t thread_completion_condition =
  (pthread_cond_t) PTHREAD_COND_INITIALIZER;
static pthread_once_t thread_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

static size_t _input_offset(void) {
  size_t alignment = _Alignof(max_align_t);
  size_t remainder = sizeof(struct Thread) % alignment;
  return remainder ? sizeof(struct Thread) + alignment - remainder
                   : sizeof(struct Thread);
}

static void *_input(Thread thread) =>
  (unsigned char *) thread + _input_offset();

// cooperative waits

/** Locks the internal monitor shared by stop publication and queue commits.
    Native synchronization failure aborts without entering Error dispatch. */
void x2c_thread_wait_lock(void) =>
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));

/** Unlocks the internal stop/queue monitor. */
void x2c_thread_wait_unlock(void) =>
  _completion_check(pthread_mutex_unlock(&thread_completion_mutex));

/** Returns the current wait's borrowed Thread token, or NULL for an unmanaged
    or cleanup-masked caller. Call while holding the internal monitor. */
Thread x2c_thread_wait_owner(void) => stop_mask ? NULL : running_thread;

/** Tests a borrowed wait token under the internal monitor. A null token has
    no stop request. Queues use this before committing a rendezvous peer. */
int x2c_thread_wait_stopped(Thread owner) => owner && owner.stop_requested;

/** Tests the current wait's pending stop under the internal monitor. */
int x2c_thread_stopping(void) =>
  x2c_thread_wait_stopped(x2c_thread_wait_owner());

/** Waits on condition with the internal monitor held. Registration and the
    pending-stop check share that monitor with Thread.stop. Returns holding
    the monitor, with the registration removed, including on pending stop.
    Queue callers recheck predicates and stop before committing an operation.
*/
void x2c_thread_wait(pthread_cond_t *condition) {
  Thread owner = x2c_thread_wait_owner();
  if (x2c_thread_wait_stopped(owner)) return;
  if (owner) owner.waiting = condition;
  _completion_check(pthread_cond_wait(condition, &thread_completion_mutex));
  if (owner) owner.waiting = NULL;
}

/** Raises a non-resumable stop outcome after queue locks and wait records
    have been released. Explicit catches may handle this shared cause. */
void x2c_thread_cancel(void) {
  raise %(bad-state (operation "Thread.stop") (cancelled 1));
}

/** Requests cooperative stopping without closing any Channel. The request
    persists and wakes a registered Channel or completion wait. Computation
    and arbitrary native I/O are not interrupted. Repeated requests are safe
    while the handle remains live; stop does not join or free it.
    Raises: <bad-arg> for a null handle. */
void Thread.stop(Thread t) {
  if (!t) raise %(bad-arg (operation "Thread.stop"));
  x2c_thread_wait_lock();
  t.stop_requested = 1;
  if (t.waiting) _completion_check(pthread_cond_broadcast(t.waiting));
  x2c_thread_wait_unlock();
}

// starting

/** Starts one worker and returns its heap-owned handle.
    `input_size` bytes are copied before native start and passed once to the
    callback. Pointees within those bytes remain shared and must outlive the
    worker. Copied storage has `max_align_t` alignment, so over-aligned input
    types are unsupported. A worker runs on an 8 MiB stack on every platform,
    so library recursion limits are reached the same way on a worker as on the
    main thread. The worker also adopts this thread's `Error` policy, so a
    cause set to `<ignore>`, `<log>`, or `<collect>` resumes inside the
    callback as it does here.
    An attempt that reaches `pthread_create` permanently enables canonical-pool
    locking; the first successful start also freezes `Var` descriptor
    registration.
    Raises: `<bad-arg>` for a NULL function or missing nonempty input,
    `<size-limit>` when the handle size or shutdown-hook registry overflows,
    `<alloc-fail>` when the handle or shutdown hook cannot be allocated, or
    `<io-fail>` when `pthread_create` fails. Failure during native once
    initialization or mutex setup aborts the process.
*/
Thread Thread.start_raw(
  ThreadFn function, const void *input, size_t input_size) {
  return _start(function, input, input_size, NULL);
}

static Thread _start(
  ThreadFn function, const void *input, size_t input_size,
  struct ParallelRun *parallel) {
  if (!function || (input_size && !input))
    raise %(bad-arg (operation "Thread.start_raw"));
  Thread thread = _new_handle(function, input, input_size);
  thread.parallel = parallel;
  int started = 0;
  defer if (!started) {
    Error.policy_release(thread.policy);
    free(thread);
  }
  if (pthread_once(&thread_shutdown_once, _register_shutdown)) {
    Error.policy_release(thread.policy);
    free(thread);
    fprintf(stderr, "Thread: could not register shutdown\n");
    abort();
  }
  __atomic_fetch_add(&thread_live_count, 1, __ATOMIC_SEQ_CST);
  Pool.thread_start();
  int error = _create_native(thread);
  if (error) {
    __atomic_fetch_sub(&thread_live_count, 1, __ATOMIC_SEQ_CST);
    _error("pthread_create", error);
  }
  started = 1;
  return thread;
}

static Var _call_value(const void *input, size_t size) {
  (void) size;
  const struct ThreadValueInput *call = input;
  return call.function(call.value);
}

/** Starts one Var-to-Var worker. Input and result bits are copied without
    cloning, exporting, or transferring referenced storage. Input storage and
    callback code stay live through join. Shared mutable data requires caller
    coordination. The callback must explicitly preserve any output it retains
    beyond exit; use separate output owners for concurrently running workers.
    Shared canonical Strings and Lists survive worker exit. Wide boxed values
    still require their backing allocation to survive.
    Thread.start_raw accepts copied byte-buffer input instead.
    Raises: bad-arg for a null callback, or Thread.start_raw causes. */
Thread Thread.start(ThreadValueFn function, Var value) {
  return _start_value(function, value, NULL);
}

static Thread _start_value(
  ThreadValueFn function, Var value, struct ParallelRun *parallel) {
  if (!function) raise %(bad-arg (operation "Thread.start"));
  struct ThreadValueInput input = { function, value };
  return _start(_call_value, &input, sizeof(input), parallel);
}

/* The handle holds the copied input after its own fields, and this thread's
   `Error` policy until the worker adopts it. */
static Thread _new_handle(
  ThreadFn function, const void *input, size_t input_size) {
  size_t input_offset = _input_offset();
  if (input_size > SIZE_MAX - input_offset) raise %(size-limit);
  void *policy = Error.policy_capture();
  Thread thread = calloc(1, input_offset + input_size);
  if (!thread) {
    Error.policy_release(policy);
    raise %(alloc-fail);
  }
  thread.policy = policy;
  thread.function = function;
  thread.input_size = input_size;
  thread.result = void;
  thread.errors = void;
  __atomic_store_n(&thread.state, <running>, __ATOMIC_SEQ_CST);
  if (input_size) memcpy(_input(thread), input, input_size);
  return thread;
}

static void _register_shutdown(void) {
  Context.initialize();
  x2c_match_initialize();
  Scope.shutdown_hook(_shutdown);
}

/* The live count falls only after native join succeeds. Process shutdown
   rejects a finished callback whose handle and captured errors were never
   consumed. */
static void _shutdown(void) {
  int live = __atomic_load_n(&thread_live_count, __ATOMIC_SEQ_CST);
  if (live) {
    fprintf(stderr, "Thread: %d worker(s) still live at shutdown\n", live);
    abort();
  }
}

/* Descriptor registration stays stable across pthread_create. Success makes
   it permanently read-only; failure unlocks it, and the caller restores the
   live count and releases the handle while pool locking stays enabled. */
static int _create_native(Thread thread) {
  pthread_attr_t attributes;
  _stack_attributes(&attributes);
  x2c_descriptor_thread_start_begin();
  int error = pthread_create(&thread.native, &attributes, _run, thread);
  x2c_descriptor_thread_start_end(!error);
  pthread_attr_destroy(&attributes);
  return error;
}

/* Library recursion limits, such as the `Regex` repetition depth, are sized
   for a main-thread stack. A macOS pthread defaults to 512 KiB, well under
   what those limits assume, so every worker is given the 8 MiB that Linux
   pthreads and the macOS main thread already provide. */
static const size_t _STACK_BYTES = 8u << 20;

static void _stack_attributes(pthread_attr_t *attributes) {
  if (pthread_attr_init(attributes) ||
      pthread_attr_setstacksize(attributes, _STACK_BYTES)) {
    fprintf(stderr, "Thread: could not size the worker stack\n");
    abort();
  }
}

static void _error(const char *operation, int error) {
  String name = operation;
  raise %(io-fail (operation $name) (errno $error));
}

// running the callback

/* Workers use shared canonical values and private mutable callback storage.
   Captured errors have separate storage until join; results keep the lifetime
   explicitly arranged by the callback. */
static void *_run(void *argument) {
  Thread thread = argument;
  running_thread = thread;
  (void) Scope.top();
  Pool.thread_initialize();
  thread.error_pool = Pool.current();
  Error.initialize_raw();
  Error.policy_adopt(thread.policy);
  thread.policy = NULL;

  if (thread.parallel) _parallel_run(thread);
  else _work(thread);

  Error.shutdown_raw();
  x2c_thread_state_release();
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));
  thread.finished = 1;
  _completion_check(pthread_cond_broadcast(&thread_completion_condition));
  _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
  return NULL;
}

/* Register the worker observer before opening the work Context, so failure
   constructing its bounded state is captured just like callback failure. */
static int _work(Thread thread) {
  int mark = Error.mark(), again = 0;
  try {
    ErrorHandler observer = Error.push(_capture_errors, thread);
    defer Error.pop(observer);
    Context work = Context.open_named("Thread callback");
    defer work.close();
    again = _call(thread);
  }
  catch %(join-fail *): _worker_failed(thread, mark);
  catch %(alloc-fail *): _worker_failed(thread, mark);
  if (thread.parallel && thread.errors is not void) {
    _parallel_park(thread);
    again = 0;
  }
  return again;
}

static int _call(Thread thread) {
  ErrorHandler logger_handler = Error.push(Logger.error_handler, void);
  defer Error.pop(logger_handler);
  const void *input = thread.input_size ? _input(thread) : NULL;
  thread.result = thread.function(input, thread.input_size);
  return thread.parallel ? _parallel_park(thread) : 0;
}

/* The outermost of the worker's registrations, so a cause the callback did not
   catch reaches it after `Logger` has had its look. A cause whose policy is
   `<abort>`, which is every shared non-returning cause and every code no
   policy names, would reach the error floor and end the process; a worker
   leaves the callback as `<join-fail>` carrying this snapshot instead. Any
   other policy resolves the cause and returns to its raise, exactly as it does
   on the starting thread, so the backstop never sees it. The replacement cause
   dispatches outward from here, which is the `try` in `_work` and nothing
   else. */
static Symbol _capture_errors(List errors, Var data) {
  Thread thread = data;
  if (!errors) return <declined>;
  Var newest = errors.last();
  if (newest is not <list>) return <declined>;
  List entry = newest;
  Var code = entry.assoc(<code>);
  if (code is not <symbol>) return <declined>;
  if (Error.policy_get(code) != <abort>) return <declined>;
  thread.errors = Error.snapshot_in(
    errors, &thread.error_scope, thread.error_pool);
  raise %(join-fail (operation "Thread callback"));
}

/* Records what escaped the callback so `Thread.join` can report `<join-fail>`.
   `_capture_errors` has already snapshotted the slice unless the transfer
   began before it was registered. */
static void _worker_failed(Thread thread, int mark) {
  if (thread.errors is void)
    thread.errors = Error.since_in(
      mark, &thread.error_scope, thread.error_pool);
  thread.result = void;
}

// completion and joining

static void _completion_check(int error) {
  if (!error) return;
  fprintf(stderr, "Thread: completion synchronization failed (%d)\n", error);
  abort();
}

/** Waits for a finished worker, removes its handle from `pending`, and
    returns it.
    A null or empty Array returns NULL. If several workers have finished, the
    first in current Array order wins; completion chronology is not recorded.
    A failed worker is also ready. This does not join, export results, or free
    the handle: the caller must still call `Thread.join` and `Thread.free`.
    `join` reports worker errors as usual.
    Entries must be unique, valid Thread handles. The caller exclusively owns
    this Array and its handles throughout the wait; concurrent mutation,
    joining, or freeing is unsupported. A returned unjoined handle may be
    added again and selected again. Freed handles must never be supplied.
    Raises: `<bad-arg>` for a null entry, or `<bad-state>` for a joining or
    joined entry. Native completion synchronization failure aborts.
*/
Thread Thread.wait_any(Array pending) {
  if (!pending.len()) return NULL;
  foreach (Thread thread, pending) {
    if (!thread) raise %(bad-arg (operation "Thread.wait_any"));
    if (__atomic_load_n(&thread.state, __ATOMIC_SEQ_CST) != <running>)
      raise %(bad-state (operation "Thread.wait_any"));
  }
  x2c_thread_wait_lock();
  Thread selected = _wait_any(pending);
  x2c_thread_wait_unlock();
  if (!selected) x2c_thread_cancel();
  return selected;
}

static Thread _wait_any(Array pending) {
  while (!x2c_thread_stopping()) {
    for (int i = 0; i < pending.len(); i++) {
      Thread thread = pending[i];
      if (thread.finished) return pending.remove(i);
    }
    x2c_thread_wait(&thread_completion_condition);
  }
  return NULL;
}

/** Joins a worker and returns its result bits without ownership changes.
    The callback must have preserved any referenced output before exiting.
    Native join failure leaves the handle joinable. Concurrent or repeated
    joins are rejected. Once native join succeeds, the handle is consumed,
    including when a captured worker Error is raised. Free it after the join
    returns or after catching that Error. Void results remain void.
    Raises: bad-arg for NULL, bad-state for an active or completed join,
    io-fail for native join failure, error-export causes, or join-fail
    containing the captured worker errors. */
Var Thread.join(Thread t) {
  if (!t) raise %(bad-arg (operation "Thread.join"));
  Symbol expected = <running>;
  if (!__atomic_compare_exchange_n(
    &t.state, &expected, <joining>, 0,
    __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
    raise %(bad-state (operation "Thread.join"));
  }
  int error = pthread_join(t.native, NULL);
  if (error) {
    __atomic_store_n(&t.state, <running>, __ATOMIC_SEQ_CST);
    _error("pthread_join", error);
  }

  __atomic_fetch_sub(&thread_live_count, 1, __ATOMIC_SEQ_CST);
  defer _finish_join(t);
  return _read_result(t);
}

static Var _read_result(Thread t) {
  if (t.errors is not void) {
    Var errors = Context.export_scope(t.error_scope, t.error_pool, t.errors);
    raise %(join-fail (errors $errors));
  }
  return t.result;
}

/* Join releases only the separately captured Error storage. Successful
   result ownership remains exactly where the developer placed it. */
static void _finish_join(Thread thread) {
  _release_result(thread);
  __atomic_store_n(&thread.state, <joined>, __ATOMIC_SEQ_CST);
}

static void _release_result(Thread thread) {
  thread.error_pool = NULL;
  if (thread.error_scope) Scope.destroy(thread.error_scope);
  thread.error_scope = NULL;
  thread.result = void;
  thread.errors = void;
}

/** Frees a `Thread` handle after its consuming join has completed.
    Raises: `<bad-state>` for NULL, running, or joining handles.
*/
void Thread.free(Thread t) {
  if (!t || __atomic_load_n(&t.state, __ATOMIC_SEQ_CST) != <joined>)
    raise %(bad-state (operation "Thread.free"));
  free(t);
}

/** Waits for one worker, joins it, frees its handle, and returns its result.
    A null or empty Array returns `void`. Selection and exclusive ownership
    follow Thread.wait_any. Result ownership is unchanged, as with Thread.join.
    The worker must explicitly preserve output before callback exit.
    A consuming join removes and frees the handle even when worker failure
    or captured-error export raises. Native join failure retains the handle
    in pending for retry. Other entries keep their relative order; a
    retained selected handle moves to the end.
    Raises: the same causes as `Thread.wait_any` and `Thread.join`.
*/
Var Thread.finish_any(Array pending) {
  Thread worker = Thread.wait_any(pending);
  if (!worker) return void;
  /* Removal retains capacity, so restoring ownership cannot allocate. */
  pending.push(worker);
  defer if (__atomic_load_n(&worker.state, __ATOMIC_SEQ_CST) == <joined>) {
    pending.remove(-1);
    worker.free();
  }
  return worker.join();
}

/** Joins and frees every worker in `pending`, discarding returned results.
    A null or empty Array does nothing. Already-joined handles are freed.
    Successfully consumed handles are removed, including workers whose join
    reported a worker or captured-error export error. Native join failure
    leaves its handle in pending for retry; all other entries are still attempted.
    Entries must be unique, valid handles exclusively owned by this caller,
    with no concurrent mutation, joining, or freeing.
    Failures are collected and raised as `<join-fail>` only after cleanup.
    During an existing Error unwind, a native stderr diagnostic reports the
    cleanup failure instead; the original Error continues unchanged.
    Raises: `<join-fail>` containing the captured join failures, including
    `<bad-arg>` for a null entry or `<bad-state>` for a joining entry.
    Error snapshot failures use the existing raw Error floor.
*/
void Thread.finish_all(Array pending) {
  int unwinding = x2c_exception_unwinding();
  List failures = NULL;
  for (int i = 0; i < pending.len();) {
    Thread worker = pending[i];
    try {
      if (!worker ||
          __atomic_load_n(&worker.state, __ATOMIC_SEQ_CST) != <joined>)
        worker.join();
    }
    catch %(?code *detail):
      failures = cons(Error.snapshot(%($code @detail)), failures);
    if (worker &&
        __atomic_load_n(&worker.state, __ATOMIC_SEQ_CST) == <joined>) {
      pending.remove(i);
      worker.free();
    }
    else i++;
  }
  if (!failures) return;
  if (unwinding) {
    fprintf(
      stderr, "Thread.finish_all: cleanup failed; %zu handle(s) remain.\n",
      pending.len());
    return;
  }
  raise %(join-fail (errors ${failures.reverse()}));
}

// synchronous callable batches

static Var _batch_call(const void *bytes, size_t size) {
  (void) size;
  Func function = *(Func const *) bytes;
  return function.apply(0, NULL);
}

static void _batch_stop(Array pending) {
  stop_mask++;
  defer --stop_mask;
  foreach (Thread worker, pending) worker.stop();
  defer if (pending.len()) {
    fprintf(stderr, "Thread.run: cleanup left unjoined workers\n");
    abort();
  }
  Thread.finish_all(pending);
}

static void _batch_check_stop(void) {
  x2c_thread_wait_lock();
  int stopped = x2c_thread_stopping();
  x2c_thread_wait_unlock();
  if (stopped) x2c_thread_cancel();
}

/** Runs zero-argument jobs concurrently and waits for all of them.
    Each successful result, including void, reaches completed on the caller
    when that callback is nonnull. Result bits carry no ownership transfer.
    Each job must explicitly preserve referenced output before returning;
    completed runs after that job's temporary storage has been reclaimed.
    Jobs, captures, and borrowed storage stay live through the call. Separate
    output scopes permit exclusive worker access; a shared allocation scope
    is not made safe by this API. Canonical values use the shared process pool.
    Explicit private pools retain their own lifetime rules.
    The completion callback must not wait on participant progress.

    Startup, job, callback, or coordinator-stop failure requests stop on all
    remaining jobs before joining any. Cleanup preserves the original Error
    and invokes no completion callbacks. Stop is cooperative: native I/O and
    computation that never checks stop can delay completion. Native join
    failure aborts if cleanup cannot establish that borrowed storage is idle.
    Raises: startup, callback, captured-error, stop, or worker join causes. */
void Thread.run(Array jobs, Func completed) {
  Array pending = $auto([]);
  ((Block) pending).reserve(jobs.len());
  defer _batch_stop(pending);
  foreach (Func job, jobs) {
    _batch_check_stop();
    pending.push(_start(_batch_call, &job, sizeof(job), NULL));
  }
  while (pending.len()) {
    Var result = Thread.finish_any(pending);
    _batch_check_stop();
    if (completed) completed.apply_value(result);
  }
  _batch_check_stop();
}

macro Expression $thread.run.jobs(Expr $jobs) => Thread.run($jobs);

$rewrite($thread.run.jobs)
meta static Code _batch_without_callback(Code code) {
  match (code) case $thread.run.jobs(?jobs):
    return $!void{ Thread.run($jobs, NULL) };
  return code;
}

/** Describes mapping `function` over `source` with at most `workers` Threads.
    Nothing runs until `ParallelMap.foldl` consumes the operation. The
    descriptor belongs to the caller's Scope and borrows the source iterator
    storage and callback code. Those must remain live until the fold ends.
    Source values follow `Thread.start` borrowing: their input graphs must
    remain live and read-only while outstanding workers use them. A source
    must not mutate or recycle an outstanding input's storage.
    Raises: `<bad-arg>` for a nonpositive worker count, or `<alloc-fail>` for
    descriptor storage.
*/
ParallelMap Iter.parallel_map(Iter i, ThreadValueFn function, int workers) {
  if (workers <= 0) raise %(bad-arg (operation "Iter.parallel_map"));
  ParallelMap map = Scope.malloc(sizeof(struct ParallelMap));
  *map = (struct ParallelMap) { i, function, workers };
  return map;
}

/** Folds borrowed worker results on the caller in completion order.
    Reuses at most the configured worker count. A worker keeps its callback
    Context alive and waits while the caller consumes its result. The next
    assignment or shutdown releases that Context and its remaining storage.
    No result graph is exported. To retain worker-owned storage, the reducer
    must explicitly move it to its own owner before returning. References,
    including cycles, do not imply ownership. Borrowed input owners stay live
    through the fold; callbacks must not mutate outstanding borrowed inputs.
    Workers use the shared canonical pool. Explicit private pools retain
    their own lifetime rules.

    A void seed takes the first result without calling the reducer. That
    result must survive worker cleanup independently; use an explicit seed
    and transfer in the reducer for worker-owned storage. Empty input or a
    null descriptor returns the seed. Source traversal and accumulation run
    on the caller; each worker holds at most one job or unread result.
    Every exit stops and joins remaining workers. Channel waits cooperate
    with stop; arbitrary computation and native I/O need not. Cleanup keeps
    the primary Error. Native join failure leaving a worker live aborts.
    Raises: source, start, worker, allocation, accumulator, or stop causes,
    including <void-op> for a void worker result. */
Var ParallelMap.foldl(ParallelMap map, Var seed, Func accumulate) {
  if (!map) return seed;
  struct ParallelRun *run = Scope.calloc(1, sizeof(struct ParallelRun));
  Array workers = NULL;
  defer _parallel_stop(run, workers);
  workers = [];
  run.ready = [];
  ((Block) workers).reserve(map.workers);
  ((Block) run.ready).reserve(map.workers);
  Var acc = seed, input;
  int seeded = seed is not void;
  while (workers.len() < map.workers && map.source.try_next(input)) {
    _batch_check_stop();
    workers.push(_start_value(map.function, input, run));
  }
  int active = workers.len();
  while (active) {
    Thread worker = _parallel_wait(run);
    Var item = _parallel_result(worker);
    active--;
    if (item is void) raise %(void-op (operation "ParallelMap.foldl"));
    if (seeded) acc = accumulate.apply_values(acc, item);
    else {
      acc = item;
      seeded = 1;
    }
    if (map.source.try_next(input)) {
      _parallel_assign(worker, input);
      active++;
    }
  }
  _batch_check_stop();
  return acc;
}

static void _parallel_run(Thread thread) {
  while (_work(thread)) {}
}

/* The caller borrows callback storage until assignment or shutdown releases
   this worker. Only the parked worker's consumer may transfer that storage. */
static int _parallel_park(Thread thread) {
  x2c_thread_wait_lock();
  if (thread.parallel.stopping) {
    thread.result = void;
    x2c_thread_wait_unlock();
    return 0;
  }
  thread.parallel.ready.push(thread);
  _completion_check(pthread_cond_broadcast(&thread_completion_condition));
  while (!thread.assigned && !thread.parallel.stopping &&
         !x2c_thread_stopping())
    x2c_thread_wait(&thread_completion_condition);
  int again = thread.assigned && !thread.parallel.stopping &&
              !x2c_thread_stopping();
  thread.assigned = 0;
  thread.result = void;
  x2c_thread_wait_unlock();
  return again;
}

static Thread _parallel_wait(struct ParallelRun *run) {
  x2c_thread_wait_lock();
  while (!run.ready.len() && !x2c_thread_stopping())
    x2c_thread_wait(&thread_completion_condition);
  Thread ready = x2c_thread_stopping() ? NULL : run.ready.remove(0);
  x2c_thread_wait_unlock();
  if (!ready) x2c_thread_cancel();
  return ready;
}

static Var _parallel_result(Thread worker) {
  if (worker.errors is not void) return _read_result(worker);
  return worker.result;
}

static void _parallel_assign(Thread worker, Var input) {
  x2c_thread_wait_lock();
  if (x2c_thread_stopping()) {
    x2c_thread_wait_unlock();
    x2c_thread_cancel();
  }
  struct ThreadValueInput *call = _input(worker);
  call.value = input;
  worker.assigned = 1;
  _completion_check(pthread_cond_broadcast(&thread_completion_condition));
  _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
}

static void _parallel_stop(struct ParallelRun *run, Array workers) {
  stop_mask++;
  defer --stop_mask;
  defer Scope.free(run);
  defer workers.cleanup();
  defer run.ready.cleanup();
  defer if (workers.len()) {
    fprintf(stderr, "ParallelMap: cleanup left unjoined workers\n");
    abort();
  }
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));
  run.stopping = 1;
  _completion_check(pthread_cond_broadcast(&thread_completion_condition));
  _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
  foreach (Thread worker, workers) worker.stop();
  Thread.finish_all(workers);
}
