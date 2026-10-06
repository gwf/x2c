/*  regions.x -- values that can outlive the region that allocated them

    Copyright (c) 2026 Gary William Flake.

    A region is a `$scope()` block, a `Scope.retain` and `Scope.release`
    pair, a `$scope(&slot)` push, a `Pool.open` bracket, an `$auto`
    local, a Scope local that `Scope.destroy` ends, or the function's own
    storage, which an address taken with `&` borrows. The pass reads the
    typed forms the parser produced, before the transform driver rewrites
    them, so a region is still the call that opens it and the `defer` beside
    it that closes it. It warns when a value born in a region reaches storage
    that outlives the region and when a local is read after it was freed.

    A function's summary is two facts: which owner supplies fresh returned
    storage, and where each parameter is sunk. The unit's functions reach a
    fixpoint over their summaries. A call into another unit has a summary
    only through the runtime table, so warnings do not depend on which units
    were translated before it. A `meta` function is walked when it is
    defined, against the summaries of the `meta` functions before it, and a
    finding there is an error, because a compile-time call frees its locals
    when it returns.

    The warnings name departures from the lexical pattern. Raw C stores,
    pointer arithmetic, callbacks, and storage the runtime did not allocate
    stay outside them.
*/

#pragma once
#include "compiler.x"

#include "meta.x"
#include "grammar.x"

/* Deferred region findings. The walk owns collection and severity. */

static macro Stmt $report.region.bad_free(Expr $w, Expr $op, Expr $subject) =>
  $w.warn(
    <bad-free>, $w.origin,
    %"${$op} is given ${$subject}, which no Scope allocator returned",
    %("only Scope.malloc, calloc, memdup, and realloc storage can be"
      "freed or reallocated"));

static macro Stmt $report.region.read_ended(Expr $w, Expr $name) =>
  $w.warn(
    <region>, $w.origin,
    %"'${$name}' is read after its owning region ended", NULL);

static macro Stmt $report.region.after_free(Expr $w, Expr $name, Expr $ended) =>
  $w.warn(
    <after-free>, $w.origin, %"'${$name}' is used after ${$ended}", NULL);

static macro Stmt $report.region.use_ended(
  Expr $f, Expr $subject, Expr $region) =>
  (*$f.w).warn(
    <region>, $f.w.origin,
    %"${$subject} is used after the region that allocated it ended",
    (*$f.w).opened($region));

static macro Stmt $report.region.local_escape(
  Expr $f, Expr $subject, Expr $exit) {
  String message =
    %"${$subject} can outlive the local storage it points into when ${$exit}";
  (*$f.w).warn(
    <region>, $f.w.origin, message,
    %("local storage ends when the function returns"));
}

static macro Stmt $report.region.escape(
  Expr $f, Expr $subject, Expr $exit, Expr $region) =>
  (*$f.w).warn(
    <region>, $f.w.origin,
    %"${$subject} can outlive the region it was allocated in when ${$exit}",
    (*$f.w).opened($region));

static macro Expression $region.reason.returned() => "returned";
static macro Expression $region.reason.static_store() => "stored into a static";
static macro Expression $region.reason.local() =>
  "assigned to a local declared outside the region";
static macro Expression $region.reason.pointer() =>
  "stored through an unknown pointer";
static macro Expression $region.reason.parameter() => "stored through a parameter";
static macro Expression $region.reason.other() =>
  "stored into an object of another region";
static macro Expression $region.reason.outer() =>
  "stored into an object of an outer region";

static macro Expression $region.reason.moved() => "Scope.realloc moved it";
static macro Expression $region.reason.freed() => "it was freed";

#include "ast.x"
#include "stage.x"
#include "type.x"

// walk state

/* An open or closed region. `kind` is scope, pool, slot, auto, local: the
   storage of a Scope local whose end has not been seen, or frame: the
   storage of the function's locals and parameters. `depth` is the
   block depth it belongs to, `origin` the statement that opened it, `slot`
   the Scope local a pushed slot names, and `outer` the next open region. */
static typedef struct Region {
  Symbol kind;
  int depth, origin, closed;
  struct Fact *slot;
  struct Region *outer;
} *Region;

/* What the walk knows about one local or parameter: the block depth that
   declares it, its parameter index or -1, whether it holds storage born in
   this function, whether a free or a realloc ended it (`ending` while the
   expression that ends it is walked), the region its value belongs to
   (and the Pool alternative of a mixed result), the region a Scope local's
   own storage forms, and for a pointer taken
   with `&`, the local and place it names. `born` records a scoped or pooled
   result, including when the allocation has no local region. */
static typedef struct Fact {
  int depth, origin, param, born;
  Symbol dead, ending;
  struct Region *region, *other, *owner;
  struct Fact *points;
  List place;
} *Fact;

static Var Fact.var(Fact fact) => Var.new(<p48>, fact);
static Fact Var.fact(Var value) => value.pointer();
static protocol Var(Fact) as void *;

/* The walk state for one unit. `facts` maps a binding to its Fact, `open`
   is the innermost open region, `frame` is the region of the function's
   own storage, and `restored` holds the places a `$let` or another `defer`
   puts back before its block ends. `fresh` and `sinks` accumulate the
   current function's summary, `warnings` holds the current walk's, and
   `pending` and `freed` are the expression walk's stacks. `readers` maps a
   function name to the positions of the functions whose walks read its
   summary, `stale` marks the positions to walk again, and `current` is the
   position being walked. `meta` is set while a `meta` definition is
   walked. */
static typedef struct Walk {
  Compiler c;
  Map summaries, facts, sinks, restored, effects, readers;
  Array warnings, pending, freed, stale;
  Region open, frame;
  String function;
  int depth, origin, fresh, changed, meta, audit, current;
} Walk;

// runtime effects

/* The runtime operations the pass reads by C name. (alloc) returns storage
   born in the active region and (alloc slot) in the Scope its first
   argument names; (alloc final) is an (alloc) whose result a `meta` body
   owns in its own frame, because a finalizer ends it when the lowered call
   returns; (pool) conses both arguments into pool cells; (store)
   puts its later arguments into its receiver; (wrap) boxes its argument
   unchanged; (free) ends its argument, or owns it from a `defer`, and
   (free scope) also requires Scope storage; (alloc moved) is a Scope
   allocation that ends its first argument; (destroy) ends a Scope local's
   storage; (open KIND) and (close KIND) bracket a region; (move) and
   (exit) hand their argument to another owner; (summary OWNER SINKS) is a
   literal summary. */
