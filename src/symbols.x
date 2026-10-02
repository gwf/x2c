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
#pragma private
$(import "../src/parse-report-macros.xmacro")
$(import "../src/grammar.xmacro")

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

/* A compiler's symbol table: a stack of scopes whose lowest `base_scopes`
   hold file-scope declarations. */
typedef struct Sym {
  Block scopes, Map globals, statics, binding_facts;
  int base_scopes, local_macro_names;
  // Owning compiler, so type resolution can report its own diagnostics.
  Compiler c;
} *Sym;

/** Creates the empty symbol table that compiler `c` owns. */
Sym Sym.new(Compiler c) {
  Sym s = Scope.calloc(1, sizeof(struct Sym));
  s.c = c;
  s.binding_facts = {};
  s.scopes = Block.new(sizeof(SymScope));
  s.statics = {};
  return s;
}

static SymScope *Sym._scope_at(Sym s, int index) {
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
  s._clear_symbols(globals, 1);
  s._push_symbols(s.globals);
}

/** Resets symbol state to read `base` below the writable scope `overlay`.

    Later definitions mutate `overlay`; `base` is only read.
*/
void Sym.reset_overlay(Sym s, Map base, Map overlay) {
  s._clear_symbols(overlay, 2);
  s._push_symbols(base != NULL ? base : {});
  s._push_symbols(s.globals);
}

static void Sym._clear_symbols(Sym s, Map globals, int base_scopes) {
  s.scopes.clear();
  s.globals = globals != NULL ? globals : {};
  s.statics = {};
  s.base_scopes = base_scopes;
  s.local_macro_names = 0;
  s.binding_facts = {};
}

static void Sym._push_symbols(Sym s, Map symbols) {
  struct SymScope scope = {
    .symbols = symbols, .bindings = {}, .enumerators = {}};
  s.scopes.push(&scope);
}

/** Pushes a new empty lexical scope. */
void Sym.push_new_scope(Sym s) => s._push_symbols({});

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

// symbol maps

/** Returns the mutable global symbol map supplied to the latest reset. */
Map Sym.global_symbols(Sym s) => s.globals;

/** Copies all base-scope symbols into a fresh map in source order.

    Package collection uses this so it resolves against the prelude and the
    importing unit's already-visible includes without mutating either.
*/
Map Sym.base_symbols(Sym s) {
  Map seed = {};
  for (int i = 0; i < s.base_scopes; i++) seed.merge(s._scope_at(i).symbols);
  return seed;
}

/** Returns the current scope's mutable symbol map, or `NULL`. */
Map Sym.current_symbols(Sym s) {
  SymScope *scope = s._scope_at(-1);
  return scope ? scope.symbols : NULL;
}

/** Returns a fresh map of the base symbols with the current scope's rows
    merged in. */
Map Sym.unit_symbols(Sym s) {
  Map symbols = s.base_symbols();
  if (!s.at_file_scope()) symbols.merge(s.current_symbols());
  return symbols;
}

/** Returns the current borrowed set of file-static declaration keys.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Sym.file_statics(Sym s) => s.statics;

/** Marks a declaration key as file-static. */
void Sym.mark_static(Sym s, List key) => s.statics[key] = 1;

/** Returns the visible one-part source names and their semantic types.
    Inner scopes win. The result is a fresh List; types remain borrowed. */
List Sym.visible_symbols(Sym s) {
  Map seen = {};
  Array rows = [];
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    SymScope *scope = s._scope_at(i);
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
  Map scope = s._scope_at(-1).symbols;
  if (log_should_log(<debug>, <symtab>))
    log_debug(<symtab>, %( (func "Sym.set") (key $key) (val $type) ));
  scope[key] = type;
  if (_retained_member(key)) s.binding_facts[%(aggfact $key)] = type;
}

static int _retained_member(List key) =>
  !!key.match(%((!or struct union) (!or (binding ? ?) (gensym ? ?)) ? *));

/** Defines `key` and returns its stable binding in the active scope. */
List Sym.define(Sym s, List key, List type) {
  SymScope *scope = s._scope_at(-1);
  s.set(key, type);
  _seed_var_tag(key, type);
  return s._scope_binding(*scope, key);
}

static void _seed_var_tag(List key, List type) {
  String owner = _var_converter_owner(key, type);
  if (!owner) return;
  String converter = %"${owner}_var", Type declared = %($owner);
  declared.register_var_tag(owner, converter);
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
    if (key is <list> && type is <list>) _seed_var_tag(key, type);
}

