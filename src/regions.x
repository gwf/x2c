/*  regions.x -- values that can outlive the region that allocated them

    Copyright (c) 2026 Gary William Flake.

    A region is a `$scope()` block, a `Scope.retain` and `Scope.release`
    pair, a `$scope(&slot)` push, a `List.pool_retain` bracket, or an `$auto`
    local. The pass reads the typed forms the parser produced, before the
    transform driver rewrites them, so a region is still the call that opens
    it and the `defer` beside it that closes it. It warns when a value born
    in a region reaches storage that outlives the region, when a region is
    opened without its close in the same block, and when a local is read
    after it was freed.

    A function's summary is three facts: it allocates into the caller's
    active region, it returns fresh storage, and where each parameter is
    sunk. Static functions reach a fixpoint inside the unit; a function with
    a non-trivial summary publishes it in the unit's interface contribution,
    where a dependent unit reads it beside the signature. The walk's records
    are ordinary Maps in the translation's own Scope, so a diagnostic's
    canonical text outlives them.

    The warnings name departures from the lexical pattern, not memory safety:
    raw C stores, pointer arithmetic, callbacks, and storage the runtime did
    not allocate stay outside them.
*/

#pragma once
#include "compiler.x"

#pragma private

#include "ast.x"
#include "type.x"

/* The walk state for one function body. `facts` maps a binding to what is
   known about it, `open` holds the regions still open innermost last, and
   `restored` holds the places a `$let` pair puts back before its block ends.
   `allocates`, `fresh`, and `sinks` accumulate this function's summary;
   `report` is zero while the fixpoint runs. A region and a binding's facts
   are both Maps, so one record can hold another. */
typedef struct Walk {
  Compiler compiler;
  Map roles, summaries, external, facts, restored, sinks;
  Array open, parameters;
  int depth, origin, report, allocates, fresh;
} *Walk;

// canonical forms the pass reads

/* Strip the wrappers that do not change which storage an expression names. */
static Var _unwrap(Var value) {
  while (value is <list> && !value.is_nil()) {
    List node = value;
    match (node) {
      case %(expr ? ?inner): value = inner;
      case %(parens ?inner): value = inner;
      case %(cast ? ?inner): value = inner;
      default: return value;
    }
  }
  return value;
}

static List _expression_type(Var value) {
  if (value is not <list> || value.is_nil()) return NULL;
  List node = value;
  match (node) case %(expr ?type ?): return type.list();
  return NULL;
}

static List _binding_of(Var value) {
  Var inner = _unwrap(value);
  if (inner is not <list> || inner.is_nil()) return NULL;
  List node = inner;
  match (node) case %(ident ?name): {
    if (name is not <list>) return NULL;
    List identity = name.list();
    return binding_identity_try_parts(identity, NULL, NULL) ? identity : NULL;
  }
  return NULL;
}

/* The arguments of a call, without the marker an empty list parses to. */
static List _call_arguments(List args) {
  Array out = [];
  foreach (List argument, args.cdr())
    match (argument) {
      case %(expr ? ()): continue;
      default: out.push(argument);
    }
  return out.list_free();
}

/* The C name a call names directly, or NULL for a call through a value. */
static String _callee_of(Var value, List *arguments) {
  Var inner = _unwrap(value);
  if (inner is not <list> || inner.is_nil()) return NULL;
  List node = inner;
  match (node) case %(call ?function (!set ?args (args *))): {
    List name = _binding_of(function);
    if (!name) return NULL;
    if (arguments) *arguments = _call_arguments(args.list());
    return binding_identity_spelling(name);
  }
  return NULL;
}

/* A canonical result is owned by its pool, not by the active region. */
static int _canonical_type(Var type) {
  if (type is <string>) {
    String name = type;
    return name == "String" || name == "List" || name == "Symbol";
  }
  if (type is not <list> || type.is_nil()) return 0;
  foreach (Var part, type.list()) if (_canonical_type(part)) return 1;
  return 0;
}

/* Only these declared types make an untyped composite an owning value. */
static int _declared_container(Var type) {
  if (type is <string>) {
    String name = type;
    return name == "Map" || name == "Array" || name == "Block" ||
           name == "Buffer";
  }
  if (type is not <list> || type.is_nil()) return 0;
  foreach (Var part, type.list()) if (_declared_container(part)) return 1;
  return 0;
}

/* A declarator with a dimension owns its elements, so a store into it is a
   stack store rather than a store through a pointer. */
static int _declares_array(Var modifiers) {
  if (modifiers is not <list> || modifiers.is_nil()) return 0;
  foreach (Var modifier, modifiers.list())
    if (modifier is <list> && !modifier.is_nil())
      match (modifier.list()) case %(dim *): return 1;
  return 0;
}

static Var _statement_expression(Var body) {
  if (body is not <list> || body.is_nil()) return body;
  List node = body;
  match (node) case %(stmnt ?inner): return inner;
  return body;
}

// runtime operations the pass reads by name

static void _install_roles(Map roles, Symbol role, List names) {
  foreach (String name, names) roles[name] = role;
}

/* One table per role: the allocators whose result is born in the active
   region, the slot allocators that name their own region, the pool
   constructors, the exits that end tracking, the `Var` wrappers that pass
   their argument through, and the operations that consume a local. */
