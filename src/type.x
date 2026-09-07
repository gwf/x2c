/*  type.x -- x2c semantic types

    Copyright (c) 2025 Gary William Flake

    Represents semantic types as `List`s, with operations for inspection,
    canonicalization, classification, and `Var` conversion. Scalar
    normalization produces primitive C spellings; semantic runtime typedefs
    keep their declared identity.
*/

#pragma once
#include "ast.x"
/** Represents a semantic type as a canonical `List` of declarator modifiers
    followed by its base type. `NULL` denotes no type, and nonempty values have
    the canonical `List`-pool lifetime.
*/
typedef List Type;

#pragma private
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>

// Build declaration-shaped AST from a canonical semantic type. Synthesized
// compiler declarations go through here so pointer, array, qualifier, and
// function-pointer precedence matches parsed source.

static Type _declarator_parts(Type type, List *modifiers) {
  Type base = type.base_type();
  if (!base) {
    if (modifiers) *modifiers = NULL;
    return type;
  }
  List reversed = NULL, qualifiers = NULL;
  for (List rest = type; rest != base; rest = rest.cdr())
    reversed = cons(rest.car(), reversed);
  while (reversed && reversed.car() is <symbol> &&
         Symbol.is_type_qualifier(reversed.car())) {
    qualifiers = cons(reversed.car(), qualifiers);
    reversed = reversed.cdr();
  }
  if (modifiers) *modifiers = reversed.reverse();
  return qualifiers.append(base);
}

static List _modifier_declaration_ast(Var value) {
  if (value is not <list>) return %($value);
  List modifier = value;
  if (!modifier || modifier.car() != <func>) return %($modifier);
  List parameters = modifier.cadr().list().map(
    %!(Type parameter) => parameter.parameter_ast(NULL));
  List result = %(fnmod (params @parameters));
  return %($result);
}

/** Returns `(base modifiers)` for reconstructing a declaration of `type`.
    Function modifiers contain parameter AST nodes, and modifier order retains
    C declarator precedence.
*/
List Type.declaration_parts(Type type) {
  List modifiers = NULL;
  Type base = _declarator_parts(type, &modifiers), Array syntax = %[];
  foreach (Var item, modifiers) {
    List converted = _modifier_declaration_ast(item);
    syntax.push(converted.car());
  }
  List result = %($base (@{syntax.list_free()}));
  return result;
}

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

// type conversion utilities

/** Returns the `List` payload of `x` as a `Type`, or `NULL` for another tag.
*/
inline Type Var.type(Var x) => x is <list> ? (Type) x.pointer() : (Type) NULL;

/** Views `x` as its underlying `List` without validating its type shape. */
inline List Type.list(Type x) => (List) x;

/** Views `x` as a `Type` without validating its type shape. */
inline Type List.type(List x) => (void *) x;

// symbol classification predicates

/** Returns whether `sym` is a storage-class specifier. */
int Symbol.is_storage_class(Symbol sym) {
  switch (sym)
    case <typedef>: case <static>: case <auto>: case <extern>: case <register>:
    case <threaded>:
      return 1;
  return 0;
}

/** Returns whether `sym` is the `inline` function specifier. */
int Symbol.is_inline(Symbol sym) => sym == <inline>;

/** Returns whether `sym` is `const`, `restrict`, or `volatile`. */
int Symbol.is_type_qualifier(Symbol sym) {
  switch (sym) case <const>: case <restrict>: case <volatile>: return 1;
  return 0;
}

/** Returns whether `sym` modifies the width or signedness of a scalar. */
int Symbol.is_type_modifier(Symbol sym) {
  switch (sym)
    case <long>: case <short>: case <signed>: case <unsigned>:
      return 1;
  return 0;
}

static int Symbol._is_number_type(Symbol sym) {
  switch (sym)
    case <double>: case <float>: case <char>: case <short>: case <int>:
    case <long>: case <signed>: case <unsigned>: case <enum>:
      return 1;
  return 0;
}

static int Symbol._is_tagged(Symbol sym) {
  switch (sym) case <struct>: case <union>: case <enum>: return 1;
  return 0;
}

/** Returns whether `sym` can begin a builtin C type specifier. */
int Symbol.is_builtin_type(Symbol sym) =>
  sym._is_number_type() || sym._is_tagged() || sym == <void>;

