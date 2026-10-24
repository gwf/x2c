/*  walk.x -- statement and expression lifetime effects */

/* Findings from statement and expression traversal. */

static macro Stmt $warn.region_bad_free(
  Expr $w, Expr $site, Expr $op, Expr $subject) =>
  _warn(
    $w, <bad-free>, $site,
    %"${$op} is given ${$subject}, which no Scope allocator returned",
    %("only Scope.malloc, calloc, memdup, and realloc storage can be"
      "freed or reallocated"));

static macro Stmt $warn.region_read_ended(Expr $w, Expr $site, Expr $name) =>
  _warn(
    $w, <region>, $site,
    %"'${$name}' is read after its owning region ended", NULL);

static macro Stmt $warn.region_after_free(
  Expr $w, Expr $site, Expr $name, Expr $ended) =>
  _warn(
    $w, <after-free>, $site, %"'${$name}' is used after ${$ended}", NULL);

static macro Expression $reason.region_moved() => "Scope.realloc moved it";
static macro Expression $reason.region_freed() => "it was freed";

// statements

module void _walk(Walk &w, Var node) {
  match (node) {
    case %(at ?origin ?inner): _walk_at(w, origin, inner);
    case $source_block_content(%(*statements)):
      _walk_block(w, statements);
    case %(seq *statements): _walk_sequence(w, statements);
    case $deferred(?body): _walk_defer(w, body);
    /* A lowered defer keeps its environment and capture records. */
    case %(defer ?body ?environment ?callback ?records ?written):
      _walk_defer(w, body);
    case %((!or declare decl) ?specifiers (bindings *bindings)):
      _declare(w, specifiers, bindings);
    case $return_value(?result):
      _walk_return(w, source_return_type(node), result);
    /* A jump leaves the statements after it to another path, and a label is
       where that path arrives, so neither carries forward what the path
       before it freed. */
    case %((!or goto label) *): _revive(w);
    case $expression_statement(?expression): _walk_expression(w, expression);
    /* A control construct's children run conditionally, so they count as a
       nested block: what they free does not end the fall-through. */
    case $source_conditional_statement():
      _walk_conditional(w, node.cdr());
    case %(catchcases ?rows): _walk(w, rows);
    case %((!or expr case) *): _scan(w, node, 0);
    case $source_content_pattern($grouped, %(?inner)):
      _scan(w, node, 0);
    /* Match and catch arms are bare `(PATTERN STATEMENT ...)` rows. */
    case %((*) *): _walk_rows(w, node);
  }
}

static void _walk_at(Walk &w, int origin, Var inner) {
  int outer = w.origin;
  w.origin = origin;
  _walk(w, inner);
  w.origin = outer;
}

static void _walk_block(Walk &w, List statements) {
  Region outer = w.open;
  Map restored = w.restored;
  w.depth += 1;
  foreach (List statement in statements) _walk(w, statement);
  _close_to(w, w.open, outer);
  w.open = outer;
  w.restored = restored;
  w.depth -= 1;
}

/* Closes oldest first. */
static void _close_to(Walk &w, Region region, Region outer) {
  if (region == outer) return;
  _close_to(w, region.outer, outer);
  region.closed = 1;
}

static void _walk_sequence(Walk &w, List statements) {
  foreach (List statement in statements) _walk(w, statement);
}

static void _walk_return(Walk &w, Type type, Var result) {
  _scan(w, result, 0);
  _flow(w, result, type, <return>, NULL);
  _revive(w);
}

/* A free ends its local for the statements that follow it on the same path.
   Where that path ends, nothing it freed is known to be freed any more. */
static void _revive(Walk &w) {
  foreach (Fact fact in w.facts) fact.dead = 0;
}

static void _walk_expression(Walk &w, Var expression) {
  List arguments = NULL;
  String callee = _callee_of(expression, arguments);
  if (callee && _region_call(w, callee, arguments)) return;
  match (_source_assignment(_unwrap(expression))) {
    case %(?target ?value): _store(w, target, value);
    default: _scan(w, expression, 0);
  }
}

/* A region-opening or region-ending call in statement position. Reports
   whether `callee` is one. */
