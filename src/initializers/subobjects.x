/*  subobjects.x -- initializer destinations and native bounds

    Paths are stacks of (owner kind selector type following-fields)
    frames. The same subobject walk owns conversion and deferred native
    assignment.
*/

static keyword loop $private.loop;

/* A qualified alias can expose another typedef below its qualifier. */
static Type _resolve_shape(Compiler c, Type type) {
  if (!type) return type;
  type = c.sym.resolve_key(type);
  int hops = 0;
  loop {
    Type key = type.canonicalize();
    if (key === type) return type;
    Type next = c.sym.next_typedef(key, hops);
    if (!next) return key;
    type = c.sym.resolve_key(next);
  }
}

// subobject choices

/** Returns (original cases) rows; each case is
    (native-condition path destination value). Explicit braces start a nested
    walk. Scalar runs map their ordinal through the native dimensions; other
    inputs retain possible cursor continuations. A NULL condition is
    unconditional, and a NULL destination is excess.
*/
List Compiler.initializer_rows(
  Compiler c, Type root, List items, List target) {
  List scalar = _scalar_rows(c, root, items, target);
  if (scalar) return scalar;
  Array rows = [];
  List first_path = _first_path(c, root, NULL);
  Type resolved_root = _resolve_shape(c, root);
  int available = !!first_path || resolved_root.scalar() ||
    resolved_root.is_pointer() || resolved_root.is_enum();
  List states = %((() $first_path $available));
  int first = 1;
  foreach (List original in items) {
    rows.push(_advance_row(c, root, original, target, states, first));
    first = 0;
  }
  return rows.list_free();
}

static List _advance_row(
  Compiler c, Type root, List original, List target,
  List &states, int first) {
  List value = original;
  if (original.car() == <dotinit> || original.car() == <indexinit>) {
    List path = _designated_path(c, root, original, value, original);
    states = %((() $path 1));
  }
  List cases = _row_cases(c, root, value, states, first);
  Array following = [];
  foreach (List choice in cases) {
    (List condition, List path, Type type, List input) = choice;
    _advance_path(c, target, path, condition, following);
  }
  states = _merge_states(following);
  return $(original, cases);
}

/* An initval supplies its own cases; otherwise each cursor state descends
   to the first subobject that the value initializes whole. */
static List _row_cases(
  Compiler c, Type root, List value, List states, int first) {
  match (value)
    case %(expr ? (!set ?body (initval *))): {
      List header = NULL;
      return Ast.initializer_cases(body, header);
    }
  Array cases = [];
  foreach (List state in states) {
    (List condition, List path, int available) = state;
    Type type = available ? _path_type(path, root) : NULL;
    if (first && _fills_char_array(c, root, value)) {
      path = NULL;
      type = root;
    }
    while (type && !_fills_whole(c, type, value)) {
      List next = _first_path(c, type, path);
      if (!next) break;
      path = next;
      type = _path_type(path, root);
    }
    cases.push($(condition, path, type, value));
  }
  return cases.list_free();
}

static List _designated_path(
  Compiler c, Type root, List node, List &value, List &normalized) {
  List path = NULL, selectors = NULL;
  Type type = root;
  loop {
    Type owner = _resolve_shape(c, type);
    match (node) {
      case %(dotinit ?field ?inner): {
        selectors = cons(%(dotinit $field), selectors);
        List selected = _named_field_path(c, type, field.car(), path);
        type = c.sym.lookup_field(type, field);
        path = selected ? selected
          : cons(%($owner field $(field.car()) $type ()), path);
        node = inner;
        continue;
      }
      case %(indexinit ?index ?inner): {
        List reference = NULL;
        List captured = _capture_index(c, index, reference);
        selectors = cons(%(indexinit $captured), selectors);
        type = owner.dereference();
        path = cons(%($owner index $reference $type ()), path);
        node = inner;
        continue;
      }
    }
    value = node;
    foreach (List selector in selectors) node = selector.append($(node));
    normalized = node;
    return path;
  }
}

static List _named_field_path(Compiler c, Type type, Var name, List parent) {
  Type owner = _resolve_shape(c, type);
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List row = fields.car();
    List path = _field_path(owner, fields, parent);
    if (row.car() == name) return path;
    Type member = row.cadr();
    if (!row.car() && _resolve_shape(c, member).is_aggregate()) {
      List nested = _named_field_path(c, member, name, path);
      if (nested) return nested;
    }
    fields = fields.cdr();
  }
  return NULL;
}

/** Returns the initializer path selecting one visible aggregate field.
    Anonymous aggregate members remain explicit path frames, so consumers
    observe the same member promotion as native initializer conversion.
*/
List Compiler.initializer_field_path(
  Compiler c, Type type, List field) =>
  _named_field_path(c, type, field.car(), NULL);