static Map runtime = %{
  "Scope_malloc": (alloc),           "Scope_calloc": (alloc),
  "Scope_memdup": (alloc),           "Scope_malloc_finalized": (alloc),
  "Scope_realloc": (alloc moved),    "String_malloc": (alloc pool),
  "String_new": (alloc pool),        "String_new_len": (alloc pool),
  "String_new_fill": (alloc pool),
  "Block_new": (alloc),              "Bytes_new": (alloc),
  "Array_new": (alloc),              "Map_new": (alloc),
  "Buffer_new": (alloc),
  "Scope_malloc_in": (alloc slot),   "Scope_calloc_in": (alloc slot),
  "Scope_memdup_in": (alloc slot),   "Scope_malloc_finalized_in": (alloc slot),
  "cons": (pool),                    "Var_cons": (pool),
  "List_cons": (pool),
  "Array_push": (store),             "Array_insert": (store),
  "Array_unshift": (store),          "Array_setindex": (store),
  "Map_setindex": (store),           "Map_set": (store),
  "Map_setdefault": (store),         "Var_setindex": (store),
  "Var_map": (wrap),                 "Map_var": (wrap),
  "Symbol_var": (summary 0 ()),      "Var_integer": (summary 0 ()),
  "Var_is_row": (summary 0 ()),       "Var_kind": (summary 0 ()),
  "Var_int": (summary 0 ()),          "Var_is_void": (summary 0 ()),
  "Var_is_nil": (summary 0 ()),       "Var_is_atom": (summary 0 ()),
  "Map_len": (summary 0 ()),
  "List_len": (summary 0 ()),         "String_equal": (summary 0 ()),
  "Symbol_str": (alloc pool),
  "int_var": (summary 0 ()),          "uint_var": (summary 0 ()),
  "char_var": (summary 0 ()),         "uchar_var": (summary 0 ()),
  "short_var": (summary 0 ()),        "ushort_var": (summary 0 ()),
  "float_var": (summary 0 ()),        "double_var": (summary 0 ()),
  "long_var": (alloc),                "Var_box_long": (alloc),
  "Func_var": (wrap),
  "List_car": (summary 0 ((0 return))),
  "List_cdr": (summary 0 ((0 return))),
  "String_lower": (summary 2 ((0 return))),
  "String_upper": (summary 2 ((0 return))),
  "String_capitalize": (summary 2 ((0 return))),
  "String_strip": (summary 2 ((0 return))),
  "String_add": (summary 2 ((0 return) (1 return))),
  "puts": (summary 0 ()),             "File_puts": (summary 0 ()),
  "assert": (summary 0 ()),
  "Var_array": (wrap),               "Array_var": (wrap),
  "Var_list": (wrap),                "List_var": (wrap),
  "Var_string": (wrap),              "String_var": (wrap),
  "Var_block": (wrap),               "Block_var": (wrap),
  "Var_buffer": (wrap),              "Buffer_var": (wrap),
  "Array_free": (free),              "Array_list_free": (free),
  "Array_cleanup": (free),           "Map_cleanup": (free),
  "Block_free": (free),              "Block_cleanup": (free),
  "Bytes_cleanup": (free),           "Buffer_free": (free),
  "Buffer_cleanup": (free),          "Context_close": (free),
  "Context_cleanup": (free),         "Scope_free": (free scope),
  "Scope_destroy": (destroy),        "Scope_cleanup": (destroy),
  "Scope_retain": (open scope),      "Scope_release": (close scope),
  "Pool_open": (open pool),          "Pool_close": (close pool),
  "Scope_push": (open slot),         "Scope_pop": (close slot),
  "Scope_move": (move),              "Context_export": (exit),
  "List_promote": (exit),            "String_promote": (exit),
  "Atom_promote": (exit),
  "Var_as_iter": (wrap),             "Iter_var": (wrap),
  "Var_adnode": (wrap),              "AdNode_var": (wrap),
  "Var_token": (wrap),               "Token_var": (wrap),
  "Var_file": (wrap),                "File_var": (wrap),
  "Var_job": (wrap),                 "Job_var": (wrap),
  "Var_arraychar": (wrap),           "ArrayChar_var": (wrap),
  "Var_arrayshort": (wrap),          "ArrayShort_var": (wrap),
  "Var_arrayint": (wrap),            "ArrayInt_var": (wrap),
  "Var_arraylong": (wrap),           "ArrayLong_var": (wrap),
  "Var_arrayfloat": (wrap),          "ArrayFloat_var": (wrap),
  "Var_arraydbl": (wrap),            "ArrayDbl_var": (wrap),
  "Var_arraystring": (wrap),         "ArrayString_var": (wrap),
  "Var_mapintint": (wrap),           "MapIntInt_var": (wrap),
  "Var_maplongdouble": (wrap),       "MapLongDouble_var": (wrap),
  "Var_mapstringstring": (wrap),     "MapStringString_var": (wrap),
  "Var_mapstringint": (wrap),        "MapStringInt_var": (wrap),
  "Var_jsonbool": (wrap),            "Var_regexcapture": (wrap),
  "Var_regexmatch": (wrap),          "Var_regex": (wrap),
  "List_job": (alloc final),
  "Job_start": (summary 0 ((0 return))),
  "String_lines": (summary 1 ((0 result))),
  "String_words": (summary 1 ((0 result))),
  "String_splits": (summary 1 ((0 result) (1 result))),
  "Var_fallback_iter": (summary 0 ((1 return))),
  "Array_write_str": (summary 0 ((1 return))),
  "Array_write_repr": (summary 0 ((1 return))),
  "Map_write_str": (summary 0 ((1 return))),
  "Map_write_repr": (summary 0 ((1 return))),
  "Buffer_reserve": (summary 0 ((0 return))),
  "Buffer_clear": (summary 0 ((0 return))),
  "Buffer_write_len": (summary 0 ((0 return))),
  "Buffer_write": (summary 0 ((0 return))),
  "Buffer_write_char": (summary 0 ((0 return))),
  "Buffer_write_repeat": (summary 0 ((0 return))),
  "Buffer_unwrite": (summary 0 ((0 return))),
  "Buffer_pad": (summary 0 ((0 return))),
  "Buffer_newline": (summary 0 ((0 return))),
  "Buffer_indent": (summary 0 ((0 return))),
  "Buffer_newline_indent": (summary 0 ((0 return))),
  "Buffer_push": (summary 0 ((0 return))),
  "Buffer_pop": (summary 0 ((0 return))),
  "Scope_new": (summary 0 ()),       "Scope_new_named": (summary 0 ()),
  "Context_open": (summary 0 ()),    "Context_current": (summary 0 ()),
  "Iter_new": (alloc),               "Iter_array": (alloc),
  "Iter_list": (alloc pool),
  "Iter_next": (summary 0 ()),       "Iter_count": (summary 0 ()),
  "Iter_sum": (summary 0 ()),        "Iter_product": (summary 0 ()),
  "Iter_max": (summary 0 ()),        "Iter_min": (summary 0 ()),
  "Array_iter": (summary 0 ((0 (param 1)) (1 return))),
  "List_iter": (summary 0 ((0 (param 1)) (1 return))),
  "Map_iter": (summary 0 ((0 (param 1)) (1 return))),
  "Map_keys": (summary 0 ((0 (param 1)) (1 return))),
  "Map_enumerate": (summary 0 ((0 (param 1)) (1 return))),
  "String_iter": (summary 0 ((0 (param 1)) (1 return))),
  "Var_iter": (summary 0 ((0 (param 1)) (1 return))),
  "range": (summary 0 ((3 return))),
  "Iter_map": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
  "Iter_filter": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
  "Iter_zip": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
  "Iter_chain": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
  "Iter_accumulate": (summary 0 ((0 (param 2)) (1 (param 2)) (2 return))),
  "Iter_enumerate": (summary 0 ((0 (param 2)) (2 return))),
  "Iter_repeat": (summary 0 ((0 (param 2)) (2 return))),
  "Iter_head": (summary 0 ((0 (param 2)) (2 return))),
  "Iter_unique": (summary 1 ((0 (param 1)) (1 return))),
  "Iter_zip_with":
    (summary 0 ((0 (param 3)) (1 (param 3)) (2 (param 3)) (3 return))),
  "Iter_map2":
    (summary 0 ((0 (param 3)) (1 (param 3)) (2 (param 3)) (3 return))),
  "Iter_scan":
    (summary 0 ((0 (param 3)) (1 (param 3)) (2 (param 3)) (3 return)))
};

