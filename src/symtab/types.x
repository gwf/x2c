/*  types.x -- symbol types */

// typedef resolution

/* The resolver uses a hop budget to terminate recursive typedefs, including
   a mutually recursive pair (typedef A B; typedef B A;). is_var_type resolves
   on nearly every converted expression, so this hot path must not allocate.

   Each user typedef costs two hops: its name node ("B") and the
   (typedef "B") node it maps to. The raw budget is twice the typedef bound
   and counts every hop, including direct typedef-to-typedef links. */
#define RESOLVE_KEY_MAX_TYPEDEFS 64
#define RESOLVE_KEY_MAX_HOPS (2 * RESOLVE_KEY_MAX_TYPEDEFS)

/** Resolves a canonical typedef key to the end of its declared chain. */
Type Sym.resolve_key(Sym s, Type key) {
  if (!key) return key;
  key = key.canonicalize();
  return _resolve_chain(s, key, NULL, key, 0);
}

/* Resolve a typedef chain, optionally stopping at a semantic type
   identity. origin is the type the caller asked about, kept only so an
   over-budget walk can name it instead of some mid-chain link. */
static Type _resolve_chain(Sym s, Type key, Type stop, Type origin, int hops) {
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  while (key.car() is <symbol> &&
         (key.car().symbol().is_type_qualifier() || key.car() == <unqual>))
    key = key.cdr();
  if (stop && key == stop) return key;
  if (key.is_typedef_name() || key.is_typedef()) {
    Type type = _typedef_target(s, key);
    if (type) return _resolve_chain(s, type, stop, origin, hops + 1);
  }
  match (key) case %((!or ?kind struct union)
      (binding ? ?spelling)):
    if (!s.field_order(key)) return $(kind, spelling);
  return key;
}

/* The hop budget does not distinguish cycles from long chains, so the
   diagnostic reports only excessive depth. `typedef Color Color;` is legal
   C; it binds ("Color") to (typedef "Color") and back. */
static void _typedef_budget_error(Sym s, Type origin) {
  $fail.symbols_typedef_depth(s.c, NULL, origin);
}

/* Semantic types contain no local aliases. A retained file type's spelling
   must keep its meaning when an inner declaration shadows that spelling. */
static Type _typedef_target(Sym s, Type key) {
  for (int i = s.base_scopes - 1; i >= 0; i--) {
    Var target;
    if (_scope_at(s, i).symbols.try_get(key, target)) return target;
  }
  return NULL;
}

/** Resolves one typedef hop and counts against the shared cycle budget.

    `hops` is an in-out counter initialized by the caller for the whole walk.
    Returns `NULL` for an unresolved link. The shared budget turns a cycle
    into the same diagnostic as full-chain resolution.
*/
Type Sym.next_typedef(Sym s, Type type, int &hops) {
  if (++hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, type);
  return type.is_typedef_name() || type.is_typedef()
       ? _typedef_target(s, type) : s.get(type);
}

/** Returns the name of the one file-scope typedef declared directly as
    `type`, or NULL when no typedef or several typedefs are.
*/
Type Sym.sole_typedef(Sym s, Type type) {
  String found = NULL;
  for (int i = 0; i < s.base_scopes; i++)
    foreach (Var (key, target) in _scope_at(s, i).symbols)
      if ((key ~= %(typedef ?(String name))) && target == type) {
        if (found && found != name) return NULL;
        found = name;
      }
  return found ? $(found) : NULL;
}

/** Resolves typedef bases while retaining every declarator qualifier. */
Type Sym.normalize_declared_type(Sym s, Type type) =>
  type ? _normalize_chain(s, type, type, 0) : NULL;

static Type _normalize_chain(Sym s, Type type, Type origin, int hops) {
  type = type.declared();
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  Type base = type.base_type();
  if (base.car() == <unqual>) {
    Type value = _normalize_chain(s, base.cdr(), origin, hops + 1);
    while (value.car() is <symbol> &&
           value.car().symbol().is_type_qualifier()) value = value.cdr();
    return _replace_type_base(type, base, value);
  }
  Type next = _typedef_base_step(s, type, base);
  return next ? _normalize_chain(s, next, origin, hops + 1) : type;
}

static Type _typedef_base_step(Sym s, Type type, Type base) {
  if (!base || (!base.is_typedef_name() && !base.is_typedef())) return NULL;
  Type next = _typedef_target(s, base);
  if (!next) next = _builtin_typedef_scalar(base);
  return next ? _replace_type_base(type, base, next) : NULL;
}

static Type _replace_type_base(Type type, Type base, Type replacement) {
  if (type === base) return replacement;
  if (!type) return type;
  return cons(type.car(), _replace_type_base(type.cdr(), base, replacement));
}

// local and builtin types

