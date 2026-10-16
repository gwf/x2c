/*  symbols.x -- the compiler's semantic symbol table

    Copyright (c) 2025 Gary William Flake.

    `Sym` holds one compiler's declarations as a stack of scopes searched
    from inner to outer; its lowest scopes hold file-scope declarations.
    It issues the binding identity of each declared name, resolves typedef
    chains and aggregate fields, and records which file-scope names are
    private. A `SymTxn` stages the rows a macro binds, so a failed expansion
    leaves the table as it was.
*/
#pragma once
#include "compiler.x"
#include "parse-report-macros.x"
#include "grammar.x"

// diagnostics

static macro Stmt $report.parse.name_package(
  Expr $c, Expr $spelling, Expr $owner) {
  $c.report_error(
    <parse>,
    %"'${$spelling}' is reserved for imported package '${$owner}'",
    $c.token, NULL);
}

static macro Stmt $report.parse.module_shadow(Expr $c, Expr $name) {
  $c.report_error(
    <parse>,
    %"'${$name}' is a module name and a static of one file in this unit",
    $c.token, %("a module declaration's name means one thing in every file"
    "of the unit; rename one of them"));
}

static macro Stmt $report.parse.module_tag(Expr $c, Expr $name) {
  $c.report_error(
    <parse>,
    %"two files of this module unit give a type named '${$name}' a Var tag",
    $c.token, %("a type's Var tag comes from its name without the file prefix,"
    "so it must be unique in the unit; rename one of the types"));
}

static macro Stmt $report.parse.name_reserved(Expr $c, Expr $spelling) {
  $c.report_error(
    <parse>,
    %"'${$spelling}' is reserved for compiler-generated names",
    $c.token, NULL);
}

static macro Stmt $report.parse.package_collision(
  Expr $c, Expr $site, Expr $kind, Expr $local) {
  $c.report_error(
    <parse>,
    %"package ${$kind} '${$local}' collides with a declared name",
    $site, NULL);
}

static macro Stmt $report.parse.package_bound(
  Expr $c, Expr $site, Expr $kind, Expr $local, Expr $bound) {
  $c.report_error(
    <parse>,
    %"package ${$kind} '${$local}' is already bound",
    $site, %( "bound to: ${$bound}" ));
}

static macro Stmt $report.type.typedef_depth(Expr $c, Expr $origin) {
  $c.report_error(
    <type>,
    %"typedef chain too deep (possible cycle) resolving ${$origin.repr()}",
    NULL, NULL);
}

// symbol scopes

/*  Type grammar:
      TYPE-LIST : ( TYPE+ )
      TYPE      : ( MOD* SPEC )
      MOD       : (array SIZE?) | * | & | FUNCTION
      FUNCTION  : ( (func TYPE-LIST) MOD* SPEC)
      SPEC      : SCALAR | (union U) | (struct S) | (enum E) | TYPEDEF
      SCALAR    : "any C basic type"
      TYPEDEF   : "any user defined type"

    Symbol table entries:

    Identifier categories:
      V: variable name
      E: enum tag name
      F: function name
      K: field name (key)
      M: method name
      S: struct tag name
      U: union tag name
      T: typedef name

    Entry formats, each a lookup key and the type the table holds for it:
      (V)                   TYPE
      (union U K)             TYPE
      (union U)               (union TYPE-LIST)
      (struct S K)            (TYPE)
      (struct S)              (struct TYPE-LIST)
      (enum E)                (enum)
      (class C M)             (func ...)
      (T)                     (typedef TYPE)
      (F)                     (func (TYPE-LIST) TYPE)

    Notes:
    - Struct fields can have (BIT N) mods as well.
    - "long", "long long", and "double double" are all omitted to keep
      sizeof(Var) to 8 bytes.
    - A declaration like "struct { int a, b; } x;" will generate two
      symbol table entries: one for an anonymous struct definition, and the
      other for x, which references the named anonymous struct definition.
*/

/** Holds a compiler's declarations in nested scopes.
    The lowest `base_scopes` contain file-scope declarations. Active
    transactions retain the rows each write replaces in `undo`. */
static typedef struct Sym {
  Block scopes, Map globals, statics, binding_facts, prefixed;
  int base_scopes, local_macro_names;
  Block undo, int transactions;
  // Owning compiler, so type resolution can report its own diagnostics.
  Compiler c;
} *Sym;

/* `map[key]` held `value` before a write, or nothing when it is void. */
static typedef struct SymUndo { Map map, Var key, value; } SymUndo;

/** Creates the empty symbol table that compiler `c` owns. */
Sym Sym.new(Compiler c) {
  Sym s = Scope.calloc(1, sizeof(struct Sym));
  s.c = c;
  s.binding_facts = {};
  s.scopes = Block.new(sizeof(SymScope));
  s.statics = {};
  s.prefixed = {};
  s.undo = Block.new(sizeof(SymUndo));
  return s;
}

/** Sets `map[key]` so that an active semantic transaction can restore it.
    Semantic writes to scope, file-static, and binding-fact maps use this.
*/
void Sym.put(Sym s, Map map, Var key, Var value) {
  _remember(s, map, key);
  map[key] = value;
}

/** Deletes `key` from `map` so that an active transaction can restore it. */
void Sym.drop(Sym s, Map map, Var key) {
  _remember(s, map, key);
  map.del(key);
}

static void _remember(Sym s, Map map, Var key) {
  if (!s.transactions) return;
  Var value = void;
  map.try_get(key, value);
  SymUndo row = { .map = map, .key = key, .value = value };
  s.undo.push(&row);
}

static SymScope *_scope_at(Sym s, int index) {
  int count = s.scopes.len();
  if (index < 0) index += count;
  if (index < 0 || index >= count) return NULL;
  SymScope *scopes = s.scopes.bytes;
  return scopes + index;
}

/** Resets symbol state to one base scope backed by `globals`.

    Later definitions mutate that caller-supplied map.
*/
void Sym.reset(Sym s, Map globals) {
  _clear_symbols(s, globals, 1);
  _push_symbols(s, s.globals);
}

/** Resets symbol state to read `base` below the writable scope `overlay`.

    Later definitions mutate `overlay`; `base` is only read.
*/
void Sym.reset_overlay(Sym s, Map base, Map overlay) {
  _clear_symbols(s, overlay, 2);
  _push_symbols(s, base != NULL ? base : {});
  _push_symbols(s, s.globals);
}

