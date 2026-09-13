/*  error.x -- handler stack and accumulated errors

    Copyright (c) 2026 Gary William Flake

    Raising an error records it and calls registered handlers, innermost first.
    Each handler sees the errors raised since it was registered and decides
    how to respond. The caller sets the policy for errors no handler accepts.

    Each accumulated record owns an independent `Scope` and
    canonical `List` and
    `String` pools. A handler watermark bounds those regions, so closing the
    handler reclaims its complete slice without touching application pools.
    Raising while the error path is itself failing uses the error floor,
    which allocates nothing.
 */

#pragma once

#include "common.x"

#define ERROR_DEFAULT_BOUND 4096

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
    outward.
    Return `<handled>`, `<declined>`, or `<fatal>`; `<unwind>` is reserved for
    compiler-generated catches. Any other result behaves as `<declined>` and
    continues outward or to policy. The `List` and its contents expire on
    return.
*/
typedef Symbol (*ErrorHandlerFn)(List errors, Var data);

#pragma private
$(import "error-macros.xmacro")
$(import "error-private.xmacro")
$error.private.types();
#pragma public

/** Registers one compiler-generated transferring catch.
    `target` names the `ExceptionFrame` that the caller pushes immediately
    afterward; the following `arm_count` arguments are `List` patterns in
    source
    order. The registration copies pattern `Var`s into its table but borrows
    every referenced `List` graph and `MatchPlan` constant.
    Those values and the
    target frame must outlive the handle. A null target, zero arm count, or
    unavailable `Error` runtime reaches the raw error floor.
    Raises: `<alloc-fail>` when registration or fence-detail storage cannot be
    allocated, or `<size-limit>` when an arm's pattern crosses a `Match`
    lowering
    fence. A fenced arm can never be selected. The registration is reclaimed
    and the error reaches the enclosing handler; the caller's own frame is not
    yet pushed, so it never sees its own failure.
*/
ErrorHandler x2c_error_catch_push(void *target, unsigned arm_count, ...) {
  if (!Error.ready() || !target || !arm_count)
    _floor(<invariant>, "could not register transferring catch");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorHandler h = Scope.malloc_in(&state.scope, sizeof(struct ErrorHandler));
  *h = (struct ErrorHandler) {
      .prev = state.handler_top, .fn = NULL, .data = void,
      .watermark = Error.count(), .target = target, .selected = -1,
      .capture_values = NULL, .retained = NULL, .detached = 0
  };
  int pushed = _scope_push(
    <alloc-fail>, "could not enter error scope for catch patterns");
  h.patterns = %[];
  h.plans = Block.new(sizeof(MatchPlan));
  const char *fenced = NULL, int fenced_arm = -1, va_list args;
  va_start(args, arm_count);
  for (unsigned i = 0; i < arm_count; i++) {
    Var pattern = va_arg(args, Var);
    h.patterns.push(pattern);
    MatchPlan plan = pattern == <default> ? NULL : MatchPlan.prepare(pattern);
    h.plans.push(&plan);
    if (plan && plan.status == MACHINE_INELIGIBLE && !fenced) {
      fenced = plan.reason;
      fenced_arm = (int) i;
    }
  }
  va_end(args);
  if (pushed) Scope.pop();
  state.floor_only--;
  /* Report the fence here, where the unusable arm can be named. Reporting it
     from dispatch would re-enter the raise path that is already answering
     one error. */
  if (fenced) {
    _handler_free(h);
    String fence = String.new(fenced);
    raise %(size-limit (owner "catch") (arm $fenced_arm) (fence $fence));
  }
  state.handler_top = h;
  return h;
}

/** Returns the selected zero-based catch arm, or -1 before selection or for a
    null handle.
*/
int x2c_error_catch_selected(ErrorHandler handle) =>
  handle ? handle.selected : -1;

/** Returns one borrowed capture from a selected catch arm.
    An invalid index, a null or unselected handle, or an unbound alternative
    returns `void`. The value remains valid until the handle is closed; use
    `Error.snapshot` to keep it longer.
*/
Var x2c_error_catch_capture(ErrorHandler handle, int index) {
  if (!handle || !handle.capture_values || index < 0 ||
      index >= (int) handle.capture_values.length)
    return void;
  Var *values = handle.capture_values.bytes;
  return values[index];
}

/** Removes the top transferring catch while retaining its selected state.
    This lets the catch arm raise outward without matching itself. The caller
    must still close the handle; repeated detach and a null handle do nothing.
    Detaching out of stack order reaches the raw error floor.
*/
void x2c_error_catch_detach(ErrorHandler handle) {
  if (!handle || handle.detached) return;
  ErrorThreadState state = _thread();
  if (state.handler_top != handle)
    _floor(<invariant>, "transferring catch detach out of order");
  state.handler_top = handle.prev;
  handle.detached = 1;
}

