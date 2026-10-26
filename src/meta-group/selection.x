/*  selection.x -- meta group selection

    Copyright (c) 2026 Gary William Flake.
*/

// group membership

/* Set when this process stages each unit's group itself; otherwise a
   project helper runs the group. */
static int meta_in_process = 0;

/** Enables in-process staging of `meta` groups for compiler sessions. */
void Compiler.stage_meta_in_process(void) { meta_in_process = 1; }

/** Answers whether a `meta` function or value belongs to the unit's group:
    a parse meets it outside a macro definition while the project meta build
    parses the unit or a session stages it.
*/
int Compiler.groups_meta(Compiler c) =>
  meta_cc && !c.macro_holes && (void *) c.meta_group &&
  (c.meta_build || (!c.meta_helper && X2C_NATIVE_MODULES && meta_in_process));

/** Answers whether a call of a project `meta` function waits for the
    translation: the project meta build's own parse has no helper yet. A
    loaded helper's parse calls the ordinary helper of its sources.
*/
int Compiler.meta_calls_wait(Compiler c) => c.meta_build && !c.meta_helper;

/** Records a native callable body `fn` in the unit's helper group. */
void Compiler.group_meta_function(Compiler c, List fn) {
  match (fn)
    case %(function ?spec (!set ?declarator (bind (binding ? ?(String name))
                                                  *)) ?): {
      Type type = %(declare $spec (bindings $declarator)).type_from_ast()
                    .canonicalize();
      c.meta_group.push(%(function $fn $name $type));
    }
}

/** Answers whether a `meta` body reaches the compiler itself: it names a
    compile-time-only function or a compiler operation, or constructs a
    template. Such a function has no runtime form.
*/
int Compiler.meta_reaches_compile_time(Compiler c, Var node) {
  if (node is not <list>) return 0;
  List syntax = node;
  match (syntax) {
    case %((!or tpl-call meta-call) *): return 1;
    case $source_identifier_content(%((binding ? ?name))): {
      if (name is not <string>) break;
      String spelling = name;
      // Expansion can insert a call typed by its macro definition.
      if (spelling in c.native_meta) c.bind_native_meta(spelling);
      return spelling in c.meta_comptime ||
             Compiler.supplies_native_meta(spelling);
    }
  }
  foreach (Var child in syntax)
    if (c.meta_reaches_compile_time(child)) return 1;
  return 0;
}

/** Closes compile-time-only calls across later meta definitions.
    Retained group bodies hold the bound calls, including literal insertions.
    Select runtime definitions only after that relation is complete.
*/
void Compiler.finish_meta_functions(Compiler c, Array nodes) {
  int grew = 1;
  while (grew) {
    grew = 0;
    foreach (List entry in c.meta_group)
      if ((entry ~= %(function ?fn ?(String name) ?)) &&
          !(name in c.meta_comptime) && c.meta_reaches_compile_time(fn)) {
        c.meta_comptime[name] = 1;
        grew = 1;
      }
  }
  int check_calls = 0;
  foreach (List entry in c.meta_group)
    if ((entry ~= %(function ? ?(String name) ?)) &&
        name in c.meta_comptime) check_calls = 1;
  int retained = 0;
  foreach (List node in nodes) {
    if (c.meta_is_comptime_only(node)) continue;
    if (check_calls) _check_runtime_meta_calls(c, node);
    nodes[retained++] = node;
  }
  nodes.resize(retained);
}

/* Reuse the ordinary call check with the parsed statement's origin after
   closure. Native and ordinary copies are absent from the staged group. */
static void _check_runtime_meta_calls(Compiler c, Var root) {
  List node;
  $ast.walk(root, node) {
    match (node) {
      case %(at ?(int origin) ?inner): {
        with (c.origin = origin) { _check_runtime_meta_calls(c, inner); }
        continue;
      }
      case %(call ?(List callee) ?): c.check_meta_call(callee, NULL);
    }
  }
}

// what the group reaches

/* The unit's definitions so far that the group can reach, in source order:
   directives, declarations, included providers, reached functions, and
   compile-time-only functions that the unit itself never emits. */
module Array _units(Compiler c) {
  String lib = %"$(x2c_get_root())/lib/";
  Array ordered = _runtime_includes(c, lib);
  Map later = _source_order(c, ordered, lib);
  Map reached = _roots(c, ordered, later);
  _close(ordered, reached, later);
  return _reachable(c, ordered, reached, later);
}

/* The runtime prelude declares more than `x2c.h` includes, and a body can
   name any of it, so the group includes each runtime unit the translation
   read, and the prelude and the compile-time surface when a collection
   pass has read none. The group copies the unit's declarations, so it
   defines the unit's header guard as the unit's source does, and the
   group headers of runtime providers precede the runtime headers. Each
   runtime header that would define a copied type is then skipped. */
