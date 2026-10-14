/*  initializers.x -- brace initializer conversion

    Copyright (c) 2026 Gary William Flake.

    A brace initializer converts each value for the subobject that C's
    initialization order gives it. This unit owns that walk over field
    order and array bounds. A bound only the native compiler knows becomes
    a condition on an unevaluated `*(T *) 0` target, and a value converts
    under each condition that can select it. `expressions.x` converts the
    single values.
*/

#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "compiler.x"
#include "type.x"

#include "grammar.x"
#include "adapter-memo.x"
#include "ast.x"
#include "expressions.x"
#include "macros.x"

// initializer conversion

/** Converts an initializer using its declared native object for array
    bounds. */
List Compiler.convert_initializer(
  Compiler c, List value, Type type, List target) =>
  _convert_initializer(c, value, type, target, NULL);

static List _convert_initializer(
  Compiler c, List value, Type type, List target, int &?native_used) {
  match (value)
    case %(expr ? (composite ?payload)):
      return _convert_composite(
        c, payload.cdr(), type.canonicalize(), target, NULL, native_used);
  return c.convert_expression(value, type.declared());
}

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

static List _convert_composite(
  Compiler c, List items, Type target, List native_target,
  List parent_condition, int &?native_used) {
  if (!items) {
    List fresh = _empty_collection(c, target);
    if (fresh) return fresh;
  }
  if (!native_target) native_target = _zero_pointer_target(target, target);
  Array elements = [];
  int discarded = 0;
  List rows = _composite_rows(
    c, target, items, native_target, parent_condition, discarded);
  // Preserve C's excess warning only when this synthetic alternative applies.
  // The always-true ICE stays on a retained value, so braces remain braces.
  List excess_check = discarded
    ? _composite_excess_check(parent_condition) : NULL;
  foreach (List row, rows) {
    List row_condition = excess_check
      ? _condition_and(parent_condition, excess_check) : parent_condition;
    excess_check = NULL;
    elements.push(
      _convert_composite_row(
        c, row, native_target, row_condition, parent_condition, native_used));
  }
  List converted = elements.list_free();
  return $!($target){ { @converted } };
}

/* An empty initializer for a Map or Array, or for a type that converts from
   one, is a fresh empty collection. A Var holds a fresh empty Map. */
static List _empty_collection(Compiler c, Type target) {
  for (int kind = 0; kind < 2; kind++) {
    Macro shape = kind ? $array_value : $map_value;
    Type source = kind ? %("Array") : %("Map");
    List literal = c.rebuild_expression(source, shape(%()));
    if (!kind && c.sym.is_var_type(target))
      return c.convert_expression(literal, target);
    if (c.sym.resolve_key(target) == c.sym.resolve_key(source))
      return c.convert_expression(literal, target);
    List converted = c.converter_call(literal, source, target);
    if (converted) return converted;
  }
  return NULL;
}

/* An unevaluated `*(native *) 0` typed as `viewed`, from which initializer
   rows name their slots. */
static List _zero_pointer_target(Type viewed, Type native) {
  Type pointer = cons(<*>, native);
  List zero = $!int{ 0 };
  return %(expr $viewed (parens (expr $viewed
    (op * (expr $pointer (parens (expr $pointer (cast $pointer $zero))))))));
}

static List _composite_rows(
  Compiler c, Type target, List items, List native_target,
  List parent_condition, int &discarded) {
  Array rows = [];
  int initialized = 0;
  foreach (List row, c.initializer_rows(target, items, native_target)) {
    List cases = row.cadr();
    int available = 0;
    foreach (List choice, cases)
      if (choice.caddr()) { available = 1; break; }
    if (parent_condition && initialized && !available) {
      discarded = 1;
      continue;
    }
    if (available) initialized = 1;
    rows.push(row);
  }
  return rows.list_free();
}

/* Keep C's excess warning on one retained value of this alternative. */
static List _composite_excess_check(List parent_condition) {
  List zero = $!int{ 0 };
  List one = $!int{ 1 };
  List size = $!int{ $parent_condition ? $zero : $one };
  Type array = %((dim $size) char);
  List probe = %(expr $array (cast $array
    (expr $array (composite (commas $zero)))));
  List count = %(expr (unsigned) (sizeof (parens $probe)));
  return %(expr (int) (op + $one (expr (int) (op * $zero $count))));
}

