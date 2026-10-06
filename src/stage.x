/*  stage.x -- the values crossing between meta code and the program

    Copyright (c) 2026 Gary William Flake.

    This file owns what crosses between meta code and the program: the
    arguments a `$` call passes, evaluated from constants, captured syntax,
    and other `$` calls; the literal code a result becomes; and the rule
    that a function reaching a compiler operation has no runtime form. A
    unit's `meta` group and its emission are in `meta-group.x`; the
    compiler's side of the project helper is in `meta-helper-client.x`.
*/
#pragma once
#include "compiler.x"

#include "grammar.x"
#include "type.x"
#include "var.x"
#include "string.x"
#include "varconvert.x"
#include "datum.x"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// diagnostics

static macro Stmt $report.macro.argument_constant(Expr $c, Expr $site) {
  $c.report_error(
    <macro>,
    "explicit meta call cannot be resolved",
    $site, %("an argument must be a constant, captured syntax, or a meta call"));
}

static macro Stmt $report.macro.function_only(
  Expr $c, Expr $site, Expr $name) {
  $c.report_error(
    <macro>,
    %"'${$name}' can only be called at compile time",
    $site, %("reason: it reaches a compiler operation, so no unit emits a"
    "definition for it; call it from a macro or another meta"
    "function"));
}

/** Evaluates a nested `$` call among a call's arguments. */
static typedef Var (*MetaCall)(Compiler c, List expression, Token site);

// arguments of a `$` call

/* The binary operators a constant argument may apply. */
static const SymbolSet meta_operators = %<<"+" "-" "*" "/" "%" "<<" ">>"
  "&" "|" "^" "<" ">" "<=" ">=" "==" "!=">>;

static const SymbolSet meta_comparisons = %<<"<" ">" "<=" ">=" "==" "!=">>;

/** Returns the value the argument expression `node` of a `$` call passes to
    a parameter of type `want`, or of no declared type when `want` is NULL:
    a constant, captured syntax, or the result of another `$` call, which
    `call` evaluates. Captured literal syntax reaches a parameter that is not
    syntax as the literal's value, a `TypeInfo` parameter as the description
    of its type, and a `Source` parameter with its source text. Anything
    else is reported at `site`. */
Var Compiler.meta_argument(
  Compiler c, List node, Type want, Token site, MetaCall call) {
  Var value = void;
  if (want)
    match (node)
      case %(expr ? (meta-cap ?captured)): {
        if (c.sym.is_named_value_type(want, "TypeInfo"))
          return meta_type_description(captured);
        if (c.sym.is_named_value_type(want, "Source"))
          return meta_source_description(captured);
      }
  match (node) {
    case %(expr ? (meta-cap ?captured)):
      value = _captured_value(c, captured, want);
    case %(expr ? ${$grouped(?inner)}):
      return c.meta_argument(inner, want, site, call);
    case %(expr ? (macro-value ?definition)):
      return c.meta_argument(
        c.capture_macro_value(definition), want, site, call);
    case %(expr ? (meta-call *)): value = call(c, node, site);
    /* Negation multiplies, so a negated zero keeps its sign. */
    case %(expr ?type ${$source_operator_content(%(- ?operand))}):
      value = c.meta_argument(operand, type, site, call).binary(<*>, -1);
    case %(expr ?type
        ${$source_operator_content(%(?operator ?left ?right))}):
      if (operator in meta_operators) {
        Type common = NULL;
        if (operator in meta_comparisons) {
          Type a = c.sym.resolve_numeric_type(left.list().cadr());
          Type b = c.sym.resolve_numeric_type(right.list().cadr());
          if (a && b) common = a.widest(b);
        }
        value = c.meta_argument(left, common, site, call).binary(
          operator, c.meta_argument(right, common, site, call));
      }
    default: value = c.folded_constant(node);
  }
  if (value is void) value = _name_syntax(c, node, site);
  return _scalar_value(c, value, want);
}

/* Captured syntax passes as itself, except that a constant reaching a
   parameter that is neither `Var` nor `List` passes as its value. */
static Var _captured_value(Compiler c, Var captured, Type want) {
  if (!want || c.sym.is_var_type(want) ||
      c.sym.is_named_value_type(want, "List"))
    return captured;
  Var literal = captured is <list> ? _constant_leaf(c, captured) : void;
  if (literal is void || literal is <list>) return captured;
  return literal;
}

/* A name that is not a constant, such as a template's own local, passes as
   its syntax. Anything else is reported at `site`. */
