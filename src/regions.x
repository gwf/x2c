/*  regions.x -- values that can outlive the region that allocated them

    Copyright (c) 2026 Gary William Flake.

    A region is a `$scope()` block, a `Scope.retain` and `Scope.release`
    pair, a `$scope(&slot)` push, a `String.pool_retain` bracket, an `$auto`
    local, or a Scope local that `Scope.destroy` ends. The pass reads the
    typed forms the parser produced, before the transform driver rewrites
    them, so a region is still the call that opens it and the `defer` beside
    it that closes it. It warns when a value born in a region reaches storage
    that outlives the region, when a region is opened without its close in
    the same block, and when a local is read after it was freed.

    A function's summary is two facts: whether it returns fresh storage, and
    where each parameter is sunk. The unit's functions reach a fixpoint over
    their summaries. A call into another unit has a summary only through the
    runtime table, so a unit's warnings do not depend on which units were
    translated before it.

    The warnings name departures from the lexical pattern. Raw C stores,
    pointer arithmetic, callbacks, and storage the runtime did not allocate
    stay outside them.
*/

#pragma once
#include "compiler.x"

#pragma private

#include "ast.x"
#include "type.x"

/* An open or closed region. `kind` is scope, pool, slot, auto, or local:
   the storage of a Scope local whose end has not been seen. `depth` is the
   block depth it belongs to, `origin` the statement that opened it, `slot`
   the Scope local a pushed slot names, and `outer` the next open region.
   `lexical` records a close in the block that opened it. */
typedef struct Region {
  Symbol kind;
  int depth, origin, closed, lexical;
  struct Fact *slot;
  struct Region *outer;
} *Region;

/* What the walk knows about one local or parameter: the block depth that
   declares it, its parameter index or -1, whether it holds storage born in
   this function, whether a free ended it, the region its value belongs to,
   the region a Scope local's own storage forms, and for a pointer taken
   with `&`, the local and place it names. */
typedef struct Fact {
  int depth, origin, param, born, dead;
  struct Region *region, *owner;
  struct Fact *points;
  List place;
} *Fact;

static Var Fact.var(Fact fact) => Var.new(<fact>, fact);
static Fact Var.fact(Var value) => value.pointer();
protocol Var(Fact);

/* The walk state for one unit. `facts` maps a binding to its Fact, `open`
   is the innermost open region, and `restored` holds the places a `$let`
   puts back before its block ends. `fresh` and `sinks` accumulate the
   current function's summary, `warnings` holds the current round's, and
   `pending` and `freed` are the expression walk's stacks. */
typedef struct Walk {
  Compiler compiler;
  Map summaries, facts, sinks, restored;
  Array warnings, pending, freed;
  Region open;
  int depth, origin, fresh, changed;
} *Walk;

/* The runtime operations the pass reads by C name. (alloc) returns storage
   born in the active region and (alloc slot) in the Scope its first
   argument names; (pool) conses both arguments into pool cells; (store)
   puts its later arguments into its receiver; (wrap) boxes its argument
   unchanged; (free) ends its argument, or owns it from a `defer`; (destroy)
   ends a Scope local's storage; (open KIND) and (close KIND) bracket a
   region; (move) and (exit) hand their argument to another owner. */
static Map runtime = %{
  "Scope_malloc": (alloc),           "Scope_calloc": (alloc),
  "Scope_memdup": (alloc),           "Scope_malloc_finalized": (alloc),
  "Scope_realloc": (alloc),          "String_malloc": (alloc),
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
  "Var_array": (wrap),               "Array_var": (wrap),
  "Var_list": (wrap),                "List_var": (wrap),
  "Var_string": (wrap),              "String_var": (wrap),
  "Var_block": (wrap),               "Block_var": (wrap),
  "Var_buffer": (wrap),              "Buffer_var": (wrap),
  "Array_free": (free),              "Array_list_free": (free),
  "Array_cleanup": (free),           "Map_free": (free),
  "Map_cleanup": (free),             "Block_free": (free),
  "Block_cleanup": (free),           "Bytes_cleanup": (free),
  "Buffer_free": (free),             "Buffer_cleanup": (free),
  "Context_close": (free),           "Context_cleanup": (free),
  "Scope_free": (free),
  "Scope_destroy": (destroy),        "Scope_cleanup": (destroy),
  "Scope_retain": (open scope),      "Scope_release": (close scope),
  "String_pool_retain": (open pool), "String_pool_release": (close pool),
  "Scope_push": (open slot),         "Scope_pop": (close slot),
  "Scope_move": (move),              "Context_export": (exit),
  "List_promote": (exit),            "Var_promote": (exit),
  "String_promote": (exit)
};

