/*  stage.x -- values crossing the compile-time boundary

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function runs as native code the compiler stages from
    the unit's `meta` group (`src/macros.x`). This file owns what crosses
    between that code and the program: the arguments a `$` call passes,
    evaluated from constants, captured syntax, and other `$` calls; the
    literal code a result becomes; and the rule that a function reaching a
    compiler operation has no runtime form.
*/
#pragma once
#include "compiler.x"
#pragma private
#include "type.x"
#include "var.x"
#include "string.x"
#include "varconvert.x"
#include <limits.h>
#include <math.h>

/* Evaluates a nested `$` call among a call's arguments. */
typedef Var (*MetaCall)(Compiler c, List expression, Token site);

/* --- the arguments of a `$` call ---------------------------------------- */


/* A String or character literal's value from its source spelling, quotes
   included: adjacent pieces are unescaped on their own and joined, as C
   does, and a character is its code. */
static Var _meta_text(String spelling) {
  int len = spelling.len();
  if (len >= 2 && spelling[0] == '"') {
    String text = "";
    for (int i = 0; i < len; i++) {
      if (spelling[i] != '"') continue;
      int start = ++i;
      while (i < len && spelling[i] != '"') i += spelling[i] == '\\' ? 2 : 1;
      String piece = String.new_len(spelling + start, i - start).unescape();
      text = %"$text$piece";
    }
    return text;
  }
  if (len >= 3 && spelling[0] == '\'') {
    String body = String.new_len(spelling + 1, len - 2).unescape();
    return (char) (body.len() ? body[0] : 0);
  }
  return spelling;
}

static Var _meta_constant(Compiler c, Var node);

/* The value of one folded leaf, or void when it is only known at run
   time. */
static Var _meta_constant_leaf(Compiler c, List value) {
  match (value) {
    case %(expr ? (parens ?inner)): return _meta_constant_leaf(c, inner);
    case %(expr ?type (cast ? ?inner)): {
      Var constant = _meta_constant_leaf(c, inner);
      if (constant is void) return void;
      Symbol tag = ((Type) type).scalar_tag();
      return tag ? constant.convert(tag) : constant;
    }
    case %(expr ? (!set ?node (cache ?))): return _meta_constant(c, node);
    case %(expr ? (!set ?node (expr ? (cache ?)))):
      return _meta_constant(c, node);
    case %(expr ? (nil)):                       return %();
    case %(expr ? (expr ? (nil))):              return %();
    case %(expr ? (literal ? ? ?symbol)):       return symbol;
    case %(expr ("String")
      (call (expr ? (ident (binding ? "String_add")))
            (args ?left ?right))): {
      Var a = _meta_constant(c, left), b = _meta_constant(c, right);
      if (a is void || b is void) return void;
      return a.string().add(b);
    }
    case %(expr ("String") (call ? (args ?inner))):
      return _meta_constant_leaf(c, inner);
    case %(expr ("Var")
      (call (expr ? (ident (binding ? "int_var"))) (args ?inner))):
      return _meta_constant_leaf(c, inner);
    case %(expr ("String") (literal ? ?(String text))): return text;
    case %(expr (* char) (literal ? ?(String text))): return _meta_text(text);
    case %(expr ?type (literal ? ?(String text))):
      return ((Type) type).numeric_literal_value(text);
  }
  if (value && value.car() == <expr>) return void;
  return value;
}

/* Literal folding hoists a constant into the compiler cache and leaves
   `(cache ID)`, a graph of ids over `cons`, `var` and `string` leaves. */
static Var _meta_constant(Compiler c, Var node) {
  match (node) {
    case %(cache ?(int id)): {
      List key = c.id_keys[id];
      match (key) {
        case %(cons ?head ?tail):
          return cons(_meta_constant(c, head), _meta_constant(c, tail));
        case %(var ?value):    return _meta_constant_leaf(c, value);
        case %(string ?value): return _meta_constant_leaf(c, value);
        case %(nil): return %();
      }
      return key;
    }
    case %(cons ?head ?tail):
      return cons(_meta_constant(c, head), _meta_constant(c, tail));
    case %(nil): return %();
  }
  return _meta_constant_leaf(c, node);
}

/* The binary operators a constant argument may apply. */
static const SymbolSet meta_operators = %<<"+" "-" "*" "/" "%" "<<" ">>"
  "&" "|" "^" "<" ">" "<=" ">=" "==" "!=">>;

/** Returns the value the argument expression `node` of a `$` call passes to
    a parameter of type `want`, or of no declared type when `want` is NULL:
    a constant, captured syntax, or the result of another `$` call, which
    `call` evaluates. Captured literal syntax reaches a parameter that is not
    syntax as the literal's value. Anything else is reported at `site`. */
