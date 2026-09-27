/*  stage.x -- meta groups, the project helper, and the values crossing

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function a project defines runs as native code in the
    project's helper program, which the project meta build compiles from
    each unit's `meta` group before translation. This file owns that group:
    what it reaches and its emission through the ordinary backend. It owns
    the helper's side in the compiler: starting it, one request and one
    reply per call, and reporting a body that fails, crashes, or runs too
    long. It also supports staging a group in process. It owns what crosses
    between meta code and the program: the arguments
    a `$` call passes, evaluated from constants, captured syntax, and other
    `$` calls; the literal code a result becomes; and the rule that a
    function reaching a compiler operation has no runtime form.
*/
#pragma once
#include "compiler.x"

/* In-process staging loads native modules, which these platforms lack. */
#if defined(_WIN32) || defined(__CYGWIN__)
#define X2C_NATIVE_MODULES 0
#else
#define X2C_NATIVE_MODULES 1
#endif

#pragma private
#include "type.x"
#include "var.x"
#include "string.x"
#include "varconvert.x"
#include "macros.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include "datum.x"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

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
    case %(expr ("String") (call "String_new" (args ?inner))):
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
    syntax as the literal's value, a `Type` parameter as the description
    of its type, and a `Source` parameter with its source text. Anything
    else is reported at `site`. */