static Map _runtime_roles(void) {
  Map roles = {};
  _install_roles(roles, <alloc>,
    %("Scope_malloc" "Scope_calloc" "Scope_memdup" "Scope_malloc_finalized"
      "Scope_realloc" "Block_new" "Bytes_new" "Array_new" "Map_new"
      "Buffer_new" "String_malloc"));
  _install_roles(roles, <slot-alloc>,
    %("Scope_malloc_in" "Scope_calloc_in" "Scope_memdup_in"
      "Scope_malloc_finalized_in"));
  _install_roles(roles, <pool>, %("cons" "Var_cons" "List_cons"));
  _install_roles(roles, <exit>,
    %("Scope_move" "Context_export" "List_promote" "Var_promote"
      "String_promote"));
  _install_roles(roles, <wrapper>,
    %("Var_map" "Var_array" "Var_list" "Var_string" "Map_var" "Array_var"
      "List_var" "String_var" "Block_var" "Var_block" "Buffer_var"
      "Var_buffer"));
  _install_roles(roles, <consume>,
    %("Array_list_free" "Block_free" "Array_free" "Map_free" "Buffer_free"));
  return roles;
}

static Symbol _role(Walk w, String name) {
  Var found = name ? w.roles[name] : void;
  return found is <symbol> ? found.symbol() : 0;
}

// summaries

/* A summary is `(ALLOCATES FRESH (SINKS ...))` with one `(INDEX TARGET ...)`
   row per sunk parameter in index order and sorted targets, so an unchanged
   summary is an identical List and the fixpoint compares by identity. A
   target is <return>, <static>, <unknown>, or `(param INDEX)`. */
static List _summary_rows(Map sinks) {
  Array rows = [];
  foreach (Var (index, targets), sinks) {
    Array names = [];
    foreach (Var target, targets.map().keys()) names.push(target);
    names.sort();
    rows.push(cons(index, names.list_free()));
  }
  rows.sort();
  return rows.list_free();
}

/* Deriving a summary sorts its rows, and every call site reads one, so each
   state keeps its derived form until the next merge changes it. */
static List _summary_of(Map state) {
  Var derived = state[<summary>];
  if (derived is <list>) return derived.list();
  List rows = _summary_rows(state[<sinks>]);
  List summary = %(${state[<allocates>]} ${state[<fresh>]} $rows);
  state[<summary>] = summary;
  return summary;
}

static List _summary_for(Walk w, String name) {
  if (!name) return NULL;
  Var local = w.summaries[name];
  if (local is <map>) return _summary_of(local.map());
  switch (_role(w, name)) {
    case <alloc>: case <slot-alloc>: return %(1 1 ());
  }
  /* One symbol-table lookup per name per unit, not per call site. */
  Var cached = w.external[name];
  if (cached is <list>) return cached.list();
  List published = w.compiler.sym.get(%("region-summary" $name));
  w.external[name] = published;
  return published;
}

static int _allocates_active(Walk w, String name) {
  List summary = _summary_for(w, name);
  return summary ? summary.car().int() : 0;
}

static int _returns_fresh(Walk w, String name) {
  List summary = _summary_for(w, name);
  return summary ? summary.cadr().int() : 0;
}

static List _parameter_sinks(Walk w, String name) {
  List summary = _summary_for(w, name);
  return summary ? summary.caddr().list() : NULL;
}

// region and binding records

static int _flag(Map record, Symbol key) {
  Var value = record[key];
  return value is void ? 0 : value.int();
}

static Map _open_region(Walk w, Symbol kind, List slot) {
  Map region = {};
  region[<kind>] = kind;
  region[<depth>] = w.depth;
  region[<origin>] = w.origin;
  region[<slot>] = slot;
  region[<closed>] = 0;
  region[<lexical>] = 0;
  w.open.push(region);
  return region;
}

static Map _region_of(Map fact) {
  Var value = fact[<region>];
  if (value is not <map>) return NULL;
  Map region = value;
  return region;
}

static Map _innermost(Walk w, List kinds) {
  for (int i = (int) w.open.len() - 1; i >= 0; i--) {
    Map region = w.open[i];
    if (_flag(region, <closed>)) continue;
    if (kinds.contains(region[<kind>])) return region;
  }
  return NULL;
}

static Map _new_fact(Walk w, int parameter) {
  Map fact = {};
  fact[<depth>] = w.depth;
  fact[<param>] = parameter;
  fact[<origin>] = 0;
  fact[<dead>] = 0;
  fact[<exited>] = 0;
  fact[<array>] = 0;
  return fact;
}

static int _parameter_of(Map fact) {
  Var value = fact[<param>];
  return value is void ? -1 : value.int();
}

/* What is known about the local an expression names, following the `Var`
   wrappers that pass their argument through unchanged. */
static Map _fact_of(Walk w, Var expression, List *named) {
  List binding = _binding_of(expression);
  if (binding) {
    if (named) *named = binding;
    Var found = w.facts[binding];
    if (found is not <map>) return NULL;
    Map fact = found;
    return fact;
  }
  List arguments = NULL;
  String callee = _callee_of(expression, &arguments);
  if (callee && _role(w, callee) == <wrapper> && arguments.len() == 1)
    return _fact_of(w, arguments.car(), named);
  return NULL;
}

// diagnostics