Var Compiler.meta_argument(
  Compiler c, List node, Type want, Token site, MetaCall call) {
  Var value = void;
  match (node) {
    case %(expr ? (meta-cap ?captured)): {
      value = captured;
      if (want && !c.sym.is_var_type(want) &&
          !c.sym.is_named_value_type(want, "List")) {
        Var literal = captured is <list> ? _meta_constant_leaf(c, captured)
                                         : void;
        if (literal is not void && literal is not <list>) value = literal;
      }
    }
    case %(expr ? (parens ?inner)):
      return c.meta_argument(inner, want, site, call);
    case %(expr ? (meta-call *)): value = call(c, node, site);
    /* Negation multiplies, so a negated zero keeps its sign. */
    case %(expr ?type (op - ?operand)):
      value = c.meta_argument(operand, type, site, call).binary(<*>, -1);
    case %(expr ?type (op ?operator ?left ?right)):
      if (operator in meta_operators)
        value = c.meta_argument(left, NULL, site, call).binary(
          operator, c.meta_argument(right, NULL, site, call));
    default: value = _meta_constant(c, node);
  }
  if (value is void)
    c.report_error(
      <macro>, "explicit meta call cannot be resolved", site,
      %("an argument must be a constant, captured syntax, or a meta call"));
  Type numeric = want ? c.sym.resolve_numeric_type(want) : NULL;
  Symbol tag = numeric ? numeric.scalar_tag() : 0;
  if (tag && (value.is_integer() || value.is_floating()))
    value = value.convert(tag);
  return value;
}

/* --- compile-time values in code ---------------------------------------- */

/* Untyped Lisp numbers retain their native Var family at the code boundary. */
static Type _meta_value_type(Var value) {
  switch (value.tag()) {
    case <i8>: return %(signed char);
    case <u8>: return %(unsigned char);
    case <i16>: return %(short);
    case <u16>: return %(unsigned short);
    case <i32>: return %(int);
    case <u32>: return %(unsigned);
    case <long>: return %(long);
    case <ulong>: return %(unsigned long);
    case <llong>: return %(long long);
    case <ullong>: return %(unsigned long long);
    case <f32>: return %(float);
    case <ldouble>: return %(long double);
  }
  if (value.is_floating()) return %(double);
  if (value.is_integer()) {
    long n = value.integer();
    return n == (int) n ? %(int) : %(long long);
  }
  return NULL;
}

/* Whether a value and everything it holds is immutable data. */
static int _meta_immutable(Var value) {
  if (value is <list>) {
    foreach (Var item, value.list())
      if (!_meta_immutable(item)) return 0;
    return 1;
  }
  return value is <string> || value is <symbol> ||
    value.is_integer() || value.is_floating();
}

/* A pointer the evaluator holds names compiler memory, which the running
   program does not have, so it never becomes a constant in code. */
static void _meta_refuse_address(Compiler c, Var value, Token site) {
  if (value.is_pointer() && value.u64)
    c.report_error(
      <macro>, "compile-time result is a compiler address", site,
      %("return data built from the pointed-to values instead"));
}

/* Builds the parser's form of one data value. Immutable values come from
   the literal cache; each Array or Map becomes a literal that builds a fresh
   collection every time it runs. `marks` holds 1 for a collection being
   built and 2 for one already built, so a cycle or a shared collection is
   reported at `site`. */
static List _meta_data(Compiler c, Var value, Map marks, Token site) {
  _meta_refuse_address(c, value, site);
  if (_meta_immutable(value)) {
    if (value is <list>) return c.cache_literal_list(value);
    return %(expr ("Var") ${c.cache_literal_var(value)});
  }
  if (value is <list>) {
    List result = %(nil);
    foreach (Var item, value.list().reverse()) {
      List head = _meta_data(c, item, marks, site);
      if (!head) return NULL;
      result = %(expr ("List") (cons $head $result));
    }
    return result;
  }
  if (value is not <array> && value is not <map>) return NULL;
  ulong address = (ulong) value.u64;
  if (address in marks)
    c.report_error(
      <macro>,
      marks[address] == 1
        ? "compile-time result contains itself"
        : "compile-time result holds one collection twice",
      site, %("each Array and Map in a result is built separately"));
  marks[address] = 1;
  List result = NULL;
  if (value is <array>) {
    Array items = $auto([]);
    foreach (Var item, value.array()) {
      List code = _meta_data(c, item, marks, site);
      if (!code) return NULL;
      items.push(code);
    }
    result = %(expr ("Array") (array @{items.list()}));
  }
  else {
    Map map = value;
    Array keys = $auto([]), entries = $auto([]);
    foreach (Var (key, item), map) keys.push(key);
    // Cache ids and emission must not depend on bucket layout.
    foreach (Var key, keys.sort()) {
      List key_code = _meta_data(c, key, marks, site);
      List value_code =
        key_code ? _meta_data(c, map[key], marks, site) : NULL;
      if (!value_code) return NULL;
      entries.push(%(map-entry $key_code $value_code));
    }
    result = %(expr ("Map") (map @{entries.sort().list()}));
  }
  marks[address] = 2;
  return result;
}