/* Runtime operations with a pooled result that the pass does not read:
   the table has no row for most, and the row for Array_list_free is its
   argument effect. A copy such as String_concat keeps none of its
   arguments, and Atom_intern may return a value that already exists. */
static Map pooled_results = %{
  "Array_list_free": 1, "Atom_intern": 1, "List_append": 1,
  "String_concat": 1,   "String_join": 1
};

static Var Walk.effect(Walk &w, String name) {
  if (!w.audit) return runtime[name];
  Var effect;
  return w.effects && w.effects.try_get(name, effect)
       ? effect : runtime[name];
}

/** The owner of the storage the runtime operation `name` returns: `<scope>`
    for the active Scope, `<slot>` for the Scope its first argument names,
    `<pool>` for the canonical-value pool, or 0 when nothing is known. What
    the operation does to its arguments is a separate fact. */
Symbol Compiler.region_result(String name) {
  match (runtime[name]) {
    case %(alloc slot): return <slot>;
    case %(alloc pool): return <pool>;
    case %(alloc *): return <scope>;
    case %(pool): return <pool>;
  }
  return name in pooled_results ? <pool> : 0;
}

/** Reports whether the runtime operation `name` returns its argument's
    storage unchanged, as a `Var` box or its unboxing does. */
int Compiler.region_wrapper(String name) => runtime[name] == %(wrap);

/** Reports whether the runtime table proves the lifetime effects of the
    native function `name`. */
int Compiler.has_region_row(String name) => name in runtime;

// per-unit fixpoint

/* The functions `ast` defines, walked to their final summaries. */
static void Walk.fixpoint(Walk &w, List ast) {
  w.frame = Scope.calloc(1, sizeof(struct Region));
  w.frame.kind = <frame>;
  Array functions = $auto([]);
  _collect_functions(ast, functions);
  foreach (List function, functions)
    if (w.summaries[function.car()] is void)
      w.summaries[function.car()] = %(0 ());
  /* Summaries only grow, and a walk reads no summary but its callees', so
     walking a function again before one of those changes repeats its last
     walk. Each round walks the functions in order, skipping those, until a
     round changes no summary. Each function's last walk then read final
     summaries, and its warnings are the unit's. */
  int count = functions.len();
  Array found = $auto([]);
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
      w.analyze(functions[w.current]);
      found[w.current] = w.warnings;
    }
  } while (w.changed);
  w.warnings = [];
  foreach (Array warnings, found)
    foreach (Var warning, warnings) w.warnings.push(warning);
}

/* One row per function: its C name, its parameter bindings in order, and
   its body. */
static void _collect_functions(Var node, Array found) {
  match (node) {
    case %(expr *): break;
    case %(function ? (bind (binding ? ?name) ((fnmod (params *rows)) *))
                    ?body): {
      Array parameters = [];
      foreach (Var row, rows)
        match (row) case %(param ? (bind ?parameter ?)):
          parameters.push(parameter);
      found.push(%($name ${parameters.list_free()} $body));
    }
    case %(*children):
      foreach (Var child, children) _collect_functions(child, found);
  }
}

/* Walk one body against the current summaries. The walk starts from the
   function's previous summary, so a summary only grows. */
static void Walk.analyze(Walk &w, List function) {
  (String name, List parameters, Var body) = function;
  w.function = name;
  (int fresh, List sinks) = w.summaries[name];
  w.facts = {};
  w.sinks = {};
  w.restored = {};
  w.open = NULL;
  w.depth = w.origin = 0;
  w.fresh = fresh;
  foreach (Var row, sinks) w.sinks[row] = 1;
  int index = 0;
  foreach (List parameter, parameters) w.new_fact(parameter, index++);
  w.walk(body);
  Array rows = [];
  foreach (Var row, w.sinks.keys()) rows.push(row);
  List summary = %(${w.fresh} ${rows.sort().list_free()}),
       previous = w.summaries[name];
  if (summary == previous) return;
  w.summaries[name] = summary;
  w.changed = 1;
  Var readers;
  if (w.readers.try_get(name, readers))
    foreach (int reader, readers) w.stale[reader] = 1;
}

// statements

static void Walk.walk(Walk &w, Var node) {
  Macro statement = $expression_statement;
  Macro deferred = $deferred;
  Macro returned = $return_value;
  match (node) {
    case %(at ?origin ?inner): w.walk_at(origin, inner);
    case $source_block_content(%(*statements)):
      w.walk_block(statements);
    case %(seq *statements): w.walk_sequence(statements);
    case deferred(?body): w.walk_defer(body);
    /* A lowered defer keeps its environment and capture records. */
    case %(defer ?body ?environment ?callback ?records ?written):
      w.walk_defer(body);
    case %((!or declare decl) ?specifiers (bindings *bindings)):
      w.declare(specifiers, bindings);
    case returned(?result):
      w.walk_return(source_return_type(node), result);
    /* A jump leaves the statements after it to another path, and a label is
       where that path arrives, so neither carries forward what the path
       before it freed. */
    case %((!or goto label) *): w.revive();
    case statement(?expression): w.walk_expression(expression);
    /* A control construct's children run conditionally, so they count as a
       nested block: what they free does not end the fall-through. */
    case $source_conditional_statement():
      w.walk_conditional(node.cdr());
    case %(catchcases ?rows): w.walk(rows);
    case %((!or expr case) *): w.scan(node, 0);
    case $source_content_pattern($grouped, %(?inner)):
      w.scan(node, 0);
    /* Match and catch arms are bare `(PATTERN STATEMENT ...)` rows. */
    case %((*) *): w.walk_rows(node);
  }
}

static void Walk.walk_at(Walk &w, int origin, Var inner) {
  int outer = w.origin;
  w.origin = origin;
  w.walk(inner);
  w.origin = outer;
}

static void Walk.walk_block(Walk &w, List statements) {
  Region outer = w.open;
  Map restored = w.restored;
  w.depth += 1;
  foreach (Var statement, statements) w.walk(statement);
  w.close_to(w.open, outer);
  w.open = outer;
  w.restored = restored;
  w.depth -= 1;
}

