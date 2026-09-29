/*  type.x -- x2c semantic types

    Copyright (c) 2025 Gary William Flake

    Represents semantic types as `List`s, with operations for inspection,
    canonicalization, classification, and `Var` conversion. Scalar
    normalization produces primitive C spellings; semantic runtime typedefs
    keep their declared identity.
*/

#pragma once
#include "ast.x"
#include "meta.x"

/** Represents a semantic type as a canonical `List` of declarator modifiers
    followed by its base type. `NULL` denotes no type, and nonempty values have
    the canonical `List`-pool lifetime.
*/
typedef List Type;

#pragma private
$(import "../src/ast-rewrite.xmacro")
$(import "../lib/native-scalar-types.xmacro")
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>

// views

/** Returns the `List` payload of `x` as a `Type`, or `NULL` for another tag.
*/
inline Type Var.type(Var x) => x is <list> ? (Type) x.pointer() : (Type) NULL;

/** Views `x` as its underlying `List` without validating its type shape. */
inline List Type.list(Type x) => (List) x;

/** Views `x` as a `Type` without validating its type shape. */
inline Type List.type(List x) => (void *) x;

/* types from declarations

   `_from_ast` converts any node inside a declaration AST. `context` is the
   base Type that a declarator's modifiers apply to. */

/** Returns the semantic `Type` represented by a complete `(declare ...)` AST.
    A declaration with one binding is unwrapped to that binding's `Type`;
    multiple bindings return their `Type`s in source order.
*/
Type List.type_from_ast(List ast) {
  List type = _from_ast(ast, NULL);
  match (type) case %((*)): return type.car();
  return type;
}

/* Each declaration form has its own step; any other node is a modifier
   chain or converts its children. A nested declaration, such as a struct
   field that is a pointer, converts the same way. */
static List _from_ast(List ast, List context) {
  if (!ast) return ast;
  // Initializers do not contribute to the declared Type.
  match (ast)
    case %(op = (!set ?binding (bind *)) ?):
      return _from_ast(binding, context);
  Var head = ast.car();
  switch (head.symbol()) {
    case <declare>:  return _from_declare(ast);
    case <bind>:     return _from_bind(ast, context);
    case <params>:
    case <bindings>: return _from_items(ast.cdr(), context);
    case <fields>:   return _from_fields(ast, context);
    case <typedef>:  return _from_typedef(ast);
    case <fnmod>:    return _from_fnmod(ast);
    case <param>:    return _from_param(ast);
    // Binding identity is AST metadata; semantic Types retain the spelling.
    case <binding>:  return %(${ast.caddr()});
    case <struct>:
    case <union>:    return _from_aggregate(ast, head);
    case <expr>:     return _from_expr(ast, context);
  }
  return _from_modifiers(ast, context);
}

/* A modifier chain in source order: pointer marks, qualifiers, storage
   classes, `inline`, and nested pointer, array, function, and bitfield
   declarators, then the Type they modify. A node that starts with no
   modifier converts its children. */
static List _from_modifiers(List ast, List context) {
  Array modifiers = NULL;
  List rest = ast;
  while (rest) {
    Var modifier = rest.car();
    if (modifier is <symbol>) {
      if (!_modifier_symbol(modifier)) break;
    }
    else if (modifier is <list>) {
      if (!_nested_declarator(modifier)) break;
      modifier = _from_ast(modifier, context);
    }
    else break;
    if (!modifiers) modifiers = [];
    modifiers.push(modifier);
    rest = rest.cdr();
  }
  if (modifiers) return modifiers.list_free().append(_from_ast(rest, context));
  return _from_items(ast, context);
}

static int _modifier_symbol(Symbol prefix) =>
  prefix == <*> || prefix == <&> || prefix == <opt-ref> || prefix == <^> ||
  prefix.is_type_qualifier() || prefix.is_storage_class() ||
  prefix.is_inline();

static int _nested_declarator(Type nested) =>
  nested.is_pointer() || nested.is_array() || nested.is_function() ||
  nested.is_bitfield();

/* Converts each List child of `items`; a node with no changed child returns
   itself. */
static List _from_items(List items, List context) {
  List child;
  $ast.rewrite_children(items, child, _from_ast(child, context));
}

// declaration forms

static List _from_declare(List ast) {
  (List source_type, List bindings) = ast.cdr();
  List type = _from_ast(_without_leading_text(source_type), NULL);
  return _from_ast(bindings, type);
}