Var Compiler.meta_argument(
  Compiler c, List node, Type want, Token site, MetaCall call) {
  Var value = void;
  if (want)
    match (node)
      case %(expr ? (meta-cap ?captured)): {
        if (c.sym.is_named_value_type(want, "Type"))
          return meta_type_description(captured);
        if (c.sym.is_named_value_type(want, "Source"))
          return meta_source_description(captured);
      }
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

/* Reports at `site` a result that cannot become data in the program. */
static void _meta_refuse(Compiler c, Var value, Token site) {
  Map marks = $auto({});
  List problem = datum_result_problem(value, marks);
  if (problem) c.report_error(<macro>, problem.car(), site, problem.cadr());
}

/* Builds the parser's form of one data value, which
   `datum_result_problem` accepted. Immutable values come from the literal
   cache; each Array or Map becomes a literal that builds a fresh
   collection every time it runs. */
static List _meta_data(Compiler c, Var value) {
  if (_meta_immutable(value)) {
    if (value is <list>) return c.cache_literal_list(value);
    return %(expr ("Var") ${c.cache_literal_var(value)});
  }
  if (value is <list>) {
    List result = %(nil);
    foreach (Var item, value.list().reverse()) {
      List head = _meta_data(c, item);
      if (!head) return NULL;
      result = %(expr ("List") (cons $head $result));
    }
    return result;
  }
  if (value is <array>) {
    Array items = $auto([]);
    foreach (Var item, value.array()) {
      List code = _meta_data(c, item);
      if (!code) return NULL;
      items.push(code);
    }
    return %(expr ("Array") (array @{items.list()}));
  }
  if (value is not <map>) return NULL;
  Map map = value;
  Array keys = $auto([]), entries = $auto([]);
  foreach (Var (key, item), map) keys.push(key);
  // Cache ids and emission must not depend on bucket layout.
  foreach (Var key, keys.sort()) {
    List key_code = _meta_data(c, key);
    List value_code = key_code ? _meta_data(c, map[key]) : NULL;
    if (!value_code) return NULL;
    entries.push(%(map-entry $key_code $value_code));
  }
  return %(expr ("Map") (map @{entries.sort().list()}));
}

/** Returns literal code for a compile-time `value`, preserving `declared`
    when supplied. An Array or Map, at any depth, becomes a literal that
    builds a fresh collection on every execution; other data comes from the
    literal cache. A cycle or a collection held twice is reported at `site`.
    Returns NULL for code Lists or values without a literal representation.
*/
List Compiler.meta_value_expression(
  Compiler c, Type declared, Var value, Token site) {
  if (value is not <list>) _meta_refuse(c, value, site);
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
    _meta_refuse(c, value, site);
    List expression = _meta_data(c, value);
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

/* --- a unit's meta group, emitted as C ---------------------------------- */

/* The C compiler and x2c include directory that build meta code. */
static String meta_cc = NULL, meta_include_dir = NULL;

/* The runtime headers this compiler was built with, which meta code shares
   because it calls the compiler's own runtime: a built checkout stage's
   `lib`, the checked-in bootstrap's, or else `include_dir`. */
static String _meta_headers(String include_dir) {
  String stage = x2c_stage_dir();
  if (stage && Path.is_file(%"$stage/lib/x2c.h")) return %"$stage/lib";
  String executable = x2c_get_executable(), root = x2c_get_root();
  if (executable && root && Path.basename(executable) == "x2c-bootstrap" &&
      Path.dirname(executable) == %"$root/bin")
    return %"$root/bootstrap/lib";
  return include_dir;
}

/** Selects the C compiler `cc` that builds the `meta` code of the units
    this process translates, with the runtime headers this compiler was
    built with, found from its installed headers in `include_dir`. */
void Compiler.use_meta_toolchain(String cc, String include_dir) {
  meta_cc = cc;
  meta_include_dir = _meta_headers(include_dir);
  meta_cc.try_own();
  meta_include_dir.try_own();
}

/** Returns the C compiler and the runtime header directory that build
    `meta` code, or NULL before `Compiler.use_meta_toolchain`. */
String Compiler.meta_cc(String &include_dir) {
  include_dir = meta_include_dir;
  return meta_cc;
}

/* Whether this process stages each unit's group in process rather than
   calling a project helper. */
static int meta_in_process = 0;

/** Enables in-process staging of `meta` groups for compiler sessions. */
void Compiler.stage_meta_in_process(void) { meta_in_process = 1; }

/** Answers whether a `meta` function or value belongs to the unit's group:
    a parse meets it outside a macro definition while the project meta build
    parses the unit or a session stages it. A `.xmacro` import, and each
    compiler that collects a segment of the unit, shares the unit's group. */
int Compiler.groups_meta(Compiler c) =>
  meta_cc && !c.macro_holes && (void *) c.meta_group &&
  (c.meta_build || (X2C_NATIVE_MODULES && meta_in_process));

static int _function_identity(List fn, Var &identity, String &name) {
  match (fn)
    case %(function ? (bind (binding ?id ?(String spelling)) *) ?): {
      identity = id;
      name = spelling;
      return 1;
    }
  return 0;
}

/** Records the bodied `meta` function `fn` in the unit's group. */
void Compiler.group_meta_function(Compiler c, List fn) {
  match (fn)
    case %(function ?spec (!set ?declarator (bind (binding ? ?(String name))
                                                  *)) ?): {
      Type type = %(declare $spec (bindings $declarator)).type_from_ast()
                    .canonicalize();
      c.meta_group.push(%(function $fn $name $type));
    }
}

/** Records that a compile-time import has just added its `meta` definitions
    to the unit, so the group places them where the import stands. */
void Compiler.record_meta_import(Compiler c) {
  if (c.groups_meta())
    c.meta_group.push(%(import ${c.unit_nodes ? c.unit_nodes.len() : 0}
                            ${c.meta_defs.len()}));
}

/** Answers whether a `meta` body reaches the compiler itself: it names a
    compile-time-only function or a compiler operation, or constructs a
    template. Such a function has no runtime form. */
int Compiler.meta_reaches_compile_time(Compiler c, Var node) {
  if (node is not <list>) return 0;
  List syntax = node;
  match (syntax) {
    case %((!or tpl-call meta-call) *): return 1;
    case %(ident (binding ? ?(String name))): {
      /* Expansion can insert a call typed by its macro definition. */
      if (name in c.native_meta) c.bind_native_meta(name);
      return name in c.meta_comptime || Compiler.supplies_native_meta(name);
    }
  }
  foreach (Var child, syntax)
    if (c.meta_reaches_compile_time(child)) return 1;
  return 0;
}

/* Whether `node` includes an x2c unit outside the runtime in `lib`, whose
   header its own translation writes: a group compiles without it. */
static int _meta_local_include(Var node, String lib) {
  match (node)
    case %(preproc ?(String text)):
      if (text.startswith("#include \"") && text.endswith(".x\"")) {
        String name = text[10:text.len() - 1];
        return !Path.is_file(%"$lib$name");
      }
  return 0;
}

/* The unit's definitions so far that the group can reach, in source order:
   every directive and declaration, the imported `meta` definitions where
   their import stands, each function the group reaches, and the group's
   compile-time-only functions, which the unit itself never emits. */
static Array _meta_group_units(Compiler c) {
  Array ordered = [];
  /* The runtime prelude declares more than `x2c.h` includes, and a body
     can name any of it, so the group includes each runtime unit the
     translation read, and the prelude and the compile-time surface when a
     collection pass has read none. */
  String lib = %"${x2c_get_root()}/lib/";
  foreach (String header, %("x2c.x" "meta.x"))
    ordered.push(%(preproc ${%"#include \"$header\""}));
  foreach (Var (path, _), c.deps) {
    String dependency = path;
    if (dependency.startswith(lib) && dependency.endswith(".x") &&
        !dependency[lib.len():].contains("/"))
      ordered.push(
        %(preproc ${%"#include \"${Path.basename(dependency)}\""}));
  }
  /* Collection parses no bodies, so its group holds only imports. */
  int flushed = 0, count = c.unit_nodes ? c.unit_nodes.len() : 0;
  for (int i = 0; i <= count; i++) {
    foreach (List entry, c.meta_group)
      match (entry)
        case %(import ?(int at) ?(int end)):
          if (at == i)
            for (; flushed < end; flushed++)
              ordered.push(c.meta_defs[flushed]);
    if (i < count && !_meta_local_include(c.unit_nodes[i], lib))
      ordered.push(c.unit_nodes[i]);
  }
  for (; flushed < (int) c.meta_defs.len(); flushed++)
    ordered.push(c.meta_defs[flushed]);
  Map present = {}, reached = {};
  Var identity, String name;
  foreach (List item, ordered)
    if (_function_identity(item, identity, name)) present[identity] = 1;
  foreach (List entry, c.meta_group)
    match (entry) case %(function ?fn *): {
      ast_collect_binding_references(fn, reached);
      if (_function_identity(fn, identity, name) && !(identity in present))
        ordered.push(fn);
      reached[identity] = 1;
    }
  foreach (List item, ordered)
    if (!_function_identity(item, identity, name))
      ast_collect_binding_references(item, reached);
  /* A function reaches only what it names, so collecting from each reached
     function until nothing new is reached closes the set. */
  Map expanded = {};
  int grew = 1;
  while (grew) {
    grew = 0;
    foreach (List item, ordered)
      if (_function_identity(item, identity, name) &&
          identity in reached && !(identity in expanded)) {
        expanded[identity] = 1;
        ast_collect_binding_references(item, reached);
        grew = 1;
      }
  }
  /* An unreached function keeps its prototype, which code generated for
     the unit's types, such as a protocol adapter, may name; the optimizer
     drops what nothing calls. */
  Array units = [];
  foreach (List item, ordered) {
    if (!_function_identity(item, identity, name) ||
        (identity in reached && name != "main"))
      units.push(item);
    else if (name != "main")
      match (item) case %(function ?spec ?declarator ?):
        units.push(%(declare $spec (bindings $declarator)));
  }
  return units;
}

/* A function definition with no parameters. */
static List _meta_entry_function(
  Compiler c, List result, String name, List body) =>
  %(function $result
      (bind ${c.sym.introduce(name)}
        ((fnmod (params (param (void) (bind () ()))))))
      $body);

static List _meta_call(String name, List arguments) =>
  %(expr () (call (expr () (ident ("x2c.ident" $name))) (args @arguments)));

/* Whether `node` holds a braced initializer. */
static int _meta_braced(Var node) {
  if (node is not <list>) return 0;
  if (((List) node).car() == <composite>) return 1;
  foreach (Var part, (List) node) if (_meta_braced(part)) return 1;
  return 0;
}

/* A braced initializer may name a type C cannot spell again, such as an
   anonymous struct, so each group static with one is declared beside an
   unchanging copy that `x2c_module_reset` assigns from. Replaces those
   declarations in `units` and returns each copy's expression by the
   static's binding. */
static Map _meta_initial_copies(Compiler c, Array units) {
  Map copies = {};
  foreach (List entry, c.meta_group)
    match (entry)
      case %(static (!set ?declaration (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding ?mods))
                                     ?initializer))))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (type.contains(<const>) || type.is_array() ||
            !_meta_braced(initializer))
          continue;
        List copy = c.sym.introduce(
          %"${binding.list().last()}_x2c_initial");
        for (int i = 0; i < (int) units.len(); i++)
          if (units[i].equal(declaration))
            units[i] = %(declare $spec (bindings
              (op = $bound $initializer)
              (op = (bind $copy $mods) $initializer)));
        copies[binding] = %(expr $type (ident $copy));
      }
  return copies;
}

