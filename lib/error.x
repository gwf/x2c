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
    outward. Return `<handled>`, `<declined>`, or `<fatal>`; `<unwind>` is
    reserved for compiler-generated catches. Any other result behaves as
    `<declined>` and continues outward or to policy. The `List` and its
    contents expire on return.
*/
typedef Symbol (*ErrorHandlerFn)(List errors, Var data);

/** Selects the arm of a compiler-generated catch for the newest `Error`,
    `error` as `(CODE @DETAIL)`, at raise time. Returns the zero-based arm,
    or -1 when no arm matches. A selected arm stores its captures, borrowed
    from `error`, in `captures` in `Match` capture order and their number in
    `count`.
*/
typedef int (*ErrorCatchSelect)(List error, Var *captures, int *count);

/** Holds the process-lifetime plans of one compiler-generated filtered catch.
    `arms` is a zero-initialized static array of `arm_count` `Match` sites and
    `default_arm` is the first unpatterned arm, or -1. `state` and `fenced_arm`
    belong to `Error`; a site must be static storage that the first
    registration binds to its patterns. A site with `select` is static from
    the start, has no `arms`, and selects through that function instead.
*/
typedef struct ErrorCatchSite {
  MatchCaptureSite *arms;
  int default_arm, arm_count, state, fenced_arm;
  ErrorCatchSelect select;
} ErrorCatchSite;

/* A site is bound on its first registration: `static` when `Match` retains a
   plan for every arm, `transient` when some pattern is built at run time and
   each registration must prepare its own plans. A pending site's patterns are
   literals in compiler output, so binding promotes them out of any nested
   `Pool` first. One thread binds a site; a thread that raced it there finds
   the site bound and ignores the patterns it built. */
#define ERROR_CATCH_PENDING 0
#define ERROR_CATCH_STATIC 1
#define ERROR_CATCH_TRANSIENT 2

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

$error.private.types();

/* One `Context`'s overlay: the policies and bound it sets, and the handler
   depth and record height its close returns to. */
static typedef struct ErrorContextState {
  struct ErrorContextState *prev, Map policy, int bound, handler_depth;
  int stack_height;
} *ErrorContextState;

/* The nested-handler probe reaches depth 2; two more levels are reserve for
   a rendering or allocation handler that itself must raise. */
#define ERROR_MAX_DEPTH 4

/* `handler_top` heads the registered handlers and `running_top` the detached
   catches whose arms run; during dispatch, `dispatch_saved` holds the
   complete chain and `dispatch_running` the handler offered the error. A
   raise reaches the floor while `floor_only` is nonzero, and
   `rendered[depth]` marks a dispatch whose error Logger rendered. */
static typedef struct ErrorThreadState {
  Scope scope, Block stack, Map policy, int shutdown_done;
  ErrorHandler handler_top, dispatch_saved, dispatch_running, running_top;
  int bound, ErrorContextState context_top, int depth, floor_only, rendered[5];
} *ErrorThreadState;

static threaded struct ErrorThreadState error_thread;

static ErrorThreadState _thread(void) {
  ErrorThreadState state = &error_thread;
  if (!state.bound) state.bound = ERROR_DEFAULT_BOUND;
  return state;
}

/* raising

   A raise enters dispatch, records the error, and offers it to the
   handlers. A zero code raises `<invariant>`. */

/* One raise in progress: its cause, the record count before it, and its
   dispatch depth. */
static typedef struct ErrorRaise {
  Symbol code, int raised_at, depth;
} ErrorRaise;

/** Raises one cause with optional structured detail.
    This functional entry records and dispatches like the `raise` statement
    but has no source-location record. A handled resumable error returns
    `<handled>`; a collected or policy-consumed resumable error returns
    `<declined>`. Shared non-returning causes may transfer to a matching
    filtered catch but never return from this call. Detail is recursively
    restricted to null/`nil`, numeric values, enums, `Symbol`s/`Atom`s,
    `String`s, and `List`s of those values. An invalid dynamic detail,
    unhandled abort-policy error, unavailable runtime, or reentrant failure
    reaches the non-reentrant error floor.

    Prefer the `raise` statement in source so generated location detail is
    retained.
*/
Symbol Error.raise(Symbol code, List detail) => _raise(NULL, code, detail);

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

/** Raises one compiler-generated error from native key-value arguments.
    `pair_count` controls the following alternating `Var` keys and values;
    `site` may be NULL. The runtime copies admissible values and preserves
    pair order. Resumable causes may return after handling or policy; shared
    non-returning causes may transfer to a filtered catch but never return
    here. Invalid detail or unavailable, reentrant, or failed `Error`
    machinery reaches the raw error floor.
*/
void x2c_error_raise_n(
  const X2CErrorSite *site, Symbol code, unsigned pair_count, ...) {
  ErrorRaise r = _raise_enter(code);
  va_list args;
  va_start(args, pair_count);
  _record_n(site, r.code, pair_count, args);
  va_end(args);
  r._dispatch();
}

static Symbol _raise(const X2CErrorSite *site, Symbol code, List detail) {
  ErrorRaise r = _raise_enter(code);
  _record(site, r.code, detail);
  return r._dispatch();
}

/* A raise reaches the floor while error state is being built, when dispatch
   is nested too deeply or shut down, and before initialization. */
static ErrorRaise _raise_enter(Symbol code) {
  Symbol effective = code ? code : <invariant>;
  ErrorThreadState state = _thread();
  if (state.floor_only) _floor(effective, "raise while building error state");
  if (!_enter()) _floor(effective, "raise re-entered or after shutdown");
  if (!Error.ready()) {
    _leave();
    _floor(effective, "raise before initialization");
  }
  ErrorRaise r = {effective, Error.count(), state.depth};
  state.rendered[r.depth] = 0;
  return r;
}

static int _enter(void) {
  ErrorThreadState state = _thread();
  if (state.shutdown_done || state.depth >= ERROR_MAX_DEPTH) return 0;
  state.depth++;
  return 1;
}