// core type predicates

/** Returns whether `type` is any struct or union shape. */
int Type.is_aggregate(Type type) => !!type.match(%((!or struct union) *));

/** Returns whether `type` is a body-free struct or union tag reference. */
int Type.is_aggregate_tag(Type type) =>
  !!type.match(%((!or struct union) (!or (!not (*)) (gensym ?))));

static int Type._is_aggregate_body(Type type) =>
  !!type.match(%((!or struct union) (*)));

/** Returns whether `type` is a tagged struct or union definition. */
int Type.is_aggregate_tag_body(Type type) =>
  !!type.match(%((!or struct union) ? (*)));

/** Returns whether `type` is any enum shape. */
int Type.is_enum(Type type) => !!type.match(%(enum *));

/** Returns whether `type` is a body-free enum tag reference. */
int Type.is_enum_tag(Type type) =>
  !!type.match(%(enum (!or (!not (*)) (gensym ?))));

static int Type._is_enum_body(Type type) => !!type.match(%(enum (*)));

/** Returns whether `type` is a tagged enum definition. */
int Type.is_enum_tag_body(Type type) => !!type.match(%(enum ? (*)));

/** Returns whether `type` begins with a pointer-like `*`, `&`, or `^`. */
int Type.is_pointer(Type type) => !!type.match(%((!or (!quote *) & ^) *));

static Symbol _declarator_kind(Type type) {
  while (type && type.car() is <list>) type = type.car();
  return type && type.car() is <symbol> ? type.car().symbol() : 0;
}

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

// type accessors and properties

/** Returns the normalized builtin scalar spelling, or `NULL` when `type` is
    not one valid scalar combination. Storage classes and qualifiers do not
    affect the result.
*/
Type Type.scalar(Type type) {
  type = _canonical(type, 0);
  int sign = 0, sign_count = 0, shorts = 0, longs = 0, ints = 0, chars = 0;
  int floats = 0, doubles = 0, voids = 0, count = 0;
  foreach (Var value, type) {
    if (value is not <symbol>) return NULL;
    count++;
    switch (value.symbol()) {
      case <signed>:   sign = -1; sign_count++; break;
      case <unsigned>: sign = 1;  sign_count++; break;
      case <short>:    shorts++;  break;
      case <long>:     longs++;   break;
      case <int>:      ints++;    break;
      case <char>:     chars++;   break;
      case <float>:    floats++;  break;
      case <double>:   doubles++; break;
      case <void>:     voids++;   break;
      default: return NULL;
    }
  }
  if (!count || sign_count > 1 || shorts > 1 || longs > 2 || ints > 1 ||
      chars > 1 || floats > 1 || doubles > 1 || voids > 1)
    return NULL;
  if (voids) return count == 1 ? %(void) : NULL;
  if (floats) return count == 1 ? %(float) : NULL;
  if (doubles) {
    if (doubles == 1 && longs <= 1 && count == doubles + longs)
      return longs ? %(long double) : %(double);
    return NULL;
  }
  if (chars) {
    if (shorts || longs || ints || count != chars + sign_count) return NULL;
    if (sign > 0) return %(unsigned char);
    if (sign < 0) return %(signed char);
    return %(char);
  }
  if (shorts && longs) return NULL;
  if (count != sign_count + shorts + longs + ints) return NULL;
  if (shorts) return sign > 0 ? %(unsigned short) : %(short);
  if (longs == 1) return sign > 0 ? %(unsigned long) : %(long);
  if (longs == 2) return sign > 0 ? %(unsigned long long) : %(long long);
  return sign > 0 ? %(unsigned) : %(int);
}

/* Process-lifetime scalar table. Its keys are the spellings Type.scalar
   produces, so the lookup needs no separate discriminator; each row carries
   the Var tag, the reader that follows Var.convert, and the helper that
   performs an atomic native update. */
static Map scalartypes = NULL;

