/*  values.x -- storage identities and allocation owners */

module Var Fact.var(Fact fact) => Var.new(<p48>, fact);
module Fact Var.fact(Var value) => value.pointer();
static protocol Var(Fact) as void *;

// store targets

module Fact _base(Walk &w, Var place, int &through) {
  through = 1;
  match (_unwrap(place)) {
    case %(op (!quote ->) ?base ?): {
      Fact fact = _fact_of(w, base, NULL);
      if (!fact) fact = _base(w, base, through);
      through = 1;
      return fact;
    }
    case %(op (!quote .) ?base ?):
      return _base(w, base, through);
    case %(op (!quote *) ?base):
      return _fact_of(w, base, NULL);
    case $($indexed(%(!set ?base (expr ?type ?)), ?)):
      return _indexed_base(w, base, type, through);
    case %(getindex (!set ?base (expr ?type ?)) ?):
      return _indexed_base(w, base, type, through);
    case %(ident ?binding): {
      through = 0;
      return _fact_of(w, place, NULL);
    }
    /* A compound literal is storage of the block the store is in. */
    case %(composite *): {
      through = 0;
      return _new_fact(w, NULL, -1);
    }
  }
  return NULL;
}

/* The local a store target's storage belongs to. `through` is zero when
   the store writes the local itself and one when it writes storage the
   local reaches. */
static Fact _indexed_base(Walk &w, List base, Type type, int &through) {
  Fact fact = _fact_of(w, base, NULL);
  if (!fact) return _base(w, base, through);
  /* A C array local owns its elements; a parameter is a pointer. */
  through = !type.is_array() || fact.param >= 0;
  return fact;
}

/* The storage `&place` borrows. A local, a parameter, or a compound
   literal is this function's own storage; a place reached through a
   pointer is storage that pointer holds. `named` is the local the place
   is part of. */
static Fact _borrow(Walk &w, Var place, List &?named) {
  int through = 0;
  Fact base = _fact_of(w, place, named);
  if (!base) base = _base(w, place, through);
  if (!base) return NULL;
  if (named)
    if (!named) named = _root(place);
  Fact borrow = _new_fact(w, NULL, -1);
  borrow.points = base;
  borrow.place = _unwrap(place);
  borrow.region = through ? base.region : w.frame;
  borrow.other = through ? base.other : NULL;
  borrow.born = through ? base.born : 0;
  if (through && !base.empty) borrow.acquired = _acquired(base);
  if (through) borrow.param = base.param;
  return borrow;
}

/* The local a place is part of, or NULL. */
module List _root(Var place) {
  while (1)
    match (_unwrap(place)) {
      case %(ident (!set ?binding (binding ? ?))): return binding;
      case %(op ? ?base *): place = base;
      case $($indexed(?base, ?selector)): place = base;
      case %(getindex ?base ?): place = base;
      default: return NULL;
    }
}

/* The sink a store through `base` reaches. A struct local is its own
   storage; a pointer local reaches the storage it was given, and a pointer
   taken with `&x` reaches `x`. */