// canonical forms the pass reads

/* The storage an expression names, without the wrappers that keep it. */
static Var _unwrap(Var value) {
  while (1)
    match (value) {
      case %((!or expr cast) ? ?inner): value = inner;
      case %(parens ?inner): value = inner;
      default: return value;
    }
}

static List _expression_type(Var value) {
  match (value) case %(expr ?type ?): return type;
  return NULL;
}

static List _binding_of(Var value) {
  match (_unwrap(value)) case %(ident (!set ?binding (binding ? ?))):
    return binding;
  return NULL;
}

/* The place `&place` names, or void. */
static Var _address_of(Var value) {
  match (_unwrap(value)) case %(op (!quote &) ?place): return place;
  return void;
}

/* The C name a call names directly, or NULL for a call through a value.
   `*arguments` omits the marker an empty argument list parses to. */
static String _callee_of(Var value, List *arguments) {
  match (_unwrap(value)) case %(call ?function (args *rows)): {
    List name = _binding_of(function);
    match (rows) case %((expr ? ())): rows = NULL;
    *arguments = rows;
    return binding_identity_spelling(name);
  }
  return NULL;
}

/* A canonical type's values belong to their pool; a container type's
   compound literal allocates. */
static Symbol _class(Walk w, Type type) {
  Symbol tag = w.compiler.sym.var_tag_for_type(type, NULL);
  if (%(string list symbol).contains(tag)) return <canonical>;
  return %(map array block buffer).contains(tag) ? <container> : 0;
}

// regions and facts

static Region _open(Walk w, Symbol kind, Fact slot) {
  Region region = Scope.calloc(1, sizeof(struct Region));
  *region = (struct Region) {kind, w.depth, w.origin, 0, 0, slot, w.open};
  return w.open = region;
}

static Region _innermost(Walk w, Symbol kind) {
  Region region = w.open;
  while (region && (region.closed || region.kind != kind))
    region = region.outer;
  return region;
}

static Fact _fact(Walk w, List binding, int param) {
  Fact fact = Scope.calloc(1, sizeof(struct Fact));
  fact.depth = w.depth;
  fact.origin = w.origin;
  fact.param = param;
  if (binding) w.facts[binding] = fact;
  return fact;
}

/* The region a Scope local's own storage forms. It ends at `Scope.destroy`
   or at the block end of a deferred destroy; until one is seen, the
   storage can outlive the function, so its values report only a read after
   the end. A caller's or static slot has none. */
static Region _owner(Walk w, Fact slot) {
  if (!slot || slot.param >= 0) return NULL;
  if (!slot.owner) {
    slot.owner = Scope.calloc(1, sizeof(struct Region));
    *slot.owner = (struct Region) {<local>, slot.depth, slot.origin};
  }
  return slot.owner;
}

/* The region an allocation goes into: the innermost open scope, or the
   storage of the Scope a pushed slot names. A bare `$auto` Scope local is
   not active, so what is allocated beside it belongs to the region around
   it. */
static Region _active(Walk w) {
  Region region = w.open;
  while (region && (region.closed ||
         (region.kind != <scope> && region.kind != <slot>)))
    region = region.outer;
  return region && region.kind == <slot> ? _owner(w, region.slot) : region;
}

/* `fact` now belongs to `region`, or to an owner outside this function. */
static void _move(Fact fact, Region region) {
  fact.region = region;
  fact.born = 0;
  fact.param = -1;
}