/** Resolves a block-local typedef to the type saved at its declaration.
    File-scope names retain their semantic identity. Local alias definitions
    are resolved before they are installed, so one lookup crosses the whole
    local chain without consulting names shadowed since its declaration.
*/
Type Sym.local_type(Sym s, Type type) {
  Type base = type.base_type();
  if ((base.is_aggregate_tag() || base.is_enum_tag()) &&
      base.cadr() is <string>)
    return _local_tag(s, type, base);
  return base.is_bare_typedef_name() ? _local_alias(s, type, base) : type;
}

// The binding of the nearest declaration replaces a block-scoped name.
static Type _local_tag(Sym s, Type type, Type base) {
  for (int i = s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = _scope_at(s, i);
    Var binding;
    if (scope.bindings.try_get(base, binding))
      return _replace_type_base(type, base, $(base.car(), binding));
  }
  return type;
}

// A local typedef name resolves to the target saved beside its marker.
static Type _local_alias(Sym s, Type type, Type base) {
  for (int i = s.scopes.len() - 1; i >= s.base_scopes; i--) {
    Map symbols = _scope_at(s, i).symbols;
    Var marker;
    if (!symbols.try_get(base, marker)) continue;
    Type declared = marker;
    if (!declared.is_typedef()) return type;
    Var target;
    if (!symbols.try_get(declared, target)) return type;
    return _replace_type_base(type, base, target);
  }
  return type;
}

/** Resolves a numeric typedef without reducing semantic object types.

    Returns `NULL` when resolution yields neither a numeric type nor a
    recognized builtin numeric typedef.
*/
Type Sym.resolve_numeric_type(Sym s, Type type) {
  Type scalar = type.scalar();
  if (scalar) return scalar;
  Type resolved = s.resolve_key(type);
  if (resolved.is_number()) return resolved;
  return _builtin_typedef_scalar(resolved);
}

/* System numeric aliases use exact String keys; Symbol encodings lose parts
   of some names. This private table and its canonical Type Lists have process
   lifetime. Source typedef resolution precedes this fallback. Width-dependent
   aliases use long when the host gives it the required width. */
static Map builtin_typedef_scalars = {
  "u8": %(unsigned char),       "uint8_t": %(unsigned char),
  "i8": %(signed char),         "int8_t": %(signed char),
  "u16": %(unsigned short),     "uint16_t": %(unsigned short),
  "i16": %(short),              "int16_t": %(short),
  "u32": %(unsigned),           "uint32_t": %(unsigned),
  "i32": %(int),                "int32_t": %(int),
  "wchar_t": %(int),
  "u64": sizeof(long) == 8 ? %(unsigned long) : %(unsigned long long),
  "uint64_t": sizeof(long) == 8 ? %(unsigned long) : %(unsigned long long),
  "uintptr_t": sizeof(long) == sizeof(void *)
             ? %(unsigned long) : %(unsigned long long),
  "size_t": sizeof(long) == sizeof(void *)
          ? %(unsigned long) : %(unsigned long long),
  "i64": sizeof(long) == 8 ? %(long) : %(long long),
  "int64_t": sizeof(long) == 8 ? %(long) : %(long long),
  "intptr_t": sizeof(long) == sizeof(void *) ? %(long) : %(long long),
  "ptrdiff_t": sizeof(long) == sizeof(void *) ? %(long) : %(long long),
  "ssize_t": sizeof(long) == sizeof(void *) ? %(long) : %(long long),
  "off_t": %(long),             "time_t": %(long),
  "u128": %(unsigned long long), "i128": %(long long),
  "f32": %(float), "f64": %(double), "f128": %(long double)
};

static Type _builtin_typedef_scalar(Type key) {
  if (!key.is_bare_typedef_name()) return NULL;
  return builtin_typedef_scalars.getdefault(key.car(), (List) NULL);
}

// value types

/** Returns a type's `Var` tag and optionally stores its resolved type.

    `resolved` receives the final type even when the result is zero because no
    `Var` tag is registered. A null input stores `NULL` and returns zero.
*/
Symbol Sym.var_tag_for_type(Sym s, Type type, Type &?resolved) {
  Type origin = type.canonicalize();
  return _var_tag_chain(s, origin, origin, resolved, 0);
}

static Symbol _var_tag_chain(
  Sym s, Type type, Type origin, Type &?resolved, int hops) {
  type = type.canonicalize();
  Symbol tag = type.var_tag();
  if (tag) {
    if (resolved) resolved = type;
    return tag;
  }
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  Type next = _typedef_base_step(s, type, type.base_type());
  if (next) return _var_tag_chain(s, next, origin, resolved, hops + 1);
  if (resolved) resolved = type;
  return 0;
}

/** Reports whether `type` reaches the named `Var` value type. */
int Sym.is_var_type(Sym s, Type type) => s.is_named_value_type(type, "Var");

/** Reports whether `type` reaches the named `String` value type. */
int Sym.is_string_type(Sym s, Type type) =>
  s.is_named_value_type(type, "String");