/* The group's entry in the shape `x2c build --kind meta-module` writes:
   the stamp, `x2c_module_reset`, which reinitializes each mutable `meta
   static` value, and `x2c_module_targets`, a Map from the name of each
   group function and of the reset entry to a `Func` that calls it. The
   exported names end in `suffix`, so several groups link into one
   program. */
static List _meta_group_entry(
  Compiler c, String stamp, Map initials, String suffix) {
  Array resets = [];
  foreach (List entry, c.meta_group)
    match (entry)
      case %(static (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding *))
                                     ?initializer)))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (type.contains(<const>) || type.is_array()) continue;
        Var initial;
        if (initials.try_get(binding, initial)) initializer = initial;
        resets.push(%(stmnt (expr $type
          (op = (expr $type (ident $binding)) $initializer))));
      }
  List reset = _meta_entry_function(
    c, %(void), %"x2c_module_reset$suffix",
    %(block @{resets.list_free()}));
  Array targets = [];
  List named = %(("x2c_module_reset" ${reset.caddr().cadr()}
                  ((func ((void))) void)));
  foreach (List entry, c.meta_group)
    match (entry) case %(function ?fn ?(String name) ?(Type type) *):
      named = named.append(%(($name ${fn.caddr().cadr()} $type)));
  /* A function whose values have no Var form, such as C's `bool` or a
     record pointer, is called only from other group code. */
  int count = 0;
  foreach (List row, named) {
    (String name, List binding, Type type) = row;
    List function = NULL;
    try function = c.convert_expression(
      %(expr $type (ident $binding)), %("Func"));
    catch %(malformed *): continue;
    targets.push(_meta_call("String_var", %(${x2c_literal_string(name)})));
    targets.push(_meta_call("Func_var", %($function)));
    count++;
  }
  List table = c.bind_syntax(
    _meta_call("Map_update_n", %(${_meta_call("Map_new", %())}
      ${x2c_literal_int(count)} @{targets.list_free()})),
    AST_EXPRESSION, NULL);
  List stamp_binding = c.sym.introduce(%"x2c_module_stamp$suffix");
  String literal = %"\"$stamp\"";
  return %(
    (declare (const char)
      (bindings (op = (bind $stamp_binding ((dim)))
                     (expr (* char) (literal (* char) $literal)))))
    $reset
    ${_meta_entry_function(
        c, %("Map"), %"x2c_module_targets$suffix",
        %(block (return ("Map") $table)))});
}