/** Closes and invalidates a transferring-catch handle.
    A detached handle releases its plans, captures, and retained error records.
    An attached handle additionally removes itself and truncates records above
    its registration watermark. Attached handles must close in stack order;
    violating that order reaches the raw error floor. A null handle does
    nothing.
*/
void x2c_error_catch_close(ErrorHandler handle) {
  if (!handle) return;
  if (!handle.detached) {
    ErrorThreadState state = _thread();
    if (state.handler_top != handle)
      _floor(<invariant>, "transferring catch close out of order");
    _truncate(handle.watermark);
    state.handler_top = handle.prev;
  }
  _handler_free(handle);
}

/** Raises one compiler-generated error from a prepared detail `List`.
    The runtime copies admissible detail before synchronous handler dispatch.
    Resumable causes may return after handling or policy; shared non-returning
    causes may transfer to a filtered catch but never return here. Invalid
    detail or unavailable, reentrant, or failed `Error` machinery reaches the
    raw error floor.
*/
void x2c_error_raise(Symbol code, List detail) {
  Error.raise(code, detail);
}

/** Marks the current nested error dispatch as already rendered by `Logger`.
    This suppresses only `Error`'s fallback report for a `<log>` policy.
    Calling
    outside dispatch has no effect.
*/
void Error.note_rendered(void) {
  ErrorThreadState state = _thread();
  if (state.depth > 0 && state.depth <= ERROR_MAX_DEPTH)
    state.rendered[state.depth] = 1;
}

/** Raises one compiler-generated error from native key-value arguments.
    `pair_count` controls the following alternating `Var` keys and values;
    `site`
    may be NULL. The runtime copies admissible values and preserves pair order.
    Resumable causes may return after handling or policy; shared non-returning
    causes may transfer to a filtered catch but never return here. Invalid
    detail or unavailable, reentrant, or failed `Error` machinery reaches the
    raw error floor.
*/
void x2c_error_raise_n(
  const X2CErrorSite *site, Symbol code, unsigned pair_count, ...) {
  Symbol effective = code ? code : <invariant>;
  _raise_enter(effective);
  ErrorThreadState state = _thread();
  int raised_at = Error.count(), depth = state.depth;
  state.rendered[depth] = 0;
  va_list args;
  va_start(args, pair_count);
  _record_n(site, effective, pair_count, args);
  va_end(args);
  _dispatch(effective, raised_at, depth);
}

/** Returns the current thread's number of registered `Error` handlers. */
int Error.handler_depth(void) {
  int depth = 0;
  for (ErrorHandler h = _thread().handler_top; h; h = h.prev) depth++;
  return depth;
}

/** Returns the current thread's borrowed top `Error`-handler pointer.
    Exception frames use this opaque value as a restore watermark; it remains
    valid only while its registration remains live.
*/
void *Error.handler_head(void) => _thread().handler_top;

/** Returns the handler head retained for the current `Error` transfer.
    During handler dispatch this is the saved pre-dispatch head, even though
    the active callback is temporarily hidden from nested raises. Exception
    frames store the opaque result as their landing watermark.
*/
void *Error.unwind_head(void) {
  ErrorThreadState state = _thread();
  return state.dispatch_saved ? state.dispatch_saved : state.handler_top;
}

/** Restores `Error` state after an exception frame lands.
    `saved_head` is a prior handler watermark and `saved_depth` is the dispatch
    depth captured when the frame was pushed. The saved head is restored only
    when the current handler head is still a suffix of its chain; dispatch
    bookkeeping is cleared.
*/
void Error.restore_landing(void *saved_head, int saved_depth) {
  ErrorHandler saved = saved_head;
  ErrorThreadState state = _thread();
  if (_chain_contains(saved, state.handler_top))
    state.handler_top = saved;
  state.dispatch_saved = NULL;
  state.depth = saved_depth;
}

/** Trims `Error` state while an exception frame leaves.
    Handlers newer than `saved_head` are reclaimed. Records at and above
    `stack_height` are also reclaimed; pass the current height on normal frame
    exit to preserve collected errors.
*/
void Error.trim(void *saved_head, int stack_height) {
  ErrorHandler saved = saved_head;
  ErrorThreadState state = _thread();
  if (_chain_contains(state.handler_top, saved))
    _unwind_to(state, saved, 1);
  _truncate(stack_height);
}

/** Discards handler and record growth after one cleanup callback.
    Registrations and records created by that callback are reclaimed toward
    the saved heights before the interrupted unwind continues. State the
    callback itself removed is not reconstructed.
*/
void Error.restore(int handler_depth, int stack_height) {
  ErrorThreadState state = _thread();
  _unwind_to(state, _handler_at_depth(state, handler_depth), 1);
  _truncate(stack_height);
}