static int _region_call(Walk &w, String callee, List arguments) {
  Fact fact = _fact_of(w, arguments.car(), NULL);
  match (_effect(w, callee)) {
    case %(open ?kind): _open_region(w, kind, _slot(w, arguments.car()));
    case %(close ?kind): {
      Region region = _innermost(w, kind);
      /* A close in a nested block runs on some paths, so the region stays
         open for the statements after that block. */
      if (region) region.closed = region.depth == w.depth;
    }
    case %(destroy): if (fact && fact.depth == w.depth && fact.owner)
      fact.owner.closed = 1;
    case %(move): {
      Fact slot = _slot(w, arguments.cadr());
      Region owner = (fact && fact.empty) || _empty(arguments.car())
        ? _owner(w, slot) : _allocate_in(w, slot);
      if (fact) _move(fact, owner);
    }
    case %(exit): if (fact) _move(fact, NULL);
    default: return 0;
  }
  return 1;
}

static void _walk_conditional(Walk &w, List children) {
  Map restored = w.restored;
  w.depth += 1;
  foreach (Var child in children) _walk(w, child);
  w.depth -= 1;
  w.restored = restored;
}

static void _walk_rows(Walk &w, List rows) {
  foreach (List row in rows) {
    _scan(w, row.car(), 0);
    foreach (List statement in row.cdr()) _walk(w, statement);
  }
}

// defers and restored places

/* A `defer` beside a region closes it at block exit, a deferred free or
   destroy owns its local until then, and any other deferred expression
   runs at block exit. */
