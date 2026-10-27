/*  sites.x -- retained source-site plans and shutdown */

/* capture sites

   The compiler gives each complete static pattern its own site, which holds
   one immutable plan in `Match`-owned process storage until shutdown. Only
   the first call takes a lock, to prepare that plan; `plan` is published
   last and read with acquire ordering, so a site that already holds a plan
   takes no lock. */

static Scope match_capture_site_scope;

static Block match_capture_sites;

static pthread_mutex_t match_site_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

// lifecycle

static pthread_once_t match_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

/** Matches through one compiler-owned static capture site.
    Its first admissible pattern permanently binds the site; direct C callers
    must not reuse one site for different patterns. `site` must be
    zero-initialized static storage and `pattern` must contain only values that
    remain live through `Match` shutdown. A pattern the site cannot retain
    takes the ordinary runtime route, with the same result, and the site
    records that refusal once, so later calls take that route directly.
    Returns 1 only after atomically committing `captures`; invalid arguments,
    malformed patterns, misses, and machine errors return 0 without changing
    it.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    publishing or matching.
*/
int x2c_match_site_try_capture(
  MatchCaptureSite *site, List input, Var pattern,
  MatchCaptureBuffer &?captures) {
  if (!captures) return 0;
  MatchPlan plan = _published(site, pattern);
  // a pattern the site cannot retain takes the ordinary runtime route
  if (!plan) return x2c_match_try_capture(input, pattern, captures);
  /* _prepared owns the status decision before capture validation. */
  return _prepared(plan, "match") &&
         _buffer_valid(plan.layout, captures) &&
         _capture(plan, input, captures, NULL) == 1;
}

/** Reports whether a compiler-owned site can retain `pattern`.
    A site borrows its pattern's values for the life of the process, so only a
    graph of values that outlives every call qualifies.
*/
int x2c_match_pattern_retainable(Var pattern) =>
  MatchPlan.borrowable(pattern, 1);

/** Returns the process-lifetime plan for one compiler-owned site.
    The first retainable pattern binds the site permanently. A pattern the site
    cannot retain returns NULL; an ineligible one returns its fenced plan so
    the caller can name the fence.
    Raises: `<alloc-fail>` while publishing.
*/
MatchPlan x2c_match_site_prepare(MatchCaptureSite *site, Var pattern) =>
  _published(site, pattern);

/** Returns bindings through one compiler-owned site, or `nil` on a miss.
    Results follow `List.match`.
*/
List x2c_match_site_match(MatchCaptureSite *site, List input, Var pat) {
  List bindings;
  if (!x2c_match_site_try_match(site, input, pat, bindings)) return NULL;
  return bindings ? bindings : %(());
}

/** Matches through one compiler-owned site, writing bindings on success.
    Results follow `List.try_match`.
*/
int x2c_match_site_try_match(
  MatchCaptureSite *site, List input, Var pat, List &?out_bindings) {
  MatchPlan plan = _plan(site, pat);
  if (!plan) return input.try_match(pat, out_bindings);
  /* Plan operations reject null outputs; wrappers map non-success to zero. */
  return plan.try_match(input, out_bindings) == 1;
}

/** Searches through one compiler-owned site, writing the first match.
    Results follow `List.try_search`.
*/
int x2c_match_site_try_search(
  MatchCaptureSite *site, List input, Var pat, Var &?out_match,
  List &?out_bindings) {
  MatchPlan plan = _plan(site, pat);
  if (!plan) return input.try_search(pat, out_match, out_bindings);
  return plan.try_search(input, out_match, out_bindings) == 1;
}

/** Returns every matching subtree through one compiler-owned site.
    Results follow `List.search`.
*/
List x2c_match_site_search(MatchCaptureSite *site, List input, Var pat) {
  MatchPlan plan = _plan(site, pat);
  if (!plan) return input.search(pat);
  List results = NULL;
  plan.search(input, results);
  return results;
}