/** Initializes the current thread's `Error` runtime without lifecycle
    insertion.
    Repeated calls after successful initialization and calls after shutdown do
    nothing. Initialization owns a private `Scope`, record stack, and policy
    `Map`;
    failure before the `Error` runtime becomes ready reaches the raw error
    floor.
*/
void Error.initialize_raw(void) {
  ErrorThreadState state = _thread();
  if (state.scope || state.shutdown_done) return;
  state.scope = Scope.new_named("error");
  Scope.push(&state.scope);
  state.stack = Block.new(sizeof(ErrorRecord));
  state.policy = %{};
  Scope.pop();
  x2c_error_runtime_ready = 1;
  _initialize_policies();
}

/* Runtime shutdown calls this after later subsystem hooks and Logger have
   closed, while the raw Scope operations needed for reclamation remain live.
   Source programs use automatic lifecycle insertion instead. */
/** Releases the current thread's `Error` storage without lifecycle insertion.
    The call reclaims all registrations, records, policies, and private storage
    and makes `Error.ready` false. Repeated calls do nothing; later raises
    reach the raw error floor.
*/
void Error.shutdown_raw(void) {
  ErrorThreadState state = _thread();
  if (state.shutdown_done) return;
  _unwind_to(state, NULL, 1);
  _truncate(0);
  if ((void *) state.stack != NULL) {
    state.stack.free();
    state.stack = NULL;
  }
  state.policy = NULL;
  state.shutdown_done = 1;
  x2c_error_runtime_ready = 0;
  if (state.scope) {
    Scope.destroy(state.scope);
    state.scope = NULL;
  }
}

#pragma private

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "array.x"
#include "block.x"
#include "exception.x"
#include "list.x"
#include "map.x"
#include "match.x"
#include "pool.x"
#include "scope.x"
#include "string.x"
#include "symbol.x"
#include "symbolset.x"
#include "var.x"

Atom Atom.intern(String spelling);
String Atom.str(Atom atom);

typedef struct ErrorContextState {
  struct ErrorContextState *prev, Map policy, int bound, handler_depth;
  int stack_height;
} *ErrorContextState;

/* The nested-handler probe reaches depth 2; two more levels are reserve for
   a rendering or allocation handler that itself must raise. */
#define ERROR_MAX_DEPTH 4

typedef struct ErrorThreadState {
  Scope scope, Block stack, Map policy, int shutdown_done;
  ErrorHandler handler_top, dispatch_saved, int bound;
  ErrorContextState context_top;
  int depth, floor_only, rendered[5];
} *ErrorThreadState;

static threaded struct ErrorThreadState error_thread;

static ErrorThreadState _thread(void) {
  ErrorThreadState state = &error_thread;
  if (!state.bound) state.bound = ERROR_DEFAULT_BOUND;
  return state;
}

/* This is the same shared cause table that drives compiler unreachable
   emission. Error locks every listed policy to abort: observing handlers may
   inspect but cannot consume one, while a matching compiler catch transfers
   control without returning to its raising call. */
static const SymbolSet error_nonreturning_causes =
  $error.nonreturning.causes();

static int _never_returns(Symbol code) =>
  error_nonreturning_causes.contains(code);

static void _initialize_policies(void) {
  foreach (Symbol code, error_nonreturning_causes)
    Error.policy_set(code, <abort>);
}

/* Reports a failure that the rich error path cannot handle and aborts.
    Reachable before initialization, after shutdown, and when raising has
    re-entered itself. Allocates nothing and calls nothing that can.
*/
static void _floor(Symbol code, const char *why) {
  fprintf(
    stderr, "x2c error floor: code 0x%lx: %s\n",
    (unsigned long) code, why ? why : "unknown");
  fflush(stderr);
  abort();
}

// fallback when <log> has no active Logger renderer
static void _report(Symbol code) {
  char spelling[SYMBOL_MAX_5BIT + 1] = { 0 };
  code.decode(spelling);
  fprintf(stderr, "x2c error: <%s>\n", spelling);
  fflush(stderr);
}

static int _enter(void) {
  ErrorThreadState state = _thread();
  if (state.shutdown_done) return 0;
  if (state.depth >= ERROR_MAX_DEPTH) return 0;
  state.depth++;
  return 1;
}

static void _leave(void) {
  ErrorThreadState state = _thread();
  if (state.depth > 0) state.depth--;
}

static int _scope_push(Symbol code, const char *message) {
  ErrorThreadState state = _thread();
  if (Scope.top() == &state.scope) return 0;
  Scope.push(&state.scope);
  if (Scope.top() != &state.scope) _floor(code, message);
  return 1;
}

static ErrorRecord *_record_at(int index) {
  ErrorRecord *records = _thread().stack.bytes;
  return &records[index];
}

/* Error Lists can contain Strings from the region's sibling String pool.
   Release the borrowing List pool first, then String storage, then wide scalar
   boxes in the Scope. No region value survives this operation. */
static void _region_destroy(ErrorRegion *region) {
  if (region.lists) region.lists = Pool.release(region.lists);
  if (region.strings) region.strings = Pool.release(region.strings);
  if (region.values) {
    Scope.destroy(region.values);
    region.values = NULL;
  }
}