static void _leave(void) {
  ErrorThreadState state = _thread();
  if (state.depth > 0) state.depth--;
}

/** Returns the current nested error-dispatch depth.
    This is the nesting depth of error dispatch. `Error.count` returns the
    number of accumulated errors.
*/
int Error.depth(void) => _thread().depth;

/* records

   A record's entry has the shape of a Diagnostics entry,
   `((code C) (detail D) (location L))`, so a handler can match on it. Its
   detail is copied into the record's own region. */

static void _record(const X2CErrorSite *site, Symbol code, List detail) {
  if (Error.count() >= Error.bound())
    _floor(code, "error stack exceeded its bound");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorRecord record = { .region = _region_new() };
  detail = record.region._copy_value(detail);
  record.entry = record.region._entry(site, code, detail);
  state.stack.push(&record);
  state.floor_only--;
}

static void _record_n(
  const X2CErrorSite *site, Symbol code, unsigned pair_count, va_list args) {
  if (Error.count() >= Error.bound())
    _floor(code, "error stack exceeded its bound");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorRecord record = { .region = _region_new() };
  List detail = record.region._counted_detail(code, pair_count, args);
  record.entry = record.region._entry(site, code, detail);
  state.stack.push(&record);
  state.floor_only--;
}

static typedef struct ErrorPair { Var key, value; } ErrorPair;

/* Copies `count` key-value arguments into `region` as a detail List in
   argument order. The pairs wait in a Block because the List is built from
   its end. */
static List ErrorRegion._counted_detail(
  ErrorRegion *region, Symbol code, unsigned count, va_list args) {
  int pushed = _scope_push(
    code, "could not enter error scope for counted detail");
  Block pairs = Block.new(sizeof(ErrorPair));
  for (unsigned i = 0; i < count; i++) {
    ErrorPair pair = { .key = region._copy_value(va_arg(args, Var)) };
    pair.value = region._copy_value(va_arg(args, Var));
    pairs.push(&pair);
  }
  ErrorPair *items = pairs.bytes;
  List detail = NULL;
  for (int i = (int) count - 1; i >= 0; i--)
    detail = region._field(items[i].key, items[i].value, detail);
  pairs.free();
  if (pushed) Scope.pop();
  return detail;
}

static List ErrorRegion._entry(
  ErrorRegion *region, const X2CErrorSite *site, Symbol code, List detail) {
  List location = region._location(site), entry = NULL;
  entry = region._field(<location>, location, entry);
  entry = region._field(<detail>, detail, entry);
  entry = region._field(<code>, code, entry);
  return entry;
}

static List ErrorRegion._location(ErrorRegion *e, const X2CErrorSite *site) {
  if (!site) return NULL;
  String file = e._site_text(site.file);
  String function = e._site_text(site.function);
  List location = e._field(<function>, function, NULL);
  location = e._field(<line>, site.line, location);
  return e._field(<file>, file, location);
}

static String ErrorRegion._site_text(ErrorRegion *region, const char *text) {
  if (!text) text = "<unknown>";
  return String.new_in(region.pool, text, strlen(text));
}

static List ErrorRegion._field(
  ErrorRegion *region, Var key, Var value, List tail) =>
  region._cons(region._pair(key, value), tail);

static List ErrorRegion._pair(ErrorRegion *region, Var key, Var value) =>
  region._cons(key, region._cons(value, NULL));

static List ErrorRegion._cons(ErrorRegion *region, Var head, List tail) =>
  List.cons_in(region.pool, head, tail);

static ErrorRecord *_record_at(int index) {
  ErrorRecord *records = _thread().stack.bytes;
  return &records[index];
}

static void _truncate(int mark) {
  if (!Error.ready() || mark < 0) return;
  while (Error.count() > mark) {
    ErrorRecord *record = _record_at(Error.count() - 1);
    record.region._destroy();
    _thread().stack.pop();
  }
}

// admissible values

/* A NULL region requests an ordinary snapshot: construct in the active
   canonical pool, then promote that same object. An explicit region copies
   into its pool instead. Both policies traverse the same immutable shape. */
static Var ErrorRegion._copy_value(ErrorRegion *region, Var value) {
  if (value is void)
    _floor(
      <bad-types>, region ? "void is not an admissible error detail"
                          : "void is not an admissible error snapshot");
  if (value.is_null() || value.is_nil() || value is <symbol>) return value;
  if (value.is_wide()) return region._copy_wide(value);
  if (value.is_integer() || value.is_floating()) return value;
  if (value is <string> || value is <lsym>) return region._copy_text(value);
  if (value is <list>) return region._copy_list(value);
  _floor(
    <bad-types>, region ? "error detail contains an identity-bearing value"
                        : "error snapshot contains an identity-bearing value");
}

static Var ErrorRegion._copy_wide(ErrorRegion *region, Var value) =>
  region ? _clone_in(&region.values, value) : _snapshot_wide(value);

/* A wide box belongs to the outermost `Scope` of the caller's active slot, so
   a nested release cannot reclaim it. An empty slot has no such `Scope` yet;
   allocate through the slot itself, which then owns the `Scope` the box
   creates. */
static Var _snapshot_wide(Var v) {
  Scope owner = *Scope.top();
  if (!owner) return v.clone_wide();
  while (owner.down) owner = owner.down;
  return _clone_in(&owner, v);
}

static Var _clone_in(Scope *owner, Var v) {
  Scope.push(owner);
  Var copy = v.clone_wide();
  Scope.pop();
  return copy;
}

static Var ErrorRegion._copy_text(ErrorRegion *region, Var value) {
  String source = value is <lsym> ? value.str() : value.string();
  if (!region) return _snapshot_text(value, source);
  String owned = String.new_in(region.pool, source, source.len());
  return value is <lsym> ? Var.new(<lsym>, owned) : owned;
}