/* Closes oldest first. */
static void Walk.close_to(Walk &w, Region region, Region outer) {
  if (region == outer) return;
  w.close_to(region.outer, outer);
  region.closed = 1;
}

static void Walk.walk_sequence(Walk &w, List statements) {
  foreach (Var statement, statements) w.walk(statement);
}

static void Walk.walk_return(Walk &w, Type type, Var result) {
  w.scan(result, 0);
  w.flow(result, type, <return>, NULL);
  w.revive();
}

/* A free ends its local for the statements that follow it on the same path.
   Where that path ends, nothing it freed is known to be freed any more. */
static void Walk.revive(Walk &w) {
  foreach (Var known, w.facts) {
    Fact fact = known;
    fact.dead = 0;
  }
}

static void Walk.walk_expression(Walk &w, Var expression) {
  List arguments = NULL;
  String callee = _callee_of(expression, arguments);
  if (callee && w.region_call(callee, arguments)) return;
  match (_source_assignment(_unwrap(expression))) {
    case %(?target ?value): w.store(target, value);
    default: w.scan(expression, 0);
  }
}

/* A region-opening or region-ending call in statement position. Reports
   whether `callee` is one. */
static int Walk.region_call(Walk &w, String callee, List arguments) {
  Fact fact = w.fact_of(arguments.car(), NULL);
  match (w.effect(callee)) {
    case %(open ?kind): w.open_region(kind, w.slot(arguments.car()));
    case %(close ?kind): {
      Region region = w.innermost(kind);
      /* A close in a nested block runs on some paths, so the region stays
         open for the statements after that block. */
      if (region) region.closed = region.depth == w.depth;
    }
    case %(destroy): if (fact && fact.depth == w.depth && fact.owner)
      fact.owner.closed = 1;
    case %(move): if (fact) _move(fact, w.owner(w.slot(arguments.cadr())));
    case %(exit): if (fact) _move(fact, NULL);
    default: return 0;
  }
  return 1;
}

static void Walk.walk_conditional(Walk &w, List children) {
  Map restored = w.restored;
  w.depth += 1;
  foreach (Var child, children) w.walk(child);
  w.depth -= 1;
  w.restored = restored;
}

static void Walk.walk_rows(Walk &w, List rows) {
  foreach (List row, rows) {
    w.scan(row.car(), 0);
    foreach (Var statement, row.cdr()) w.walk(statement);
  }
}

// defers and restored places

/* A `defer` beside a region closes it at block exit, a deferred free or
   destroy owns its local until then, and any other deferred expression
   runs at block exit. */
static void Walk.walk_defer(Walk &w, Var body) {
  List arguments = NULL;
  String callee = NULL;
  Macro statement = $expression_statement;
  match (body) case statement(?expression):
    callee = _callee_of(expression, arguments);
  Fact fact = w.fact_of(arguments.car(), NULL);
  match (callee ? w.effect(callee) : void) {
    case %(close ?): return;
    case %(free *) if (fact && fact.param < 0): {
      fact.region = w.open_region(<auto>, NULL);
      return;
    }
    case %(destroy): {
      Region owner = w.owner(fact);
      if (!owner || owner.kind != <local>) return;
      owner.kind = <auto>;
      owner.outer = w.open;
      w.open = owner;
      return;
    }
  }
  if (w.note_restored(body)) return;
  w.restored = w.restored.copy();
  w.note_deferred_stores(body);
  w.scan(body, 1);
}

/* `$let` saves a place, installs a value, and restores the place in a
   defer. A store into a place this block restores is undone before the
   block ends, so it is not an escape. */
static int Walk.note_restored(Walk &w, Var body) {
  Macro statement = $expression_statement;
  match (body) case statement(?expression):
    match (_source_assignment(_unwrap(expression))) case %(?target ?): {
      Var place = w.target_place(target);
      if (place == _unwrap(target)) return 0;
      w.restored = w.restored.copy();
      w.restored[place] = 1;
      return 1;
    }
  return 0;
}

/* A place a `defer` writes is put back when its block ends, so a store
   into it after the `defer` is not an escape. */
static void Walk.note_deferred_stores(Walk &w, Var node) {
  match (_source_assignment(node)) case %(?target ?): {
    w.restored[_unwrap(target)] = 1;
    return;
  }
  match (node) case %(*children):
    foreach (Var child, children) w.note_deferred_stores(child);
}

// expressions

/* Visit every read, call, and nested store in one expression, left to
   right and without recursion, so a long operator chain fits the stack. A
   free ends its local after the whole expression, and a deferred
   expression runs at block exit, so what it frees stays live for the
   statements this block still has to walk. */
static void Walk.scan(Walk &w, Var value, int deferred) {
  Var root = _unwrap(value);
  int base = w.pending.len(), mark = w.freed.len();
  w.pending.push(value);
  while ((int) w.pending.len() > base) {
    Var node = w.pending.take_last();
    if (w.scan_call_node(node)) continue;
    if (w.scan_assignment(node, root)) continue;
    w.scan_node(node);
  }
  while ((int) w.freed.len() > mark) {
    Fact fact = w.freed.take_last();
    if (!deferred) fact.dead = fact.ending;
  }
}

static int Walk.scan_call_node(Walk &w, Var node) {
  List call = _source_call(node);
  if (!call) return 0;
  (Var function, List arguments) = call;
  String callee = binding_identity_spelling(_binding_of(function));
  match (callee ? w.effect(callee) : void) {
    case %((!or exit wrap)): break;
    case %(free): w.end(arguments.car(), NULL, <freed>);
    case %(free scope): w.end(arguments.car(), "Scope.free", <freed>);
    case %(alloc moved):
      w.end(arguments.car(), "Scope.realloc", <moved>);
    default: if (callee) w.scan_call(node, callee, arguments);
  }
  if (arguments) w.pending.push(arguments);
  return 1;
}

/* An argument that ends its storage. `op` names a Scope operation, which
   reports storage no Scope allocator returned: a literal, the function's
   own storage, or a pooled value. The local it names is dead after the
   expression, `how` recording whether it was freed or moved. */
static void Walk.end(Walk &w, Var argument, String op, Symbol how) {
  List named = NULL;
  Fact storage = w.value_fact(argument, named);
  int literal = 0;
  match (_unwrap(argument)) case $source_literal_content(%(*fields)):
    literal = 1;
  if (op && (literal || (storage &&
      (storage.region == w.frame || storage.born == 2)))) {
    String subject = literal ? "a literal"
                             : w.subject(argument, named, storage);
    $report.region.bad_free(w, op, subject);
  }
  Fact fact = w.fact_of(argument, NULL);
  if (!fact || fact.depth != w.depth) return;
  fact.ending = how;
  w.freed.push(fact);
}