static ErrorRegion _region_new(void) {
  ErrorRegion region = { 0 };
  region.values = Scope.new_named("Error record values");
  region.strings = Pool.retain_named(NULL, "Error record Strings");
  region.lists = Pool.retain_named(NULL, "Error record Lists");
  return region;
}

static List _cons(ErrorRegion *region, Var head, List tail) =>
  List.cons_in(region.lists, head, tail);

static Var _copy_value(ErrorRegion *region, Var value) {
  if (value is void)
    _floor(<bad-types>, "void is not an admissible error detail");
  if (value.is_null() || value.is_nil() || value is <symbol>) return value;
  if (value.is_wide()) {
    Scope.push(&region.values);
    Var owned = value.clone_wide();
    Scope.pop();
    return owned;
  }
  if (value.is_integer() || value.is_floating()) return value;
  if (value is <string>) {
    String source = value;
    String owned = String.new_in(region.strings, source, source.len());
    return owned;
  }
  if (value is <lsym>) {
    String source = value.str();
    String owned = String.new_in(region.strings, source, source.len());
    return Var.new(<lsym>, owned);
  }
  if (value is <list>) {
    List source = value;
    Var head = _copy_value(region, source.car());
    List tail = _copy_value(region, source.cdr());
    return _cons(region, head, tail);
  }
  _floor(<bad-types>, "error detail contains an identity-bearing value");
}

static List _pair(ErrorRegion *region, Var key, Var value) =>
  _cons(region, key, _cons(region, value, NULL));

static List _field(ErrorRegion *region, Var key, Var value, List tail) =>
  _cons(region, _pair(region, key, value), tail);

/* Builds one error record.
    The shape matches Diagnostics entries so a handler can match on it.
    Symbols are bound and interpolated, never written inside the form.
*/
static List _location(ErrorRegion *region, const X2CErrorSite *site) {
  if (!site) return NULL;
  const char *file_source = site.file ? site.file : "<unknown>";
  const char *function_source = site.function ? site.function : "<unknown>";
  String file = String.new_in(
    region.strings, file_source, strlen(file_source));
  String function = String.new_in(
    region.strings, function_source, strlen(function_source));
  int line = site.line, List location = NULL;
  location = _field(region, <function>, function, location);
  location = _field(region, <line>, line, location);
  location = _field(region, <file>, file, location);
  return location;
}

static List _entry(
  ErrorRegion *region, const X2CErrorSite *site, Symbol code, List detail) {
  List location = _location(region, site), entry = NULL;
  entry = _field(region, <location>, location, entry);
  entry = _field(region, <detail>, detail, entry);
  entry = _field(region, <code>, code, entry);
  return entry;
}

static void _append_record(ErrorRecord *record) {
  _thread().stack.push(record);
}

static void _record(const X2CErrorSite *site, Symbol code, List detail) {
  if (Error.count() >= Error.bound())
    _floor(code, "error stack exceeded its bound");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorRecord record = { .region = _region_new() };
  detail = _copy_value(&record.region, detail);
  record.entry = _entry(&record.region, site, code, detail);
  _append_record(&record);
  state.floor_only--;
}

typedef struct ErrorPair {
  Var key;
  Var value;
} ErrorPair;

static void _record_n(
  const X2CErrorSite *site, Symbol code, unsigned pair_count, va_list args) {
  if (Error.count() >= Error.bound())
    _floor(code, "error stack exceeded its bound");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorRecord record = { .region = _region_new() };
  int pushed = _scope_push(
    code, "could not enter error scope for counted detail");
  Block pairs = Block.new(sizeof(ErrorPair));
  for (unsigned i = 0; i < pair_count; i++) {
    ErrorPair pair = {
      .key = _copy_value(&record.region, va_arg(args, Var)),
      .value = _copy_value(&record.region, va_arg(args, Var))
    };
    pairs.push(&pair);
  }
  ErrorPair *items = pairs.bytes;
  List detail = NULL;
  for (int i = (int) pair_count - 1; i >= 0; i--)
    detail = _cons(
      &record.region,
      _pair(&record.region, items[i].key, items[i].value),
      detail);
  pairs.free();
  if (pushed) Scope.pop();
  record.entry = _entry(&record.region, site, code, detail);
  _append_record(&record);
  state.floor_only--;
}

static void _truncate(int mark) {
  if (!Error.ready() || mark < 0) return;
  while (Error.count() > mark) {
    ErrorRecord *record = _record_at(Error.count() - 1);
    _region_destroy(&record.region);
    _thread().stack.pop();
  }
}

/** Returns the current nested error-dispatch depth.
    This is the nesting depth of error dispatch. `Error.count` returns the
    number of accumulated errors.
*/
int Error.depth(void) => _thread().depth;

/** Returns the number of errors currently accumulated.
    Returns zero before `Error` initialization and after shutdown.
*/
int Error.count(void) => Error.ready() ? (int) _thread().stack.length : 0;

/** Captures the current error-stack position.
    Pass the result to `Error.since` to inspect only later errors.
*/
int Error.mark(void) => Error.count();