/** Defines `key` in the unit's writable base scope.

    The definition survives the expression scope that first resolved it. Its
    binding is issued at the first reference, as for a row an included file
    contributes, so the unit numbers its bindings the same whether it defined
    the row here or replayed it from an interface.
*/
void Sym.define_global(Sym s, List key, List type) {
  SymScope *scope = s._scope_at(s.base_scopes - 1);
  scope.symbols[key] = type;
  _seed_var_tag(key, type);
}

/** Associates an enumerator key with its owner in the active scope. */
void Sym.declare_enumerator(Sym s, List key, Symbol owner) {
  SymScope *scope = s._scope_at(-1);
  if (scope) scope.enumerators[key] = owner;
}

// bindings

static List Sym._scope_binding(Sym s, SymScope &scope, List key) {
  Var found;
  List binding;
  if (scope.bindings.try_get(key, found)) binding = found;
  else {
    binding = s._new_binding(key);
    scope.bindings[key] = binding;
  }
  (Var binding_tag, int identity, String spelling) = binding;
  (void) binding_tag;
  if (!s.binding_facts.contains(%(known $identity)))
    s.binding_facts[%(known $identity)] = spelling;
  List self_key = %(self $binding);
  if (!s.binding_facts.contains(self_key)) {
    Var relative;
    if (scope.symbols.try_get(%(self $spelling), relative))
      s.binding_facts[self_key] = relative;
  }
  if (s.c.source_facts) s._note_source_key(scope, key, binding);
  return binding;
}

/* Source facts find a binding's declaration through the map and key that
   hold its symbol row. */
static void Sym._note_source_key(
  Sym s, SymScope &scope, List key, List binding) {
  Compiler c = s.c;
  List source_key = %(${scope.symbols} $key);
  s.binding_facts[%(src-key $binding)] = source_key;
  Var declaration;
  if (c.source_primary && !c.shallow &&
      c.source_declarations.try_get(source_key, declaration))
    c.source_definitions[binding] = declaration;
}

static List Sym._new_binding(Sym s, List key) {
  int identity = ++s.c.names.next_binding;
  Var name = key.last();
  List binding = binding_identity_new(identity, name);
  s.binding_facts[%(known $identity)] = name;
  return binding;
}

/** Allocates a fresh binding identity for a compiler-introduced spelling. */
List Sym.introduce(Sym s, String spelling) => s._new_binding(%($spelling));

/** Returns `key`'s binding in the current scope, or `NULL`. */
List Sym.current_binding(Sym s, List key) {
  SymScope *scope = s._scope_at(-1);
  Var binding;
  return scope && scope.bindings.try_get(key, binding) ? binding : NULL;
}

/** Returns the current scope's enum owner for `key`, or zero. */
Symbol Sym.enumerator_owner(Sym s, List key) {
  SymScope *scope = s._scope_at(-1);
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
    foreach (Var (_, candidate), s._scope_at(i).bindings)
      if (List.equal(candidate, binding)) return 1;
  return 0;
}

/** Returns the current borrowed semantic-facts map indexed by binding.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Compiler.semantic_binding_facts(Compiler c) => c.sym.binding_facts;

// lookup

/** Returns `key`'s type, retrying a bare key in package space, or `NULL`. */
List Sym.get(Sym s, List key) {
  List found = s.get_exact(key);
  if (found) return found;
  List retry = s._package_retry_key(key);
  return retry ? s.get_exact(retry) : NULL;
}

/** Returns `key`'s type without package fallback, or `NULL`. */
List Sym.get_exact(Sym s, List key) {
  Var val;
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    Map scope = s._scope_at(i).symbols;
    if (scope.try_get(key, val)) return val;
  }
  if (_retained_member(key) &&
      s.binding_facts.try_get(%(aggfact $key), val)) return val;
  return NULL;
}

/* Package files may reference their own file-scope names bare. A plain-key
   total miss retries the package-prefixed key; exact entries win, and
   units outside package mode never retry. */