// subobject choices

/** Returns (original cases) rows; each case is
    (native-condition path destination value). Explicit braces start a nested
    walk. Scalar runs map their ordinal through the native dimensions; other
    inputs retain possible cursor continuations. A NULL condition is
    unconditional, and a NULL destination is excess. */
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
  foreach (List original, items) {
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
  foreach (List choice, cases) {
    (List condition, List path, Type type, List input) = choice;
    _advance_path(c, target, path, condition, following);
  }
  states = _merge_states(following);
  return %($original $cases);
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
  foreach (List state, states) {
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
    cases.push(%($condition $path $type $value));
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
          : cons(%($owner field ${field.car()} $type ()), path);
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
    foreach (List selector, selectors) node = selector.append(%($node));
    normalized = node;
    return path;
  }
}

static List _named_field_path(
  Compiler c, Type type, Var name, List parent) {
  Type owner = _resolve_shape(c, type);
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List row = fields.car();
    List path = _field_path(owner, fields, parent);
    if (row.car() == name) return path;
    Type member = row.cadr();
    if (!row.car() &&
        _resolve_shape(c, member).is_aggregate()) {
      List nested = _named_field_path(c, member, name, path);
      if (nested) return nested;
    }
    fields = fields.cdr();
  }
  return NULL;
}

/** Returns the initializer path selecting one visible aggregate field.
    Anonymous aggregate members remain explicit path frames, so consumers
    observe the same member promotion as native initializer conversion. */
List Compiler.initializer_field_path(
  Compiler c, Type type, List field) =>
  _named_field_path(c, type, field.car(), NULL);

/* An enum constant captures one native index expansion where the original
   designator occurred. Its ordinary cast shape survives normalization. */