static Var _snapshot_value(Var v) {
  if (v is void)
    _floor(<bad-types>, "void is not an admissible error snapshot");
  if (v.is_null() || v.is_nil() || v is <symbol>) return v;
  if (v.is_wide()) {
    Scope owner = *Scope.top();
    while (owner && owner.down) owner = owner.down;
    Scope.push(&owner);
    Var copy = v.clone_wide();
    Scope.pop();
    return copy;
  }
  if (v.is_integer() || v.is_floating()) return v;
  if (v is <string>) {
    String source = v, copy = String.new_len(source, source.len());
    String.try_own(copy);
    return copy;
  }
  if (v is <lsym>) {
    String spelling = v.str();
    Atom copy = Atom.intern(String.new_len(spelling, spelling.len()));
    if (copy is <lsym>) String.try_own(copy.str());
    return copy;
  }
  if (v is <list>) {
    List source = v;
    Var head = _snapshot_value(source.car());
    List tail = _snapshot_value(source.cdr()), copy = cons(head, tail);
    List.try_own(copy);
    return copy;
  }
  _floor(
    <bad-types>, "error snapshot contains an identity-bearing value");
}

/** Copies one admissible error value into the caller's ordinary owners.
    Handler slices and filtered-catch bindings are borrowed. Snapshot a value
    that must outlive its callback or selected arm; `String`s and `List`s enter
    the caller's outermost canonical pools and wide scalar boxes enter its
    outermost `Scope`, so nested caller brackets may be released safely.
    Invalid or identity-bearing values and failures while copying reach the raw
    error floor; they never re-enter handler dispatch.
*/
Var Error.snapshot(Var value) {
  ErrorThreadState state = _thread();
  state.floor_only++;
  Var result = _snapshot_value(value);
  state.floor_only--;
  return result;
}

/** Copies one admissible error value into explicit runtime owners.
    `String`s and `List`s are canonicalized through `pool`'s chain and remain
    live
    until their actual owning pool is released. Wide scalar boxes enter
    `*values`, whose possibly updated `Scope` head is written back, and remain
    live until that `Scope` is destroyed. `Null` owners, invalid or
    identity-bearing values, and failures while copying reach the raw floor.
*/
Var Error.snapshot_in(Var value, Scope *values, Pool pool) {
  if (!values || !pool)
    _floor(<bad-arg>, "error snapshot requires explicit owners");
  ErrorRegion region = {
    .values = *values, .strings = pool, .lists = pool
  };
  ErrorThreadState state = _thread();
  state.floor_only++;
  Var result = _copy_value(&region, value);
  state.floor_only--;
  *values = region.values;
  return result;
}

/** Copies errors at and after `mark` into explicit owners, oldest first.
    `String`s and `List`s are canonicalized through `pool`'s chain and remain
    live
    until their actual owning pool is released. Wide scalar boxes enter
    `*values`, whose possibly updated `Scope` head is written back, and remain
    live until that `Scope` is destroyed. An unavailable runtime or negative
    mark
    returns `nil`. `Null` owners or failures while copying reach the raw floor.
*/
List Error.since_in(int mark, Scope *values, Pool pool) {
  if (!Error.ready() || mark < 0) return NULL;
  if (!values || !pool)
    _floor(<bad-arg>, "error snapshot requires explicit owners");
  ErrorRegion region = {
    .values = *values, .strings = pool, .lists = pool
  };
  ErrorThreadState state = _thread();
  state.floor_only++;
  List out = NULL;
  for (int i = Error.count() - 1; i >= mark; i--) {
    ErrorRecord *record = _record_at(i);
    Var entry = _copy_value(&region, record.entry);
    out = _cons(&region, entry, out);
  }
  state.floor_only--;
  *values = region.values;
  return out;
}

static List _view_since(ErrorRegion *region, int mark) {
  List out = NULL;
  for (int i = Error.count() - 1; i >= mark; i--) {
    ErrorRecord *record = _record_at(i);
    Var entry = _copy_value(region, record.entry);
    out = _cons(region, entry, out);
  }
  return out;
}

/** Returns the accumulated errors at and after `mark`, oldest first.
    Each entry has `code`, `detail`, and `location` fields. An invalid mark or
    an unavailable `Error` runtime returns `nil`. The snapshot enters the
    caller's
    outermost `Scope` and canonical pools and remains live until those owners
    are
    released. Failure to materialize it reaches the non-reentrant error floor.
*/
List Error.since(int mark) {
  if (!Error.ready() || mark < 0) return NULL;
  ErrorThreadState state = _thread();
  state.floor_only++;
  List out = NULL;
  for (int i = Error.count() - 1; i >= mark; i--) {
    ErrorRecord *record = _record_at(i);
    Var entry = _snapshot_value(record.entry);
    out = cons(entry, out);
  }
  List.try_own(out);
  state.floor_only--;
  return out;
}