static String _origin_note(Compiler c, const char *label, int origin) {
  List location = origin ? c.origin_location(origin) : NULL;
  Var line = location ? location.assoc(<line>) : void;
  if (line is void) return String.new(label);
  return "%s line %d".printf(label, line.int());
}

static void _warn(Walk w, Symbol code, String message, List notes) {
  if (!w.report) return;
  int previous = w.compiler.origin;
  w.compiler.origin = w.origin;
  w.compiler.report_warning(code, message, NULL, notes);
  w.compiler.origin = previous;
}

/* The one escape report: what left, where it was born, and how it left. */
static void _report_escape(Walk w, String subject, Map region, String exit) {
  String born =
    _origin_note(w.compiler, "region opened at", _flag(region, <origin>));
  _warn(w, <region>,
        %"'$subject' can outlive the region it was allocated in",
        %($born ${%"leaves by: $exit"}));
}

static void _report_dead(Walk w, String subject) =>
  _warn(w, <after-free>, %"'$subject' is used after it was freed", NULL);

// the walk

static void _assign(Walk w, Map fact, Var value, Var declared_type);
static void _walk_statement(Walk w, Var node);

/* Where a fresh value an expression produces is born: <active> for the
   innermost open region, <composite> when the declaration's type decides,
   <pool> for a pool bracket, `(slot BINDING)` for an allocation named by a
   Scope slot, or `(region MAP)` when a value passes through unchanged. */
static List _birth_of(Walk w, Var expression) {
  Var inner = _unwrap(expression);
  if (inner is <list> && !inner.is_nil())
    match (inner.list()) {
      case %(array *): return %(active scope);
      case %(composite *): return %(composite scope);
      case %(cache *): return NULL;
    }
  List arguments = NULL;
  String callee = _callee_of(expression, &arguments);
  if (!callee) return NULL;
  switch (_role(w, callee)) {
    case <alloc>: return %(active scope);
    case <pool>: return %(pool pool);
    case <slot-alloc>: {
      List slot = NULL;
      Var first = arguments ? _unwrap(arguments.car()) : void;
      if (first is <list> && !first.is_nil())
        match (first.list()) case %(op (!quote &) ?place):
          slot = _binding_of(place);
      return %((slot $slot) scope);
    }
    case <wrapper>: {
      Map fact = arguments ? _fact_of(w, arguments.car(), NULL) : NULL;
      Map region = fact ? _region_of(fact) : NULL;
      return region ? %((region $region) ${fact[<kind>]}) : NULL;
    }
  }
  if (_returns_fresh(w, callee)) return %(active scope);
  /* A callee that hands one argument back keeps that argument's region. */
  foreach (List row, _parameter_sinks(w, callee)) {
    int index = row.car().int();
    if (!row.cdr().contains(<return>) || index >= (int) arguments.len())
      continue;
    Map fact = _fact_of(w, arguments[index], NULL);
    if (!fact || _flag(fact, <exited>)) continue;
    Map region = _region_of(fact);
    if (region) return %((region $region) ${fact[<kind>]});
  }
  return NULL;
}

/* The region a birth descriptor names, or NULL when the caller owns the
   storage. A bare `$auto` Scope local is not the active region: a value
   allocated while it is in scope still belongs to the enclosing region. */
static Map _region_for(Walk w, List birth) {
  Var where = birth.car();
  if (where == <pool>) return _innermost(w, %(pool));
  if (where == <active> || where == <composite>) {
    Map region = _innermost(w, %(scope slot));
    if (!region || region[<kind>] != <slot>) return region;
    Var slot = region[<slot>];
    return slot is <list> && !slot.is_nil()
         ? _region_for(w, %((slot ${slot.list()}) scope)) : NULL;
  }
  if (where is not <list> || where.is_nil()) return NULL;
  match (where.list()) {
    case %(region ?found): {
      if (found is not <map>) return NULL;
      Map region = found;
      return region;
    }
    case %(slot ?slot): {
      if (slot is not <list> || slot.is_nil()) return NULL;
      Var found = w.facts[slot];
      /* A caller's slot and a static slot both outlive this function. */
      if (found is not <map>) return NULL;
      Map fact = found;
      if (_parameter_of(fact) >= 0) return NULL;
      for (int i = (int) w.open.len() - 1; i >= 0; i--) {
        Map region = w.open[i];
        if (region[<kind>] == <auto> && region[<slot>] == slot &&
            !_flag(region, <closed>)) return region;
      }
      return NULL;
    }
  }
  return NULL;
}

/* A store target names either a local's own storage or storage reached
   through it. `*through` reports which. */
static Map _store_base(Walk w, Var target, int *through) {
  Var inner = _unwrap(target);
  *through = 1;
  if (inner is not <list> || inner.is_nil()) return NULL;
  List node = inner;
  match (node) {
    case %(op (!quote ->) ?base ?): {
      Map fact = _fact_of(w, base, NULL);
      if (fact) return fact;
      fact = _store_base(w, base, through);
      *through = 1;
      return fact;
    }
    case %(op (!quote .) ?base ?): return _store_base(w, base, through);
    case %(op (!quote *) ?base): return _fact_of(w, base, NULL);
    case %(!or (getindex ?base ?) (index ?base ?)): {
      Map fact = _fact_of(w, base, NULL);
      if (!fact) return _store_base(w, base, through);
      *through = !_flag(fact, <array>);
      return fact;
    }
    case %(ident ?): {
      *through = 0;
      return _fact_of(w, target, NULL);
    }
    /* A compound literal is storage of the block the store is in, so it ends
       with that block and reaches nothing outside it. */
    case %(composite *): {
      *through = 0;
      return _new_fact(w, -1);
    }
  }
  return NULL;
}