/* (bind ?ident ?mods): a declarator modifier is never a named type, so all
   of its source attribute text, `("__attribute__((unused))")`, drops. */
static List _from_bind(List ast, List context) {
  Array typed = [];
  foreach (Var item, ast.caddr()) if (!_is_source_text(item)) typed.push(item);
  List mods = _from_ast(typed.list_free(), context);
  return context.type()._modify(mods);
}

/* A static assertion among the fields, under any origin wrappers, declares
   no field. */
static List _from_fields(List ast, List context) {
  Array types = [];
  foreach (List field, ast.cdr()) {
    List declaration = field;
    while (declaration.car() == <at>) declaration = declaration.caddr();
    if (declaration.car() != <c-assert>) types.push(_from_ast(field, context));
  }
  return types.list_free();
}

static List _from_typedef(List ast) {
  (List source_type, List bindings) = ast.cdr();
  List type = _from_ast(source_type, NULL);
  return _from_ast(bindings, type);
}

static List _from_fnmod(List ast) {
  List params = _from_ast(ast.cdr(), NULL);
  return %( func @params );
}

static List _from_param(List ast) {
  (Type parameter_type, List mods) = ast.cdr();
  return _from_ast(mods, parameter_type);
}

/* (struct tag) stays as written, (struct (fields)) converts its fields, and
   (struct tag (fields)) drops its body; a union converts the same way. */
static List _from_aggregate(List ast, Var head) {
  if (ast.type().is_aggregate_tag()) return ast;
  if (ast.type()._is_aggregate_body()) {
    List fields = _from_ast(ast.cadr(), NULL).flatten();
    return %( $head $fields );
  }
  return %( $head ${ast.cadr()} );
}

/* An integer literal, such as an array bound, keeps only its spelling; any
   other expression converts its children. */
static List _from_expr(List ast, List context) {
  match (ast) case %(expr (int) (literal ? ?value)): return %($value);
  return _from_items(ast, context);
}

/* Source specifier text, `("_Noreturn")` or `("__attribute__((unused))")`,
   is written before a declaration's type and is no part of it. A named type
   is spelled the same way and is the type's last item, so only an item
   before it is text. */
static List _without_leading_text(List items) {
  List rest = items;
  while (rest.cdr() && !_is_source_text(rest.car())) rest = rest.cdr();
  if (!rest.cdr()) return items;
  Array typed = [];
  size_t index = 0, last = items.len() - 1;
  foreach (Var item, items)
    if (index++ == last || !_is_source_text(item)) typed.push(item);
  return typed.list_free();
}

static int _is_source_text(Var item) =>
  item is <list> && car(item) is <string>;

static Type Type._modify(Type type, List mods) => %( @mods @type );

/* declarations from types

   Synthesized compiler declarations go through here so pointer, array,
   qualifier, and function-pointer precedence matches parsed source. */

/** Returns `(base modifiers)` for reconstructing a declaration of `type`,
    through `type_declaration_parts` in `lib/meta.x`, which a project's
    helper shares. */
List Type.declaration_parts(Type type) => type_declaration_parts(type);

/** Returns a complete `(declare ...)` AST for `type` and `binding`.
    A `NULL` binding produces an abstract declaration.
*/
List Type.declaration_ast(Type type, List binding) {
  List (base, mods) = type.declaration_parts();
  return %(declare $base (bindings (bind $binding $mods)));
}

/** Returns a complete `(param ...)` AST for `type` and `binding`.
    A `NULL` binding produces an unnamed parameter.
*/
List Type.parameter_ast(Type type, List binding) {
  List (base, mods) = type.declaration_parts();
  return %(param $base (bind $binding $mods));
}

/** Returns `declarator` with the outermost `volatile` removed from each of
    its parameters. C ignores a parameter's top-level qualifier when it
    compares a prototype with its definition, and the qualifier the error
    transfer requires belongs to the definition that writes the parameter,
    not to the declaration its callers read.
*/
List ast_prototype_declarator(List declarator) {
  Array modifiers = [], int changed = 0;
  foreach (Var modifier, declarator.caddr()) {
    match (modifier)
      case %(fnmod (params *parameters)):
        modifier = _prototype_params(parameters, changed);
    modifiers.push(modifier);
  }
  if (!changed) {
    modifiers.free();
    return declarator;
  }
  return %(bind ${declarator.cadr()} ${modifiers.list_free()});
}

/* The function modifier for `parameters`, each without its outermost
   `volatile`; `changed` becomes 1 when one had it. */
