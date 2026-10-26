/*  loaded.x -- meta group loaded

    Copyright (c) 2026 Gary William Flake.
*/

// loaded program entries

/* Parameter arrays have pointer calling conventions, and typedef spellings
   do not change the two standard main signatures. */
static int _main_arity(Compiler c, Type type) {
  List parameters = NULL;
  Type result = NULL;
  type.function_parts(parameters, result);
  if (c.sym.normalize_declared_type(result).canonicalize() != %(int))
    return -1;
  if (!parameters) return 0;
  if (parameters.len() != 2) return -1;
  Type count = c.sym.normalize_declared_type(parameters.car()).canonicalize();
  Type values = c.sym.normalize_declared_type(parameters.cadr());
  if (values.is_array()) values = values.dereference().reference();
  return count == %(int) && values.canonicalize() == %(* * char) ? 2 : -1;
}

/* Keep the source binding and calling convention for recursion and other
   native callers. Only the helper's public entry takes independent data. */
static List _loaded_entry(Compiler c, List binding, Type type) {
  int arity = _main_arity(c, type);
  if (arity < 0)
    $fail.meta_group_main_signature(c, NULL);
  List entry = c.sym.introduce(c.fresh_name("loaded_entry"));
  List target = %(expr $type (ident $binding));
  if (!arity)
    return c.bind_syntax(
      $!Unit{ static int $entry(void) { return $target(); } }, <unit>, NULL);
  return c.bind_syntax(
    $!Unit{
      static int $entry(Array values) {
        int count = values.len();
        char **argv = xcalloc((size_t) count + 1, sizeof(char *));
        for (int i = 0; i < count; i++) {
          String text = values[i];
          size_t size = text.len();
          argv[i] = xcalloc(size + 1, 1);
          if (size) memcpy(argv[i], (char *) text, size);
        }
        return $target(count, argv);
      }
    }, <unit>, NULL);
}

/** Exposes a loaded unit's main through the ordinary helper target table.
    Native calls retain its declared signature; the public argc/argv entry
    takes an Array of Strings. A renamed main still returns zero on falling
    through its closing brace. Source text and tokens are unchanged.
*/
void Compiler.prepare_loaded_main(Compiler c, Array nodes) {
  for (int i = 0; i < nodes.len(); i++)
    match (nodes[i])
      case %(function ?spec (!set ?declarator
              (bind (!set ?binding (binding ? "main")) *)) (block *body)): {
        Type type = %(declare $spec (bindings $declarator)).type_from_ast();
        List entry = _loaded_entry(c, binding, type);
        nodes[i] = %(function $spec $declarator
          (block @body (return (int) $($!int{ 0 }))));
        for (int j = c.meta_group.len() - 1; j >= 0; j--)
          if (c.meta_group[j] ~= %(function ? "main" ?))
            c.meta_group.remove(j);
        Type adapted = %(declare $(entry.cadr())
          (bindings $(entry.caddr()))).type_from_ast();
        c.meta_group.push(
          %(function $entry "main" $(c.func_signature(adapted))));
        return;
      }
}

/** Adds a loaded unit's public functions and object accessors to its targets.
    Meta closure must finish first so these entries retain runtime semantics.
    Existing meta entries and the adapted main keep their original targets.
*/
void Compiler.prepare_loaded_functions(Compiler c, Array nodes) {
  Map present = {};
  foreach (List entry in c.meta_group)
    if (entry ~= %(function ? ?name ?)) present[name] = 1;
  Var identity, String name;
  foreach (List node in nodes)
    if (_function_identity(node, identity, name) &&
        c.public_native_function(node, name) && !(name in present)) {
      c.group_meta_function(node);
      present[name] = 1;
    }
  foreach (List node in nodes)
    if (node ~= %(declare ?spec (bindings *rows)))
      foreach (List row in rows) _loaded_global(c, spec, row, present);
}

/* Each path has one accessor, with one parameter per array dimension.
   Native sizeof owns extents, including bounds inferred from initializers. */
static typedef struct LoadedPath {
  Compiler compiler;
  Array descriptions;
  String name;
  List parameters, checks;
} LoadedPath;

