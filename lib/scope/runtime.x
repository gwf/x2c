/*  runtime.x -- scope runtime */

// lifecycle

static Symbol scope_state = <uninit>;
static void(**hooks)(void);
static int hook_count, hook_capacity;

/** Initializes the process-wide `Scope` runtime owner. */
void Scope.initialize(void) {
  _initialize();
}

/** Registers `hook` to run during process-wide `Scope` shutdown.
    The function pointer is retained without being invoked. Shutdown invokes
    registrations once in reverse order while `Scope` storage is still
    available, including one registered by a hook that shutdown is already
    running.

    Raises: `<bad-arg>` for a null hook, `<size-limit>` when the registry
    cannot grow, or `<alloc-fail>` when its storage cannot be allocated.
*/
void Scope.shutdown_hook(void (*hook)(void)) {
  _require_running();
  if (!hook) raise %(bad-arg);
  hooks = _raw_grow(hooks, hook_count, hook_capacity, sizeof(*hooks));
  hooks[hook_count++] = hook;
}

/** Releases resources owned by `Scope`.
    `Scope` groups managed allocations by lifetime; balanced retain/release
    and push/pop boundaries remain caller responsibilities.
*/
void Scope_shutdown(void) {
  if (scope_state == <shutdown> || scope_state == <shutting>) return;
  if (scope_state == <uninit>) {
    scope_state = <shutdown>;
    return;
  }
  scope_state = <shutting>;
  /* Hooks close higher-level owners in reverse dependency order while Scope
     allocations still work. Thread-local regions then disappear before leak
     reporting reads the name registry, and shared thread state goes last. */
  _run_hooks();
  x2c_static_shutdown();
  x2c_scope_thread_release();
  _report_leaks();
  _free_name_registry();
  scope_state = <shutdown>;
  x2c_thread_state_release();
}

static void _initialize(void) {
  if (scope_state == <running> || scope_state == <shutting>) return;
  if (scope_state == <shutdown>)
    _raw_fatal("operation attempted after shutdown");
  ScopeThreadState state = _thread();
  state.active = &state.root;
  scope_state = <running>;
  if (atexit(Scope_shutdown))
    _raw_fatal("could not register shutdown handler");
}

module void _raw_fatal(const char *message) {
  fprintf(stderr, "Scope: %s\n", message);
  abort();
}

/* A hook that registers another runs it next, still newest first. */
static void _run_hooks(void) {
  while (hook_count) {
    void (*hook)(void) = hooks[--hook_count];
    hook();
  }
  _raw_free(hooks);
  hooks = NULL;
  hook_count = hook_capacity = 0;
}

module void _raw_free(void *ptr) {
  if (!ptr) return;
  atomic_fetch_add(&raw_free_count, 1);
  free(ptr);
}

/* Returns `items` with room for one element past `count`, starting at 16 and
   doubling `capacity` when full. */
module void *_raw_grow(void *items, int count, int &capacity, size_t size) {
  if (!items) {
    items = _raw_malloc(16 * size);
    capacity = 16;
  }
  else if (count == capacity) {
    if (capacity > INT_MAX / 2) raise %(size-limit);
    items = _raw_realloc(items, capacity * 2 * size);
    capacity *= 2;
  }
  return items;
}

module void *_raw_malloc(size_t size) {
  void *ptr = malloc(size);
  if (!ptr) raise %(alloc-fail);
  atomic_fetch_add(&raw_alloc_count, 1);
  return ptr;
}

static void *_raw_realloc(void *ptr, size_t size) {
  void *result = realloc(ptr, size);
  if (!result) raise %(alloc-fail);
  return result;
}

module void _require_running(void) {
  if (scope_state != <running>) _ensure_running();
}

static void _ensure_running(void) {
  if (scope_state == <uninit>) _initialize();
  else if (scope_state == <shutdown>)
    _raw_fatal("operation attempted after shutdown");
}
