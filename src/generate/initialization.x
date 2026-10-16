/*  initialization.x -- construct once-only file initialization */

// initialization syntax

/** Returns the function `type name(void)` running `body`. */
List Compiler.initializer_function(
  Compiler c, Type type, List name, List body) =>
  c.rebuild_unit_function($!Unit{ $type $name(void) { @body } });

/** Returns a run-once initializer body: `before`, then a return when
   `guard` is set that sets it otherwise, then `after`. */
List Compiler.run_once_body(Compiler c, List before, List guard, List after) {
  List flag = $!int{ $guard };
  List test = c.rebuild_statement($!{ if ($flag) return; $flag = 1; }).cdr();
  return List.concat_n(3, before, test, after);
}

/* Consume the initialization state completed by cache setup. `source`
   already holds the cache slots and batch helpers at the prelude boundary.
   The helpers are functions, so the guard and synthetic initializer follow
   the slots and precede the helpers, and cache reachability sees them. */
module List _file_init(Compiler c, List source) {
  if (!c.pending.initializes() && !c.fini_fn && !c.init_fn) return source;
  Init init = {.c = c, .initializer = c.init_fn};
  _prepare(init, source);
  Array entries = [];
  foreach (List item, source)
    entries.push(init.enter(item, _patches(init, item)));
  List guard = c.initialization_guard(init.guard);
  List prelude = init.synthetic ? %($guard ${init.synthetic}) : %($guard);
  return c.place_source_prelude(entries.list_free(), prelude);
}

/* A file without a type initializer, or with one that conditional groups
   may compile out, gets a synthetic initializer. */
static void _prepare(Init &i, List source) {
  Compiler c = i.c;
  i.guard = c.sym.reference(%("_init_guard_"), NULL);
  i.shutdown = _shutdown_registration(c, source);
  List arms = i.initializer ? _definition_arms(source, i.initializer) : NULL;
  if (!i.initializer || arms) i.synthetic = _synthesize(i, arms);
  else i.entry = c.sym.reference(%(${i.initializer}), NULL);
  if (_cache_only(c)) i.reachable = _cache_reachable(source);
}

/** Returns `function` with its entry setup: the protocol initializer and
    the type initializer run once, and a `guarded` entry calls the region's
    initializer unless its guard is set. */
List Init.enter(Init &i, List function, int guarded) {
  match (function)
    case %(function ? (bind (binding ? ?(String name)) ?) (block *body)): {
      if (name == "x2c_initialize_protocols")
        return _protocol_initializer(i.c, function, body);
      if (i.initializer && name == i.initializer)
        return _replace_body(i.c, function, _statements(i, NULL, body));
      if (guarded) return _guarded(i, function, body);
    }
  return function;
}

/* A source file guards its public entries. The protocol bootstrap
   functions are never guarded, and a cache-only file guards only the
   entries that reach a cache. */
static int _patches(Init &i, List item) {
  match (item)
    case %(function (!set ?type (*)) (bind (binding ? ?(String name)) ?)
           (block *)):
      return !type.type().is_static() && !_protocol_bootstrap(name) &&
        (i.reachable == NULL || name in i.reachable);
  return 0;
}

static int _protocol_bootstrap(String name) =>
  name == "x2c_initialize_protocols" ||
  name == "x2c_register_builtin_descriptor" ||
  name == "x2c_try_register_tagged_descriptor";

// initializers

static macro Decorator $initializer_body(Function $function,
    Stmt @body) {
  @body
}

static macro Decorator $initialized_entry(
  Function $function, Expr $guard, Expr $entry, Stmt @body) {
  if (!$guard) $entry();
  @body
}

/* The synthetic initializer runs `entry` before its guard. Without a type
   initializer it is a constructor that runs protocol setup; as a
   constructor it runs in the root epoch, before main. Literal statics last
   for the whole process, so they must never be created inside a caller's
   allocation bracket, and the lazy entry guards remain as the portable
   fallback. A type initializer in conditional groups may be compiled out,
   so the synthetic initializer calls it under the arms that compile it,
   which sets the guard, and otherwise runs the file's own initialization.
   Every public entry checks the guard before calling it, so it stays out
   of line and cold: a small initializer inlined into each entry costs
   every call its frame setup. */
static List _synthesize(Init &i, List arms) {
  List binding = i.entry = i.c.sym.introduce("_file_init_");
  List type =
    %(("__attribute__((constructor, noinline, cold))") static void);
  String entry = "x2c_initialize_protocols";
  if (i.initializer) {
    type = %(("__attribute__((noinline, cold))") static void);
    entry = i.initializer;
  }
  List statements =
    _statements(i, _within_definitions(arms, Ast.entry_call(entry)), NULL);
  return i.c.initializer_function(type, binding, statements);
}

/* An initializer runs `entry` and its run-once test, then the `<prepare>`
   and `<statics>` areas, its own `body`, the `<finish>` area, and the
   shutdown registration. Cache graphs that require the initializer's own
   String/List canonicalizer go in `<finish>`; all other cache and static
   setup keeps its pre-body order. */
