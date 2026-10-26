/*  conversion.x -- initializer values and native type definitions */

// initializer conversion

/** Converts an initializer using its declared native object for array
    bounds.
*/
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
  /* Preserve C's excess warning only when this synthetic alternative applies.
     The always-true ICE stays on a retained value, so braces remain braces. */
  List excess_check = discarded
    ? _composite_excess_check(parent_condition) : NULL;
  foreach (List row in rows) {
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
  foreach (List row in c.initializer_rows(target, items, native_target)) {
    List cases = row.cadr();
    int available = 0;
    foreach (List choice in cases)
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
  foreach (List choice in cases) {
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
  foreach (List choice in cases) {
    (List condition, List path, Type destination, List input) = choice;
    List value = _convert_case(
      c, choice, input, native_target, row_condition, native_used);
    checked.push($(condition, path, destination, value));
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
    case %((!or ?tag dotinit indexinit) ?key ?inner):
      return $(tag, key, _replace_value(inner, value));
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
    (composite (commas $($!int{ 0 }))))));
}

static List _rejected_initializer(
  Type type, List condition, List zero) {
  List size = %(expr (int) (op ? $condition
    (expr (int) (literal (int) "-1"))
    $($!int{ 1 })));
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
  foreach (List choice in cases) {
    (List condition, List path, Type destination, List input) = choice;
    List result = _convert_case(
      c, choice, prepared, native_target, row_condition, native_used);
    int identity = result === prepared;
    match (result)
      case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
        if (yes === prepared) identity = 1;
    if (!identity) native_identity = 0;
    converted.push($(condition, path, destination, result));
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
    case %((!or ?kind dotinit indexinit) ?key ?inner):
      return $(kind, key, _capture_leaves(c, inner, inputs));
    case %(expr ?type $($source_composite_content(%(*items)))): {
      Array captured = [];
      foreach (List item in items)
        captured.push(_capture_leaves(c, item, inputs));
      return %(expr $type $(source_composite_content(
        captured.list_free())));
    }
    /* A value leaf; an internally constructed native call may have a bare
       string callee. */
    case %(expr ?type (!or $($source_identifier_content(%(*)))
                           $($source_operator_content(%(*)))
                           $($source_cast_content(%(*)))
                           $($grouped(?))
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
  inputs.push($(formal, value));
  return %(expr $type $formal);
}

// Capturing native leaves must preserve construction and cache facts.
static int _is_literal(List value) {
  match (value) {
    case %(expr ? $($source_literal_content(%(*)))): return 1;
    case %(expr ? $($grouped(?inner))):
      return _is_literal(inner);
    case %(expr ? $($source_cast_content(%(? ?inner)))):
      return _is_literal(inner);
  }
  return 0;
}

static List _materialize_mixed_row(
  Compiler c, List original, List source,
  Array converted, Array captured) {
  String formal = c.fresh_name("initializer_value");
  List placeholder = %(expr $(source.cadr()) $formal);
  List values = converted.list_free();
  List adapted = _adapt_choices(c, source, values, placeholder);
  if (adapted) values = adapted;
  Array replaced = [];
  List inputs = captured.list_free();
  int uses_input = !!adapted;
  foreach (List choice in values) {
    (List condition, List path, Type destination, List result) = choice;
    List substituted =
      !destination && source.match(%(expr ? (composite *)))
        ? result : result.search_replace(%(!quote $source), placeholder);
    if (substituted !== result) uses_input = 1;
    replaced.push($(condition, path, destination, substituted));
  }
  List choices = replaced.list_free();
  if (uses_input) inputs = cons($(formal, source), inputs);
  if (inputs) choices = cons(%(input @inputs), choices);
  List result = %(expr () (initval @choices));
  return _replace_value(original, result);
}

static List _adapt_choices(
  Compiler c, List source, List choices, List placeholder) {
  Type from = _adapter_type(c, source.cadr());
  if (!from || !Ast.contains_head(source, <fields>)) return NULL;
  Array prepared = auto [];
  foreach (List choice in choices) {
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
    prepared.push($(condition, path, destination, value));
  }
  Array adapted = [];
  foreach (List choice in prepared.list()) {
    (List condition, List path, Type destination, List value) = choice;
    List adapter = _value_adapter(c, source, value);
    Type callable = adapter.cadr(), result = callable.apply();
    Macro called = $called;
    value = c.rebuild_expression(
      result, called(adapter, $(placeholder)));
    adapted.push($(condition, path, destination, value));
  }
  return adapted.list_free();
}

static List _value_adapter(
  Compiler c, List source, List converted) {
  Type from = _adapter_type(c, source.cadr());
  Type result = _adapter_type(c, converted.cadr());
  List formal = %(expr $(source.cadr()) "_x2c_gensym_initializer_argument");
  List body = converted.search_replace(%(!quote $source), formal);
  List key = %(iadapt $from $result $body), adapter = NULL;
  $adapter.memo(c, key, adapter) {
    List parameter = c.sym.introduce(c.fresh_name("initializer_arg"));
    List input = $!($(source.cadr())){ $parameter };
    body = body.search_replace(%(!quote $formal), input);
    List binding = c.sym.introduce(c.fresh_name("initializer_adapt"));
    c.add_early(
      c.wrapper_function(
        %(static @result), binding, $(from.parameter_ast(parameter)),
        %((return $result $body))));
    Type callable = %((func ($from)) @result);
    adapter = $!($callable){ $binding };
  }
  return adapter;
}

/* Inline native type definitions cannot be copied into conversion arms.
   A selected by-value adapter consumes the original expression just once. */
static Type _adapter_type(Compiler c, Type type) {
  if (c.sym.is_var_type(type)) return %("Var");
  Type scalar = c.sym.resolve_key(type).scalar();
  return scalar === %(void) ? NULL : scalar;
}

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
    expressions reuse that exact layout without a new scope.
*/
List Compiler.initializer_native_types(Compiler c, Type type) {
  Type base = type.base_type(), definition = base, reference = base;
  match (base) {
    case %(!or ((!or ?kind struct union) (gensym ? ?) ?body)
               ((!or ?kind struct union) (!set ?body (fields *)))): {
      String name = c.fresh_name("initializer_type");
      definition = $(kind, name, body);
      reference = $(kind, name);
    }
    case %((!or ?kind struct union) ?name (fields *)):
      reference = $(kind, name);
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
  return $(definition, reference);
}

static Var _native_modifier(Compiler c, Var modifier, Var &reused) {
  reused = modifier;
  match (modifier)
    case %(dim ?bound): {
      unsigned long long count;
      if (!bound || _literal_integer(bound, count)) return modifier;
      match (bound)
        case %(expr ? $($sizeof_grouped(%(struct ?tag (fields
            (declare (char) (bindings (bind ? ((dim ?)))))))))): {
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
