/*  thread.x -- `Context`-backed native worker threads

    Copyright (c) 2026 Gary William Flake

    A `Thread` copies Var bits or fixed-size bytes, runs one callback in an
    isolated `Context`, and seals the exported result or error until join.
    Raw input has max_align_t alignment; over-aligned types are unsupported.
    Shared objects require their own coordination.
*/

#pragma once

#include "common.x"

/** Computes one `Thread` result from a borrowed copy of the start input bytes.
    The input is valid only during the call. The returned value is exported by
    `Thread.join`; an `Error` escaping the callback is reported as
    `<join-fail>`. A cause the worker's `Error` policy resolves returns to its
    raise and does not end the callback.
*/
typedef Var (*ThreadFn)(const void *input, size_t input_size);

/** Computes a worker result from one borrowed `Var` input.
    Referenced input storage must stay alive and unchanged until join.
    Return fresh worker-owned values normally; `Thread.join` exports them.
    Error policy and result transfer follow `ThreadFn`.
*/
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
  pthread_t native, ThreadFn function, size_t input_size, Scope result_scope;
  Pool result_pool;
  Var result;
  Var errors;
  void *policy;
  Symbol state;
  int finished;
  struct ParallelRun *parallel;
  int assigned;
};

static struct ThreadValueInput { ThreadValueFn function; Var value; };
static struct ParallelMap {
  Iter source;
  ThreadValueFn function;
  int workers;
};

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
Thread Thread.start_raw(ThreadFn function, const void *input, size_t input_size) {
  return _start(function, input, input_size, NULL);
}

static Thread _start(ThreadFn function, const void *input, size_t input_size,
  struct ParallelRun *parallel) {
  if (!function || (input_size && !input))
    raise %(bad-arg (operation "Thread.start_raw"));
  Thread thread = _new_handle(function, input, input_size);
  thread.parallel = parallel;
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
    Error.policy_release(thread.policy);
    free(thread);
    _error("pthread_create", error);
  }
  return thread;
}

static Var _call_value(const void *input, size_t size) {
  (void) size;
  const struct ThreadValueInput *call = input;
  return call.function(call.value);
}

/** Starts one `Var`-to-`Var` worker using the ordinary Thread lifecycle.
    Copies the `Var` bits, including `void`, without cloning or transferring
    referenced storage. The input graph and callback code must outlive join;
    treat all referenced input as read-only until then. In particular, a
    borrowed Map is not a private copy and must not receive worker-owned
    values. Return a fresh Map for worker-created output instead.
    Scalars and immutable Strings can be read directly; wide boxed scalars
    still borrow their caller-owned storage. Result export and Error policy
    are those of `Thread.start_raw` and `Thread.join`. Use `Thread.start_raw`
    for explicit byte-buffer inputs.
    Raises: `<bad-arg>` for a null callback, or the causes of `Thread.start_raw`.
*/
Thread Thread.start(ThreadValueFn function, Var value) {
  return _start_value(function, value, NULL);
}

static Thread _start_value(ThreadValueFn function, Var value,
  struct ParallelRun *parallel) {
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
   rejects a finished callback whose sealed result stores were never
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

/* The worker sets up its own runtime state under the starting thread's
   `Error` policy and opens the result stores before the callback runs.
   Detaching the result pool and popping its Scope afterward seal both for
   the joining thread. Error and other per-thread state shut down last,
   after no worker-private value still needs them. */
static void *_run(void *argument) {
  Thread thread = argument;
  (void) Scope.top();
  Pool.thread_initialize();
  Error.initialize_raw();
  Error.policy_adopt(thread.policy);
  thread.policy = NULL;

  if (thread.parallel) _parallel_run(thread);
  else _run_job(thread);

  Error.shutdown_raw();
  x2c_thread_state_release();
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));
  thread.finished = 1;
  _completion_check(pthread_cond_broadcast(&thread_completion_condition));
  _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
  return NULL;
}