static void _walk_defer(Walk &w, Var body) {
  List arguments = NULL;
  String callee = NULL;
  match (body) case $expression_statement(?expression):
    callee = _callee_of(expression, arguments);
  Fact fact = _fact_of(w, arguments.car(), NULL);
  match (callee ? _effect(w, callee) : void) {
    case %(close ?): return;
    case %((!or free destroy) *)
      if (fact && fact.constant && fact.param < 0): {
      if (!fact.empty)
        _acquired(fact).cleanup = _open_region(w, <auto>, NULL);
      return;
    }
    case %(free *) if (fact && fact.param < 0): {
      fact.region = _open_region(w, <auto>, NULL);
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

/* A `with` entry saves a place, installs a value, and restores the place in a
   defer. A store into a place this block restores is undone before the
   block ends, so it is not an escape. */
static int _note_restored(Walk &w, Var body) {
  match (body) case $expression_statement(?expression):
    match (_source_assignment(_unwrap(expression))) case %(?target ?): {
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
static void _note_deferred_stores(Walk &w, Var node) {
  match (_source_assignment(node)) case %(?target ?): {
    w.restored[_unwrap(target)] = 1;
    return;
  }
  match (node) case %(*children):
    foreach (Var child in children) _note_deferred_stores(w, child);
}

// expressions

/* Visit every read, call, and nested store in one expression, left to
   right and without recursion, so a long operator chain fits the stack. A
   free ends its local after the whole expression, and a deferred
   expression runs at block exit, so what it frees stays live for the
   statements this block still has to walk. */
static void _scan(Walk &w, Var value, int deferred) {
  Var root = _unwrap(value);
  int base = w.pending.len(), mark = w.freed.len();
  w.pending.push(value);
  while ((int) w.pending.len() > base) {
    Var node = w.pending.take_last();
    if (node == <nested> || node == <unnested>) {
      w.depth += node == <nested> ? 1 : -1;
      continue;
    }
    if (_scan_call_node(w, node)) continue;
    if (_scan_conditional(w, node)) continue;
    if (_scan_assignment(w, node, root)) continue;
    _scan_node(w, node);
  }
  while ((int) w.freed.len() > mark) {
    Fact fact = w.freed.take_last();
    if (!deferred) fact.dead = fact.ending;
  }
}

static int _scan_call_node(Walk &w, Var node) {
  List call = _source_call(node);
  if (!call) return 0;
  (Var function, List arguments) = call;
  String callee = Ast.binding_spelling(_binding_of(function));
  match (callee ? _effect(w, callee) : void) {
    case %((!or exit wrap)): break;
    case %(free): _end(w, arguments.car(), NULL, <freed>);
    case %(free scope): _end(w, arguments.car(), "Scope.free", <freed>);
    case %(alloc moved):
      _end(w, arguments.car(), "Scope.realloc", <moved>);
    default: if (callee) _scan_call(w, node, callee, arguments);
  }
  if (arguments) w.pending.push(arguments);
  return 1;
}

/* An argument that ends its storage. `op` names a Scope operation, which
   reports storage no Scope allocator returned: a literal, the function's
   own storage, or a pooled value. The local it names is dead after the
   expression, `how` recording whether it was freed or moved. */
static void _end(Walk &w, Var argument, String op, Symbol how) {
  List named = NULL;
  Fact storage = _value_fact(w, argument, named);
  int literal = 0;
  match (_unwrap(argument)) case $source_literal_content(%(*fields)):
    literal = 1;
  if (op && (literal || (storage &&
      (storage.region == w.frame || storage.born == 2)))) {
    String subject = literal ? "a literal"
                             : _subject(w, argument, named, storage);
    $warn.region_bad_free(w, w.origin, op, subject);
  }
  Fact fact = _fact_of(w, argument, NULL);
  if (!fact || fact.depth != w.depth) return;
  fact.ending = how;
  w.freed.push(fact);
}

/* A call sinks each argument where the callee's summary says. */
static void _scan_call(Walk &w, Var call, String callee, List arguments) {
  int count = arguments.len();
  List types = _parameter_types(call);
  foreach (List row in _summary(w, callee).cadr()) {
    (int index, Var target) = row;
    if (index >= count) continue;
    Type type = NULL, holder_type = NULL;
    Var argument = _passed(types, arguments, index, type);
    if (target == <static>) _flow(w, argument, type, <static>, NULL);
    else if (target == <unknown>) _flow(w, argument, type, <heap>, NULL);
    else if (target == <result>) {
      int born = 0;
      Region other = NULL;
      Acquired acquired = NULL;
      Region region = _birth(w, call, NULL, born, other, acquired);
      struct Fact result = {
        .param = -1, .born = born, .region = region, .other = other,
        .acquired = acquired};
      _flow(w, argument, type, <heap>, &result);
    }
    else match (target) case %(param ?other): {
      if (other.int() >= count) continue;
      Var holder = _passed(types, arguments, other.int(), holder_type);
      int through = 1;
      Fact base = _base(w, _address_of(holder), through), object = NULL;
      if (!base) base = _fact_of(w, holder, NULL);
      Symbol sink = _sink_of(base, through, object);
      _flow(w, argument, type, sink, object);
    }
  }
}

/* The later operands of `&&`, `||`, and `?:` run on some paths, so they
   count as a nested block, as a conditional statement's children do. */
static int _scan_conditional(Walk &w, Var node) {
  match (node) case %(op (!or && || (!quote ?)) ?first *later): {
    w.pending.push(<unnested>);
    _scan_children(w, later);
    w.pending.push(<nested>);
    w.pending.push(first);
    return 1;
  }
  return 0;
}

static int _scan_assignment(Walk &w, Var node, Var root) {
  List assignment = _source_assignment(node);
  if (!assignment || _unwrap(node) == root) return 0;
  (Var target, Var stored) = assignment;
  _store(w, target, stored);
  w.pending.push(target);
  return 1;
}

static void _scan_node(Walk &w, Var node) {
  match (node) {
    case %(expr ? ?inner): w.pending.push(inner);
    case $source_identifier_content(
        %((!set ?binding (binding ? ?)))):
      _scan_ident(w, binding);
    /* A statement expression declares locals of its own. */
    case %((!or declare decl) ?specifiers (bindings *bindings)):
      _declare(w, specifiers, bindings);
    /* A List literal retains its values in the active Pool. */
    case %(cons ?head ?tail): _scan_cons(w, node, head, tail);
    case %(*children): _scan_children(w, children);
  }
}

static void _scan_ident(Walk &w, Var binding) {
  Var found = w.facts[binding];
  if (found is void) return;
  Fact fact = found;
  Region cleanup = _cleanup(fact.acquired);
  if (w.audit && (_closed(fact.region) || _closed(fact.other) ||
                  (cleanup && cleanup.closed))) {
    String name = Ast.binding_spelling(binding);
    $warn.region_read_ended(w, w.origin, name);
    return;
  }
  if (!fact.dead) return;
  String name = Ast.binding_spelling(binding);
  String ended = fact.dead == <moved> ? $reason.region_moved()
                                      : $reason.region_freed();
  $warn.region_after_free(w, w.origin, name, ended);
  fact.dead = 0;
}

static void _scan_cons(Walk &w, Var node, Var head, Var tail) {
  int born = 0;
  Region other = NULL;
  Acquired acquired = NULL;
  Region region = _birth(w, node, NULL, born, other, acquired);
  struct Fact result = {.param = -1, .born = born, .region = region};
  _flow(w, head, NULL, <heap>, &result);
  _flow(w, tail, NULL, <heap>, &result);
  w.pending.push(tail);
  w.pending.push(head);
}

static void _scan_children(Walk &w, List children) {
  int start = w.pending.len();
  foreach (Var child in children) w.pending.push(child);
  for (int end = w.pending.len() - 1; start < end; start++, end--) {
    Var first = w.pending[start];
    w.pending[start] = w.pending[end];
    w.pending[end] = first;
  }
}

// stores and declarations

static void _store(Walk &w, Var target, Var value) {
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

/* The place a store target names, seen through the pointer a `with` entry
   holds: `*address` and the place `address` was taken from are one
   storage. */
static Var _target_place(Walk &w, Var target) {
  Var inner = _unwrap(target);
  match (inner)
    case $source_operator_content(%((!quote *) ?pointer)): {
      Fact fact = _fact_of(w, pointer, NULL);
      if (fact && fact.place) return fact.place;
    }
  return inner;
}

/* `fact` receives `value`, declared or stored as `type`. A store of a
   region-born local into a local declared outside that region reports
   once, and the receiving local does not carry the region further. */
static void _assign(Walk &w, Fact fact, Var value, Type type, int store) {
  _scan(w, value, 0);
  Fact source = _value_fact(w, value, NULL);
  if (!source) source = _returned_argument(w, value, NULL);
  int born = 0;
  Region other = source ? source.other : NULL;
  Acquired acquired = NULL;
  Region region = source ? source.region
                         : _birth(w, value, type, born, other, acquired);
  int owners = source ? source.born : born;
  int kept = (source || born) && !_number(w, type, value);
  int copies = kept && _copies(w, type, value);
  if (kept && copies) {
    if (owners == 3) {
      region = other;
      other = NULL;
      owners = 2;
    }
    else kept = (owners & 2) || (region && region.kind == <pool>);
  }
  if (kept && store && source &&
      (region || other || _cleanup(source.acquired)))
    kept = !_flow(w, value, type, <local>, fact);
  if (kept && source && !copies && !source.empty)
    acquired = _acquired(source);
  if (copies || (source && !kept)) acquired = NULL;
  /* A nested store runs on some paths; the others keep the earlier value. */
  if (!acquired && store && fact.depth < w.depth) acquired = fact.acquired;
  fact.acquired = acquired;
  fact.empty = source ? source.empty : _empty(value);
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
static void _declare(Walk &w, Var specifiers, List bindings) {
  Map types = w.c.semantic_binding_facts();
  if (<static> in specifiers || <extern> in specifiers) {
    foreach (List item in bindings)
      match (item) case %(op = (bind ?name ?) ?value): {
        _scan(w, value, 0);
        _flow(w, value, types[%(type $name)], <static>, NULL);
      }
    return;
  }
  foreach (List item in bindings)
    match (item) {
      case %(op (!quote =) (bind (!set ?name (binding ? ?)) ?) ?value):
        _declare_initialized(w, name, value, types[%(type $name)]);
      case %(bind (!set ?name (binding ? ?)) ?): _new_fact(w, name, -1);
    }
}

static void _declare_initialized(
  Walk &w, List name, Var value, Type type) {
  Fact fact = _new_fact(w, name, -1);
  foreach (Var part in w.c.sym.normalize_declared_type(type)) {
    if (part is not <symbol> || !part.symbol().is_type_qualifier()) break;
    if (part == <const>) fact.constant = 1;
  }
  _assign(w, fact, value, type, 0);
}