static List Sym._package_retry_key(Sym s, List key) {
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
  s._lookup_from(key, type, (int) s.scopes.len() - 1, 0);

/** Resolves `key` or creates a forward binding in the current scope.

    Stores `NULL` through `type` when no declaration supplies a type.
*/
List Sym.reference(Sym s, List key, Type &?type) =>
  s._lookup_from(key, type, (int) s.scopes.len() - 1, 1);

/** Resolves a binding through base scopes and optionally stores its type.

    Returns `NULL` when no base scope contains the key.
*/
List Sym.resolve_global(Sym s, List key, Type &?type) =>
  s._lookup_from(key, type, s.base_scopes - 1, 0);

/** Resolves a global name or creates its forward binding in the base scope.
    Local declarations cannot capture a retained macro's global reference.
*/
List Sym.reference_global(Sym s, List key) {
  List binding = s.resolve_global(key, NULL);
  if (binding) return binding;
  return s._scope_binding(*s._scope_at(s.base_scopes - 1), key);
}

static List Sym._lookup_from(
  Sym s, List key, Type &?type, int first, int forward) {
  Var found;
  for (int i = first; i >= 0; i--) {
    SymScope *scope = s._scope_at(i);
    if (scope.symbols.try_get(key, found)) {
      if (type) type = found;
      return s._scope_binding(*scope, key);
    }
    if (scope.bindings.try_get(key, found)) {
      if (type) type = NULL;
      return found;
    }
  }
  List retry = s._package_retry_key(key);
  if (retry && (!forward || s.get_exact(retry)))
    return s._lookup_from(retry, type, first, forward);
  if (type) type = NULL;
  return forward ? s._scope_binding(*s._scope_at(-1), key) : NULL;
}

// declarations

/** Analyzes a complete declaration type and installs its stored declared type.

    Returns the declared binding. At file scope this also records static
    visibility; local declarations record automatic-storage and declared-type
    facts. Stored types discard storage and `inline` while retaining `const`,
    `restrict`, and `volatile`.
*/
List Sym.declare(Sym s, List context, List key, List ast) {
  if (s.c.package) key = s._package_declared_key(context, key, ast);
  s.c._check_spelling(_declared_spelling(key));
  Type ctxkey = %( @context @key ), type = ast.type_from_ast();
  Type declared_type = type;
  if ((int) s.scopes.len() == s.base_scopes && !context)
    s._track_static((List) ctxkey, ast);
  List binding = NULL;
  if (context === %(typedef)) binding = s.define(key, (List) ctxkey);
  type = _stored_type(type, ctxkey, ast);
  if (!binding) binding = s.define(ctxkey, (List) type);
  else {
    s.set(ctxkey, (List) type);
    s._local_typedef(type, binding);
  }
  if (!context && !s.at_file_scope())
    s._local_object(key, binding, declared_type);
  return binding;
}

/* Package mode rewrites file-scope non-static declaration keys into the
   package's `name__` space, so binding spellings, aggregate tags, and
   derived Var converters carry the prefix everywhere they are read.
   Statics keep their spellings (C internal linkage); anonymous aggregate
   gensyms are not source spellings and stay in the compiler's space. */
static List Sym._package_declared_key(
  Sym s, List context, List key, List ast) {
  Compiler c = s.c;
  if ((int) s.scopes.len() != s.base_scopes) return key;
  if (context && !(context === %(typedef))) return key;
  if (ast.type().is_static()) return key;
  Var (head, tag) = key;
  if (head is <string> && !key.cdr()) return %(${c.package_spelling(head)});
  if ((head == <struct> || head == <union> || head == <enum>) &&
      key.cdr() && !key.cddr() && tag is <string>)
    return %($head ${c.package_spelling(tag)});
  return key;
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

macro Statement $report.parse_name_package(
  Expr $c, Expr $spelling, Expr $owner) {
  $c.report_error(
    <parse>,
    %"'${$spelling}' is reserved for imported package '${$owner}'",
    $c.token, NULL);
}

macro Statement $report.parse_name_reserved(Expr $c, Expr $spelling) {
  $c.report_error(
    <parse>,
    %"'${$spelling}' is reserved for compiler-generated names",
    $c.token, NULL);
}

/* A source declaration may not take a compiler-generated spelling or one
   in an imported package's space. A shallow parse reads emitted C, whose
   generated spellings are the compiler's own output. */
static void Compiler._check_spelling(Compiler c, String spelling) {
  if (!c.shallow && _is_reserved_spelling(spelling)) {
    $report.parse_name_reserved(c, spelling);
  }
  String owner = c._package_reserved_owner(spelling);
  if (owner)
    $report.parse_name_package(c, spelling, owner);
}

// Checked once per declaration, with no prepass over the token stream.
static int _is_reserved_spelling(String s) {
  if (!s) return 0;
  if (s.startswith("_x2c_") || s == "_init_guard_" || s == "_file_init_")
    return 1;
  if (s.len() < 2 || s[0] != '_') return 0;
  for (int i = 1; i < s.len(); i++) if (s[i] < '0' || s[i] > '9') return 0;
  return 1;
}

/* Only packages imported by this unit reserve their `name__` space; foreign
   headers may contain `__`, and a package unit keeps its own prefix. */
static String Compiler._package_reserved_owner(Compiler c, String spelling) {
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
   strips it. */
static void Sym._track_static(Sym s, List key, List ast) {
  if (ast.type().is_static()) s.statics[key] = 1;
  else s.statics.del(key);
}

// A tagged definition also publishes its tag unless the key is that tag.
static Type _stored_type(Type type, Type key, List ast) {
  if (type.is_aggregate_tag_body() && !key.is_aggregate_tag()) {
    Var (aggregate, tag) = ast;
    type = %( $aggregate $tag );
  }
  return type.declared();
}

/* A block-local typedef emits under a fresh spelling, and a local tag
   records its named type. */
static void Sym._local_typedef(Sym s, Type type, List binding) {
  if (s.at_file_scope()) return;
  if (type.is_aggregate_tag()) s.binding_facts[%(ntype $binding)] = type;
  s.binding_facts[%(emitted $binding)] =
    s.c.fresh_name("local_typedef");
}

/* A local object records its automatic storage and declared type. One that
   shadows a declared `T_var` converter emits under a fresh spelling, so
   generated boxing still reaches the converter. */
static void Sym._local_object(Sym s, List key, List binding, Type type) {
  s._mark_automatic(binding, type);
  Type global_type = NULL;
  s.resolve_global(key, global_type);
  if (_var_converter_owner(key, global_type) &&
      !s.binding_facts.contains(%(emitted $binding)))
    s.binding_facts[%(emitted $binding)] =
      s.c.fresh_name("var_converter_shadow");
}

static void Sym._mark_automatic(Sym s, List binding, Type type) {
  s.binding_facts[%(automatic $binding)] = 1;
  s.binding_facts[%(type $binding)] = type;
}

/** Installs an existing binding with `ast`'s qualifier-preserving type. */
List Sym.bind_identity(Sym s, List context, List binding, List ast) {
  String spelling = binding_identity_spelling(binding);
  List key = context ? %(@context $spelling) : %($spelling);
  SymScope *scope = s._scope_at(-1);
  Type annotation = ast.type_from_ast();
  scope.symbols[key] = annotation.declared();
  if (context === %(typedef)) {
    key = %($spelling);
    scope.symbols[key] = %(typedef $spelling);
    s._local_typedef(annotation, binding);
  }
  scope.bindings[key] = binding;
  if (!context && !s.at_file_scope()) s._mark_automatic(binding, annotation);
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
    if (definition && !s.get_exact(type)) s.declare(NULL, type, type);
    return name;
  }
  if (!definition && s.get_exact(type)) return s.local_type(type).cadr();
  if (!definition && c.shallow) return name;
  List binding = s.current_binding(type);
  return binding ? binding : s.declare(NULL, type, type);
}

// declaration visibility

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
      String name = binding_identity_spelling(identity);
      if (name) c.sym.mark_static(%($name));
    }
    case %(
      (!set ?kind (!or typedef declare)) ?type (bindings *rows)
    ): {
      int mark = private || type.type().is_static();
      c._record_rows_visibility(declaration, kind, private, mark, rows);
    }
  }
}