/* Each job uses the same isolated work and sealed result owners as a one-shot
   Thread. A reusable worker waits until the consumer releases those owners. */
static void _run_job(Thread thread) {
  thread.result_scope = Scope.new_named("Thread result");
  Scope.push(&thread.result_scope);
  thread.result_pool = Pool.open_named("Thread result");
  _work(thread);
  thread.result_pool = Pool.detach();
  Scope.pop();
}

/* Callback temporaries belong to `work`; its exported result or Error
   snapshot is moved or copied into the outer result stores before `work`
   closes. */
static void _work(Thread thread) {
  Context work = Context.open_isolated_named("Thread callback");
  int mark = Error.mark();
  try _call(thread, work);
  /* A registered catch is consulted during dispatch, before `Error` reaches
     its policy table, so a bare `catch:` would match first and no policy could
     ever resume inside a worker. `_capture_errors` converts the causes that
     really must leave the callback, so this backstop needs only that cause and
     the one an `Error.push` failure can raise before the observer exists. */
  catch %(join-fail *): _worker_failed(thread, mark);
  catch %(alloc-fail *): _worker_failed(thread, mark);
  work.close();
}

/* The exported result reaches the result stores while both handlers are
   registered. */
static void _call(Thread thread, Context work) {
  ErrorHandler observer = Error.push(_capture_errors, thread);
  defer Error.pop(observer);
  ErrorHandler logger_handler = Error.push(Logger.error_handler, void);
  defer Error.pop(logger_handler);
  const void *input = thread.input_size ? _input(thread) : NULL;
  thread.result = work.export(thread.function(input, thread.input_size));
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
    errors, &thread.result_scope, thread.result_pool);
  raise %(join-fail (operation "Thread callback"));
}

/* Records what escaped the callback so `Thread.join` can report `<join-fail>`.
   `_capture_errors` has already snapshotted the slice unless the transfer
   began before it was registered. */
static void _worker_failed(Thread thread, int mark) {
  if (thread.errors is void)
    thread.errors = Error.since_in(
      mark, &thread.result_scope, thread.result_pool);
  thread.result = void;
}

// completion and joining

static void _completion_check(int error) {
  if (!error) return;
  fprintf(stderr, "Thread: completion synchronization failed (%d)\n", error);
  abort();
}

/** Waits for a finished worker, removes its handle from `pending`, and returns it.
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
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));
  defer _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
  foreach (Thread thread, pending) {
    if (!thread) raise %(bad-arg (operation "Thread.wait_any"));
    if (__atomic_load_n(&thread.state, __ATOMIC_SEQ_CST) != <running>)
      raise %(bad-state (operation "Thread.wait_any"));
  }
  while (1) {
    for (int i = 0; i < pending.len(); i++) {
      Thread thread = pending[i];
      if (thread.finished) return pending.remove(i);
    }
    _completion_check(pthread_cond_wait(
      &thread_completion_condition, &thread_completion_mutex));
  }
}

/** Joins one worker and exports its result into the joining `Scope` and pools.
    A failure during export still consumes the sealed worker storage.
    A native join failure leaves the `Thread` joinable for a retry. Concurrent
    joins are rejected while one is active; once native join succeeds, export
    cannot be retried.
    Raises: `<bad-arg>` for a NULL handle, `<bad-state>` when another join is
    active or the worker was already joined, `<io-fail>` when the native join
    fails, any cause from result or error export, and
    `<join-fail>` carrying the worker's exported errors. None of them return
    here. A callback that returns `void` joins as `void`; a handled worker
    failure transfers instead of returning a sentinel.
*/
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
  Var result = void, errors = void;
  if (t.errors is not void)
    errors = Context.export_scope(t.result_scope, t.result_pool, t.errors);
  else result = Context.export_scope(
    t.result_scope, t.result_pool, t.result);
  if (errors is not void) raise %(join-fail (errors $errors));
  return result;
}

/* Join owns the sealed result stores after pthread_join succeeds. Release the
   detached canonical pool before destroying the Scope that holds wide boxes,
   then publish JOINED so the handle becomes freeable. This runs under a defer,
   including when result export or `<join-fail>` transfers. */
