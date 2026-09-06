/*  exception.x -- transfer frames for x2c `Error` unwinding and cleanup

    The emitter allocates `ExceptionFrame` objects on the C stack for
    filtered catches and finally clauses. Callable cleanup records cover
    `defer`-only regions without adding a setjmp landing. `Error` unwind drains
    those records before landing each intervening exception frame.
*/

#pragma once

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

#include "common.x"

/** Performs one compiler-generated cleanup using its borrowed environment.
    Exception invokes the callback once after unlinking its record, on normal
    leave or `Error` transfer. The environment must remain live until then.
*/
typedef void (*X2CCleanupFn)(void *env);

/** Holds one caller-owned cleanup registration.
    The record and its callback environment storage must remain live from
    `x2c_cleanup_push` through `x2c_cleanup_leave` or `Error` transfer. The
    runtime owns the record's links while registered. Cleanup records nest and
    run in last-in, first-out order.
*/
typedef struct X2CCleanup {
  struct X2CCleanup *prev, X2CCleanupFn fn, void *env;
} X2CCleanup;

/** Holds one caller-owned non-local `Error` transfer frame.
    Compiler-generated code keeps the frame on the C stack, pushes it before
    establishing its `sigsetjmp` landing, and leaves it in nesting order. Its
    fields capture cleanup and `Error` restore points and are runtime-managed
    while the frame is active.
*/
typedef struct ExceptionFrame {
  struct ExceptionFrame *prev;
  X2CCleanup *cleanup_watermark;
  sigjmp_buf env, volatile Symbol state;
  struct ExceptionFrame *volatile unwind_target, void *error_handler_head;
  void *volatile error_landing_head, int error_dispatch_depth;
  int error_stack_height;
} ExceptionFrame;

#pragma private

typedef struct ExceptionThreadState {
  ExceptionFrame *exception_top;
  X2CCleanup *cleanup_top;
} *ExceptionThreadState;

static threaded struct ExceptionThreadState exception_thread;

static ExceptionThreadState _thread(void) => &exception_thread;

#pragma public

/** Pushes one compiler-generated cleanup record.
    `record` and its `fn` must be nonnull, and the record and borrowed `env`
    must remain live until leave or `Error` transfer. Invalid registration
    exits
    through the raw exception fatal path.
*/
void x2c_cleanup_push(X2CCleanup *record) {
  if (!record || !record.fn) _fatal("invalid cleanup registration");
  ExceptionThreadState state = _thread();
  record.prev = state.cleanup_top;
  state.cleanup_top = record;
}

/** Removes and runs the current compiler-generated cleanup record.
    Records must leave in last-in, first-out order. The record is unlinked
    before its callback runs, so a callback that transfers cannot run it again.
    A null or out-of-order record exits through the raw exception fatal path.
*/
void x2c_cleanup_leave(X2CCleanup *record) {
  ExceptionThreadState state = _thread();
  if (!record || state.cleanup_top != record)
    _fatal("cleanup chain imbalance");
  state.cleanup_top = record.prev;
  record.fn(record.env);
}

/** Initializes and pushes one compiler-generated exception frame.
    The frame records the current cleanup, handler, dispatch-depth, and error
    stack watermarks and must remain live until `x2c_exception_leave`. A null
    frame does nothing.
*/
void x2c_exception_push(ExceptionFrame *e) {
  if (!e) return;
  ExceptionThreadState state = _thread();
  e.prev = state.exception_top;
  e.cleanup_watermark = state.cleanup_top;
  e.state = <active>;
  e.unwind_target = NULL;
  if (x2c_error_runtime_ready) {
    e.error_handler_head = Error.handler_head();
    e.error_landing_head = e.error_handler_head;
    e.error_dispatch_depth = Error.depth();
    e.error_stack_height = Error.count();
  }
  else {
    e.error_handler_head = NULL;
    e.error_landing_head = NULL;
    e.error_dispatch_depth = 0;
    e.error_stack_height = 0;
  }
  state.exception_top = e;
}