List Compiler.transform(Compiler compiler, List ast);
List generate_code_text(Compiler c, List ast, String basename);

/* `node` with each template call replaced by a call of `x2c_template_call`,
   named by `callee`, on its template and its arguments as Vars. */
static Var _meta_template_calls(Compiler c, Var node, List callee) {
  if (node is not <list>) return node;
  match (node)
    case %(expr ?type (tpl-call ?stored (args *arguments))): {
      List values = %(nil);
      foreach (Var argument, arguments.reverse())
        values = %(expr ("List") (cons ${c.convert_expression(
          _meta_template_calls(c, argument, callee), %("Var"))} $values));
      List template = stored is <list>
        ? c.convert_expression(c.cache_literal_list(stored), %("Var"))
        : %(expr ("Var") ${c.cache_literal_var(stored.str())});
      return %(expr $type (call $callee (args $template $values)));
    }
  Array parts = [];
  foreach (Var part, (List) node)
    parts.push(_meta_template_calls(c, part, callee));
  return parts.list_free();
}

/* A native module's C target lives in the module, not in the helper.
   Keep its native function type while looking it up in the same module
   that supplied the compiler's binding. */
static Var _meta_native_targets(Compiler c, Var node, List lookup) {
  if (node is not <list>) return node;
  match (node) {
    case %(expr ?(Type result)
           (call (!set ?callee
             (expr ? (ident (binding ? ?(String name)))))
             (args *arguments))): {
      Type native = NULL;
      if (name in c.native_meta && c.native_meta_module(name, native)) {
        Array values = [];
        List declared = c.func_signature(callee.list().cadr()).car().list()
                         .cadr();
        List parameters = native.car().list().cadr();
        foreach (List argument, arguments) {
          argument = _meta_native_targets(c, argument, lookup);
          if (c.sym.normalize_declared_type(declared.car()).equal(
                c.sym.normalize_declared_type(%("Func"))) &&
              c.sym.normalize_declared_type(parameters.car()).equal(
                c.sym.normalize_declared_type(%("Var"))))
            argument = c.convert_expression(
              c.convert_expression(argument, %("Func")), %("Var"));
          values.push(argument);
          declared = declared.cdr();
          parameters = parameters.cdr();
        }
        List target = _meta_native_targets(c, callee, lookup);
        List call = c.resolve_expression(
          %(expr () (call $target (args @{values.list_free()}))), NULL);
        return c.convert_expression(call, result);
      }
    }
    case %(expr ?(Type type) (ident (binding ? ?(String name)))):
      if (type.is_function() && name in c.native_meta) {
        String module = c.native_meta_module(name, type);
        if (module) {
          c.add_translation_dependency(module);
          Type pointer = type.reference();
          List target = %(expr (* void) (call $lookup
            (args ${x2c_literal_string(module)}
                  ${x2c_literal_string(name)})));
          return %(expr $pointer (cast $pointer $target));
        }
      }
  }
  Array parts = [];
  foreach (Var part, (List) node)
    parts.push(_meta_native_targets(c, part, lookup));
  return parts.list_free();
}

/* Emits the group through the ordinary backend as `(hfile htext cfile
   ctext)` named by `stem`, with exported names ending in `suffix`, or
   returns NULL with `failure` set when it does not lower. The emission
   borrows the unit's bindings and types and leaves the unit as it found
   it: generated names, literal caches, helpers, initializers, and semantic
   rows are its own. */