/* A call sinks each argument where the callee's summary says. */
static void Walk.scan_call(Walk &w, Var call, String callee, List arguments) {
  int count = arguments.len();
  List types = _parameter_types(call);
  foreach (List row, w.summary(callee).cadr()) {
    (int index, Var target) = row;
    if (index >= count) continue;
    Type type = NULL, holder_type = NULL;
    Var argument = _passed(types, arguments, index, type);
    if (target == <static>) w.flow(argument, type, <static>, NULL);
    else if (target == <unknown>) w.flow(argument, type, <heap>, NULL);
    else if (target == <result>) {
      int born = 0;
      Region other = NULL;
      Region region = w.birth(call, NULL, born, other);
      struct Fact result = {
        .param = -1, .born = born, .region = region, .other = other};
      w.flow(argument, type, <heap>, &result);
    }
    else match (target) case %(param ?other): {
      if (other.int() >= count) continue;
      Var holder = _passed(types, arguments, other.int(), holder_type);
      int through = 1;
      Fact base = w.base(_address_of(holder), through), object = NULL;
      if (!base) base = w.fact_of(holder, NULL);
      Symbol sink = _sink_of(base, through, object);
      w.flow(argument, type, sink, object);
    }
  }
}

static int Walk.scan_assignment(Walk &w, Var node, Var root) {
  List assignment = _source_assignment(node);
  if (!assignment || _unwrap(node) == root) return 0;
  (Var target, Var stored) = assignment;
  w.store(target, stored);
  w.pending.push(target);
  return 1;
}

static void Walk.scan_node(Walk &w, Var node) {
  match (node) {
    case %(expr ? ?inner): w.pending.push(inner);
    case $source_identifier_content(
        %((!set ?binding (binding ? ?)))):
      w.scan_ident(binding);
    /* A statement expression declares locals of its own. */
    case %((!or declare decl) ?specifiers (bindings *bindings)):
      w.declare(specifiers, bindings);
    /* A List literal retains its values in the active Pool. */
    case %(cons ?head ?tail): w.scan_cons(node, head, tail);
    case %(*children): w.scan_children(children);
  }
}

static void Walk.scan_ident(Walk &w, Var binding) {
  Var found = w.facts[binding];
  if (found is void) return;
  Fact fact = found;
  if (w.audit && ((fact.region && fact.region.closed) ||
                  (fact.other && fact.other.closed))) {
    String name = binding_identity_spelling(binding);
    $report.region.read_ended(w, name);
    return;
  }
  if (!fact.dead) return;
  String name = binding_identity_spelling(binding);
  String ended = fact.dead == <moved> ? $region.reason.moved()
                                      : $region.reason.freed();
  $report.region.after_free(w, name, ended);
  fact.dead = 0;
}

static void Walk.scan_cons(Walk &w, Var node, Var head, Var tail) {
  int born = 0;
  Region other = NULL;
  Region region = w.birth(node, NULL, born, other);
  struct Fact result = {.param = -1, .born = born, .region = region};
  w.flow(head, NULL, <heap>, &result);
  w.flow(tail, NULL, <heap>, &result);
  w.pending.push(tail);
  w.pending.push(head);
}

static void Walk.scan_children(Walk &w, List children) {
  int start = w.pending.len();
  foreach (Var child, children) w.pending.push(child);
  for (int end = w.pending.len() - 1; start < end; start++, end--) {
    Var first = w.pending[start];
    w.pending[start] = w.pending[end];
    w.pending[end] = first;
  }
}

// stores and declarations

static void Walk.store(Walk &w, Var target, Var value) {
  /* A store through a pointer reads the pointer. */
  if (!_binding_of(target)) w.scan(target, 0);
  if (w.target_place(target) in w.restored) {
    w.scan(value, 0);
    return;
  }
  Type type = _expression_type(target);
  List named = _binding_of(target);
  Var found = named ? w.facts[named] : void;
  if (found is not void) {
    w.assign(found, value, type, 1);
    return;
  }
  w.scan(value, 0);
  if (named) {
    w.flow(value, type, <static>, NULL);
    return;
  }
  int through = 0;
  Fact object = NULL, base = w.base(target, through);
  /* A field or element of file-scope storage is that storage. */
  if (!base && !through && _root(target)) {
    w.flow(value, type, <static>, NULL);
    return;
  }
  Symbol sink = _sink_of(base, through, object);
  w.flow(value, type, sink, object);
}

/* The place a store target names, seen through the pointer a `$let` holds:
   `*address` and the place `address` was taken from are one storage. */
static Var Walk.target_place(Walk &w, Var target) {
  Var inner = _unwrap(target);
  match (inner)
    case $source_operator_content(%((!quote *) ?pointer)): {
      Fact fact = w.fact_of(pointer, NULL);
      if (fact && fact.place) return fact.place;
    }
  return inner;
}

/* `fact` receives `value`, declared or stored as `type`. A store of a
   region-born local into a local declared outside that region reports
   once, and the receiving local does not carry the region further. */
static void Walk.assign(Walk &w, Fact fact, Var value, Type type, int store) {
  w.scan(value, 0);
  Fact source = w.value_fact(value, NULL);
  if (!source) source = w.returned_argument(value, NULL);
  int born = 0;
  Region other = source ? source.other : NULL;
  Region region = source ? source.region
                         : w.birth(value, type, born, other);
  int owners = source ? source.born : born;
  int kept = (source || born) && !w.number(type, value);
  if (kept && w.copies(type, value)) {
    if (owners == 3) {
      region = other;
      other = NULL;
      owners = 2;
    }
    else kept = (owners & 2) || (region && region.kind == <pool>);
  }
  if (kept && store && source && (region || other))
    kept = !w.flow(value, type, <local>, fact);
  fact.dead = 0;
  fact.points = kept && source ? source.points : NULL;
  fact.place = kept && source ? source.place : NULL;
  /* A Scope local that is assigned again names other storage, whose end has
     not been seen, so the region its previous value formed is not the one
     the next allocation belongs to. */
  fact.owner = NULL;
  fact.region = kept ? region : NULL;
  fact.other = kept ? other : NULL;
  fact.born = kept ? owners : 0;
  fact.param = kept && source ? source.param : -1;
}

/* A static or extern local is not the function's storage, so the walk
   treats it as file-scope state. */
static void Walk.declare(Walk &w, Var specifiers, List bindings) {
  Map types = w.c.semantic_binding_facts();
  if (<static> in specifiers || <extern> in specifiers) {
    foreach (List item, bindings)
      match (item) case %(op = (bind ?name ?) ?value): {
        w.scan(value, 0);
        w.flow(value, types[%(type $name)], <static>, NULL);
      }
    return;
  }
  foreach (Var item, bindings)
    match (item) {
      case %(op (!quote =) (bind (!set ?name (binding ? ?)) ?) ?value):
        w.assign(w.new_fact(name, -1), value, types[%(type $name)], 0);
      case %(bind (!set ?name (binding ? ?)) ?): w.new_fact(name, -1);
    }
}

// flows

/* One value on its way to a sink: what the walk knows about it as `fact`,
   and the local it names as `named`. */