/** Sets the default disposition for `code`.
    Supported policy values are `<abort>`, `<collect>`, `<log>`, and
    `<ignore>`. Another value raises `<bad-arg>` and leaves the previous policy
    unchanged. Shared non-returning causes accept only `<abort>`; another
    disposition raises `<bad-arg>` and leaves their policy unchanged. The call
    is a no-op while `Error` is unavailable; failure to update `Error`-owned
    storage reaches the non-reentrant error floor.
*/
void Error.policy_set(Symbol code, Symbol disposition) {
  if (!Error.ready()) return;
  if (disposition != <abort> && disposition != <log> &&
      disposition != <collect> && disposition != <ignore>)
    raise %(bad-arg (owner "Error.policy_set") (dispositio $disposition));
  if (_never_returns(code) && disposition != <abort>)
    raise %(bad-arg (owner "Error.policy_set") (code $code)
                   (dispositio $disposition));
  ErrorThreadState state = _thread();
  state.floor_only++;
  int pushed = _scope_push(
    code, "could not enter error scope while setting policy");
  Map policy = state.context_top ? state.context_top.policy : state.policy;
  policy.setindex(code, disposition);
  if (pushed) Scope.pop();
  state.floor_only--;
}

/** Returns the default disposition for `code`.
    Unknown codes and an unavailable `Error` runtime default to `<abort>`.
*/
Symbol Error.policy_get(Symbol code) {
  if (!Error.ready()) return <abort>;
  ErrorThreadState thread = _thread();
  for (ErrorContextState state = thread.context_top; state;
       state = state.prev) {
    Var found = state.policy[code];
    if (found is not void) return found;
  }
  Var found = thread.policy[code];
  if (found is void) return <abort>;
  return found;
}

/** Returns the maximum number of errors that may remain accumulated. */
int Error.bound(void) {
  ErrorThreadState state = _thread();
  return state.context_top ? state.context_top.bound : state.bound;
}

/** Sets the accumulated-error bound when `bound` is positive.
    A zero or negative value leaves the current bound unchanged.
*/
void Error.bound_set(int bound) {
  if (bound <= 0) return;
  ErrorThreadState state = _thread();
  if (state.context_top) state.context_top.bound = bound;
  else state.bound = bound;
}

/** Pushes an observing handler and returns its removal handle.
    The handler sees a borrowed view of errors raised after this registration;
    the view is valid only during the callback. Use `Error.snapshot` for any
    value that must escape. Returning `<handled>` consumes that slice,
    `<declined>` leaves it for outer handlers, and `<fatal>` reaches the error
    floor. For a shared non-returning cause, `<handled>` also reaches the
    floor. A null callback or unavailable runtime returns NULL without
    registering. Raises `<alloc-fail>` if registration storage cannot be
    allocated. `data` is retained by value without copying its referent, so
    any referenced storage must outlive the registration.
*/
ErrorHandler Error.push(ErrorHandlerFn fn, Var data) {
  if (!Error.ready() || !fn) return NULL;
  ErrorThreadState state = _thread();
  ErrorHandler h = Scope.malloc_in(&state.scope, sizeof(struct ErrorHandler));
  h.prev = state.handler_top;
  h.fn = fn;
  h.data = data;
  h.watermark = Error.count();
  h.patterns = NULL;
  h.plans = NULL;
  h.target = NULL;
  h.selected = -1;
  h.capture_values = NULL;
  h.retained = NULL;
  h.detached = 0;
  state.handler_top = h;
  return h;
}

static void _retained_destroy(Block retained) {
  if ((void *) retained == NULL) return;
  ErrorRecord *records = retained.bytes;
  for (size_t i = 0; i < retained.length; i++)
    _region_destroy(&records[i].region);
  retained.free();
}

/* Pops handlers down to `stop`, reclaiming each one. `truncate` also discards
   the records above every popped handler's watermark; a Context closed by an
   unwinding exception keeps those for its outer handler and is the one caller
   that passes zero. */
static void _unwind_to(
  ErrorThreadState state, ErrorHandler stop, int truncate) {
  while (state.handler_top && state.handler_top != stop) {
    ErrorHandler removed = state.handler_top;
    state.handler_top = removed.prev;
    if (truncate) _truncate(removed.watermark);
    _handler_free(removed);
  }
}

/* Returns the handler that leaves exactly `depth` registered, or the current
   head when the stack is already that shallow. The height is measured once
   here so an unwind does not re-measure it per cleanup record. */
static ErrorHandler _handler_at_depth(
  ErrorThreadState state, int depth) {
  ErrorHandler stop = state.handler_top;
  for (int height = Error.handler_depth(); height > depth && stop; height--)
    stop = stop.prev;
  return stop;
}