/* A snapshot promotes its copy, and an Atom's spelling is interned first. */
static Var _snapshot_text(Var value, String source) {
  String owned = String.new_len(source, source.len());
  if (value is not <lsym>) {
    String.try_own(owned);
    return owned;
  }
  Atom atom = Atom.intern(owned);
  if (atom is <lsym>) String.try_own(atom.str());
  return atom;
}

static List ErrorRegion._copy_list(ErrorRegion *region, List source) {
  Var head = region._copy_value(source.car());
  List tail = region._copy_value(source.cdr());
  if (region) return region._cons(head, tail);
  List owned = cons(head, tail);
  List.try_own(owned);
  return owned;
}

static ErrorRegion _region_new(void) {
  ErrorRegion region = { 0 };
  region.values = Scope.new_named("Error record values");
  region.pool = Pool.retain_named(NULL, "Error record canonical values");
  return region;
}

/* Release canonical values before their borrowed wide scalar boxes.
   No region value survives this operation. */
static void ErrorRegion._destroy(ErrorRegion *region) {
  if (region.pool) region.pool = Pool.release(region.pool);
  if (region.values) {
    Scope.destroy(region.values);
    region.values = NULL;
  }
}

/* dispatch

   A handler runs on the live frame, before any transfer, and sees the errors
   accrued since it was registered. Dispatch hides each handler before
   offering it the error, so a nested raise begins at the next outer handler;
   the saved full chain is restored after dispatch or at a transfer landing. */

/* Offers the newest record to the handlers, then restores the chain. An
   error every handler declined follows its cause's policy, and a shared
   non-returning cause that no catch took reaches the floor. */
static Symbol ErrorRaise._dispatch(ErrorRaise r) {
  ErrorThreadState state = _thread();
  ErrorHandler saved = state.handler_top, outer = state.dispatch_saved;
  ErrorHandler outer_running = state.dispatch_running;
  /* Only the outermost dispatch records the complete chain. A handler that
     raises starts a nested dispatch from its own hidden position, and a
     transfer out of that nested dispatch must still hand every registration
     back to the cleanup that runs between the raise and the landing. */
  if (!outer) state.dispatch_saved = saved;
  Symbol disposition = state._offer(saved, r.code);
  state.handler_top = saved;
  state.dispatch_saved = outer;
  state.dispatch_running = outer_running;
  _leave();
  if (_never_returns(r.code))
    _floor(r.code, "non-returning error was not caught");
  if (disposition == <declined>) state._apply_policy(r);
  return disposition;
}

/* Offers the error to each handler from `h` outward. `<handled>` consumes
   that handler's slice and stops the search; `<declined>` continues outward
   and leaves the errors accumulated. */
static Symbol ErrorThreadState._offer(
  ErrorThreadState e, ErrorHandler h, Symbol code) {
  for (; h; h = h.prev) {
    e.dispatch_running = h;
    e.handler_top = h.prev;
    Symbol disposition = h.site ? h._catch_match() : e._observe(h);
    if (disposition == <unwind> || disposition == <fatal>)
      e._transfer(h, code, disposition);
    if (disposition == <handled>) {
      _truncate(h.watermark);
      return <handled>;
    }
  }
  return <declined>;
}

/* The view belongs to the handler, not to this frame: `exit()` from the
   callback abandons the frame, and shutdown reclaims the handler. */
static Symbol ErrorThreadState._observe(ErrorThreadState e, ErrorHandler h) {
  defer h.view._destroy();
  e.floor_only++;
  h.view = _region_new();
  List slice = h.view._view_since(h.watermark);
  e.floor_only--;
  return h.fn(slice, h.data);
}

/* Hands the complete chain back to the cleanup that runs before a landing,
   then lands at the selected catch's frame. `<fatal>` aborts, and `<unwind>`
   is not available to an observing registration, so both reach the floor. */
static void ErrorThreadState._transfer(
  ErrorThreadState state, ErrorHandler h, Symbol code, Symbol disposition) {
  state.handler_top = state.dispatch_saved;
  state.dispatch_saved = state.dispatch_running = NULL;
  _leave();
  if (disposition == <unwind> && h.site) ExceptionFrame.unwind(h.target);
  _floor(
    code, disposition == <fatal> ? "handler returned fatal"
        : "<unwind> from an observing registration");
}

/* `<log>` reports an error unless Logger rendered it, and both `<log>` and
   `<ignore>` drop the records the raise added; `<collect>` keeps them. */
static void ErrorThreadState._apply_policy(ErrorThreadState e, ErrorRaise r) {
  Symbol policy = Error.policy_get(r.code);
  if (policy == <abort>) _floor(r.code, "unhandled and policy is abort");
  if (policy == <log>) {
    if (!e.rendered[r.depth]) _report(r.code);
    _truncate(r.raised_at);
  }
  else if (policy == <ignore>) _truncate(r.raised_at);
}

/* The `<log>` fallback when Logger did not render the error. */
static void _report(Symbol code) {
  char spelling[SYMBOL_MAX_5BIT + 1] = { 0 };
  code.decode(spelling);
  fprintf(stderr, "x2c error: <%s>\n", spelling);
  fflush(stderr);
}

/** Marks the current nested error dispatch as already rendered by `Logger`.
    This suppresses only `Error`'s fallback report for a `<log>` policy.
    Calling outside dispatch has no effect.
*/
void Error.note_rendered(void) {
  ErrorThreadState state = _thread();
  if (state.depth > 0 && state.depth <= ERROR_MAX_DEPTH)
    state.rendered[state.depth] = 1;
}

/* catch selection

   A transferring catch selects the first arm whose pattern matches the
   newest record's `(code @detail)`. The selected arm's captures and the
   records above the watermark then belong to the handle. */