/* The parameter a call's result aliases, or -1. A callee that hands one
   argument back keeps that argument's identity, so where the result goes is
   decided where the caller binds or returns it. */
static int _alias_parameter(Walk w, Var expression) {
  List arguments = NULL;
  String callee = _callee_of(expression, &arguments);
  if (!callee) return -1;
  foreach (List row, _parameter_sinks(w, callee)) {
    int index = row.car().int();
    if (!row.cdr().contains(<return>) || index >= (int) arguments.len())
      continue;
    Map fact = _fact_of(w, arguments[index], NULL);
    if (fact && _parameter_of(fact) >= 0 && !_flag(fact, <exited>))
      return _parameter_of(fact);
  }
  return -1;
}

/* The sink a store into `base` reaches. A struct local is stack storage; a
   pointer local reaches the storage it was given, and `&x` names `x`. */
static Var _sink_for_base(Walk w, Map base, int through) {
  if (!through) {
    if (base && _parameter_of(base) < 0 && !_flag(base, <origin>))
      return %(local $base);
    return base ? %(heap $base) : %(heap ());
  }
  if (!base) return %(heap ());
  Var points = base[<points>];
  if (points is <map>) return _sink_for_base(w, points.map(), 0);
  if (_parameter_of(base) >= 0 || _flag(base, <origin>))
    return %(heap $base);
  return %(heap ());
}

static void _sink_parameter(Walk w, int index, Var target) {
  Var found = w.sinks[index];
  Map targets = {};
  if (found is <map>) targets = found.map();
  targets[target] = 1;
  w.sinks[index] = targets;
}

/* A value born in `region` reaches `sink`. */
static void _flow_region(Walk w, Map region, Var sink, String subject) {
  if (!region) {
    if (sink == <return>) w.fresh = 1;
    return;
  }
  if (_flag(region, <closed>)) {
    _warn(w, <region>,
          %"'$subject' is used after the region that allocated it ended",
          %(${_origin_note(w.compiler, "region opened at",
                           _flag(region, <origin>))}));
    return;
  }
  if (sink == <return>) {
    _report_escape(w, subject, region, "returned");
    return;
  }
  if (sink == <static>) {
    _report_escape(w, subject, region, "stored into a static");
    return;
  }
  if (sink is not <list> || sink.is_nil()) return;
  match (sink.list()) {
    case %(local ?target): {
      if (target is <map> && _flag(target.map(), <depth>) <
                             _flag(region, <depth>))
        _report_escape(w, subject, region,
                       "assigned to a local declared outside the region");
      return;
    }
    case %(heap ?base): {
      if (base is not <map>) {
        _report_escape(w, subject, region,
                       "stored through an unknown pointer");
        return;
      }
      Map object = base;
      if (_parameter_of(object) >= 0) {
        _report_escape(w, subject, region, "stored through a parameter");
        return;
      }
      Map home = _region_of(object);
      if (home == region) return;
      _report_escape(w, subject, region, home
        ? "stored into an object of another region"
        : "stored into an object of an outer region");
      return;
    }
  }
}

/* `value` flows into `sink`. A parameter records a summary row instead of a
   report: where it goes is this function's contract, not a departure. */
static void _check_flow(Walk w, Var value, Var sink) {
  List named = NULL;
  Map fact = _fact_of(w, value, &named);
  if (!fact) {
    int aliased = _alias_parameter(w, value);
    if (aliased >= 0 && aliased < (int) w.parameters.len())
      fact = w.parameters[aliased];
    if (!fact) {
      List birth = _birth_of(w, value);
      if (!birth) return;
      _flow_region(w, _region_for(w, birth), sink, "a fresh allocation");
      return;
    }
  }
  String subject = named ? binding_identity_spelling(named) : "a value";
  if (_flag(fact, <dead>)) {
    _report_dead(w, subject);
    return;
  }
  int parameter = _parameter_of(fact);
  if (parameter >= 0) {
    if (_flag(fact, <exited>)) return;
    Var target = void;
    if (sink == <return>) target = <return>;
    else if (sink == <static>) target = <static>;
    else if (sink is <list> && !sink.is_nil())
      match (sink.list()) {
        case %(heap ?base): {
          if (base is not <map>) target = <unknown>;
          else {
            Map object = base;
            int index = _parameter_of(object);
            if (index >= 0) target = %(param $index);
            else if (!_region_of(object)) target = <return>;
          }
        }
      }
    if (target is not void) _sink_parameter(w, parameter, target);
    return;
  }
  Map region = _region_of(fact);
  if (!region || _flag(fact, <exited>)) {
    if (sink == <return> && _flag(fact, <origin>)) w.fresh = 1;
    return;
  }
  _flow_region(w, region, sink, subject);
}

/* A canonical target receiving a non-canonical expression copies. */
static int _converts(Var declared_type, Var value) {
  if (!_canonical_type(declared_type)) return 0;
  List type = _expression_type(value);
  return type && !_canonical_type(type);
}

