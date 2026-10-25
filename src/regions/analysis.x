/*  analysis.x -- function summaries and lifetime analysis */

// per-unit fixpoint

/* The functions `ast` defines, walked to their final summaries. */
static void _fixpoint(Walk &w, List ast) {
  w.frame = xcalloc(1, sizeof(struct Region));
  w.frame.kind = <frame>;
  Array functions = auto [];
  _collect_functions(ast, functions);
  foreach (List function in functions)
    if (w.summaries[function.car()] is void)
      w.summaries[function.car()] = %(0 ());
  /* Summaries only grow, and a walk reads no summary but its callees', so
     walking a function again before one of those changes repeats its last
     walk. Each round walks the functions in order, skipping those, until a
     round changes no summary. Each function's last walk then read final
     summaries, and its warnings are the unit's. */
  int count = functions.len();
  Array found = auto [];
  w.readers = {};
  w.stale = [];
  for (int i = 0; i < count; i++) {
    found.push(NULL);
    w.stale.push(1);
  }
  do {
    w.changed = 0;
    for (w.current = 0; w.current < count; w.current++) {
      if (!w.stale[w.current].int()) continue;
      w.stale[w.current] = 0;
      w.warnings = [];
      _analyze(w, functions[w.current]);
      found[w.current] = w.warnings;
    }
  } while (w.changed);
  w.warnings = [];
  foreach (Array warnings in found)
    foreach (List warning in warnings) w.warnings.push(warning);
}

/* One row per function: its C name, its parameter bindings in order, and
   its body. */
static void _collect_functions(Var node, Array found) {
  match (node) {
    case %(expr *): break;
    case %(function ? (bind (binding ? ?name) ((fnmod (params *rows)) *))
                    ?body): {
      Array parameters = [];
      foreach (List row in rows)
        match (row) case %(param ? (bind ?parameter ?)):
          parameters.push(parameter);
      found.push(%($name $(parameters.list_free()) $body));
    }
    case %(*children):
      foreach (Var child in children) _collect_functions(child, found);
  }
}

/* Walk one body against the current summaries. The walk starts from the
   function's previous summary, so a summary only grows. */
static void _analyze(Walk &w, List function) {
  (String name, List parameters, Var body) = function;
  w.function = name;
  (int fresh, List sinks) = w.summaries[name];
  w.facts = {};
  w.sinks = {};
  w.restored = {};
  w.open = NULL;
  w.depth = w.origin = 0;
  w.fresh = fresh;
  foreach (List row in sinks) w.sinks[row] = 1;
  int index = 0;
  foreach (List parameter in parameters) _new_fact(w, parameter, index++);
  _walk(w, body);
  Array rows = [];
  foreach (List row in w.sinks.keys()) rows.push(row);
  List summary = %($(w.fresh) $(rows.sort().list_free())),
       previous = w.summaries[name];
  if (summary == previous) return;
  w.summaries[name] = summary;
  w.changed = 1;
  Var readers;
  if (w.readers.try_get(name, readers))
    foreach (int reader in readers) w.stale[reader] = 1;
}

/* A summary is `(OWNER SINKS)`, where OWNER is a bit set of scoped (1) and
   pooled (2) returned storage. SINKS is a sorted List of `(INDEX TARGET)`
   pairs and a target is <return>, <result>, <static>, <unknown>, or
   `(param INDEX)`. <result> retains an argument in fresh result storage;
   <return> aliases an argument as the result. */
module List _summary(Walk &w, String callee) {
  match (_effect(w, callee)) {
    case %(alloc pool): return %(2 ());
    case %(alloc *): return %(1 ());
    case %(pool): return %(2 ((0 result) (1 result)));
    case %(store): return %(0 ((1 (param 0)) (2 (param 0))));
    case %(summary ?owner ?sinks): return %($owner $sinks);
  }
  _read(w, callee);
  Var local = w.summaries[callee];
  return local is void ? %(0 ()) : local;
}

/* Records that the current walk reads the summary of `callee`. */
static void _read(Walk &w, String callee) {
  Var known;
  if (!w.readers.try_get(callee, known)) {
    known = [];
    w.readers[callee] = known;
  }
  Array readers = known;
  int count = readers.len();
  if (!count || readers[count - 1].int() != w.current)
    readers.push(w.current);
}

// entry points

/** Warns about values that can outlive the region that allocated them.
    `ast` must be the bound and typed top-level unit, before transform
    lowering rewrites its `defer` and region forms. The call adds warnings to
    `c` and does not change `ast`.
*/
void Compiler.check_regions(Compiler c, List ast) {
  Walk w = {.c = c, .summaries = {}, .pending = [], .freed = []};
  _fixpoint(w, ast);
  int origin = c.origin;
  foreach (List warning in w.warnings) {
    (Symbol code, int at, String message, List notes) = warning;
    c.origin = at;
    c.report_warning(code, message, NULL, notes);
  }
  c.origin = origin;
}

/** Rejects a `meta` function whose body breaks the rule
    `Compiler.check_regions` warns about. A compile-time call frees its
    locals when it returns, so an address of one that is returned or stored
    into a static, a parameter's object, or an unknown pointer would read
    freed memory. The first finding is reported as an error. `fn` must be
    the bound and typed definition. The walk reads the summaries of the
    `meta` functions installed before `fn` and records the summary of `fn`
    in `meta_regions`.
*/
void Compiler.check_meta_regions(Compiler c, List fn) {
  match (fn) case %(function ? (bind (binding ? ?(String name)) *) ?): {
    /* A replaced definition starts again from an empty summary. */
    c.meta_regions[name] = %(0 ());
  }
  Walk w = {
    .c = c, .summaries = c.meta_regions, .pending = [], .freed = [],
    .meta = 1};
  _fixpoint(w, fn);
  if (!w.warnings.len()) return;
  (Symbol code, int at, String message, List notes) = w.warnings[0];
  with (c.origin = at) { c.report_error(code, message, NULL, notes); }
}

/** Computes one unit's region summaries and findings for an optional
    project audit. `seed` contains prior project-round summaries indexed by
    the emitted names visible in this unit. `effects` adds audit-only native
    contracts; neither input changes ordinary translation. Findings carry
    their function name and are returned without compiler diagnostics. */
Map Compiler.audit_regions(
  Compiler c, List ast, Map seed, Map effects, Array findings) {
  Walk w = {
    .c = c, .summaries = seed.copy(), .effects = effects,
    .pending = [], .freed = [], .audit = 1};
  _fixpoint(w, ast);
  foreach (List finding in w.warnings) findings.push(finding);
  return w.summaries;
}