static Symbol ErrorHandler._catch_match(ErrorHandler h) {
  if (Error.count() <= h.watermark) return <declined>;
  ErrorRecord *record = _record_at(Error.count() - 1);
  Symbol code = record.entry.car().list().cadr();
  List detail = record.entry.cadr().list().cadr();
  ErrorThreadState state = _thread();
  state.floor_only++;
  List projection = record.region._cons(code, detail);
  Pool.open_named("Error catch bindings");
  int selected = h._catch_select(record, projection);
  Pool.close();
  if (selected) h._catch_retain();
  state.floor_only--;
  return selected ? <unwind> : <declined>;
}

static int ErrorHandler._catch_select(
  ErrorHandler h, ErrorRecord *record, List projection) {
  if (h.site.select) return h._catch_selected(record, projection);
  for (int i = 0; i < h.site.arm_count; i++)
    if (h._catch_arm(record, projection, i)) {
      h.selected = i;
      return 1;
    }
  return 0;
}

/* A site's selector picks the arm and its captures in one call. */
static int ErrorHandler._catch_selected(
  ErrorHandler h, ErrorRecord *record, List projection) {
  Var values[MACHINE_BINDER_MAX];
  int count = 0, arm = h.site.select(projection, values, &count);
  if (arm < 0) return 0;
  MatchCaptureBuffer captures = {values, ~0UL, count};
  h._commit_captures(record, count, &captures);
  h.selected = arm;
  return 1;
}

/* Tries arm `i` and, when it matches, copies its captures into the record's
   region. The default arm matches without a plan. */
static int ErrorHandler._catch_arm(
  ErrorHandler h, ErrorRecord *record, List projection, int i) {
  MatchPlan plan = h._arm_plan(i);
  MatchCaptureLayout layout = plan ? plan.layout : NULL;
  int binders = layout ? layout.binder_count : 0;
  Var *values = binders ? Scope.malloc(sizeof(Var) * binders) : NULL;
  MatchCaptureBuffer captures = {values, 0, binders};
  int matched = i == h.site.default_arm ||
    (plan.status == MACHINE_PREPARED &&
     plan.execute_capture(projection, captures, NULL) == 1);
  if (matched) h._commit_captures(record, binders, &captures);
  if (values) Scope.free(values);
  return matched;
}

/* A transient site's registration holds its own plans; a static site
   retains one plan per arm. */
static MatchPlan ErrorHandler._arm_plan(ErrorHandler h, int i) {
  if (i == h.site.default_arm) return NULL;
  MatchPlan *plans = h.plans != NULL ? h.plans.bytes : NULL;
  return plans ? plans[i] : h.site.arms[i].plan;
}

static void ErrorHandler._commit_captures(
  ErrorHandler handle, ErrorRecord *record, int count,
  MatchCaptureBuffer *captures) {
  if (handle.capture_values != NULL) {
    handle.capture_values.free();
    handle.capture_values = NULL;
  }
  if (!count) return;
  int pushed = _scope_push(
    <alloc-fail>, "could not enter error scope for catch captures");
  handle.capture_values = Block.new(sizeof(Var));
  handle.capture_values.append(NULL, count);
  Var *values = handle.capture_values.bytes;
  for (int i = 0; i < count; i++) {
    values[i] = void;
    if (captures.has(i))
      values[i] = record.region._copy_value(captures.values[i]);
  }
  if (pushed) Scope.pop();
}

/* Move the selected slice off the public record stack without destroying its
   private regions. Capture values were copied into the newest record's region,
   so the detached catch handle owns both them and the selected Error until
   `ErrorHandler._free` destroys `retained`. Records are stored newest first;
   their order is immaterial because the catch exposes only captures. A second
   transfer can select the same handle before its landing runs, as when a
   `finally` raises while carrying an Error; the abandoned selection is
   destroyed here because the replacement transfer owns the handle. */
static void ErrorHandler._catch_retain(ErrorHandler handle) {
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

static void _retained_destroy(Block retained) {
  if (retained == NULL) return;
  ErrorRecord *records = retained.bytes;
  for (size_t i = 0; i < retained.length; i++)
    records[i].region._destroy();
  retained.free();
}

/* policy

   A policy decides what happens to an error every handler declined. A
   `Context` overlays its own policies and bound on the thread's. */

/* This is the same shared cause table that drives compiler unreachable
   emission. Error locks every listed policy to abort: observing handlers may
   inspect but cannot consume one, while a matching compiler catch transfers
   control without returning to its raising call. */
static const SymbolSet error_nonreturning_causes =
  $error.nonreturning.causes();

static int _never_returns(Symbol code) => code in error_nonreturning_causes;

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
    raise %(bad-arg (operation "Error.policy_set") (dispositio $disposition));
  if (_never_returns(code) && disposition != <abort>)
    raise %(bad-arg (operation "Error.policy_set") (code $code)
                   (dispositio $disposition));
  ErrorThreadState state = _thread();
  state.floor_only++;
  int pushed = _scope_push(
    code, "could not enter error scope while setting policy");
  Map policy = state.context_top ? state.context_top.policy : state.policy;
  policy[code] = disposition;
  if (pushed) Scope.pop();
  state.floor_only--;
}