static void _store(Walk w, Var target, Var value);

/* A container store puts its later arguments into the receiver's storage;
   any other call sinks an argument wherever the callee's summary says. */
static void _scan_call(Walk w, String callee, List arguments) {
  if (callee == "setindex" || callee.endswith("_setindex") ||
      callee.endswith("_push") || callee.endswith("_insert")) {
    Map fact = arguments ? _fact_of(w, arguments.car(), NULL) : NULL;
    foreach (Var argument, arguments ? arguments.cdr() : NULL)
      _check_flow(w, argument, fact ? %(heap $fact) : %(heap ()));
    return;
  }
  List rows = _parameter_sinks(w, callee);
  int count = (int) arguments.len();
  foreach (List row, rows) {
    int index = row.car().int();
    if (index >= count) continue;
    Var argument = arguments[index];
    foreach (Var target, row.cdr()) {
      if (target == <static>) _check_flow(w, argument, <static>);
      else if (target == <unknown>) _check_flow(w, argument, %(heap ()));
      else if (target is <list> && !target.is_nil())
        match (target.list()) case %(param ?(int other)): {
          if (other >= count) continue;
          int through = 1;
          Var holder = _unwrap(arguments[other]);
          Map base = NULL;
          if (holder is <list> && !holder.is_nil())
            match (holder.list()) case %(op (!quote &) ?place):
              base = _store_base(w, place, &through);
          if (!base) base = _fact_of(w, arguments[other], NULL);
          _check_flow(w, argument, _sink_for_base(w, base, through));
        }
    }
  }
  if (_allocates_active(w, callee) && !_innermost(w, %(scope slot auto)))
    w.allocates = 1;
}

/* Visit every call, store, and freed local inside one expression. A
   deferred expression runs at block exit, so what it consumes stays live
   for the statements this block still has to walk. */
static void _scan(Walk w, Var value, int deferred) {
  Array pending = $auto([value]), consumed = $auto([]);
  Var root = _unwrap(value);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    List binding = NULL;
    match (node) case %(ident ?): binding = _binding_of(node);
    if (binding) {
      Var found = w.facts[binding];
      if (found is <map> && _flag(found.map(), <dead>)) {
        _report_dead(w, binding_identity_spelling(binding));
        found.map()[<dead>] = 0;
      }
    }
    /* Only the call node itself, so the expression that wraps it does not
       read as a second call to the same callee. */
    List arguments = NULL, String callee = NULL;
    match (node) case %(call *): callee = _callee_of(node, &arguments);
    if (callee && _role(w, callee) == <consume> && arguments) {
      Map fact = _fact_of(w, arguments.car(), NULL);
      if (fact && _flag(fact, <depth>) == w.depth) consumed.push(fact);
    }
    if (callee && _role(w, callee) != <exit> && _role(w, callee) != <wrapper>)
      _scan_call(w, callee, arguments);
    match (node) {
      case %(setindex ?base ? ?stored): {
        Map fact = _fact_of(w, base, NULL);
        _check_flow(w, stored, fact ? %(heap $fact) : %(heap ()));
      }
      case %(op (!quote =) ?stored_target ?stored_value):
        if (current != root) _store(w, stored_target, stored_value);
    }
    for (int i = (int) node.len() - 1; i >= 0; i--) pending.push(node[i]);
  }
  if (deferred) return;
  foreach (Var item, consumed) {
    Map fact = item;
    fact[<dead>] = 1;
  }
}

/* `fact` receives `value`. */
static void _assign(Walk w, Map fact, Var value, Var declared_type) {
  _scan(w, value, 0);
  fact.del(<points>);
  fact.del(<place>);
  Var inner = _unwrap(value);
  if (inner is <list> && !inner.is_nil())
    match (inner.list()) case %(op (!quote &) ?place): {
      int through = 0;
      Map pointee = _fact_of(w, place, NULL);
      if (!pointee) pointee = _store_base(w, place, &through);
      if (pointee) fact[<points>] = pointee;
      fact[<place>] = _unwrap(place);
      fact.del(<region>);
      return;
    }
  List birth = _birth_of(w, value);
  Map source = _fact_of(w, value, NULL);
  int pooled = (source && source[<kind>] == <pool>) ||
               (birth && birth.cadr() == <pool>);
  if (declared_type is not void && !pooled &&
      (_converts(declared_type, value) || _canonical_type(declared_type))) {
    fact.del(<region>);
    return;
  }
  if (source) {
    if (_flag(source, <dead>))
      _report_dead(w, binding_identity_spelling(_binding_of(value)));
    Map inherited = _region_of(source);
    if (inherited) fact[<region>] = inherited;
    else fact.del(<region>);
    Var kind = source[<kind>];
    if (kind is void) fact.del(<kind>);
    else fact[<kind>] = kind;
    fact[<exited>] = _flag(source, <exited>);
    fact[<origin>] = _flag(source, <origin>);
    if (_parameter_of(source) >= 0) fact[<param>] = _parameter_of(source);
    return;
  }
  if (!birth) {
    int aliased = _alias_parameter(w, value);
    if (aliased >= 0) fact[<param>] = aliased;
    fact.del(<region>);
    return;
  }
  /* An untyped composite is a plain struct initializer unless the
     declaration gives it an owning container type. */
  if (birth.car() == <composite> && declared_type is not void &&
      !_declared_container(declared_type)) {
    fact.del(<region>);
    return;
  }
  if ((birth.car() == <active> || birth.car() == <composite>) &&
      !_innermost(w, %(scope slot auto))) w.allocates = 1;
  Map region = _region_for(w, birth);
  if (region) fact[<region>] = region;
  else fact.del(<region>);
  fact[<kind>] = birth.cadr();
  fact[<origin>] = w.origin;
}