static typedef struct Flow {
  Walk *w;
  Var value;
  Type type;
  Symbol sink;
  Fact fact;
  List named;
} Flow;

/* `value` reaches `sink` through a destination of `type`: <return>,
   <static>, <local> for the local `target`, or <heap> for the storage
   `target` reaches, or an unknown pointer when `target` is NULL. A canonical
   destination copies. A parameter adds the sink to this function's summary;
   any other value reports when either possible owner can end first.
   Returns whether it reported. */
static int Walk.flow(Walk &w, Var value, Type type, Symbol sink, Fact target) {
  if (w.number(type, value)) return 0;
  match (_unwrap(value))
    case $source_operator_content(%((!quote ?) ? ?yes ?no)):
      return w.flow(yes, type, sink, target) ||
             w.flow(no, type, sink, target);
  List named = NULL;
  Fact fact = w.value_fact(value, named);
  if (!fact) fact = w.returned_argument(value, named);
  int born = 0;
  Region other = NULL;
  Region region = fact ? fact.region : w.birth(value, NULL, born, other);
  if (!fact && !born) return 0;
  if (fact && fact.param >= 0) {
    w.sink_parameter(fact, sink, target);
    return 0;
  }
  if (fact) {
    born = fact.born;
    other = fact.other;
  }
  Flow flow = {&w, value, type, sink, fact, named};
  return flow.owners(target, region, other, born);
}

static void Walk.sink_parameter(Walk &w, Fact fact, Symbol sink, Fact target) {
  Var row = sink;
  if (sink == <heap>) {
    if (!target) row = <unknown>;
    else if (target.param >= 0) row = %(param ${target.param});
    else row = target.born ? <result>
           : (target.region || target.other) ? void : <return>;
  }
  if (sink != <local> && row is not void)
    w.sinks[%(${fact.param} $row)] = 1;
}

static int Flow.owners(
  Flow &f, Fact target, Region region, Region other, int born) {
  int reported = 0;
  for (int choice = 0; choice < (born == 3 ? 2 : 1); choice++) {
    Region owner = choice ? other : region;
    int kind = born;
    if (born == 3) kind = choice ? 2 : 1;
    if (owner && target && target.born == 3 && f.sink == <heap>) {
      struct Fact pooled = *target;
      pooled.region = target.other;
      pooled.born = 2;
      reported |= f.check(target, owner, kind, !reported);
      reported |= f.check(&pooled, owner, kind, !reported);
    }
    else
      reported |= f.check(target, owner, kind, !reported);
  }
  return reported;
}

static int Flow.check(
  Flow &f, Fact target, Region region, int born, int report) {
  if ((*f.w).copies(f.type, f.value) && !(born & 2) &&
      (!region || region.kind != <pool>))
    return 0;
  if (!region) {
    if (f.sink == <return>) f.w.fresh |= born;
    return 0;
  }
  String subject = (*f.w).subject(f.value, f.named, f.fact);
  if (region.closed) {
    if (report)
      $report.region.use_ended(f, subject, region);
    return 1;
  }
  if (region.kind == <local>) return 0;
  String exit = f.exit(target, region);
  if (!exit) return 0;
  if (report) {
    // lint: allow one-statement-braces ST-1: macro emits declaration and call
    if (region == f.w.frame) {
      $report.region.local_escape(f, subject, exit);
    }
    else
      $report.region.escape(f, subject, exit, region);
  }
  return 1;
}

static String Flow.exit(Flow &f, Fact target, Region region) {
  switch (f.sink) {
    case <return>: return $region.reason.returned();
    case <static>: return $region.reason.static_store();
    case <local>:
      return target.depth < region.depth
        ? $region.reason.local() : NULL;
    default:
      if (!target) return $region.reason.pointer();
      if (target.param >= 0) return $region.reason.parameter();
      if (target.region == region) return NULL;
      /* Every region a function opens ends before its own storage. */
      if (target.region)
        return region == f.w.frame ? NULL
          : $region.reason.other();
      return $region.reason.outer();
  }
}

// store targets

static Fact Walk.base(Walk &w, Var place, int &through) {
  through = 1;
  match (_unwrap(place)) {
    case $source_operator_content(%((!quote ->) ?base ?)): {
      Fact fact = w.fact_of(base, NULL);
      if (!fact) fact = w.base(base, through);
      through = 1;
      return fact;
    }
    case $source_operator_content(%((!quote .) ?base ?)):
      return w.base(base, through);
    case $source_operator_content(%((!quote *) ?base)):
      return w.fact_of(base, NULL);
    case ${$indexed(%(!set ?base (expr ?type ?)), ?)}:
      return w.indexed_base(base, type, through);
    case %(getindex (!set ?base (expr ?type ?)) ?):
      return w.indexed_base(base, type, through);
    case $source_identifier_content(%(?binding)): {
      through = 0;
      return w.fact_of(place, NULL);
    }
    /* A compound literal is storage of the block the store is in. */
    case %(composite *): {
      through = 0;
      return w.new_fact(NULL, -1);
    }
  }
  return NULL;
}

/* The local a store target's storage belongs to. `through` is zero when
   the store writes the local itself and one when it writes storage the
   local reaches. */
static Fact Walk.indexed_base(Walk &w, List base, Type type, int &through) {
  Fact fact = w.fact_of(base, NULL);
  if (!fact) return w.base(base, through);
  /* A C array local owns its elements; a parameter is a pointer. */
  through = !type.is_array() || fact.param >= 0;
  return fact;
}

/* The storage `&place` borrows. A local, a parameter, or a compound
   literal is this function's own storage; a place reached through a
   pointer is storage that pointer holds. `named` is the local the place
   is part of. */
static Fact Walk.borrow(Walk &w, Var place, List &?named) {
  int through = 0;
  Fact base = w.fact_of(place, named);
  if (!base) base = w.base(place, through);
  if (!base) return NULL;
  if (named)
    if (!named) named = _root(place);
  Fact borrow = w.new_fact(NULL, -1);
  borrow.points = base;
  borrow.place = _unwrap(place);
  borrow.region = through ? base.region : w.frame;
  borrow.other = through ? base.other : NULL;
  borrow.born = through ? base.born : 0;
  if (through) borrow.param = base.param;
  return borrow;
}

/* The local a place is part of, or NULL. */
static List _root(Var place) {
  while (1)
    match (_unwrap(place)) {
      case $source_identifier_content(
          %((!set ?binding (binding ? ?)))): return binding;
      case $source_operator_content(%(? ?base *)): place = base;
      case ${$indexed(?base, ?selector)}: place = base;
      case %(getindex ?base ?): place = base;
      default: return NULL;
    }
}

/* The sink a store through `base` reaches. A struct local is its own
   storage; a pointer local reaches the storage it was given, and a pointer
   taken with `&x` reaches `x`. */
static Symbol _sink_of(Fact base, int through, Fact &target) {
  if (through && base && base.points) {
    base = base.points;
    through = 0;
  }
  int own = base && base.param < 0 && !base.born;
  target = through && own ? NULL : base;
  return !through && own ? <local> : <heap>;
}