static List _meta_group_code(
  Compiler c, String stamp, String stem, String suffix, String &failure) {
  Array units = _meta_group_units(c);
  struct Compiler saved = *c;
  struct GenNames names = *c.names;
  SymTxn transaction = c.begin_semantic_transaction();
  with c {
    _.names.adapters = names.adapters.copy();
    _.names.file_scope_owners = names.file_scope_owners.copy();
    _.id_keys = saved.id_keys.copy();
    _.key_ids = saved.key_ids.copy();
    _.inits = [];
    _.early_decls = [];
    _.origins = saved.origins.copy();
    _.init_tokens = {};
    _.static_init_deps = {};
    _.fn_defs = saved.fn_defs.copy();
    _.protocol_helpers = saved.protocol_helpers.copy();
    _.meta_regions = saved.meta_regions.copy();
    _.deps = {};
    _.needs_exception = 0;
    _.macro_stack = NULL;
    _.macro_holes = NULL;
    _.meta_body = 0;
    _.return_type = NULL;
    _.lambda_scopes = NULL;
    _.source_facts = 0;
    _.recovery_depth = saved.recovery_depth + 1;
    _.filename = %"$stem.x";
    _.diagnostics = Diagnostics.new(NULL, 1);
  }
  List code = NULL;
  try {
    List binding = c.sym.introduce("x2c_template_call");
    Type type = %((func (("Var") ("List"))) "List");
    List callee = %(expr $type (ident $binding));
    for (int i = 0; i < (int) units.len(); i++)
      units[i] = _meta_template_calls(c, units[i], callee);
    if (c.meta_build) {
      Type lookup_type = %((func (("String") ("String"))) * void);
      List lookup_binding = c.sym.introduce("x2c_meta_native_symbol");
      List lookup = %(expr $lookup_type
        (ident $lookup_binding));
      List (base, mods) = lookup_type.declaration_parts();
      units.push(%(declare $base
        (bindings (bind $lookup_binding $mods))));
      for (int i = 0; i < (int) units.len(); i++)
        units[i] = _meta_native_targets(c, units[i], lookup);
    }
    int after = 0;
    while (after < (int) units.len() &&
           ((List) units[after]).car() == <preproc>)
      after++;
    units.insert(after, %(declare ("List") (bindings (bind $binding
      ((fnmod (params (param ("Var") (bind () ()))
                      (param ("List") (bind () ())))))))));
    Map initials = _meta_initial_copies(c, units);
    foreach (Var unit, _meta_group_entry(c, stamp, initials, suffix))
      units.push(unit);
    /* The unit's protocol adapters and their registration belong to the
       program; group code reaches the runtime's own. */
    List ast = c.transform(units.list_free());
    code = generate_code_text(c, ast, stem);
  }
  catch %(?kind *detail): {
    List entries = c.diagnostics.entries();
    failure = entries ? entries.repr() : cons(kind, detail).repr();
    code = NULL;
  }
  *c = saved;
  *c.names = names;
  transaction.rollback();
  return code;
}

/** Returns the identity of the C compiler at `cc`: its path and content
    hash. */
String Compiler.meta_cc_identity(String cc) {
  String path = cc.contains("/") ? cc : x2c_find_program(cc);
  int ok = path != NULL;
  uint64_t hash = UINT64_C(1469598103934665603);
  if (ok) hash = x2c_fnv_file(hash, path, ok);
  return ok ? "%s %016llx".printf(path, (unsigned long long) hash) : cc;
}

/* The C compiler's first located error in `errors`, or else its first
   line, joined with the next when it ends in a colon, as a linker's
   undefined-symbol report does. */
static String _meta_cc_error(String errors) {
  Array lines = [];
  foreach (String line, (errors ? errors : "").split("\n")) {
    String text = line.strip(NULL);
    if (!text) continue;
    if (text.contains(": error: ") && !text.startswith("clang:") &&
        !text.startswith("cc:") && !text.startswith("gcc:"))
      return text;
    lines.push(text);
  }
  if (!lines.len()) return "the C compiler failed";
  String first = lines[0];
  if (!first.endswith(":") || lines.len() < 2) return first;
  String next = lines[1];
  if (next.endswith(":")) next = next[:next.len() - 1];
  return %"$first $next";
}

/** Runs `arguments`, a C compiler command building the group C in
    `directory`, and returns NULL, or else its first error, which names
    `directory` when a group's C is the cause. */
String Compiler.meta_cc_run(List arguments, String directory) {
  String printed = NULL, errors = NULL;
  if (!tool_capture(arguments, printed, errors)) return NULL;
  String failure = _meta_cc_error(errors);
  return !directory || failure.contains(directory) ? failure
    : %"$failure; the group's C is in $directory";
}

/* The first name `node` reads that is a bodyless `meta` prototype nothing
   supplies, or NULL. */
static String _meta_unbound_callee(Compiler c, Var node) {
  if (node is not <list>) return NULL;
  Var bound;
  match (node) case %(ident (binding ? ?(String name))): {
    String unbound = %"<unbound $name>";
    return unbound in c.meta_group_bound ||
           (name in c.native_meta && !c.macro_lisp.try_get(name, bound) &&
            !c.bind_native_meta(name)) ? name : NULL;
  }
  foreach (Var child, (List) node) {
    String name = _meta_unbound_callee(c, child);
    if (name) return name;
  }
  return NULL;
}

/* Why the group cannot link, or NULL: a function it calls is a bodyless
   `meta` prototype that nothing supplies. */
static String _meta_group_unbound(Compiler c) {
  foreach (List entry, c.meta_group)
    match (entry) case %(function ?fn *): {
      String name = _meta_unbound_callee(c, fn);
      if (name) return %"no binding for $name";
    }
  return NULL;
}

/* --- the project meta build --------------------------------------------- */

