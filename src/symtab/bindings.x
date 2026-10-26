/*  bindings.x -- symbol bindings */

// definitions

/** Sets a semantic type for `key` in the required active scope. */
void Sym.set(Sym s, List key, List type) {
  Map scope = _scope_at(s, -1).symbols;
  if (log_should_log(<debug>, <symtab>))
    log_debug(<symtab>, %(func "Sym.set"), %(key $key), %(val $type));
  s.put(scope, key, type);
  if (_retained_member(key)) s.put(s.binding_facts, %(aggfact $key), type);
}

static int _retained_member(List key) {
  match (key) {
    case %(struct (binding ? ?) ? *): return 1;
    case %(struct (gensym ? ?) ? *): return 1;
    case %(union (binding ? ?) ? *): return 1;
    case %(union (gensym ? ?) ? *): return 1;
    default: return 0;
  }
}

/** Defines `key` and returns its stable binding in the active scope. */
List Sym.define(Sym s, List key, List type) {
  SymScope *scope = _scope_at(s, -1);
  s.set(key, type);
  _seed_var_tag(s, key, type);
  return _scope_binding(s, *scope, key);
}

/** Defines `name` in the active scope as an alias of the parsed
    `expression` and returns its binding. The row carries the expression's
    type; the `(alias binding)` fact carries the expression. */
List Sym.define_alias(Sym s, String name, List expression) {
  List type = NULL;
  match (expression) case %(expr ?expression_type ?): type = expression_type;
  List binding = s.define($(name), type);
  s.put(s.binding_facts, %(alias $binding), expression);
  _scope_at(s, -1).aliases++;
  s.aliases++;
  return binding;
}

/** Removes the alias row `name` of the active scope, with its binding and
    its `(alias binding)` fact. */
void Sym.undefine_alias(Sym s, String name) {
  SymScope *scope = _scope_at(s, -1);
  List key = $(name);
  Var binding;
  if (scope.bindings.try_get(key, binding))
    s.drop(s.binding_facts, %(alias $binding));
  s.drop(scope.symbols, key);
  s.drop(scope.bindings, key);
  scope.aliases--;
  s.aliases--;
}

/* A module file's static type keeps its short name as its tag, which no
   other type of the unit may take. */
static void _seed_var_tag(Sym s, List key, List type) {
  String owner = _var_converter_owner(key, type);
  if (!owner) return;
  String converter = %"$(owner)_var", Type declared = $(owner);
  String name = s.c.unprefixed(owner);
  if (s.c.file_prefixes()) _claim_class_tag(s, name, owner);
  declared.register_var_tag(name, converter);
}

static void _claim_class_tag(Sym s, String name, String owner) {
  List fact = %(class-tag $(name.lower()));
  Var claimed;
  if (s.binding_facts.try_get(fact, claimed) && claimed != owner)
    $fail.symbols_module_tag(s.c, s.c.token, name);
  s.put(s.binding_facts, fact, owner);
}

/* A declared `Var T.var(T)` is the conformance marker that lets a named
   type box like a builtin. Keep its tag and exact converter in the active
   translation unit rather than the process-lifetime builtin table. */
module String _var_converter_owner(List key, List type) {
  match (type)
    case %((func ((?(String named)))) "Var"):
      match (key)
        case %(?(String spelling)):
          return spelling == %"$(named)_var" ? named : NULL;
  return NULL;
}

/** Registers declared `T_var` converters in the active `Type` unit. */
void Sym.seed_var_tags(Sym s, Map symbols) {
  if (!symbols) return;
  foreach (Var (key, type) in symbols)
    if (key is <list> && type is <list>) _seed_var_tag(s, key, type);
}

/** Defines `key` in the unit's writable base scope.

    The definition survives the expression scope that first resolved it. Its
    binding is issued at the first reference, as for a row an included file
    contributes, so the unit numbers its bindings the same whether it defined
    the row here or replayed it from an interface.
*/
void Sym.define_global(Sym s, List key, List type) {
  SymScope *scope = _scope_at(s, s.base_scopes - 1);
  s.put(scope.symbols, key, type);
  _seed_var_tag(s, key, type);
}

/** Removes `key`'s definition and binding from the unit's writable base
    scope. A later reference no longer resolves; a later definition receives
    a fresh binding. */
void Sym.undefine_global(Sym s, List key) {
  SymScope *scope = _scope_at(s, s.base_scopes - 1);
  s.drop(scope.symbols, key);
  s.drop(scope.bindings, key);
}

