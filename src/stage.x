/*  stage.x -- staged meta groups and the values crossing into them

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function runs as native code the compiler stages from
    the unit's `meta` group. This file owns that group: what it reaches, its
    emission through the ordinary backend, the cached module it builds, and
    its binding into the unit's session. It also owns what crosses between
    that code and the program: the arguments a `$` call passes, evaluated
    from constants, captured syntax, and other `$` calls; the literal code a
    result becomes; and the rule that a function reaching a compiler
    operation has no runtime form.
*/
#pragma once
#include "compiler.x"

/* Staged groups load as native modules, which these platforms lack. */
#if defined(__COSMOPOLITAN__) || defined(_WIN32) || defined(__CYGWIN__)
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
#include "generate.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <limits.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
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

/* --- the deadline of a running meta call -------------------------------- */

/* The outermost running `$` call: its deadline in monotonic seconds, zero
   when none runs, and where to report it. A watchdog thread, started in
   each process at its first call, stops a call that passes its deadline.
   The thread reads only these C values, so it touches no runtime state. */
static volatile double watch_deadline = 0;
static int watch_depth = 0, watch_line = 0, watch_col = 0;
static char watch_file[512], watch_name[128];
static double watch_limit = -1;
static pid_t watch_pid = 0;

static double _watch_now(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return now.tv_sec + now.tv_nsec / 1e9;
}

static void *_watch_run(void *unused) {
  (void) unused;
  for (;;) {
    usleep(100000);
    double deadline = watch_deadline;
    if (!deadline || _watch_now() < deadline) continue;
    fprintf(stderr,
      "%s:%d:%d: macro: this meta call ran longer than %g s\n"
      "  note: function: %s\n"
      "  note: set X2C_META_TIMEOUT to a larger limit in seconds, or 0 "
      "for none\n",
      watch_file, watch_line, watch_col, watch_limit, watch_name);
    fflush(stderr);
    _exit(1);
  }
  return NULL;
}

/* The limit from `X2C_META_TIMEOUT`, 60 seconds by default; zero or less
   turns the watchdog off. */
static double _watch_limit(void) {
  String text = Env.get("X2C_META_TIMEOUT");
  return text ? atof(text) : 60.0;
}

/** Starts the deadline of the `meta` function `name` called at `site`,
    unless a call is already running. */
void Compiler.meta_watch_begin(Compiler c, String name, Token site) {
  if (watch_depth++) return;
  if (watch_limit < 0) watch_limit = _watch_limit();
  if (watch_limit <= 0) return;
  if (watch_pid != getpid()) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, _watch_run, NULL)) return;
    pthread_detach(thread);
    watch_pid = getpid();
  }
  snprintf(watch_file, sizeof watch_file, "%s",
           c.filename ? (char *) c.filename : "<input>");
  snprintf(watch_name, sizeof watch_name, "%s", (char *) name);
  watch_line = site ? site.line : 0;
  watch_col = site ? site.col : 0;
  watch_deadline = _watch_now() + watch_limit;
}

/** Ends the deadline `Compiler.meta_watch_begin` started. */
void Compiler.meta_watch_end(void) {
  if (--watch_depth == 0) watch_deadline = 0;
}

/* --- the unit's meta group, staged as native code ---------------------- */

/* The C compiler and x2c include directory that stage meta groups. */
static String meta_cc = NULL, meta_include_dir = NULL;

/* The runtime headers this compiler was built with, which a staged module
   shares because it calls the compiler's own runtime: a built checkout
   stage's `lib`, the checked-in bootstrap's, or else `include_dir`. */
static String _meta_headers(String include_dir) {
  String stage = x2c_stage_dir();
  if (stage && Path.is_file(%"$stage/lib/x2c.h")) return %"$stage/lib";
  String executable = x2c_get_executable(), root = x2c_get_root();
  if (executable && root && Path.basename(executable) == "x2c-bootstrap" &&
      Path.dirname(executable) == %"$root/bin")
    return %"$root/bootstrap/lib";
  return include_dir;
}

/** Selects the C compiler `cc` that stages the `meta` groups of the units
    this process translates, with the runtime headers this compiler was
    built with, found from its installed headers in `include_dir`. */
void Compiler.use_meta_toolchain(String cc, String include_dir) {
  meta_cc = cc;
  meta_include_dir = _meta_headers(include_dir);
  meta_cc.try_own();
  meta_include_dir.try_own();
}