static void _clear_symbols(Sym s, Map globals, int base_scopes) {
  s.scopes.clear();
  s.globals = globals != NULL ? globals : {};
  s.statics = {};
  s.prefixed = {};
  s.base_scopes = base_scopes;
  s.local_macro_names = 0;
  s.binding_facts = {};
}

static void _push_symbols(Sym s, Map symbols) {
  struct SymScope scope = {
    .symbols = symbols, .bindings = {}, .enumerators = {}};
  s.scopes.push(&scope);
}

/** Pushes a new empty lexical scope. */
void Sym.push_new_scope(Sym s) => _push_symbols(s, {});

/** Pushes a caller-supplied lexical scope while retaining its map objects. */
void Sym.push_scope(Sym s, SymScope scope) => s.scopes.push(&scope);

/** Pops the innermost scope, or returns an empty scope when none exists. */
SymScope Sym.pop_scope(Sym s) {
  struct SymScope scope = { 0 };
  s.scopes.try_pop(&scope);
  if (scope.macros != NULL) s.local_macro_names -= scope.macros.len();
  return scope;
}

/** Returns the number of semantic scopes, including base scopes. */
int Sym.scope_count(Sym s) => s.scopes.len();

/** Returns whether declarations currently bind at file scope. */
int Sym.at_file_scope(Sym s) => (int) s.scopes.len() <= s.base_scopes;

/** Sets aside the local scopes now open, so declarations bind at file
    scope until `Sym.reopen_scopes` restores the returned scopes. */
Block Sym.close_local_scopes(Sym s) {
  Block local = Block.new(sizeof(SymScope));
  if (s.at_file_scope()) return local;
  local.append(_scope_at(s, s.base_scopes), s.scopes.len() - s.base_scopes);
  s.scopes.truncate(s.base_scopes);
  return local;
}

/** Reopens the local scopes `Sym.close_local_scopes` set aside. */
void Sym.reopen_scopes(Sym s, Block local) {
  s.scopes.append(local.bytes, local.len());
  local.free();
}

// symbol maps

/** Returns the mutable global symbol map supplied to the latest reset. */
Map Sym.global_symbols(Sym s) => s.globals;

/** Copies all base-scope symbols into a fresh map in source order.

    Package collection uses this so it resolves against the prelude and the
    importing unit's already-visible includes without mutating either.
*/
Map Sym.base_symbols(Sym s) {
  Map seed = {};
  for (int i = 0; i < s.base_scopes; i++) seed.merge(_scope_at(s, i).symbols);
  return seed;
}

/** Returns the current scope's mutable symbol map, or `NULL`. */
Map Sym.current_symbols(Sym s) {
  SymScope *scope = _scope_at(s, -1);
  return scope ? scope.symbols : NULL;
}

/** Returns a fresh map of the base symbols with the current scope's rows
    merged in. */
Map Sym.unit_symbols(Sym s) {
  Map symbols = s.base_symbols();
  if (!s.at_file_scope()) symbols.merge(s.current_symbols());
  return symbols;
}

/** Returns the borrowed set of file-static declaration keys. */
Map Sym.file_statics(Sym s) => s.statics;

/** Marks a declaration key as file-static. */
void Sym.mark_static(Sym s, List key) => s.put(s.statics, key, 1);

/** Returns the visible one-part source names and their semantic types.
    Inner scopes win. The result is a fresh List; types remain borrowed. */
List Sym.visible_symbols(Sym s) {
  Map seen = {};
  Array rows = [];
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    SymScope *scope = _scope_at(s, i);
    foreach (Var (key, value), scope.symbols)
      match (key)
        case %(?(String name)):
          if (_unseen(seen, name)) rows.push(%($name $value));
    if (scope.macros != NULL)
      foreach (Var (name, definition), scope.macros)
        if (name is <string> && _unseen(seen, name))
          rows.push(%($name ${_macro_kind(definition)}));
  }
  return rows.list_free();
}

static int _unseen(Map seen, Var name) {
  if (name in seen) return 0;
  seen[name] = 1;
  return 1;
}

static Symbol _macro_kind(Var definition) {
  Symbol kind = definition is <list> ? definition.list().assoc(<kind>) : 0;
  return kind == <type> ? <typemacro> : <macro>;
}

// definitions

/** Sets a semantic type for `key` in the required active scope. */
void Sym.set(Sym s, List key, List type) {
  Map scope = _scope_at(s, -1).symbols;
  if (log_should_log(<debug>, <symtab>))
    log_debug(<symtab>, %( (func "Sym.set") (key $key) (val $type) ));
  s.put(scope, key, type);
  if (_retained_member(key)) s.put(s.binding_facts, %(aggfact $key), type);
}

static int _retained_member(List key) =>
  !!key.match(%((!or struct union) (!or (binding ? ?) (gensym ? ?)) ? *));

/** Defines `key` and returns its stable binding in the active scope. */
List Sym.define(Sym s, List key, List type) {
  SymScope *scope = _scope_at(s, -1);
  s.set(key, type);
  _seed_var_tag(s, key, type);
  return _scope_binding(s, *scope, key);
}

/* A module file's static type keeps its short name as its tag, which no
   other type of the unit may take. */
static void _seed_var_tag(Sym s, List key, List type) {
  String owner = _var_converter_owner(key, type);
  if (!owner) return;
  String converter = %"${owner}_var", Type declared = %($owner);
  String name = s.c.unprefixed(owner);
  if (s.c.file_prefixes()) _claim_class_tag(s, name, owner);
  declared.register_var_tag(name, converter);
}

static void _claim_class_tag(Sym s, String name, String owner) {
  List fact = %(class-tag ${name.lower()});
  Var claimed;
  if (s.binding_facts.try_get(fact, claimed) && claimed != owner)
    $report.parse.module_tag(s.c, name);
  s.put(s.binding_facts, fact, owner);
}

/* A declared `Var T.var(T)` is the conformance marker that lets a named
   type box like a builtin. Keep its tag and exact converter in the active
   translation unit rather than the process-lifetime builtin table. */
static String _var_converter_owner(List key, List type) {
  match (type)
    case %((func ((?(String named)))) "Var"):
      match (key)
        case %(?(String spelling)):
          return spelling == %"${named}_var" ? named : NULL;
  return NULL;
}