static List _prototype_params(List parameters, int &changed) {
  Array rebuilt = [];
  foreach (List parameter, parameters) {
    match (parameter)
      case %(param ?type (bind ?name (volatile *rest))): {
        parameter = %(param $type (bind $name (@rest)));
        changed = 1;
      }
    rebuilt.push(parameter);
  }
  return %(fnmod (params @{rebuilt.list_free()}));
}

// specifier symbols

static const SymbolSet storage_classes =
  %<<typedef static auto extern register threaded>>;
static const SymbolSet type_qualifiers = %<<const restrict volatile>>;
static const SymbolSet type_modifiers = %<<long short signed unsigned>>;
static const SymbolSet number_types =
  %<<double float char short int long signed unsigned enum>>;
static const SymbolSet tagged_types = %<<struct union enum>>;

/** Returns whether `sym` is a storage-class specifier. */
int Symbol.is_storage_class(Symbol sym) => sym in storage_classes;

/** Returns whether `sym` is the `inline` function specifier. */
int Symbol.is_inline(Symbol sym) => sym == <inline>;

/** Returns whether `sym` is `const`, `restrict`, or `volatile`. */
int Symbol.is_type_qualifier(Symbol sym) => sym in type_qualifiers;

/** Returns whether `sym` modifies the width or signedness of a scalar. */
int Symbol.is_type_modifier(Symbol sym) => sym in type_modifiers;

static int Symbol._is_number_type(Symbol sym) => sym in number_types;

static int Symbol._is_tagged(Symbol sym) => sym in tagged_types;

/** Returns whether `sym` can begin a builtin C type specifier. */
int Symbol.is_builtin_type(Symbol sym) =>
  sym._is_number_type() || sym._is_tagged() || sym == <void>;

// aggregates and enums

/** Returns whether `type` is any struct or union shape. */
int Type.is_aggregate(Type type) => !!type.match(%((!or struct union) *));

/** Returns whether `t` is a body-free struct or union tag reference. */
int Type.is_aggregate_tag(Type t) =>
  !!t.match(%((!or struct union) (!or (!not (*)) (gensym ? ?) (binding ? ?))));

static int Type._is_aggregate_body(Type type) =>
  !!type.match(%((!or struct union) (*)));

/** Returns whether `type` is a tagged struct or union definition. */
int Type.is_aggregate_tag_body(Type type) =>
  !!type.match(%((!or struct union) ? (*)));

/** Returns whether `type` is any enum shape. */
int Type.is_enum(Type type) => !!type.match(%(enum *));

/** Returns whether `type` is a body-free enum tag reference. */
int Type.is_enum_tag(Type type) =>
  !!type.match(%(enum (!or (!not (*)) (gensym ? ?))));

static int Type._is_enum_body(Type type) => !!type.match(%(enum (*)));

/** Returns whether `type` is a tagged enum definition. */
int Type.is_enum_tag_body(Type type) => !!type.match(%(enum ? (*)));

/** Returns the one-element tag `List` of an enum, struct, or union `Type`.
    For a compiler-generated anonymous tag, that element is a gensym node. A
    shape with no tag slot returns `NULL`.
*/
List Type.tag(Type type) {
  if (type.is_enum_tag() || type.is_enum_tag_body() ||
      type.is_aggregate_tag() || type.is_aggregate_tag_body())
    return %( ${type.cadr()} );
  return NULL;
}

/** Returns the stored body portion of an enum, struct, or union `Type`.
    Tag references and `Type`s without a stored body return `NULL`.
*/
List Type.body(Type t) {
  if (t._is_enum_body() || t._is_aggregate_body()) return cdr(t);
  if (t.is_enum_tag_body() || t.is_aggregate_tag_body()) return t.cddr();
  return NULL;
}

// declarators

/** Returns whether `t` begins with a pointer-like modifier. */
int Type.is_pointer(Type t) => !!t.match(%((!or (!quote *) & opt-ref ^) *));

/** Returns whether the outer declarator represented by `type` is an array. */
int Type.is_array(Type type) => _declarator_kind(type) == <dim>;

/** Returns whether the outer declarator is a function or inline function. */
int Type.is_function(Type type) {
  Symbol kind = _declarator_kind(type);
  return kind == <func> || kind == <inline>;
}

/** Returns whether the outer declarator represented by `type` is a
    bitfield.
*/
int Type.is_bitfield(Type type) => _declarator_kind(type) == <bitfield>;

static Symbol _declarator_kind(Type type) {
  while (type && type.car() is <list>) type = type.car();
  return type && type.car() is <symbol> ? type.car() : 0;
}