/** Answers whether a `meta` function or value belongs to the unit's pending
    group: a parse meets it outside a macro definition. A `.xmacro` import,
    and each compiler that collects a segment of the unit, shares the unit's
    group. */
int Compiler.groups_meta(Compiler c) =>
  X2C_NATIVE_MODULES && meta_cc && !c.macro_holes && (void *) c.meta_group;

/* The C compiler flags of a staged module, besides its include
   directories: position-independent code, lightly optimized. */
static List _meta_flags(void) => %("-fsigned-char" "-fPIC" "-O1");

static int _function_identity(List fn, Var &identity, String &name) {
  match (fn)
    case %(function ? (bind (binding ?id ?(String spelling)) *) ?): {
      identity = id;
      name = spelling;
      return 1;
    }
  return 0;
}

/** Records the bodied `meta` function `fn` in the pending group. */
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
    to the unit, so a staged group places them where the import stands. */
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
    case %(ident (binding ? ?(String name))):
      return name in c.meta_comptime || Compiler.supplies_native_meta(name);
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
     can name any of it, so the module includes each runtime unit the
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
     drops what nothing staged calls. */
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

/* The entry of the group's module in the shape `x2c build --kind
   meta-module` writes: the stamp, `x2c_module_reset`, which reinitializes
   each mutable `meta static` value, and `x2c_module_targets`, a Map from
   the name of each group function and of the reset entry to a `Func` that
   calls it. */
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

static List _meta_group_entry(Compiler c, String stamp, Map initials) {
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
    c, %(void), "x2c_module_reset", %(block @{resets.list_free()}));
  Array targets = [];
  List named = %(("x2c_module_reset" ${reset.caddr().cadr()}
                  ((func ((void))) void)));
  foreach (List entry, c.meta_group)
    match (entry) case %(function ?fn ?(String name) ?(Type type) *):
      named = named.append(%(($name ${fn.caddr().cadr()} $type)));
  /* A function whose values have no Var form, such as C's `bool` or a
     record pointer, is called only from other staged code. */
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
  List stamp_binding = c.sym.introduce("x2c_module_stamp");
  String literal = %"\"$stamp\"";
  return %(
    (declare (const char)
      (bindings (op = (bind $stamp_binding ((dim)))
                     (expr (* char) (literal (* char) $literal)))))
    $reset
    ${_meta_entry_function(
        c, %("Map"), "x2c_module_targets",
        %(block (return ("Map") $table)))});
}

List Compiler.transform(Compiler compiler, List ast);

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

/* Emits the group through the ordinary backend as `(hfile htext cfile
   ctext)`, or returns NULL with `failure` set when it does not lower. The
   emission borrows the unit's bindings and types and leaves the unit as it
   found it: generated names, literal caches, helpers, initializers, and
   semantic rows are its own. */
