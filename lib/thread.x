/*  thread.x -- `Context`-backed native worker threads

    Copyright (c) 2026 Gary William Flake

    A `Thread` copies its fixed-size input with max_align_t alignment, runs one
    callback in an isolated `Context`, and seals the exported result or error
    snapshot until join. Over-aligned input types are not supported.
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

/** A heap-owned native worker handle with one consuming join.
    A started `Thread` must be joined, including after its callback finishes,
    and then released with `Thread.free`.
*/
typedef struct Thread *Thread;

#pragma private

#include "context.x"
#include "dispatch.x"
#include "error.x"
#include "error_init.x"
#include "exception.x"
#include "list.x"
#include "logger.x"
#include "match.x"
#include "pool.x"
#include "scope.x"
#include "string.x"

#include <errno.h>
#include <stddef.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

enum ThreadState {
  THREAD_RUNNING,
  THREAD_JOINING,
  THREAD_JOINED
};

struct Thread {
  pthread_t native, ThreadFn function, size_t input_size, Scope result_scope;
  Pool result_pool;
  Var result;
  Var errors;
  void *policy;
  int state;
};

static int thread_live_count;
static pthread_once_t thread_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

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

static size_t _input_offset(void) {
  size_t alignment = _Alignof(max_align_t);
  size_t remainder = sizeof(struct Thread) % alignment;
  return remainder ? sizeof(struct Thread) + alignment - remainder
                   : sizeof(struct Thread);
}

static void *_input(Thread thread) =>
  (unsigned char *) thread + _input_offset();

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

static void _register_shutdown(void) {
  Context.initialize();
  x2c_match_initialize();
  Scope.shutdown_hook(_shutdown);
}

/* The outermost of the worker's registrations, so a cause the callback did not
   catch reaches it after `Logger` has had its look. A cause whose policy is
   `<abort>`, which is every shared non-returning cause and every code no
   policy names, would reach the error floor and end the process; a worker
   leaves the callback as `<join-fail>` carrying this snapshot instead. Any
   other policy resolves the cause and returns to its raise, exactly as it does
   on the starting thread, so the backstop never sees it. The replacement cause
   dispatches outward from here, which is the `try` below and nothing else. */
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
  raise %(join-fail (owner "Thread callback"));
}

/* Join owns the sealed result stores after pthread_join succeeds. Release the
   detached canonical pool before destroying the Scope that holds wide boxes,
   then publish JOINED so the handle becomes freeable. This runs under a defer,
   including when result export or `<join-fail>` transfers. */
static void _finish_join(Thread thread) {
  if (thread.result_pool) thread.result_pool.release();
  thread.result_pool = NULL;
  if (thread.result_scope) Scope.destroy(thread.result_scope);
  thread.result_scope = NULL;
  __atomic_store_n(&thread.state, THREAD_JOINED, __ATOMIC_SEQ_CST);
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

static void *_run(void *argument) {
  Thread thread = argument;
  (void) Scope.top();
  Pool.thread_initialize();
  Error.initialize_raw();
  Error.policy_adopt(thread.policy);
  thread.policy = NULL;

  thread.result_scope = Scope.new_named("Thread result");
  Scope.push(&thread.result_scope);
  thread.result_pool = Pool.open_named("Thread result");

  /* Callback temporaries belong to `work`; its exported result or Error
     snapshot is moved or copied into the outer result stores before `work`
     closes. Detach that result pool and pop its Scope only afterward, sealing
     both for the joining thread. Error and other per-thread state shut down
     last, after no worker-private value still needs them. */
  Context work = Context.open_isolated_named("Thread callback");
  int mark = Error.mark();
  try {
    ErrorHandler observer = Error.push(_capture_errors, thread);
    defer Error.pop(observer);
    ErrorHandler logger_handler = Error.push(Logger.error_handler, void);
    defer Error.pop(logger_handler);
    const void *input = thread.input_size ? _input(thread) : NULL;
    Var result = thread.function(input, thread.input_size);
    thread.result = work.export(result);
  }
  /* A registered catch is consulted during dispatch, before `Error` reaches
     its policy table, so a bare `catch:` would match first and no policy could
     ever resume inside a worker. `_capture_errors` converts the causes that
     really must leave the callback, so this backstop needs only that cause and
     the one an `Error.push` failure can raise before the observer exists. */
  catch %(join-fail *): _worker_failed(thread, mark);
  catch %(alloc-fail *): _worker_failed(thread, mark);
  work.close();
  thread.result_pool = Pool.detach();
  Scope.pop();

  Error.shutdown_raw();
  x2c_thread_state_release();
  return NULL;
}

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
Thread Thread.start(ThreadFn function, const void *input, size_t input_size) {
  if (!function || (input_size && !input))
    raise %(bad-arg (owner "Thread.start"));
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
  __atomic_store_n(&thread.state, THREAD_RUNNING, __ATOMIC_SEQ_CST);
  if (input_size) memcpy(_input(thread), input, input_size);
  if (pthread_once(&thread_shutdown_once, _register_shutdown)) {
    Error.policy_release(thread.policy);
    free(thread);
    fprintf(stderr, "Thread: could not register shutdown\n");
    abort();
  }
  __atomic_fetch_add(&thread_live_count, 1, __ATOMIC_SEQ_CST);
  Pool.thread_start();
  pthread_attr_t attributes;
  _stack_attributes(&attributes);
  /* Hold descriptor registration stable across pthread_create. Success makes
     it permanently read-only; failure unlocks it, restores the live count,
     and releases the handle while pool locking stays enabled. */
  x2c_descriptor_thread_start_begin();
  int error = pthread_create(&thread.native, &attributes, _run, thread);
  x2c_descriptor_thread_start_end(!error);
  pthread_attr_destroy(&attributes);
  if (error) {
    __atomic_fetch_sub(&thread_live_count, 1, __ATOMIC_SEQ_CST);
    Error.policy_release(thread.policy);
    free(thread);
    _error("pthread_create", error);
  }
  return thread;
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
  if (!t) raise %(bad-arg (owner "Thread.join"));
  int expected = THREAD_RUNNING;
  if (!__atomic_compare_exchange_n(
    &t.state, &expected, THREAD_JOINING, 0,
    __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
    raise %(bad-state (owner "Thread.join"));
  }
  int error = pthread_join(t.native, NULL);
  if (error) {
    __atomic_store_n(&t.state, THREAD_RUNNING, __ATOMIC_SEQ_CST);
    _error("pthread_join", error);
  }

  __atomic_fetch_sub(&thread_live_count, 1, __ATOMIC_SEQ_CST);
  defer _finish_join(t);
  Var result = void, errors = void;
  if (t.errors is not void)
    errors = Context.export_scope(t.result_scope, t.result_pool, t.errors);
  else result = Context.export_scope(
    t.result_scope, t.result_pool, t.result);
  if (errors is not void) raise %(join-fail (errors $errors));
  return result;
}

/** Frees a `Thread` handle after its consuming join has completed.
    Raises: `<bad-state>` for NULL, running, or joining handles.
*/
void Thread.free(Thread t) {
  if (!t || __atomic_load_n(&t.state, __ATOMIC_SEQ_CST) != THREAD_JOINED)
    raise %(bad-state (owner "Thread.free"));
  free(t);
}