static List _capture_index(
  Compiler c, List index, List &reference) {
  match (index)
    case %(expr ? ${$source_cast_content(
        %((enum ((op = ?binding ?original)))
          (!set ?value (expr ? (ident ?binding)))))}): {
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
  foreach (List state, states) {
    (List condition, List path, int available) = state;
    List key = %($path $available);
    Var stored;
    if (!positions.try_get(key, stored)) {
      positions[key] = merged.len();
      merged.push(state);
      continue;
    }
    int at = stored;
    List previous = merged[at];
    condition = _condition_or(previous.car(), condition);
    merged[at] = %($condition $path $available);
  }
  states.free();
  return merged.list_free();
}

static int _fills_whole(Compiler c, Type type, List value) {
  if (value.match(%(expr ? (composite *)))) return 1;
  Type source = value.cadr(), resolved = _resolve_shape(c, type);
  if (_resolve_shape(c, source) == resolved) return 1;
  if (c.sym.is_var_type(type)) return 1;
  if (_fills_char_array(c, type, value)) return 1;
  return !resolved.is_array() && !resolved.is_aggregate();
}

static int _fills_char_array(
  Compiler c, Type type, List value) {
  if (!value.match(
    %(expr (* char) ${$source_literal_content(%((* char) ?))}))) return 0;
  Type array = _resolve_shape(c, type);
  if (!array.is_array()) return 0;
  Type element = c.sym.resolve_key(array.cdr()).scalar();
  return element === %(char) || element === %(signed char) ||
         element === %(unsigned char);
}

/* initializer paths

   Paths are stacks of (owner kind selector type following-fields)
   frames. The same subobject walk owns conversion and deferred native
   assignment. */

static Type _path_type(List path, Type root) {
  if (!path) return root;
  (Type owner, Symbol kind, Var selector, Type type, List rest) =
    path.car();
  return type;
}

static List _first_path(
  Compiler c, Type type, List parent) {
  Type owner = _resolve_shape(c, type);
  if (owner.is_array()) {
    List zero = $!int{ 0 };
    return cons(%($owner index $zero ${owner.cdr()} ()), parent);
  }
  if (owner.is_aggregate())
    return _field_path(owner, c.sym.field_order(owner).cdr(), parent);
  return NULL;
}

static List _field_path(
  Type owner, List fields, List parent) {
  fields = _next_field(fields);
  if (!fields) return NULL;
  List row = fields.car();
  return cons(
    %($owner field ${row.car()} ${row.cadr()} ${fields.cdr()}), parent);
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
  states.push(%(${_condition_and(condition, inside)} $next 1));
  condition = _condition_and(
    condition, %(expr (int) (op ! (expr (int) (parens $inside)))));
  return 0;
}

static List _index_inside(
  Compiler c, List target, List parent, Type type, List index) {
  List array = c.initializer_slot(target, parent);
  List element = %(expr $type (index $array ${$!int{ 0 }}));
  List length = %(expr (unsigned)
    (op / (expr (unsigned) (sizeof (parens $array)))
          (expr (unsigned) (sizeof (parens $element)))));
  return %(expr (int)
    (op < (expr (int) (parens $index))
          (expr (unsigned) (parens $length))));
}

/** Selects a native subobject without evaluating it when used by sizeof. */
List Compiler.initializer_slot(Compiler c, List target, List path) {
  foreach (List frame, path.reverse()) {
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

static List _scalar_rows(
  Compiler c, Type root, List items, List target) {
  int symbolic = 0;
  List string = NULL;
  if (!_scalar_inputs(c, items, string)) return NULL;
  List layout = _scalar_layout(c, root, target, string, symbolic);
  if (!layout || !symbolic) return NULL;
  int array = _resolve_shape(c, root).is_array();
  Array rows = [];
  unsigned long long at = 0;
  foreach (List value, items) {
    List ordinal = _ull_literal(at++);
    List count = layout.cadr();
    List condition = array ? %(expr (int)
      (op < $ordinal (expr (unsigned long long) (parens $count)))) : NULL;
    Array cases = [];
    _ordinal_cases(layout, ordinal, NULL, condition, value, cases);
    cases.push(%(() () () $value));
    rows.push(%($value ${cases.list_free()}));
  }
  return rows.list_free();
}

static int _scalar_inputs(Compiler c, List items, List &string) {
  foreach (List value, items) {
    match (value) {
      case %(expr ? (!or (composite *) (initval *))): return 0;
      case %(expr ?type ?): {
        Type source = _resolve_shape(c, type);
        if (!c.sym.is_var_type(type) &&
            (source.is_array() || source.is_aggregate())) return 0;
      }
      default: return 0;
    }
    if (value.match(
      %(expr (* char)
        ${$source_literal_content(%((* char) ?))}))) string = value;
  }
  return 1;
}

static List _scalar_layout(
  Compiler c, Type type, List target, List string, int &symbolic) {
  Type owner = _resolve_shape(c, type);
  if (c.sym.is_var_type(type) ||
      (!owner.is_array() && !owner.is_aggregate()))
    return %($type ${_ull_literal(1)} ());
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
  return %($type $count ((${path.car()} $child)));
}

static List _record_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  Array children = $auto([]);
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
    children.push(%(${path.car()} $child));
    fields = rest;
  }
  if (!count) return NULL;
  return %($type $count ${children.list()});
}

static void _ordinal_cases(
  List layout, List ordinal, List path, List condition, List value,
  Array cases) {
  (Type type, List count, List children) = layout;
  if (!children) {
    cases.push(%($condition $path $type $value));
    return;
  }
  List start = NULL;
  List one = _ull_literal(1);
  foreach (List entry, children) {
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
                         ${$!int{ 0 }}))
    : %(expr (int)
        (op < (expr (unsigned long long) (parens $position))
              (expr (unsigned long long) (parens $units))));
  active = _condition_and(active, test);
  start = start ? _ull_op(<+>, start, units) : units;
}

// row conversion

static typedef struct RowSelection {
  Type type;
  List path, applicable;
  int homogeneous, excess;
} RowSelection;

