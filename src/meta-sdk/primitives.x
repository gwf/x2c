/*  primitives.x -- compile-time SDK primitives

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_symbol_set_value(Expr $value) =>
  MetaContext.reject(
    "_x2c_symbol_set requires Symbols", $("value:", $value.repr()));

static macro Stmt $fail.meta_sdk_symbol_set_duplicate(
  Expr $values, Expr $duplicate) =>
  MetaContext.reject(
    "_x2c_symbol_set requires distinct Symbols",
    $("symbol:", $values[$duplicate].repr()));

static alias fail_native_declarations to MetaContext.reject(
  "native module sources declare no meta function",
  %("declare each exported function with a bodyless meta prototype"));

/** Implements `x2c_meta_definition_hashes`, declared in `lib/meta.x`. */
Map x2c_meta_definition_hashes(void) {
  _require_expansion("x2c_meta_definition_hashes");
  Compiler c = active.expander;
  Map hashes = {};
  foreach (String name in c.meta_calls.keys())
    hashes[name] = c.meta_hashes[name];
  return hashes;
}

/** Adds the SDK primitives the compiler's shipped sources call through
    `lib/compiler-meta.x` to the built-in targets `rows`.
*/
void Compiler.add_sdk_targets(Map rows) {
  rows["_x2c_literal_list"] = (Func) MetaContext.literal_list;
  rows["_x2c_native_rows"] = (Func) _native_rows;
  rows["_x2c_declared_rows"] = (Func) _declared_targets;
  rows["_x2c_meta_linked_hashes"] = (Func) _linked_hashes;
  rows["_x2c_prelude_records"] = (Func) _linked_prelude;
  rows["_x2c_symbol_set"] = (Func) _symbol_set;
}

/** Returns `values`, such as a signature, as a cached literal
    of the expanding unit.
*/
List MetaContext.literal_list(List values) =>
  active.expander.cache_literal_list(values);

// compile-time SDK primitives

/* Imported functions refer to their provider's shared definition hash.
   Fully parsed copies retain their own hashes and precise references. */
static Map _linked_hashes(void) {
  _require_expansion("_x2c_meta_linked_hashes");
  Compiler c = active.expander;
  Map rows = {};
  c.add_linked_meta_provider_hashes(rows);
  foreach ((String name, List source) in c.project_meta)
    if (source ~= %(? ?provider)) {
      Map hashes = c.meta_provider_hashes(provider);
      rows[name] = $(hashes[name], provider);
    }
  foreach (String name in c.meta_calls.keys())
    rows[name] = $(c.meta_hashes[name], c.meta_calls[name]);
  return rows;
}

/* The prelude components' interface records, which `src/collect/collect.x` links
   into the compiler it is translated into. */
static Map _linked_prelude(void) {
  _require_expansion("_x2c_prelude_records");
  return active.expander.linked_prelude_records();
}

static Var _symbol_set(List values) {
  _require_expansion("_x2c_symbol_set");
  foreach (Var value in values)
    if (value is not <symbol>)
      $fail.meta_sdk_symbol_set_value(value);
  int duplicate = -1;
  List expression = active.expander.symbol_set_expression(values, duplicate);
  if (duplicate >= 0)
    $fail.meta_sdk_symbol_set_duplicate(values, duplicate);
  return expression;
}

/* `leading`, the rows of one target inventory, then `trailing`. The
   compiler's own operations are its `x2c_`, `Code_`, and `Type_` targets;
   runtime Lisp binds the others directly, and the compiler also binds
   those that take a callback. An `_x2c_` name is a built-in algorithm,
   which no C function of that name implements. */
static List _native_rows(Symbol inventory, List leading, List trailing) {
  Array rows = auto leading;
  foreach (List row in Compiler.native_meta_targets(
             NULL, inventory == <runtime>)) {
    String name = row.car();
    int own = name.startswith("x2c_") || name.startswith("Code_") ||
              name.startswith("Type_");
    if (!name.startswith("_x2c_") && own == (inventory == <compiler>))
      rows.push(row);
  }
  foreach (Var row in trailing) rows.push(row);
  return rows;
}

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _declared_targets(List paths) {
  List rows = Compiler.native_meta_targets(paths, 1);
  if (!rows)
    fail_native_declarations;
  return rows;
}