static void _finish_join(Thread thread) {
  _release_result(thread);
  __atomic_store_n(&thread.state, <joined>, __ATOMIC_SEQ_CST);
}

static void _release_result(Thread thread) {
  if (thread.result_pool) thread.result_pool.release();
  thread.result_pool = NULL;
  if (thread.result_scope) Scope.destroy(thread.result_scope);
  thread.result_scope = NULL;
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
    follow `Thread.wait_any`. The exported result belongs to the caller's
    Scope and pools, as with `Thread.join`.
    A consuming join removes and frees the handle even when worker failure
    or result export raises. A native join failure retains the live handle
    in `pending` for retry. Other entries keep their relative order; a
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
    reported a worker or result-export error. A native join failure leaves
    its handle in `pending` for a retry; all other entries are still attempted.
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
    fprintf(stderr, "Thread.finish_all: cleanup failed; %zu handle(s) remain.\n",
      pending.len());
    return;
  }
  raise %(join-fail (errors ${failures.reverse()}));
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
ParallelMap Iter.parallel_map(Iter source, ThreadValueFn function, int workers) {
  if (workers <= 0) raise %(bad-arg (operation "Iter.parallel_map"));
  ParallelMap map = Scope.malloc(sizeof(struct ParallelMap));
  *map = (struct ParallelMap) { source, function, workers };
  return map;
}

/** Consumes ready worker results into one sequential accumulator.
    Starts at most the configured worker count and reuses those Threads for
    successive inputs. Each completed job publishes one sealed result; the
    caller exports it and runs `accumulate(acc, result)` before assigning
    that worker another input. Other workers may still be running.
    Results follow completion-queue order, not source order. Source traversal
    and accumulation stay on the calling thread. Each worker holds at most
    one unfinished job or unread result.
    A `void` seed uses the first result as accumulator, as with `Iter.foldl`.
    Empty input or a null descriptor returns the seed without invoking the
    worker or accumulator. No result Array is collected. The fold joins all
    remaining workers on every exit, preserving a primary Error during
    cleanup. If native join failure leaves a worker unjoined, the process
    aborts rather than release storage that worker may still use.
    This descriptor supports consuming folds, not general pull iteration.
    Raises: source, start, worker, export, allocation, or accumulator causes,
    including `<void-op>` for a `void` worker result.
*/
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
  while (workers.len() < map.workers && map.source.try_next(input))
    workers.push(_start_value(map.function, input, run));
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
  return acc;
}

static void _parallel_run(Thread thread) {
  while (1) {
    _run_job(thread);
    _completion_check(pthread_mutex_lock(&thread_completion_mutex));
    thread.parallel.ready.push(thread);
    _completion_check(pthread_cond_broadcast(&thread_completion_condition));
    while (!thread.assigned && !thread.parallel.stopping)
      _completion_check(pthread_cond_wait(
        &thread_completion_condition, &thread_completion_mutex));
    int again = thread.assigned;
    thread.assigned = 0;
    _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
    if (!again) return;
  }
}

static Thread _parallel_wait(struct ParallelRun *run) {
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));
  defer _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
  while (!run.ready.len())
    _completion_check(pthread_cond_wait(
      &thread_completion_condition, &thread_completion_mutex));
  return run.ready.remove(0);
}

static Var _parallel_result(Thread worker) {
  defer _release_result(worker);
  return _read_result(worker);
}

static void _parallel_assign(Thread worker, Var input) {
  _completion_check(pthread_mutex_lock(&thread_completion_mutex));
  struct ThreadValueInput *call = _input(worker);
  call.value = input;
  worker.assigned = 1;
  _completion_check(pthread_cond_broadcast(&thread_completion_condition));
  _completion_check(pthread_mutex_unlock(&thread_completion_mutex));
}

static void _parallel_stop(struct ParallelRun *run, Array workers) {
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
  Thread.finish_all(workers);
}