/** Associates an enumerator key with its owner in the active scope. */
void Sym.declare_enumerator(Sym s, List key, Symbol owner) {
  SymScope *scope = _scope_at(s, -1);
  if (scope) s.put(scope.enumerators, key, owner);
}

// bindings

static List _scope_binding(Sym s, SymScope &scope, List key) {
  Var found;
  List binding;
  if (scope.bindings.try_get(key, found)) binding = found;
  else {
    binding = _new_binding(s, key);
    s.put(scope.bindings, key, binding);
  }
  (Var binding_tag, int identity, String spelling) = binding;
  (void) binding_tag;
  if (!(%(known $identity) in s.binding_facts))
    s.put(s.binding_facts, %(known $identity), spelling);
  List self_key = %(self $binding);
  if (!(self_key in s.binding_facts)) {
    Var relative;
    if (scope.symbols.try_get(%(self $spelling), relative))
      s.put(s.binding_facts, self_key, relative);
  }
  if (s.c.source_facts) _note_source_key(s, scope, key, binding);
  return binding;
}

/* Source facts find a binding's declaration through the map and key that
   hold its symbol row. */
static void _note_source_key(
  Sym s, SymScope &scope, List key, List binding) {
  Compiler c = s.c;
  List source_key = $(scope.symbols, key);
  s.put(s.binding_facts, %(src-key $binding), source_key);
  Var declaration;
  if (c.source_primary && !c.shallow &&
      c.source_declarations.try_get(source_key, declaration))
    c.source_definitions[binding] = declaration;
}

static List _new_binding(Sym s, List key) {
  int identity = ++s.c.names.next_binding;
  Var name = key.last();
  List binding = Ast.binding(identity, name);
  s.put(s.binding_facts, %(known $identity), name);
  return binding;
}

/** Returns how many introduced bindings no scope holds: those
    `Sym.introduce` made, as opposed to the ones each scope makes once for
    a name it resolves. */
int Sym.introduced(Sym s) {
  int held = 0;
  for (int i = 0; i < (int) s.scopes.len(); i++)
    held += _scope_at(s, i).bindings.len();
  return s.c.names.next_binding - held;
}

/** Allocates a fresh binding identity for a compiler-introduced spelling. */
List Sym.introduce(Sym s, String spelling) => _new_binding(s, $(spelling));

/** Returns `key`'s binding in the current scope, or `NULL`. */
List Sym.current_binding(Sym s, List key) {
  SymScope *scope = _scope_at(s, -1);
  Var binding;
  return scope && scope.bindings.try_get(key, binding) ? binding : NULL;
}

/** Returns the current scope's enum owner for `key`, or zero. */
Symbol Sym.enumerator_owner(Sym s, List key) {
  SymScope *scope = _scope_at(s, -1);
  Var owner;
  return scope && scope.enumerators.try_get(key, owner) ? owner : 0;
}

/** Reports whether `binding` belongs to a scope inside the base scopes. */
int Sym.binding_is_local(Sym s, List binding) =>
  s.binding_is_local_before(binding, s.scopes.len());

/** Reports whether `binding` belongs to a local scope below `scope_count`.

    Counts beyond the current scope depth are clamped to that depth.
*/
int Sym.binding_is_local_before(Sym s, List binding, int scope_count) {
  if (scope_count > (int) s.scopes.len()) scope_count = s.scopes.len();
  for (int i = scope_count - 1; i >= s.base_scopes; i--)
    foreach (List (_, candidate) in _scope_at(s, i).bindings)
      if (List.equal(candidate, binding)) return 1;
  return 0;
}

/** Returns the borrowed semantic-facts map indexed by binding.

    Write it through `set_fact` and `drop_fact`, which a semantic
    transaction can restore.
*/
Map Compiler.semantic_binding_facts(Compiler c) => c.sym.binding_facts;

/** Returns the List one semantic binding fact holds, or NULL when it is
    absent.
*/
List Compiler.fact(Compiler c, Var key) {
  Var stored;
  return c.sym.binding_facts.try_get(key, stored) ? stored : NULL;
}

/** Sets one semantic binding fact. */
void Compiler.set_fact(Compiler c, Var key, Var value) =>
  c.sym.put(c.sym.binding_facts, key, value);

/** Deletes one semantic binding fact. */
void Compiler.drop_fact(Compiler c, Var key) =>
  c.sym.drop(c.sym.binding_facts, key);

// lookup

/** Returns `key`'s type, or `NULL`. A plain key tries the current module
    file's static spelling first and retries a miss in package space. */