/** Removes one outer pointer-like or array modifier, or returns `NULL`. */
Type Type.dereference(Type type) {
  _qualifiers(type);
  if (type.is_pointer() || type.is_array()) return cdr(type);
  return NULL;
}

/** Returns the pointer `Type` formed by prefixing `type` with `*`. */
Type Type.reference(Type type) => %(* @type);

/** Returns the result `Type` of a function `Type`, following pointer and array
    modifiers, or `NULL` when the chain does not end at a function.
*/
Type Type.apply(Type type) {
  if (!type) return NULL;
  if (type.is_pointer()) return cdr(type).type().apply();
  Symbol kind = _declarator_kind(type);
  if (kind == <dim>) return cdr(type).type().apply();
  if (kind == <func> || kind == <inline>) return cdr(type);
  return NULL;
}

// storage classes

/** Returns whether `type` carries the `static` storage class. */
int Type.is_static(Type type) => !!type.match(%(* static *));

/** Returns whether `type` carries the `inline` function specifier. */
int Type.is_inline(Type type) => !!type.match(%(* inline *));

/** Returns whether `type` carries the `extern` storage class. */
int Type.is_extern(Type type) => !!type.match(%(* extern *));

/** Returns whether `type` carries the `threaded` storage class. */
int Type.is_threaded(Type type) => !!type.match(%(* threaded *));

/** Returns whether `type` begins with the `typedef` storage class. */
int Type.is_typedef(Type type) => type && type.car() == <typedef>;

// canonical forms

/** Returns the suffix of `type` beginning at its builtin or typedef base.
    The result shares the original `List` and is `NULL` when no base is
    present.
*/
Type Type.base_type(Type type) => type_base_suffix(type);

/** Removes non-typedef storage classes, `inline`, and type qualifiers from
    `type`.
*/
Type Type.canonicalize(Type type) => _canonical(type, 0);

/** Returns the stored declaration `Type` after removing non-typedef storage
    classes and `inline`. Those specifiers describe declaration placement;
    `const`, `restrict`, and `volatile` describe the stored value and remain.
*/
Type Type.declared(Type type) => _canonical(type, 1);

/* A type that omits nothing returns itself without a copy. */
static Type _canonical(Type type, int keep_qualifiers) {
  List rest = type;
  while (rest && _kept(rest.car(), keep_qualifiers)) rest = rest.cdr();
  if (!rest) return type;
  Array out = [];
  foreach (Var item, type) if (_kept(item, keep_qualifiers)) out.push(item);
  return out.list_free();
}

static int _kept(Var item, int keep_qualifiers) =>
  item is not <symbol> || !_omit_specifier(item, keep_qualifiers);

static int _omit_specifier(Symbol first, int keep_qualifiers) =>
  (first.is_storage_class() ||
   (!keep_qualifiers && first.is_type_qualifier()) || first.is_inline()) &&
  first != <typedef>;

/** Returns whether handing a `source` value to a `target` declaration would
    silently drop a qualifier the target does not keep. The leading
    qualifiers of each type describe the copied value, not what it points
    at, so only the deeper levels are compared. Callers use this where the
    two types are otherwise the same; a conversion through a converter
    function copies instead of aliasing.
*/
int Type.discards_qualifiers(Type source, Type target) {
  _qualifiers(source);
  _qualifiers(target);
  while (source && target) {
    source = source.cdr();
    target = target.cdr();
    unsigned wanted = _qualifiers(source), offered = _qualifiers(target);
    if (wanted & ~offered) return 1;
  }
  return 0;
}

/* Consume the qualifiers at the front of one type and report them as a set.
   The cursor advances past them so a caller can walk a pointer chain one
   level at a time. */
static unsigned _qualifiers(Type &cursor) {
  unsigned found = 0;
  Type type = cursor;
  while (type && type.car() is <symbol>) {
    Symbol head = type.car();
    if (!head.is_type_qualifier()) break;
    switch (head) {
      case <const>:    found |= 1; break;
      case <volatile>: found |= 2; break;
      case <restrict>: found |= 4; break;
    }
    type = type.cdr();
  }
  cursor = type;
  return found;
}

// classification

/** Returns whether `type` is a builtin scalar, struct, union, or enum. */
int Type.is_builtin(Type type) => !!type.scalar() || type._is_tagged();

static int Type._is_tagged(Type type) {
  if (!type) return 0;
  Var first = type.car();
  if (first is <symbol>) return Symbol._is_tagged(first);
  return 0;
}