static void _store(Walk w, Var target, Var value) {
  if (w.restored.contains(_target_place(w, target))) {
    _scan(w, value, 0);
    return;
  }
  List named = _binding_of(target);
  if (!named) {
    _scan(w, value, 0);
    int through = 0;
    Map base = _store_base(w, target, &through);
    _check_flow(w, value, _sink_for_base(w, base, through));
    return;
  }
  Var found = w.facts[named];
  if (found is not <map>) {
    _check_flow(w, value, <static>);
    return;
  }
  Map fact = found;
  if (_converts(_expression_type(target), value)) {
    fact.del(<region>);
    _scan(w, value, 0);
    return;
  }
  Map source = _fact_of(w, value, NULL);
  if (source && _region_of(source) && !_flag(source, <exited>))
    _check_flow(w, value, %(local $fact));
  _assign(w, fact, value, void);
}

static void _declare(Walk w, Var type, List bindings) {
  foreach (Var item, bindings.cdr()) {
    if (item is not <list> || item.is_nil()) continue;
    match (item.list()) {
      case %(op (!quote =) (bind ?name ?modifiers) ?value): {
        if (name is not <list> ||
            !binding_identity_try_parts(name.list(), NULL, NULL)) continue;
        Map fact = _new_fact(w, -1);
        fact[<array>] = _declares_array(modifiers);
        w.facts[name] = fact;
        _assign(w, fact, value, type);
      }
      case %(bind ?name ?modifiers): {
        if (name is not <list> ||
            !binding_identity_try_parts(name.list(), NULL, NULL)) continue;
        Map fact = _new_fact(w, -1);
        fact[<array>] = _declares_array(modifiers);
        w.facts[name] = fact;
      }
    }
  }
}

/* The place a store target names, seen through the pointer a `$let` holds:
   `*address` and the place `address` was taken from are one storage. */
static Var _target_place(Walk w, Var target) {
  Var inner = _unwrap(target);
  if (inner is <list> && !inner.is_nil())
    match (inner.list()) case %(op (!quote *) ?pointer): {
      Map fact = _fact_of(w, pointer, NULL);
      Var place = fact ? fact[<place>] : void;
      if (place is not void) return place;
    }
  return inner;
}

/* `$let` saves a place, installs a value, and restores the place in a
   defer. A store into a place this block restores is undone before the
   block ends, so it is not an escape. */
static int _note_restored(Walk w, Var body) {
  Var inner = _unwrap(_statement_expression(body));
  if (inner is not <list> || inner.is_nil()) return 0;
  match (inner.list()) case %(op (!quote =) ?target ?): {
    Var restored = _target_place(w, target);
    if (restored == _unwrap(target)) return 0;
    w.restored[restored] = w.depth;
    return 1;
  }
  return 0;
}

/* A `defer` closes the region beside it, owns an `$auto` local, or is an
   ordinary expression that runs at block exit. */
static void _walk_defer(Walk w, Var body) {
  List arguments = NULL;
  String callee = _callee_of(_statement_expression(body), &arguments);
  Map region = NULL;
  if (callee == "Scope_release") region = _innermost(w, %(scope));
  else if (callee == "List_pool_release") region = _innermost(w, %(pool));
  else if (callee == "Scope_pop") region = _innermost(w, %(slot));
  if (region) {
    region[<lexical>] = 1;
    return;
  }
  int owns = callee && arguments && arguments.len() == 1 &&
             (callee.endswith("_cleanup") || callee.endswith("_free") ||
              callee.endswith("_close"));
  List slot = owns ? _binding_of(arguments.car()) : NULL;
  if (!slot) {
    if (!_note_restored(w, body)) _scan(w, body, 1);
    return;
  }
  Map owned = _open_region(w, <auto>, slot);
  owned[<lexical>] = 1;
  Var found = w.facts[slot];
  if (callee == "Scope_cleanup" || found is not <map>) return;
  Map fact = found;
  if (_parameter_of(fact) >= 0) return;
  fact[<region>] = owned;
  fact[<kind>] = <owned>;
}

/* A region opened in one block and closed in another leaves the lexical
   pattern the warnings describe. */
static void _report_unbalanced(Walk w, Map region) {
  int previous = w.origin;
  w.origin = _flag(region, <origin>);
  _warn(w, <unbalanced>,
        "this region has no matching release in the block that opens it",
        %("a region opens and closes in one block"));
  w.origin = previous;
}

