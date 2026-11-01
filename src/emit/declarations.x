/*  declarations.x -- C declarations, declarators and native types */

// native aliases

static macro Expression $emit.alias.definition(Expr $target, Expr $native) =>
  %"#define $($target) $($native)";

static macro Expression $emit.alias.checked(
  Expr $native, Expr $pointer, Expr $message, Expr $definition) =>
  $(
    "#ifndef X2CCPP", "_Static_assert(", "_Generic(&", @($native), ", ",
    @($pointer), ": 1, default: 0), ", %"\"$($message)\");", "#endif",
    $definition);

module void _parameters(Emitter &e, Var parameters) {
  _put(e, "(");
  _node(e, parameters);
  _put(e, ")");
}

// declarations

module void _declare(Emitter &e, List type, List bindings) {
  _node(e, type);
  _node(e, bindings);
}

module void _bind(Emitter &e, List ident, List mods) {
  if (!mods) _emit(e, ident);
  else _put_all(e, _declarator(e, _tokens(e, ident), mods));
}

module void _param(Emitter &e, List type, List mods) {
  Type container = Type.rest_container(type);
  _emit(e, container ? container : type);
  _node(e, mods);
}

module void _function(Emitter &e, List type, List bindings, List body) {
  String old_fn = e.fn_name;
  List function_binding = bindings.cadr();
  e.fn_name = Ast.binding_spelling(function_binding);
  Var defer_owner;
  if (e.semantic_binding_facts().try_get(
    %(defer-ownr $function_binding), defer_owner))
    e.fn_name = defer_owner;
  _node(e, type);
  with (e.static_objects = {}) {
    _node(e, bindings);
    _node(e, body);
  }
  e.fn_name = old_fn;
}

// Emit a checked native-function alias without a wrapper object.
module List _foreign_alias(
  Emitter &e, List declaration, List target, List native_binding) {
  Type function_type = declaration.type_from_ast().declared();
  Type pointer_type = function_type.reference();
  List pointer = _semantic_type(e, pointer_type);
  List native = _tokens(e, native_binding);
  String target_name = e.emitted_binding_name(target);
  String native_name = e.emitted_binding_name(native_binding);
  String message = %"native alias $target_name does not match $native_name";
  String define = $emit.alias.definition(target_name, native_name);
  return $emit.alias.checked(native, pointer, message, define);
}

module void _typedef(Emitter &e, List ast) {
  _put(e, "typedef");
  _emit(e, ast.cdr());
  _put(e, ";");
  if (ast ~= %(typedef ? (bindings *declarators)))
    foreach (List declarator in declarators) {
      List binding = declarator.cadr();
      Var type;
      if (e.semantic_binding_facts().try_get(%(ntype $binding), type))
        e.native_aliases = cons($(type, binding), e.native_aliases);
    }
}

module void _block(Emitter &e, List ast) {
  with (e.native_aliases = e.native_aliases) {
    _put(e, "{");
    _emit(e, ast.cdr());
    _put(e, "}");
  }
}

module void _binding(Emitter &e, List ast) {
  _put(e, e.emitted_binding_name(ast));
}

// declarators

module List _semantic_type(Emitter &e, Type type) {
  List (_, base, bindings) = type.declaration_ast(NULL);
  return _tokens(e, $(base, bindings));
}

module List _semantic_name(Emitter &e, Type type, String name) {
  List (base, mods) = type.parts();
  List declarator = _declarator(e, $(name), mods);
  return $(_tokens(e, base), @declarator);
}

/* Fold one layer at a time; typedef prefixes surround the final result. */
static List _declarator(Emitter &e, List decl, List mods) {
  int typedefs = 0;
  while (mods) {
    Var first = mods.car();
    if (first is <list>) {
      decl = _list_declarator(e, decl, first);
      mods = mods.cdr();
      continue;
    }
    Symbol sym = first;
    switch (sym) {
      case <dim>: decl = _array_declarator(e, decl, NULL); break;
      case <&>: case <opt-ref>: decl = cons(<*>, decl); break;
      case <*>: decl = cons(first, decl); break;
      case <typedef>: typedefs++; break;
      case <bitfield>: decl = _bitfield_declarator(e, mods); continue;
      default: decl = _native_declarator(decl, mods, sym); break;
    }
    mods = mods.cdr();
  }
  while (typedefs--) decl = cons(<typedef>, decl);
  return decl;
}

static List _list_declarator(Emitter &e, List decl, Type mod) {
  if (mod.car() == <fnmod>) return _function_declarator(e, decl, mod.cadr());
  if (mod.car() is <string>) return %(@decl @mod);
  if (mod.is_array()) return _array_declarator(e, decl, mod.cadr());
  return %(@decl ":" @(_tokens(e, mod.cadr())));
}

static List _bitfield_declarator(Emitter &e, List &mods) {
  List tokens = _tokens(e, mods.cdr());
  mods = NULL;
  return tokens;
}

static List _native_declarator(List decl, List &mods, Symbol sym) {
  if (sym.is_type_qualifier()) return cons(sym, decl);
  List tokens = %(@mods @decl);
  mods = NULL;
  return tokens;
}

static List _array_declarator(Emitter &e, List decl, List dimension) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  List size = _tokens(e, dimension);
  return size ? %(@decl "[" @size "]") : %(@decl "[]");
}

static List _function_declarator(Emitter &e, List decl, List parameters) {
  if (decl.type().is_pointer()) decl = _parens(decl);
  return %(@decl "(" @(_tokens(e, parameters)) ")");
}

// tagged types

module List _enum(Emitter &e, List ast) {
  if (ast.type().is_enum_tag()) {
    Var alias = e.native_aliases.assoc(ast);
    if (alias is <list>) return _tokens(e, alias);
  }
  List name = ast.type().tag(), body = ast.type().body().car();
  if (_is_gensym_tag(name) && !ast.type().is_enum_tag()) name = NULL;
  if (name) name = _tokens(e, name);
  body = _commas(_grouped(e, body));
  return _tagged(ast, name, body);
}

module List _aggregate(Emitter &e, List ast) {
  if (ast.type().is_aggregate_tag()) {
    Var alias = e.native_aliases.assoc(ast);
    if (alias is <list>) return _tokens(e, alias);
  }
  List tag = ast.type().tag();
  if (_is_gensym_tag(tag) && !ast.type().is_aggregate_tag()) tag = NULL;
  if (tag) tag = _tokens(e, tag);
  if (ast.type().is_aggregate_tag()) return $(ast.car(), @tag);
  List body = _tokens(e, ast.type().body());
  return _tagged(ast, tag, body);
}

static List _tagged(List ast, List tag, List body) {
  if (tag && body) return %( $(ast.car()) @tag "{" @body "}");
  if (tag) return $(ast.car(), @tag);
  return %( $(ast.car()) "{" @body "}");
}

/* The tag slot of an anonymous aggregate holds the compiler-internal
   gensym key that stands in for the tag the source never wrote. It names
   nothing outside this unit, and two units that reach the same counter
   state mint the same key, so it is never emitted. The tagless definition
   is what the source wrote, and tagless typedefs are compatible across
   translation units (C11 6.2.7). */
static int _is_gensym_tag(List tag) {
  if (tag ~= %((gensym *) *)) return 1;
  return 0;
}
