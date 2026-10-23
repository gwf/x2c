/*  policy.x -- error policy */

/* policy

   A policy decides what happens to an error every handler declined. A
   `Context` overlays its own policies and bound on the thread's. */

/* This is the same shared cause table that drives compiler unreachable
   emission. Error locks every listed policy to abort: observing handlers may
   inspect but cannot consume one, while a matching compiler catch transfers
   control without returning to its raising call. */
module const SymbolSet error_nonreturning_causes =
  $error.nonreturning.causes();

module int _never_returns(Symbol code) => code in error_nonreturning_causes;

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
  ErrorContextState context = xmalloc(sizeof(struct ErrorContextState));
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
  ErrorHandler stop = _handler_at_depth(state, context.handler_depth);
  _unwind_to(state, stop, !preserve_records);
  if (!preserve_records) _truncate(context.stack_height);
  state.context_top = context.prev;
}
