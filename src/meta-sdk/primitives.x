/*  primitives.x -- compile-time SDK primitives

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_symbol_set_value(Expr $value) =>
  MetaContext.reject(
    "_x2c.symbol-set requires Symbols", %("value:" ${$value.repr()}));

static macro Stmt $fail.meta_sdk_symbol_set_duplicate(
  Expr $values, Expr $duplicate) =>
  MetaContext.reject(
    "_x2c.symbol-set requires distinct Symbols",
    %("symbol:" ${$values[$duplicate].repr()}));

static macro Stmt $fail.meta_sdk_native_declarations() =>
  MetaContext.reject(
    "native module sources declare no meta function",
    %("declare each exported function with a bodyless meta prototype"));

/** Answers `x2c.meta.definition.hashes`, declared in `lib/meta.x`. */
Map x2c_meta_definition_hashes(void) {
  _require_expansion("x2c.meta.definition.hashes");
  Compiler c = active.expander;
  Map hashes = {};
  foreach (String name in c.meta_calls.keys())
    hashes[name] = c.meta_hashes[name];
  return hashes;
}

/* Imported functions refer to their provider's shared definition hash.
   Fully parsed copies retain their own hashes and precise references. */
static Map _linked_hashes(void) {
  _require_expansion("_x2c.meta.linked.hashes");
  Compiler c = active.expander;
  Map rows = {};
  c.add_linked_meta_provider_hashes(rows);
  foreach ((String name, List source) in c.project_meta)
    match (source) case %(? ?provider): {
      Map hashes = c.meta_provider_hashes(provider);
      rows[name] = %(${hashes[name]} $provider);
    }
  foreach (String name in c.meta_calls.keys())
    rows[name] = %(${c.meta_hashes[name]} ${c.meta_calls[name]});
  return rows;
}

/* The prelude components' interface records, which `src/collect/collect.x` links
   into the compiler it is translated into. */
static Map _linked_prelude(void) {
  _require_expansion("_x2c.prelude.linked");
  return active.expander.linked_prelude_records();
}

/** Returns `values`, such as a Lisp-built signature, as a cached literal
    of the expanding unit. */
List MetaContext.literal_list(List values) =>
  active.expander.cache_literal_list(values);

static Var _symbol_set(List values) {
  _require_expansion("_x2c.symbol-set");
  foreach (Var value in values)
    if (value is not <symbol>)
      $fail.meta_sdk_symbol_set_value(value);
  int duplicate = -1;
  List expression = active.expander.symbol_set_expression(values, duplicate);
  if (duplicate >= 0)
    $fail.meta_sdk_symbol_set_duplicate(values, duplicate);
  return expression;
}

static List _native_targets(void) {
  Array rows = [];
  foreach (List row in Compiler.native_meta_targets(NULL, 0))
    if (!_builtin_algorithm(row.car())) rows.push(row);
  return rows.list_free();
}

/* An `_x2c_` name is a built-in algorithm, which no C function of that
   name implements. */
static int _builtin_algorithm(String name) => name.startswith("_x2c_");

/* `leading`, the rows of one target inventory, then `trailing`. The
   compiler's own operations are its `x2c_`, `Code_`, and `Type_` targets;
   runtime Lisp binds the others directly, and the compiler also binds
   those that take a callback. */
static List _native_rows(Symbol inventory, List leading, List trailing) {
  Array rows = auto leading;
  foreach (List row in Compiler.native_meta_targets(
             NULL, inventory == <runtime>)) {
    String name = row.car();
    int own = name.startswith("x2c_") || name.startswith("Code_") ||
              name.startswith("Type_");
    if (!_builtin_algorithm(name) && own == (inventory == <compiler>))
      rows.push(row);
  }
  foreach (Var row in trailing) rows.push(row);
  return rows;
}

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _declared_targets(List paths) {
  List rows = Compiler.native_meta_targets(paths, 0);
  if (!rows)
    $fail.meta_sdk_native_declarations();
  return rows;
}

/** Adds the SDK primitives the compiler's shipped sources call through
    `lib/compiler-meta.x` to the built-in targets `rows`. */
void Compiler.add_sdk_targets(Map rows) {
  rows["_x2c_literal_list"] = (Func) MetaContext.literal_list;
  rows["_x2c_native_rows"] = (Func) _native_rows;
  rows["_x2c_declared_rows"] = (Func) _declared_targets;
  rows["_x2c_meta_linked_hashes"] = (Func) _linked_hashes;
  rows["_x2c_prelude_records"] = (Func) _linked_prelude;
  rows["_x2c_symbol_set"] = (Func) _symbol_set;
}

// lisp primitives

/** Binds the internal primitives the compile-time SDK library wraps into
    `lisp`, under their `_x2c.` names. */
void Compiler.bind_sdk_primitives(Lisp lisp) {
  $lisp.bind(lisp, "_x2c.meta.linked.hashes", _linked_hashes);
  $lisp.bind(lisp, "_x2c.prelude.linked", _linked_prelude);
  $lisp.bind(lisp, "_x2c.function.reference", MetaContext.function_reference);
  $lisp.bind(lisp, "_x2c.function.native-type", Code.native_signature);
  $lisp.bind(lisp, "_x2c.literal.list", MetaContext.literal_list);
  $lisp.bind(lisp, "_x2c.native-meta.targets", _native_targets);
  $lisp.bind(lisp, "_x2c.native-meta.declared", _declared_targets);
  $lisp.bind(lisp, "_x2c.symbol-set", _symbol_set);
}