static void Compiler._record_rows_visibility(
  Compiler c, List declaration, Symbol kind, int private, int mark,
  List rows) {
  foreach (List row, rows)
    match (row) case $source_declarator_row(%(?identity *)):
      _record_declaration_binding_visibility(
        c, declaration, kind, private, mark, identity);
}

static void _record_declaration_binding_visibility(
  Compiler c, List declaration, Symbol kind, int private, int mark,
  List identity) {
  String name = binding_identity_spelling(identity);
  if (kind == <typedef> && name)
    c.record_source_typedef(name, declaration, private);
  if (mark && name) c.sym.mark_static(%($name));
}

// package names

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
  c._check_package_binding("alias", alias, token);
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
    $report.parse_package_member(c, member_token, name, member);
  c._check_package_binding("name", local, local_token);
  c.package_members[local] = binding;
}

macro Statement $report.parse_package_collision(
  Expr $c, Expr $site, Expr $kind, Expr $local) {
  $c.report_error(
    <parse>,
    %"package ${$kind} '${$local}' collides with a declared name",
    $site, NULL);
}

macro Statement $report.parse_package_bound(
  Expr $c, Expr $site, Expr $kind, Expr $local, Expr $bound) {
  $c.report_error(
    <parse>,
    %"package ${$kind} '${$local}' is already bound",
    $site, %( "bound to: ${$bound}" ));
}

