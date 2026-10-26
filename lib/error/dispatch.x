/*  dispatch.x -- error dispatch */

/* The nested-handler probe reaches depth 2; two more levels are reserve for
   a rendering or allocation handler that itself must raise. */
#define ERROR_MAX_DEPTH 4

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
Symbol Error.raise(Symbol code, List detail) {
  ErrorRaise r = _raise_enter(code);
  _record(NULL, r.code, detail);
  return _dispatch(r);
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
  _dispatch(r);
}

/* A raise reaches the floor while error state is being built, when dispatch
   is nested too deeply or shut down, and before initialization. */
static ErrorRaise _raise_enter(Symbol code) {
  Symbol effective = code ? code : <invariant>;
  ErrorThreadState state = _thread();
  if (state.floor_only) _floor(effective, "raise while building error state");
  if (state.shutdown_done || state.depth >= ERROR_MAX_DEPTH)
    _floor(effective, "raise re-entered or after shutdown");
  state.depth++;
  if (!Error.ready()) {
    _leave();
    _floor(effective, "raise before initialization");
  }
  ErrorRaise r = {effective, Error.count(), state.depth};
  state.rendered[r.depth] = 0;
  return r;
}

static void _leave(void) => _thread().depth--;

/** Returns the current nested error-dispatch depth.
    This is the nesting depth of error dispatch. `Error.count` returns the
    number of accumulated errors.
*/
int Error.depth(void) => _thread().depth;

/* dispatch

   A handler runs on the live frame, before any transfer, and sees the errors
   accrued since it was registered. Dispatch hides each handler before
   offering it the error, so a nested raise begins at the next outer handler;
   the saved full chain is restored after dispatch or at a transfer landing. */

/* Offers the newest record to the handlers, then restores the chain. An
   error every handler declined follows its cause's policy, and a shared
   non-returning cause that no catch took reaches the floor. */
static Symbol _dispatch(ErrorRaise r) {
  ErrorThreadState state = _thread();
  ErrorHandler saved = state.handler_top, outer = state.dispatch_saved;
  ErrorHandler outer_running = state.dispatch_running;
  /* Only the outermost dispatch records the complete chain. A handler that
     raises starts a nested dispatch from its own hidden position, and a
     transfer out of that nested dispatch must still hand every registration
     back to the cleanup that runs between the raise and the landing. */
  if (!outer) state.dispatch_saved = saved;
  Symbol disposition = _offer(state, saved, r.code);
  state.handler_top = saved;
  state.dispatch_saved = outer;
  state.dispatch_running = outer_running;
  _leave();
  if (_never_returns(r.code))
    _terminate(state, r, "non-returning error was not caught");
  if (disposition == <declined>) _apply_policy(state, r);
  return disposition;
}

/* Logger has already reported a rendered error, so the floor adds nothing. */
static void _terminate(ErrorThreadState e, ErrorRaise r, const char *why) {
  if (e.rendered[r.depth]) abort();
  _floor(r.code, why);
}

/* Offers the error to each handler from `h` outward. `<handled>` consumes
   that handler's slice and stops the search; `<declined>` continues outward
   and leaves the errors accumulated. */
static Symbol _offer(
  ErrorThreadState e, ErrorHandler h, Symbol code) {
  for (; h; h = h.prev) {
    e.dispatch_running = h;
    e.handler_top = h.prev;
    Symbol disposition = h.site ? _catch_match(h) : _observe(e, h);
    if (disposition == <unwind> || disposition == <fatal>)
      _transfer(e, h, code, disposition);
    if (disposition == <handled>) {
      _truncate(h.watermark);
      return <handled>;
    }
  }
  return <declined>;
}

/* The view belongs to the handler, not to this frame: `exit()` from the
   callback abandons the frame, and shutdown reclaims the handler. */
static Symbol _observe(ErrorThreadState e, ErrorHandler h) {
  defer _destroy(&(h.view));
  e.floor_only++;
  h.view = _region_new();
  List slice = _view_since(&(h.view), h.watermark);
  e.floor_only--;
  return h.fn(slice, h.data);
}

/* Hands the complete chain back to the cleanup that runs before a landing,
   then lands at the selected catch's frame. `<fatal>` aborts, and `<unwind>`
   is not available to an observing registration, so both reach the floor. */
static void _transfer(
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
static void _apply_policy(ErrorThreadState e, ErrorRaise r) {
  Symbol policy = Error.policy_get(r.code);
  if (policy == <abort>) _terminate(e, r, "unhandled and policy is abort");
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