static void _warn(Walk w, Symbol code, int origin, String message,
                  List notes) {
  w.warnings.push(%($code $origin $message $notes));
}

static List _opened(Walk w, Region region) {
  List location = w.compiler.origin_location(region.origin);
  return %("region opened at line ${location.assoc(<line>).int()}");
}

// summaries

/* A summary is `(FRESH SINKS)`, where SINKS is a sorted List of
   `(INDEX TARGET)` pairs and a target is <return>, <static>, <unknown>, or
   `(param INDEX)`. An unchanged summary is the identical List. */
static List _summary(Walk w, String callee) {
  match (runtime[callee]) {
    case %(alloc *): return %(1 ());
    /* A cons cell holds both arguments in storage no region owns. */
    case %(pool): return %(0 ((0 unknown) (1 unknown)));
    case %(store): return %(0 ((1 (param 0)) (2 (param 0))));
  }
  Var local = w.summaries[callee];
  return local is void ? %(0 ()) : local;
}

/* What is known about the local an expression names, through the `Var`
   wrappers that pass their argument through and either arm of `?:`. */
static Fact _fact_of(Walk w, Var expression, List *named) {
  Var inner = _unwrap(expression);
  match (inner) {
    case %(ident (!set ?binding (binding ? ?))): {
      if (named) *named = binding;
      Var found = w.facts[binding];
      return found is void ? NULL : found;
    }
    case %(op (!quote ?) ? ?yes ?no): {
      Fact fact = _fact_of(w, yes, named);
      return fact ? fact : _fact_of(w, no, named);
    }
  }
  List arguments = NULL;
  String callee = _callee_of(inner, &arguments);
  if (!callee || runtime[callee] != %(wrap)) return NULL;
  return _fact_of(w, arguments.car(), named);
}

/* The Scope local a slot argument names: `&local`, or a `Scope *` local. */
static Fact _slot(Walk w, Var argument) {
  Fact fact = _fact_of(w, _address_of(argument), NULL);
  return fact ? fact : _fact_of(w, argument, NULL);
}

/* The argument a callee hands back as its result, when that argument is a
   parameter or region-born, so the result keeps its identity. */
static Fact _returned_argument(Walk w, Var value, List *named) {
  List arguments = NULL;
  String callee = _callee_of(value, &arguments);
  if (!callee) return NULL;
  foreach (List row, _summary(w, callee).cadr()) {
    (int index, Var target) = row;
    if (target != <return> || index >= arguments.len()) continue;
    Fact fact = _fact_of(w, arguments[index], named);
    if (fact && (fact.param >= 0 || fact.region)) return fact;
  }
  return NULL;
}

/* A pool cell is fresh inside a pool bracket, which frees it; outside one
   it belongs to no region. */
static Region _pooled(Walk w, int *born) {
  Region pool = _innermost(w, <pool>);
  *born = pool != NULL;
  return pool;
}

/* The region fresh storage an expression makes is born in, with `*born`
   set; NULL with `*born` set is the caller's active region. `type` is the
   declared type a compound literal initializes, or NULL for its own. */
static Region _birth(Walk w, Var value, Type type, int *born) {
  List arguments = NULL;
  String callee = _callee_of(value, &arguments);
  *born = 1;
  match (callee ? runtime[callee] : void) {
    case %(alloc slot): return _owner(w, _slot(w, arguments.car()));
    case %(alloc): return _active(w);
    case %(pool): return _pooled(w, born);
  }
  match (_unwrap(value)) {
    case %(cons *): return _pooled(w, born);
    /* A closure holds what it captures, so it lives no longer than they. */
    case %(lambda ? (captures *captures) *): {
      foreach (Var capture, captures)
        match (capture) case %(capture ? ? ?captured): {
          Fact fact = _fact_of(w, captured, NULL);
          if (fact && fact.region) return fact.region;
        }
      return _active(w);
    }
    case %((!or array map) *): return _active(w);
    case %(composite *)
      if (_class(w, type ? type : _expression_type(value)) == <container>):
      return _active(w);
  }
  if (callee && _summary(w, callee).car().int()) return _active(w);
  *born = 0;
  return NULL;
}