/** Returns whether the base of `type` is exactly one typedef-name `String`. */
int Type.is_typedef_name(Type type) {
  type = type.base_type();
  return type && type.len() == 1 && type.car() is <string>;
}

/** Returns whether `type` is one bare typedef-name `String`.
    Unlike `is_typedef_name`, this rejects pointer and array wrappers.
*/
int Type.is_bare_typedef_name(Type type) =>
  !!type.match(%(?)) && type.car() is <string>;

/** Returns whether `type` is a fixed numeric scalar or an enum. */
int Type.is_number(Type type) => !!type.scalar_tag() || type.is_enum();

/** Returns whether `type` is a fixed integral scalar or an enum. */
int Type.is_integral(Type type) {
  if (type.is_enum()) return 1;
  X2CVarNumericInfo info;
  return Var.numeric_info(type.scalar_tag(), info) && !info.floating;
}

// scalars

/* The count of each scalar specifier in one type. `sign` is -1 after
   `signed` and 1 after `unsigned`, and `signs` counts both. */
typedef struct Specifiers {
  int sign, signs, shorts, longs, ints, chars, floats, doubles, voids, count;
} Specifiers;

/** Returns the normalized builtin scalar spelling, or `NULL` when `t` is not
    one valid scalar combination. Storage classes and qualifiers do not
    affect the result.
*/
Type Type.scalar(Type t) {
  Specifiers s = { 0 };
  foreach (Var item, t) if (item is not <symbol> || !s.add(item)) return NULL;
  return s.spelling();
}

/* Counts one specifier; storage classes, qualifiers, and `inline` count as
   nothing. Any other symbol means the type is no scalar. */
static int Specifiers.add(Specifiers *s, Symbol symbol) {
  if (_omit_specifier(symbol, 0)) return 1;
  s.count++;
  switch (symbol) {
    case <signed>:   s.sign = -1; s.signs++; break;
    case <unsigned>: s.sign = 1;  s.signs++; break;
    case <short>:    s.shorts++;  break;
    case <long>:     s.longs++;   break;
    case <int>:      s.ints++;    break;
    case <char>:     s.chars++;   break;
    case <float>:    s.floats++;  break;
    case <double>:   s.doubles++; break;
    case <void>:     s.voids++;   break;
    default: return 0;
  }
  return 1;
}

/* The one spelling C gives a valid combination of counts, or `NULL`. */
static Type Specifiers.spelling(Specifiers *s) {
  if (!s.count || s.signs > 1 || s.shorts > 1 || s.longs > 2 || s.ints > 1 ||
      s.chars > 1 || s.floats > 1 || s.doubles > 1 || s.voids > 1)
    return NULL;
  if (s.voids) return s.count == 1 ? %(void) : NULL;
  if (s.floats) return s.count == 1 ? %(float) : NULL;
  if (s.doubles) {
    if (s.longs <= 1 && s.count == s.doubles + s.longs)
      return s.longs ? %(long double) : %(double);
    return NULL;
  }
  if (s.chars) {
    if (s.shorts || s.longs || s.ints || s.count != s.chars + s.signs)
      return NULL;
    if (s.sign > 0) return %(unsigned char);
    if (s.sign < 0) return %(signed char);
    return %(char);
  }
  if (s.shorts && s.longs) return NULL;
  if (s.count != s.signs + s.shorts + s.longs + s.ints) return NULL;
  if (s.shorts) return s.sign > 0 ? %(unsigned short) : %(short);
  if (s.longs == 1) return s.sign > 0 ? %(unsigned long) : %(long);
  if (s.longs == 2) return s.sign > 0 ? %(unsigned long long) : %(long long);
  return s.sign > 0 ? %(unsigned) : %(int);
}

/* Process-lifetime scalar table. Its keys are the spellings Type.scalar
   produces, so the lookup needs no separate discriminator; each row carries
   the Var tag, the reader that follows Var.convert, and the helper that
   performs an atomic native update, plus the Func signature spelling. */
static Map scalartypes = $native_scalar_types();

static List _scalar_row(Type type) {
  Type scalar = type.scalar();
  if (!scalar) return NULL;
  Var row = scalartypes[scalar];
  return row is <list> ? row : NULL;
}

static int _scalar_numeric_info(Type type, X2CVarNumericInfo &info) {
  Var row = scalartypes[type];
  return row is <list> && Var.numeric_info(row.list().car(), info);
}