/* An enum constant captures one native index expansion where the original
   designator occurred. Its ordinary cast shape survives normalization. */
static List _capture_index(Compiler c, List index, List &reference) {
  match (index)
    case %(expr ? (cast (enum ((op = ?binding ?original)))
          (!set ?value (expr ? (ident ?binding))))): {
      reference = value;
      return index;
    }
  unsigned long long at;
  if (_literal_integer(index, at)) {
    reference = index;
    return index;
  }
  Type type = index.cadr();
  List binding = c.sym.introduce(c.fresh_name("initializer_index"));
  c.sym.bind_identity(NULL, binding, type.declaration_ast(binding));
  Type native = %(enum ((op = $binding $index)));
  reference = $!($type){ $binding };
  return %(expr $type (cast $native $reference));
}

static List _merge_states(Array states) {
  Map positions = {};
  Array merged = [];
  foreach (List state in states) {
    (List condition, List path, int available) = state;
    List key = $(path, available);
    Var stored;
    if (!positions.try_get(key, stored)) {
      positions[key] = merged.len();
      merged.push(state);
      continue;
    }
    int at = stored;
    List previous = merged[at];
    condition = _condition_or(previous.car(), condition);
    merged[at] = $(condition, path, available);
  }
  states.free();
  return merged.list_free();
}

static int _fills_whole(Compiler c, Type type, List value) {
  if (value ~= %(expr ? (composite *))) return 1;
  Type source = value.cadr(), resolved = _resolve_shape(c, type);
  if (_resolve_shape(c, source) == resolved) return 1;
  if (c.sym.is_var_type(type)) return 1;
  if (_fills_char_array(c, type, value)) return 1;
  return !resolved.is_array() && !resolved.is_aggregate();
}

static int _fills_char_array(Compiler c, Type type, List value) {
  match (value) {
    case %(expr ? (literal ?literal_type ?)): {
      if (!Type.is_char_pointer_like(literal_type)) return 0;
      Type array = _resolve_shape(c, type);
      if (!array.is_array()) return 0;
      Type element = c.sym.resolve_key(array.cdr()).scalar();
      return element === %(char) || element === %(signed char) ||
             element === %(unsigned char);
    }
  }
  return 0;
}

// initializer paths

static Type _path_type(List path, Type root) {
  if (!path) return root;
  List frame = path.car();
  return frame[3];
}

static List _first_path(Compiler c, Type type, List parent) {
  Type owner = _resolve_shape(c, type);
  if (owner.is_array()) {
    List zero = $!int{ 0 };
    return cons(%($owner index $zero $(owner.cdr()) ()), parent);
  }
  if (owner.is_aggregate())
    return _field_path(owner, c.sym.field_order(owner).cdr(), parent);
  return NULL;
}

static List _field_path(Type owner, List fields, List parent) {
  fields = _next_field(fields);
  if (!fields) return NULL;
  List row = fields.car();
  return cons(
    %($owner field $(row.car()) $(row.cadr()) $(fields.cdr())), parent);
}

/* C positional initialization skips unnamed bit-fields, not anonymous
   aggregate subobjects. The ordered metadata retains both kinds. */
static List _next_field(List fields) {
  while (fields) {
    List row = fields.car();
    Type type = row.cadr();
    if (row.car() || !type.is_bitfield()) break;
    fields = fields.cdr();
  }
  return fields;
}