static Type _loaded_scalar(Compiler c, Type type) {
  if (type.is_bitfield()) type = type.base_type();
  if (c.sym.is_string_type(type)) return %("String");
  if (c.sym.is_named_value_type(type, "Symbol")) return %("Symbol");
  if (c.sym.is_named_value_type(type, "bool") ||
      c.sym.is_named_value_type(type, "_Bool")) return %(int);
  Type numeric = c.sym.resolve_numeric_type(type);
  if (!numeric || !numeric.is_number()) return NULL;
  return numeric.is_enum() ? numeric.promote() : numeric.canonicalize();
}

static Type _loaded_shape(Compiler c, Type type) =>
  c.sym.resolve_key(c.sym.normalize_declared_type(type));

static int _loaded_aggregate(Compiler c, Type type, int root) {
  Type shape = _loaded_shape(c, type);
  if (shape ~= %(struct ?)) return !!c.sym.field_order(shape);
  if (!shape.is_array()) return 0;
  List dimension = shape.car();
  return root || (dimension.cdr() && dimension.cadr().list());
}

static List _loaded_length(List target) =>
  $!size_t{ sizeof($target) / sizeof($target[0]) };

/* Snapshot traversal consumes one shared budget, including containers.
   Unsupported fields stay visible without exposing their native storage. */
static List _loaded_snapshot(
  Compiler c, Type type, List target,
  List budget, int root, Array statements) {
  Type scalar = _loaded_scalar(c, type);
  if (scalar) return $!($scalar){ ($scalar) $target };
  if (!_loaded_aggregate(c, type, root))
    return $!String{ String.new("<unavailable>") };
  Type shape = _loaded_shape(c, type);
  List value = c.sym.introduce(c.fresh_name("snapshot"));
  List body;
  if (shape.is_array()) {
    List index = c.sym.introduce(c.fresh_name("index"));
    Type element = c.sym.normalize_declared_type(type).dereference();
    List selected = %(expr $element
      (index $target $($!(unsigned long long){ $index })));
    Array items = auto [];
    List item = _loaded_snapshot(c, element, selected, budget, 0, items);
    body = $!{
      Array $value = [];
      unsigned long long $index = 0;
      for (; $index < $(_loaded_length(target)); $index++) {
        if ($budget <= 0) { $value.push("..."); break; }
        $budget--;
        @(items.list())
        $value.push($item);
      }
    };
  }
  else {
    Array fields = auto [];
    _loaded_snapshot_fields(c, type, target, value, budget, fields);
    body = $!{ Map $value = {}; @(fields.list()) };
  }
  statements.push(body);
  return shape.is_array() ? $!Array{ $value } : $!Map{ $value };
}

static void _loaded_snapshot_fields(
  Compiler c, Type type, List target, List value, List budget, Array fields) {
  foreach (List row in c.sym.field_order(_loaded_shape(c, type)).cdr()) {
    (String name, Type field) = row;
    field = field.qualify(c.sym.normalize_declared_type(type));
    if (!name) {
      if (_loaded_shape(c, field) ~= %(struct ?))
        _loaded_snapshot_fields(c, field, target, value, budget, fields);
      continue;
    }
    List selected = %(expr $field (op . $target ($name)));
    Array items = auto [];
    List item = _loaded_snapshot(c, field, selected, budget, 0, items);
    fields.push(
      $!{
        if ($budget > 0) {
          $budget--;
          @(items.list())
          $value[$name] = $item;
        }
        else $value["..."] = "...";
      });
  }
}

static void _loaded_accessor(
  LoadedPath path, Type bridge, List body, int setter) {
  Compiler c = path.compiler;
  List name = c.sym.introduce(c.fresh_name("loaded_access"));
  List parameters = path.parameters;
  if (setter) parameters = %(@parameters
    (param $bridge (bind $(c.sym.introduce("value")) ()))
    (param (int) (bind $(c.sym.introduce("operation")) ())));
  List function = c.bind_syntax(
    %(function (static @bridge)
      (bind $name ((fnmod (params @parameters))))
      (block @(path.checks) $body)), <unit>, NULL);
  Type type = %(declare $(function.cadr())
    (bindings $(function.caddr()))).type_from_ast();
  String request = (setter ? "set global " : "get global ") + path.name;
  c.meta_group.push(%(function $function $request $(c.func_signature(type))));
}

/* The selector is called only inside the helper. Its pointer-bearing List
   never enters the datum transport. Native reference readers use its type. */