/** Returns the fixed `Var` numeric tag for `type`, or zero when none exists.
*/
Symbol Type.scalar_tag(Type type) {
  List row = _scalar_row(type);
  return row ? row.car() : (Symbol) 0;
}

/** Returns the numeric `Var` reader for `type`, or `NULL` when unsupported.
    Enums use `Var_int` after conversion to their shared integer tag.
*/
String Type.var_numeric_extractor(Type type) {
  if (type.is_enum()) return "Var_int";
  List row = _scalar_row(type);
  return row ? row.cadr() : NULL;
}

/** Returns the native numeric update helper for `type`, or `NULL` when the
    scalar has no registered update helper.
*/
String Type.var_numeric_update_helper(Type type) {
  List row = _scalar_row(type);
  return row ? row.caddr() : NULL;
}

// arithmetic conversions

/** Applies integer promotion to `type`.
    Enums and narrow integers become `int`; other scalars retain their
    canonical spelling, and a non-scalar returns `NULL`.
*/
Type Type.promote(Type type) {
  if (type.is_enum()) return %(int);
  type = type.scalar();
  if (!type) return NULL;
  X2CVarNumericInfo info;
  if (_scalar_numeric_info(type, info) && !info.floating && info.rank < 3)
    return %(int);
  return type;
}

/** Returns the usual arithmetic result `Type` for two scalar operands.
    A missing or non-scalar operand produces `NULL`.
*/
Type Type.widest(Type a, Type b) {
  if (!a || !b) return NULL;
  a = a.promote();
  b = b.promote();
  if (!a || !b) return NULL;
  X2CVarNumericInfo ai = { 0 }, bi = { 0 };
  _scalar_numeric_info(a, ai);
  _scalar_numeric_info(b, bi);
  if (ai.floating || bi.floating) return ai.rank >= bi.rank ? a : b;
  int ua = ai.unsigned_value, ub = bi.unsigned_value;
  int ra = ai.rank, rb = bi.rank;
  if (ua == ub) return ra >= rb ? a : b;
  if (ua && ra >= rb) return a;
  if (ub && rb >= ra) return b;
  Type signed_type = ua ? b : a;
  int signed_bits = ua ? bi.bits : ai.bits;
  int unsigned_bits = ua ? ai.bits : bi.bits;
  if (signed_bits > unsigned_bits) return signed_type;
  return _unsigned_scalar(signed_type);
}

static Type _unsigned_scalar(Type type) {
  switch (type.scalar_tag()) {
    case <i8>:    return %(unsigned char);
    case <i16>:   return %(unsigned short);
    case <i32>:   return %(unsigned);
    case <long>:  return %(unsigned long);
    case <llong>: return %(unsigned long long);
  }
  return type;
}

// numeric literals

/** Returns the native type selected by a validated numeric token.
    `floating` selects floating suffix rules; an integer outside all supported
    native families returns `NULL`.
*/
Type Type.numeric_literal(String text, int floating) {
  int length = text.len();
  if (floating) {
    int last = text[length - 1];
    if (last == 'f' || last == 'F') return %(float);
    if (last == 'l' || last == 'L') return %(long double);
    return %(double);
  }
  int suffix = _integer_literal_end(text);
  int is_unsigned = 0, longs = 0;
  for (int i = suffix; i < length; i++) {
    int ch = text[i];
    if (ch == 'u' || ch == 'U') is_unsigned = 1;
    else longs++;
  }
  unsigned long long value;
  int decimal;
  if (!_literal_magnitude(text, suffix, value, decimal)) return NULL;
  return _integer_literal_type(value, decimal, is_unsigned, longs);
}

/** Reads a validated numeric literal at its semantic type's precision.
    Returns `void` when its magnitude exceeds the integer representation.
*/
Var Type.numeric_literal_value(Type type, String text) {
  Symbol tag = type.scalar_tag();
  if (tag == <f32>) { float value = strtof(text, NULL); return value; }
  if (tag == <f64>) { double value = strtod(text, NULL); return value; }
  if (tag == <ldouble>) {
    long double value = strtold(text, NULL);
    return value;
  }
  int negative = text[0] == '-';
  if (negative || text[0] == '+') text = text[1:];
  int end = _integer_literal_end(text);
  unsigned long long magnitude;
  int decimal;
  if (!_literal_magnitude(text, end, magnitude, decimal)) return void;
  Var value = negative ? 0ULL - magnitude : magnitude;
  return value.convert(tag);
}