static void _advance_path(
  Compiler c, List target, List path, List condition, Array states) {
  while (path) {
    List frame = path.car(), parent = path.cdr();
    (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
    if (kind == <field>) {
      // A union initializes one member, so no field follows another.
      List next = owner.car() == <union> ? NULL
        : _field_path(owner, rest, parent);
      if (next) {
        states.push(%($condition $next 1));
        return;
      }
    }
    else if (_next_index(c, target, frame, parent, condition, states)) return;
    path = parent;
  }
  // Excess entries are the native initializer's final fallback.
  states.push(%(() () 0));
}

static int _next_index(
  Compiler c, List target, List frame, List parent,
  List &condition, Array states) {
  (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
  List index = selector, dimension = owner.car().cadr();
  unsigned long long at, count;
  List base;
  _index_position(index, base, at);
  int known_index = !base;
  List increment = _ull_literal(at + 1);
  index = base
    ? %(expr (unsigned long long)
        (op + (expr (unsigned long long) (parens $base)) $increment))
    : increment;
  List next = cons(%($owner index $index $type ()), parent);
  if (!dimension) { states.push(%($condition $next 1)); return 1; }
  if (known_index && _literal_integer(dimension, count)) {
    if (at + 1 < count) { states.push(%($condition $next 1)); return 1; }
    return 0;
  }
  List inside = _index_inside(c, target, parent, type, index);
  states.push(%($(_condition_and(condition, inside)) $next 1));
  condition = _condition_and(
    condition, %(expr (int) (op ! (expr (int) (parens $inside)))));
  return 0;
}

static List _index_inside(
  Compiler c, List target, List parent, Type type, List index) {
  List array = c.initializer_slot(target, parent);
  List element = %(expr $type (index $array $($!int{ 0 })));
  List length = %(expr (unsigned)
    (op / (expr (unsigned) (sizeof (parens $array)))
          (expr (unsigned) (sizeof (parens $element)))));
  return %(expr (int)
    (op < (expr (int) (parens $index))
          (expr (unsigned) (parens $length))));
}

/** Selects a native subobject without evaluating it when used by sizeof. */
List Compiler.initializer_slot(Compiler c, List target, List path) {
  foreach (List frame in path.reverse()) {
    (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
    if (kind == <index>)
      target = %(expr $selected (index $target $selector));
    else if (selector)
      target = %(expr $selected (op . $target ($selector)));
  }
  return target;
}

/* scalar runs

   Scalar positional runs have one ordinal, independent of the native
   array boundaries. Count the type tree once instead of retaining
   cursor histories. Children pair ordinary path frames with
   (type count children) layouts. */

static List _scalar_rows(Compiler c, Type root, List items, List target) {
  int symbolic = 0;
  List string = NULL;
  if (!_scalar_inputs(c, items, string)) return NULL;
  List layout = _scalar_layout(c, root, target, string, symbolic);
  if (!layout || !symbolic) return NULL;
  int array = _resolve_shape(c, root).is_array();
  Array rows = [];
  unsigned long long at = 0;
  foreach (List value in items) {
    List ordinal = _ull_literal(at++);
    List count = layout.cadr();
    List condition = array ? %(expr (int)
      (op < $ordinal (expr (unsigned long long) (parens $count)))) : NULL;
    Array cases = [];
    _ordinal_cases(layout, ordinal, NULL, condition, value, cases);
    cases.push(%(() () () $value));
    rows.push($(value, cases.list_free()));
  }
  return rows.list_free();
}

static int _scalar_inputs(Compiler c, List items, List &string) {
  foreach (List value in items) {
    match (value) {
      case %(expr ? (!or (composite *) (initval *))): return 0;
      case %(expr ?type ?): {
        Type source = _resolve_shape(c, type);
        if (!c.sym.is_var_type(type) &&
            (source.is_array() || source.is_aggregate())) return 0;
      }
      default: return 0;
    }
    if (value ~= %(expr ? (literal ?literal_type ?)))
      if (Type.is_char_pointer_like(literal_type)) string = value;
  }
  return 1;
}

static List _scalar_layout(
  Compiler c, Type type, List target, List string, int &symbolic) {
  Type owner = _resolve_shape(c, type);
  if (c.sym.is_var_type(type) ||
      (!owner.is_array() && !owner.is_aggregate()))
    return %($type $(_ull_literal(1)) ());
  if (owner.is_array())
    return _array_layout(c, type, owner, target, string, symbolic);
  if (owner.car() == <union>) return NULL;
  return _record_layout(c, type, owner, target, string, symbolic);
}

static List _array_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  List dimension = owner.car().cadr();
  if (!dimension) return NULL;
  if (string && _fills_char_array(c, type, string)) return NULL;
  unsigned long long size;
  if (!_literal_integer(dimension, size)) symbolic = 1;
  List path = _first_path(c, type, NULL);
  List element = c.initializer_slot(target, path);
  List child = _scalar_layout(c, owner.cdr(), element, string, symbolic);
  if (!child) return NULL;
  List one = _ull_literal(1);
  List bytes = %(expr (unsigned long long) (sizeof (parens $element)));
  List divisor = child.caddr() ? %(expr (unsigned long long)
    (op ? $bytes $bytes $one)) : bytes;
  List count = %(expr (unsigned long long)
    (op / (expr (unsigned long long) (sizeof (parens $target)))
          (expr (unsigned long long) (parens $divisor))));
  List units = child.cadr();
  if (units !== one) count = _ull_op(<*>, count, units);
  return %($type $count (($(path.car()) $child)));
}

static List _record_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  Array children = auto [];
  List count = NULL;
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List path = _field_path(owner, fields, NULL);
    if (!path) break;
    (Type parent, Symbol kind, Var name, Type member, List rest) = path.car();
    List slot = c.initializer_slot(target, path);
    List child = _scalar_layout(c, member, slot, string, symbolic);
    if (!child) return NULL;
    List units = child.cadr();
    count = count ? _ull_op(<+>, count, units) : units;
    children.push($(path.car(), child));
    fields = rest;
  }
  if (!count) return NULL;
  return $(type, count, children.list());
}