static Var _name_syntax(Compiler c, List node, Token site) {
  match (node)
    case %(expr ? ${$source_identifier_content(%(?))}): return node;
  $report.macro.argument_constant(c, site);
}

/* A number passed to a numeric parameter takes the parameter's type. */
static Var _scalar_value(Compiler c, Var value, Type want) {
  Type numeric = want ? c.sym.resolve_numeric_type(want) : NULL;
  Symbol tag = numeric ? numeric.scalar_tag() : 0;
  if (tag && (value.is_integer() || value.is_floating()))
    return value.convert(tag);
  return value;
}

// folded constants

/** Returns the value of the folded constant `node`, or void when part of it
    is only known at run time. Literal folding hoists a constant into the
    compiler cache and leaves `(cache ID)`, a graph of ids over `cons`,
    `var` and `string` leaves. */
Var Compiler.folded_constant(Compiler c, Var node) {
  match (node) {
    case %(cache ?(int id)): return _cached_constant(c, c.id_keys[id]);
    case %(cons ?head ?tail):
      return cons(c.folded_constant(head), c.folded_constant(tail));
    case %(nil): return %();
  }
  return _constant_leaf(c, node);
}

static Var _cached_constant(Compiler c, List key) {
  match (key) {
    case %(cons ?head ?tail):
      return cons(c.folded_constant(head), c.folded_constant(tail));
    case %(var ?value):    return _constant_leaf(c, value);
    case %(string ?value): return _constant_leaf(c, value);
    case %(nil): return %();
  }
  return key;
}

/* The value of one folded leaf, or void when it is only known at run
   time. */
static Var _constant_leaf(Compiler c, List expr) {
  match (expr) {
    case %(expr ? ${$grouped(?inner)}):
      return _constant_leaf(c, inner);
    case %(expr ?type ${$source_cast_content(%(? ?inner))}):
      return _cast_constant(c, type, inner);
    case %(expr ? (!set ?node (cache ?))): return c.folded_constant(node);
    case %(expr ? (!set ?node (expr ? (cache ?)))):
      return c.folded_constant(node);
    case %(expr ? (nil)):                       return %();
    case %(expr ? (expr ? (nil))):              return %();
    case %(expr ? ${$source_literal_content(%(? ? ?symbol))}): return symbol;
    case %(expr ("String") ${$called(
        %(expr ? ${$source_identifier_content(%((binding ? "String_add")))}),
        %(?left ?right))}):
      return _joined_constant(c, left, right);
    case %(expr ("String") (call "String_new" (args ?inner))):
      return _constant_leaf(c, inner);
    case %(expr ("Var") ${$called(
        %(expr ? ${$source_identifier_content(%((binding ? "int_var")))}),
        %(?inner))}):
      return _constant_leaf(c, inner);
    case %(expr ("String") ${$source_literal_content(%(? ?text))})
      if (text is <string>): return text;
    case %(expr (* char) ${$source_literal_content(%(? ?text))})
      if (text is <string>):
      return literal_text_value(text);
    case %(expr ?type ${$source_literal_content(%(? ?text))})
      if (text is <string>):
      return ((Type) type).numeric_literal_value(text);
  }
  if (expr && expr.car() == <expr>) return void;
  return expr;
}

static Var _cast_constant(Compiler c, Var type, List inner) {
  Var constant = _constant_leaf(c, inner);
  if (constant is void) return void;
  Symbol tag = ((Type) type).scalar_tag();
  return tag ? constant.convert(tag) : constant;
}

static Var _joined_constant(Compiler c, Var left, Var right) {
  Var a = c.folded_constant(left), b = c.folded_constant(right);
  if (a is void || b is void) return void;
  return a.string().add(b);
}

/** Returns the value of a String or character literal from its source
    `spelling`, quotes included: adjacent pieces are unescaped on their own
    and joined, as C does, and a character is its code. */