static int _integer_literal_end(String text) {
  int end = text.len();
  while (end > 0) {
    int ch = text[end - 1];
    if (ch != 'u' && ch != 'U' && ch != 'l' && ch != 'L') break;
    end--;
  }
  return end;
}

/* Reads a validated integer token's unsigned magnitude. `decimal` is 1 when
   the token has no radix prefix and no octal leading zero. */
static int _literal_magnitude(
  String text, int end, unsigned long long &value, int &decimal) {
  int pos = 0, base = _radix(text, end, pos);
  decimal = base == 10;
  unsigned long long result = 0;
  for (; pos < end; pos++) {
    unsigned digit = _literal_digit((unsigned char) text[pos]);
    if (result > (ULLONG_MAX - digit) / (unsigned) base) return 0;
    result = result * (unsigned) base + digit;
  }
  value = result;
  return 1;
}

/* The radix of an integer token, with `pos` advanced past a `0x`, `0b`, or
   `0o` prefix. A leading zero before an octal digit selects radix 8. */
static int _radix(String text, int end, int &pos) {
  if (end < 2 || text[0] != '0') return 10;
  switch (text[1]) {
    case 'x': case 'X': pos = 2; return 16;
    case 'b': case 'B': pos = 2; return 2;
    case 'o': case 'O': pos = 2; return 8;
  }
  return text[1] >= '0' && text[1] <= '7' ? 8 : 10;
}

static unsigned _literal_digit(int ch) =>
  ch <= '9' ? (unsigned) (ch - '0') : (unsigned) ((ch | 32) - 'a' + 10);

/* C gives an integer literal the first type of its suffix's list that holds
   the value; a decimal literal without `u` skips the unsigned types. */
static Type _integer_literal_type(
  unsigned long long value, int decimal, int is_unsigned, int longs) {
  if (!is_unsigned && !longs) {
    if (value <= INT_MAX) return %(int);
    if (!decimal && value <= UINT_MAX) return %(unsigned);
    if (value <= LONG_MAX) return %(long);
    if (!decimal && value <= ULONG_MAX) return %(unsigned long);
    if (value <= LLONG_MAX) return %(long long);
    if (!decimal) return %(unsigned long long);
    return NULL;
  }
  if (is_unsigned && !longs) {
    if (value <= UINT_MAX) return %(unsigned);
    if (value <= ULONG_MAX) return %(unsigned long);
    return %(unsigned long long);
  }
  if (!is_unsigned && longs == 1) {
    if (value <= LONG_MAX) return %(long);
    if (!decimal && value <= ULONG_MAX) return %(unsigned long);
    if (value <= LLONG_MAX) return %(long long);
    if (!decimal) return %(unsigned long long);
    return NULL;
  }
  if (is_unsigned && longs == 1)
    return value <= ULONG_MAX ? %(unsigned long) : %(unsigned long long);
  if (!is_unsigned && longs == 2) {
    if (value <= LLONG_MAX) return %(long long);
    return decimal ? NULL : %(unsigned long long);
  }
  return %(unsigned long long);
}

// designated names

/** Returns the name whose address an expression takes, or `NULL`. */
String ast_addressed_identifier(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case %(expr ? ?inner): return ast_addressed_identifier(inner);
    case %(parens ?inner): return ast_addressed_identifier(inner);
    case %(op & ?inner):   return ast_direct_identifier(inner);
  }
  return NULL;
}

/** Returns the name an expression designates directly, following the forms
    that still name the same object - parentheses, a member, an array index,
    a dereference - or `NULL` when the expression designates no single name.
    A declaration qualifier that must reach one object, such as the `volatile`
    an error transfer requires, applies to this name.
*/
String ast_direct_identifier(Var value) {
  Var designated = _designated(value);
  if (designated is not <list>) return NULL;
  List ast = designated;
  match (ast) {
    case %(ident ?binding): return binding_identity_spelling(binding);
    case %(op (!quote ->) ?base *): return ast_addressed_identifier(base);
    case %(op (!quote *) ?base): return ast_addressed_identifier(base);
  }
  return NULL;
}

/** Returns the name of the pointer an expression designates through, or
    `NULL` when it designates no object through a single name. `*pointer`,
    `pointer[index]`, and `pointer->member` all change the object the pointer
    holds, which `ast_direct_identifier` reports as no name at all.
*/
String ast_indirect_identifier(Var value) {
  Var designated = _designated(value);
  if (designated is not <list>) return NULL;
  List ast = designated;
  match (ast) {
    case %(index (!set ?base (expr ? ?)) ?):
      return ast_direct_identifier(base);
    case %(op (!quote ->) ?base *): return ast_direct_identifier(base);
    case %(op (!quote *) ?base): return ast_direct_identifier(base);
  }
  return NULL;
}