// births and summaries

/* The region fresh storage an expression makes is born in, with `born`
   set; NULL with `born` set is the caller's active region. A mixed
   Scope/Pool result keeps its Pool region in `other`. `type` is the
   declared type a compound literal initializes, or NULL for its own. */
static Region Walk.birth(
  Walk &w, Var value, Type type, int &born, Region &other) {
  List arguments = NULL;
  String callee = _callee_of(value, arguments);
  born = 1;
  other = NULL;
  match (callee ? w.effect(callee) : void) {
    case %(alloc slot): return w.owner(w.slot(arguments.car()));
    case %(alloc pool): return w.pooled(born);
    case %(alloc final) if (w.meta): return w.frame;
    case %(alloc *): return w.active();
    case %(pool): return w.pooled(born);
  }
  Macro captured = $lambda_captured;
  match (source_expression(value)) {
    /* A closure holds what it captures, so it lives no longer than they. A
       reference capture moves its local into a cell of the active region,
       so the closure holds the local's value, not its address. */
    case captured(?body, *captures, *params):
      return w.captured_birth(captures, born, other);
  }
  match (_unwrap(value)) {
    case %(cons *): return w.pooled(born);
    case ${$array_value(*items)}:
      return w.active();
    case ${$map_value(*rows)}:
      return w.active();
    case %(composite *)
      if (w.value_class(type ? type : _expression_type(value)) == <container>):
      return w.active();
  }
  if (callee) return w.summary_birth(callee, born, other);
  born = 0;
  return NULL;
}

/* A pool value remains pooled even without a local bracket: a caller may
   open one around a helper call. */
static Region Walk.pooled(Walk &w, int &born) {
  Region pool = w.innermost(<pool>);
  born = 2;
  return pool;
}

static Region Walk.summary_birth(
  Walk &w, String callee, int &born, Region &other) {
  int owner = w.summary(callee).car().int();
  if (owner == 3) {
    born = owner;
    other = w.innermost(<pool>);
    return w.active();
  }
  if (owner & 2) return w.pooled(born);
  if (owner & 1) return w.active();
  born = 0;
  return NULL;
}

/* A closure keeps the first captured value with an owner; an address
   capture keeps the place it names. */
static Region Walk.captured_birth(
  Walk &w, List captures, int &born, Region &other) {
  foreach (Var capture, captures)
    match (capture) case %(capture ? ? ?captured): {
      Var place = _address_of(captured);
      Fact fact = w.fact_of(place is void ? captured : place, NULL);
      if (fact && (fact.born || fact.region || fact.other)) {
        if (fact.born) born = fact.born;
        other = fact.other;
        return fact.region;
      }
    }
  return w.active();
}

/* A summary is `(OWNER SINKS)`, where OWNER is a bit set of scoped (1) and
   pooled (2) returned storage. SINKS is a sorted List of `(INDEX TARGET)`
   pairs and a target is <return>, <result>, <static>, <unknown>, or
   `(param INDEX)`. <result> retains an argument in fresh result storage;
   <return> aliases an argument as the result. */
static List Walk.summary(Walk &w, String callee) {
  match (w.effect(callee)) {
    case %(alloc pool): return %(2 ());
    case %(alloc *): return %(1 ());
    case %(pool): return %(2 ((0 result) (1 result)));
    case %(store): return %(0 ((1 (param 0)) (2 (param 0))));
    case %(summary ?owner ?sinks): return %($owner $sinks);
  }
  w.read(callee);
  Var local = w.summaries[callee];
  return local is void ? %(0 ()) : local;
}

