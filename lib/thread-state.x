/*  thread-state.x -- native per-thread runtime storage

    Copyright (c) 2026 Gary William Flake.

    Keeps the release order independent of aggregate runtime initialization
    so `Scope` can still operate at the raw allocation floor. Also owns the
    stack bound that recursive runtime operations stop at.
*/

#pragma once

#include "common.x"

threaded int x2c_error_runtime_ready;
threaded unsigned long x2c_execution_stack_low;
static threaded unsigned long native_stack_low;

#if defined(__GLIBC__)
extern int pthread_getattr_np(pthread_t thread, pthread_attr_t *attributes);
#endif

/* The least stack a recursion leaves for the calls and the raise that stop
   it. Sanitized builds need about half of it on the smallest task stack. */
static const unsigned long _STACK_RESERVE = 16 << 10;

/* Exchanges the installed downward-growing task stack bound.
    Zero selects native pthread bounds for stack-aware runtime consumers.
*/
unsigned long x2c_execution_stack_exchange(unsigned long low) {
  unsigned long previous = x2c_execution_stack_low;
  x2c_execution_stack_low = low;
  return previous;
}

/* Returns the lowest frame address that recursion started by the caller
   may reach: four fifths of the way from the caller down to the installed
   task stack bound or, outside a task, the native thread's bound, keeping
   at least _STACK_RESERVE above that bound and no higher than the caller.
   Returns 0, which bounds nothing, when the bound is unknown. */
unsigned long _x2c_stack_floor(void) {
  unsigned long at = (unsigned long) __builtin_frame_address(0);
  unsigned long low = x2c_execution_stack_low;
  if (!low) low = native_stack_low ? native_stack_low : _native_stack_low();
  if (!low || low >= at) return 0;
  unsigned long reserve = (at - low) / 5;
  if (reserve < _STACK_RESERVE) reserve = _STACK_RESERVE;
  return reserve < at - low ? low + reserve : at;
}

/* Reports whether the calling frame lies below `floor`, a result of
   `_x2c_stack_floor`. */
inline int _x2c_stack_below(unsigned long floor) =>
  (unsigned long) __builtin_frame_address(0) < floor;

/* Finds and keeps the native thread's lowest stack address, or 0 when the
   platform does not report it. */
static unsigned long _native_stack_low(void) {
#if defined(__APPLE__)
  pthread_t self = pthread_self();
  native_stack_low = (unsigned long) pthread_get_stackaddr_np(self)
    - pthread_get_stacksize_np(self);
#elif defined(__GLIBC__)
  pthread_attr_t attributes;
  if (!pthread_getattr_np(pthread_self(), &attributes)) {
    void *address;
    size_t size;
    if (!pthread_attr_getstack(&attributes, &address, &size))
      native_stack_low = (unsigned long) address;
    pthread_attr_destroy(&attributes);
  }
#endif
  return native_stack_low;
}

/*  Every module keeps its own per-thread state in a `threaded` object.
    Native static storage releases first, then Match disposes its plan cache
    before Scope destroys its owner. Context, List, String, Error, and
    Exception own no per-thread resources here; their shutdown paths ran.

    Every thread that reaches this storage releases it itself: a worker at the
    end of its entry function and the process at the end of Scope shutdown.
    A pthread-key destructor cannot do this. It runs at an unspecified point
    relative to atexit handlers, so it could free the process thread's state
    before Scope shutdown read it.
*/
void x2c_thread_state_release(void) {
  x2c_static_thread_release();
  x2c_match_thread_release();
  x2c_scope_thread_release();
}