/** Returns the `List` replacement through one compiler-owned site.
    Results follow `List.match_replace`.
*/
List x2c_match_site_match_replace(
  MatchCaptureSite *site, List input, Var pat, Var template) {
  Var result;
  if (!x2c_match_site_try_match_replace(site, input, pat, template, result))
    return input;
  /* The List destination maps scalar replacement results to nil. */
  return result;
}

/** `Match`-replaces through one compiler-owned site.
    Results follow `List.try_match_replace`.
*/
int x2c_match_site_try_match_replace(
  MatchCaptureSite *site, List input, Var pat, Var template, Var &?out) {
  MatchPlan plan = _plan(site, pat);
  if (!plan) return input.try_match_replace(pat, template, out);
  return plan.try_match_replace(input, template, out) == 1;
}

/** Replaces every match through one compiler-owned site.
    Results follow `List.search_replace`.
*/
List x2c_match_site_search_replace(
  MatchCaptureSite *site, List input, Var pat, Var template) {
  MatchPlan plan = _plan(site, pat);
  if (!plan) return input.search_replace(pat, template);
  List result = input;
  plan.search_replace(input, template, result);
  return result;
}

// borrowed patterns

/** Reports whether a plan may borrow `pattern` by its canonical identity.
    `permanent_lists` requires every `List` in it to belong to the outermost
    pool, as a plan kept for the life of the process does. Without it, a
    `List` that is canonical now qualifies until its pool level is released.
*/
int MatchPlan.borrowable(Var pattern, int permanent_lists) =>
  _pattern_borrowable(pattern, 0, permanent_lists);

/** Registers process-wide `Match` cleanup exactly once.
    Repeated calls have no effect. Failure of the native once primitive writes
    a diagnostic and aborts the process.
    Raises: `<alloc-fail>` or `<size-limit>` while registering the shutdown
    hook.
*/
void x2c_match_initialize(void) {
  int status = pthread_once(&match_shutdown_once, _register_shutdown_once);
  _thread_check(status, "register shutdown");
}

/* Returns this site's plan, publishing it on the first call and answering
   NULL for a site whose pattern it cannot retain. The refusal is recorded on
   the site, so a pattern the site rejects costs two atomic loads per call
   instead of the registry lock and a fresh admissibility walk. */
static MatchPlan _published(
  MatchCaptureSite *site, Var pattern) {
  if (!site) return NULL;
  MatchPlan plan = __atomic_load_n(&site.plan, __ATOMIC_ACQUIRE);
  if (plan) return plan;
  if (__atomic_load_n(&site.refused, __ATOMIC_ACQUIRE)) return NULL;
  return _publish_plan(site, pattern);
}

/* Prepares one site once, under the lock that also guards the site
   registry. Every later call sees the published plan and skips this. */
static MatchPlan _publish_plan(MatchCaptureSite *m, Var pattern) {
  _site_lock();
  // preparation allocates, and an allocation failure never returns here
  defer _site_unlock();
  if (!m.plan) _prepare(m, pattern);
  return m.plan;
}

static void _prepare(MatchCaptureSite *site, Var pattern) {
  if (!MatchPlan.borrowable(pattern, 1)) {
    __atomic_store_n(&site.refused, 1, __ATOMIC_RELEASE);
    return;
  }
  _sites_initialize();
  MatchPlan plan = NULL;
  auto (&match_capture_site_scope) {
    plan = MatchPlan.prepare(pattern);
    match_capture_sites.push(&site);
  }
  /* Normalizing a guard allocates cells in the pool active at this first
     call, and the layout keeps them for the life of the process. */
  if (plan.layout.normalized is <list>) List.try_own(plan.layout.normalized);
  __atomic_store_n(&site.plan, plan, __ATOMIC_RELEASE);
}