/** Reports whether `type` reaches the named `Array` value type. */
int Sym.is_array_type(Sym s, Type type) =>
  s.is_named_value_type(type, "Array");

/** Reports whether `type` reaches the named `Map` value type. */
int Sym.is_map_type(Sym s, Type type) => s.is_named_value_type(type, "Map");

/** Reports whether `type` reaches a named value type before its definition. */
int Sym.is_named_value_type(Sym s, Type type, String name) {
  if (!type || !name) return 0;
  Type wanted = $(name), origin = type.canonicalize();
  type = _resolve_chain(s, origin, wanted, origin, 0);
  return type == wanted;
}

// aggregate fields

/** Returns an aggregate field's declared type, or `NULL`.
    A member of an anonymous struct or union belongs to its enclosing
    aggregate in C, so unnamed rows are searched the way a designated
    initializer already reaches them.
*/
Type Sym.lookup_field(Sym s, Type type, List field) {
  Type object = s.normalize_declared_type(type);
  type = s.resolve_key(object);
  if (!type || !type.is_aggregate_tag()) return NULL;
  Type found = s.get(%( @type @field ));
  if (found) return found.qualify(object);
  foreach (List row in s.field_order(type).cdr()) {
    Type member = row.cadr();
    if (row.car() || !s.resolve_key(member).is_aggregate()) continue;
    found = s.lookup_field(member, field);
    if (found) return found.qualify(object);
  }
  return NULL;
}

/** Records declaration AST fields in source order after binding finishes.

    `Field` types already use member keys. Unnamed rows retain their type
    and an empty name so initializer traversal preserves anonymous subobjects.
*/
void Sym.declare_field_order(Sym s, Type type, List fields) {
  Array rows = [];
  foreach (List declaration in fields) {
    declaration = Ast.without_origin(declaration);
    if (declaration.car() == <c-assert>) continue;
    List bindings = declaration.caddr();
    foreach (List declarator in bindings.cdr())
      rows.push(_field_row(s, type, declaration, declarator));
  }
  s.set(%(@type "field-order"), %(fields @(rows.list_free())));
}

static List _field_row(Sym s, Type type, List declaration, List declarator) {
  String name = Ast.binding_spelling(declarator.cadr());
  Type declared = name ? s.get($(@type, name))
    : %(declare $(declaration.cadr()) (bindings $declarator))
      .type_from_ast().declared();
  return $(name, declared);
}

/** Returns recorded fields in source order, or `NULL`. */
List Sym.field_order(Sym s, Type type) => s.get(%(@type "field-order"));

/** Records that the field `name` of `aggregate` was declared with the field
    keyword `mark`, such as `delegate`, and that `aggregate` declares one.
*/
void Sym.mark_field(Sym s, Type aggregate, Symbol mark, String name) {
  s.set($(@aggregate, mark, name), $(mark));
  s.set($(@aggregate, mark), $(mark));
}

/** Returns the `(NAME TYPE)` rows of the fields of `aggregate` declared with
    `mark`, in declaration order.
*/
List Sym.marked_fields(Sym s, Type aggregate, Symbol mark) {
  List order = s.field_order(aggregate), Array rows = [];
  foreach (List row in order ? order.cdr() : NULL) {
    String name = row.car();
    if (name && s.get($(@aggregate, mark, name))) rows.push(row);
  }
  return rows.list_free();
}

/** Resolves typedefs or one pointer layer to an aggregate tag, or `NULL`. */
Type Sym.aggregate_of(Sym s, Type type) {
  type = type.canonicalize();
  int hops = 0;
  while (type && !type.is_aggregate_tag()) {
    if (type.is_pointer()) {
      type = s.resolve_key(type.dereference());
      break;
    }
    type = s.next_typedef(type, hops);
  }
  return type && type.is_aggregate_tag() ? type : NULL;
}

/** Compares only List rest conventions in corresponding callable positions,
    including callback parameters and returned function pointers. Native C
    checking owns other type differences, but cannot see this convention.
*/
int Sym.same_list_rest_convention(Sym s, Type source, Type target) {
  if (source == target) return 1;
  source = s.resolve_key(source);
  target = s.resolve_key(target);
  if (source == target) return 1;
  List left = NULL, right = NULL, Type left_result = NULL, right_result = NULL;
  if (source.function_parts(left, left_result) &&
      target.function_parts(right, right_result)) {
    if (source.list_rest_index() != target.list_rest_index()) return 0;
    while (left && right) {
      if (!s.same_list_rest_convention(left.car(), right.car())) return 0;
      left = left.cdr(), right = right.cdr();
    }
    return s.same_list_rest_convention(left_result, right_result);
  }
  if (source.is_pointer() && target.is_pointer())
    return s.same_list_rest_convention(
      source.dereference(), target.dereference());
  return 1;
}
