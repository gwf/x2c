/*  runtime.x -- error runtime */

#define ERROR_DEFAULT_BOUND 4096

static threaded struct ErrorThreadState error_thread;

module ErrorThreadState _thread(void) {
  ErrorThreadState state = &error_thread;
  if (!state.bound) state.bound = ERROR_DEFAULT_BOUND;
  return state;
}

/* the error floor

   The floor reports a failure that the rich error path cannot handle and
   aborts. It is reachable before initialization, after shutdown, and when
   raising has re-entered itself, so it allocates nothing and calls nothing
   that can. */

module void _floor(Symbol code, const char *why) {
  char spelling[SYMBOL_MAX_5BIT + 1] = { 0 };
  code.decode(spelling);
  fprintf(
    stderr, "x2c error floor: <%s>: %s\n", spelling, why ? why : "unknown");
  fflush(stderr);
  abort();
}

/* Pushes the thread's error scope unless it is already on top, and answers
   whether the caller must pop it. */
module int _scope_push(Symbol code, const char *message) {
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
  foreach (Symbol code in error_nonreturning_causes)
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
  _reclaim_hidden(state);
  _unwind_to(state, NULL, 1);
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
static void _reclaim_hidden(ErrorThreadState state) {
  ErrorHandler stop = state.dispatch_running;
  for (ErrorHandler h = stop ? state.dispatch_saved : NULL; h;) {
    ErrorHandler prev = h.prev;
    int last = h == stop;
    _free(h);
    if (last) break;
    h = prev;
  }
  state.dispatch_saved = state.dispatch_running = NULL;
  while (state.running_top) {
    ErrorHandler running = state.running_top;
    state.running_top = running.running;
    _free(running);
  }
}

/** Reports whether the rich `Error` runtime can currently accept raises.
    This is per-thread state and is false before initialization and after
    shutdown.
*/
int Error.ready(void) => x2c_error_runtime_ready;