// flows

/* `value` reaches `sink` through a destination of `type`: <return>,
   <static>, <local> for the local `target`, or <heap> for the storage
   `target` reaches, or an unknown pointer when `target` is NULL. A canonical
   destination copies. A parameter adds the sink to this function's summary;
   any other value reports when its region can end first. Returns whether
   it reported. */
static int _flow(Walk w, Var value, Type type, Symbol sink, Fact target) {
  List named = NULL;
  Fact fact = _fact_of(w, value, &named);
  if (!fact) fact = _returned_argument(w, value, &named);
  int born = 0;
  Region region = fact ? fact.region : _birth(w, value, NULL, &born);
  if (!fact && !born) return 0;
  if (_class(w, type) == <canonical> && (!region || region.kind != <pool>))
    return 0;
  if (fact && fact.param >= 0) {
    Var row = sink;
    if (sink == <heap>) {
      if (!target) row = <unknown>;
      else if (target.param >= 0) row = %(param ${target.param});
      else row = target.region ? void : <return>;
    }
    if (sink != <local> && row is not void)
      w.sinks[%(${fact.param} $row)] = 1;
    return 0;
  }
  if (!region) {
    if (sink == <return> && (fact ? fact.born : born)) w.fresh = 1;
    return 0;
  }
  String subject = named ? %"'${binding_identity_spelling(named)}'"
                         : "a fresh allocation";
  if (region.closed) {
    _warn(w, <region>, w.origin,
          %"$subject is used after the region that allocated it ended",
          _opened(w, region));
    return 1;
  }
  if (region.kind == <local>) return 0;
  String exit = NULL;
  switch (sink) {
    case <return>: exit = "returned"; break;
    case <static>: exit = "stored into a static"; break;
    case <local>:
      if (target.depth < region.depth)
        exit = "assigned to a local declared outside the region";
      break;
    default:
      if (!target) exit = "stored through an unknown pointer";
      else if (target.param >= 0) exit = "stored through a parameter";
      else if (target.region == region) exit = NULL;
      else if (target.region) exit = "stored into an object of another region";
      else exit = "stored into an object of an outer region";
  }
  if (!exit) return 0;
  _warn(w, <region>, w.origin,
        %"$subject can outlive the region it was allocated in when $exit",
        _opened(w, region));
  return 1;
}

/* The local a store target's storage belongs to. `*through` is zero when
   the store writes the local itself and one when it writes storage the
   local reaches. */
static Fact _base(Walk w, Var place, int *through) {
  *through = 1;
  match (_unwrap(place)) {
    case %(op (!quote ->) ?base ?): {
      Fact fact = _fact_of(w, base, NULL);
      if (!fact) fact = _base(w, base, through);
      *through = 1;
      return fact;
    }
    case %(op (!quote .) ?base ?): return _base(w, base, through);
    case %(op (!quote *) ?base): return _fact_of(w, base, NULL);
    case %((!or getindex index) (!set ?base (expr ?type ?)) ?): {
      Fact fact = _fact_of(w, base, NULL);
      if (!fact) return _base(w, base, through);
      /* A C array local owns its elements. */
      Type declared = type;
      *through = !declared.is_array();
      return fact;
    }
    case %(ident ?): {
      *through = 0;
      return _fact_of(w, place, NULL);
    }
    /* A compound literal is storage of the block the store is in. */
    case %(composite *): {
      *through = 0;
      return _fact(w, NULL, -1);
    }
  }
  return NULL;
}

/* The sink a store through `base` reaches. A struct local is its own
   storage; a pointer local reaches the storage it was given, and a pointer
   taken with `&x` reaches `x`. */
static Symbol _sink_of(Fact base, int through, Fact *target) {
  if (through && base && base.points) {
    base = base.points;
    through = 0;
  }
  int own = base && base.param < 0 && !base.born;
  *target = through && own ? NULL : base;
  return !through && own ? <local> : <heap>;
}

