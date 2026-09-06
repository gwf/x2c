/*  error_init.x -- initialization entry points for `Error`

    Copyright (c) 2026 Gary William Flake

    This wrapper stays outside error.x so the compiler does not insert
    initialization into `Error.ready` or the emitter-facing raise entry point.
    Both must observe the pre-initialization state.
*/

#pragma once

#include "common.x"
typedef struct Error *Error;

#pragma private
#include "error.x"

/* Initializes the current thread's Error runtime owner. Runtime startup
   calls this; source programs rely on automatic initialization. */
void Error.initialize(void) {
  Error.initialize_raw();
}

/* Releases the current thread's Error owner after later hooks finish. */
void Error.shutdown(void) {
  Error.shutdown_raw();
}