static Array _runtime_includes(Compiler c, String lib) {
  Array ordered = [%(preproc $(%"#define $(c.header_guard())"))];
  int groups = ordered.len();
  foreach (String header in %("x2c.x" "meta.x"))
    ordered.push(%(preproc $(%"#include \"$header\"")));
  foreach ((String path, Var hash) in c.deps) {
    if (hash is <string> && String.startswith(hash, "search:")) continue;
    if (c.canonical_path(path) == c.canonical_path(c.filename)) continue;
    String dependency = path;
    if (dependency.startswith(lib) && dependency.endswith(".x") &&
        !("/" in dependency[lib.len():])) {
      Var index;
      if (meta_build_tables.try_get(Path.absolute(dependency), index))
        ordered.insert(
          groups++, %(preproc $(%"#include \"meta_group_$index.h\"")));
      else
        ordered.push(
          %(preproc $(%"#include \"$(Path.basename(dependency))\"")));
    }
  }
  return ordered;
}

/* Copies the unit's definitions in source order and returns, by address,
   those after a form the project meta build's parse skipped. A later
   definition may name what the skipped form declares, so none is a root:
   the group keeps a later variable only when a meta function reaches it,
   and a later function only as its prototype unless one does. */
static Map _source_order(Compiler c, Array ordered, String lib) {
  Map placeholders = _placeholders(c), later = {};
  int skipped = c.meta_build ? c.skipped_form - 1 : -1;
  for (int i = 0; i < c.unit_nodes.len(); i++) {
    Var node = _group_include(c, c.unit_nodes[i], lib);
    if (node is void) continue;
    List copy = _uninitialized(node, placeholders);
    if (skipped >= 0 && i >= skipped) later[(void *) copy] = 1;
    ordered.push(copy);
  }
  return later;
}

/* A later variable declaration, kept only when a meta function reaches
   one of its names. Types and directives stay. */
static int _optional(List item, Map later) {
  if (!((void *) item in later)) return 0;
  if (item ~= %(declare ?(Type spec) (bindings ? *)))
    return !spec.is_typedef();
  return 0;
}

// Whether `item` declares a name in `reached`.
static int _declares_reached(List item, Map reached) {
  match (item) case %(declare ? (bindings *rows)):
    foreach (List row in rows) {
      match (row) case %(op = ?bound ?): row = bound;
      if ((row ~= %(bind (binding ?identity ?) ?)) &&
          identity in reached) return 1;
    }
  return 0;
}

/* The values the project meta build's parse put in place of calls left for
   the translation, by address. */
static Map _placeholders(Compiler c) {
  Map placeholders = {};
  foreach (List entry in c.meta_group)
    match (entry) case %(later ?(List placeholder)):
      placeholders[(void *) placeholder] = 1;
  return placeholders;
}

/* A project's included provider uses its group header, which declares the
   types and native functions shared by the provider objects. */
static Var _group_include(Compiler c, Var node, String lib) {
  match (node) case %(preproc ?(String text)): {
    int angle = 0;
    String target = Compiler.preproc_include_target(text, angle);
    if (!target || !Path.is_x2c_source(target)) break;
    String path = c.sources.resolve_include(
      c.include_dirs, Path.dirname(c.filename), target, angle);
    Var index;
    if (path && meta_build_tables.try_get(Path.absolute(path), index))
      return %(preproc $(%"#include \"meta_group_$index.h\""));
    if (Path.is_file(%"$lib$target")) break;
    return void;
  }
  return node;
}

/* `node`, a declaration whose initializer holds a placeholder, without
   its initializers: a placeholder has the wrong type for C, and the
   group's copy never had the call's value. */
static Var _uninitialized(Var node, Map placeholders) {
  if (!_holds(node, placeholders)) return node;
  match (node)
    case %(declare ?spec (bindings *bindings)): {
      Array bare = [];
      foreach (List binding in bindings) {
        match (binding) case %(op = ?bound ?): binding = bound;
        bare.push(binding);
      }
      return %(declare $spec (bindings @(bare.list_free())));
    }
  return node;
}

/* Whether one of `placeholders`, compared by address, is `node` or lies
   within it. */
static int _holds(Var node, Map placeholders) {
  if (node is not <list>) return 0;
  List syntax = node;
  if ((void *) syntax in placeholders) return 1;
  foreach (Var child in syntax) if (_holds(child, placeholders)) return 1;
  return 0;
}

/* What the group reaches before following function bodies: each group
   function and what it names, and what every other definition names. A
   group function the unit's definitions lack joins them. */