module Symbol _sink_of(Fact base, int through, Fact &target) {
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
module Region _birth(
  Walk &w, Var value, Type type, int &born, Region &other,
  Acquired &acquired) {
  List arguments = NULL;
  String callee = _callee_of(value, arguments);
  born = 1;
  other = NULL;
  acquired = NULL;
  match (callee ? _effect(w, callee) : void) {
    case %(alloc slot): return _allocate_in(w, _slot(w, arguments.car()));
    case %(alloc pool): return _pooled(w, born);
    case %(alloc final) if (w.meta): return w.frame;
    case %(alloc *): return _active(w);
    case %(pool): return _pooled(w, born);
  }
  match (_under_casts(value)) {
    /* A closure holds what it captures, so it lives no longer than they. A
       reference capture moves its local into a cell of the active region,
       so the closure holds the local's value, not its address. */
    case $lambda_captured(?body, *captures, *params):
      return _captured_birth(w, captures, born, other, acquired);
  }
  match (_unwrap(value)) {
    case %(cons *): return _pooled(w, born);
    case $($array_value(*items)):
      return _active(w);
    case $($map_value(*rows)):
      return _active(w);
    case %(composite *)
      if (_value_class(w, type ? type : _expression_type(value)) ==
          <container>):
      return _active(w);
  }
  if (callee) return _summary_birth(w, callee, born, other);
  born = 0;
  return NULL;
}

/* A pool value remains pooled even without a local bracket: a caller may
   open one around a helper call. */
static Region _pooled(Walk &w, int &born) {
  Region pool = _innermost(w, <pool>);
  born = 2;
  return pool;
}

static Region _summary_birth(
  Walk &w, String callee, int &born, Region &other) {
  int owner = _summary(w, callee).car().int();
  if (owner == 3) {
    born = owner;
    other = _innermost(w, <pool>);
    return _active(w);
  }
  if (owner & 2) return _pooled(w, born);
  if (owner & 1) return _active(w);
  born = 0;
  return NULL;
}

/* A closure keeps the first captured value with an owner; an address
   capture keeps the place it names. */
static Region _captured_birth(
  Walk &w, List captures, int &born, Region &other, Acquired &acquired) {
  foreach (List capture in captures)
    match (capture) case %(capture ? ? ?captured): {
      Var place = _address_of(captured);
      Fact fact = _fact_of(w, place is void ? captured : place, NULL);
      if (fact && (fact.born || fact.region || fact.other ||
                   _cleanup(fact.acquired))) {
        if (fact.born) born = fact.born;
        other = fact.other;
        acquired = fact.acquired;
        return fact.region;
      }
    }
  return _active(w);
}

/* The argument a callee hands back as its result, when that argument is a
   parameter or region-born, so the result keeps its identity. */
module Fact _returned_argument(Walk &w, Var value, List &?named) {
  List arguments = NULL;
  String callee = _callee_of(value, arguments);
  if (!callee) return NULL;
  List types = _parameter_types(value);
  foreach (List row in _summary(w, callee).cadr()) {
    (int index, Var target) = row;
    if (target != <return> || index >= arguments.len()) continue;
    Type type = NULL;
    Fact fact = _fact_of(w, _passed(types, arguments, index, type), named);
    if (fact && (fact.param >= 0 || fact.born || fact.region || fact.other ||
                 _cleanup(fact.acquired)))
      return fact;
  }
  return NULL;
}

// facts and regions

/* What is known about the local an expression names or the storage an
   address borrows, through the `Var` wrappers that pass their argument
   through and either arm of `?:`, preferring an arm with a region. */
module Fact _fact_of(Walk &w, Var expression, List &?named) {
  Var inner = _unwrap(expression);
  match (inner) {
    case %(ident (!set ?binding (binding ? ?))): {
      if (named) named = binding;
      Var found = w.facts[binding];
      return found is void ? NULL : found;
    }
    case %(op (!quote &) ?place):
      return _borrow(w, place, named);
    case %(op (!quote ?) ? ?yes ?no): {
      List yes_name = NULL, no_name = NULL;
      Fact fact = _fact_of(w, yes, yes_name);
      Fact other = _fact_of(w, no, no_name);
      if (other && (!fact ||
          ((other.region || other.other || _cleanup(other.acquired)) &&
           !fact.region && !fact.other && !_cleanup(fact.acquired)))) {
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
  if (!callee || _effect(w, callee) != %(wrap)) return NULL;
  return _fact_of(w, arguments.car(), named);
}

/* What is known about a value that is returned, stored, or passed on. A
   local C array there decays to the address of its first element, which
   is the function's own storage. */
module Fact _value_fact(Walk &w, Var value, List &?named) {
  Fact fact = _fact_of(w, value, named);
  Type type = _expression_type(value);
  if (!fact || fact.param >= 0 || !type || !type.is_array()) return fact;
  match (_unwrap(value)) case %(ident *fields):
    return _borrow(w, value, named);
  return fact;
}

/* Accepts `&local` or a `Scope *` local. */
module Fact _slot(Walk &w, Var argument) {
  Fact fact = _fact_of(w, _address_of(argument), NULL);
  if (fact) return fact;
  fact = _fact_of(w, argument, NULL);
  return fact && fact.points ? fact.points : fact;
}

module Fact _new_fact(Walk &w, List binding, int param) {
  Fact fact = xmalloc(sizeof(struct Fact));
  *fact = (struct Fact) {.depth = w.depth, .origin = w.origin, .param = param};
  if (binding) w.facts[binding] = fact;
  return fact;
}

module Acquired _acquired(Fact fact) {
  if (!fact.acquired)
    fact.acquired = xcalloc(1, sizeof(struct Acquired));
  return fact.acquired;
}

module Region _cleanup(Acquired acquired) =>
  acquired ? acquired.cleanup : NULL;

module int _closed(Region region) {
  if (!region) return 0;
  Region cleanup = _cleanup(region.acquired);
  return region.closed || (cleanup && cleanup.closed);
}

/* A known empty handle has no identity to share with another empty slot. */
module int _empty(Var value) {
  match (_unwrap(value)) {
    case %(ident (binding ? "NULL")): return 1;
    case %(literal ?ltype ?text): {
      Type type = ltype;
      unsigned long long number;
      return type.integer_literal_magnitude(text, number) && !number;
    }
  }
  return 0;
}

/* The region a Scope local's own storage forms. It ends at `Scope.destroy`
   or at the block end of a deferred destroy; until one is seen, the
   storage can outlive the function, so its values report only a read after
   the end. A caller's or static slot has none. */
module Region _owner(Walk &w, Fact slot) {
  if (!slot || slot.param >= 0) return NULL;
  if (!slot.owner) {
    slot.owner = xmalloc(sizeof(struct Region));
    *slot.owner = (struct Region) {<local>, slot.depth, slot.origin};
  }
  return slot.owner;
}

/* An allocation fills an empty Scope slot. A deferred destroy may already
   own that slot, but a copy of its earlier NULL did not acquire this Scope. */
module Region _allocate_in(Walk &w, Fact slot) {
  Region owner = _owner(w, slot);
  if (owner) {
    slot.empty = 0;
    owner.acquired = _acquired(slot);
  }
  return owner;
}

/* `fact` now belongs to `region`, or to an owner outside this function. */
module void _move(Fact fact, Region region) {
  fact.region = region;
  fact.other = NULL;
  fact.born = 0;
  fact.param = -1;
}

module Region _open_region(Walk &w, Symbol kind, Fact slot) {
  Region region = xmalloc(sizeof(struct Region));
  *region = (struct Region) {kind, w.depth, w.origin, 0, slot, w.open};
  return w.open = region;
}

module Region _innermost(Walk &w, Symbol kind) {
  Region region = w.open;
  while (region && (region.closed || region.kind != kind))
    region = region.outer;
  return region;
}

/* The region an allocation goes into: the innermost open scope, or the
   storage of the Scope a pushed slot names. A Scope local with initializer
   auto is not active, so what is allocated beside it belongs to the region
   around it. */
static Region _active(Walk &w) {
  Region region = w.open;
  while (region && (region.closed ||
         (region.kind != <scope> && region.kind != <slot>)))
    region = region.outer;
  return region && region.kind == <slot>
    ? _allocate_in(w, region.slot) : region;
}

// canonical forms the pass reads

/* Removes casts and parentheses, retaining the final typed expression. */
module Var _under_casts(Var value) {
  while (1) {
    match (value) {
      case %(expr ? (parens ?inner)): value = inner;
      case %(expr ? (cast ? ?inner)): value = inner;
      case %(parens ?inner): value = inner;
      case %(cast ? ?inner): value = inner;
      default: return value;
    }
  }
}

/* The parser's empty argument marker represents no arguments. */
module List _source_call(Var value) {
  match (value)
    case $($called(?callee, *rows)): {
      if (rows ~= %((expr ? ()))) rows = NULL;
      return $(callee, rows);
    }
  return NULL;
}

/* A declarator initializer shares the operator but is not an assignment. */
module List _source_assignment(Var value) {
  match (value) {
    case $($assigned(%(bind *), ?)): return NULL;
    case $($assigned(?target, ?stored)): return $(target, stored);
  }
  return NULL;
}

/* The storage an expression names, without the wrappers that keep it. */
module Var _unwrap(Var value) {
  while (1)
    match (value) {
      case %(expr ? ?inner): value = inner;
      case %(cast ? ?inner): value = inner;
      case $Macro.content_pattern($grouped, %(?inner)): value = inner;
      default: return value;
    }
}

module List _expression_type(Var value) {
  match (value) case %(expr ?type ?): return type;
  return NULL;
}

module List _binding_of(Var value) {
  match (_unwrap(value)) case %(ident (!set ?binding (binding ? ?))):
    return binding;
  return NULL;
}

/* The place `&place` names, or void. */
module Var _address_of(Var value) {
  match (_unwrap(value))
    case %(op (!quote &) ?place): return place;
  return void;
}

/* The C name a call names directly, or NULL for a call through a value.
   `arguments` omits the marker an empty argument list parses to. */
module String _callee_of(Var value, List &arguments) {
  match (_source_call(_unwrap(value))) case %(?function ?rows): {
    List name = _binding_of(function);
    arguments = rows;
    return Ast.binding_spelling(name);
  }
  return NULL;
}

/* Direct calls retain their callee's resolved signature. */
module List _parameter_types(Var call) {
  match (_source_call(_unwrap(call)))
    case %((expr ((func ?parameters) *) ?) *): return parameters;
  return NULL;
}

/* The argument a call passes at `index`, and the type it passes it as. A
   reference parameter receives the address of the object its argument
   names, as `&object` passes it to a pointer; an argument that is itself
   a reference is already that address. */
module Var _passed(List types, List arguments, int index, Type &type) {
  Var argument = arguments[index];
  Var declared = types[index];
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
static Symbol _value_class(Walk &w, Type type) {
  Symbol tag = w.c.sym.var_tag_for_type(type, NULL);
  if (tag in %(string list symbol)) return <canonical>;
  return tag in %(map array block buffer) ? <container> : 0;
}

/* Whether a destination of `type` copies `value` rather than keeping it: a
   canonical destination, or a `Var`, which boxes a C string as a fresh
   String. */
module int _copies(Walk &w, Type type, Var value) {
  if (_value_class(w, type) == <canonical>) return 1;
  if (!type || !w.c.sym.is_var_type(type)) return 0;
  Type source = _expression_type(value);
  return source.is_char_pointer_like();
}

/* Whether `value` or a destination of `type` is a number: an integer,
   floating, or enum type. A number holds no address the program can follow
   without a cast back, so nothing the walk knows moves with it. */
module int _number(Walk &w, Type type, Var value) {
  Type given = _expression_type(value);
  return (type && w.c.sym.resolve_numeric_type(type)) ||
         (given && w.c.sym.resolve_numeric_type(given));
}