static void _loaded_address(LoadedPath path, Type type, List target) {
  if (type.is_bitfield()) return;
  Compiler c = path.compiler;
  List name = c.sym.introduce(c.fresh_name("loaded_address"));
  List native_type = c.cache_literal_list(
    c.sym.normalize_declared_type(type).declared());
  List function = c.bind_syntax(
    %(function (static "List")
      (bind $name ((fnmod (params @(path.parameters)))))
      (block @(path.checks) $($!{
        return cons($native_type, cons((void *) &$target, NULL));
      }))), <unit>, NULL);
  Type signature = %(declare $(function.cadr())
    (bindings $(function.caddr()))).type_from_ast();
  c.meta_group.push(
    %(function $function $("address global " + path.name)
      $(c.func_signature(signature))));
}

static void _loaded_path(LoadedPath path, Type type, List target, int root) {
  Compiler c = path.compiler;
  Type bridge = _loaded_scalar(c, type);
  if (!bridge && !_loaded_aggregate(c, type, root)) return;
  _loaded_address(path, type, target);
  int writable = bridge &&
    !(<const> in c.sym.normalize_declared_type(type));
  if (bridge) {
    _loaded_accessor(path, bridge, $!{ return ($bridge) $target; }, 0);
    if (writable)
      _loaded_accessor(path, bridge, _loaded_setter(bridge, target), 1);
  }
  else {
    bridge = %("Var");
    List budget = c.sym.introduce(c.fresh_name("remaining"));
    Array statements = auto [];
    List snapshot = _loaded_snapshot(
      c, type, target, budget, root, statements);
    _loaded_accessor(
      path, bridge,
      $!{ int $budget = 100; @(statements.list()) return $snapshot; }, 0);
  }
  path.descriptions.push(
    $(path.name, bridge, writable, path.parameters.len()));
  Type shape = _loaded_shape(c, type);
  if (shape.is_array()) {
    List index = c.sym.introduce(c.fresh_name("index"));
    List argument = $!(long long){ $index };
    path.parameters = %(@(path.parameters)
      (param (long long) (bind $index ())));
    path.checks = $(@(path.checks), $!{
      if ($argument < 0 || (unsigned long long) $argument >=
          $(_loaded_length(target)))
        raise %(repl (reason "loaded array index out of bounds"));
    });
    path.name += "[]";
    Type element = c.sym.normalize_declared_type(type).dereference();
    _loaded_path(
      path, element, %(expr $element (index $target $argument)), 0);
  }
  else if (shape ~= %(struct ?))
    _loaded_fields(path, type, target);
}

static void _loaded_fields(LoadedPath path, Type type, List target) {
  Compiler c = path.compiler;
  foreach (List row in c.sym.field_order(_loaded_shape(c, type)).cdr()) {
    (String name, Type field) = row;
    field = field.qualify(c.sym.normalize_declared_type(type));
    if (!name) {
      if (_loaded_shape(c, field) ~= %(struct ?))
        _loaded_fields(path, field, target);
      continue;
    }
    LoadedPath selected = path;
    selected.name += "." + name;
    _loaded_path(
      selected, field, %(expr $field (op . $target ($name))), 0);
  }
}

static void _loaded_global(Compiler c, Type spec, List row, Map present) {
  int initialized = 0;
  if (row ~= %(op = ?bound ?)) { row = bound; initialized = 1; }
  if (spec.is_static() || (spec.is_extern() && !initialized)) return;
  if (row ~= %(bind ?binding ?)) {
    String name = Ast.binding_spelling(binding);
    if (!name || name in present || $(name) in c.sym.file_statics()) return;
    Type type = %(declare $spec (bindings $row)).type_from_ast();
    if (!_loaded_scalar(c, type) &&
        !_loaded_aggregate(c, type, initialized)) return;
    LoadedPath path = {.compiler = c, .descriptions = [], .name = name};
    _loaded_path(
      path, type,
      %(expr $(type.declared()) (ident $binding)), initialized);
    c.meta_group.push(%(global $name $(path.descriptions.list_free())));
    present[name] = 1;
  }
}

/* Native postfix updates read and write once, including volatile objects. */
static List _loaded_setter(Type bridge, List target) =>
  bridge.is_number() ? $!{
    if (operation == 1) return ($bridge) $target++;
    if (operation == 2) return ($bridge) $target--;
    return ($bridge) ($target = value);
  } : $!{
    (void) operation;
    return ($bridge) ($target = value);
  };