static void _handler_free(ErrorHandler handle) {
  if (!handle) return;
  if ((void *) handle.patterns != NULL) handle.patterns.free();
  if ((void *) handle.plans != NULL) {
    MatchPlan *plans = handle.plans.bytes;
    for (size_t i = 0; i < handle.plans.length; i++) {
      MatchPlan plan = plans[i];
      plan.free();
    }
    handle.plans.free();
  }
  if ((void *) handle.capture_values != NULL) handle.capture_values.free();
  _retained_destroy(handle.retained);
  Scope.free(handle);
}

/** Closes the most recently pushed observing handler.
    Closing truncates and reclaims every error above the handler's registration
    watermark, then unregisters it. `Error`s below the watermark remain.
    Handles
    must be popped in stack order. An out-of-order pop reaches the
    non-reentrant error floor; a null handle does nothing.
*/
void Error.pop(ErrorHandler handle) {
  if (!handle) return;
  ErrorThreadState state = _thread();
  if (state.handler_top != handle)
    _floor(<invariant>, "Error.pop out of order");
  _truncate(handle.watermark);
  state.handler_top = handle.prev;
  _handler_free(handle);
}

/** Opens the `Error` state owned by one `Context`.
    Policy and bound changes become local overlays; handlers and accumulated
    records are restored by `Error.context_close`. The returned opaque token is
    allocated in the current `Scope`, which must remain live through the
    matching
    close. An unavailable `Error` runtime returns NULL.
    Raises: `<alloc-fail>` when the overlay cannot be allocated.
*/
void *Error.context_open(void) {
  if (!Error.ready()) return NULL;
  ErrorThreadState thread = _thread();
  ErrorContextState state = Scope.malloc(sizeof(struct ErrorContextState));
  state.prev = thread.context_top;
  state.policy = %{};
  state.bound = Error.bound();
  state.handler_depth = Error.handler_depth();
  state.stack_height = Error.count();
  thread.context_top = state;
  return state;
}

/** Closes one `Context` `Error` overlay.
    An exception unwinding out of the `Context` keeps its records for the outer
    handler; an ordinary close discards records accumulated inside it. In both
    cases handlers pushed inside the `Context` are reclaimed. Tokens must close
    in nesting order; an out-of-order close reaches the raw error floor. A null
    token does nothing and a closed token is invalid.
*/
void Error.context_close(void *token, int preserve_records) {
  ErrorContextState state = token;
  if (!state) return;
  ErrorThreadState thread = _thread();
  if (thread.context_top != state)
    _floor(<invariant>, "Error Context close out of order");
  _unwind_to(
    thread, _handler_at_depth(thread, state.handler_depth),
    !preserve_records);
  if (!preserve_records) _truncate(state.stack_height);
  thread.context_top = state.prev;
}

/* Move the selected slice off the public record stack without destroying its
   private regions. Capture values were copied into the newest record's region,
   so the detached catch handle owns both them and the selected Error until
   `_handler_free` destroys `retained`. Records are stored newest first here;
   their order is immaterial because the catch exposes only captures. A second
   transfer can select the same handle before its landing runs, as when a
   `finally` raises while carrying an Error; the abandoned selection is
   destroyed here because the replacement transfer owns the handle. */
static void _catch_retain(ErrorHandler handle) {
  int pushed = _scope_push(
    <alloc-fail>, "could not enter error scope for retained catch records");
  _retained_destroy(handle.retained);
  handle.retained = Block.new(sizeof(ErrorRecord));
  while (Error.count() > handle.watermark) {
    ErrorRecord record = *_record_at(Error.count() - 1);
    handle.retained.push(&record);
    _thread().stack.pop();
  }
  if (pushed) Scope.pop();
}

static void _catch_commit_captures(
  ErrorHandler handle, ErrorRecord *record, MatchCaptureLayout layout,
  MatchCaptureBuffer *captures) {
  if (!layout || !layout.binder_count) return;
  int pushed = _scope_push(
    <alloc-fail>, "could not enter error scope for catch captures");
  handle.capture_values = Block.new(sizeof(Var));
  handle.capture_values.append(NULL, layout.binder_count);
  Var *values = handle.capture_values.bytes;
  for (int i = 0; i < layout.binder_count; i++) {
    values[i] = void;
    if (!captures.has(i)) continue;
    values[i] = _copy_value(&record.region, captures.values[i]);
  }
  if (pushed) Scope.pop();
}

static Symbol _catch_match(ErrorHandler h) {
  if (Error.count() <= h.watermark) return <declined>;
  ErrorRecord *record = _record_at(Error.count() - 1);
  Symbol code = record.entry.car().list().cadr();
  List detail = record.entry.cadr().list().cadr();
  ErrorThreadState state = _thread();
  state.floor_only++;
  List projection = _cons(&record.region, code, detail);
  List.pool_retain_named("Error catch bindings");
  MatchPlan *plans = h.plans.bytes;
  for (int i = 0; i < h.patterns.len(); i++) {
    Var pattern = h.patterns[i];
    MatchPlan plan = plans[i];
    MatchCaptureLayout layout = plan ? plan.layout : NULL;
    Var *values = layout && layout.binder_count
                ? Scope.malloc(sizeof(Var) * layout.binder_count)
                : NULL;
    MatchCaptureBuffer captures = {
      values, 0, layout ? layout.binder_count : 0
    };
    int matched = pattern == <default> ? 1 :
      plan.status == MACHINE_PREPARED &&
      plan.execute_capture(projection, &captures, NULL) == 1;
    if (!matched) {
      if (values) Scope.free(values);
      continue;
    }
    _catch_commit_captures(h, record, layout, &captures);
    if (values) Scope.free(values);
    h.selected = i;
    List.pool_release();
    _catch_retain(h);
    state.floor_only--;
    return <unwind>;
  }
  List.pool_release();
  state.floor_only--;
  return <declined>;
}

