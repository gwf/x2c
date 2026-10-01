#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#include "type.x"

#pragma private
$(import "../src/grammar.xmacro")
#include "ast.x"
#include "expressions.x"
#include "macros.x"

/* initializer paths, rows, and native layout */

/* C positional initialization skips unnamed bit-fields, not anonymous
   aggregate subobjects. The ordered metadata retains both kinds. */
static List _next_initializer_field(List fields) {
  while (fields) {
    List row = fields.car();
    Type type = row.cadr();
    if (row.car().truth() || !type.is_bitfield()) break;
    fields = fields.cdr();
  }
  return fields;
}

/* Paths are stacks of (owner kind selector type following-fields) frames.
   The same subobject walk owns conversion and deferred native assignment. */
static Type _initializer_type(List path, Type root) {
  if (!path) return root;
  (Type owner, Symbol kind, Var selector, Type type, List rest) =
    path.car();
  return type;
}

static List _initializer_field(
  Type owner, List fields, List parent) {
  fields = _next_initializer_field(fields);
  if (!fields) return NULL;
  List row = fields.car();
  return cons(
    %($owner field ${row.car()} ${row.cadr()} ${fields.cdr()}), parent);
}

static List _initializer_first(
  Compiler c, Type type, List parent) {
  Type owner = c.sym.resolve_key(type);
  if (owner.is_array()) {
    List zero = %(expr (int) (literal (int) "0"));
    return cons(%($owner index $zero ${owner.cdr()} ()), parent);
  }
  if (owner.is_aggregate())
    return _initializer_field(owner, c.sym.field_order(owner).cdr(), parent);
  return NULL;
}

// Decode only a literal fact; native expressions are never evaluated here.
static int _initializer_integer(List expression, unsigned long long &value) {
  String text = NULL;
  match (expression) {
    case %(expr ? ${$source_literal_content(%(? ?spelling))}):
      text = spelling;
    case %(?(String spelling)): text = spelling;
  }
  if (!text || text[0] < '0' || text[0] > '9') return 0;
  char *end, *digits = text;
  int base = 0;
  if (text[0] == '0' && (text[1] == 'b' || text[1] == 'B')) base = 2;
  if (text[0] == '0' && (text[1] == 'o' || text[1] == 'O')) base = 8;
  if (base) digits += 2;
  unsigned long long decoded = strtoull(digits, &end, base);
  while (*end == 'u' || *end == 'U' || *end == 'l' || *end == 'L') end++;
  if (*end) return 0;
  value = decoded;
  return 1;
}

static Var _native_modifier(Compiler c, Var modifier, Var &reused) {
  reused = modifier;
  match (modifier)
    case %(dim ?dimension): {
      List bound = dimension;
      unsigned long long count;
      int captured = 0;
      match (bound)
        case %(expr ? ${$source_content_pattern(
          $sizeof_grouped, %(?argument))}):
          match (argument)
            case %(struct ?name (fields
              (declare (char) (bindings (bind ? ((dim ?))))))): {
              List prior = %(expr (unsigned long)
                (sizeof (parens (struct $name))));
              reused = %(dim $prior);
              captured = 1;
            }
      if (bound && !captured && !_initializer_integer(bound, count)) {
        String name = c.fresh_name("initializer_bound");
        Type bytes = %((dim $bound) char);
        List field = bytes.declaration_ast(%("bytes"));
        Type declared = %(struct $name (fields $field));
        List size = %(expr (unsigned long) (sizeof (parens $declared)));
        List prior = %(expr (unsigned long)
          (sizeof (parens (struct $name))));
        modifier = %(dim $size);
        reused = %(dim $prior);
      }
    }
  return modifier;
}

/** Returns native definition/reference types for a compound literal.
    Macro expansion stays in the original cast; named tags let later sizeof
    expressions reuse that exact layout without a new scope. */