static Map _scalartypes_table(void) {
  if ((void *) scalartypes != NULL) return scalartypes;
  scalartypes = %{
    (char)               : (i8 "Var_char" "x2c_var_update_i8"),
    (signed char)        : (i8 "Var_char" "x2c_var_update_schar"),
    (unsigned char)      : (u8 "Var_uchar" "x2c_var_update_u8"),
    (short)              : (i16 "Var_short" "x2c_var_update_i16"),
    (unsigned short)     : (u16 "Var_ushort" "x2c_var_update_u16"),
    (int)                : (i32 "Var_int" "x2c_var_update_i32"),
    (unsigned)           : (u32 "Var_uint" "x2c_var_update_u32"),
    (long)               : (long "Var_long" "x2c_var_update_long"),
    (unsigned long)      : (ulong "Var_ulong" "x2c_var_update_ulong"),
    (long long)          : (llong "Var_long_long" "x2c_var_update_long_long"),
    (unsigned long long) : (ullong "Var_ulong_long"
                           "x2c_var_update_ulong_long"),
    (float)              : (f32 "Var_float" "x2c_var_update_f32"),
    (double)             : (f64 "Var_floating" "x2c_var_update_f64"),
    (long double)        : (ldouble "Var_long_double"
                           "x2c_var_update_long_double")
  };
  return scalartypes;
}

static int _scalar_numeric_info(Type type, X2CVarNumericInfo *info) {
  Var row = _scalartypes_table()[type];
  return row is <list> &&
         Var.numeric_info(row.list().car(), info);
}

static List _scalar_row(Type type) {
  Type scalar = type.scalar();
  if (!scalar) return NULL;
  Var row = _scalartypes_table()[scalar];
  return row is <list> ? row.list() : NULL;
}

/** Returns the fixed `Var` numeric tag for `type`, or zero when none exists.
*/
Symbol Type.scalar_tag(Type type) {
  List row = _scalar_row(type);
  return row ? row.car().symbol() : (Symbol) 0;
}

/** Returns the numeric `Var` reader for `type`, or `NULL` when unsupported.
    Enums use `Var_int` after conversion to their shared integer tag.
*/
String Type.var_numeric_extractor(Type type) {
  if (type.is_enum()) return "Var_int";
  List row = _scalar_row(type);
  return row ? row.cadr().str() : NULL;
}

/** Returns the native numeric update helper for `type`, or `NULL` when the
    scalar has no registered update helper.
*/
String Type.var_numeric_update_helper(Type type) {
  List row = _scalar_row(type);
  return row ? row.caddr().str() : NULL;
}

static unsigned _literal_digit(int ch) => ch <= '9' ? (unsigned) (ch - '0')
                   : (unsigned) ((ch | 32) - 'a' + 10);

// Read a validated integer token's unsigned magnitude and radix.
static int _literal_magnitude(
  String text, int end, unsigned long long *value, int *decimal) {
  int pos = 0, base = 10;
  *decimal = 1;
  if (pos + 1 < end && text[pos] == '0') {
    switch (text[pos + 1]) {
      case 'x': case 'X': base = 16; pos += 2; *decimal = 0; break;
      case 'b': case 'B': base = 2;  pos += 2; *decimal = 0; break;
      case 'o': case 'O': base = 8;  pos += 2; *decimal = 0; break;
      default:
        if (text[pos + 1] >= '0' && text[pos + 1] <= '7') {
          base = 8;
          *decimal = 0;
        }
    }
  }
  unsigned long long result = 0;
  while (pos < end) {
    unsigned digit = _literal_digit((unsigned char) text[pos]);
    if (result > (ULLONG_MAX - digit) / (unsigned) base) return 0;
    result = result * (unsigned) base + digit;
    pos++;
  }
  *value = result;
  return 1;
}

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
  int suffix = length;
  while (suffix > 0) {
    int ch = text[suffix - 1];
    if (ch != 'u' && ch != 'U' && ch != 'l' && ch != 'L') break;
    suffix--;
  }
  int is_unsigned = 0, longs = 0;
  for (int i = suffix; i < length; i++) {
    int ch = text[i];
    if (ch == 'u' || ch == 'U') is_unsigned = 1;
    else longs++;
  }
  unsigned long long value;
  int decimal;
  if (!_literal_magnitude(text, suffix, &value, &decimal)) return NULL;
  return _integer_literal_type(value, decimal, is_unsigned, longs);
}

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
List Type.body(Type type) {
  if (type._is_enum_body() || type._is_aggregate_body()) return cdr(type);
  if (type.is_enum_tag_body() || type.is_aggregate_tag_body())
    return type.cddr();
  return NULL;
}