/** Returns the default disposition for `code`.
    Unknown codes and an unavailable `Error` runtime default to `<abort>`.
*/
Symbol Error.policy_get(Symbol code) {
  if (!Error.ready()) return <abort>;
  ErrorThreadState state = _thread();
  for (ErrorContextState at = state.context_top; at; at = at.prev) {
    Var found = at.policy[code];
    if (found is not void) return found;
  }
  Var found = state.policy[code];
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

/* A capture holds only `Symbol` pairs and its own allocation, so it crosses a
   thread boundary without borrowing `Error`, `Scope`, or `Pool` storage. The
   pairs follow the header in the same block. */
static typedef struct ErrorPolicyCapture {
  int count, Symbol *pairs;
} *ErrorPolicyCapture;

/** Captures the calling thread's `Error` policy for another thread to adopt.
    Policy is per-thread state, so a worker starts with only the shared
    non-returning causes locked to `<abort>`; a capture carries the starting
    thread's dispositions across. `Error.policy_adopt` consumes the capture and
    `Error.policy_release` discards one that no thread adopted. An unavailable
    `Error` runtime captures nothing and answers NULL.
    Raises: `<alloc-fail>` when the capture cannot be allocated.
*/
void *Error.policy_capture(void) {
  if (!Error.ready()) return NULL;
  ErrorThreadState state = _thread();
  int capacity = state.policy.len();
  for (ErrorContextState at = state.context_top; at; at = at.prev)
    capacity += at.policy.len();
  capacity *= 2;
  ErrorPolicyCapture capture = malloc(
    sizeof(struct ErrorPolicyCapture) + (size_t) capacity * sizeof(Symbol));
  if (!capture) raise %(alloc-fail (operation "Error.policy_capture"));
  capture.pairs = (Symbol *) (capture + 1);
  int written = _fill_pairs(state.policy, capture.pairs, 0, capacity);
  capture.count =
    _fill_contexts(state.context_top, capture.pairs, written, capacity);
  return capture;
}

/* Outermost context first, so replaying the pairs in order reproduces the
   overlays an inner context placed over an outer one. */
static int _fill_contexts(
  ErrorContextState context, Symbol *pairs, int at, int capacity) {
  if (!context) return at;
  at = _fill_contexts(context.prev, pairs, at, capacity);
  return _fill_pairs(context.policy, pairs, at, capacity);
}

static int _fill_pairs(Map policy, Symbol *pairs, int at, int capacity) {
  unsigned cursor = 0;
  Var key = void, value = void;
  while (policy.try_next(cursor, key, value)) {
    if (at + 2 > capacity) break;
    pairs[at++] = key;
    pairs[at++] = value;
  }
  return at;
}

/** Adopts a policy capture on the calling thread and releases it.
    Each captured code takes its captured disposition; codes the capture does
    not name keep the disposition this thread already has. A NULL capture, or
    one adopted while `Error` is unavailable, is released without effect.
    Failure to update `Error`-owned storage reaches the non-reentrant error
    floor.
*/
void Error.policy_adopt(void *capture) {
  ErrorPolicyCapture adopted = capture;
  if (!adopted) return;
  if (Error.ready()) {
    ErrorThreadState state = _thread();
    Map policy = state.context_top ? state.context_top.policy : state.policy;
    state.floor_only++;
    int pushed = _scope_push(
      <invariant>, "could not enter error scope while adopting policy");
    for (int i = 0; i + 1 < adopted.count; i += 2)
      policy[adopted.pairs[i]] = adopted.pairs[i + 1];
    if (pushed) Scope.pop();
    state.floor_only--;
  }
  free(adopted);
}

/** Releases a policy capture that no thread adopted. A NULL capture is
    accepted and does nothing.
*/
void Error.policy_release(void *capture) => free(capture);

/* the handler stack

   The newest registration is the innermost handler. A handler's watermark
   is the record count at its registration, so the records above it are the
   errors raised since. */

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
  ErrorHandler h = _handler_new(fn, data);
  _thread().handler_top = h;
  return h;
}

static ErrorHandler _handler_new(ErrorHandlerFn fn, Var data) {
  ErrorThreadState state = _thread();
  ErrorHandler h = Scope.malloc_in(&state.scope, sizeof(struct ErrorHandler));
  *h = (struct ErrorHandler) {
    .prev = state.handler_top, .fn = fn, .data = data,
    .watermark = Error.count(), .selected = -1};
  return h;
}

/** Closes the observing handler on top of the handler stack.
    Closing truncates and reclaims every error above the handler's registration
    watermark, then unregisters it. `Error`s below the watermark remain.
    Handles must be popped in stack order. An out-of-order pop reaches the
    non-reentrant error floor; a null handle does nothing.
*/
void Error.pop(ErrorHandler handle) {
  if (!handle) return;
  ErrorThreadState state = _thread();
  if (state.handler_top != handle)
    _floor(<invariant>, "Error.pop out of order");
  _truncate(handle.watermark);
  state.handler_top = handle.prev;
  handle._free();
}

static void ErrorHandler._free(ErrorHandler handle) {
  if (!handle) return;
  // a per-call site has no static storage and belongs to this handler
  if (handle.site && !handle.site.arms && !handle.site.select)
    Scope.free(handle.site);
  _plans_free(handle.plans);
  if (handle.capture_values != NULL) handle.capture_values.free();
  _retained_destroy(handle.retained);
  handle.view._destroy();
  Scope.free(handle);
}

static void _plans_free(Block plans) {
  if (plans == NULL) return;
  MatchPlan *items = plans.bytes;
  for (size_t i = 0; i < plans.length; i++) items[i].free();
  plans.free();
}

/* Pops handlers down to `stop`, reclaiming each one. `truncate` also discards
   the records above every popped handler's watermark; a Context closed by an
   unwinding exception keeps those for its outer handler and is the one caller
   that passes zero. */
static void ErrorThreadState._unwind_to(
  ErrorThreadState state, ErrorHandler stop, int truncate) {
  while (state.handler_top && state.handler_top != stop) {
    ErrorHandler removed = state.handler_top;
    state.handler_top = removed.prev;
    if (truncate) _truncate(removed.watermark);
    removed._free();
  }
}

/* Returns the handler that leaves exactly `depth` registered, or the current
   head when the stack is already that shallow. The height is measured once
   here so an unwind does not re-measure it per cleanup record. */
static ErrorHandler ErrorThreadState._handler_at_depth(
  ErrorThreadState state, int depth) {
  ErrorHandler stop = state.handler_top;
  for (int height = Error.handler_depth(); height > depth && stop; height--)
    stop = stop.prev;
  return stop;
}