/* Every case of a row carries the value under its designators. */
static List _convert_composite_row(
  Compiler c, List row, List native_target, List row_condition,
  List parent_condition, int &?native_used) {
  (List original, List cases) = row;
  List value = original;
  while (value.car() == <dotinit> || value.car() == <indexinit>)
    value = value.caddr();
  if (value.match(%(expr ? (initval *))))
    return row_condition === parent_condition ? original
      : _convert_initval_row(
        c, row, value, native_target, row_condition, native_used);
  RowSelection selected = _select_row(cases);
  if (selected.homogeneous)
    return _convert_homogeneous_row(
      c, original, value, selected, native_target, row_condition,
      native_used);
  return _convert_mixed_row(
    c, row, value, native_target, row_condition, parent_condition,
    native_used);
}

static RowSelection _select_row(List cases) {
  RowSelection selected = { .homogeneous = 1 };
  int applicable_seen = 0;
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    if (!destination) { selected.excess = 1; continue; }
    selected.applicable = applicable_seen
      ? _condition_or(selected.applicable, condition) : condition;
    applicable_seen = 1;
    if (!selected.type) { selected.type = destination; selected.path = path; }
    else if (destination !== selected.type) selected.homogeneous = 0;
  }
  return selected;
}

static List _convert_initval_row(
  Compiler c, List row, List terminal, List native_target,
  List row_condition, int &?native_used) {
  (List original, List cases) = row;
  Array checked = [];
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    List value = _convert_case(
      c, choice, input, native_target, row_condition, native_used);
    checked.push(%($condition $path $destination $value));
  }
  List header = NULL;
  Ast.initializer_cases(terminal.caddr(), header);
  List choices = checked.list_free();
  if (header) choices = cons(header, choices);
  List value = %(expr () (initval @choices));
  return _replace_value(original, value);
}

/* A case's value converted for its destination under the row's condition;
   an excess case keeps the value. */
static List _convert_case(
  Compiler c, List choice, List value, List native_target,
  List row_condition, int &?native_used) {
  (List condition, List path, Type destination, List input) = choice;
  if (!destination) return value;
  return _convert_alternative(
    c, value, destination, _condition_and(row_condition, condition),
    c.initializer_slot(native_target, path), native_used);
}

static List _convert_homogeneous_row(
  Compiler c, List original, List value, RowSelection selected,
  List native_target, List row_condition, int &?native_used) {
  List slot = c.initializer_slot(native_target, selected.path);
  List condition = _condition_and(
    row_condition, selected.excess ? selected.applicable : NULL);
  List converted = !selected.type ? value
    : _convert_alternative(
      c, value, selected.type, condition, slot, native_used);
  return _replace_value(original, converted);
}

static List _replace_value(List original, List value) {
  match (original)
    case %((!set ?tag (!or dotinit indexinit)) ?key ?inner):
      return %($tag $key ${_replace_value(inner, value)});
  return value;
}

/* Only native-dependent alternatives speculate. */
static List _convert_alternative(
  Compiler c, List value, Type type, List condition, List target,
  int &?native_used) {
  if (!condition)
    return _convert_initializer(c, value, type, target, native_used);
  if (native_used) native_used = 1;
  match (value)
    case %(expr ?stored (call "__builtin_choose_expr"
                             (args ?when ?yes ?no))):
      if (stored === type && when === condition) return value;
  List result = _speculate(c, value, type, condition, target, native_used);
  List zero = _zero_value(type, target);
  return !result ? _rejected_initializer(type, condition, zero)
    : _accepted_initializer(result, type, target, condition, zero);
}

/* The conversion of a native-dependent alternative, or NULL when it reports
   a type error. The transaction owns binding and name rollback while
   conversion may also append literal and adapter data. */