/* Offers the newest record to each handler from innermost outward.
    A handler runs on the live frame, before any transfer, and sees the errors
    accrued since it was registered. `<handled>` consumes that slice and stops
    the search. `<declined>` continues outward and leaves the errors
    accumulated. `<fatal>` aborts. `<unwind>` is not available to an observing
    registration and is a programmer error here. Hiding the current handler
    before its callback makes a nested raise begin at the next outer handler;
    the saved full chain is restored after dispatch or at a transfer landing.
*/
static Symbol _dispatch(Symbol effective, int raised_at, int depth) {
  ErrorThreadState state = _thread();
  ErrorHandler saved = state.handler_top;
  state.dispatch_saved = saved;
  Symbol result = <declined>;
  for (ErrorHandler h = saved; h; h = h.prev) {
    state.handler_top = h.prev;
    Symbol disposition = <declined>;
    if (h.patterns) disposition = _catch_match(h);
    else {
      ErrorRegion view = { 0 };
      {
        defer _region_destroy(&view);
        state.floor_only++;
        view = _region_new();
        List slice = _view_since(&view, h.watermark);
        state.floor_only--;
        disposition = h.fn(slice, h.data);
      }
    }
    if (disposition == <unwind>) {
      if (h.patterns) {
        state.handler_top = saved;
        state.dispatch_saved = NULL;
        _leave();
        ExceptionFrame.unwind(h.target);
      }
      state.handler_top = saved;
      state.dispatch_saved = NULL;
      _leave();
      _floor(effective, "<unwind> from an observing registration");
    }
    if (disposition == <fatal>) {
      state.handler_top = saved;
      state.dispatch_saved = NULL;
      _leave();
      _floor(effective, "handler returned fatal");
    }
    if (disposition == <handled>) {
      _truncate(h.watermark);
      result = <handled>;
      break;
    }
  }
  state.handler_top = saved;
  state.dispatch_saved = NULL;
  _leave();

  if (_never_returns(effective))
    _floor(effective, "non-returning error was not caught");
  if (result != <declined>) return result;
  Symbol policy = Error.policy_get(effective);
  if (policy == <abort>)
    _floor(effective, "unhandled and policy is abort");
  if (policy == <log>) {
    if (!state.rendered[depth]) _report(effective);
    _truncate(raised_at);
  }
  else if (policy == <ignore>) _truncate(raised_at);
  return result;
}

static void _raise_enter(Symbol effective) {
  if (_thread().floor_only)
    _floor(effective, "raise while building error state");
  if (!_enter())
    _floor(effective, "raise re-entered or after shutdown");
  if (!Error.ready()) {
    _leave();
    _floor(effective, "raise before initialization");
  }
}

static Symbol _raise(
  const X2CErrorSite *site, Symbol code, List detail) {
  Symbol effective = code ? code : <invariant>;
  _raise_enter(effective);
  ErrorThreadState state = _thread();
  int raised_at = Error.count(), depth = state.depth;
  state.rendered[depth] = 0;
  _record(site, effective, detail);
  return _dispatch(effective, raised_at, depth);
}

/** Raises one cause with optional structured detail.
    This functional entry records and dispatches like the `raise` statement
    but has no source-location record. A handled resumable error
    returns `<handled>`; a collected or policy-consumed resumable error
    returns `<declined>`. Shared non-returning causes may transfer to a
    matching filtered catch but never return from this call.
    Detail is recursively restricted to null/`nil`, numeric values, enums,
    `Symbol`s/`Atom`s, `String`s, and `List`s of those values. An invalid
    dynamic
    detail, unhandled abort-policy error, unavailable runtime, or reentrant
    failure reaches the non-reentrant error floor.

    Prefer the `raise` statement in source so generated location detail is
    retained.
*/
Symbol Error.raise(Symbol code, List detail) => _raise(NULL, code, detail);

static int _chain_contains(ErrorHandler head, ErrorHandler wanted) {
  if (!wanted) return 1;
  for (ErrorHandler h = head; h; h = h.prev) if (h == wanted) return 1;
  return 0;
}

/** Reports whether the rich `Error` runtime can currently accept raises.
    This is per-thread state and is false before initialization and after
    shutdown.
*/
int Error.ready(void) => x2c_error_runtime_ready;