/* Builtin tag rows have process lifetime. Source-declared rows are rebuilt
   for each translation unit because their canonical Type keys and converter
   names may belong to that unit's pools; end_unit drops the table before
   those pools are released. */
static Map typetags = NULL;
static Map declared_typetags = NULL;

static Map _typetags_table(void) {
  if ((void *) typetags != NULL) return typetags;
  typetags = %{
    (* void)           : p48,      (* unsigned char)       : <u8*>,
    (* signed char)    : <i8*>,      (* unsigned short)      : <u16*>,
    (* short)          : <i16*>,     (* unsigned)            : <u32*>,
    (* int)            : <i32*>,     (* float)               : <f32*>,
    (* unsigned long)  : <ulong*>,     (* long)                : <long*>,
    (* double)         : <f64*>,     (* unsigned long long)  : <ullong*>,
    (* long long)      : <llong*>,    (* long double)         : <ldouble*>,
    (* * void)          : <p48*>,     (* * unsigned char)      : <u8**>,
    (* * signed char)   : <i8**>,     (* * unsigned short)     : <u16**>,
    (* * short)         : <i16**>,    (* * unsigned)           : <u32**>,
    (* * int)           : <i32**>,    (* * float)              : <f32**>,
    (* * unsigned long) : <ulong**>,    (* * long)               : <long**>,
    (* * double)        : <f64**>,    (* * unsigned long long) : <ullong**>,
    (* * long long)     : <llong**>,   (* * long double)        : <ldouble**>,
    ("Array")          : array,    ("Block")               : block,
    ("Buffer")         : buffer,   ("Bytes")               : bytes,
    ("Context")        : context,  ("Error")               : error,
    ("File")           : file,     ("Func")                : func,
    ("Iter")           : iter,
    ("Lambda")         : lambda,   ("List")                : list,
    ("Logger")         : logger,   ("Map")                 : map,
    ("Mutex")          : mutex,    ("Pipe")                : pipe,
    ("Proc")           : proc,
    ("Regexp")         : regexp,   ("Rope")                : rope,
    ("Scope")          : scope,    ("Slice")               : slice,
    ("Socket")         : socket,   ("Stream")              : stream,
    ("String")         : string,   ("Symbol")              : symbol,
    ("Tensor")         : tensor,   ("Thread")              : thread,
    ("Token")          : token,    ("Var")                 : var,
    (* "Array")        : <array*>,   (* "Block")             : <block*>,
    (* "Buffer")       : <buffer*>,  (* "Bytes")             : <bytes*>,
    (* "Context")      : <context*>, (* "Error")             : <error*>,
    (* "File")         : <file*>,    (* "Func")              : <func*>,
    (* "Iter")         : <iter*>,
    (* "Lambda")       : <lambda*>,  (* "List")              : <list*>,
    (* "Logger")       : <logger*>,  (* "Map")               : <map*>,
    (* "Mutex")        : <mutex*>,   (* "Pipe")              : <pipe*>,
    (* "Proc")         : <proc*>,
    (* "Regexp")       : <regexp*>,  (* "Rope")              : <rope*>,
    (* "Scope")        : <scope*>,   (* "Slice")             : <slice*>,
    (* "Socket")       : <socket*>,  (* "Stream")            : <stream*>,
    (* "String")       : <string*>,  (* "Symbol")            : <symbol*>,
    (* "Tensor")       : <tensor*>,  (* "Thread")            : <thread*>,
    (* "Token")        : <token*>,   (* "Var")               : <var*>
  };
  return typetags;
}

/** Initializes the process-lifetime scalar and fixed `Var`-tag tables. */
void Type.initialize(void) {
  _typetags_table();
  _scalartypes_table();
}

/** Starts an empty set of source-declared `Var` rows for one translation
    unit.
*/
void Type.begin_unit(void) {
  declared_typetags = %{};
}

/** Ends the source-declared `Var`-row lifetime before the unit `Scope` is
    released.
*/
void Type.end_unit(void) {
  declared_typetags = NULL;
}