static List _speculate(
  Compiler c, List value, Type type, List condition, List target,
  int &?native_used) {
  SymTxn transaction = c.begin_semantic_transaction();
  Map keys = c.key_ids, adapters = c.names.adapters;
  int key_count = c.id_keys.len(), PendingMark mark = c.pending.checkpoint();
  c.key_ids = keys.copy();
  c.names.adapters = adapters.copy();
  DiagnosticsHold hold = c.diagnostics.hold();
  int depth = c.recovery_depth, completed = 0, rejected = 0;
  List result = NULL;
  {
    defer {
      c.recovery_depth = depth;
      c.diagnostics.release(hold, !rejected);
      if (!completed) {
        c.key_ids = keys;
        c.names.adapters = adapters;
        c.id_keys.resize(key_count);
        c.pending.restore(mark);
      }
      transaction.rollback();
    }
    c.recovery_depth = depth + 1;
    try {
      match (value) {
        case %(expr ? (composite ?payload)):
          result = _convert_composite(
            c, payload.cdr(), type.canonicalize(), target, condition,
            native_used);
        default: result = c.convert_expression(value, type);
      }
      transaction.commit();
      completed = 1;
    }
    catch %(malformed (category type)): rejected = 1;
  }
  return result;
}

static List _zero_value(Type type, List target) {
  Type native = type.is_bitfield() ? type.base_type()
    : target ? %("__typeof__" (parens $target)) : type;
  return %(expr $type (cast $native (expr $type
    (composite (commas ${$!int{ 0 }})))));
}

static List _rejected_initializer(
  Type type, List condition, List zero) {
  List size = %(expr (int) (op ? $condition
    (expr (int) (literal (int) "-1"))
    ${$!int{ 1 }}));
  List check = %(expr (unsigned)
    (sizeof ("(" "char[" $size "]" ")")));
  Symbol comma = <,>;
  check = %(expr (void) (cast (void) $check));
  return %(expr $type (parens (expr $type (op $comma $check $zero))));
}

static List _accepted_initializer(
  List result, Type type, List target, List condition, List zero) {
  if (result.match(%(expr ? (composite *)))) {
    Type native = target ? %("__typeof__" (parens $target)) : type;
    return %(expr $type (cast $native $result));
  }
  return %(expr $type
    (call "__builtin_choose_expr" (args $condition $result $zero)));
}

// mixed rows

static List _convert_mixed_row(
  Compiler c, List row, List source, List native_target,
  List row_condition, List parent_condition, int &?native_used) {
  (List original, List cases) = row;
  Array converted = [], captured = [];
  List prepared = source;
  if (source.match(%(expr ? (composite *))))
    prepared = _capture_leaves(c, source, captured);
  int native_identity = !parent_condition;
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    List result = _convert_case(
      c, choice, prepared, native_target, row_condition, native_used);
    int identity = result === prepared;
    match (result)
      case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
        if (yes === prepared) identity = 1;
    if (!identity) native_identity = 0;
    converted.push(%($condition $path $destination $result));
  }
  if (native_identity) {
    converted.free();
    captured.free();
    return original;
  }
  return _materialize_mixed_row(c, original, source, converted, captured);
}

static List _capture_leaves(
  Compiler c, List value, Array inputs) {
  match (value) {
    case %((!set ?kind (!or dotinit indexinit)) ?key ?inner):
      return %($kind $key ${_capture_leaves(c, inner, inputs)});
    case %(expr ?type ${$source_composite_content(%(*items))}): {
      Array captured = [];
      foreach (List item, items)
        captured.push(_capture_leaves(c, item, inputs));
      return %(expr $type ${source_composite_content(
        captured.list_free())});
    }
    /* A value leaf; an internally constructed native call may have a bare
       string callee. */
    case %(expr ?type (!or ${$source_identifier_content(%(*))}
                           ${$source_operator_content(%(*))}
                           ${$source_cast_content(%(*))}
                           ${$grouped(?)}
                           (call *))):
      return _capture_value(c, value, type, inputs);
  }
  return value;
}

static List _capture_value(
  Compiler c, List value, Type type, Array inputs) {
  if (!c.sym.is_var_type(type) && !c.sym.resolve_key(type).scalar())
    return value;
  if (_is_literal(value)) return value;
  String formal = c.fresh_name("initializer_value");
  inputs.push(%($formal $value));
  return %(expr $type $formal);
}

// Capturing native leaves must preserve construction and cache facts.
static int _is_literal(List value) {
  match (value) {
    case %(expr ? ${$source_literal_content(%(*))}): return 1;
    case %(expr ? ${$grouped(?inner)}):
      return _is_literal(inner);
    case %(expr ? ${$source_cast_content(%(? ?inner))}):
      return _is_literal(inner);
  }
  return 0;
}