static int _chain_contains(ErrorHandler head, ErrorHandler wanted) {
  if (!wanted) return 1;
  for (ErrorHandler h = head; h; h = h.prev) if (h == wanted) return 1;
  return 0;
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

/* transferring catches

   A compiler-generated `try` registers a transferring catch through the
   static site of its arms, and the first registration binds the site. */

/** Registers one compiler-generated transferring catch through its site.
    `target` names the `ExceptionFrame` that the caller pushes immediately
    afterward and `site` is the static site of this `try`, whose `patterns`
    are read in source order. A pending site reads `patterns`; a bound static
    site ignores them, so a caller may pass anything once
    `x2c_error_catch_site_pending` answers 0. The first registration of a
    pending site promotes its patterns, which are literals in compiler output,
    to process lifetime and binds them there when it can. A transient
    registration borrows its patterns, and they and the target frame must
    outlive the registration.
    A null target or site, a zero arm count, or an unavailable `Error` runtime
    reaches the raw error floor.
    Raises: `<alloc-fail>` when registration or fence-detail storage cannot be
    allocated, or `<size-limit>` when an arm's pattern crosses a `Match`
    lowering fence. A fenced arm can never be selected. The registration is
    reclaimed and the error reaches the enclosing handler; the caller's own
    frame is not yet pushed, so it never sees its own failure.
*/
ErrorHandler x2c_error_catch_site_push(
  void *target, ErrorCatchSite *site, Var *patterns) {
  if (!Error.ready() || !target || !site || !site.arm_count)
    _floor(<invariant>, "could not register transferring catch");
  ErrorThreadState state = _thread();
  state.floor_only++;
  ErrorHandler h = _handler_new(NULL, void);
  h.site = site;
  h.target = target;
  int arm = -1;
  const char *fenced = h._prepare_arms(patterns, arm);
  state.floor_only--;
  /* Report the fence here, where the unusable arm can be named. Reporting it
     from dispatch would re-enter the raise path that is already answering
     one error. */
  if (fenced) {
    h._free();
    String fence = String.new(fenced);
    raise %(size-limit (operation "catch") (arm $arm) (fence $fence));
  }
  state.handler_top = h;
  return h;
}

/* Binds a pending site, then returns why the first fenced arm this
   registration can reach is unusable, or NULL. A transient site prepares
   its plans for this registration alone. */
static const char *ErrorHandler._prepare_arms(
  ErrorHandler h, Var *patterns, int &arm) {
  ErrorCatchSite *site = h.site;
  if (site._state() == ERROR_CATCH_PENDING) site._bind(patterns);
  if (site._state() == ERROR_CATCH_TRANSIENT)
    return h._prepare_plans(patterns, arm);
  if (site.fenced_arm < 0) return NULL;
  arm = site.fenced_arm;
  return site.arms[arm].plan.reason;
}

static int ErrorCatchSite._state(ErrorCatchSite *site) =>
  __atomic_load_n(&site.state, __ATOMIC_ACQUIRE);

static void ErrorCatchSite._bind(ErrorCatchSite *site, Var *patterns) {
  _site_lock();
  // promotion and preparation allocate, and a failure never returns here
  defer _site_unlock();
  if (site._state() != ERROR_CATCH_PENDING) return;
  int retainable = 1;
  for (int i = 0; retainable && i < site.arm_count; i++)
    if (i != site.default_arm)
      retainable = List.try_own(patterns[i]) &&
                   x2c_match_pattern_retainable(patterns[i]);
  if (retainable)
    for (int i = 0; i < site.arm_count; i++) {
      if (i == site.default_arm) continue;
      MatchPlan plan = x2c_match_site_prepare(&site.arms[i], patterns[i]);
      if (plan.status == MACHINE_INELIGIBLE && site.fenced_arm < 0)
        site.fenced_arm = i;
    }
  __atomic_store_n(
    &site.state, retainable ? ERROR_CATCH_STATIC : ERROR_CATCH_TRANSIENT,
    __ATOMIC_RELEASE);
}

/* The mutex is recursive: an `<alloc-fail>` observer that registers another
   pending site while a bind holds it must not deadlock. */
static pthread_mutex_t catch_site_mutex;
static pthread_once_t catch_site_mutex_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

static void _site_mutex_initialize(void) =>
  Mutex.recursive_initialize(
    &catch_site_mutex, "Error: could not initialize catch site mutex");

static void _site_lock(void) =>
  Mutex.recursive_lock(
    &catch_site_mutex, &catch_site_mutex_once, _site_mutex_initialize,
    "Error: could not lock catch site");

static void _site_unlock(void) =>
  Mutex.recursive_unlock(
    &catch_site_mutex, "Error: could not unlock catch site");

/* Prepares one plan per arm for a registration of a transient site. */
static const char *ErrorHandler._prepare_plans(
  ErrorHandler h, Var *patterns, int &fenced_arm) {
  ErrorCatchSite *site = h.site;
  const char *fenced = NULL;
  int pushed = _scope_push(
    <alloc-fail>, "could not enter error scope for catch patterns");
  h.plans = Block.new(sizeof(MatchPlan));
  for (int i = 0; i < site.arm_count; i++) {
    MatchPlan plan = i == site.default_arm || patterns[i] == <default>
                   ? NULL : MatchPlan.prepare(patterns[i]);
    h.plans.push(&plan);
    if (plan && plan.status == MACHINE_INELIGIBLE && !fenced) {
      fenced = plan.reason;
      fenced_arm = i;
    }
  }
  if (pushed) Scope.pop();
  return fenced;
}

/** Registers one transferring catch from patterns supplied per call.
    A hand-written caller that has no static site uses this form; `arm_count`
    `List` pattern `Var`s follow in source order, and one plan per arm is
    prepared for this registration alone. Results and failures follow
    `x2c_error_catch_site_push`.
*/
ErrorHandler x2c_error_catch_push(void *target, unsigned arm_count, ...) {
  if (!Error.ready() || !arm_count)
    _floor(<invariant>, "could not register transferring catch");
  ErrorThreadState state = _thread();
  ErrorCatchSite *site = Scope.malloc_in(
    &state.scope, sizeof(ErrorCatchSite) + sizeof(Var) * arm_count);
  Var *patterns = (void *) (site + 1);
  *site = (ErrorCatchSite) {
    NULL, -1, (int) arm_count, ERROR_CATCH_TRANSIENT, -1};
  va_list args;
  va_start(args, arm_count);
  for (unsigned i = 0; i < arm_count; i++) {
    patterns[i] = va_arg(args, Var);
    if (patterns[i] == <default> && site.default_arm < 0)
      site.default_arm = (int) i;
  }
  va_end(args);
  return x2c_error_catch_site_push(target, site, patterns);
}

/** Reports whether one catch site still needs its patterns at registration.
    A bound static site answers 0, so its caller can skip constructing them.
*/
int x2c_error_catch_site_pending(ErrorCatchSite *site) =>
  !site || site._state() != ERROR_CATCH_STATIC;

// running arms

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

/** Unregisters the top transferring catch before its arm runs.
    The handler stack then holds only registrations that can still be
    selected, so the arm may raise outward without matching itself and may
    close handlers the `try` was nested inside. The handle moves to the
    thread's chain of running arms, which owns the retained `Error` and
    captures the arm still reads until `x2c_error_catch_close`; `Error`
    shutdown walks that chain, so an `exit()` from inside an arm still
    reclaims them. Repeated detach and a null handle do nothing. Detaching out
    of stack order reaches the raw error floor.
*/
void x2c_error_catch_detach(ErrorHandler handle) {
  if (!handle || handle.detached) return;
  ErrorThreadState state = _thread();
  if (state.handler_top != handle)
    _floor(<invariant>, "transferring catch detach out of order");
  state.handler_top = handle.prev;
  handle.detached = 1;
  handle.running = state.running_top;
  state.running_top = handle;
}

/** Closes and invalidates a transferring-catch handle.
    The handle releases its plans, captures, and retained error records. A
    still-registered handle also leaves the handler stack and truncates
    records above its registration watermark; a detached one leaves the chain
    of running arms instead. Handles must close in stack order on whichever
    chain holds them; violating that order reaches the raw error floor. A null
    handle does nothing.
*/
void x2c_error_catch_close(ErrorHandler handle) {
  if (!handle) return;
  ErrorThreadState state = _thread();
  if (handle.detached) {
    if (state.running_top != handle)
      _floor(<invariant>, "transferring catch close out of order");
    state.running_top = handle.running;
  }
  else {
    if (state.handler_top != handle)
      _floor(<invariant>, "transferring catch close out of order");
    _truncate(handle.watermark);
    state.handler_top = handle.prev;
  }
  handle._free();
}

/* frames and contexts

   An exception frame and a `Context` note the handler and record heights
   when they open and restore them when they leave. */

/** Returns the handler head retained for the current `Error` transfer.
    During handler dispatch this is the head saved by the outermost dispatch,
    even though the running callbacks are temporarily hidden from nested
    raises. Exception frames store the opaque result as their landing
    watermark.
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
  if (_chain_contains(saved, state.handler_top)) state.handler_top = saved;
  state.dispatch_saved = state.dispatch_running = NULL;
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
  if (_chain_contains(state.handler_top, saved)) state._unwind_to(saved, 1);
  _truncate(stack_height);
}

/** Discards handler and record growth after one cleanup callback.
    Registrations and records created by that callback are reclaimed toward
    the saved heights before the interrupted unwind continues. State the
    callback itself removed is not reconstructed.
*/
void Error.restore(int handler_depth, int stack_height) {
  ErrorThreadState state = _thread();
  state._unwind_to(state._handler_at_depth(handler_depth), 1);
  _truncate(stack_height);
}

/** Opens the `Error` state owned by one `Context`.
    Policy and bound changes become local overlays; handlers and accumulated
    records are restored by `Error.context_close`. The returned opaque token is
    allocated in the current `Scope`, which must remain live through the
    matching close. An unavailable `Error` runtime returns NULL.
    Raises: `<alloc-fail>` when the overlay cannot be allocated.
*/
void *Error.context_open(void) {
  if (!Error.ready()) return NULL;
  ErrorThreadState state = _thread();
  ErrorContextState context = Scope.malloc(sizeof(struct ErrorContextState));
  *context = (struct ErrorContextState) {
    .prev = state.context_top, .policy = {}, .bound = Error.bound(),
    .handler_depth = Error.handler_depth(), .stack_height = Error.count()};
  state.context_top = context;
  return context;
}

/** Closes one `Context` `Error` overlay.
    An exception unwinding out of the `Context` keeps its records for the outer
    handler; an ordinary close discards records accumulated inside it. In both
    cases handlers pushed inside the `Context` are reclaimed. Tokens must close
    in nesting order; an out-of-order close reaches the raw error floor. A null
    token does nothing and a closed token is invalid.
*/
void Error.context_close(void *token, int preserve_records) {
  ErrorContextState context = token;
  if (!context) return;
  ErrorThreadState state = _thread();
  if (state.context_top != context)
    _floor(<invariant>, "Error Context close out of order");
  ErrorHandler stop = state._handler_at_depth(context.handler_depth);
  state._unwind_to(stop, !preserve_records);
  if (!preserve_records) _truncate(context.stack_height);
  state.context_top = context.prev;
}

/* accumulated errors

   A handler's view and a catch's bindings are borrowed. A snapshot copies
   errors or values into the caller's owners so they outlive their callback
   or arm. */

/** Returns the number of errors currently accumulated.
    Returns zero before `Error` initialization and after shutdown.
*/
int Error.count(void) => Error.ready() ? (int) _thread().stack.length : 0;

/** Captures the current error-stack position.
    Pass the result to `Error.since` to inspect only later errors.
*/
int Error.mark(void) => Error.count();

/** Returns the accumulated errors at and after `mark`, oldest first.
    Each entry has `code`, `detail`, and `location` fields. An invalid mark or
    an unavailable `Error` runtime returns `nil`. The snapshot enters the
    caller's outermost `Scope` and canonical pools and remains live until
    those owners are released. Failure to materialize it reaches the
    non-reentrant error floor.
*/
List Error.since(int mark) {
  if (!Error.ready() || mark < 0) return NULL;
  ErrorThreadState state = _thread();
  state.floor_only++;
  List out = ErrorRegion._view_since(NULL, mark);
  List.try_own(out);
  state.floor_only--;
  return out;
}

/* Copies errors oldest first, using an explicit region or active pools. */
static List ErrorRegion._view_since(ErrorRegion *region, int mark) {
  List out = NULL;
  for (int i = Error.count() - 1; i >= mark; i--) {
    ErrorRecord *record = _record_at(i);
    Var entry = region._copy_value(record.entry);
    out = region ? region._cons(entry, out) : cons(entry, out);
  }
  return out;
}

/** Copies errors at and after `mark` into explicit owners, oldest first.
    `String`s and `List`s are canonicalized through `pool`'s chain and remain
    live until their actual owning pool is released. Wide scalar boxes enter
    `*values`, whose possibly updated `Scope` head is written back, and remain
    live until that `Scope` is destroyed. An unavailable runtime or negative
    mark returns `nil`. `Null` owners or failures while copying reach the raw
    floor.
*/
List Error.since_in(int mark, Scope *values, Pool pool) {
  if (!Error.ready() || mark < 0) return NULL;
  ErrorRegion region = _owners(values, pool);
  ErrorThreadState state = _thread();
  state.floor_only++;
  List out = ErrorRegion._view_since(&region, mark);
  state.floor_only--;
  *values = region.values;
  return out;
}

static ErrorRegion _owners(Scope *values, Pool pool) {
  if (!values || !pool)
    _floor(<bad-arg>, "error snapshot requires explicit owners");
  return (ErrorRegion) { .values = *values, .pool = pool };
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
  Var copy = ErrorRegion._copy_value(NULL, value);
  state.floor_only--;
  return copy;
}

/** Copies one admissible error value into explicit runtime owners.
    `String`s and `List`s are canonicalized through `pool`'s chain and remain
    live until their actual owning pool is released. Wide scalar boxes enter
    `*values`, whose possibly updated `Scope` head is written back, and remain
    live until that `Scope` is destroyed. `Null` owners, invalid or
    identity-bearing values, and failures while copying reach the raw floor.
*/
Var Error.snapshot_in(Var value, Scope *values, Pool pool) {
  ErrorRegion region = _owners(values, pool);
  ErrorThreadState state = _thread();
  state.floor_only++;
  Var copy = ErrorRegion._copy_value(&region, value);
  state.floor_only--;
  *values = region.values;
  return copy;
}

/* the error floor

   The floor reports a failure that the rich error path cannot handle and
   aborts. It is reachable before initialization, after shutdown, and when
   raising has re-entered itself, so it allocates nothing and calls nothing
   that can. */

static void _floor(Symbol code, const char *why) {
  char spelling[SYMBOL_MAX_5BIT + 1] = { 0 };
  code.decode(spelling);
  fprintf(
    stderr, "x2c error floor: <%s>: %s\n", spelling, why ? why : "unknown");
  fflush(stderr);
  abort();
}

/* Pushes the thread's error scope unless it is already on top, and answers
   whether the caller must pop it. */
static int _scope_push(Symbol code, const char *message) {
  ErrorThreadState state = _thread();
  if (Scope.top() == &state.scope) return 0;
  Scope.push(&state.scope);
  if (Scope.top() != &state.scope) _floor(code, message);
  return 1;
}

// lifecycle

/** Initializes the current thread's `Error` runtime without lifecycle
    insertion. Repeated calls after successful initialization and calls after
    shutdown do nothing. Initialization owns a private `Scope`, record stack,
    and policy `Map`; failure before the `Error` runtime becomes ready
    reaches the raw error floor.
*/
void Error.initialize_raw(void) {
  ErrorThreadState state = _thread();
  if (state.scope || state.shutdown_done) return;
  state.scope = Scope.new_named("error");
  Scope.push(&state.scope);
  state.stack = Block.new(sizeof(ErrorRecord));
  state.policy = {};
  Scope.pop();
  x2c_error_runtime_ready = 1;
  foreach (Symbol code, error_nonreturning_causes)
    Error.policy_set(code, <abort>);
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
  state._reclaim_hidden();
  state._unwind_to(NULL, 1);
  _truncate(0);
  if (state.stack != NULL) {
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

/* Reclaims the registrations the handler stack no longer names. `exit()` can
   run shutdown from inside a handler callback, which dispatch has hidden
   along with every registration it already offered the error to, or from
   inside a catch arm, whose handle left the stack for the running chain.
   Dispatch hides exactly the span from its saved head through the handler
   whose callback is running, so both chains stay disjoint from the visible
   one and nothing is reclaimed twice. */
static void ErrorThreadState._reclaim_hidden(ErrorThreadState state) {
  ErrorHandler stop = state.dispatch_running;
  for (ErrorHandler h = stop ? state.dispatch_saved : NULL; h;) {
    ErrorHandler prev = h.prev;
    int last = h == stop;
    h._free();
    if (last) break;
    h = prev;
  }
  state.dispatch_saved = state.dispatch_running = NULL;
  while (state.running_top) {
    ErrorHandler running = state.running_top;
    state.running_top = running.running;
    running._free();
  }
}

/** Reports whether the rich `Error` runtime can currently accept raises.
    This is per-thread state and is false before initialization and after
    shutdown.
*/
int Error.ready(void) => x2c_error_runtime_ready;