/* Where the project meta build writes each unit's group, while it runs. */
static String meta_build_directory = NULL;

/** Directs the group of each unit the project meta build parses into
    `directory`, or stops that when it is NULL. */
void Compiler.use_meta_build_directory(String directory) {
  meta_build_directory = directory;
}

/** Writes the group of a unit the project meta build parsed into the build
    directory as `group-K.c` and `group-K.h`, K being its table, with the
    x2c sources it read in `group-K.deps`, or its failure in
    `group-K.failure`. A unit without `meta` functions writes nothing. */
void Compiler.write_meta_build(Compiler c) {
  int index = c.meta_build - 1, functions = 0;
  foreach (List entry, c.meta_group)
    match (entry) case %(function *): functions++;
  if (!functions || !meta_build_directory) return;
  String base = %"$meta_build_directory/group-$index";
  String failure = _meta_group_unbound(c);
  List code = failure ? NULL : _meta_group_code(
    c, build_module_stamp(), %"meta_group_$index", %"_$index", failure);
  Array sources = [];
  foreach (Var (path, _), c.deps) sources.push(path);
  Path.write_text(%"$base.deps", "\n".join(sources.list_free()));
  if (!code) {
    Path.write_text(%"$base.failure", failure);
    return;
  }
  (String hfile, String header, String cfile, String source) = code;
  Path.write_text(%"$meta_build_directory/$hfile", header);
  Path.write_text(%"$base.c", source);
}

/* --- the helper that runs a project's meta functions ---------------------- */

/* The project's helper, its tables' failures by index, and the table each
   input calls, which last for the process; a forked translation worker
   inherits them. */
static String helper_path = NULL;
static Map helper_failures = NULL, helper_units = NULL;
static Scope helper_scope = NULL;

/* The helper this process runs, its ends of the two pipes, the reply bytes
   read so far, the table the unit being translated calls, and whether that
   unit's reset is still to be sent. */
static pid_t helper_pid = 0, helper_owner = 0;
static int helper_to = -1, helper_from = -1, helper_table = 0;
static int helper_reset = 0;
static Buffer helper_input = NULL;

/** Stops the helper this process runs, which a translation worker does
    when its units are done and every process does as it ends. */
void Compiler.stop_meta_helper(void) { _helper_stop(0); }

static int _helper_stop(int signal);

static void _helper_shutdown(void) {
  _helper_stop(0);
  helper_scope.destroy();
  helper_scope = NULL;
  helper_path = NULL;
  helper_failures = helper_units = NULL;
  helper_input = NULL;
}

/** Uses the helper at `path`, or none when it is NULL, whose tables named
    in `failures` could not be built, each with why, and whose table for
    each input path is in `units`. */
void Compiler.use_meta_helper(String path, Map failures, Map units) {
  if (!path && !failures) return;
  if (!helper_scope) Scope.shutdown_hook(_helper_shutdown);
  Scope.push(&helper_scope);
  helper_path = path ? String.new(path) : NULL;
  helper_failures = failures ? failures.copy() : NULL;
  helper_units = units ? units.copy() : NULL;
  helper_input = Buffer.new(0);
  Scope.pop();
}

/** Selects the table of the unit at `filename` for the calls that follow,
    and resets the unit's `meta static` values before the first one. */
void Compiler.begin_meta_unit(String filename) {
  Var table;
  helper_table = helper_units && filename &&
    helper_units.try_get(Path.absolute(filename), table) ? table.integer() : 0;
  helper_reset = 1;
}

/* Ends the helper this process started, if any, and forgets it: asks it
   to quit, or sends it `signal`, and reaps it. Returns its wait status. */
static int _helper_send(List message);

static int _helper_stop(int signal) {
  int status = 0;
  if (helper_pid > 0 && helper_owner == getpid()) {
    if (signal) kill(helper_pid, signal);
    else _helper_send(%(quit));
    close(helper_to);
    close(helper_from);
    waitpid(helper_pid, &status, 0);
  }
  helper_pid = 0;
  helper_to = helper_from = -1;
  if (helper_input) helper_input.clear();
  return status;
}

/* Starts the helper unless this process runs one. A worker forked from a
   process that ran one starts its own. Every pipe end is close-on-exec,
   and the helper keeps only its descriptors 3 and 4, so it reads the end
   of its requests as soon as this process closes its end or ends. */
static int _helper_start(void) {
  if (helper_pid > 0 && helper_owner == getpid()) return 1;
  helper_pid = 0;
  int requests[2], replies[2];
  if (pipe(requests) || pipe(replies)) return 0;
  for (int i = 0; i < 2; i++) {
    fcntl(requests[i], F_SETFD, FD_CLOEXEC);
    fcntl(replies[i], F_SETFD, FD_CLOEXEC);
  }
  pid_t pid = fork();
  if (!pid) {
    int in = fcntl(requests[0], F_DUPFD_CLOEXEC, 10);
    int out = fcntl(replies[1], F_DUPFD_CLOEXEC, 10);
    dup2(in, 3);
    dup2(out, 4);
    execl(helper_path, helper_path, (char *) NULL);
    _exit(127);
  }
  close(requests[0]);
  close(replies[1]);
  helper_pid = pid;
  helper_owner = getpid();
  helper_to = requests[1];
  helper_from = replies[0];
  if (helper_input) helper_input.clear();
  helper_reset = 1;
  return 1;
}

