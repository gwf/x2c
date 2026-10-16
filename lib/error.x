/*  error.x -- handler stack and accumulated errors

    Copyright (c) 2026 Gary William Flake

    Raising an error records it and calls registered handlers, innermost first.
    Each handler sees the errors raised since it was registered and decides
    how to respond. The caller sets the policy for errors no handler accepts.

    Each accumulated record owns an independent `Scope` and one canonical
    `List` and `String` pool. A handler watermark bounds those regions, so
    closing the handler reclaims its complete slice without touching
    application pools. Raising while the error path is itself failing
    reaches the error floor, which allocates nothing.
*/

#pragma once

#include "common.x"
#include "match.x"
#include "mutex.x"



/** Names the structured-error runtime and its static operations.
    Programs do not construct `Error` values; automatic runtime initialization
    owns the per-thread handler, record, policy, and dispatch state.
*/
typedef struct Error *Error;


/** Identifies one `Error`-owned handler registration.
    An observing handle remains valid until `Error.pop`; a transferring-catch
    handle remains valid until `x2c_error_catch_close`. Enclosing frame or
    `Context` cleanup and `Error` shutdown may reclaim a registration first.
*/
typedef struct ErrorHandler *ErrorHandler;


/** Handles a borrowed oldest-first `List` of errors raised since registration.
    `Error` invokes callbacks synchronously from innermost registration
    outward. Return `<handled>`, `<declined>`, or `<fatal>`; `<unwind>` is
    reserved for compiler-generated catches. Any other result behaves as
    `<declined>` and continues outward or to policy. The `List` and its
    contents expire on return.
*/
typedef Symbol (*ErrorHandlerFn)(List errors, Var data);


/** Holds the process-lifetime plans of one compiler-generated filtered catch.
    `arms` is a zero-initialized static array of `arm_count` `Match` sites and
    `default_arm` is the first unpatterned arm, or -1. `state` and `fenced_arm`
    belong to `Error`; a site must be static storage that the first
    registration binds to its patterns.
*/
typedef struct ErrorCatchSite {
  MatchCaptureSite *arms;
  int default_arm, arm_count, state, fenced_arm;
} ErrorCatchSite;


#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "array.x"
#include "block.x"
#include "exception.x"
#include "list.x"
#include "map.x"
#include "pool.x"
#include "scope.x"
#include "string.x"
#include "symbol.x"
#include "symbolset.x"
#include "var.x"

#include "error-macros.x"
#include "error-private.x"

Atom Atom.intern(String spelling);
String Atom.str(Atom atom);

/* thread state

   Each thread owns its handlers, records, and policies. A record pairs one
   entry List with the region that owns its values; error-private.x
   declares the record and handler layouts, which a unit test shares. */

module typedef struct ErrorRegion {
  $error.private.region.fields();
} ErrorRegion;

module typedef struct ErrorRecord {
  $error.private.record.fields();
} ErrorRecord;

module struct ErrorHandler {
  $error.private.handler.fields();
};


/* One `Context`'s overlay: the policies and bound it sets, and the handler
   depth and record height its close returns to. */
module typedef struct ErrorContextState {
  struct ErrorContextState *prev, Map policy, int bound, handler_depth;
  int stack_height;
} *ErrorContextState;


/* `handler_top` heads the registered handlers and `running_top` the detached
   catches whose arms run; during dispatch, `dispatch_saved` holds the
   complete chain and `dispatch_running` the handler offered the error. A
   raise reaches the floor while `floor_only` is nonzero, and
   `rendered[depth]` marks a dispatch whose error Logger rendered. */
module typedef struct ErrorThreadState {
  Scope scope, Block stack, Map policy, int shutdown_done;
  ErrorHandler handler_top, dispatch_saved, dispatch_running, running_top;
  int bound, ErrorContextState context_top, int depth, floor_only, rendered[5];
} *ErrorThreadState;

module {
  "error/dispatch.x",
  "error/policy.x",
  "error/records.x",
  "error/handlers.x",
  "error/runtime.x",
}