static void _ordinal_cases(
  List layout, List ordinal, List path, List condition, List value,
  Array cases) {
  (Type type, List count, List children) = layout;
  if (!children) {
    cases.push($(condition, path, type, value));
    return;
  }
  List start = NULL;
  List one = _ull_literal(1);
  foreach (List entry in children) {
    (List frame, List child) = entry;
    Symbol kind = frame.cadr();
    List units = child.cadr(), position = ordinal, active = condition;
    if (kind == <index>)
      frame = _ordinal_index(frame, ordinal, units, one, position);
    else _ordinal_field(ordinal, units, one, start, position, active);
    _ordinal_cases(
      child, position, cons(frame, path), active, value, cases);
  }
}

static List _ordinal_index(
  List frame, List ordinal, List units, List one, List &position) {
  (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
  List index = ordinal;
  position = $!int{ 0 };
  if (units !== one) {
    // Empty native subarrays leave these selectors well-formed.
    List divisor = %(expr (unsigned long long)
      (op ? $units $units $one));
    index = _ull_op(</>, ordinal, divisor);
    position = _ull_op(<%>, ordinal, divisor);
  }
  return %($owner index $index $selected ());
}

static void _ordinal_field(
  List ordinal, List units, List one, List &start,
  List &position, List &active) {
  if (start) {
    position = _ull_op(<->, ordinal, start);
    if (units !== one)
      active = _condition_and(
        active,
        %(expr (int)
          (op >= (expr (unsigned long long) (parens $ordinal))
                 (expr (unsigned long long) (parens $start)))));
  }
  List test = units === one
    ? %(expr (int) (op == (expr (unsigned long long) (parens $position))
                         $($!int{ 0 })))
    : %(expr (int)
        (op < (expr (unsigned long long) (parens $position))
              (expr (unsigned long long) (parens $units))));
  active = _condition_and(active, test);
  start = start ? _ull_op(<+>, start, units) : units;
}

// native conditions

/* A NULL condition is unconditional, so it absorbs the other. */
module List _condition_or(List first, List second) {
  if (!first || !second) return NULL;
  if (first === second) return first;
  return %(expr (int) (op || (expr (int) (parens $first))
                             (expr (int) (parens $second))));
}

module List _condition_and(List first, List second) {
  if (!first) return second;
  if (!second) return first;
  match (second)
    case %(expr ? (op < (expr ? $($grouped(?index)))
            (expr ? $($grouped(?bound))))): {
      unsigned long long at;
      List base;
      _index_position(index, base, at);
      first = _drop_bound(first, bound, base, at);
    }
  return first ? %(expr (int) (op && (expr (int) (parens $first))
                                    (expr (int) (parens $second)))) : second;
}

static List _drop_bound(
  List condition, List bound, List base, unsigned long long minimum) {
  match (condition) {
    case %(expr ? (op && (expr ? $($grouped(?left)))
             (expr ? $($grouped(?right))))):
      return _condition_and(
        _drop_bound(left, bound, base, minimum),
        _drop_bound(right, bound, base, minimum));
    case %(expr ? (op < (expr ? $($grouped(?index)))
            (expr ? $($grouped(?length))))): {
      unsigned long long at;
      List origin;
      _index_position(index, origin, at);
      if (length === bound && origin === base && at <= minimum) return NULL;
    }
  }
  return condition;
}

/* Cursor offsets are literal facts even when their native starting index
   is not. Keep one base-plus-offset expression instead of nested
   increments. */
static void _index_position(
  List index, List &base, unsigned long long &offset) {
  base = NULL;
  if (_literal_integer(index, offset)) return;
  match (index)
    case %(expr ? (op + (expr ? $($grouped(?origin))) ?amount)):
      if (_literal_integer(amount, offset)) {
        base = origin;
        return;
      }
  base = index;
  offset = 0;
}

/* Decode only a literal fact; native expressions are never evaluated here.
   A bare spelling is the int bound a canonical array type keeps. */
module int _literal_integer(List expression, unsigned long long &value) {
  match (expression) {
    case %(expr ? (literal ?type ?spelling)):
      return ((Type) type).integer_literal_magnitude(spelling, value);
    case %(?(String spelling)):
      return Type.integer_literal_magnitude(%(int), spelling, value);
  }
  return 0;
}

static List _ull_literal(unsigned long long value) {
  String spelling = %"$(value)ULL";
  return %(expr (unsigned long long)
    (literal (unsigned long long) $spelling));
}

/* `left operator right` in unsigned long long, operands parenthesized. */
static List _ull_op(Symbol operator, List left, List right) =>
  %(expr (unsigned long long)
    (op $operator (expr (unsigned long long) (parens $left))
                  (expr (unsigned long long) (parens $right))));
