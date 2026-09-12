/*  thread-state.x -- native per-thread runtime storage

    Copyright (c) 2026 Gary William Flake

    Keeps the release order independent of aggregate runtime initialization
    so `Scope` can still operate at the raw allocation floor.
*/

#pragma once

#include "common.x"

#pragma private

threaded int x2c_error_runtime_ready;

/*  Every module keeps its own per-thread state in a `threaded` object.
    Native static storage releases before Scope destroys its owner. Match,
    Context, List, String, Error, and Exception own no per-thread resources
    here; their shutdown paths ran.

    Every thread that reaches this storage releases it itself: a worker at the
    end of its entry function and the process at the end of Scope shutdown.
    A pthread-key destructor cannot do this. It runs at an unspecified point
    relative to atexit handlers, and on Cosmopolitan it freed the process
    thread's state before Scope shutdown read it.
*/
void x2c_thread_state_release(void) {
  x2c_static_thread_release();
  x2c_scope_thread_release();
}