static List _statements(Init &i, List entry, List body) {
  Compiler c = i.c;
  List queued = List.concat_n(
    5, c.init_statements(<prepare>), c.init_statements(<statics>), body,
    c.init_statements(<finish>), i.shutdown);
  return c.run_once_body(entry, i.guard, queued);
}

/* `function` calls the region's initializer unless its guard is set. */
static List _guarded(Init &i, List function, List body) {
  Macro shape = $initialized_entry;
  List guard = i.guard, condition = $!int{ $guard };
  List callee = %(expr ((func ((void))) void) (ident ${i.entry}));
  return i.c.rebuild_function(function, shape(condition, callee, body));
}

module List _replace_body(
  Compiler c, List function, List statements) {
  Macro shape = $initializer_body;
  return c.rebuild_function(function, shape(statements));
}

/* Install generated built-in protocol methods before any ordinary file
   constructor can create a String- or List-backed cache. */
static List _protocol_initializer(
  Compiler c, List function, List body) {
  List guard = c.sym.introduce("_x2c_gensym_protocol_guard_");
  List declaration = c.initialization_guard(guard);
  List queued = c.init_statements(<protocol>).append(body);
  return _replace_body(
    c, function, c.run_once_body(%($declaration), guard, queued));
}

/* The registration of the unit's shutdown function, under the arms that
   compile its definition. */
static List _shutdown_registration(Compiler c, List source) {
  String shutdown = c.fini_fn;
  if (!shutdown) return NULL;
  List binding = c.sym.reference(%($shutdown), NULL);
  return _within_definitions(
    _definition_arms(source, shutdown), %((
    stmnt
      (expr (void)
        (call "Scope_shutdown_hook"
          (args (expr ((func ((void))) void) (ident $binding)))))
  )));
}

/* The conditional arms around each definition of the function `name`, in
   source order, each as `Compiler.preproc_track_arms` keeps them. A definition
   outside every conditional group is always compiled, which gives NULL. */
static List _definition_arms(List source, String name) {
  List arms = NULL, found = NULL;
  foreach (List item, source)
    match (item) {
      case %(function (*) (bind (binding ? ?(String spelling)) ?) (block *)):
        if (spelling == name) {
          if (!arms) return NULL;
          found = cons(arms, found);
        }
      case %(preproc ?(String content)):
        arms = Compiler.preproc_track_arms(arms, content);
    }
  return found.reverse();
}

/* `statements` under the arms that compile each definition in `found`, or
   unconditionally when `found` is NULL. At most one definition compiles. */
static List _within_definitions(List found, List statements) {
  if (!found) return statements;
  Array out = [];
  foreach (List arms, found)
    foreach (List item, Compiler.preproc_within_arms(arms, statements))
      out.push(item);
  return out.list_free();
}

/** Returns the statements queued for `phase`, in the order they were added. */
List Compiler.init_statements(Compiler c, Symbol phase) =>
  c.pending.area(phase);

/* cache-only files

   A file without a type initializer whose only queued work is `<prepare>`
   cache setup patches only the entries that reach a cache. Its eager
   constructor already runs the initializers, and unrelated foundational
   calls then cannot recursively materialize literals during String/List
   pool setup. */

static int _cache_only(Compiler c) =>
  !c.init_fn && c.pending.area(<prepare>) &&
  !c.pending.area(<statics>) && !c.pending.area(<finish>);

/* Every function that directly or transitively reaches a source cache. */
static Map _cache_reachable(List source) {
  Map callers = {}, reachable = {}, Array queue = [];
  foreach (List node, source)
    match (node)
      case %(!set ?definition
             (function ? (bind (binding ? ?spelling) ?) ?)):
        if (_record_calls(definition, spelling, callers)) queue.push(spelling);
  for (int i = 0; i < queue.len(); i++) {
    Var key = queue[i];
    if (key in reachable) continue;
    reachable[key] = 1;
    if (key in callers)
      foreach (Var caller, callers[key].list()) queue.push(caller);
  }
  queue.free();
  return reachable;
}

/* Records in `callers` each function `caller` calls within `value`, and
   returns whether `value` uses a cache. Functions are keyed by spelling,
   which names one file-scope function in the unit. Binding numbers do not:
   class defaults selected during macro-library preload are numbered apart
   from the unit's own walk. */
static int _record_calls(Var value, Var caller, Map callers) {
  if (value is not <list>) return 0;
  List node = value;
  match (node) {
    case %(cache ?): return 1;
    case %(ident (binding ? ?callee)): {
      List found = callee in callers ? callers[callee] : NULL;
      callers[callee] = cons(caller, found);
      return 0;
    }
  }
  int uses = 0;
  foreach (Var child, node)
    if (_record_calls(child, caller, callers)) uses = 1;
  return uses;
}