/* Sends one frame, or returns 0 when the helper has gone. A write to a
   helper that has exited must not end the compiler with SIGPIPE. */
static int _helper_send(List message) {
  Buffer out = $auto(Buffer.new(0));
  if (!datum_write(out, message, 1)) return 0;
  String frame = %"${out.len()}\n$out";
  void (*previous)(int) = signal(SIGPIPE, SIG_IGN);
  size_t done = 0, size = frame.len();
  while (done < size) {
    ssize_t n = write(helper_to, (char *) frame + done, size - done);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) break;
    done += n;
  }
  signal(SIGPIPE, previous);
  return done == size;
}

/* The limit on one call from `X2C_META_TIMEOUT` in seconds, 60 by default;
   zero or less is none. */
static double _helper_limit(void) {
  String text = Env.get("X2C_META_TIMEOUT");
  return text ? atof(text) : 60.0;
}

static double _helper_now(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1e9;
}

/* Reads the next reply frame into `reply`. Returns 1, 0 when the helper
   ended, or -1 when `deadline` passed first. */
static int _helper_receive(double deadline, Var &reply) {
  for (;;) {
    String input = helper_input;
    int newline = input.find("\n");
    if (newline > 0) {
      size_t length = strtoul(input, NULL, 10);
      if (input.len() >= newline + 1 + length) {
        String frame = String.new_len(input + newline + 1, length);
        String rest = input[newline + 1 + length:];
        helper_input.clear();
        if (rest) helper_input.write(rest);
        unsigned cursor = 0;
        reply = void;
        try return datum_read(frame, cursor, reply);
        catch %((!or incomplete malformed) *): return 0;
      }
    }
    int wait = -1;
    if (deadline > 0) {
      double left = deadline - _helper_now();
      if (left <= 0) return -1;
      wait = (int) (left * 1000) + 1;
    }
    struct pollfd ready = { .fd = helper_from, .events = POLLIN };
    int polled = poll(&ready, 1, wait);
    if (polled < 0 && errno == EINTR) continue;
    if (polled == 0) return -1;
    char bytes[65536];
    ssize_t n = read(helper_from, bytes, sizeof bytes);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return 0;
    helper_input.write(String.new_len(bytes, n));
  }
}

/* Why the helper that answered no more ended: how it exited, or the signal
   that stopped it, which is also how a body that overflows the stack
   ends. */
static String _helper_ending(void) {
  int status = _helper_stop(0);
  int code = WEXITSTATUS(status);
  if (!WIFSIGNALED(status)) return %"the body exited with status $code";
  int signal = WTERMSIG(status);
  String name = String.new(strsignal(signal));
  return %"the body crashed or overflowed the stack (signal $signal: $name)";
}

/* Why the group function `name` has no table entry, from its type. */
static String _helper_missing(Compiler c, String name) {
  Type type = NULL;
  foreach (List entry, c.meta_group)
    match (entry) case %(function ? ?(String target) ?(Type own)):
      if (target == name) type = own;
  Type result = type ? type.apply() : NULL;
  if (result && !c.sym.is_var_type(result)) result = c.sym.resolve_key(result);
  if (result && result.is_aggregate())
    return "a struct or union result has no compile-time value; return its "
           "fields as a List or Map";
  if (result && result.is_pointer())
    return "an address result has no compile-time value; return data built "
           "from the pointed-to values";
  return "a parameter or the result has no Var form, such as C's bool; use "
         "int, a String, a Symbol, or a List";
}

static void _helper_refuse(Compiler c, String name, Token site, String why) {
  c.report_error(
    <macro>, "this function cannot run at compile time", site,
    %("function: $name" "reason: $why"));
}

/** Calls the project `meta` function `name` in the helper with the values
    `arguments`, for the call at `site`, and returns its result. A warning
    the body makes is reported at `site` and a failure it reports is the
    call's failure. A body that crashes, exits, or passes the deadline ends
    the helper, which is reported at `site` and started again for the next
    call. */
