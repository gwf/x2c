/*  declarations.x -- symbol declarations */

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
  Type prior = type.is_function() ? s.get(ctxkey) : NULL;
  if (prior.is_function() && !s.same_list_rest_convention(type, prior))
    s.c.report_error(<type>, "conflicting List rest calling convention",
      NULL, NULL);
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
    Retained declarations keep their already resolved spelling.
*/
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
  if (plain) return $(c.declared_spelling(prefix, head));
  if (tagged) return $(head, c.declared_spelling(prefix, tag));
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
  return $(Ast.binding_spelling(binding)) in s.statics;
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
  foreach (List context in contexts) {
    if (prefix && !(name in s.prefixed) &&
        $(@context, name) in s.statics)
      $fail.symbols_module_shadow(c, c.token, name);
    if (!c.module_declaration ||
        !(c.source_private > 0 || ast.type().is_static())) continue;
    foreach (String other in c.file_prefixes())
      if (%(@context "$other$name") in s.statics)
        $fail.symbols_module_shadow(c, c.token, name);
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
    $fail.symbols_name_reserved(c, c.token, spelling);
  String owner = _package_reserved_owner(c, spelling);
  if (owner)
    $fail.symbols_name_package(c, c.token, spelling, owner);
}

// Checked once per declaration, with no prepass over the token stream.
static int _is_reserved_spelling(String s) {
  if (!s) return 0;
  if (s.startswith("_x2c_gensym_") ||
      s == "_init_guard_" || s == "_file_init_")
    return 1;
  int length = s.len();
  if (length < 2 || s[0] != '_') return 0;
  for (int i = 1; i < length; i++) if (s[i] < '0' || s[i] > '9') return 0;
  return 1;
}

/* Only packages imported by this unit reserve their `name__` space; foreign
   headers may contain `__`, and a package unit keeps its own prefix. */
static String _package_reserved_owner(Compiler c, String spelling) {
  if (!spelling || !c.package_aliases.len()) return NULL;
  foreach (String (alias, name) in c.package_aliases) {
    if (name == c.package) continue;
    if (spelling.startswith(%"$(name)__")) return name;
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
    type = $(aggregate, tag);
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

/* A local object records its automatic storage and declared type. One
   that shadows a declared `T_var` converter emits under a fresh spelling,
   so generated boxing still reaches the converter. */
static void _local_object(Sym s, List key, List binding, Type type) {
  _mark_automatic(s, binding, type);
  Type global_type = NULL;
  s.resolve_global(key, global_type);
  if (_var_converter_owner(key, global_type) &&
      !(%(emitted $binding) in s.binding_facts))
    s.put(
      s.binding_facts, %(emitted $binding),
      s.c.fresh_name("var_converter_shadow"));
}

static void _mark_automatic(Sym s, List binding, Type type) {
  s.put(s.binding_facts, %(automatic $binding), 1);
  s.put(s.binding_facts, %(type $binding), type);
}

/** Emits every local object spelled `spelling` that the current scope
    sees, the enclosing ones too, under one fresh spelling, so a file-scope
    name a template keeps reaches the global there, and returns them.
    Locals of other scopes keep their spellings for the native macros that
    name them.
*/
List Sym.unshadow_visible(Sym s, String spelling) {
  List key = $(spelling), visible = NULL;
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
  List key = context ? $(@context, spelling) : $(spelling);
  SymScope *scope = _scope_at(s, -1);
  Type annotation = ast.type_from_ast();
  s.put(scope.symbols, key, annotation.declared());
  if (context === %(typedef)) {
    key = $(spelling);
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
  if (definition && !c.macro_holes)
    match (name) case %(gensym *):
      match (c.enclosing(<declarator>))
        case %(declare ?(Type base) *)
          if (<auto> in base && !base.base_type()):
            return s.introduce(c.fresh_name("inferred_type"));
  if (name is not <string>) return name;
  if (c.macro_holes) {
    List local = c.macro_tag_name(kind, name, definition);
    return local ? local : name;
  }
  Type type = $(kind, name);
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
