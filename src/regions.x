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

#pragma private

#include "ast.x"
#include "comptime.x"
#include "type.x"

/* An open or closed region. `kind` is scope, pool, slot, auto, local: the
   storage of a Scope local whose end has not been seen, or frame: the
   storage of the function's locals and parameters. `depth` is the
   block depth it belongs to, `origin` the statement that opened it, `slot`
   the Scope local a pushed slot names, and `outer` the next open region. */
typedef struct Region {
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
typedef struct Fact {
  int depth, origin, param, born;
  Symbol dead, ending;
  struct Region *region, *other, *owner;
  struct Fact *points;
  List place;
} *Fact;

static Var Fact.var(Fact fact) => Var.new(<fact>, fact);
static Fact Var.fact(Var value) => value.pointer();
protocol Var(Fact);

/* The walk state for one unit. `facts` maps a binding to its Fact, `open`
   is the innermost open region, `frame` is the region of the function's
   own storage, and `restored` holds the places a `$let` or another `defer`
   puts back before its block ends. `fresh` and `sinks` accumulate the
   current function's summary, `warnings` holds the current round's, and
   `pending` and `freed` are the expression walk's stacks. `meta` is set
   while a `meta` definition is walked. */
typedef struct Walk {
  Compiler compiler;
  Map summaries, facts, sinks, restored;
  Array warnings, pending, freed;
  Region open, frame;
  int depth, origin, fresh, changed, meta;
} *Walk;

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
   `arguments` omits the marker an empty argument list parses to. */
static String _callee_of(Var value, List &arguments) {
  match (_unwrap(value)) case %(call ?function (args *rows)): {
    List name = _binding_of(function);
    match (rows) case %((expr ? ())): rows = NULL;
    arguments = rows;
    return binding_identity_spelling(name);
  }
  return NULL;
}

/* A canonical type's values belong to their pool; a container type's
   compound literal allocates. */
static Symbol _class(Walk w, Type type) {
  Symbol tag = w.compiler.sym.var_tag_for_type(type, NULL);
  if (tag in %(string list symbol)) return <canonical>;
  return tag in %(map array block buffer) ? <container> : 0;
}

/* Whether a destination of `type` copies `value` rather than keeping it: a
   canonical destination, or a `Var`, which boxes a C string as a fresh
   String. */
static int _copies(Walk w, Type type, Var value) {
  if (_class(w, type) == <canonical>) return 1;
  if (!type || !w.compiler.sym.is_var_type(type)) return 0;
  Type source = _expression_type(value);
  return source &&
         (source.match(%((!or (dim *) (!quote *)) char)) ||
          source.match(%((!or (dim *) (!quote *)) const char)));
}

// regions and facts

static Region _open(Walk w, Symbol kind, Fact slot) {
  Region region = Scope.calloc(1, sizeof(struct Region));
  *region = (struct Region) {kind, w.depth, w.origin, 0, slot, w.open};
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
  *fact = (struct Fact) {.depth = w.depth, .origin = w.origin, .param = param};
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
  fact.other = NULL;
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

/* A summary is `(OWNER SINKS)`, where OWNER is a bit set of scoped (1) and
   pooled (2) returned storage. SINKS is a sorted List of `(INDEX TARGET)`
   pairs and a target is <return>, <result>, <static>, <unknown>, or
   `(param INDEX)`. <result> retains an argument in fresh result storage;
   <return> aliases an argument as the result. */
static List _summary(Walk w, String callee) {
  match (runtime[callee]) {
    case %(alloc pool): return %(2 ());
    case %(alloc *): return %(1 ());
    case %(pool): return %(2 ((0 result) (1 result)));
    case %(store): return %(0 ((1 (param 0)) (2 (param 0))));
    case %(summary ?owner ?sinks): return %($owner $sinks);
  }
  Var local = w.summaries[callee];
  return local is void ? %(0 ()) : local;
}

/* What is known about the local an expression names or the storage an
   address borrows, through the `Var` wrappers that pass their argument
   through and either arm of `?:`, preferring an arm with a region. */
static Fact _fact_of(Walk w, Var expression, List *named) {
  Var inner = _unwrap(expression);
  match (inner) {
    case %(ident (!set ?binding (binding ? ?))): {
      if (named) *named = binding;
      Var found = w.facts[binding];
      return found is void ? NULL : found;
    }
    case %(op (!quote &) ?place): return _borrow(w, place, named);
    case %(op (!quote ?) ? ?yes ?no): {
      List yes_name = NULL, no_name = NULL;
      Fact fact = _fact_of(w, yes, &yes_name);
      Fact other = _fact_of(w, no, &no_name);
      if (other && (!fact || ((other.region || other.other) &&
                             !fact.region && !fact.other))) {
        fact = other;
        yes_name = no_name;
      }
      if (named && fact) *named = yes_name;
      return fact;
    }
  }
  List arguments = NULL;
  String callee = _callee_of(inner, arguments);
  if (!callee || !Compiler.region_wrapper(callee)) return NULL;
  return _fact_of(w, arguments.car(), named);
}

/* What is known about a value that is returned, stored, or passed on. A
   local C array there decays to the address of its first element, which
   is the function's own storage. */
static Fact _value_fact(Walk w, Var value, List *named) {
  Fact fact = _fact_of(w, value, named);
  Type type = _expression_type(value);
  if (!fact || fact.param >= 0 || !type || !type.is_array()) return fact;
  match (_unwrap(value)) case %(ident *): return _borrow(w, value, named);
  return fact;
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
  String callee = _callee_of(value, arguments);
  if (!callee) return NULL;
  foreach (List row, _summary(w, callee).cadr()) {
    (int index, Var target) = row;
    if (target != <return> || index >= arguments.len()) continue;
    Fact fact = _fact_of(w, arguments[index], named);
    if (fact && (fact.param >= 0 || fact.born || fact.region || fact.other))
      return fact;
  }
  return NULL;
}

/* A pool value remains pooled even without a local bracket: a caller may
   open one around a helper call. */
static Region _pooled(Walk w, int &born) {
  Region pool = _innermost(w, <pool>);
  born = 2;
  return pool;
}

/* The region fresh storage an expression makes is born in, with `born`
   set; NULL with `born` set is the caller's active region. A mixed
   Scope/Pool result keeps its Pool region in `other`. `type` is the
   declared type a compound literal initializes, or NULL for its own. */
static Region _birth(Walk w, Var value, Type type, int &born,
                     Region &other) {
  List arguments = NULL;
  String callee = _callee_of(value, arguments);
  born = 1;
  other = NULL;
  match (callee ? runtime[callee] : void) {
    case %(alloc slot): return _owner(w, _slot(w, arguments.car()));
    case %(alloc pool): return _pooled(w, born);
    case %(alloc final) if (w.meta): return w.frame;
    case %(alloc *): return _active(w);
    case %(pool): return _pooled(w, born);
  }
  match (_unwrap(value)) {
    case %(cons *): return _pooled(w, born);
    /* A closure holds what it captures, so it lives no longer than they. A
       reference capture moves its local into a cell of the active region,
       so the closure holds the local's value, not its address. */
    case %(lambda ? (captures *captures) *): {
      foreach (Var capture, captures)
        match (capture) case %(capture ? ? ?captured): {
          Var place = _address_of(captured);
          Fact fact = _fact_of(w, place is void ? captured : place, NULL);
          if (fact && (fact.born || fact.region || fact.other)) {
            if (fact.born) born = fact.born;
            other = fact.other;
            return fact.region;
          }
        }
      return _active(w);
    }
    case %((!or array map) *): return _active(w);
    case %(composite *)
      if (_class(w, type ? type : _expression_type(value)) == <container>):
      return _active(w);
  }
  if (callee) {
    int owner = _summary(w, callee).car().int();
    if (owner == 3) {
      born = owner;
      other = _innermost(w, <pool>);
      return _active(w);
    }
    if (owner & 2) return _pooled(w, born);
    if (owner & 1) return _active(w);
  }
  born = 0;
  return NULL;
}

// flows

/* `value` reaches `sink` through a destination of `type`: <return>,
   <static>, <local> for the local `target`, or <heap> for the storage
   `target` reaches, or an unknown pointer when `target` is NULL. A canonical
   destination copies. A parameter adds the sink to this function's summary;
   any other value reports when either possible owner can end first.
   Returns whether it reported. */
static int _flow_region(Walk w, Var value, Type type, Symbol sink,
                        Fact target, Fact fact, List named, Region region,
                        int born, int report) {
  if (_copies(w, type, value) && !(born & 2) &&
      (!region || region.kind != <pool>))
    return 0;
  if (!region) {
    if (sink == <return>) w.fresh |= born;
    return 0;
  }
  String subject = _subject(w, value, named, fact);
  if (region.closed) {
    if (report)
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
      /* Every region a function opens ends before its own storage. */
      else if (target.region)
        exit = region == w.frame ? NULL
                                 : "stored into an object of another region";
      else exit = "stored into an object of an outer region";
  }
  if (!exit) return 0;
  if (report) {
    if (region == w.frame) {
      String message =
        %"$subject can outlive the local storage it points into when $exit";
      _warn(w, <region>, w.origin,
            message,
            %("local storage ends when the function returns"));
    }
    else
      _warn(w, <region>, w.origin,
            %"$subject can outlive the region it was allocated in when $exit",
            _opened(w, region));
  }
  return 1;
}

static int _flow(Walk w, Var value, Type type, Symbol sink, Fact target) {
  match (_unwrap(value)) case %(op (!quote ?) ? ?yes ?no):
    return _flow(w, yes, type, sink, target) ||
           _flow(w, no, type, sink, target);
  List named = NULL;
  Fact fact = _value_fact(w, value, &named);
  if (!fact) fact = _returned_argument(w, value, &named);
  int born = 0;
  Region other = NULL;
  Region region = fact ? fact.region
                       : _birth(w, value, NULL, born, other);
  if (!fact && !born) return 0;
  if (fact && fact.param >= 0) {
    Var row = sink;
    if (sink == <heap>) {
      if (!target) row = <unknown>;
      else if (target.param >= 0) row = %(param ${target.param});
      else row = target.born ? <result>
             : (target.region || target.other) ? void : <return>;
    }
    if (sink != <local> && row is not void)
      w.sinks[%(${fact.param} $row)] = 1;
    return 0;
  }
  if (fact) {
    born = fact.born;
    other = fact.other;
  }
  int reported = 0;
  for (int choice = 0; choice < (born == 3 ? 2 : 1); choice++) {
    Region owner = choice ? other : region;
    int kind = born;
    if (born == 3) kind = choice ? 2 : 1;
    if (owner && target && target.born == 3 && sink == <heap>) {
      struct Fact pooled = *target;
      pooled.region = target.other;
      pooled.born = 2;
      reported |= _flow_region(w, value, type, sink, target, fact,
                               named, owner, kind, !reported);
      reported |= _flow_region(w, value, type, sink, &pooled, fact,
                               named, owner, kind, !reported);
    }
    else
      reported |= _flow_region(w, value, type, sink, target, fact,
                               named, owner, kind, !reported);
  }
  return reported;
}

/* How a warning names the value that leaves: a local by its name, and an
   address by the local it borrows from. A callee may hand back the address
   it was given or one inside it. */
static String _subject(Walk w, Var value, List named, Fact fact) {
  match (_unwrap(value)) case %(lambda *): return "a closure";
  if (!named) return "a fresh allocation";
  String name = %"'${binding_identity_spelling(named)}'";
  Var own = w.facts[named];
  if (own is not void && own.pointer() == fact) return name;
  List arguments = NULL;
  if (_callee_of(value, arguments)) return %"an address from $name";
  match (fact ? fact.place : NULL) case %(ident *):
    return %"the address of $name";
  return %"an address inside $name";
}

/* The local a store target's storage belongs to. `through` is zero when
   the store writes the local itself and one when it writes storage the
   local reaches. */
static Fact _base(Walk w, Var place, int &through) {
  through = 1;
  match (_unwrap(place)) {
    case %(op (!quote ->) ?base ?): {
      Fact fact = _fact_of(w, base, NULL);
      if (!fact) fact = _base(w, base, through);
      through = 1;
      return fact;
    }
    case %(op (!quote .) ?base ?): return _base(w, base, through);
    case %(op (!quote *) ?base): return _fact_of(w, base, NULL);
    case %((!or getindex index) (!set ?base (expr ?type ?)) ?): {
      Fact fact = _fact_of(w, base, NULL);
      if (!fact) return _base(w, base, through);
      /* A C array local owns its elements; a parameter is a pointer. */
      Type declared = type;
      through = !declared.is_array() || fact.param >= 0;
      return fact;
    }
    case %(ident ?): {
      through = 0;
      return _fact_of(w, place, NULL);
    }
    /* A compound literal is storage of the block the store is in. */
    case %(composite *): {
      through = 0;
      return _fact(w, NULL, -1);
    }
  }
  return NULL;
}

/* The storage `&place` borrows. A local, a parameter, or a compound
   literal is this function's own storage; a place reached through a
   pointer is storage that pointer holds. `*named` is the local the place
   is part of. */
static Fact _borrow(Walk w, Var place, List *named) {
  int through = 0;
  Fact base = _fact_of(w, place, named);
  if (!base) base = _base(w, place, through);
  if (!base) return NULL;
  if (named && !*named) *named = _root(place);
  Fact borrow = _fact(w, NULL, -1);
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
      case %(ident (!set ?binding (binding ? ?))): return binding;
      case %(op ? ?base *): place = base;
      case %((!or getindex index) ?base ?): place = base;
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

/* The declared parameter types of the function a call names, so an
   argument that a canonical parameter converts by copying is not stored. */
static List _parameter_types(Var call) {
  match (_unwrap(call)) case %(call (expr ((func ?types) *) ?) *):
    return types;
  return NULL;
}

/* A call sinks each argument where the callee's summary says. */
static void _scan_call(Walk w, Var call, String callee, List arguments) {
  int count = arguments.len();
  List types = _parameter_types(call);
  foreach (List row, _summary(w, callee).cadr()) {
    (int index, Var target) = row;
    if (index >= count) continue;
    Var argument = arguments[index];
    Var declared = index < types.len() ? types[index] : void;
    Type type = declared is <list> ? declared.list() : NULL;
    if (target == <static>) _flow(w, argument, type, <static>, NULL);
    else if (target == <unknown>) _flow(w, argument, type, <heap>, NULL);
    else if (target == <result>) {
      int born = 0;
      Region other = NULL;
      Region region = _birth(w, call, NULL, born, other);
      struct Fact result = {
        .param = -1, .born = born, .region = region, .other = other};
      _flow(w, argument, type, <heap>, &result);
    }
    else match (target) case %(param ?other): {
      if (other.int() >= count) continue;
      Var holder = arguments[other.int()];
      int through = 1;
      Fact base = _base(w, _address_of(holder), through), object = NULL;
      if (!base) base = _fact_of(w, holder, NULL);
      Symbol sink = _sink_of(base, through, object);
      _flow(w, argument, type, sink, object);
    }
  }
}

// the walk

/* An argument that ends its storage. `op` names a Scope operation, which
   reports storage no Scope allocator returned: a literal, the function's
   own storage, or a pooled value. The local it names is dead after the
   expression, `how` recording whether it was freed or moved. */
static void _end(Walk w, Var argument, String op, Symbol how) {
  List named = NULL;
  Fact storage = _value_fact(w, argument, &named);
  int literal = 0;
  match (_unwrap(argument)) case %(literal *): literal = 1;
  if (op && (literal || (storage &&
      (storage.region == w.frame || storage.born == 2)))) {
    String subject = literal ? "a literal"
                             : _subject(w, argument, named, storage);
    _warn(w, <bad-free>, w.origin,
          %"$op is given $subject, which no Scope allocator returned",
          %("only Scope.malloc, calloc, memdup, and realloc storage can be"
            "freed or reallocated"));
  }
  Fact fact = _fact_of(w, argument, NULL);
  if (!fact || fact.depth != w.depth) return;
  fact.ending = how;
  w.freed.push(fact);
}

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
        String ended = fact.dead == <moved> ? "Scope.realloc moved it"
                                            : "it was freed";
        _warn(w, <after-free>, w.origin,
              %"'$name' is used after $ended", NULL);
        fact.dead = 0;
      }
      case %(op (!quote =) ?target ?stored) if (node != root): {
        _store(w, target, stored);
        w.pending.push(target);
      }
      case %(call ? ?args): {
        List arguments = NULL;
        String callee = _callee_of(node, arguments);
        match (callee ? runtime[callee] : void) {
          case %((!or exit wrap)): break;
          case %(free): _end(w, arguments.car(), NULL, <freed>);
          case %(free scope):
            _end(w, arguments.car(), "Scope.free", <freed>);
          case %(alloc moved):
            _end(w, arguments.car(), "Scope.realloc", <moved>);
          default: if (callee) _scan_call(w, node, callee, arguments);
        }
        w.pending.push(args);
      }
      /* A statement expression declares locals of its own. */
      case %((!or declare decl) ?specifiers (bindings *bindings)):
        _declare(w, specifiers, bindings);
      /* A List literal retains its values in the active Pool. */
      case %(cons ?head ?tail): {
        int born = 0;
        Region other = NULL;
        Region region = _birth(w, node, NULL, born, other);
        struct Fact result = {.param = -1, .born = born, .region = region};
        _flow(w, head, NULL, <heap>, &result);
        _flow(w, tail, NULL, <heap>, &result);
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
    if (!deferred) fact.dead = fact.ending;
  }
}

/* A free ends its local for the statements that follow it on the same path.
   Where that path ends, nothing it freed is known to be freed any more. */
static void _revive(Walk w) {
  foreach (Var known, w.facts.iter()) {
    Fact fact = known;
    fact.dead = 0;
  }
}

/* `fact` receives `value`, declared or stored as `type`. A store of a
   region-born local into a local declared outside that region reports
   once, and the receiving local does not carry the region further. */
static void _assign(Walk w, Fact fact, Var value, Type type, int store) {
  _scan(w, value, 0);
  Fact source = _value_fact(w, value, NULL);
  if (!source) source = _returned_argument(w, value, NULL);
  int born = 0;
  Region other = source ? source.other : NULL;
  Region region = source ? source.region
                         : _birth(w, value, type, born, other);
  int owners = source ? source.born : born;
  int kept = source || born;
  if (kept && _copies(w, type, value)) {
    if (owners == 3) {
      region = other;
      other = NULL;
      owners = 2;
    }
    else kept = (owners & 2) || (region && region.kind == <pool>);
  }
  if (kept && store && source && (region || other))
    kept = !_flow(w, value, type, <local>, fact);
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
  /* A store through a pointer reads the pointer. */
  if (!_binding_of(target)) _scan(w, target, 0);
  if (_target_place(w, target) in w.restored) {
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
  Fact object = NULL, base = _base(w, target, through);
  /* A field or element of file-scope storage is that storage. */
  if (!base && !through && _root(target)) {
    _flow(w, value, type, <static>, NULL);
    return;
  }
  Symbol sink = _sink_of(base, through, object);
  _flow(w, value, type, sink, object);
}

/* A static or extern local is not the function's storage, so the walk
   treats it as file-scope state. */
static void _declare(Walk w, Var specifiers, List bindings) {
  Map types = w.compiler.semantic_binding_facts();
  if (<static> in specifiers || <extern> in specifiers) {
    foreach (List item, bindings)
      match (item) case %(op = (bind ?name ?) ?value): {
        _scan(w, value, 0);
        _flow(w, value, types[%(type $name)], <static>, NULL);
      }
    return;
  }
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

/* A place a `defer` writes is put back when its block ends, so a store
   into it after the `defer` is not an escape. */
static void _note_deferred_stores(Walk w, Var node) {
  match (node) {
    case %(op (!quote =) ?target ?): w.restored[_unwrap(target)] = 1;
    case %(*children):
      foreach (Var child, children) _note_deferred_stores(w, child);
  }
}

/* A `defer` beside a region closes it at block exit, a deferred free or
   destroy owns its local until then, and any other deferred expression
   runs at block exit. */
static void _walk_defer(Walk w, Var body) {
  List arguments = NULL;
  String callee = NULL;
  match (body) case %(stmnt ?expression):
    callee = _callee_of(expression, arguments);
  Fact fact = _fact_of(w, arguments.car(), NULL);
  match (callee ? runtime[callee] : void) {
    case %(close ?): return;
    case %(free *) if (fact && fact.param < 0): {
      fact.region = _open(w, <auto>, NULL);
      return;
    }
    case %(destroy): {
      Region owner = _owner(w, fact);
      if (!owner || owner.kind != <local>) return;
      owner.kind = <auto>;
      owner.outer = w.open;
      w.open = owner;
      return;
    }
  }
  if (_note_restored(w, body)) return;
  w.restored = w.restored.copy();
  _note_deferred_stores(w, body);
  _scan(w, body, 1);
}

/* A region-opening or region-ending call in statement position. Reports
   whether `callee` is one. */
static int _walk_region_call(Walk w, String callee, List arguments) {
  Fact fact = _fact_of(w, arguments.car(), NULL);
  match (runtime[callee]) {
    case %(open ?kind): _open(w, kind, _slot(w, arguments.car()));
    case %(close ?kind): {
      Region region = _innermost(w, kind);
      /* A close in a nested block runs on some paths, so the region stays
         open for the statements after that block. */
      if (region) region.closed = region.depth == w.depth;
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
    case %((!or declare decl) ?specifiers (bindings *bindings)):
      _declare(w, specifiers, bindings);
    case %(return ?type ?result): {
      _scan(w, result, 0);
      _flow(w, result, type, <return>, NULL);
      _revive(w);
    }
    /* A jump leaves the statements after it to another path, and a label is
       where that path arrives, so neither carries forward what the path
       before it freed. */
    case %((!or goto label) *): _revive(w);
    case %(stmnt ?expression): {
      List arguments = NULL;
      String callee = _callee_of(expression, arguments);
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
      Map restored = w.restored;
      w.depth += 1;
      foreach (Var child, children) _walk(w, child);
      w.depth -= 1;
      w.restored = restored;
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

/* The functions `ast` defines, walked to their final summaries. */
static void _fixpoint(Walk w, List ast, Array functions) {
  w.frame = Scope.calloc(1, sizeof(struct Region));
  w.frame.kind = <frame>;
  _collect_functions(ast, functions);
  foreach (List function, functions)
    if (w.summaries[function.car()] is void)
      w.summaries[function.car()] = %(0 ());
  /* Summaries only grow, so a round that changes none walked every body
     against final summaries, and its warnings are the unit's. */
  do {
    w.changed = 0;
    w.warnings = [];
    foreach (List function, functions) _analyze(w, function);
  } while (w.changed);
}

/** Warns about values that can outlive the region that allocated them.
    `ast` must be the bound and typed top-level unit, before transform
    lowering rewrites its `defer` and region forms. The call adds warnings to
    `c` and does not change `ast`.
*/
void Compiler.check_regions(Compiler c, List ast) {
  struct Walk walk = {
    .compiler = c, .summaries = {}, .pending = [], .freed = []};
  Walk w = &walk;
  Array functions = $auto([]);
  _fixpoint(w, ast, functions);
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
    in `meta_regions`; a definition whose lowering the process already
    cached takes the summary recorded with it.
*/
void Compiler.check_meta_regions(Compiler c, List fn) {
  match (fn) case %(function ? (bind (binding ? ?(String name)) *) ?): {
    List checked = c.lowered_meta_regions(fn);
    if (checked) {
      c.meta_regions[name] = checked;
      return;
    }
    /* A replaced definition starts again from an empty summary. */
    c.meta_regions[name] = %(0 ());
  }
  struct Walk walk = {
    .compiler = c, .summaries = c.meta_regions, .pending = [], .freed = [],
    .meta = 1};
  Walk w = &walk;
  Array functions = $auto([]);
  _fixpoint(w, fn, functions);
  if (!w.warnings.len()) return;
  (Symbol code, int at, String message, List notes) = w.warnings[0];
  $let(c.origin, at) { c.report_error(code, message, NULL, notes); }
}

/** Reports whether the runtime table proves the lifetime effects of the
    native function `name`. */
int Compiler.has_region_row(String name) => name in runtime;