static void _walk_block(Walk w, List node) {
  w.depth += 1;
  int opened = (int) w.open.len();
  foreach (Var statement, node.cdr()) _walk_statement(w, statement);
  for (int i = opened; i < (int) w.open.len(); i++) {
    Map region = w.open[i];
    if (_flag(region, <closed>)) continue;
    Symbol kind = region[<kind>];
    if ((kind == <scope> || kind == <pool>) && !_flag(region, <lexical>))
      _report_unbalanced(w, region);
    region[<closed>] = 1;
  }
  while ((int) w.open.len() > opened) w.open.take_last();
  Array expired = [];
  foreach (Var (place, depth), w.restored)
    if (depth.int() == w.depth) expired.push(place);
  foreach (Var place, expired) w.restored.del(place);
  expired.free();
  w.depth -= 1;
}

/* The calls that open, close, or end a region, and the moves that end
   tracking for one value. */
static int _walk_region_call(Walk w, String callee, List arguments) {
  if (callee == "Scope_retain") {
    _open_region(w, <scope>, NULL);
    return 1;
  }
  if (callee == "List_pool_retain") {
    _open_region(w, <pool>, NULL);
    return 1;
  }
  if (callee == "Scope_push") {
    List slot = NULL;
    Var first = arguments ? _unwrap(arguments.car()) : void;
    if (first is <list> && !first.is_nil())
      match (first.list()) case %(op (!quote &) ?place):
        slot = _binding_of(place);
    _open_region(w, <slot>, slot);
    return 1;
  }
  if (callee == "Scope_release" || callee == "List_pool_release" ||
      callee == "Scope_pop") {
    Map region = _innermost(w, callee == "List_pool_release" ? %(pool)
                             : callee == "Scope_pop" ? %(slot) : %(scope));
    if (region) {
      region[<closed>] = 1;
      region[<lexical>] = 1;
    }
    return 1;
  }
  if (callee == "Scope_destroy" && arguments) {
    List slot = _binding_of(arguments.car());
    Var found = slot ? w.facts[slot] : void;
    if (found is <map> && _flag(found.map(), <depth>) == w.depth)
      foreach (Var item, w.open) {
        Map region = item;
        if (region[<slot>] == slot) region[<closed>] = 1;
      }
    return 1;
  }
  if (callee == "Scope_free" && arguments) {
    Map fact = _fact_of(w, arguments.car(), NULL);
    if (fact && _flag(fact, <depth>) == w.depth) fact[<dead>] = 1;
    return 1;
  }
  if (callee == "Scope_move" && arguments && arguments.len() == 2) {
    Map fact = _fact_of(w, arguments.car(), NULL);
    if (!fact) return 1;
    List slot = NULL;
    Var destination = _unwrap(arguments[1]);
    if (destination is <list> && !destination.is_nil())
      match (destination.list()) case %(op (!quote &) ?place):
        slot = _binding_of(place);
    if (!slot) slot = _binding_of(arguments[1]);
    Var found = slot ? w.facts[slot] : void;
    if (found is not <map> || _parameter_of(found.map()) >= 0) {
      fact[<exited>] = 1;
      return 1;
    }
    fact.del(<region>);
    foreach (Var item, w.open) {
      Map region = item;
      if (region[<slot>] == slot) fact[<region>] = region;
    }
    fact[<exited>] = !_region_of(fact);
    return 1;
  }
  if (callee == "List_promote" || callee == "Var_promote" ||
      callee == "String_promote") {
    Map fact = arguments ? _fact_of(w, arguments.car(), NULL) : NULL;
    if (fact) fact[<exited>] = 1;
    return 1;
  }
  return 0;
}

/* A control construct's children run conditionally, so they count as a
   nested block: what they consume does not kill the fall-through. */
static void _walk_child(Walk w, Var child) {
  if (child is not <list> || child.is_nil()) return;
  List node = child;
  match (node) {
    case %((!or block at stmnt declare decl return seq defer case default
                empty goto break continue label if while do for switch try
                with match foreach finally) *):
      _walk_statement(w, node);
    case %((!or expr parens) *): _scan(w, node, 0);
    case %(catchcases *arms): {
      foreach (Var arm, arms) _walk_child(w, arm);
      return;
    }
    default: {
      /* A match case list is a bare sequence of `(PATTERN STATEMENT ...)`
         rows, so its head is a List rather than a production name. */
      if (node.car() is <list>) {
        foreach (Var arm, node) {
          if (arm is not <list> || arm.is_nil()) continue;
          _scan(w, arm.list().car(), 0);
          foreach (Var statement, arm.list().cdr()) _walk_child(w, statement);
        }
        return;
      }
      _scan(w, node, 0);
    }
  }
}

static void _walk_statement(Walk w, Var value) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(at ?(int origin) ?inner): {
      int previous = w.origin;
      w.origin = origin;
      _walk_statement(w, inner);
      w.origin = previous;
      return;
    }
    case %(block *): {
      _walk_block(w, node);
      return;
    }
    case %(seq *statements): {
      foreach (Var statement, statements) _walk_statement(w, statement);
      return;
    }
    case %(defer ?body *): {
      _walk_defer(w, body);
      return;
    }
    case %((!or declare decl) ?type (!set ?bindings (bindings *))): {
      _declare(w, type, bindings.list());
      return;
    }
    case %(return ?type ?result): {
      Map fact = _fact_of(w, result, NULL);
      if ((fact && fact[<kind>] == <pool>) ||
          (!_converts(type, result) && !_canonical_type(type)))
        _check_flow(w, result, <return>);
      _scan(w, result, 0);
      return;
    }
    case %(stmnt ?inner): {
      List arguments = NULL;
      String callee = _callee_of(inner, &arguments);
      if (callee && _walk_region_call(w, callee, arguments)) return;
      Var expression = _unwrap(inner);
      if (expression is <list> && !expression.is_nil())
        match (expression.list()) case %(op (!quote =) ?target ?stored): {
          _store(w, target, stored);
          return;
        }
      _scan(w, inner, 0);
      return;
    }
    case %((!or if while do for switch try with match foreach finally)
           *children): {
      w.depth += 1;
      foreach (Var child, children) _walk_child(w, child);
      w.depth -= 1;
      return;
    }
    case %((!or case default empty goto break continue label) *children): {
      foreach (Var child, children)
        if (child is <list> && !child.is_nil())
          match (child.list()) case %(expr *): _scan(w, child, 0);
      return;
    }
    case %(expr *): {
      _scan(w, node, 0);
      return;
    }
  }
  foreach (Var child, node.cdr()) _walk_child(w, child);
}