Var Compiler.meta_helper_call(
  Compiler c, String name, Token site, List arguments) {
  Var failure;
  if (!helper_path)
    _helper_refuse(
      c, name, site,
      helper_failures && helper_failures.try_get(-1, failure)
        ? failure : "the project meta module was not built");
  if (helper_failures && helper_failures.try_get(helper_table, failure))
    _helper_refuse(c, name, site, failure);
  String missing = _helper_missing(c, name);
  if (missing.startswith("a struct")) _helper_refuse(c, name, site, missing);
  if (!_helper_start())
    _helper_refuse(c, name, site, "the compile-time helper did not start");
  if (helper_reset) {
    _helper_send(%(reset $helper_table));
    helper_reset = 0;
  }
  _helper_send(%(call $name $arguments));
  double limit = _helper_limit();
  double deadline = limit > 0 ? _helper_now() + limit : 0;
  for (;;) {
    Var reply;
    int status = _helper_receive(deadline, reply);
    if (status < 0) {
      _helper_stop(SIGKILL);
      c.report_error(
        <macro>, "%s%g s".printf("this meta call ran longer than ", limit),
        site,
        %("function: $name"
          "set X2C_META_TIMEOUT to a larger limit in seconds, or 0 for none"));
    }
    if (!status)
      c.report_error(
        <macro>, "this meta call stopped the compile-time helper", site,
        %("function: $name" "reason: ${_helper_ending()}"));
    match (reply) {
      case %(warning ?(String message) ?(List notes)):
        c.report_warning(<macro>, message, site, notes);
      case %(value ?value): return value;
      case %(void): return void;
      case %(error ?(String message) ?(List notes)):
        c.report_error(<macro>, message, site, notes);
      case %(dependency ?(String path) ?(String hash)):
        c.deps.merge_translation_dependency(path, hash);
      case %(missing): _helper_refuse(c, name, site, _helper_missing(c, name));
      case %(failure (?code *detail)): Error.raise(code, detail);
      default:
        c.report_error(
          <macro>, "this meta call stopped the compile-time helper", site,
          %("function: $name" "reason: the helper sent an unknown reply"));
    }
  }
}

/* --- a session group, staged in process -------------------------------- */

/* Holds what staged `meta static` values allocate. */
static Scope session_meta_scope = NULL;

/* Builds the group's native module under the cache root, named by the
   SHA-256 of its emitted C, the compiler stamp, the C compiler's identity,
   and the runtime headers' directory, or reuses the module an earlier
   submission built. Returns its path, or NULL with `failure` set when
   there is no cache or the group does not build. */
static String _stage_meta_group(Compiler c, String &failure) {
  String root = script_cache_root(), stamp = build_module_stamp();
  if (!root || !stamp) {
    failure = "native modules need a cache directory and a known compiler";
    return NULL;
  }
  List code = _meta_group_code(c, stamp, "group", "", failure);
  if (!code) return NULL;
  (String hfile, String header, String cfile, String source) = code;
  String key = String.sha256(%"$header\n$source\n$stamp\n"
    + %"${Compiler.meta_cc_identity(meta_cc)}\n$meta_include_dir");
  String directory = %"$root/meta/$key";
  String module = %"$directory/group.module";
  if (Path.is_file(module)) return module;
  String output = %"$module.${"%ld".printf((long) getpid())}";
  Path.make_dirs(directory);
  Path.write_text(%"$directory/$hfile", header);
  Path.write_text(%"$directory/$cfile", source);
  Toolchain linker = toolchain_new(meta_cc, NULL, NULL, NULL, NULL, 0, 0);
  failure = Compiler.meta_cc_run(linker.module_action(
    output, %("-fsigned-char" "-fPIC" "-O0" "-iquote" $directory
              "-iquote" $meta_include_dir ${%"$directory/$cfile"}))
    .arguments, directory);
  if (failure) return NULL;
  Path.move_to(output, module);
  return module;
}

/** Builds and loads the session's `meta` group, then binds each
    group function in the session not yet bound. Returns the loaded module,
    or NULL with `failure` set when the group does not stage. */
String Compiler.stage_meta_group(Compiler c, String &failure) {
  failure = c.groups_meta() ? _meta_group_unbound(c)
                            : "native modules are unavailable";
  String module = failure ? NULL : _stage_meta_group(c, failure);
  if (!module) return NULL;
  module = Compiler.load_native_module(module);
  Map targets = Compiler.native_module_targets(module);
  if (!(module in c.meta_group_bound)) {
    c.meta_group_bound[module] = 1;
    Scope.push(&session_meta_scope);
    ((Func) targets["x2c_module_reset"].pointer()).apply(0, NULL);
    Scope.pop();
  }
  foreach (List entry, c.meta_group)
    match (entry) case %(function ? ?(String target) ?(Type type) *): {
      if (target in c.meta_group_bound || !(target in targets)) continue;
      Var bound = targets[target];
      if (!c.native_meta_accepts(bound, c.func_signature(type))) continue;
      c.macro_lisp.set_global(target, bound);
      c.meta_group_bound[target] = 1;
    }
  return module;
}

/** Binds the session's group function `name` when it is not bound yet, by
    staging the group, and reports at `site` a function that cannot run. */
void Compiler.bind_meta_group(Compiler c, String name, Token site) {
  if (name in c.meta_group_bound) return;
  String failure = NULL;
  if (!c.stage_meta_group(failure)) _helper_refuse(c, name, site, failure);
  if (!(name in c.meta_group_bound))
    _helper_refuse(c, name, site, _helper_missing(c, name));
}