List Sym.get(Sym s, List key) {
  List found = _get_from(s, key, _file_key(s, key));
  if (found) return found;
  List retry = _package_retry_key(s, key);
  return retry ? s.get_exact(retry) : NULL;
}

/** Returns `key`'s type without package fallback, or `NULL`. */
List Sym.get_exact(Sym s, List key) => _get_from(s, key, NULL);

/** Reports whether a scope inside the base scopes declares `key`. */
int Sym.has_local(Sym s, List key) {
  for (int i = (int) s.scopes.len() - 1; i >= s.base_scopes; i--)
    if (key in _scope_at(s, i).symbols) return 1;
  return 0;
}

/* `own`, the current module file's spelling of `key`, comes first at file
   scope, so a file's statics shadow the unit's other names there. */
static List _get_from(Sym s, List key, List own) {
  Var val;
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    Map scope = _scope_at(s, i).symbols;
    if (own && i < s.base_scopes && scope.try_get(own, val)) return val;
    if (scope.try_get(key, val)) return val;
  }
  if (_retained_member(key) &&
      s.binding_facts.try_get(%(aggfact $key), val)) return val;
  return NULL;
}

/* A plain key's spelling among the current module file's statics, or NULL
   outside a module unit. A template's free names bind where its expansion
   lands, so none resolves to a static of the file that defines the macro. */
module List _file_key(Sym s, List key) {
  if (!s.c.line_markers || s.c.macro_holes || !key || key.cdr() ||
      key.car() is not <string>)
    return NULL;
  String prefix = s.c.file_prefix();
  return prefix ? %("$prefix$(key.car())") : NULL;
}

/* Package files may reference their own file-scope names bare. A plain-key
   total miss retries the package-prefixed key; exact entries win, and
   units outside package mode never retry. */
module List _package_retry_key(Sym s, List key) {
  String package = s.c.package;
  if (!package || !key || key.cdr() || key.car() is not <string>) return NULL;
  String spelling = key.car();
  String prefixed = s.c.package_spelling(spelling);
  return prefixed == spelling ? NULL : $(prefixed);
}

/** Resolves an existing key and optionally stores its semantic type.

    A symbol row without a binding receives a stable binding identity. A total
    miss returns `NULL` and stores `NULL` through `type` when provided.
*/
List Sym.lookup(Sym s, List key, Type &?type) =>
  _lookup_from(s, key, type, (int) s.scopes.len() - 1, 0);

/** Resolves `key` or creates a forward binding in the current scope.

    Stores `NULL` through `type` when no declaration supplies a type.
*/
List Sym.reference(Sym s, List key, Type &?type) =>
  _lookup_from(s, key, type, (int) s.scopes.len() - 1, 1);

/** Resolves a binding through base scopes and optionally stores its type.

    Returns `NULL` when no base scope contains the key.
*/
List Sym.resolve_global(Sym s, List key, Type &?type) =>
  _lookup_from(s, key, type, s.base_scopes - 1, 0);

/** Resolves a global name or creates its forward binding in the base scope.
    Local declarations cannot capture a retained macro's global reference.
*/
List Sym.reference_global(Sym s, List key) {
  List binding = s.resolve_global(key, NULL);
  if (binding) return binding;
  return _scope_binding(s, *_scope_at(s, s.base_scopes - 1), key);
}

static List _lookup_from(
  Sym s, List key, Type &?type, int first, int forward) {
  List binding = NULL;
  int i = first;
  for (; i >= s.base_scopes; i--) {
    binding = _scope_find(s, *_scope_at(s, i), key, type);
    if (binding) return binding;
  }
  List own = _file_key(s, key);
  for (; i >= 0; i--) {
    SymScope *scope = _scope_at(s, i);
    if (own) binding = _scope_find(s, *scope, own, type);
    if (!binding) binding = _scope_find(s, *scope, key, type);
    if (binding) return binding;
  }
  List retry = _package_retry_key(s, key);
  if (retry && (!forward || s.get_exact(retry)))
    return _lookup_from(s, retry, type, first, forward);
  if (type) type = NULL;
  return forward ? _scope_binding(s, *_scope_at(s, -1), key) : NULL;
}

static List _scope_find(Sym s, SymScope &scope, List key, Type &?type) {
  Var found;
  if (scope.symbols.try_get(key, found)) {
    if (type) type = found;
    return _scope_binding(s, scope, key);
  }
  if (!scope.bindings.try_get(key, found)) return NULL;
  if (type) type = NULL;
  return found;
}