// per-unit fixpoint and publication

/* One function row: its C name, whether it is static, its parameter
   bindings in order, and its body. */
static void _collect_functions(Var value, Array found) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(expr *): return;
    case %(function ?type (bind ?name ?modifiers) ?body): {
      String spelling = name is <list> ? binding_identity_spelling(name.list())
                                       : NULL;
      if (!spelling) return;
      Array parameters = [];
      foreach (Var modifier, modifiers)
        if (modifier is <list> && !modifier.is_nil())
          match (modifier.list()) case %(fnmod (params *rows)):
            foreach (Var row, rows)
              match (row.list()) case %(param ? (bind ?parameter ?)): {
                if (parameter is <list> &&
                    binding_identity_try_parts(parameter.list(), NULL, NULL))
                  parameters.push(parameter);
                else parameters.push(NULL);
              }
      Type declared = type;
      found.push(%($spelling ${declared.is_static() ? 1 : 0}
                   ${parameters.list_free()} $body));
      return;
    }
  }
  foreach (Var child, node) _collect_functions(child, found);
}

/* Walk one body, then merge what it found into that function's summary
   state. Reporting is off until the summaries stop changing. */
static void _analyze(
  Walk w, List parameters, Var body, Map state, int report) {
  if (body is not <list> || body.is_nil()) return;
  w.facts = {};
  w.restored = {};
  w.sinks = {};
  w.open = [];
  w.parameters = [];
  w.depth = 0;
  w.origin = 0;
  w.report = report;
  w.allocates = 0;
  w.fresh = 0;
  int index = 0;
  foreach (Var parameter, parameters) {
    Map fact = _new_fact(w, index);
    if (parameter is <list> && !parameter.is_nil()) w.facts[parameter] = fact;
    w.parameters.push(fact);
    index++;
  }
  _walk_statement(w, body);
  if (w.allocates && !_flag(state, <allocates>)) {
    state[<allocates>] = 1;
    state.del(<summary>);
  }
  if (w.fresh && !_flag(state, <fresh>)) {
    state[<fresh>] = 1;
    state.del(<summary>);
  }
  Map sinks = state[<sinks>];
  foreach (Var (parameter_index, targets), w.sinks) {
    Var existing = sinks[parameter_index];
    Map merged = {};
    if (existing is <map>) merged = existing.map();
    foreach (Var target, targets.map().keys()) {
      if (merged.contains(target)) continue;
      merged[target] = 1;
      state.del(<summary>);
    }
    sinks[parameter_index] = merged;
  }
}

/** Warns about values that can outlive the region that allocated them and
    records each function's region summary for this unit's interface.
    `ast` must be the bound and typed top-level unit, before transform
    lowering rewrites its `defer` and region forms. The call adds warnings to
    `compiler` and records a `("region-summary" NAME)` contribution for every
    non-static function whose summary is not empty. It does not change `ast`.
*/
void Compiler.check_regions(Compiler compiler, List ast) {
  Array functions = [];
  defer functions.free();
  _collect_functions(ast, functions);
  if (!functions.len()) return;
  struct Walk state = {compiler, _runtime_roles(), {}, {}, {}, {}, {}, [], [],
                       0, 0, 0, 0, 0};
  Walk w = &state;
  Map summaries = w.summaries;
  foreach (List row, functions) {
    Map empty = {}, Map sinks = {};
    empty[<allocates>] = 0;
    empty[<fresh>] = 0;
    empty[<sinks>] = sinks;
    summaries[row.car()] = empty;
  }
  /* The summaries only grow, so the fixpoint stops as soon as one pass over
     the unit adds nothing. The bound keeps a pathological unit finite. */
  int changed = 1;
  for (int round = 0; changed && round < 20; round++) {
    changed = 0;
    foreach (List row, functions) {
      (Var name, Var is_static, List parameters, Var body) = row;
      (void) is_static;
      Map current = summaries[name];
      List before = _summary_of(current);
      _analyze(w, parameters, body, current, 0);
      if (_summary_of(current) != before) changed = 1;
    }
  }
  foreach (List row, functions) {
    (String name, Var is_static, List parameters, Var body) = row;
    Map current = summaries[name];
    _analyze(w, parameters, body, current, 1);
    List summary = _summary_of(current);
    if (is_static.int() || summary == %(0 0 ())) continue;
    compiler.record_region_summary(name, summary);
  }
}