/* A call sinks each argument where the callee's summary says. */
static void _scan_call(Walk w, String callee, List arguments) {
  int count = arguments.len();
  foreach (List row, _summary(w, callee).cadr()) {
    (int index, Var target) = row;
    if (index >= count) continue;
    Var argument = arguments[index];
    if (target == <static>) _flow(w, argument, NULL, <static>, NULL);
    else if (target == <unknown>) _flow(w, argument, NULL, <heap>, NULL);
    else match (target) case %(param ?other): {
      if (other.int() >= count) continue;
      Var holder = arguments[other.int()];
      int through = 1;
      Fact base = _base(w, _address_of(holder), &through), object = NULL;
      if (!base) base = _fact_of(w, holder, NULL);
      Symbol sink = _sink_of(base, through, &object);
      _flow(w, argument, NULL, sink, object);
    }
  }
}

// the walk

/* Visit every read, call, and nested store in one expression, left to
   right and without recursion, so a long operator chain fits the stack. A
   free ends its local after the whole expression, and a deferred
   expression runs at block exit, so what it frees stays live for the
   statements this block still has to walk. */
static void _scan(Walk w, Var value, int deferred) {
  Var root = _unwrap(value);
  int base = w.pending.len(), mark = w.freed.len();
  w.pending.push(value);
  while ((int) w.pending.len() > base) {
    Var node = w.pending.take_last();
    match (node) {
      case %(expr ? ?inner): w.pending.push(inner);
      case %(ident (!set ?binding (binding ? ?))): {
        Var found = w.facts[binding];
        if (found is void) break;
        Fact fact = found;
        if (!fact.dead) break;
        String name = binding_identity_spelling(binding);
        _warn(w, <after-free>, w.origin,
              %"'$name' is used after it was freed", NULL);
        fact.dead = 0;
      }
      case %(op (!quote =) ?target ?stored) if (node != root): {
        _store(w, target, stored);
        w.pending.push(target);
      }
      case %(call ? ?args): {
        List arguments = NULL;
        String callee = _callee_of(node, &arguments);
        match (callee ? runtime[callee] : void) {
          case %((!or exit wrap)): break;
          case %(free): {
            Fact fact = _fact_of(w, arguments.car(), NULL);
            if (fact && fact.depth == w.depth) w.freed.push(fact);
          }
          default: if (callee) _scan_call(w, callee, arguments);
        }
        w.pending.push(args);
      }
      /* A List literal's cells outlive every region. */
      case %(cons ?head ?tail): {
        _flow(w, head, NULL, <heap>, NULL);
        w.pending.push(tail);
        w.pending.push(head);
      }
      case %(*children):
        for (int i = children.len() - 1; i >= 0; i--)
          w.pending.push(children[i]);
    }
  }
  while ((int) w.freed.len() > mark) {
    Fact fact = w.freed.take_last();
    if (!deferred) fact.dead = 1;
  }
}

/* `fact` receives `value`, declared or stored as `type`. A store of a
   region-born local into a local declared outside that region reports
   once, and the receiving local does not carry the region further. */
static void _assign(Walk w, Fact fact, Var value, Type type, int store) {
  _scan(w, value, 0);
  Var place = _address_of(value);
  Fact source = _fact_of(w, value, NULL);
  if (!source) source = _returned_argument(w, value, NULL);
  int born = 0;
  Region region = source ? source.region : _birth(w, value, type, &born);
  int kept = source || born;
  if (kept && _class(w, type) == <canonical>)
    kept = region && region.kind == <pool>;
  if (kept && store && source && region)
    kept = !_flow(w, value, type, <local>, fact);
  fact.dead = 0;
  fact.points = NULL;
  fact.place = NULL;
  if (place is not void) {
    int through = 0;
    fact.points = _fact_of(w, place, NULL);
    if (!fact.points) fact.points = _base(w, place, &through);
    fact.place = _unwrap(place);
    kept = 0;
  }
  fact.region = kept ? region : NULL;
  fact.born = kept && (source ? source.born : born);
  fact.param = kept && source ? source.param : -1;
}

/* The place a store target names, seen through the pointer a `$let` holds:
   `*address` and the place `address` was taken from are one storage. */