/* Both borrowing owners walk the same graph and differ on one question: how
   long the borrow lasts. Symbols and narrow immediates have value lifetime,
   and `nil` holds no storage, so no later pattern can reuse its address. A
   `String` or long `Atom` is borrowed only when the outermost canonical pool
   owns it, because an equal transient buffer is never interned and its
   address proves nothing. Wide boxes, pointers, and references are never
   borrowed; those patterns prepare a transient plan owned by their lease.

   `permanent_lists` is what separates the two owners. A site keeps its
   program for the life of the process, so it needs a `List` the outermost
   pool owns: a nested pool reuses the storage of its released cells, and an
   identity that belongs to one would let a different pattern answer at the
   same address. The plan cache retires every entry when a level is released,
   so a `List` that is canonical now serves it, and interning gives an equal
   pattern the same cell. */
static int _pattern_borrowable(Var value, int depth, int permanent_lists) {
  if (depth >= 128) return 0;
  switch (value.kind()) {
    case <symbol>: return 1;
    case <pointer>: case <reference>: return 0;
    case <object>: return _object_borrowable(value, depth, permanent_lists);
  }
  return value is not <long> && value is not <ulong> &&
         value is not <llong> && value is not <ullong> &&
         value is not <ldouble>;
}

static int _object_borrowable(Var value, int depth, int permanent_lists) {
  if (value is <lsym>) return String.is_permanent((String) value.pointer());
  if (value is <string>) return String.is_permanent(value);
  if (value is not <list>) return 0;
  if (!value.pointer()) return 1;
  if (permanent_lists && !Pool.is_permanent(value)) return 0;
  // kind and tag prove the raw payload is a List cell
  foreach (Var part in (List) value.pointer())
    if (!_pattern_borrowable(part, depth + 1, permanent_lists)) return 0;
  return 1;
}

static void _sites_initialize(void) {
  if (match_capture_site_scope) return;
  match_capture_site_scope = Scope.new_named("Match source-site plans");
  auto (&match_capture_site_scope) {
    match_capture_sites = Block.new(sizeof(MatchCaptureSite *));
  }
  x2c_match_initialize();
}

static void _site_lock(void) {
  _thread_check(pthread_mutex_lock(&match_site_mutex), "lock source site");
}

static void _site_unlock(void) {
  _thread_check(pthread_mutex_unlock(&match_site_mutex), "unlock source site");
}

/* A native thread primitive that fails leaves the registry in an unknown
   state, so the process reports it and aborts. */
static void _thread_check(int status, const char *action) {
  if (!status) return;
  fprintf(stderr, "Match: could not %s\n", action);
  abort();
}

static void _register_shutdown_once(void) {
  Scope.shutdown_hook(_shutdown);
}

static void _shutdown(void) {
  x2c_match_thread_release();
  _sites_shutdown();
}

static void _sites_shutdown(void) {
  if (!match_capture_site_scope) return;
  MatchCaptureSite **sites = match_capture_sites != NULL
                           ? match_capture_sites.bytes : NULL;
  for (size_t i = 0; i < match_capture_sites.length; i++) {
    MatchCaptureSite *site = sites[i];
    /* The registry contains live nonnull sites accepted by _published. */
    if (!site.plan) continue;
    site.plan.free();
    site.plan = NULL;
  }
  if (match_capture_sites != NULL) match_capture_sites.free();
  match_capture_site_scope.destroy();
  match_capture_site_scope = NULL;
}

/* site consumers

   Each operation follows its `List` counterpart. A pattern the site cannot
   retain, or an ineligible one, takes that ordinary runtime route, which has
   the same result and names the public operation when it reports a fence. */

/* The plan this site holds, publishing it on the first call, or NULL for
   the ordinary runtime route. */
static MatchPlan _plan(MatchCaptureSite *site, Var pattern) {
  MatchPlan plan = _published(site, pattern);
  return plan && plan.status != <ineligible> ? plan : NULL;
}