/** Registers one named type's unit-local `Var` tag and exact forward
    converter.
    The first row for a canonical `Type` wins. A `NULL` type, name, or
    converter,
    or no active unit, leaves the table unchanged.
*/
void Type.register_var_tag(Type type, String name, String converter) {
  if ((void *) declared_typetags == NULL ||
      !type || !name || !converter) return;
  Type key = type.canonicalize();
  Var row = declared_typetags[key];
  if (row is void)
    declared_typetags[key] = %( ${name.lower().symbol()} $converter );
}

/** Replaces a registered type's inferred `Var` tag with `tag`, or with the
    fixed tag of `representation` when `tag` is zero. Missing rows and
    untagged representations leave the table unchanged.
*/
void Type.register_var_adoption(
  Type type, Type representation, Symbol tag) {
  if ((void *) declared_typetags == NULL || !type) return;
  Type key = type.canonicalize();
  Var row = declared_typetags[key];
  if (!tag && representation) tag = representation.fixed_var_tag();
  if (row is void || !tag) return;
  declared_typetags[key] = %($tag ${row.list().cadr()});
}

/** Returns the unit-local forward `Var` converter for the canonical form of
    `type`, or `NULL`.
*/
String Type.var_converter(Type type) {
  if ((void *) declared_typetags == NULL || !type) return NULL;
  Var row = declared_typetags[type.canonicalize()];
  if (row is void) return NULL;
  return row.list().cadr().str();
}

/** Returns the process-lifetime `Var` tag fixed for `type`, or zero. */
Symbol Type.fixed_var_tag(Type type) {
  if (!type) return 0;
  Symbol scalar = type.scalar_tag();
  if (scalar) return scalar;
  Var vtag = _typetags_table()[type.canonicalize()];
  return vtag is <symbol> ? vtag.symbol() : 0;
}

/** Returns the unit-local `Var` tag for `type`, falling back to its fixed
    tag.
*/
Symbol Type.var_tag(Type type) {
  if (!type) return 0;
  if ((void *) declared_typetags != NULL) {
    Var row = declared_typetags[type.canonicalize()];
    if (row is not void) return row.list().car();
  }
  return type.fixed_var_tag();
}

// type transformation and normalization

/** Returns the suffix of `type` beginning at its builtin or typedef base.
    The result shares the original `List` and is `NULL` when no base is
    present.
*/
Type Type.base_type(Type type) {
  while (type) {
    Var head = type.car();
    // The only strings in types are identifiers, and if we find one
    // before hitting a builtin type, then it must be a typedef name.
    if (head is <string>) return type;
    // Possibly a builtin type
    if (head is <symbol>) {
      switch (type.car().symbol()) {
        case <typedef>:
          return type;
        case <struct>: case <union>: case <enum>: case <int>: case <long>:
        case <short>: case <char>: case <signed>: case <unsigned>: case <void>:
        case <float>: case <double>:
          return type;
        case <const>: case <restrict>: case <volatile>: case <auto>:
        case <static>: case <extern>: case <inline>:
        case <*>: case <&>:case <^>:
          break;
      }
    }
    type = type.cdr();
  }
  return NULL;
}

static int _omit_specifier(Symbol first, int keep_qualifiers) =>
  (first.is_storage_class() ||
   (!keep_qualifiers && first.is_type_qualifier()) || first.is_inline()) &&
  first != <typedef>;

static Type _canonical(Type type, int keep_qualifiers) {
  List rest = type;
  while (rest && (rest.car() is not <symbol> ||
                 !_omit_specifier(rest.car(), keep_qualifiers)))
    rest = rest.cdr();
  if (!rest) return type;
  Array result = %[];
  foreach (Var head, type) {
    if (head is <symbol>) {
      Symbol first = head;
      if (_omit_specifier(first, keep_qualifiers)) continue;
    }
    result.push(head);
  }
  return result.list_free();
}

/** Removes non-typedef storage classes, `inline`, and type qualifiers from
    `type`.
*/
Type Type.canonicalize(Type type) => _canonical(type, 0);

/** Returns the stored declaration `Type` after removing non-typedef storage
    classes and `inline`. Those specifiers describe declaration placement;
    `const`, `restrict`, and `volatile` describe the stored value and remain.
*/
Type Type.declared(Type type) => _canonical(type, 1);