static List _meta_group_code(Compiler c, String stamp, String &failure) {
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
    _.fixed = {};
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
    _.filename = "group.x";
    _.diagnostics = Diagnostics.new(NULL, 1);
  }
  List code = NULL;
  try {
    List binding = c.sym.introduce("x2c_template_call");
    Type type = %((func (("Var") ("List"))) "List");
    List callee = %(expr $type (ident $binding));
    for (int i = 0; i < (int) units.len(); i++)
      units[i] = _meta_template_calls(c, units[i], callee);
    int after = 0;
    while (after < (int) units.len() &&
           ((List) units[after]).car() == <preproc>)
      after++;
    units.insert(after, %(declare ("List") (bindings (bind $binding
      ((fnmod (params (param ("Var") (bind () ()))
                      (param ("List") (bind () ())))))))));
    Map initials = _meta_initial_copies(c, units);
    foreach (Var unit, _meta_group_entry(c, stamp, initials))
      units.push(unit);
    /* The unit's protocol adapters and their registration belong to the
       program; staged code reaches the runtime's own. */
    List ast = c.transform(units.list_free());
    code = generate_code_text(c, ast, "group");
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

/* The identity of the C compiler at `cc`: its path and content hash. */
static String _meta_cc_identity(String cc) {
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

/* Builds the group's native module under the cache root, named by the
   SHA-256 of its emitted C, the compiler stamp, the C compiler's identity,
   the flags, and the runtime headers' directory, or reuses the module an
   earlier translation built. Returns its path, or NULL with `failure` set
   when there is no cache or the group does not build. */
static String _stage_meta_group(Compiler c, String &failure) {
  String root = script_cache_root(), stamp = build_module_stamp();
  if (!root || !stamp) {
    failure = "native modules need a cache directory and a known compiler";
    return NULL;
  }
  List code = _meta_group_code(c, stamp, failure);
  if (!code) return NULL;
  (String hfile, String header, String cfile, String source) = code;
  List flags = _meta_flags();
  String compiler = _meta_cc_identity(meta_cc);
  String key = String.sha256(
    %"$header\n$source\n$stamp\n$compiler\n${flags.repr()}\n$meta_include_dir");
  String directory = %"$root/meta/$key";
  String module = %"$directory/group.module";
  if (Path.is_file(module)) return module;
  String output = %"$module.${"%ld".printf((long) getpid())}";
  failure = %"cannot write the module under $directory";
  try Path.make_dirs(directory);
  catch %((!or not-found io-fail) *): return NULL;
  /* Workers that reach the same group wait for the first to build it. */
  int lock = file_lock(%"$directory/lock", 1);
  defer close(lock);
  if (Path.is_file(module)) return module;
  try {
    Path.write_text(%"$directory/$hfile", header);
    Path.write_text(%"$directory/$cfile", source);
  }
  catch %((!or not-found io-fail) *): return NULL;
  Toolchain linker = toolchain_new(meta_cc, NULL, NULL, NULL, NULL, 0, 0);
  String unit = %"$directory/$cfile";
  ToolAction action = linker.module_action(
    output, %(@flags "-iquote" $directory "-iquote" $meta_include_dir $unit));
  String printed = NULL, errors = NULL;
  if (tool_capture(action.arguments, printed, errors)) {
    failure = _meta_cc_error(errors);
    if (!failure.contains(directory))
      failure = %"$failure; the group's C is in $directory";
    return NULL;
  }
  try Path.move_to(output, module);
  catch %((!or not-found io-fail) *): return NULL;
  return module;
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

static String _load_meta_group(Compiler c, String &failure);

/** Binds each unbound function of the pending group to its staged native
    code when `name` is pending, after reinitializing the module's `meta
    static` values for this unit in the unit's meta Scope. Returns whether
    `name` is now native; a function that cannot run is reported at
    `site`. */
int Compiler.bind_meta_group(Compiler c, String name, Token site) {
  if (!c.groups_meta() || name in c.meta_group_bound) return 0;
  Type type = NULL;
  foreach (List entry, c.meta_group)
    match (entry) case %(function ? ?(String target) ?(Type own)):
      if (target == name) type = own;
  if (!type) return 0;
  /* A record returned by value has no Var form of its own; its Func form
     would hand back the compiler's copy of it. */
  Type result = type.apply();
  if (!c.sym.is_var_type(result)) result = c.sym.resolve_key(result);
  String reason = result && result.is_aggregate()
    ? "a struct or union result has no compile-time value; return its "
      "fields as a List or Map"
    : NULL;
  String failure = NULL;
  if (!reason && !_load_meta_group(c, failure)) reason = failure;
  if (!reason && !(name in c.meta_group_bound))
    reason = result && result.is_pointer()
      ? "an address result has no compile-time value; return data built "
        "from the pointed-to values"
      : "a parameter or the result has no Var form, such as C's bool; use "
        "int, a String, a Symbol, or a List";
  if (reason)
    c.report_error(
      <macro>, "this function cannot run at compile time", site,
      %("function: $name" "reason: $reason"));
  return 1;
}

/** Stages the unit's pending `meta` group now, for a caller such as the
    REPL that adds functions to `meta_group` itself, and binds each group
    function in the session. Returns the loaded module, or NULL with
    `failure` set when the group does not stage. */
String Compiler.stage_meta_group(Compiler c, String &failure) {
  if (!c.groups_meta()) {
    failure = "native modules are unavailable";
    return NULL;
  }
  return _load_meta_group(c, failure);
}

/* Stages and loads the pending group and binds each of its functions not
   yet bound. Returns the module, or NULL with `failure` set. */
static String _load_meta_group(Compiler c, String &failure) {
  failure = _meta_group_unbound(c);
  String module = failure ? NULL : _stage_meta_group(c, failure);
  if (!module) return NULL;
  module = Compiler.load_native_module(module);
  Map targets = Compiler.native_module_targets(module);
  if (!(module in c.meta_group_bound)) {
    c.meta_group_bound[module] = 1;
    Scope.push(&c.meta_scope);
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