static Var _target_place(Walk w, Var target) {
  Var inner = _unwrap(target);
  match (inner) case %(op (!quote *) ?pointer): {
    Fact fact = _fact_of(w, pointer, NULL);
    if (fact && fact.place) return fact.place;
  }
  return inner;
}

static void _store(Walk w, Var target, Var value) {
  if (w.restored.contains(_target_place(w, target))) {
    _scan(w, value, 0);
    return;
  }
  Type type = _expression_type(target);
  List named = _binding_of(target);
  Var found = named ? w.facts[named] : void;
  if (found is not void) {
    _assign(w, found, value, type, 1);
    return;
  }
  _scan(w, value, 0);
  if (named) {
    _flow(w, value, type, <static>, NULL);
    return;
  }
  int through = 0;
  Fact object = NULL;
  Symbol sink = _sink_of(_base(w, target, &through), through, &object);
  _flow(w, value, type, sink, object);
}

static void _declare(Walk w, List bindings) {
  Map types = w.compiler.semantic_binding_facts();
  foreach (Var item, bindings)
    match (item) {
      case %(op (!quote =) (bind (!set ?name (binding ? ?)) ?) ?value):
        _assign(w, _fact(w, name, -1), value, types[%(type $name)], 0);
      case %(bind (!set ?name (binding ? ?)) ?): _fact(w, name, -1);
    }
}

/* `$let` saves a place, installs a value, and restores the place in a
   defer. A store into a place this block restores is undone before the
   block ends, so it is not an escape. */
static int _note_restored(Walk w, Var body) {
  match (body) case %(stmnt ?expression):
    match (_unwrap(expression)) case %(op (!quote =) ?target ?): {
      Var place = _target_place(w, target);
      if (place == _unwrap(target)) return 0;
      w.restored = w.restored.copy();
      w.restored[place] = 1;
      return 1;
    }
  return 0;
}

/* A `defer` beside a region closes it at block exit, a deferred free or
   destroy owns its local until then, and any other deferred expression
   runs at block exit. */
static void _walk_defer(Walk w, Var body) {
  List arguments = NULL;
  String callee = NULL;
  match (body) case %(stmnt ?expression):
    callee = _callee_of(expression, &arguments);
  Fact fact = _fact_of(w, arguments.car(), NULL);
  match (callee ? runtime[callee] : void) {
    case %(close ?kind): {
      Region region = _innermost(w, kind);
      if (region) region.lexical = 1;
      return;
    }
    case %(free) if (fact && fact.param < 0): {
      fact.region = _open(w, <auto>, NULL);
      fact.region.lexical = 1;
      return;
    }
    case %(destroy): {
      Region owner = _owner(w, fact);
      if (!owner || owner.kind != <local>) return;
      owner.kind = <auto>;
      owner.lexical = 1;
      owner.outer = w.open;
      w.open = owner;
      return;
    }
  }
  if (!_note_restored(w, body)) _scan(w, body, 1);
}

/* A region-opening or region-ending call in statement position. Reports
   whether `callee` is one. */
static int _walk_region_call(Walk w, String callee, List arguments) {
  Fact fact = _fact_of(w, arguments.car(), NULL);
  match (runtime[callee]) {
    case %(open ?kind): _open(w, kind, _slot(w, arguments.car()));
    case %(close ?kind): {
      Region region = _innermost(w, kind);
      if (!region) break;
      /* A close in a nested block runs on some paths, so the region stays
         open for the statements after that block. */
      region.lexical = 1;
      region.closed = region.depth == w.depth;
    }
    case %(destroy): if (fact && fact.depth == w.depth && fact.owner)
      fact.owner.closed = 1;
    case %(move): if (fact) _move(fact, _owner(w, _slot(w, arguments.cadr())));
    case %(exit): if (fact) _move(fact, NULL);
    default: return 0;
  }
  return 1;
}