static Map _roots(Compiler c, Array ordered, Map later) {
  Map present = {}, reached = {};
  Var identity, String name;
  foreach (List item in ordered)
    if (_function_identity(item, identity, name)) {
      present[identity] = 1;
      if (c.meta_build && !((void *) item in later) &&
          c.public_native_function(item, name))
        reached[identity] = 1;
    }
  foreach (List entry in c.meta_group)
    match (entry) case %(function ?fn *): {
      Ast.collect_binding_references(fn, reached);
      if (_function_identity(fn, identity, name) && !(identity in present))
        ordered.push(fn);
      reached[identity] = 1;
    }
  foreach (List item in ordered)
    if (!_function_identity(item, identity, name) && !_optional(item, later))
      Ast.collect_binding_references(item, reached);
  return reached;
}

/* A function or later variable reaches only what it names, so collecting
   from each reached one until nothing new is reached closes the set. */
static void _close(Array ordered, Map reached, Map later) {
  Map expanded = {};
  Var identity, String name;
  int grew = 1;
  while (grew) {
    grew = 0;
    foreach (List item in ordered) {
      Var key = (void *) item;
      if (key in expanded) continue;
      if (_function_identity(item, identity, name)
            ? !(identity in reached)
            : !_optional(item, later) || !_declares_reached(item, reached))
        continue;
      expanded[key] = 1;
      Ast.collect_binding_references(item, reached);
      grew = 1;
    }
  }
}

/* An unreached function keeps its prototype, which code generated for
   the unit's types, such as a protocol adapter, may name; the optimizer
   drops what nothing calls. A result with no base type came from a name
   the parse never declared, such as one a skipped form supplies, and has
   no C prototype. */
static Array _reachable(Compiler c, Array ordered, Map reached, Map later) {
  Array units = [];
  Var identity, String name;
  foreach (List item in ordered) {
    if (_optional(item, later) && !_declares_reached(item, reached)) continue;
    if (!_function_identity(item, identity, name) ||
        (identity in reached && (name != "main" || c.load_source)))
      units.push(item);
    else if (name != "main")
      match (item) case %(function ?spec ?declarator ?): {
        List prototype = %(declare $spec (bindings $declarator));
        if (prototype.type_from_ast().apply().base_type())
          units.push(prototype);
      }
  }
  return units;
}

module int _function_identity(List fn, Var &identity, String &name) {
  match (fn)
    case %(function ? (bind (binding ?id ?(String spelling)) *) ?): {
      identity = id;
      name = spelling;
      return 1;
    }
  return 0;
}

/** Answers whether a definition has public native linkage.
    Main is excluded because its process entry needs a separate adapter.
*/
int Compiler.public_native_function(
  Compiler c, List function, String name) =>
  name != "main" && !(%(function $name) in c.sym.file_statics()) &&
  !%(declare $(function.cadr()) (bindings $(function.caddr())))
     .type_from_ast().is_static();

// refusing a call

/** Returns why the group function `name` has no compile-time entry, from
    its type.
*/
String Compiler.meta_call_missing(Compiler c, String name) {
  Type type = NULL;
  foreach (List entry in c.meta_group)
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

/** Reports at `site` that the `meta` function `name` cannot run at compile
    time, and `why`.
*/
void Compiler.refuse_meta_call(
  Compiler c, String name, Token site, String why) {
  $fail.meta_group_function_unavailable(c, site, name, why);
}

/** Reports at `site` that the group function `name` cannot run at compile
    time when its result is a struct or union, which its type alone
    decides.
*/
void Compiler.refuse_record_meta_call(Compiler c, String name, Token site) {
  String missing = c.meta_call_missing(name);
  if (missing.startswith("a struct")) c.refuse_meta_call(name, site, missing);
}

/* Why the group cannot link, or NULL: a function it calls is a bodyless
   `meta` prototype that nothing supplies. */
module String _unbound(Compiler c) {
  foreach (List entry in c.meta_group)
    match (entry) case %(function ?fn *): {
      String name = _unbound_callee(c, fn);
      if (name) return %"no binding for $name";
    }
  return NULL;
}

/* The first name `node` reads that is a bodyless `meta` prototype nothing
   supplies, or NULL. */
static String _unbound_callee(Compiler c, Var node) {
  if (node is not <list>) return NULL;
  Var bound;
  match (node) case $source_identifier_content(%((binding ? ?name))): {
    if (name is not <string>) break;
    String spelling = name;
    String unbound = %"<unbound $spelling>";
    return unbound in c.meta_group_bound ||
           (spelling in c.native_meta &&
            !c.meta_binding(spelling, bound) &&
            !c.bind_native_meta(spelling)) ? spelling : NULL;
  }
  foreach (Var child in (List) node) {
    String name = _unbound_callee(c, child);
    if (name) return name;
  }
  return NULL;
}