/** Transfers an `Error` toward the selected active exception frame.
    `target_ptr` must identify this frame or an outer frame in the current
    thread. The call marks the current frame, drains newer cleanup records in
    last-in, first-out order, records the post-cleanup handler head, and jumps
    to the current frame's landing. It never returns normally. An invalid
    target exits through the raw exception fatal path. The transfer does not
    restore the process signal mask.
*/
void ExceptionFrame.unwind(void *target_ptr) {
  ExceptionFrame *target = target_ptr, *frame = _current();
  int found = 0;
  for (ExceptionFrame *at = frame; at; at = at.prev)
    if (at == target) found = 1;
  if (!frame || !found) _fatal("invalid error unwind target");
  frame.state = <err-unwind>;
  frame.unwind_target = target;
  _cleanup_drain(frame.cleanup_watermark);
  frame.error_landing_head = Error.unwind_head();
  siglongjmp(frame.env, 1);
}

/** Restores `Error` handler and dispatch state after a frame landing.
    Compiler-generated code calls this only on the nonzero `sigsetjmp` path.
    A null frame does nothing.
*/
void x2c_exception_landed(ExceptionFrame *frame) {
  if (!frame) return;
  if (x2c_error_runtime_ready)
    Error.restore_landing(
      frame.error_landing_head, frame.error_dispatch_depth);
}

/** Reports whether any active frame is carrying an `Error` transfer. */
int x2c_exception_unwinding(void) {
  for (ExceptionFrame *frame = _thread().exception_top;
       frame; frame = frame.prev)
    if (frame.state == <err-unwind>) return 1;
  return 0;
}

/** Reports whether `frame` is carrying an `Error` transfer targeted to itself.
    A null, inactive, handled, or intervening frame returns false.
*/
int x2c_exception_is_error_target(ExceptionFrame *frame) =>
  _is_error_unwind(frame) && frame.unwind_target == frame;

/** Marks a selected exception-frame `Error` transfer as handled.
    This prevents `x2c_exception_leave` from continuing the transfer outward.
    A null frame does nothing.
*/
void x2c_exception_mark_handled(ExceptionFrame *frame) {
  if (frame) frame.state = <handled>;
}

/** Removes an active exception frame and continues any pending `Error`
    transfer.
    The frame must be left in nesting order after its cleanup records have been
    removed. Normal leave preserves accumulated errors but reclaims handlers
    registered inside the frame. An intervening unwind instead restores the
    frame's error-stack watermark and transfers to the next outer frame. A null
    frame does nothing; cleanup imbalance exits through the raw fatal path.
*/
void x2c_exception_leave(ExceptionFrame *frame) {
  if (!frame) return;
  ExceptionThreadState state = _thread();
  if (state.cleanup_top != frame.cleanup_watermark)
    _fatal("exception frame cleanup imbalance");
  int should_unwind = frame.state == <err-unwind>;
  ExceptionFrame *target = NULL;
  if (should_unwind) target = frame.unwind_target;
  if (x2c_error_runtime_ready) {
    /* Reclaim handler registrations made inside the frame, and keep the
       errors collected during its normal lifetime. The restore point stays
       available for an abandoned transfer path. */
    int stack_height = should_unwind
                     ? frame.error_stack_height : Error.count();
    Error.trim(frame.error_handler_head, stack_height);
  }
  state.exception_top = frame.prev;
  if (should_unwind) ExceptionFrame.unwind(target);
}

#pragma private

#include "error.x"

static inline ExceptionFrame *_current(void) => _thread().exception_top;

static void _fatal(const char *message) {
  fprintf(stderr, "Fatal: uncaught exception %s\n", message);
  exit(1);
}

/* Drain only records newer than the landing frame's watermark. Unlink each
   record before invoking it so a cleanup that raises cannot run twice. A
   callback may handle a nested resumable Error or alter registrations; discard
   additions toward the pre-callback handler and record heights before
   continuing the original unwind. Removed state is not reconstructed. A
   non-returning Error instead starts its own transfer. */
static void _cleanup_drain(X2CCleanup *watermark) {
  ExceptionThreadState state = _thread();
  while (state.cleanup_top != watermark) {
    if (!state.cleanup_top) _fatal("cleanup watermark not found");
    int handler_depth = 0, stack_height = 0;
    if (x2c_error_runtime_ready) {
      handler_depth = Error.handler_depth();
      stack_height = Error.count();
    }
    X2CCleanup *record = state.cleanup_top;
    state.cleanup_top = record.prev;
    record.fn(record.env);
    if (x2c_error_runtime_ready) Error.restore(handler_depth, stack_height);
  }
}

static int _is_error_unwind(ExceptionFrame *frame) =>
  frame && frame.state == <err-unwind>;