/* Consume the qualifiers at the front of one type and report them as a set.
   The cursor advances past them so a caller can walk a pointer chain one
   level at a time. */
static unsigned _qualifiers(Type *cursor) {
  unsigned found = 0;
  Type type = *cursor;
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
  *cursor = type;
  return found;
}

/** Returns whether handing a `source` value to a `target` declaration would
    silently drop a qualifier the target does not keep. The leading
    qualifiers of each type describe the copied value, not what it points
    at, so only the deeper levels are compared. Callers use this where the
    two types are otherwise the same; a conversion through a converter
    function copies instead of aliasing.
*/
int Type.discards_qualifiers(Type source, Type target) {
  _qualifiers(&source);
  _qualifiers(&target);
  while (source && target) {
    source = source.cdr();
    target = target.cdr();
    unsigned wanted = _qualifiers(&source), offered = _qualifiers(&target);
    if (wanted & ~offered) return 1;
  }
  return 0;
}

// type classification predicates

/** Returns whether `type` is a builtin scalar, struct, union, or enum. */
int Type.is_builtin(Type type) => !!type.scalar() || type._is_tagged();

/** Returns whether the base of `type` is exactly one typedef-name `String`. */
int Type.is_typedef_name(Type type) {
  type = type.base_type();
  return type && type.len() == 1 && car(type) is <string>;
}

/** Returns whether `type` is one bare typedef-name `String`.
    Unlike `is_typedef_name`, this rejects pointer and array wrappers.
*/
int Type.is_bare_typedef_name(Type type) =>
  !!type.match(%(?)) && type.car() is <string>;

/** Returns whether `type` begins with the `typedef` storage class. */
int Type.is_typedef(Type type) {
  if (!type) return 0;
  return type.car() == <typedef>;
}

/** Returns whether `type` is a fixed numeric scalar or an enum. */
int Type.is_number(Type type) => !!type.scalar_tag() || type.is_enum();

/** Returns whether `type` is a fixed integral scalar or an enum. */
int Type.is_integral(Type type) {
  if (type.is_enum()) return 1;
  X2CVarNumericInfo info;
  return Var.numeric_info(type.scalar_tag(), &info) && !info.floating;
}

static int Type._is_tagged(Type type) {
  if (!type) return 0;
  Var first = car(type);
  if (first is <symbol>) return Symbol._is_tagged(first);
  return 0;
}