/* Close the regions a block opened, oldest first. */
static void _close_to(Walk w, Region region, Region outer) {
  if (region == outer) return;
  _close_to(w, region.outer, outer);
  if (!region.closed && !region.lexical &&
      (region.kind == <scope> || region.kind == <pool>))
    _warn(w, <unbalanced>, region.origin,
          "this region has no matching release in the block that opens it",
          %("a region opens and closes in one block"));
  region.closed = 1;
}

static void _walk_block(Walk w, List statements) {
  Region outer = w.open;
  Map restored = w.restored;
  w.depth += 1;
  foreach (Var statement, statements) _walk(w, statement);
  _close_to(w, w.open, outer);
  w.open = outer;
  w.restored = restored;
  w.depth -= 1;
}

static void _walk(Walk w, Var node) {
  match (node) {
    case %(at ?origin ?inner): {
      int outer = w.origin;
      w.origin = origin;
      _walk(w, inner);
      w.origin = outer;
    }
    case %(block *statements): _walk_block(w, statements);
    case %(seq *statements):
      foreach (Var statement, statements) _walk(w, statement);
    case %(defer ?body *): _walk_defer(w, body);
    case %((!or declare decl) ? (bindings *bindings)): _declare(w, bindings);
    case %(return ?type ?result): {
      _scan(w, result, 0);
      _flow(w, result, type, <return>, NULL);
    }
    case %(stmnt ?expression): {
      List arguments = NULL;
      String callee = _callee_of(expression, &arguments);
      if (callee && _walk_region_call(w, callee, arguments)) break;
      match (_unwrap(expression)) {
        case %(op (!quote =) ?target ?value): _store(w, target, value);
        default: _scan(w, expression, 0);
      }
    }
    /* A control construct's children run conditionally, so they count as a
       nested block: what they free does not end the fall-through. */
    case %((!or if while do for switch try with match foreach finally)
           *children): {
      w.depth += 1;
      foreach (Var child, children) _walk(w, child);
      w.depth -= 1;
    }
    case %(catchcases ?rows): _walk(w, rows);
    case %((!or expr parens case) *): _scan(w, node, 0);
    /* Match and catch arms are bare `(PATTERN STATEMENT ...)` rows. */
    case %((*) *): foreach (List row, node) {
      _scan(w, row.car(), 0);
      foreach (Var statement, row.cdr()) _walk(w, statement);
    }
  }
}

// per-unit fixpoint

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
static void _analyze(Walk w, List function) {
  (String name, List parameters, Var body) = function;
  (int fresh, List sinks) = w.summaries[name];
  w.facts = {};
  w.sinks = {};
  w.restored = {};
  w.open = NULL;
  w.depth = w.origin = 0;
  w.fresh = fresh;
  foreach (Var row, sinks) w.sinks[row] = 1;
  int index = 0;
  foreach (List parameter, parameters) _fact(w, parameter, index++);
  _walk(w, body);
  Array rows = [];
  foreach (Var row, w.sinks.keys()) rows.push(row);
  List summary = %(${w.fresh} ${rows.sort().list_free()}),
       previous = w.summaries[name];
  if (summary == previous) return;
  w.summaries[name] = summary;
  w.changed = 1;
}

/** Warns about values that can outlive the region that allocated them.
    `ast` must be the bound and typed top-level unit, before transform
    lowering rewrites its `defer` and region forms. The call adds warnings to
    `c` and does not change `ast`.
*/
void Compiler.check_regions(Compiler c, List ast) {
  Array functions = $auto([]);
  _collect_functions(ast, functions);
  struct Walk walk = {
    .compiler = c, .summaries = {}, .pending = [], .freed = []};
  Walk w = &walk;
  foreach (List function, functions) w.summaries[function.car()] = %(0 ());
  /* Summaries only grow, so a round that changes none walked every body
     against final summaries, and its warnings are the unit's. */
  do {
    w.changed = 0;
    w.warnings = [];
    foreach (List function, functions) _analyze(w, function);
  } while (w.changed);
  int origin = c.origin;
  foreach (List warning, w.warnings) {
    (Symbol code, int at, String message, List notes) = warning;
    c.origin = at;
    c.report_warning(code, message, NULL, notes);
  }
  c.origin = origin;
}