static List _materialize_mixed_row(
  Compiler c, List original, List source,
  Array converted, Array captured) {
  String formal = c.fresh_name("initializer_value");
  List placeholder = %(expr ${source.cadr()} $formal);
  List values = converted.list_free();
  List adapted = _adapt_choices(c, source, values, placeholder);
  if (adapted) values = adapted;
  Array replaced = [];
  List inputs = captured.list_free();
  int uses_input = !!adapted;
  foreach (List choice, values) {
    (List condition, List path, Type destination, List result) = choice;
    List substituted =
      !destination && source.match(%(expr ? (composite *)))
        ? result : result.search_replace(%(!quote $source), placeholder);
    if (substituted !== result) uses_input = 1;
    replaced.push(%($condition $path $destination $substituted));
  }
  List choices = replaced.list_free();
  if (uses_input) inputs = cons(%($formal $source), inputs);
  if (inputs) choices = cons(%(input @inputs), choices);
  List result = %(expr () (initval @choices));
  return _replace_value(original, result);
}

static List _adapt_choices(
  Compiler c, List source, List choices, List placeholder) {
  Type from = _adapter_type(c, source.cadr());
  if (!from || !Ast.contains_head(source, <fields>)) return NULL;
  Array prepared = $auto([]);
  foreach (List choice, choices) {
    (List condition, List path, Type destination, List value) = choice;
    if (destination && !_adapter_type(c, destination)) return NULL;
    if (value !== source) {
      match (value) {
        case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
          value = yes;
        default: return NULL;
      }
    }
    if (!_adapter_type(c, value.cadr())) return NULL;
    prepared.push(%($condition $path $destination $value));
  }
  Array adapted = [];
  foreach (List choice, prepared.list()) {
    (List condition, List path, Type destination, List value) = choice;
    List adapter = _value_adapter(c, source, value);
    Type callable = adapter.cadr(), result = callable.apply();
    Macro called = $called;
    value = c.rebuild_expression(
      result, called(adapter, %($placeholder)));
    adapted.push(%($condition $path $destination $value));
  }
  return adapted.list_free();
}

static List _value_adapter(
  Compiler c, List source, List converted) {
  Type from = _adapter_type(c, source.cadr());
  Type result = _adapter_type(c, converted.cadr());
  List formal = %(expr ${source.cadr()} "_x2c_gensym_initializer_argument");
  List body = converted.search_replace(%(!quote $source), formal);
  List key = %(iadapt $from $result $body), adapter = NULL;
  $adapter.memo(c, key, adapter) {
    List parameter = c.sym.introduce(c.fresh_name("initializer_arg"));
    List input = $!(${source.cadr()}){ $parameter };
    body = body.search_replace(%(!quote $formal), input);
    List binding = c.sym.introduce(c.fresh_name("initializer_adapt"));
    c.add_early(
      c.wrapper_function(
        %(static @result), binding, %(${from.parameter_ast(parameter)}),
        %((return $result $body))));
    Type callable = %((func ($from)) @result);
    adapter = $!($callable){ $binding };
  }
  return adapter;
}

// Inline native type definitions cannot be copied into conversion arms.
// A selected by-value adapter consumes the original expression just once.
static Type _adapter_type(Compiler c, Type type) {
  if (c.sym.is_var_type(type)) return %("Var");
  Type scalar = c.sym.resolve_key(type).scalar();
  return scalar === %(void) ? NULL : scalar;
}

// native conditions

/* A NULL condition is unconditional, so it absorbs the other. */
static List _condition_or(List first, List second) {
  if (!first || !second) return NULL;
  if (first === second) return first;
  return %(expr (int) (op || (expr (int) (parens $first))
                             (expr (int) (parens $second))));
}