/* The innermost node an expression designates, past the forms that still
   name the same object: parentheses, a member, and an index into an array.
   What remains is a name, a designation through a pointer, or neither. */
static Var _designated(Var value) {
  while (value is <list>) {
    List ast = value;
    Var inner = _same_object(ast);
    if (inner is void) return ast;
    value = inner;
  }
  return NULL;
}

/* One step inward through an `expr` wrapper, parentheses, a member, or an
   array index; `void` when `ast` is none of them. */
static Var _same_object(List ast) {
  match (ast) {
    case %(!or (expr ? ?inner) (parens ?inner)): return inner;
    case %(index (!set ?base (expr ?base_type ?)) ?): {
      Type type = base_type;
      if (type.is_array()) return base;
    }
    case %(op . ?base *): return base;
  }
  return void;
}

// var tags

/* Only the leaf unit `src/type-ledger.x` imports the Var tag ledger, so it
   defines these two tables' accessors and includes this unit. */
Map Type.builtin_var_tags(void);
Map Type.var_tag_rows(void);

/* Source-declared rows are rebuilt for each translation unit because their
   canonical Type keys and converter names may belong to that unit's pools;
   end_unit drops the table before those pools are released. */
static Map declared_typetags = NULL;

/** Returns the unit-local `Var` tag for `type`, falling back to its fixed
    tag.
*/
Symbol Type.var_tag(Type type) {
  if (!type) return 0;
  if (declared_typetags != NULL) {
    Var row = declared_typetags[type.canonicalize()];
    if (row is not void) return row.list().car();
  }
  return type.fixed_var_tag();
}

/** Returns the process-lifetime `Var` tag fixed for `type`, or zero. */
Symbol Type.fixed_var_tag(Type type) {
  if (!type) return 0;
  Symbol scalar = type.scalar_tag();
  if (scalar) return scalar;
  Var vtag = Type.builtin_var_tags()[type.canonicalize()];
  return vtag is <symbol> ? vtag : 0;
}

/** Returns the unit-local forward `Var` converter for the canonical form of
    `type`, or `NULL`.
*/
String Type.var_converter(Type type) {
  if (declared_typetags == NULL || !type) return NULL;
  Var row = declared_typetags[type.canonicalize()];
  if (row is void) return NULL;
  return row.list().cadr();
}

/** Reads the encoding row of `tag` into `top`, `mask`, and `bottom` and
    reports whether one exists. A tag whose decoded form carries a validity
    clause, an immediate width, or a user registration has no constant row.
*/
int Type.var_tag_row(
  Symbol tag, unsigned long &top, unsigned long &mask, unsigned long &bottom) {
  Var row = Type.var_tag_rows()[tag];
  if (row is void) return 0;
  List fields = row;
  top = fields.car();
  mask = fields.cadr();
  bottom = fields.caddr();
  return 1;
}

/** Registers one named type's unit-local `Var` tag and exact forward
    converter. The first row for a canonical `Type` wins. A `NULL` type,
    name, or converter, or no active unit, leaves the table unchanged.
*/
void Type.register_var_tag(Type t, String name, String converter) {
  if (declared_typetags == NULL || !t || !name || !converter) return;
  Type key = t.canonicalize();
  Var row = declared_typetags[key];
  if (row is void)
    declared_typetags[key] = %( ${name.lower().symbol()} $converter );
}

/** Replaces a registered type's inferred `Var` tag with `tag`, or with the
    fixed tag of `representation` when `tag` is zero. Missing rows and
    untagged representations leave the table unchanged.
*/
void Type.register_var_adoption(Type type, Type representation, Symbol tag) {
  if (declared_typetags == NULL || !type) return;
  Type key = type.canonicalize();
  Var row = declared_typetags[key];
  if (!tag && representation) tag = representation.fixed_var_tag();
  if (row is void || !tag) return;
  declared_typetags[key] = %($tag ${row.list().cadr()});
}

/** Starts an empty set of source-declared `Var` rows for one translation
    unit.
*/
void Type.begin_unit(void) {
  declared_typetags = {};
}

/** Ends the source-declared `Var`-row lifetime before the unit `Scope` is
    released.
*/
void Type.end_unit(void) {
  declared_typetags = NULL;
}