List Compiler.initializer_native_types(Compiler c, Type type) {
  Type base = type.base_type(), definition = base, reference = base;
  match (base) {
    case %((!set ?kind (!or struct union)) (gensym ? ?) ?body): {
      String name = c.fresh_name("initializer_type");
      definition = %($kind $name $body);
      reference = %($kind $name);
    }
    case %((!set ?kind (!or struct union)) (!set ?body (fields *))): {
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

/* An enum constant captures one native index expansion where the original
   designator occurred. Its ordinary cast shape survives normalization. */
static List _initializer_index(Compiler c, List index, List &reference) {
  match (index)
    case %(expr ? ${$source_cast_content(
        %((enum ((op = ?binding ?original)))
          (!set ?value (expr ? (ident ?binding)))))}): {
      reference = value;
      return index;
    }
  unsigned long long at;
  if (_initializer_integer(index, at)) {
    reference = index;
    return index;
  }
  Type type = index.cadr();
  List binding = c.sym.introduce(c.fresh_name("initializer_index"));
  c.sym.bind_identity(NULL, binding, type.declaration_ast(binding));
  Type native = %(enum ((op = $binding $index)));
  reference = %(expr $type (ident $binding));
  return %(expr $type (cast $native $reference));
}

/* Cursor offsets are literal facts even when their native starting index
   is not. Keep one base-plus-offset expression instead of nested
   increments. */
static void _initializer_position(
  List index, List &base, unsigned long long &offset) {
  base = NULL;
  if (_initializer_integer(index, offset)) return;
  match (index)
    case %(expr ? ${$source_operator_content(
        %(+ (expr ? ${$source_content_pattern(
          $grouped, %(?origin))}) ?amount))}):
      if (_initializer_integer(amount, offset)) {
        base = origin;
        return;
      }
  base = index;
  offset = 0;
}

static List _initializer_drop_bound(
  List condition, List bound, List base, unsigned long long minimum) {
  match (condition) {
    case %(expr ? ${$source_operator_content(
        %(&& (expr ? ${$source_content_pattern($grouped, %(?left))})
             (expr ? ${$source_content_pattern($grouped, %(?right))})))}):
      return _initializer_and(
        _initializer_drop_bound(left, bound, base, minimum),
        _initializer_drop_bound(right, bound, base, minimum));
    case %(expr ? ${$source_operator_content(
        %(< (expr ? ${$source_content_pattern($grouped, %(?index))})
            (expr ? ${$source_content_pattern($grouped, %(?length))})))}): {
      unsigned long long at;
      List origin;
      _initializer_position(index, origin, at);
      if (length === bound && origin === base && at <= minimum) return NULL;
    }
  }
  return condition;
}

static List _initializer_and(List first, List second) {
  if (!first) return second;
  if (!second) return first;
  match (second)
    case %(expr ? ${$source_operator_content(
        %(< (expr ? ${$source_content_pattern($grouped, %(?index))})
            (expr ? ${$source_content_pattern($grouped, %(?bound))})))}): {
      unsigned long long at;
      List base;
      _initializer_position(index, base, at);
      first = _initializer_drop_bound(first, bound, base, at);
    }
  return first ? %(expr (int) (op && (expr (int) (parens $first))
                                    (expr (int) (parens $second)))) : second;
}

/** Selects a native subobject without evaluating it when used by sizeof. */
List Compiler.initializer_slot(Compiler c, List target, List path) {
  foreach (List frame, path.reverse()) {
    (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
    if (kind == <index>)
      target = %(expr $selected (index $target $selector));
    else if (selector.truth())
      target = %(expr $selected (op . $target ($selector)));
  }
  return target;
}

static List _index_inside(
  Compiler c, List target, List parent, Type type, List index) {
  List array = c.initializer_slot(target, parent);
  List element = %(expr $type (index $array
    (expr (int) (literal (int) "0"))));
  List length = %(expr (unsigned)
    (op / (expr (unsigned) (sizeof (parens $array)))
          (expr (unsigned) (sizeof (parens $element)))));
  return %(expr (int)
    (op < (expr (int) (parens $index))
          (expr (unsigned) (parens $length))));
}

static int _next_index(
  Compiler c, List target, List frame, List parent,
  List &condition, Array states) {
  (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
  List index = selector, dimension = owner.car().cadr();
  unsigned long long at, count;
  List base;
  _initializer_position(index, base, at);
  int known_index = !base;
  String next_index = %"${at + 1}ULL";
  List increment = %(expr (unsigned long long)
    (literal (unsigned long long) $next_index));
  index = base
    ? %(expr (unsigned long long)
        (op + (expr (unsigned long long) (parens $base)) $increment))
    : increment;
  List next = cons(%($owner index $index $type ()), parent);
  if (!dimension) { states.push(%($condition $next 1)); return 1; }
  if (known_index && _initializer_integer(dimension, count)) {
    if (at + 1 < count) { states.push(%($condition $next 1)); return 1; }
    return 0;
  }
  List inside = _index_inside(c, target, parent, type, index);
  states.push(%(${_initializer_and(condition, inside)} $next 1));
  condition = _initializer_and(
    condition, %(expr (int) (op ! (expr (int) (parens $inside)))));
  return 0;
}

static void _initializer_next(
  Compiler c, List target, List path, List condition, Array states) {
  while (path) {
    List frame = path.car(), parent = path.cdr();
    (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
    if (kind == <field>) {
      if (owner.car() != <union>) {
        List next = _initializer_field(owner, rest, parent);
        if (next) {
          states.push(%($condition $next 1));
          return;
        }
      }
    }
    else if (_next_index(c, target, frame, parent, condition, states)) return;
    path = parent;
  }
  // Excess entries are the native initializer's final fallback.
  states.push(%(() () 0));
}

static List _initializer_merge(Array states) {
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
    List previous = merged[at], before = previous.car();
    if (!before || !condition) condition = NULL;
    else if (before !== condition)
      condition = %(expr (int)
        (op || (expr (int) (parens $before))
               (expr (int) (parens $condition))));
    merged[at] = %($condition $path $available);
  }
  states.free();
  return merged.list_free();
}

static List _initializer_named(
  Compiler c, Type type, Var name, List parent) {
  Type owner = c.sym.resolve_key(type);
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List row = fields.car();
    List path = _initializer_field(owner, fields, parent);
    if (row.car() == name) return path;
    Type member = row.cadr();
    if (!row.car().truth() && c.sym.resolve_key(member).is_aggregate()) {
      List nested = _initializer_named(c, member, name, path);
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
  _initializer_named(c, type, field.car(), NULL);

static List _initializer_designated(
  Compiler c, Type root, List node, List &value, List &normalized) {
  List path = NULL, selectors = NULL;
  Type type = root;
  loop {
    Type owner = c.sym.resolve_key(type);
    match (node) {
      case %(dotinit ?field ?inner): {
        selectors = cons(%(dotinit $field), selectors);
        List selected = _initializer_named(c, type, field.car(), path);
        type = c.sym.lookup_field(type, field);
        path = selected ? selected
          : cons(%($owner field ${field.car()} $type ()), path);
        node = inner;
        continue;
      }
      case %(indexinit ?index ?inner): {
        List reference = NULL;
        List captured = _initializer_index(c, index, reference);
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

static int _initializer_string_array(Compiler c, Type type, List value) {
  if (!value.match(%(expr (* char) ${$source_literal_content(
      %((* char) ?))}))) return 0;
  Type array = c.sym.resolve_key(type);
  if (!array.is_array()) return 0;
  Type element = c.sym.resolve_key(array.cdr()).scalar();
  return element === %(char) || element === %(signed char) ||
         element === %(unsigned char);
}

static int _initializer_whole(Compiler c, Type type, List value) {
  if (value.match(%(expr ? (composite *)))) return 1;
  Type source = value.cadr(), resolved = c.sym.resolve_key(type);
  if (c.sym.resolve_key(source).equal(resolved)) return 1;
  if (c.sym.is_var_type(type)) return 1;
  if (_initializer_string_array(c, type, value)) return 1;
  return !resolved.is_array() && !resolved.is_aggregate();
}

/* Scalar positional runs have one ordinal, independent of the native array
   boundaries. Count the type tree once instead of retaining cursor histories.
   Children pair ordinary path frames with (type count children) layouts. */
static List _array_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  List dimension = owner.car().cadr();
  if (!dimension) return NULL;
  if (string && _initializer_string_array(c, type, string)) return NULL;
  unsigned long long size;
  if (!_initializer_integer(dimension, size)) symbolic = 1;
  List path = _initializer_first(c, type, NULL);
  List element = c.initializer_slot(target, path);
  List child = _initializer_layout(c, owner.cdr(), element, string, symbolic);
  if (!child) return NULL;
  List one = %(expr (unsigned long long)
    (literal (unsigned long long) "1ULL"));
  List bytes = %(expr (unsigned long long) (sizeof (parens $element)));
  List divisor = child.caddr() ? %(expr (unsigned long long)
    (op ? $bytes $bytes $one)) : bytes;
  List count = %(expr (unsigned long long)
    (op / (expr (unsigned long long) (sizeof (parens $target)))
          (expr (unsigned long long) (parens $divisor))));
  List units = child.cadr();
  if (units !== one)
    count = %(expr (unsigned long long)
      (op * (expr (unsigned long long) (parens $count))
            (expr (unsigned long long) (parens $units))));
  return %($type $count ((${path.car()} $child)));
}

static List _record_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  Array children = $auto([]);
  List count = NULL;
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List path = _initializer_field(owner, fields, NULL);
    if (!path) break;
    (Type parent, Symbol kind, Var name, Type member, List rest) = path.car();
    List slot = c.initializer_slot(target, path);
    List child = _initializer_layout(c, member, slot, string, symbolic);
    if (!child) return NULL;
    List units = child.cadr();
    count = count ? %(expr (unsigned long long)
      (op + (expr (unsigned long long) (parens $count))
            (expr (unsigned long long) (parens $units)))) : units;
    children.push(%(${path.car()} $child));
    fields = rest;
  }
  if (!count) return NULL;
  return %($type $count ${children.list()});
}

static List _initializer_layout(
  Compiler c, Type type, List target, List string, int &symbolic) {
  Type owner = c.sym.resolve_key(type);
  if (c.sym.is_var_type(type) ||
      (!owner.is_array() && !owner.is_aggregate())) {
    List one = %(expr (unsigned long long)
      (literal (unsigned long long) "1ULL"));
    return %($type $one ());
  }
  if (owner.is_array())
    return _array_layout(c, type, owner, target, string, symbolic);
  if (owner.car() == <union>) return NULL;
  return _record_layout(c, type, owner, target, string, symbolic);
}

static List _ordinal_index(
  List frame, List ordinal, List units, List one, List &position) {
  (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
  List index = ordinal;
  position = %(expr (int) (literal (int) "0"));
  if (units !== one) {
    // Empty native subarrays leave these selectors well-formed.
    List divisor = %(expr (unsigned long long)
      (op ? $units $units $one));
    index = %(expr (unsigned long long)
      (op / (expr (unsigned long long) (parens $ordinal))
            (expr (unsigned long long) (parens $divisor))));
    position = %(expr (unsigned long long)
      (op % (expr (unsigned long long) (parens $ordinal))
            (expr (unsigned long long) (parens $divisor))));
  }
  return %($owner index $index $selected ());
}

static void _ordinal_field(
  List ordinal, List units, List one, List &start,
  List &position, List &active) {
  if (start) {
    position = %(expr (unsigned long long)
      (op - (expr (unsigned long long) (parens $ordinal))
            (expr (unsigned long long) (parens $start))));
    if (units !== one)
      active = _initializer_and(
        active,
        %(expr (int)
          (op >= (expr (unsigned long long) (parens $ordinal))
                 (expr (unsigned long long) (parens $start)))));
  }
  List test = units === one
    ? %(expr (int) (op == (expr (unsigned long long) (parens $position))
                         (expr (int) (literal (int) "0"))))
    : %(expr (int)
        (op < (expr (unsigned long long) (parens $position))
              (expr (unsigned long long) (parens $units))));
  active = _initializer_and(active, test);
  start = start ? %(expr (unsigned long long)
    (op + (expr (unsigned long long) (parens $start))
          (expr (unsigned long long) (parens $units)))) : units;
}

static void _initializer_ordinal(
  List layout, List ordinal, List path, List condition, List value,
  Array cases) {
  (Type type, List count, List children) = layout;
  if (!children) {
    cases.push(%($condition $path $type $value));
    return;
  }
  List start = NULL;
  List one = %(expr (unsigned long long)
    (literal (unsigned long long) "1ULL"));
  foreach (List entry, children) {
    (List frame, List child) = entry;
    Symbol kind = frame.cadr();
    List units = child.cadr(), position = ordinal, active = condition;
    if (kind == <index>)
      frame = _ordinal_index(frame, ordinal, units, one, position);
    else _ordinal_field(ordinal, units, one, start, position, active);
    _initializer_ordinal(
      child, position, cons(frame, path), active, value, cases);
  }
}

static int _scalar_inputs(Compiler c, List items, List &string) {
  foreach (List value, items) {
    match (value) {
      case %(expr ? (composite *)): return 0;
      case %(expr ? (initval *)): return 0;
      case %(expr ?type ?): {
        Type source = c.sym.resolve_key(type);
        if (!c.sym.is_var_type(type) &&
            (source.is_array() || source.is_aggregate())) return 0;
      }
      default: return 0;
    }
    if (value.match(%(expr (* char) ${$source_literal_content(
        %((* char) ?))}))) string = value;
  }
  return 1;
}

static List _initializer_scalar_rows(
  Compiler c, Type root, List items, List target) {
  int symbolic = 0;
  List string = NULL;
  if (!_scalar_inputs(c, items, string)) return NULL;
  List layout = _initializer_layout(c, root, target, string, symbolic);
  if (!layout || !symbolic) return NULL;
  int array = c.sym.resolve_key(root).is_array();
  Array rows = [];
  unsigned long long at = 0;
  foreach (List value, items) {
    String spelling = %"${at++}ULL";
    List ordinal = %(expr (unsigned long long)
      (literal (unsigned long long) $spelling));
    List count = layout.cadr();
    List condition = array ? %(expr (int)
      (op < $ordinal (expr (unsigned long long) (parens $count)))) : NULL;
    Array cases = [];
    _initializer_ordinal(layout, ordinal, NULL, condition, value, cases);
    cases.push(%(() () () $value));
    rows.push(%($value ${cases.list_free()}));
  }
  return rows.list_free();
}

static List _row_value(
  Compiler c, Type root, List &original, List &states) {
  List value = original;
  if (original.car() == <dotinit> || original.car() == <indexinit>) {
    List path = _initializer_designated(
      c, root, original, value, original);
    states = %((() $path 1));
  }
  return value;
}

static List _initializer_row(
  Compiler c, Type root, List original, List target,
  List &states, int first) {
  List value = _row_value(c, root, original, states);
  match (value)
    case %(expr ? (!set ?body (initval *))): {
      List header = NULL;
      List choices = Ast.initializer_cases(body, header);
      Array following = [];
      foreach (List choice, choices) {
        (List condition, List path, Type type, List input) = choice;
        _initializer_next(c, target, path, condition, following);
      }
      states = _initializer_merge(following);
      return %($original $choices);
    }
  Array cases = [], following = [];
  foreach (List state, states) {
    (List condition, List path, int available) = state;
    Type type = available ? _initializer_type(path, root) : NULL;
    if (first && _initializer_string_array(c, root, value)) {
      path = NULL;
      type = root;
    }
    while (type && !_initializer_whole(c, type, value)) {
      List next = _initializer_first(c, type, path);
      if (!next) break;
      path = next;
      type = _initializer_type(path, root);
    }
    cases.push(%($condition $path $type $value));
    _initializer_next(c, target, path, condition, following);
  }
  states = _initializer_merge(following);
  return %($original ${cases.list_free()});
}

/** Returns (original cases) rows; each case is
    (native-condition path destination value). Explicit braces start a nested
    walk. Scalar runs map their ordinal through the native dimensions; other
    inputs retain possible cursor continuations. A NULL condition is
    unconditional, and a NULL destination is excess. */
List Compiler.initializer_rows(
  Compiler c, Type root, List items, List target) {
  List scalar = _initializer_scalar_rows(c, root, items, target);
  if (scalar) return scalar;
  Array rows = [];
  List first_path = _initializer_first(c, root, NULL);
  Type resolved_root = c.sym.resolve_key(root);
  int available = !!first_path || resolved_root.scalar() ||
    resolved_root.is_pointer() || resolved_root.is_enum();
  List states = %((() $first_path $available));
  int first = 1;
  foreach (List original, items) {
    rows.push(_initializer_row(c, root, original, target, states, first));
    first = 0;
  }
  return rows.list_free();
}

static List _initializer_replace(List original, List value) {
  match (original)
    case %((!set ?tag (!or dotinit indexinit)) ?key ?inner):
      return %($tag $key ${_initializer_replace(inner, value)});
  return value;
}

static List _initializer_zero(Type type, List target) {
  Type native = type.is_bitfield() ? type.base_type()
    : target ? %("__typeof__" (parens $target)) : type;
  return %(expr $type (cast $native (expr $type
    (composite (commas (expr (int) (literal (int) "0")))))));
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

static List _rejected_initializer(
  Type type, List condition, List zero) {
  List size = %(expr (int) (op ? $condition
    (expr (int) (literal (int) "-1"))
    (expr (int) (literal (int) "1"))));
  List check = %(expr (unsigned)
    (sizeof ("(" "char[" $size "]" ")")));
  Symbol comma = <,>;
  check = %(expr (void) (cast (void) $check));
  return %(expr $type (parens (expr $type (op $comma $check $zero))));
}

/* The transaction owns binding and name rollback while conversion may also
   append literal and adapter data. */
static List _speculative_initializer_conversion(
  Compiler c, List value, Type type, List condition, List target,
  int &?native_used, int &rejected) {
  SymTxn transaction = c.begin_semantic_transaction();
  Map keys = c.key_ids, adapters = c.names.adapters;
  int key_count = c.id_keys.len(), declarations = c.early_decls.len();
  c.key_ids = keys.copy();
  c.names.adapters = adapters.copy();
  DiagnosticsHold hold = c.diagnostics.hold();
  int depth = c.recovery_depth, completed = 0;
  List result = NULL;
  {
    defer {
      c.recovery_depth = depth;
      c.diagnostics.release(hold, !rejected);
      if (!completed) {
        c.key_ids = keys;
        c.names.adapters = adapters;
        c.id_keys.resize(key_count);
        c.early_decls.resize(declarations);
      }
      transaction.rollback();
    }
    c.recovery_depth = depth + 1;
    try {
      result = value.match(%(expr ? (composite ?)))
        ? _convert_composite(
          c, value, type.canonicalize(), target, condition, native_used)
        : c.convert_expression(value, type);
      transaction.commit();
      completed = 1;
    }
    catch %(malformed (category type)): rejected = 1;
  }
  return result;
}

/* Only native-dependent alternatives speculate. */
static List _initializer_conversion(
  Compiler c, List value, Type type, List condition, List target,
  int &?native_used) {
  if (!condition)
    return _convert_initializer(c, value, type, target, native_used);
  if (native_used) native_used = 1;
  match (value)
    case %(expr ?stored (call "__builtin_choose_expr"
                             (args ?when ?yes ?no))):
      if (stored === type && when === condition) return value;
  int rejected = 0;
  List result = _speculative_initializer_conversion(
    c, value, type, condition, target, native_used, rejected);
  List zero = _initializer_zero(type, target);
  return rejected ? _rejected_initializer(type, condition, zero)
    : _accepted_initializer(result, type, target, condition, zero);
}

// Keep literal construction/cache facts while capturing native value leaves.
static int _initializer_literal(List value) {
  match (value) {
    case %(expr ? ${$source_literal_content(%(*))}): return 1;
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _initializer_literal(inner);
    case %(expr ? ${$source_cast_content(%(? ?inner))}):
      return _initializer_literal(inner);
  }
  return 0;
}

static List _capture_initializer_value(
  Compiler c, List value, Type type, Array inputs) {
  if (!c.sym.is_var_type(type) && !c.sym.resolve_key(type).scalar())
    return value;
  if (_initializer_literal(value)) return value;
  String formal = c.fresh_name("initializer_value");
  inputs.push(%($formal $value));
  return %(expr $type $formal);
}

static List _initializer_capture_leaves(
  Compiler c, List value, Array inputs) {
  match (value) {
    case %((!set ?kind (!or dotinit indexinit)) ?key ?inner):
      return %($kind $key ${_initializer_capture_leaves(c, inner, inputs)});
    case %(expr ?type ${$source_composite_content(%(*items))}): {
      Array captured = [];
      foreach (List item, items)
        captured.push(_initializer_capture_leaves(c, item, inputs));
      return %(expr $type ${source_composite_content(
        captured.list_free())});
    }
    case %(expr ?type ${$source_identifier_content(%(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_call_content($called, %(expr ? ?), %(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_operator_content(%(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_cast_content(%(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_content_pattern($grouped, %(?))}):
      return _capture_initializer_value(c, value, type, inputs);
    /* Internally constructed native calls may have a bare string callee. */
    case %(expr ?type (call *)):
      return _capture_initializer_value(c, value, type, inputs);
  }
  return value;
}

// Inline native type definitions cannot be copied into conversion arms.
// A selected by-value adapter consumes the original expression just once.
static Type _initializer_value_type(Compiler c, Type type) {
  if (c.sym.is_var_type(type)) return %("Var");
  Type scalar = c.sym.resolve_key(type).scalar();
  return scalar === %(void) ? NULL : scalar;
}

static List _initializer_adapter(
  Compiler c, List source, List converted) {
  Type from = _initializer_value_type(c, source.cadr());
  Type result = _initializer_value_type(c, converted.cadr());
  List formal = %(expr ${source.cadr()} "_x2c_initializer_argument");
  List body = converted.search_replace(%(!quote $source), formal);
  List key = %(iadapt $from $result $body);
  Var stored;
  if (c.names.adapters.try_get(key, stored)) return stored;
  List parameter = c.sym.introduce(c.fresh_name("initializer_arg"));
  List input = %(expr ${source.cadr()} (ident $parameter));
  body = body.search_replace(%(!quote $formal), input);
  List binding = c.sym.introduce(c.fresh_name("initializer_adapt"));
  List params = %(params ${from.parameter_ast(parameter)});
  List function = %(function (static $result)
    (bind $binding ((fnmod $params)))
    (block (stmnt (return $body))));
  Type callable = %((func ($from)) @result);
  List adapter = %(expr $callable (ident $binding));
  c.names.adapters[key] = adapter;
  c.add_early(function);
  return adapter;
}

static List _initializer_adapters(
  Compiler c, List source, List choices, List placeholder) {
  Type from = _initializer_value_type(c, source.cadr());
  if (!from || !ast_contains_head(source, <fields>)) return NULL;
  Array prepared = $auto([]);
  foreach (List choice, choices) {
    (List condition, List path, Type destination, List value) = choice;
    if (destination && !_initializer_value_type(c, destination)) return NULL;
    if (value !== source) {
      match (value) {
        case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
          value = yes;
        default: return NULL;
      }
    }
    if (!_initializer_value_type(c, value.cadr())) return NULL;
    prepared.push(%($condition $path $destination $value));
  }
  Array adapted = [];
  foreach (List choice, prepared.list()) {
    (List condition, List path, Type destination, List value) = choice;
    List adapter = _initializer_adapter(c, source, value);
    Type callable = adapter.cadr(), result = callable.apply();
    Macro called = $called;
    value = c.rebuild_expression(
      result, called(adapter, %($placeholder)));
    adapted.push(%($condition $path $destination $value));
  }
  return adapted.list_free();
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
    if (c.sym.resolve_key(target).equal(c.sym.resolve_key(source)))
      return c.convert_expression(literal, target);
    List converted = _converter_call(c, literal, source, target);
    if (converted) return converted;
  }
  return NULL;
}

static List _composite_rows(
  Compiler compiler, Type target, List items, List native_target,
  List parent_condition, int &discarded) {
  Array rows = [];
  int initialized = 0;
  foreach (List row, compiler.initializer_rows(target, items, native_target)) {
    List cases = row.cadr();
    int available = 0;
    foreach (List choice, cases)
      if (choice.caddr().truth()) { available = 1; break; }
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
  List zero = %(expr (int) (literal (int) "0"));
  List one = %(expr (int) (literal (int) "1"));
  List size = %(expr (int) (op ? $parent_condition $zero $one));
  Type array = %((dim $size) char);
  List probe = %(expr $array (cast $array
    (expr $array (composite (commas $zero)))));
  List count = %(expr (unsigned) (sizeof (parens $probe)));
  return %(expr (int) (op + $one (expr (int) (op * $zero $count))));
}

static List _materialize_mixed_row(
  Compiler compiler, List original, List source,
  Array converted, Array captured) {
  String formal = compiler.fresh_name("initializer_value");
  List placeholder = %(expr ${source.cadr()} $formal);
  List values = converted.list_free();
  List adapted = _initializer_adapters(
    compiler, source, values, placeholder);
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
  return _initializer_replace(original, result);
}

static List _mixed_initializer_row(
  Compiler compiler, List row, List source, List native_target,
  List row_condition, List parent_condition, int &?native_used) {
  (List original, List cases) = row;
  Array converted = [], captured = [];
  List prepared = source;
  if (source.match(%(expr ? (composite *))))
    prepared = _initializer_capture_leaves(compiler, source, captured);
  int native_identity = !parent_condition;
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    input = prepared;
    List slot = native_target
      ? compiler.initializer_slot(native_target, path) : NULL;
    List effective = _initializer_and(row_condition, condition);
    List result = destination
      ? _initializer_conversion(
        compiler, input, destination, effective, slot, native_used)
      : input;
    int identity = result === input;
    match (result)
      case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
        if (yes === input) identity = 1;
    if (!identity) native_identity = 0;
    converted.push(%($condition $path $destination $result));
  }
  if (native_identity) {
    converted.free();
    captured.free();
    return original;
  }
  return _materialize_mixed_row(
    compiler, original, source, converted, captured);
}

typedef struct RowSelection {
  Type type;
  List value, path, applicable;
  int homogeneous, excess;
} RowSelection;

static RowSelection _select_row(List cases) {
  RowSelection selected = { .homogeneous = 1 };
  int applicable_seen = 0;
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    selected.value = input;
    if (!destination) { selected.excess = 1; continue; }
    if (!applicable_seen) {
      selected.applicable = condition;
      applicable_seen = 1;
    }
    else if (!selected.applicable || !condition) selected.applicable = NULL;
    else if (selected.applicable !== condition)
      selected.applicable = %(expr (int)
        (op || (expr (int) (parens ${selected.applicable}))
               (expr (int) (parens $condition))));
    if (!selected.type) { selected.type = destination; selected.path = path; }
    else if (destination !== selected.type) selected.homogeneous = 0;
  }
  return selected;
}

static List _convert_initval_row(
  Compiler compiler, List row, List terminal, List native_target,
  List row_condition, int &?native_used) {
  (List original, List cases) = row;
  Array checked = [];
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    List slot = compiler.initializer_slot(native_target, path);
    List effective = _initializer_and(row_condition, condition);
    List value = !destination ? input
      : _initializer_conversion(
        compiler, input, destination, effective, slot, native_used);
    checked.push(%($condition $path $destination $value));
  }
  List header = NULL;
  Ast.initializer_cases(terminal.caddr(), header);
  List choices = checked.list_free();
  if (header) choices = cons(header, choices);
  List value = %(expr () (initval @choices));
  return _initializer_replace(original, value);
}

static List _convert_homogeneous_row(
  Compiler compiler, List original, RowSelection selected,
  List native_target, List row_condition, int &?native_used) {
  List slot = native_target
    ? compiler.initializer_slot(native_target, selected.path) : NULL;
  List condition = _initializer_and(
    row_condition, selected.excess ? selected.applicable : NULL);
  List converted = !selected.type ? selected.value
    : _initializer_conversion(
      compiler, selected.value, selected.type, condition, slot, native_used);
  return _initializer_replace(original, converted);
}

static List _convert_composite_row(
  Compiler compiler, List row, List native_target, List row_condition,
  List parent_condition, int &?native_used) {
  (List original, List cases) = row;
  RowSelection selected = _select_row(cases);
  List terminal = original;
  while (terminal.car() == <dotinit> || terminal.car() == <indexinit>)
    terminal = terminal.caddr();
  if (terminal.match(%(expr ? (initval *))))
    return row_condition === parent_condition ? original
      : _convert_initval_row(
        compiler, row, terminal, native_target, row_condition, native_used);
  if (selected.homogeneous)
    return _convert_homogeneous_row(
      compiler, original, selected, native_target, row_condition,
      native_used);
  return _mixed_initializer_row(
    compiler, row, selected.value, native_target, row_condition,
    parent_condition, native_used);
}

/* An unevaluated `*(native *) 0` typed as `viewed`, from which initializer
   rows name their slots. */
static List _zero_pointer_target(Type viewed, Type native) {
  Type pointer = cons(<*>, native);
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr $viewed (parens (expr $viewed
    (op * (expr $pointer (parens (expr $pointer (cast $pointer $zero))))))));
}

static List _convert_composite(
  Compiler compiler, List expr, Type target, List native_target,
  List parent_condition, int &?native_used) {
  if (!expr.caddr().cadr().cdr()) {
    List fresh = _empty_collection(compiler, target);
    if (fresh) return fresh;
  }
  if (!native_target) native_target = _zero_pointer_target(target, target);
  Array elements = [];
  List items = expr.caddr().cadr().cdr();
  int discarded = 0;
  List rows = _composite_rows(
    compiler, target, items, native_target, parent_condition, discarded);
  // Preserve C's excess warning only when this synthetic alternative applies.
  // The always-true ICE stays on a retained value, so braces remain braces.
  List excess_check = discarded
    ? _composite_excess_check(parent_condition) : NULL;
  foreach (List row, rows) {
    List row_condition = parent_condition;
    if (excess_check) {
      row_condition = _initializer_and(parent_condition, excess_check);
      excess_check = NULL;
    }
    List converted = _convert_composite_row(
      compiler, row, native_target, row_condition,
      parent_condition, native_used);
    elements.push(converted);
  }
  return %(expr $target (composite (commas @{elements.list_free()})));
}

static List _convert_initializer(
  Compiler c, List value, Type type, List target, int &?native_used) {
  if (value.match(%(expr ? (composite ?))))
    return _convert_composite(
      c, value, type.canonicalize(), target, NULL, native_used);
  return c.convert_expression(value, type.declared());
}

/** Converts an initializer using its declared native object for array
    bounds. */
List Compiler.convert_initializer(
  Compiler c, List value, Type type, List target) =>
  _convert_initializer(c, value, type, target, NULL);

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