/** Returns literal code for a compile-time `value`, preserving `declared`
    when supplied. An Array or Map, at any depth, becomes a literal that
    builds a fresh collection on every execution; other data comes from the
    literal cache. A cycle or a collection held twice is reported at `site`.
    Returns NULL for code Lists or values without a literal representation.
*/
List Compiler.meta_value_expression(
  Compiler c, Type declared, Var value, Token site) {
  _meta_refuse_address(c, value, site);
  Type type = declared ? declared : _meta_value_type(value);
  if (c.sym.is_var_type(type)) type = %("Var");
  else c.sym.var_tag_for_type(type, type);
  if ((value.is_integer() || value.is_floating()) &&
      type !== %("Var")) {
    type = c.sym.resolve_numeric_type(type);
    Symbol tag = type ? type.scalar_tag() : 0;
    if (!tag) return NULL;
    value = value.convert(tag);
    if (type.scalar() === %(int)) {
      long n = value.integer();
      Type result = declared ? declared : type;
      List literal = %(expr $result (literal (int) ${value.str()}));
      if (n == INT_MIN)
        return %(expr $result (parens (expr $result (cast (int) $literal))));
      return n < 0 ? %(expr $result (parens $literal)) : literal;
    }
    X2CVarNumeric number;
    value.numeric_decode(number);
    String text;
    Type literal_type;
    if (number.floating) {
      literal_type = %(long double);
      long double n = number.floating_value;
      if (isnan(n)) text = "__builtin_nanl(\"\")";
      else if (isinf(n))
        text = n < 0 ? "(-__builtin_infl())" : "__builtin_infl()";
      else text = "%LaL".printf(n);
    }
    else {
      literal_type = %(unsigned long long);
      text = "%lluULL".printf(number.raw);
    }
    List literal = %(expr $literal_type (literal $literal_type $text));
    Type result = declared ? declared : type;
    return %(expr $result (parens (expr $result (cast $type $literal))));
  }
  Type kind = value is <array> ? %("Array") : value is <map> ? %("Map")
    : value is <list> ? %("List") : NULL;
  // Without a declared type, a List result is code rather than data.
  if (declared ? type === %("Var") || type === kind
      : kind && kind !== %("List")) {
    Map marks = $auto({});
    List expression = _meta_data(c, value, marks, site);
    return expression && declared
      ? c.convert_expression(expression, declared) : expression;
  }
  if (value is <string>) {
    if (!declared || type === %(* char))
      return %(expr (* char) (literal (* char) ${value.repr()}));
    if (type === %("String")) {
      List literal = %(expr ("String") (literal ("String") $value));
      return %(expr $declared ${c.cache(%(string $literal))});
    }
  }
  if (value is <symbol> && (!declared || type === %("Symbol")))
    return %(expr ("Symbol") (literal ("Symbol")
                  ${value.symbol().str()} ${value.symbol()}));
  return NULL;
}

/** Refuses a run-time call to a `meta` function this compiler derived
    compile-time only.

    Such a function reaches a `Meta` operation, so it exists only inside a
    compiler and the unit emits no definition for it. Unchecked, the call
    reaches the linker as an undefined symbol, which names the C spelling
    and not the source. Another `meta` function may call it: calling one is
    what makes the caller compile-time only too, so a body being parsed
    under the marker is left alone.
*/
void Compiler.check_meta_call(Compiler c, List callee, Token origin) {
  if (c.meta_body || !c.meta_comptime.len()) return;
  match (callee)
    case %(expr ? (ident (binding ? ?(String name)))):
      if (name in c.meta_comptime)
        c.report_error(
          <macro>, %"'$name' can only be called at compile time", origin,
          %("reason: it reaches a compiler operation, so no unit emits a"
            "definition for it; call it from a macro or another meta"
            "function"));
}

/** Returns whether `fn` is a `meta` function this compiler recorded as
    compile-time only, whose runtime form the unit does not emit.
*/
int Compiler.meta_is_comptime_only(Compiler c, List fn) {
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) *) ?):
      return name in c.meta_comptime;
  return 0;
}