/* An alias and a `with` name each claim one local spelling. Rebinding that
   spelling, or taking one a declaration already uses, is the same conflict.
   Both messages name what the developer wrote. */
static void Compiler._check_package_binding(
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
    $report.parse_package_bound(c, token, kind, local, bound);
  if (c.sym.get_exact(%($local)))
    $report.parse_package_collision(c, token, kind, local);
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

    Captured bindings are recorded for later shadow handling. Replacing a
    name already defined in this scope does not increase the local macro
    count.
*/
void Sym.define_macro(Sym s, Atom name, List definition) {
  SymScope *scope = s._scope_at(-1);
  if (scope.macros == NULL) scope.macros = {};
  if (!scope.macros.contains(name)) s.local_macro_names++;
  scope.macros[name] = definition;
  Var captures = definition.assoc(<captures>);
  if (captures is <list>) foreach (Var capture, captures.list())
    if (capture is <list>)
      s.binding_facts[%(local-macro-capture ${capture.list()})] = 1;
}

/** Returns whether any lexical scope contains a local macro definition. */
int Sym.has_local_macros(Sym s) => s.local_macro_names != 0;

/** Returns the innermost visible local macro named `name`, or `NULL`. */
List Sym.lookup_macro(Sym s, Atom name) {
  Var definition;
  for (int i = (int) s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = s._scope_at(i);
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
  return s._resolve_chain(key, NULL, key, 0);
}

/* Resolve a typedef chain, optionally stopping at a semantic type
   identity. origin is the type the caller asked about, kept only so an
   over-budget walk can name it instead of some mid-chain link. */
static Type Sym._resolve_chain(
  Sym s, Type key, Type stop, Type origin, int hops) {
  if (hops > RESOLVE_KEY_MAX_HOPS) s._typedef_budget_error(origin);
  if (stop && key == stop) return key;
  if (key.is_typedef_name() || key.is_typedef()) {
    Type type = s._typedef_target(key);
    if (type) return s._resolve_chain(type, stop, origin, hops + 1);
  }
  match (key) case %((!set ?kind (!or struct union))
      (binding ? ?spelling)):
    if (!s.field_order(key)) return %($kind $spelling);
  return key;
}

macro Statement $report.type_typedef_depth(Expr $c, Expr $origin) {
  $c.report_error(
    <type>,
    %"typedef chain too deep (possible cycle) resolving ${$origin.repr()}",
    NULL, NULL);
}

/* The resolver cannot tell a true cycle from an absurdly long chain, so the
   diagnostic states only what it can determine. `typedef Color Color;` is
   legal C; it binds ("Color") to (typedef "Color") and back, so cycles are
   real. */
static void Sym._typedef_budget_error(Sym s, Type origin) {
  $report.type_typedef_depth(s.c, origin);
}

/* Semantic types contain no local aliases. A retained file type's spelling
   must keep its meaning when an inner declaration shadows that spelling. */
static Type Sym._typedef_target(Sym s, Type key) {
  for (int i = s.base_scopes - 1; i >= 0; i--) {
    Var target;
    if (s._scope_at(i).symbols.try_get(key, target)) return target;
  }
  return NULL;
}

/** Resolves one typedef hop and counts against the shared cycle budget.

    `hops` is an in-out counter initialized by the caller for the whole walk.
    Returns `NULL` for an unresolved link. The shared budget turns a cycle
    into the same diagnostic as full-chain resolution.
*/
Type Sym.next_typedef(Sym s, Type type, int &hops) {
  if (++hops > RESOLVE_KEY_MAX_HOPS) s._typedef_budget_error(type);
  return type.is_typedef_name() || type.is_typedef()
       ? s._typedef_target(type) : s.get(type);
}

/** Resolves a typedef name through the base scopes only, ignoring local
    typedefs, or returns NULL when the base scopes do not declare it. */
Type Sym.resolve_base_type(Sym s, Type key) {
  Type type = s._typedef_target(key);
  for (int hops = 0; type && hops < RESOLVE_KEY_MAX_HOPS; hops++) {
    Type next = s._typedef_target(type);
    if (!next) break;
    type = next;
  }
  return type;
}

/** Returns the name of the one file-scope typedef declared directly as
    `type`, or NULL when no typedef or several typedefs are. */
Type Sym.sole_typedef(Sym s, Type type) {
  String found = NULL;
  for (int i = 0; i < s.base_scopes; i++)
    foreach (Var (key, target), s._scope_at(i).symbols)
      match (key) case %(typedef ?(String name)):
        if (target == type) {
          if (found && found != name) return NULL;
          found = name;
        }
  return found ? %($found) : NULL;
}

/** Resolves typedef bases while retaining every declarator qualifier. */
Type Sym.normalize_declared_type(Sym s, Type type) =>
  type ? s._normalize_chain(type, type, 0) : NULL;

static Type Sym._normalize_chain(Sym s, Type type, Type origin, int hops) {
  type = type.declared();
  if (hops > RESOLVE_KEY_MAX_HOPS) s._typedef_budget_error(origin);
  Type next = s._typedef_base_step(type);
  return next ? s._normalize_chain(next, origin, hops + 1) : type;
}

static Type Sym._typedef_base_step(Sym s, Type type) {
  Type base = type.base_type();
  if (!base || (!base.is_typedef_name() && !base.is_typedef())) return NULL;
  Type next = s._typedef_target(base);
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
  if (base.is_aggregate_tag() && base.cadr() is <string>)
    return s._local_tag(type, base);
  return base.is_bare_typedef_name() ? s._local_alias(type, base) : type;
}

// The binding of the nearest declaration replaces a block-scoped name.
static Type Sym._local_tag(Sym s, Type type, Type base) {
  for (int i = s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = s._scope_at(i);
    Var binding;
    if (scope.bindings.try_get(base, binding))
      return _replace_type_base(type, base, %(${base.car()} $binding));
  }
  return type;
}

// A local typedef name resolves to the target saved beside its marker.
static Type Sym._local_alias(Sym s, Type type, Type base) {
  for (int i = s.scopes.len() - 1; i >= s.base_scopes; i--) {
    Map symbols = s._scope_at(i).symbols;
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

/* Angle-included system typedefs have no collected binding. These canonical
   forms match Type.scalar and are consulted only after source typedef
   resolution, so a source declaration wins. A 64-bit or pointer-width name
   maps to long where long has that width, retaining the native long Var
   identity, and to long long on a host such as LLP64 Windows where it does
   not.

   The labels are encoded Symbols, not the C spellings, and the subject is
   `name.symbol()`, the same encoding applied to the source identifier.
   A C name that outruns the Symbol capacity therefore appears here in the
   form it encodes to: `size_t` is `<size-t>`, since the 5-bit alphabet
   folds the separator, and `uint16_t` is `<uint16_>`, since a digit forces
   the seven-byte form. `uint8_t` and `int16_t` fit and keep their
   spelling. */
static Type _builtin_typedef_scalar(Type key) {
  if (!key.is_bare_typedef_name()) return NULL;
  String name = key.car();
  switch (name.symbol()) {
    case <u8>: case <uint8_t>: return %(unsigned char);
    case <i8>: case <int8_t>: return %(signed char);
    case <u16>: case <uint16_>: return %(unsigned short);
    case <i16>: case <int16_t>: return %(short);
    case <u32>: case <uint32_>: return %(unsigned);
    case <i32>: case <int32_t>: case <wchar-t>: return %(int);
    case <u64>: case <uint64_>:
      return sizeof(long) == 8 ? %(unsigned long) : %(unsigned long long);
    case <uintptr-t>: case <size-t>:
      return sizeof(long) == sizeof(void *)
           ? %(unsigned long) : %(unsigned long long);
    case <i64>: case <int64_t>:
      return sizeof(long) == 8 ? %(long) : %(long long);
    case <intptr-t>: case <ptrdiff-t>: case <ssize-t>:
      return sizeof(long) == sizeof(void *) ? %(long) : %(long long);
    case <off-t>: case <time-t>: return %(long);
    case <u128>: return %(unsigned long long);
    case <i128>: return %(long long);
    case <f32>: return %(float);
    case <f64>: return %(double);
    case <f128>: return %(long double);
  }
  return NULL;
}

// value types

/** Returns a type's `Var` tag and optionally stores its resolved type.

    `resolved` receives the final type even when the result is zero because no
    `Var` tag is registered. A null input stores `NULL` and returns zero.
*/
Symbol Sym.var_tag_for_type(Sym s, Type type, Type &?resolved) {
  Type origin = type.canonicalize();
  return s._var_tag_chain(origin, origin, resolved, 0);
}

static Symbol Sym._var_tag_chain(
  Sym s, Type type, Type origin, Type &?resolved, int hops) {
  type = type.canonicalize();
  Symbol tag = type.var_tag();
  if (tag) {
    if (resolved) resolved = type;
    return tag;
  }
  if (hops > RESOLVE_KEY_MAX_HOPS) s._typedef_budget_error(origin);
  Type next = s._typedef_base_step(type);
  if (next) return s._var_tag_chain(next, origin, resolved, hops + 1);
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
  type = s._resolve_chain(origin, wanted, origin, 0);
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
    if (row.car().truth() || !s.resolve_key(member).is_aggregate()) continue;
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
    while (declaration.car() == <at>) declaration = declaration.caddr();
    if (declaration.car() == <c-assert>) continue;
    List bindings = declaration.caddr();
    foreach (List declarator, bindings.cdr())
      rows.push(s._field_row(type, declaration, declarator));
  }
  s.set(%(@type "field-order"), %(fields @{rows.list_free()}));
}

static List Sym._field_row(
  Sym s, Type type, List declaration, List declarator) {
  String name = binding_identity_spelling(declarator.cadr());
  Type declared = name ? s.get(%(@type $name))
    : %(declare ${declaration.cadr()} (bindings $declarator))
      .type_from_ast().declared();
  return %($name $declared);
}

/** Returns recorded fields in source order, or `NULL`. */
List Sym.field_order(Sym s, Type type) => s.get(%(@type "field-order"));

/** Marks one named aggregate field as a delegate. */
void Sym.declare_delegate_field(Sym s, Type aggregate, String name) {
  s.set(%(@aggregate delegate $name), %(delegate));
}

/** Resolves typedefs or one pointer layer to an aggregate tag, or `NULL`. */
Type Sym.delegate_aggregate(Sym s, Type type) {
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

   Binding a macro's syntax stages its rows in a transaction, so a failed
   expansion leaves the symbol table as it was. */

/** Begins a reversible transaction over the current semantic scope.

    The transaction stages the current scope maps, file-static and binding
    facts, compile-time struct layouts, binding and generated-name
    counters, and initializer names. It does not snapshot parser position or
    other compiler state.
*/
SymTxn Compiler.begin_semantic_transaction(Compiler c) {
  SymTxn transaction = { .c = c };
  transaction.scope_index = c.sym.scopes.len() - 1;
  SymScope *scope = c.sym._scope_at(transaction.scope_index);
  transaction._save(*scope);
  if (transaction.extended) transaction._save_effects();
  if (c.source_facts && c.source_primary) transaction._save_sources();
  transaction._stage(*scope);
  transaction.active = 1;
  return transaction;
}

static void SymTxn._save(SymTxn &s, SymScope scope) {
  Compiler c = s.c;
  s.scope = scope;
  s.counters = c.names.counters;
  s.statics = c.sym.statics;
  s.binding_facts = c.semantic_binding_facts();
  s.next_binding = c.names.next_binding;
  s.local_macro_names = c.sym.local_macro_names;
  s.initializer_name = c.init_fn;
  s.shutdown_name = c.fini_fn;
  s.extended = c.macro_application > 0;
}

/* The base scopes other than the active one get fresh binding maps; the
   transaction keeps the originals. */
static void SymTxn._save_effects(SymTxn &s) {
  Compiler c = s.c;
  s.adapters = c.names.adapters;
  s.base_bindings = [];
  s.early_count = c.early_decls.len();
  s.init_count = c.inits.len();
  s.origin_count = c.origins.len();
  s.origin = c.origin;
  s.needs_exception = c.needs_exception;
  c.names.adapters = c.names.adapters.copy();
  for (int i = 0; i < c.sym.base_scopes; i++) {
    if (i == s.scope_index) continue;
    SymScope *base = c.sym._scope_at(i);
    s.base_bindings.push(%($i ${base.bindings}));
    base.bindings = base.bindings.copy();
  }
}

static void SymTxn._save_sources(SymTxn &s) {
  s.source_definitions = s.c.source_definitions.copy();
  s.source_occurrences = s.c.source_occurrences.len();
}

/* Macro binding is incremental. Copy only the maps that construction
   mutates so failure can discard its rows while reads still reach the
   unchanged outer scopes. */
static void SymTxn._stage(SymTxn &s, SymScope &scope) {
  Compiler c = s.c;
  scope.symbols = s.scope.symbols.copy();
  c.merge_source_declarations(scope.symbols, s.scope.symbols);
  scope.bindings = s.scope.bindings.copy();
  scope.enumerators = s.scope.enumerators.copy();
  scope.macros = s.scope.macros != NULL ? s.scope.macros.copy() : NULL;
  c.sym.statics = c.sym.statics.copy();
  c.sym.binding_facts = c.semantic_binding_facts().copy();
  c.names.counters = c.names.counters.copy();
}

/** Returns whether the transaction's active scope changed its macro map. */
int SymTxn.local_macros_changed(SymTxn &s) {
  SymScope *scope = s.c.sym._scope_at(s.scope_index);
  Map before = s.scope.macros, after = scope.macros;
  if (before == NULL || after == NULL)
    return (void *) before != (void *) after;
  return !before.equal(after);
}

// commit and rollback

/** Publishes an active semantic transaction and makes rollback a no-op.
    An absent or inactive transaction has no effect.
*/
void SymTxn.commit(SymTxn &?s) {
  if (!s) return;
  if (!s.active) return;
  Compiler c = s.c;
  SymScope *scope = c.sym._scope_at(s.scope_index);
  SymScope staged = *scope;
  /* Restore the original map identities before merging staged rows. Code
     holding a borrowed scope map must observe a committed expansion. */
  *scope = s.scope;
  c._merge_scope(*scope, staged);
  if (s.extended) s._commit_effects();
  s.active = 0;
}

static void Compiler._merge_scope(
  Compiler c, SymScope &scope, SymScope staged) {
  scope.symbols.merge(staged.symbols);
  c.merge_source_declarations(scope.symbols, staged.symbols);
  scope.bindings.merge(staged.bindings);
  scope.enumerators.merge(staged.enumerators);
  if (staged.macros == NULL) return;
  if (scope.macros == NULL) scope.macros = {};
  scope.macros.merge(staged.macros);
}

static void SymTxn._commit_effects(SymTxn &s) {
  Compiler c = s.c;
  Map adapters = c.names.adapters;
  c.names.adapters = s.adapters;
  s.adapters.merge(adapters);
  foreach (List row, s.base_bindings.list()) {
    SymScope *base = c.sym._scope_at(row.car());
    Map staged = base.bindings, original = row.cadr();
    base.bindings = original;
    original.merge(staged);
  }
}

/** Commits an active transaction, retaining the original semantic-map owners.
    The caller may then release the transaction's construction scope.
    Source-fact collection must be disabled: its records retain staged maps.
    Parsing and evaluation must allocate outside that temporary scope.
*/
void SymTxn.commit_transient(SymTxn &s) {
  Compiler c = s.c;
  Map statics = c.sym.statics, facts = c.semantic_binding_facts();
  Map counters = c.names.counters;
  s.commit();
  c.sym.statics = s.statics;
  c.sym.binding_facts = s.binding_facts;
  c.names.counters = s.counters;
  _replace_map(s.statics, statics);
  _replace_map(s.binding_facts, facts);
  _replace_map(s.counters, counters);
}

/* Gives `original` exactly the rows of `staged` and keeps its identity.
   Deletions matter: a declaration can remove an earlier file-static
   designation. */
static void _replace_map(Map original, Map staged) {
  Array keys = $auto(original.keys());
  foreach (Var key, keys) if (!staged.contains(key)) original.del(key);
  original.merge(staged);
}

/** Restores every semantic value captured by an active transaction.
    An absent or inactive transaction has no effect.
*/
void SymTxn.rollback(SymTxn &?s) {
  if (!s) return;
  if (!s.active) return;
  Compiler c = s.c;
  s._restore();
  if (s.extended) s._restore_effects();
  if (c.source_facts && c.source_primary) s._restore_sources();
  s.active = 0;
}

static void SymTxn._restore(SymTxn &s) {
  Compiler c = s.c;
  SymScope *scope = c.sym._scope_at(s.scope_index);
  *scope = s.scope;
  c.sym.statics = s.statics;
  c.sym.binding_facts = s.binding_facts;
  c.names.next_binding = s.next_binding;
  c.sym.local_macro_names = s.local_macro_names;
  c.names.counters = s.counters;
  c.init_fn = s.initializer_name;
  c.fini_fn = s.shutdown_name;
}

static void SymTxn._restore_effects(SymTxn &s) {
  Compiler c = s.c;
  c.names.adapters = s.adapters;
  foreach (List row, s.base_bindings.list())
    c.sym._scope_at(row.car()).bindings = row.cadr();
  c.early_decls.resize(s.early_count);
  c.inits.resize(s.init_count);
  c.origins.resize(s.origin_count);
  c.origin = s.origin;
  c.needs_exception = s.needs_exception;
}

static void SymTxn._restore_sources(SymTxn &s) {
  Compiler c = s.c;
  c.source_occurrences.resize(s.source_occurrences);
  _replace_map(c.source_definitions, s.source_definitions);
}