/** Removes one outer pointer-like or array modifier, or returns `NULL`. */
Type Type.dereference(Type type) {
  _qualifiers(&type);
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

/** Applies integer promotion to `type`.
    Enums and narrow integers become `int`; other scalars retain their
    canonical spelling, and a non-scalar returns `NULL`.
*/
Type Type.promote(Type type) {
  if (type.is_enum()) return %(int);
  type = type.scalar();
  if (!type) return NULL;
  X2CVarNumericInfo info;
  if (_scalar_numeric_info(type, &info) &&
      !info.floating && info.rank < 3)
    return %(int);
  return type;
}

static Type _unsigned_scalar(Type type) {
  switch (type.scalar_tag()) {
    case <i8>:   return %(unsigned char);
    case <i16>:  return %(unsigned short);
    case <i32>:  return %(unsigned);
    case <long>:  return %(unsigned long);
    case <llong>: return %(unsigned long long);
  }
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
  _scalar_numeric_info(a, &ai);
  _scalar_numeric_info(b, &bi);
  if (ai.floating || bi.floating) return ai.rank >= bi.rank ? a : b;
  int ua = ai.unsigned_value, ub = bi.unsigned_value;
  int ra = ai.rank, rb = bi.rank;
  if (ua == ub)         return (ra >= rb) ? a : b;
  if (ua && ra >= rb)   return a;
  if (ub && rb >= ra)   return b;
  Type signed_type = ua ? b : a, unsigned_type = ua ? a : b;
  int signed_bits = ua ? bi.bits : ai.bits;
  int unsigned_bits = ua ? ai.bits : bi.bits;
  if (signed_bits > unsigned_bits) return signed_type;
  return _unsigned_scalar(signed_type);
}

static Type Type._modify(Type type, List mods) => %( @mods @type );

// storage class predicates

/** Returns whether `type` carries the `static` storage class. */
int Type.is_static(Type type) => !!type.match(%(* static *));
/** Returns whether `type` carries the `inline` function specifier. */
int Type.is_inline(Type type) => !!type.match(%(* inline *));
/** Returns whether `type` carries the `extern` storage class. */
int Type.is_extern(Type type) => !!type.match(%(* extern *));
/** Returns whether `type` carries the `threaded` storage class. */
int Type.is_threaded(Type type) => !!type.match(%(* threaded *));

/* Private version can take any internal node of a declaration AST.  It
   will also apply modifications to inline sub-types (i.e., a struct field
   that's a pointer). */
static List _from_ast(List ast, List context);

static List _from_ast_items(List items, List context) {
  Array result = %[];
  foreach (Var item, items) {
    if (item is <list>) result.push(_from_ast(item, context));
    else result.push(item);
  }
  return result.list_free();
}

static List _from_ast(List ast, List context) {
  if (!ast) return ast;
  // Initializers do not contribute to the declared Type.
  match (ast)
    case %(op = (!set ?binding (bind *)) ?):
      return _from_ast(binding, context);
  Var head = car(ast);
  switch (head.symbol()) {
    // (declare ?type ?bindings)
    case <declare>: {
      (List source_type, List bindings) = ast.cdr();
      List type = _from_ast(source_type, NULL);
      return _from_ast(bindings, type);
    }
    // (bind ?ident ?mods)
    case <bind>: {
      List (ident, mods) = ast.cdr();
      (void) ident;
      mods = _from_ast(mods, context);
      List type = context.type()._modify(mods);
      return type;
    }
    // (params ?params), (bindings ?bindings), (fields ?fields)
    case <params>:
    case <bindings>:
    case <fields>:
      return _from_ast_items(cdr(ast), context);
    // (typedef ?type (bindings ?bindings))
    case <typedef>: {
      (List source_type, List bindings) = ast.cdr();
      List type = _from_ast(source_type, NULL);
      return _from_ast(bindings, type);
    }
    // (fnmod ?params)
    case <fnmod>: {
      List params = _from_ast(cdr(ast), NULL);
      return %( func @params );
    }
    // (param ?type ?mods)
    case <param>: {
      (Type parameter_type, List mods) = ast.cdr();
      return _from_ast(mods, parameter_type);
    }
    // Binding identity is AST metadata; semantic Types retain the spelling.
    case <binding>:
      return %(${ast.caddr()});
    // (struct ...), (union ...)
    case <struct>: case <union>: {
      // (struct tag), (union tag) -> as is
      if (ast.type().is_aggregate_tag()) return ast;
      List fields = NULL;
      if (ast.type()._is_aggregate_body()) {
        // (struct body), (union body) -> canonicalize the body
        fields = ast.cadr();
        fields = _from_ast(fields, NULL);
        fields = fields.flatten();
        return %( $head  $fields );
      }
      // (struct ?tag ?body) or (union ?tag ?body) -> drop the body
      return %( $head ${ast.cadr()} );
    }
    case <expr>: {
      match (ast)
        case %(expr (int) (literal ? ?value)): return %($value);
      break;
    }
  }

  Array modifiers = NULL;
  List rest = ast;
  while (rest) {
    Var modifier = rest.car();
    if (modifier is <symbol>) {
      if (modifier != <*> && modifier != <&> && modifier != <^>) break;
    }
    else if (modifier is <list>) {
      Type nested = modifier;
      if (!nested.is_pointer() && !nested.is_array() &&
          !nested.is_function() && !nested.is_bitfield())
        break;
      modifier = _from_ast(modifier, context);
    }
    else break;
    if (!modifiers) modifiers = %[];
    modifiers.push(modifier);
    rest = rest.cdr();
  }
  if (modifiers)
    return modifiers.list_free().append(_from_ast(rest, context));

  return _from_ast_items(ast, context);
}

/** Returns the semantic `Type` represented by a complete `(declare ...)` AST.
    A declaration with one binding is unwrapped to that binding's `Type`;
    multiple bindings return their `Type`s in source order.
*/
Type List.type_from_ast(List ast) {
  List type = _from_ast(ast, NULL);
  match (type) case %((*)): return type.car();
  return type;
}