/** Registers declared `T_var` converters in the active `Type` unit. */
void Sym.seed_var_tags(Sym s, Map symbols) {
  if (!symbols) return;
  foreach (Var (key, type), symbols)
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
  List source_key = %(${scope.symbols} $key);
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
List Sym.introduce(Sym s, String spelling) => _new_binding(s, %($spelling));

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
    foreach (Var (_, candidate), _scope_at(s, i).bindings)
      if (List.equal(candidate, binding)) return 1;
  return 0;
}

/** Returns the borrowed semantic-facts map indexed by binding.

    Write it through `set_fact` and `drop_fact`, which a semantic
    transaction can restore.
*/
Map Compiler.semantic_binding_facts(Compiler c) => c.sym.binding_facts;

/** Returns the List one semantic binding fact holds, or NULL when it is
    absent. */
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
static List _file_key(Sym s, List key) {
  if (!s.c.line_markers || s.c.macro_holes || !key || key.cdr() ||
      key.car() is not <string>)
    return NULL;
  String prefix = s.c.file_prefix();
  return prefix ? %("$prefix${key.car()}") : NULL;
}

/* Package files may reference their own file-scope names bare. A plain-key
   total miss retries the package-prefixed key; exact entries win, and
   units outside package mode never retry. */
static List _package_retry_key(Sym s, List key) {
  String package = s.c.package;
  if (!package || !key || key.cdr() || key.car() is not <string>) return NULL;
  String spelling = key.car();
  String prefixed = s.c.package_spelling(spelling);
  return prefixed == spelling ? NULL : %($prefixed);
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

// declarations

/** Analyzes a complete declaration type and installs its stored declared type.

    Returns the declared binding. At file scope this also records static
    visibility; local declarations record automatic-storage and declared-type
    facts. Stored types discard storage and `inline` while retaining `const`,
    `restrict`, and `volatile`.
*/
List Sym.declare(Sym s, List context, List key, List ast) =>
  _declare(s, context, key, ast, s.declared_key(context, key, ast));

/** Installs an aggregate or named type whose parser resolved its spelling. */
List Sym.declare_resolved(Sym s, List context, List key, List ast) =>
  _declare(s, context, key, ast, key);

static List _declare(
  Sym s, List context, List key, List ast, List declared) {
  if (!s.at_file_scope() && !List.equal(declared, key))
    _link_local(s, declared);
  key = declared;
  _check_spelling(s.c, _declared_spelling(key));
  Type ctxkey = %( @context @key ), type = ast.type_from_ast();
  Type declared_type = type;
  if ((int) s.scopes.len() == s.base_scopes && !context)
    _track_static(s, (List) ctxkey, ast);
  List binding = NULL;
  if (context === %(typedef)) binding = s.define(key, (List) ctxkey);
  type = _stored_type(type, ctxkey, ast);
  if (!binding) binding = s.define(ctxkey, (List) type);
  else {
    s.set(ctxkey, (List) type);
    _local_typedef(s, type, binding);
  }
  if (!context && !s.at_file_scope() && _names_local_object(declared_type))
    _local_object(s, key, binding, declared_type);
  return binding;
}

/** Returns the key a declaration of `key` with type `ast` takes in this
    unit: its file-private or package spelling at file scope, else `key`.
    Retained declarations keep their already resolved spelling. */
List Sym.declared_key(Sym s, List context, List key, List ast) {
  if (!s.c.package && !s.c.line_markers) return key;
  return _declared_key(s, context, key, ast);
}

/* A file-scope declaration's key takes its scope's spelling. A static of
   a module file takes the file's prefix, so each file's statics have their
   own keys; package mode puts other declarations in the package's `name__`
   space. Binding spellings, aggregate tags, and derived Var converters then
   carry the prefix everywhere they are read. A later declaration of a
   static without `static` names that static, as C links it. Other statics
   keep their spellings; anonymous aggregate gensyms are not source
   spellings and stay in the compiler's space. */
static List _declared_key(Sym s, List context, List key, List ast) {
  Compiler c = s.c;
  if (!s.at_file_scope())
    return context || _names_local_object(ast.type_from_ast())
      ? key : _linked_key(s, key);
  if (context && !(context === %(typedef))) return key;
  String prefix = c.private_prefix(ast);
  Var (head, tag) = key;
  int plain = head is <string> && !key.cdr();
  int tagged = (head == <struct> || head == <union> || head == <enum>) &&
               key.cdr() && !key.cddr() && tag is <string>;
  if (plain) _check_module_shadow(s, %(() (typedef)), prefix, head, ast);
  if (tagged) _check_module_shadow(s, %(($head)), prefix, tag, ast);
  if (plain && !context && !prefix && !c.module_declaration) {
    List own = _file_key(s, key);
    if (!own) own = key;
    if (own in s.statics) return own;
  }
  if (!prefix && (!c.package || ast.type().is_static())) return key;
  if (plain) return %(${c.declared_spelling(prefix, head)});
  if (tagged) return %($head ${c.declared_spelling(prefix, tag)});
  return key;
}

/* A block-scope `extern` or function declaration names the file-scope
   binding it sees, so it takes that binding's key: the file's static, the
   unit's name, or the package's name. A local of the spelling hides them,
   and the declaration then keeps its own spelling. */
static List _linked_key(Sym s, List key) {
  if (s.has_local(key)) return key;
  List own = _file_key(s, key), package = _package_retry_key(s, key);
  if (own && _global_key(s, own)) return own;
  if (package && !_global_key(s, key) && _global_key(s, package))
    return package;
  return key;
}

/* A block-scope declaration linked to a file-scope binding of another
   spelling declares that binding, so it takes the binding's identity. */
static void _link_local(Sym s, List key) =>
  s.put(_scope_at(s, -1).bindings, key, s.resolve_global(key, NULL));

/** Reports whether `binding` names a file-scope static of this unit. */
int Sym.is_file_static(Sym s, Var binding) {
  if (binding is not <list> || !Ast.try_binding(binding, NULL, NULL))
    return 0;
  return %(${Ast.binding_spelling(binding)}) in s.statics;
}

static int _global_key(Sym s, List key) {
  for (int i = 0; i < s.base_scopes; i++)
    if (key in _scope_at(s, i).symbols) return 1;
  return 0;
}

/* A `module` name has one meaning across the unit, so no file's static may
   take its name, whichever is declared first. `contexts` are the static
   key contexts of the name's C namespace: objects, functions, and
   typedefs share one, and each tag kind has its own. */
static void _check_module_shadow(
  Sym s, List contexts, String prefix, String name, List ast) {
  Compiler c = s.c;
  foreach (List context, contexts) {
    if (prefix && !(name in s.prefixed) &&
        %(@context $name) in s.statics)
      $report.parse.module_shadow(c, name);
    if (!c.module_declaration ||
        !(c.source_private > 0 || ast.type().is_static())) continue;
    foreach (String other, c.file_prefixes())
      if (%(@context "$other$name") in s.statics)
        $report.parse.module_shadow(c, name);
  }
}

/* The declared spelling, when the key names one. Aggregate keys carry the
   tag in their second slot; anonymous aggregates carry a gensym list there
   and are not source spellings. */
static String _declared_spelling(List key) {
  Var (head, tag) = key;
  if (head is <string>) return head;
  if (head == <struct> || head == <union> || head == <enum>)
    if (tag is <string>) return tag;
  return NULL;
}

/* A source declaration may not take a compiler-generated spelling or one
   in an imported package's space. A shallow parse reads emitted C, whose
   generated spellings are the compiler's own output. */
static void _check_spelling(Compiler c, String spelling) {
  if (!c.shallow && _is_reserved_spelling(spelling))
    $report.parse.name_reserved(c, spelling);
  String owner = _package_reserved_owner(c, spelling);
  if (owner)
    $report.parse.name_package(c, spelling, owner);
}

// Checked once per declaration, with no prepass over the token stream.
static int _is_reserved_spelling(String s) {
  if (!s) return 0;
  if (s.startswith("_x2c_gensym_") ||
      s == "_init_guard_" || s == "_file_init_")
    return 1;
  if (s.len() < 2 || s[0] != '_') return 0;
  for (int i = 1; i < s.len(); i++) if (s[i] < '0' || s[i] > '9') return 0;
  return 1;
}

/* Only packages imported by this unit reserve their `name__` space; foreign
   headers may contain `__`, and a package unit keeps its own prefix. */
static String _package_reserved_owner(Compiler c, String spelling) {
  if (!spelling || !c.package_aliases.len()) return NULL;
  foreach (Var (alias, value), c.package_aliases) {
    String name = value;
    if (name == c.package) continue;
    if (spelling.startswith(%"${name}__")) return name;
  }
  return NULL;
}

/* File-local globals are tracked for protocol and static initializer
   checks. The storage class is only visible here, before canonicalization
   strips it. A later declaration without `static` keeps the internal
   linkage, as in C. */
static void _track_static(Sym s, List key, List ast) {
  if (ast.type().is_static()) s.put(s.statics, key, 1);
}

// A tagged definition also publishes its tag unless the key is that tag.
static Type _stored_type(Type type, Type key, List ast) {
  if ((type.is_aggregate_tag_body() && !key.is_aggregate_tag()) ||
      (type.is_enum_tag_body() && !key.is_enum_tag() && !key.is_typedef())) {
    Var (aggregate, tag) = ast;
    type = %( $aggregate $tag );
  }
  return type.declared();
}

/* A block-local typedef emits under a fresh spelling, and a local tag
   records its named type. */
static void _local_typedef(Sym s, Type type, List binding) {
  if (s.at_file_scope()) return;
  if (type.is_aggregate_tag())
    s.put(s.binding_facts, %(ntype $binding), type);
  s.put(
    s.binding_facts, %(emitted $binding), s.c.fresh_name("local_typedef"));
}

/* A block-scope `extern` declaration or function prototype names an
   external symbol, so it is never a local object and keeps C's spelling. */
static int _names_local_object(Type declared) =>
  !declared.is_extern() && !declared.is_function();

/* A local object records its automatic storage and declared type, and
   joins the locals of its spelling unless it is a template's own local,
   which binds again where the template expands. One that shadows a
   declared `T_var` converter emits under a fresh spelling, so generated
   boxing still reaches the converter. */
static void _local_object(Sym s, List key, List binding, Type type) {
  _mark_automatic(s, binding, type);
  if (!s.c.macro_holes) s.join_locals(binding);
  Type global_type = NULL;
  s.resolve_global(key, global_type);
  if (_var_converter_owner(key, global_type) &&
      !(%(emitted $binding) in s.binding_facts))
    s.put(
      s.binding_facts, %(emitted $binding),
      s.c.fresh_name("var_converter_shadow"));
}

/** Records the program local `binding` among the locals of its spelling,
    under the private spelling `Sym.unshadow_global` gave that spelling, if
    any. */
void Sym.join_locals(Sym s, List binding) {
  String spelling = Ast.binding_spelling(binding);
  Var alias;
  if (s.binding_facts.try_get(%(unshadowed $spelling), alias))
    _unshadow_local(s, binding, alias);
  s.put(
    s.binding_facts, %(locals $spelling), cons(binding, _locals(s, spelling)));
}

static List _locals(Sym s, String spelling) {
  Var stored;
  return s.binding_facts.try_get(%(locals $spelling), stored) ? stored : NULL;
}

static void _mark_automatic(Sym s, List binding, Type type) {
  s.put(s.binding_facts, %(automatic $binding), 1);
  s.put(s.binding_facts, %(type $binding), type);
}

/** Emits every local object spelled `spelling` in this unit, declared
    before or after, under one fresh spelling, so code that the transform
    binds after their scopes closed reaches the file-scope declaration.
    Locals of that spelling keep one spelling among themselves, as C wrote
    them. */
void Sym.unshadow_global(Sym s, String spelling) {
  if (%(unshadowed $spelling) in s.binding_facts) return;
  String alias = s.c.fresh_name("binding_shadow");
  s.put(s.binding_facts, %(unshadowed $spelling), alias);
  foreach (List local, _locals(s, spelling)) _unshadow_local(s, local, alias);
}

/** Emits every local object spelled `spelling` that the current scope
    sees, the enclosing ones too, under one fresh spelling, so a file-scope
    name a template keeps reaches the global there, and returns them.
    Locals of other scopes keep their spellings for the native macros that
    name them. */
List Sym.unshadow_visible(Sym s, String spelling) {
  List key = %($spelling), visible = NULL;
  String alias = s.c.fresh_name("binding_shadow");
  for (int i = s.base_scopes; i < (int) s.scopes.len(); i++) {
    SymScope *scope = _scope_at(s, i);
    Var binding;
    if (key in scope.symbols && scope.bindings.try_get(key, binding) &&
        %(automatic $binding) in s.binding_facts) {
      _unshadow_local(s, binding, alias);
      visible = cons(binding, visible);
    }
  }
  return visible;
}

static void _unshadow_local(Sym s, List binding, String alias) {
  if (!(%(emitted $binding) in s.binding_facts))
    s.put(s.binding_facts, %(emitted $binding), alias);
}

/** Installs an existing binding with `ast`'s qualifier-preserving type. */
List Sym.bind_identity(Sym s, List context, List binding, List ast) {
  String spelling = Ast.binding_spelling(binding);
  List key = context ? %(@context $spelling) : %($spelling);
  SymScope *scope = _scope_at(s, -1);
  Type annotation = ast.type_from_ast();
  s.put(scope.symbols, key, annotation.declared());
  if (context === %(typedef)) {
    key = %($spelling);
    s.put(scope.symbols, key, %(typedef $spelling));
    _local_typedef(s, annotation, binding);
  }
  s.put(scope.bindings, key, binding);
  if (!context && !s.at_file_scope()) _mark_automatic(s, binding, annotation);
  return binding;
}

/** Binds a local aggregate tag before its fields, preserving native spelling.
    A reference reuses the nearest visible tag; a definition or standalone
    forward declaration introduces the tag in the current lexical scope. A
    macro template names its tags as template locals.
*/
Var Compiler.aggregate_name(
  Compiler c, Symbol kind, Var name, int definition) {
  Sym s = c.sym;
  if (name is not <string>) return name;
  if (c.macro_holes) {
    List local = c.macro_tag_name(kind, name, definition);
    return local ? local : name;
  }
  Type type = %($kind $name);
  if (s.at_file_scope()) {
    /* Only a definition or standalone forward owns this package tag.
       A field or prototype may merely refer to a tag from a C header. */
    if (definition && !s.get_exact(type)) s.declare_resolved(NULL, type, type);
    return name;
  }
  if (!definition && s.get_exact(type)) return s.local_type(type).cadr();
  if (!definition && c.shallow) return name;
  List binding = s.current_binding(type);
  return binding ? binding : s.declare(NULL, type, type);
}

// privacy boundaries

/** Records the visibility of one parsed top-level declaration.
    Lexical privacy and static storage mark bindings in `Sym`; typedef rows are
    retained for placing generated protocol declarations at the same boundary.
*/
void Compiler.record_declaration_visibility(Compiler c, List declaration) {
  int private = c.source_private > 0;
  match (declaration) {
    case %(seq *rows):
      foreach (List row, rows) c.record_declaration_visibility(row);
    case %(function ?type (bind ?identity *) *): {
      if (!private && !type.type().is_static()) return;
      String name = Ast.binding_spelling(identity);
      if (name) c.sym.mark_static(%($name));
    }
    case %(
      (!set ?kind (!or typedef declare)) ?type (bindings *rows)
    ): {
      int mark = private || type.type().is_static();
      if (mark) {
        Type base = type.type().base_type();
        match (base)
          case %((!set ?tag (!or struct union enum)) ?name *body):
            if (name && (body || !rows || rows === %((bind () ()))))
              c.sym.mark_static(%($tag $name));
      }
      _record_rows_visibility(c, declaration, kind, private, mark, rows);
      if (kind == <declare> && !mark)
        _record_native_objects(c, type, rows);
    }
  }
}

/* A public object definition belongs to this source, including a tentative
   definition. An extern declaration only names its native supplier. */
static void _record_native_objects(
  Compiler c, Type spec, List rows) {
  if (!c.shallow || c.source_private < 0 || spec.is_extern() ||
      !Path.is_x2c_source(c.filename)) return;
  String path = Compiler.portable_path(c.canonical_path(c.filename));
  foreach (List row, rows) {
    List declarator = row;
    match (row) case %(op = ?bound ?): declarator = bound;
    match (declarator) case %(bind ?binding ?): {
      List declaration = %(declare $spec (bindings $declarator));
      if (declaration.type_from_ast().is_function()) continue;
      String name = Ast.binding_spelling(binding);
      if (!name || !name.len()) continue;
      c.sym.set(
        %("source-node" (native-object $path ${c.token.pos} $name)),
        %(native-object $name));
    }
  }
}

static void _record_rows_visibility(
  Compiler c, List declaration, Symbol kind, int private, int mark,
  List rows) {
  foreach (List row, rows)
    match (row) case $source_declarator_row(%(?identity *)):
      _record_binding_visibility(
        c, declaration, kind, private, mark, identity);
}

static void _record_binding_visibility(
  Compiler c, List declaration, Symbol kind, int private, int mark,
  List identity) {
  String name = Ast.binding_spelling(identity);
  if (kind == <typedef> && name) {
    c.record_source_typedef(name, declaration, mark);
    if (mark) c.sym.mark_static(%(typedef $name));
  }
  if (mark && name) c.sym.mark_static(%($name));
}

// module and package names

/** Returns the prefix that a file-scope declaration of `type` takes in the
    current module file, or NULL. A static takes it, and so does each
    declaration of a `static typedef` or `static class`; a `module`
    declaration and every declaration outside a module unit do not. */
String Compiler.private_prefix(Compiler c, Type type) {
  if (c.module_declaration ||
      !(c.source_private > 0 || (type && type.is_static())))
    return NULL;
  return c.file_prefix();
}

/** Returns `name` spelled in a declaration's scope: with `prefix`, a file
    prefix, or else in the current package. A name the compiler derived
    from a spelling this unit already prefixed, such as `second__Node_new`
    or `Var_second__node` for a private class `second__Node`, stays
    unchanged; it is unique in the unit, so code generated outside the file
    still reaches it. Ordinary source spellings always take their file's
    prefix, even when they resemble another generated spelling. */
String Compiler.scoped_spelling(Compiler c, String prefix, String name) {
  if (!prefix) return c.package_spelling(name);
  if (!name || (c.macro_stack && _derived_spelling(c.sym, name)))
    return name;
  return %"$prefix$name";
}

/** Returns `name` as `scoped_spelling` does for a declaration, recording
    a spelling that took `prefix` so the names the compiler derives from
    it are known to hold their prefix already. A replayed collected
    declaration was spelled when it was collected, so its names are final
    and are recorded as they are. */
String Compiler.declared_spelling(Compiler c, String prefix, String name) {
  String spelled =
    c.replaying_declaration ? name : c.scoped_spelling(prefix, name);
  if (!prefix || (spelled == name && !c.replaying_declaration))
    return spelled;
  String bare = spelled.startswith(prefix) ? spelled[prefix.len():] : name;
  c.sym.put(c.sym.prefixed, spelled, bare);
  c.sym.put(c.sym.prefixed, spelled.lower(), bare.lower());
  return spelled;
}

/* `name` is a recorded prefixed spelling, one followed by `_` and more,
   or `Var_` and one in lower case. */
static int _derived_spelling(Sym s, String name) {
  if (!s.prefixed.len()) return 0;
  if (name in s.prefixed) return 1;
  if (name.startswith("Var_") && name[4:] in s.prefixed) return 1;
  for (int at = 1; at < name.len() - 1; at++)
    if (name[at] == '_' && name[:at] in s.prefixed) return 1;
  return 0;
}

/** Returns the static prefix of each file of the module unit. */
List Compiler.file_prefixes(Compiler c) {
  Array prefixes = [];
  if (c.line_markers)
    foreach (List row, c.line_markers)
      match (row) case %(? ? ? ? ? ? ?(String prefix)):
        if (!(prefix in prefixes)) prefixes.push(prefix);
  return prefixes.list_free();
}

/** Returns the source name of a spelling this unit gave a file prefix, or
    `name`. Var tags and descriptor names use that short name. */
String Compiler.unprefixed(Compiler c, String name) {
  Var bare;
  return c.sym.prefixed.try_get(name, bare) ? bare : name;
}

/** Returns a name in the current package namespace, preserving prefixes.

    Idempotence lets parsing and declaration rewrites share this operation.
*/
String Compiler.package_spelling(Compiler c, String name) {
  if (!c.package || !name) return name;
  String prefix = %"${c.package}__";
  return name.startswith(prefix) ? name : %"$prefix$name";
}

/** Registers one local package alias.

    Shallow collection and full parsing both see an import, so repeating the
    same package and alias is a no-op. Another binding of the local spelling
    is a parse error.
*/
void Compiler.register_package_alias(
  Compiler c, String name, String alias, Token token) {
  Var bound = c.package_aliases[alias];
  if (bound is not void && bound == name) return;
  _check_package_binding(c, "alias", alias, token);
  c.package_aliases[alias] = name;
}

/** Registers one package member under a bare local spelling.

    The package member must already exist in the symbol table. Repeating the
    same binding is a no-op; any conflicting local binding is an error.
*/
void Compiler.register_package_member(
  Compiler c, String name, String member, String local,
  Token member_token, Token local_token) {
  /* Keep the source spellings so a later conflict says `geo.Vec` rather
     than naming the package-prefixed C symbol. */
  List binding = %($name $member);
  Var bound = c.package_members[local];
  if (bound is not void && bound.list() === binding) return;
  String spelling = %"${name}__$member";
  if (!c.sym.get_exact(%($spelling)))
    $report.parse.package_member(c, member_token, name, member);
  _check_package_binding(c, "name", local, local_token);
  c.package_members[local] = binding;
}

/* An alias and a `with` name each claim one local spelling. Rebinding that
   spelling, or taking one a declaration already uses, is the same conflict.
   Both messages name what the developer wrote. */
static void _check_package_binding(
  Compiler c, String kind, String local, Token token) {
  Var alias = c.package_aliases[local];
  Var member = c.package_members[local];
  String bound = alias is void ? NULL : alias;
  if (!bound && member is not void) {
    List pair = member;
    (String package, String member_name) = pair;
    bound = %"$package.$member_name";
  }
  if (bound)
    $report.parse.package_bound(c, token, kind, local, bound);
  if (c.sym.get_exact(%($local)))
    $report.parse.package_collision(c, token, kind, local);
}

/** Returns a visible `with` name's package-prefixed spelling, or `NULL`.

    An ordinary declaration of the local spelling shadows the `with` name.
*/
String Compiler.package_member_spelling(Compiler c, String name) {
  if (!c.package_members.len()) return NULL;
  Var bound = c.package_members[name];
  if (bound is void || c.sym.get_exact(%($name))) return NULL;
  List pair = bound;
  (String package, String member_name) = pair;
  return %"${package}__$member_name";
}

/** Returns sorted imported packages that publish `name`.

    Package-owned methods use `<package>__<Type>_<member>` internally while
    consumers retain the spelling from the package header. Sorting keeps
    ambiguity diagnostics deterministic.
*/
List Compiler.imported_providers(Compiler c, String name) {
  if (!name || !c.package_roots.len()) return NULL;
  List packages = %();
  foreach (Var (key, root), c.package_roots) {
    String package = key;
    if (c.sym.get_exact(%("${package}__$name")))
      packages = cons(package, packages);
  }
  return packages.sort();
}

/** Returns an unambiguous imported spelling for `name`, or `NULL`. */
String Compiler.imported_spelling(Compiler c, String name) {
  List packages = c.imported_providers(name);
  if (!packages || packages.cdr()) return NULL;
  return %"${packages.car()}__$name";
}

// local macros

/** Defines or replaces a macro in the active lexical scope.

    Replacing a name already defined in this scope does not increase the
    local macro count.
*/
void Sym.define_macro(Sym s, Atom name, List definition) {
  SymScope *scope = _scope_at(s, -1);
  if (scope.macros == NULL) scope.macros = {};
  if (!(name in scope.macros)) s.local_macro_names++;
  s.put(scope.macros, name, definition);
}

/** Returns whether any lexical scope contains a local macro definition. */
int Sym.has_local_macros(Sym s) => s.local_macro_names != 0;

/** Returns the innermost visible local macro named `name`, or `NULL`. */
List Sym.lookup_macro(Sym s, Atom name) {
  Var definition;
  for (int i = (int) s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = _scope_at(s, i);
    if (scope.macros != NULL && scope.macros.try_get(name, definition))
      return definition;
  }
  return NULL;
}

/** Returns the active macro definition's borrowed local map, or `NULL`. */
Map Compiler.macro_definition_locals(Compiler c) {
  Var stored = c.macro_holes[%(locals)];
  return stored is <map> ? stored : NULL;
}

/** Reports whether `binding` is a local of the active macro definition or
    of a template that encloses it; a nested definition's literal names
    share the enclosing template's names. */
int Compiler.macro_template_local(Compiler c, List binding) {
  Var holes = c.macro_holes;
  while (holes is <map>) {
    Map current = holes;
    Var locals = current[%(locals)];
    if (locals is <map> && binding in (Map) locals) return 1;
    holes = current[%(enclosing)];
  }
  return 0;
}

// typedef resolution

/* Longest typedef chain any legitimate source may hand to the resolver:
   a mutually recursive pair (typedef A B; typedef B A;) otherwise walks
   forever.  A bound rather than a visited set, because is_var_type
   resolves on nearly every converted expression and that hot path
   must not allocate.

   One user typedef costs two resolver hops, the name node ("B") and then
   the (typedef "B") node it maps to, so the raw recursion budget is
   twice the user-visible chain bound.  The budget counts every hop
   rather than only name hops so that the walk still terminates if a
   typedef node is ever mapped straight onto another typedef node. */
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
static Type _resolve_chain(
  Sym s, Type key, Type stop, Type origin, int hops) {
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  if (stop && key == stop) return key;
  if (key.is_typedef_name() || key.is_typedef()) {
    Type type = _typedef_target(s, key);
    if (type) return _resolve_chain(s, type, stop, origin, hops + 1);
  }
  match (key) case %((!set ?kind (!or struct union))
      (binding ? ?spelling)):
    if (!s.field_order(key)) return %($kind $spelling);
  return key;
}

/* The resolver cannot tell a true cycle from an absurdly long chain, so the
   diagnostic states only what it can determine. `typedef Color Color;` is
   legal C; it binds ("Color") to (typedef "Color") and back, so cycles are
   real. */
static void _typedef_budget_error(Sym s, Type origin) {
  $report.type.typedef_depth(s.c, origin);
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
    `type`, or NULL when no typedef or several typedefs are. */
Type Sym.sole_typedef(Sym s, Type type) {
  String found = NULL;
  for (int i = 0; i < s.base_scopes; i++)
    foreach (Var (key, target), _scope_at(s, i).symbols)
      match (key) case %(typedef ?(String name)):
        if (target == type) {
          if (found && found != name) return NULL;
          found = name;
        }
  return found ? %($found) : NULL;
}

/** Resolves typedef bases while retaining every declarator qualifier. */
Type Sym.normalize_declared_type(Sym s, Type type) =>
  type ? _normalize_chain(s, type, type, 0) : NULL;

static Type _normalize_chain(Sym s, Type type, Type origin, int hops) {
  type = type.declared();
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  Type next = _typedef_base_step(s, type);
  return next ? _normalize_chain(s, next, origin, hops + 1) : type;
}

static Type _typedef_base_step(Sym s, Type type) {
  Type base = type.base_type();
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
      return _replace_type_base(type, base, %(${base.car()} $binding));
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
  Type next = _typedef_base_step(s, type);
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
  // Stop at the named type instead of resolving through its typedef.
  if (!type || !name) return 0;
  Type wanted = %($name), origin = type.canonicalize();
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
  foreach (List row, s.field_order(type).cdr()) {
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
  foreach (List declaration, fields) {
    declaration = Ast.without_origin(declaration);
    if (declaration.car() == <c-assert>) continue;
    List bindings = declaration.caddr();
    foreach (List declarator, bindings.cdr())
      rows.push(_field_row(s, type, declaration, declarator));
  }
  s.set(%(@type "field-order"), %(fields @{rows.list_free()}));
}

static List _field_row(
  Sym s, Type type, List declaration, List declarator) {
  String name = Ast.binding_spelling(declarator.cadr());
  Type declared = name ? s.get(%(@type $name))
    : %(declare ${declaration.cadr()} (bindings $declarator))
      .type_from_ast().declared();
  return %($name $declared);
}

/** Returns recorded fields in source order, or `NULL`. */
List Sym.field_order(Sym s, Type type) => s.get(%(@type "field-order"));

/** Records that the field `name` of `aggregate` was declared with the field
    keyword `mark`, such as `delegate`, and that `aggregate` declares one. */
void Sym.mark_field(Sym s, Type aggregate, Symbol mark, String name) {
  s.set(%(@aggregate $mark $name), %($mark));
  s.set(%(@aggregate $mark), %($mark));
}

/** Returns the `(NAME TYPE)` rows of the fields of `aggregate` declared with
    `mark`, in declaration order. */
List Sym.marked_fields(Sym s, Type aggregate, Symbol mark) {
  List order = s.field_order(aggregate);
  Array rows = [];
  foreach (List row, order ? order.cdr() : NULL) {
    String name = row.car();
    if (name && s.get(%(@aggregate $mark $name))) rows.push(row);
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

/* semantic transactions

   Binding a macro's syntax runs in a transaction, so a failed expansion
   leaves the symbol table as it was. Writes change the maps in place and
   record the rows they replace in the symbol table's undo log, so beginning
   and committing cost nothing per row the unit already holds. */

/** Begins a reversible transaction over the current semantic scope.

    The transaction restores the current scope maps, file-static and binding
    facts, binding and generated-name counters, initializer names, and the
    parser's ancestors and placements. It does not snapshot parser position
    or other compiler state.
*/
SymTxn Compiler.begin_semantic_transaction(Compiler c) {
  SymTxn transaction = { .c = c };
  transaction.scope_index = c.sym.scopes.len() - 1;
  _save(transaction, *_scope_at(c.sym, transaction.scope_index));
  if (transaction.extended) _save_effects(transaction);
  if (c.source_facts && c.source_primary) _save_sources(transaction);
  /* Related compilers with their own symbol tables share these counters,
     so the transaction stages a copy instead of logging their writes. */
  c.names.counters = c.names.counters.copy();
  c.sym.transactions++;
  transaction.active = 1;
  return transaction;
}

static void _save(SymTxn &s, SymScope scope) {
  Compiler c = s.c;
  s.scope = scope;
  s.mark = c.sym.undo.len();
  s.meta_group_size = c.meta_group.len();
  s.ancestors = c.ancestors.len();
  s.placements = c.placements.len();
  s.counters = c.names.counters;
  s.statics = c.sym.statics;
  s.binding_facts = c.semantic_binding_facts();
  s.next_binding = c.names.next_binding;
  s.local_macro_names = c.sym.local_macro_names;
  s.initializer_name = c.init_fn;
  s.shutdown_name = c.fini_fn;
  s.extended = c.macro_application > 0;
}

static void _save_effects(SymTxn &s) {
  Compiler c = s.c;
  s.adapters = c.names.adapters;
  s.pending = c.pending.checkpoint();
  s.origin_count = c.origins.len();
  s.origin = c.origin;
  s.needs_exception = c.needs_exception;
  c.names.adapters = c.names.adapters.copy();
}

static void _save_sources(SymTxn &s) {
  s.source_definitions = s.c.source_definitions.copy();
  s.source_occurrences = s.c.source_occurrences.len();
}

/* Rollback restores the active scope's maps, file statics, binding facts,
   and declaration source metadata. Base-scope identities also roll back
   with their binding facts and counter. Rows of other maps stay in the log for
   an enclosing transaction. */
static int _tracks(SymTxn &s, Map map) {
  if (_same(map, s.scope.symbols) || _same(map, s.scope.bindings) ||
      _same(map, s.scope.enumerators) || _same(map, s.scope.macros) ||
      _same(map, s.statics) || _same(map, s.binding_facts) ||
      _same(map, s.c.macros) || _same(map, s.c.kw_aliases)) return 1;
  if (s.c.source_facts && _same(map, s.c.source_declarations)) return 1;
  Sym sym = s.c.sym;
  for (int i = 0; i < sym.base_scopes; i++)
    if (_same(map, _scope_at(sym, i).bindings)) return 1;
  return 0;
}

static int _same(Map a, Map b) => (void *) a == (void *) b;

/** Returns whether the transaction's active scope changed its macro map. */
int SymTxn.local_macros_changed(SymTxn &s) {
  SymScope *scope = _scope_at(s.c.sym, s.scope_index);
  Map before = s.scope.macros, after = scope.macros;
  if (before == NULL || after == NULL) return !_same(before, after);
  Block undo = s.c.sym.undo;
  SymUndo *rows = undo.bytes;
  Map seen = {};
  for (int i = s.mark; i < (int) undo.len(); i++) {
    SymUndo row = rows[i];
    if (!_same(row.map, after) || row.key in seen) continue;
    seen[row.key] = 1;
    if (row.value is void || row.value != after[row.key]) return 1;
  }
  return 0;
}

/** Returns whether a semantic transaction is open. */
int Sym.transacting(Sym s) => s.transactions > 0;

/** Stops one transaction's semantic write log. */
void Sym.end_log(Sym s) {
  if (!--s.transactions) s.undo.clear();
}

// commit and rollback

/** Publishes an active semantic transaction and makes rollback a no-op.
    Its writes are already in the scope maps, so code holding a borrowed
    map observes a committed expansion. An absent or inactive transaction
    has no effect.
*/
void SymTxn.commit(SymTxn &?s) {
  if (!s) return;
  if (!s.active) return;
  if (s.extended) {
    Compiler c = s.c;
    Map adapters = c.names.adapters;
    c.names.adapters = s.adapters;
    s.adapters.merge(adapters);
  }
  _finish(s);
}

/* Completing the outermost transaction empties the undo log. */
static void _finish(SymTxn &s) {
  s.active = 0;
  s.c.sym.end_log();
}

/** Commits an active transaction, retaining the original counters map.
    The caller may then release the transaction's construction scope.
    Parsing and evaluation must allocate outside that temporary scope.
*/
void SymTxn.commit_transient(SymTxn &s) {
  Compiler c = s.c;
  Map counters = c.names.counters;
  s.commit();
  c.names.counters = s.counters;
  _replace_map(s.counters, counters);
}

/* Gives `original` exactly the rows of `staged` and keeps its identity.
   Deletions matter: a declaration can remove an earlier file-static
   designation. */
static void _replace_map(Map original, Map staged) {
  Array keys = $auto(original.keys());
  foreach (Var key, keys) if (!(key in staged)) original.del(key);
  original.merge(staged);
}

/** Restores every semantic value captured by an active transaction.
    An absent or inactive transaction has no effect.
*/
void SymTxn.rollback(SymTxn &?s) {
  if (!s) return;
  if (!s.active) return;
  Compiler c = s.c;
  _undo(s);
  _restore(s);
  if (s.extended) _restore_effects(s);
  if (c.source_facts && c.source_primary) _restore_sources(s);
  _finish(s);
}

/* Restores the logged rows this transaction tracks, newest first, and
   keeps the others in order. */
static void _undo(SymTxn &s) {
  Block undo = s.c.sym.undo;
  SymUndo *rows = undo.bytes;
  int end = undo.len(), kept = s.mark;
  for (int i = end - 1; i >= s.mark; i--) {
    SymUndo row = rows[i];
    if (!_tracks(s, row.map)) continue;
    if (row.value is void) row.map.del(row.key);
    else row.map[row.key] = row.value;
  }
  for (int i = s.mark; i < end; i++)
    if (!_tracks(s, rows[i].map)) rows[kept++] = rows[i];
  undo.truncate(kept);
}

static void _restore(SymTxn &s) {
  Compiler c = s.c;
  SymScope *scope = _scope_at(c.sym, s.scope_index);
  *scope = s.scope;
  c.sym.statics = s.statics;
  c.sym.binding_facts = s.binding_facts;
  c.names.next_binding = s.next_binding;
  c.meta_group.resize(s.meta_group_size);
  c.ancestors.truncate(s.ancestors);
  c.placements.resize(s.placements);
  c.sym.local_macro_names = s.local_macro_names;
  c.names.counters = s.counters;
  c.init_fn = s.initializer_name;
  c.fini_fn = s.shutdown_name;
}

static void _restore_effects(SymTxn &s) {
  Compiler c = s.c;
  c.names.adapters = s.adapters;
  c.pending.restore(s.pending);
  c.origins.resize(s.origin_count);
  c.origin = s.origin;
  c.needs_exception = s.needs_exception;
}

static void _restore_sources(SymTxn &s) {
  Compiler c = s.c;
  c.source_occurrences.resize(s.source_occurrences);
  _replace_map(c.source_definitions, s.source_definitions);
}
