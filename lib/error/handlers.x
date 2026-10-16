/*  handlers.x -- error handlers */

/* A site is bound on its first registration: `static` when `Match` retains a
   plan for every arm, `transient` when some pattern is built at run time and
   each registration must prepare its own plans. A pending site's patterns are
   literals in compiler output, so binding promotes them out of any nested
   `Pool` first. One thread binds a site; a thread that raced it there finds
   the site bound and ignores the patterns it built. */
#define ERROR_CATCH_PENDING 0
#define ERROR_CATCH_STATIC 1
#define ERROR_CATCH_TRANSIENT 2

/* catch selection

   A transferring catch selects the first arm whose pattern matches the
   newest record's `(code @detail)`. The selected arm's captures and the
   records above the watermark then belong to the handle. */

static Symbol _catch_match(ErrorHandler h) {
  if (Error.count() <= h.watermark) return <declined>;
  ErrorRecord *record = _record_at(Error.count() - 1);
  Symbol code = record.entry.car().list().cadr();
  List detail = record.entry.cadr().list().cadr();
  ErrorThreadState state = _thread();
  state.floor_only++;
  List projection = _cons(&(record.region), code, detail);
  Pool.open_named("Error catch bindings");
  int selected = _catch_select(h, record, projection);
  Pool.close();
  if (selected) _catch_retain(h);
  state.floor_only--;
  return selected ? <unwind> : <declined>;
}

static int _catch_select(
  ErrorHandler h, ErrorRecord *record, List projection) {
  for (int i = 0; i < h.site.arm_count; i++)
    if (_catch_arm(h, record, projection, i)) {
      h.selected = i;
      return 1;
    }
  return 0;
}

/* Tries arm `i` and, when it matches, copies its captures into the record's
   region. The default arm matches without a plan. */
static int _catch_arm(
  ErrorHandler h, ErrorRecord *record, List projection, int i) {
  MatchPlan plan = _arm_plan(h, i);
  MatchCaptureLayout layout = plan ? plan.layout : NULL;
  int binders = layout ? layout.binder_count : 0;
  Var *values = binders ? Scope.malloc(sizeof(Var) * binders) : NULL;
  MatchCaptureBuffer captures = {values, 0, binders};
  int matched = i == h.site.default_arm ||
    (plan.status == <prepared> &&
     plan.execute_capture(projection, captures, NULL) == 1);
  if (matched) _commit_captures(h, record, layout, &captures);
  if (values) Scope.free(values);
  return matched;
}

/* A transient site's registration holds its own plans; a static site
   retains one plan per arm. */
static MatchPlan _arm_plan(ErrorHandler h, int i) {
  if (i == h.site.default_arm) return NULL;
  MatchPlan *plans = h.plans != NULL ? h.plans.bytes : NULL;
  return plans ? plans[i] : h.site.arms[i].plan;
}

static void _commit_captures(
  ErrorHandler handle, ErrorRecord *record, MatchCaptureLayout layout,
  MatchCaptureBuffer *captures) {
  if (handle.capture_values != NULL) {
    handle.capture_values.free();
    handle.capture_values = NULL;
  }
  if (!layout || !layout.binder_count) return;
  int pushed = _scope_push(
    <alloc-fail>, "could not enter error scope for catch captures");
  handle.capture_values = Block.new(sizeof(Var));
  handle.capture_values.append(NULL, layout.binder_count);
  Var *values = handle.capture_values.bytes;
  for (int i = 0; i < layout.binder_count; i++) {
    values[i] = void;
    if (captures.has(i))
      values[i] = _copy_value(&(record.region), captures.values[i]);
  }
  if (pushed) Scope.pop();
}

/* Move the selected slice off the public record stack without destroying its
   private regions. Capture values were copied into the newest record's region,
   so the detached catch handle owns both them and the selected Error until
   `_free` destroys `retained`. Records are stored newest first;
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

static void _retained_destroy(Block retained) {
  if (retained == NULL) return;
  ErrorRecord *records = retained.bytes;
  for (size_t i = 0; i < retained.length; i++)
    _destroy(&(records[i].region));
  retained.free();
}

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
  _free(handle);
}

static void _free(ErrorHandler handle) {
  if (!handle) return;
  // a per-call site has no static arm storage and belongs to this handler
  if (handle.site && !handle.site.arms) Scope.free(handle.site);
  _plans_free(handle.plans);
  if (handle.capture_values != NULL) handle.capture_values.free();
  _retained_destroy(handle.retained);
  _destroy(&(handle.view));
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
static void _unwind_to(
  ErrorThreadState state, ErrorHandler stop, int truncate) {
  while (state.handler_top && state.handler_top != stop) {
    ErrorHandler removed = state.handler_top;
    state.handler_top = removed.prev;
    if (truncate) _truncate(removed.watermark);
    _free(removed);
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
  const char *fenced = _prepare_arms(h, patterns, arm);
  state.floor_only--;
  /* Report the fence here, where the unusable arm can be named. Reporting it
     from dispatch would re-enter the raise path that is already answering
     one error. */
  if (fenced) {
    _free(h);
    String fence = String.new(fenced);
    raise %(size-limit (operation "catch") (arm $arm) (fence $fence));
  }
  state.handler_top = h;
  return h;
}

/* Binds a pending site, then returns why the first fenced arm this
   registration can reach is unusable, or NULL. A transient site prepares
   its plans for this registration alone. */
static const char *_prepare_arms(
  ErrorHandler h, Var *patterns, int &arm) {
  ErrorCatchSite *site = h.site;
  if (_state(site) == ERROR_CATCH_PENDING) _bind(site, patterns);
  if (_state(site) == ERROR_CATCH_TRANSIENT)
    return _prepare_plans(h, patterns, arm);
  if (site.fenced_arm < 0) return NULL;
  arm = site.fenced_arm;
  return site.arms[arm].plan.reason;
}

static int _state(ErrorCatchSite *site) =>
  __atomic_load_n(&site.state, __ATOMIC_ACQUIRE);

static void _bind(ErrorCatchSite *site, Var *patterns) {
  _site_lock();
  // promotion and preparation allocate, and a failure never returns here
  defer _site_unlock();
  if (_state(site) != ERROR_CATCH_PENDING) return;
  int retainable = 1;
  for (int i = 0; retainable && i < site.arm_count; i++)
    if (i != site.default_arm)
      retainable = List.try_own(patterns[i]) &&
                   x2c_match_pattern_retainable(patterns[i]);
  if (retainable)
    for (int i = 0; i < site.arm_count; i++) {
      if (i == site.default_arm) continue;
      MatchPlan plan = x2c_match_site_prepare(&site.arms[i], patterns[i]);
      if (plan.status == <ineligible> && site.fenced_arm < 0)
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
static const char *_prepare_plans(
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
    if (plan && plan.status == <ineligible> && !fenced) {
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
  !site || _state(site) != ERROR_CATCH_STATIC;

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
  _free(handle);
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
  if (_chain_contains(state.handler_top, saved)) _unwind_to(state, saved, 1);
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