/* Records that the current walk reads the summary of `callee`. */
static void Walk.read(Walk &w, String callee) {
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

/* The argument a callee hands back as its result, when that argument is a
   parameter or region-born, so the result keeps its identity. */
static Fact Walk.returned_argument(Walk &w, Var value, List &?named) {
  List arguments = NULL;
  String callee = _callee_of(value, arguments);
  if (!callee) return NULL;
  List types = _parameter_types(value);
  foreach (List row, w.summary(callee).cadr()) {
    (int index, Var target) = row;
    if (target != <return> || index >= arguments.len()) continue;
    Type type = NULL;
    Fact fact = w.fact_of(_passed(types, arguments, index, type), named);
    if (fact && (fact.param >= 0 || fact.born || fact.region || fact.other))
      return fact;
  }
  return NULL;
}

// facts and regions

/* What is known about the local an expression names or the storage an
   address borrows, through the `Var` wrappers that pass their argument
   through and either arm of `?:`, preferring an arm with a region. */
static Fact Walk.fact_of(Walk &w, Var expression, List &?named) {
  Var inner = _unwrap(expression);
  match (inner) {
    case $source_identifier_content(
        %((!set ?binding (binding ? ?)))): {
      if (named) named = binding;
      Var found = w.facts[binding];
      return found is void ? NULL : found;
    }
    case $source_operator_content(%((!quote &) ?place)):
      return w.borrow(place, named);
    case $source_operator_content(%((!quote ?) ? ?yes ?no)): {
      List yes_name = NULL, no_name = NULL;
      Fact fact = w.fact_of(yes, yes_name);
      Fact other = w.fact_of(no, no_name);
      if (other && (!fact || ((other.region || other.other) &&
                             !fact.region && !fact.other))) {
        fact = other;
        yes_name = no_name;
      }
      if (!fact) return NULL;
      if (named) named = yes_name;
      return fact;
    }
  }
  List arguments = NULL;
  String callee = _callee_of(inner, arguments);
  if (!callee || w.effect(callee) != %(wrap)) return NULL;
  return w.fact_of(arguments.car(), named);
}

/* What is known about a value that is returned, stored, or passed on. A
   local C array there decays to the address of its first element, which
   is the function's own storage. */
static Fact Walk.value_fact(Walk &w, Var value, List &?named) {
  Fact fact = w.fact_of(value, named);
  Type type = _expression_type(value);
  if (!fact || fact.param >= 0 || !type || !type.is_array()) return fact;
  match (_unwrap(value)) case $source_identifier_content(%(*fields)):
    return w.borrow(value, named);
  return fact;
}

/* Accepts `&local` or a `Scope *` local. */
static Fact Walk.slot(Walk &w, Var argument) {
  Fact fact = w.fact_of(_address_of(argument), NULL);
  return fact ? fact : w.fact_of(argument, NULL);
}

static Fact Walk.new_fact(Walk &w, List binding, int param) {
  Fact fact = Scope.calloc(1, sizeof(struct Fact));
  *fact = (struct Fact) {.depth = w.depth, .origin = w.origin, .param = param};
  if (binding) w.facts[binding] = fact;
  return fact;
}

/* The region a Scope local's own storage forms. It ends at `Scope.destroy`
   or at the block end of a deferred destroy; until one is seen, the
   storage can outlive the function, so its values report only a read after
   the end. A caller's or static slot has none. */
static Region Walk.owner(Walk &w, Fact slot) {
  if (!slot || slot.param >= 0) return NULL;
  if (!slot.owner) {
    slot.owner = Scope.calloc(1, sizeof(struct Region));
    *slot.owner = (struct Region) {<local>, slot.depth, slot.origin};
  }
  return slot.owner;
}

/* `fact` now belongs to `region`, or to an owner outside this function. */
static void _move(Fact fact, Region region) {
  fact.region = region;
  fact.other = NULL;
  fact.born = 0;
  fact.param = -1;
}

static Region Walk.open_region(Walk &w, Symbol kind, Fact slot) {
  Region region = Scope.calloc(1, sizeof(struct Region));
  *region = (struct Region) {kind, w.depth, w.origin, 0, slot, w.open};
  return w.open = region;
}

static Region Walk.innermost(Walk &w, Symbol kind) {
  Region region = w.open;
  while (region && (region.closed || region.kind != kind))
    region = region.outer;
  return region;
}

/* The region an allocation goes into: the innermost open scope, or the
   storage of the Scope a pushed slot names. A bare `$auto` Scope local is
   not active, so what is allocated beside it belongs to the region around
   it. */
static Region Walk.active(Walk &w) {
  Region region = w.open;
  while (region && (region.closed ||
         (region.kind != <scope> && region.kind != <slot>)))
    region = region.outer;
  return region && region.kind == <slot> ? w.owner(region.slot) : region;
}

// warnings

static void Walk.warn(
  Walk &w, Symbol code, int origin, String message, List notes) {
  w.warnings.push(
    w.audit ? %(${w.function} $code $origin $message $notes)
            : %($code $origin $message $notes));
}

static List Walk.opened(Walk &w, Region region) {
  List location = w.c.origin_location(region.origin);
  return %("region opened at line ${location.assoc(<line>).int()}");
}

/* How a warning names the value that leaves: a local by its name, and an
   address by the local it borrows from. A callee may hand back the address
   it was given or one inside it. */
static String Walk.subject(Walk &w, Var value, List named, Fact fact) {
  match (source_expression(value)) case $source_any_lambda():
    return "a closure";
  if (!named) return "a fresh allocation";
  String name = %"'${binding_identity_spelling(named)}'";
  Var own = w.facts[named];
  if (own is not void && own.pointer() == fact) return name;
  List arguments = NULL;
  if (_callee_of(value, arguments)) return %"an address from $name";
  match (fact ? fact.place : NULL)
    case $source_identifier_content(%(*fields)):
    return %"the address of $name";
  return %"an address inside $name";
}

// canonical forms the pass reads

/* The parser's empty argument marker represents no arguments. */
static List _source_call(Var value) {
  match (value)
    case ${$called(?callee, *rows)}: {
      match (rows) case %((expr ? ())): rows = NULL;
      return %($callee $rows);
    }
  return NULL;
}

/* A declarator initializer shares the operator but is not an assignment. */
static List _source_assignment(Var value) {
  match (value) {
    case ${$assigned(%(bind *), ?)}: return NULL;
    case ${$assigned(?target, ?stored)}: return %($target $stored);
  }
  return NULL;
}

/* The storage an expression names, without the wrappers that keep it. */
static Var _unwrap(Var value) {
  while (1)
    match (value) {
      case %(expr ? ?inner): value = inner;
      case $source_cast_content(%(? ?inner)): value = inner;
      case $source_content_pattern($grouped, %(?inner)): value = inner;
      default: return value;
    }
}

static List _expression_type(Var value) {
  match (value) case %(expr ?type ?): return type;
  return NULL;
}

static List _binding_of(Var value) {
  match (_unwrap(value)) case $source_identifier_content(
      %((!set ?binding (binding ? ?)))):
    return binding;
  return NULL;
}

/* The place `&place` names, or void. */
static Var _address_of(Var value) {
  match (_unwrap(value))
    case $source_operator_content(%((!quote &) ?place)): return place;
  return void;
}

/* The C name a call names directly, or NULL for a call through a value.
   `arguments` omits the marker an empty argument list parses to. */
static String _callee_of(Var value, List &arguments) {
  match (_source_call(_unwrap(value))) case %(?function ?rows): {
    List name = _binding_of(function);
    arguments = rows;
    return binding_identity_spelling(name);
  }
  return NULL;
}

/* Direct calls retain their callee's resolved signature. */
static List _parameter_types(Var call) {
  match (_source_call(_unwrap(call)))
    case %((expr ((func ?parameters) *) ?) *): return parameters;
  return NULL;
}

/* The argument a call passes at `index`, and the type it passes it as. A
   reference parameter receives the address of the object its argument
   names, as `&object` passes it to a pointer; an argument that is itself
   a reference is already that address. */
static Var _passed(List types, List arguments, int index, Type &type) {
  Var argument = arguments[index];
  Var declared = index < types.len() ? types[index] : void;
  type = declared is <list> ? declared.list() : NULL;
  if (!type.is_reference()) return argument;
  Type given = _expression_type(argument);
  if (given.is_reference()) return argument;
  Type object = cdr(type);
  type = object.reference();
  return %(expr $type (op & $argument));
}

/* A canonical type's values belong to their pool; a container type's
   compound literal allocates. */
static Symbol Walk.value_class(Walk &w, Type type) {
  Symbol tag = w.c.sym.var_tag_for_type(type, NULL);
  if (tag in %(string list symbol)) return <canonical>;
  return tag in %(map array block buffer) ? <container> : 0;
}

/* Whether a destination of `type` copies `value` rather than keeping it: a
   canonical destination, or a `Var`, which boxes a C string as a fresh
   String. */
static int Walk.copies(Walk &w, Type type, Var value) {
  if (w.value_class(type) == <canonical>) return 1;
  if (!type || !w.c.sym.is_var_type(type)) return 0;
  Type source = _expression_type(value);
  return source.is_char_pointer_like();
}

/* Whether `value` or a destination of `type` is a number: an integer,
   floating, or enum type. A number holds no address the program can follow
   without a cast back, so nothing the walk knows moves with it. */
static int Walk.number(Walk &w, Type type, Var value) {
  Type given = _expression_type(value);
  return (type && w.c.sym.resolve_numeric_type(type)) ||
         (given && w.c.sym.resolve_numeric_type(given));
}

// entry points

/** Warns about values that can outlive the region that allocated them.
    `ast` must be the bound and typed top-level unit, before transform
    lowering rewrites its `defer` and region forms. The call adds warnings to
    `c` and does not change `ast`.
*/
void Compiler.check_regions(Compiler c, List ast) {
  Walk w = {.c = c, .summaries = {}, .pending = [], .freed = []};
  w.fixpoint(ast);
  int origin = c.origin;
  foreach (List warning, w.warnings) {
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
  w.fixpoint(fn);
  if (!w.warnings.len()) return;
  (Symbol code, int at, String message, List notes) = w.warnings[0];
  $let(c.origin, at) { c.report_error(code, message, NULL, notes); }
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
  w.fixpoint(ast);
  foreach (List finding, w.warnings) findings.push(finding);
  return w.summaries;
}