Var literal_text_value(String spelling) {
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

// values in code

/** Returns literal code for a compile-time `value`, preserving `declared`
    when supplied. An Array or Map, at any depth, becomes a literal that
    builds a fresh collection on every execution; other data comes from the
    literal cache. A cycle or a collection held twice is reported at `site`.
    Returns NULL for code Lists or values without a literal representation.
*/
List Compiler.meta_value_expression(
  Compiler c, Type declared, Var value, Token site) {
  if (value is not <list>) _refuse(c, value, site);
  Type type = declared ? declared : Macro.number_type(value);
  if (value is <list> && c.sym.is_named_value_type(declared, "Macro")) {
    List expression = c.macro_value_literal(value);
    return %(expr ("Macro") ${expression.caddr()});
  }
  if (c.sym.is_var_type(type)) type = %("Var");
  else c.sym.var_tag_for_type(type, type);
  if ((value.is_integer() || value.is_floating()) && type !== %("Var"))
    return _number_literal(c, declared, type, value);
  Type kind = value is <array> ? %("Array") : value is <map> ? %("Map")
    : value is <list> ? %("List") : NULL;
  // Without a declared type, a List result is code; an Array or Map is data.
  if (declared ? type === %("Var") || type === kind
      : kind && kind !== %("List"))
    return _data_literal(c, declared, value, site);
  if (value is <string>) return _string_literal(c, declared, type, value);
  if (value is <symbol> && (!declared || type === %("Symbol")))
    return %(expr ("Symbol") (literal ("Symbol")
                  ${value.symbol().str()} ${value.symbol()}));
  return NULL;
}

/* Reports at `site` a result that cannot become data in the program. */
static void _refuse(Compiler c, Var value, Token site) {
  Map marks = $auto({});
  List problem = datum_result_problem(value, marks);
  if (problem) c.report_error(<macro>, problem.car(), site, problem.cadr());
}

static List _string_literal(Compiler c, Type declared, Type type, Var value) {
  if (!declared || type === $!Type{ char * })
    return %(expr (* char) (literal (* char) ${value.repr()}));
  if (type !== %("String")) return NULL;
  List literal = %(expr ("String") (literal ("String") $value));
  return %(expr $declared ${c.cache(%(string $literal))});
}

// number literals

/* A number becomes a literal of its scalar type, or NULL when the type has
   none. */
static List _number_literal(Compiler c, Type declared, Type type, Var value) {
  type = c.sym.resolve_numeric_type(type);
  Symbol tag = type ? type.scalar_tag() : 0;
  if (!tag) return NULL;
  return Macro.number_literal(
    declared ? declared : type, type, value.convert(tag));
}

// data literals

/* Data code for `value`, converted to `declared` when there is one. */
static List _data_literal(Compiler c, Type declared, Var value, Token site) {
  _refuse(c, value, site);
  List expression = _data_form(c, value);
  return expression && declared
    ? c.convert_expression(expression, declared) : expression;
}

/* Builds the parser's form of one data value, which
   `datum_result_problem` accepted. Immutable values come from the literal
   cache; each Array or Map becomes a literal that builds a fresh
   collection every time it runs. */
static List _data_form(Compiler c, Var value) {
  if (value.is_null())
    return %(expr ("Var") (call "Var_null" (args)));
  if (_immutable(value)) {
    if (value is <list>) return c.cache_literal_list(value);
    return %(expr ("Var") ${c.cache_literal_var(value)});
  }
  if (value is <list>) return _list_form(c, value);
  if (value is <array>) return _array_form(c, value);
  if (value is not <map>) return NULL;
  return _map_form(c, value);
}

/* Strings, atoms, numbers, and Lists that hold only such values. */
static int _immutable(Var value) {
  if (value is <list>) {
    foreach (Var item, value.list()) if (!_immutable(item)) return 0;
    return 1;
  }
  return value is <string> || value.is_atom() ||
    value.is_integer() || value.is_floating();
}

static List _list_form(Compiler c, Var value) {
  List tail = %(nil);
  foreach (Var item, value.list().reverse()) {
    List head = _data_form(c, item);
    if (!head) return NULL;
    tail = %(expr ("List") (cons $head $tail));
  }
  return tail;
}

static List _array_form(Compiler c, Var value) {
  Array items = $auto([]);
  foreach (Var item, value.array()) {
    List code = _data_form(c, item);
    if (!code) return NULL;
    items.push(code);
  }
  return %(expr ("Array") (array @{items.list()}));
}

static List _map_form(Compiler c, Var value) {
  Map map = value;
  Array keys = $auto([]), entries = $auto([]);
  foreach (Var (key, item), map) keys.push(key);
  // Cache ids and emission must not depend on bucket layout.
  foreach (Var key, keys.sort()) {
    List key_code = _data_form(c, key);
    List value_code = key_code ? _data_form(c, map[key]) : NULL;
    if (!value_code) return NULL;
    entries.push(%(map-entry $key_code $value_code));
  }
  return %(expr ("Map") (map @{entries.sort().list()}));
}

// compile-time-only functions

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
    case %(expr ? ${$source_identifier_content(%((binding ? ?name)))})
      if (name is <string> && name in c.meta_comptime):
        $report.macro.function_only(c, origin, name);
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