static List _condition_and(List first, List second) {
  if (!first) return second;
  if (!second) return first;
  match (second)
    case %(expr ? ${$source_operator_content(
        %(< (expr ? ${$grouped(?index)})
            (expr ? ${$grouped(?bound)})))}): {
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
    case %(expr ? ${$source_operator_content(
        %(&& (expr ? ${$grouped(?left)})
             (expr ? ${$grouped(?right)})))}):
      return _condition_and(
        _drop_bound(left, bound, base, minimum),
        _drop_bound(right, bound, base, minimum));
    case %(expr ? ${$source_operator_content(
        %(< (expr ? ${$grouped(?index)})
            (expr ? ${$grouped(?length)})))}): {
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
    case %(expr ? ${$source_operator_content(
        %(+ (expr ? ${$grouped(?origin)}) ?amount))}):
      if (_literal_integer(amount, offset)) {
        base = origin;
        return;
      }
  base = index;
  offset = 0;
}

/* Decode only a literal fact; native expressions are never evaluated here.
   A bare spelling is the int bound a canonical array type keeps. */
static int _literal_integer(List expression, unsigned long long &value) {
  match (expression) {
    case %(expr ? ${$source_literal_content(%(?type ?spelling))}):
      return ((Type) type).integer_literal_magnitude(spelling, value);
    case %(?(String spelling)):
      return Type.integer_literal_magnitude(%(int), spelling, value);
  }
  return 0;
}

static List _ull_literal(unsigned long long value) {
  String spelling = %"${value}ULL";
  return %(expr (unsigned long long)
    (literal (unsigned long long) $spelling));
}

/* `left operator right` in unsigned long long, operands parenthesized. */
static List _ull_op(Symbol operator, List left, List right) =>
  %(expr (unsigned long long)
    (op $operator (expr (unsigned long long) (parens $left))
                  (expr (unsigned long long) (parens $right))));

// compound literals

/** Keeps a compound literal's native type definition at its original scope. */
List Compiler.convert_compound_literal(
  Compiler c, List value, Type type, Type native_type) {
  (Type definition, Type reference) = c.initializer_native_types(native_type);
  List target = _zero_pointer_target(type, reference);
  int native_used = 0;
  List converted = _convert_initializer(c, value, type, target, native_used);
  if (!native_used) definition = native_type;
  return %(cast $definition $converted);
}

/** Returns native definition/reference types for a compound literal.
    Macro expansion stays in the original cast; named tags let later sizeof
    expressions reuse that exact layout without a new scope. */
List Compiler.initializer_native_types(Compiler c, Type type) {
  Type base = type.base_type(), definition = base, reference = base;
  match (base) {
    case %(!or ((!set ?kind (!or struct union)) (gensym ? ?) ?body)
               ((!set ?kind (!or struct union)) (!set ?body (fields *)))): {
      String name = c.fresh_name("initializer_type");
      definition = %($kind $name $body);
      reference = %($kind $name);
    }
    case %((!set ?kind (!or struct union)) ?name (fields *)):
      reference = %($kind $name);
  }
  Array definitions = [], references = [];
  for (List rest = type; rest !== base; rest = rest.cdr()) {
    Var reused = NULL;
    Var modifier = _native_modifier(c, rest.car(), reused);
    definitions.push(modifier);
    references.push(reused);
  }
  definition = definitions.list_free().append(definition);
  reference = references.list_free().append(reference);
  return %($definition $reference);
}

static Var _native_modifier(Compiler c, Var modifier, Var &reused) {
  reused = modifier;
  match (modifier)
    case %(dim ?bound): {
      unsigned long long count;
      if (!bound || _literal_integer(bound, count)) return modifier;
      match (bound)
        case %(expr ? ${$sizeof_grouped(%(struct ?tag (fields
            (declare (char) (bindings (bind ? ((dim ?))))))))}): {
          reused = %(dim (expr (unsigned long)
            (sizeof (parens (struct $tag)))));
          return modifier;
        }
      String name = c.fresh_name("initializer_bound");
      Type bytes = %((dim $bound) char);
      List field = bytes.declaration_ast(%("bytes"));
      Type declared = %(struct $name (fields $field));
      List size = %(expr (unsigned long) (sizeof (parens $declared)));
      reused = %(dim (expr (unsigned long) (sizeof (parens (struct $name)))));
      return %(dim $size);
    }
  return modifier;
}
