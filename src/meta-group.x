/*  meta-group.x -- a unit's meta group, emitted as C

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function a project defines runs as native code in the
    project's helper program, which the project meta build compiles from
    each unit's `meta` group before translation (`meta-project.x`). This
    file owns that group: what it reaches, its emission through the
    ordinary backend, and the files the project meta build reads. It also
    stages a session's group in process as a native module.
*/
#pragma once
#include "compiler.x"

/* `generate.x` reaches this unit through `emit.x` and `transform.x`, so
   including it here would make a cycle. */
List Compiler.transform(Compiler compiler, List ast);
List generate_code_text(Compiler c, List ast, String basename);

/* In-process staging loads native modules, which these platforms lack. */
#if defined(_WIN32) || defined(__CYGWIN__)
#define X2C_NATIVE_MODULES 0
#else
#define X2C_NATIVE_MODULES 1
#endif

#pragma private
#include "type.x"
#include "macros.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <unistd.h>

// the meta toolchain

/* The C compiler and x2c include directory that build meta code. */
static String meta_cc = NULL, meta_include_dir = NULL;

/** Selects the C compiler `cc` that builds the `meta` code of the units
    this process translates, with the runtime headers this compiler was
    built with, found from its installed headers in `include_dir`. */
void Compiler.use_meta_toolchain(String cc, String include_dir) {
  meta_cc = cc;
  meta_include_dir = _runtime_headers(include_dir);
  meta_cc.try_own();
  meta_include_dir.try_own();
}

/* The runtime headers this compiler was built with, which meta code shares
   because it calls the compiler's own runtime: a built checkout stage's
   `lib`, the checked-in bootstrap's, or else `include_dir`. */
static String _runtime_headers(String include_dir) {
  String stage = x2c_stage_dir();
  if (stage && Path.is_file(%"$stage/lib/x2c.h")) return %"$stage/lib";
  String executable = x2c_get_executable(), root = x2c_get_root();
  if (executable && root && Path.basename(executable) == "x2c-bootstrap" &&
      Path.dirname(executable) == %"$root/bin")
    return %"$root/bootstrap/lib";
  return include_dir;
}

/** Returns the C compiler and the runtime header directory that build
    `meta` code, or NULL before `Compiler.use_meta_toolchain`. */
String Compiler.meta_cc(String &include_dir) {
  include_dir = meta_include_dir;
  return meta_cc;
}

/** Returns the identity of the C compiler at `cc`: its path and content
    hash. */
String Compiler.meta_cc_identity(String cc) {
  String path = "/" in cc ? cc : x2c_find_program(cc);
  int ok = path != NULL;
  uint64_t hash = UINT64_C(1469598103934665603);
  if (ok) hash = x2c_fnv_file(hash, path, ok);
  return ok ? "%s %016llx".printf(path, (unsigned long long) hash) : cc;
}

/** Runs `arguments`, a C compiler command building the group C in
    `directory`, and returns NULL, or else its first error, which names
    `directory` when a group's C is the cause. */
String Compiler.meta_cc_run(List arguments, String directory) {
  String printed = NULL, errors = NULL;
  if (!tool_capture(arguments, printed, errors)) return NULL;
  String failure = _cc_error(errors);
  return !directory || directory in failure ? failure
    : %"$failure; the group's C is in $directory";
}

/* The C compiler's first located error in `errors`, or else its first
   line, joined with the next when it ends in a colon, as a linker's
   undefined-symbol report does. */
static String _cc_error(String errors) {
  Array lines = [];
  foreach (String line, (errors ? errors : "").split("\n")) {
    String text = line.strip(NULL);
    if (!text) continue;
    if (": error: " in text && !text.startswith("clang:") &&
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

// group membership

/* Set when this process stages each unit's group itself; otherwise a
   project helper runs the group. */
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

/** Records the point where a compile-time import added its `meta`
    definitions to the unit, so the group places them where the import
    stands. */
void Compiler.record_meta_import(Compiler c) {
  if (c.groups_meta())
    c.meta_group.push(
      %(import ${c.unit_nodes ? c.unit_nodes.len() : 0} ${c.meta_defs.len()}));
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
  foreach (Var child, syntax) if (c.meta_reaches_compile_time(child)) return 1;
  return 0;
}

// emitting the group

/* Emits the group through the ordinary backend as `(hfile htext cfile
   ctext)` named by `stem`, with exported names ending in `suffix`, or
   returns NULL with `failure` set when it does not lower. The emission
   borrows the unit's bindings and types and leaves the unit as it found
   it: generated names, literal caches, helpers, initializers, and semantic
   rows are its own. */
static List _code(
  Compiler c, String stamp, String stem, String suffix, String &failure) {
  Array units = _units(c);
  /* The backend reads more of the unit's compiler than a child from
     `Compiler.new_shared` inherits, such as its tokenizer, runtime header
     and literal policy, init names, origin, and Lisp session, so the
     emission runs on the unit's own compiler and restores it after. */
  struct Compiler saved = *c;
  struct GenNames names = *c.names;
  SymTxn transaction = c.begin_semantic_transaction();
  _isolate(c, saved, names, stem);
  List code = NULL;
  try {
    List lowered = _lower(c, units, stamp, suffix);
    /* The unit's protocol adapters and their registration belong to the
       program; group code reaches the runtime's own. */
    List ast = c.transform(lowered);
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

/* Gives the emission its own copies of the state it adds to, taken from
   the unit's `saved` compiler and `names`, and fresh state where it starts
   from nothing, so restoring those undoes the emission. */
static void _isolate(
  Compiler c, struct Compiler &saved, struct GenNames &names, String stem) {
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
}

/* The group's units as the backend takes them: every template call becomes
   a call of `x2c_template_call`, which is declared after the leading
   directives; a meta build's native calls go through their modules; and
   the entry follows. */
static List _lower(Compiler c, Array units, String stamp, String suffix) {
  List binding = c.sym.introduce("x2c_template_call");
  Type type = %((func (("Var") ("List"))) "List");
  List callee = %(expr $type (ident $binding));
  for (int i = 0; i < (int) units.len(); i++)
    units[i] = _template_calls(c, units[i], callee);
  if (c.meta_build) _native_lookups(c, units);
  int after = _after_directives(units);
  units.insert(
    after,
    %(declare ("List") (bindings (bind $binding
      ((fnmod (params (param ("Var") (bind () ()))
                      (param ("List") (bind () ())))))))));
  Map initials = _initial_copies(c, units);
  foreach (Var unit, _entry(c, stamp, initials, suffix)) units.push(unit);
  return units.list_free();
}

/* A meta build calls a native module's function through the address
   `x2c_meta_native_symbol` finds in the module. */
static void _native_lookups(Compiler c, Array units) {
  Type lookup_type = %((func (("String") ("String"))) * void);
  List lookup_binding = c.sym.introduce("x2c_meta_native_symbol");
  List lookup = %(expr $lookup_type (ident $lookup_binding));
  List (base, mods) = lookup_type.declaration_parts();
  units.push(%(declare $base (bindings (bind $lookup_binding $mods))));
  for (int i = 0; i < (int) units.len(); i++)
    units[i] = _native_targets(c, units[i], lookup);
}

static int _after_directives(Array units) {
  int after = 0;
  while (after < (int) units.len() &&
         ((List) units[after]).car() == <preproc>)
    after++;
  return after;
}

// what the group reaches

/* The unit's definitions so far that the group can reach, in source order:
   every directive and declaration, the imported `meta` definitions where
   their import stands, each function the group reaches, and the group's
   compile-time-only functions, which the unit itself never emits. */
static Array _units(Compiler c) {
  String lib = %"${x2c_get_root()}/lib/";
  Array ordered = _runtime_includes(c, lib);
  _source_order(c, ordered, lib);
  Map reached = _roots(c, ordered);
  _close(ordered, reached);
  return _reachable(ordered, reached);
}

/* The runtime prelude declares more than `x2c.h` includes, and a body can
   name any of it, so the group includes each runtime unit the translation
   read, and the prelude and the compile-time surface when a collection
   pass has read none. */
static Array _runtime_includes(Compiler c, String lib) {
  Array ordered = [];
  foreach (String header, %("x2c.x" "meta.x"))
    ordered.push(%(preproc ${%"#include \"$header\""}));
  foreach (Var (path, _), c.deps) {
    String dependency = path;
    if (dependency.startswith(lib) && dependency.endswith(".x") &&
        !dependency[lib.len():].contains("/"))
      ordered.push(
        %(preproc ${%"#include \"${Path.basename(dependency)}\""}));
  }
  return ordered;
}

/* Appends the unit's directives and declarations with each import's `meta`
   definitions where the import stands, then the imports' remaining
   definitions. Collection parses no bodies, so its group holds only
   imports. */
static void _source_order(Compiler c, Array ordered, String lib) {
  Map placeholders = _placeholders(c);
  int flushed = 0, count = c.unit_nodes ? c.unit_nodes.len() : 0;
  for (int i = 0; i <= count; i++) {
    _imports_at(c, ordered, i, flushed);
    if (i < count && !_local_include(c.unit_nodes[i], lib))
      ordered.push(_uninitialized(c.unit_nodes[i], placeholders));
  }
  for (; flushed < (int) c.meta_defs.len(); flushed++)
    ordered.push(c.meta_defs[flushed]);
}

/* The values the project meta build's parse put in place of calls left for
   the translation, by address. */
static Map _placeholders(Compiler c) {
  Map placeholders = {};
  foreach (List entry, c.meta_group)
    match (entry) case %(later ?(List placeholder)):
      placeholders[%"${(long) (void *) placeholder}"] = 1;
  return placeholders;
}

/* Appends the imported definitions of each import that stands before unit
   node `i`; `flushed` counts the definitions appended so far. */
static void _imports_at(Compiler c, Array ordered, int i, int &flushed) {
  foreach (List entry, c.meta_group)
    match (entry)
      case %(import ?(int at) ?(int end)):
        if (at == i)
          for (; flushed < end; flushed++) ordered.push(c.meta_defs[flushed]);
}

/* Whether `node` includes an x2c unit outside the runtime in `lib`, whose
   header its own translation writes: a group compiles without it. */
static int _local_include(Var node, String lib) {
  match (node)
    case %(preproc ?(String text)):
      if (text.startswith("#include \"") && text.endswith(".x\"")) {
        String name = text[10:text.len() - 1];
        return !Path.is_file(%"$lib$name");
      }
  return 0;
}

/* `node`, a declaration whose initializer holds a placeholder, without
   its initializers: a placeholder has the wrong type for C, and the
   group's copy never had the call's value. */
static Var _uninitialized(Var node, Map placeholders) {
  if (!_holds(node, placeholders)) return node;
  match (node)
    case %(declare ?spec (bindings *bindings)): {
      Array bare = [];
      foreach (List binding, bindings) {
        match (binding) case %(op = ?bound ?): binding = bound;
        bare.push(binding);
      }
      return %(declare $spec (bindings @{bare.list_free()}));
    }
  return node;
}

/* Whether one of `placeholders`, compared by address, is `node` or lies
   within it. */
static int _holds(Var node, Map placeholders) {
  if (node is not <list>) return 0;
  if (%"${(long) (void *) (List) node}" in placeholders) return 1;
  foreach (Var child, (List) node) if (_holds(child, placeholders)) return 1;
  return 0;
}

/* What the group reaches before following function bodies: each group
   function and what it names, and what every other definition names. A
   group function the unit's definitions lack joins them. */
static Map _roots(Compiler c, Array ordered) {
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
  return reached;
}

/* A function reaches only what it names, so collecting from each reached
   function until nothing new is reached closes the set. */
static void _close(Array ordered, Map reached) {
  Map expanded = {};
  Var identity, String name;
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
}

/* An unreached function keeps its prototype, which code generated for
   the unit's types, such as a protocol adapter, may name; the optimizer
   drops what nothing calls. */
static Array _reachable(Array ordered, Map reached) {
  Array units = [];
  Var identity, String name;
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

static int _function_identity(List fn, Var &identity, String &name) {
  match (fn)
    case %(function ? (bind (binding ?id ?(String spelling)) *) ?): {
      identity = id;
      name = spelling;
      return 1;
    }
  return 0;
}

// rewriting calls

/* `node` with each template call replaced by a call of `x2c_template_call`,
   named by `callee`, on its template and its arguments as Vars. */
static Var _template_calls(Compiler c, Var node, List callee) {
  if (node is not <list>) return node;
  match (node)
    case %(expr ?type (tpl-call ?stored (args *arguments))): {
      List values = %(nil);
      foreach (Var argument, arguments.reverse())
        values = %(expr ("List") (cons ${c.convert_expression(
          _template_calls(c, argument, callee), %("Var"))} $values));
      List template = stored is <list>
        ? c.convert_expression(c.cache_literal_list(stored), %("Var"))
        : %(expr ("Var") ${c.cache_literal_var(stored.str())});
      return %(expr $type (call $callee (args $template $values)));
    }
  Array parts = [];
  foreach (Var part, (List) node) parts.push(_template_calls(c, part, callee));
  return parts.list_free();
}

/* `node` with each use of a native module's function made through the
   address `lookup` finds in that module. A native module's C target lives
   in the module, not in the helper. */
static Var _native_targets(Compiler c, Var node, List lookup) {
  if (node is not <list>) return node;
  match (node) {
    case %(expr ?(Type result)
           (call (!set ?callee
             (expr ? (ident (binding ? ?(String name)))))
             (args *arguments))): {
      List call = _native_call(c, callee, name, arguments, lookup);
      if (call) return c.convert_expression(call, result);
    }
    case %(expr ?(Type type) (ident (binding ? ?(String name)))): {
      List symbol = _native_symbol(c, type, name, lookup);
      if (symbol) return symbol;
    }
  }
  Array parts = [];
  foreach (Var part, (List) node) parts.push(_native_targets(c, part, lookup));
  return parts.list_free();
}

/* A call of the native function `callee`, or NULL when no native module
   supplies it. A Func argument the module takes as a Var is passed boxed.
*/
static List _native_call(
  Compiler c, Var callee, String name, List arguments, List lookup) {
  Type native = NULL;
  if (!(name in c.native_meta) || !c.native_meta_module(name, native))
    return NULL;
  Array values = [];
  List declared = c.func_signature(callee.list().cadr()).car().list()
                   .cadr();
  List parameters = native.car().list().cadr();
  foreach (List argument, arguments) {
    argument = _native_targets(c, argument, lookup);
    if (_boxes_func(c, declared.car(), parameters.car()))
      argument = c.convert_expression(
        c.convert_expression(argument, %("Func")), %("Var"));
    values.push(argument);
    declared = declared.cdr();
    parameters = parameters.cdr();
  }
  List target = _native_targets(c, callee, lookup);
  return c.resolve_expression(
    %(expr () (call $target (args @{values.list_free()}))), NULL);
}

/* Whether the compiler declares a parameter `Func` that the native module
   declares `Var`. */
static int _boxes_func(Compiler c, List declared, List parameter) =>
  c.sym.normalize_declared_type(declared).equal(
    c.sym.normalize_declared_type(%("Func"))) &&
  c.sym.normalize_declared_type(parameter).equal(
    c.sym.normalize_declared_type(%("Var")));

/* The native function `name` of `type` read through its module's address,
   or NULL when no native module supplies it. The read keeps the function
   type of the module that supplied the compiler's binding. */
static List _native_symbol(Compiler c, Type type, String name, List lookup) {
  if (!type.is_function() || !(name in c.native_meta)) return NULL;
  String module = c.native_meta_module(name, type);
  if (!module) return NULL;
  c.add_translation_dependency(module);
  Type pointer = type.reference();
  List target = %(expr (* void) (call $lookup
    (args ${x2c_literal_string(module)}
          ${x2c_literal_string(name)})));
  return %(expr $pointer (cast $pointer $target));
}

// the group's entry

/* A braced initializer may name a type C cannot spell again, such as an
   anonymous struct, so each group static with one is declared beside an
   unchanging copy that `x2c_module_reset` assigns from. Replaces those
   declarations in `units` and returns each copy's expression by the
   static's binding. */
static Map _initial_copies(Compiler c, Array units) {
  Map copies = {};
  foreach (List entry, c.meta_group)
    match (entry)
      case %(static (!set ?declaration (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding ?mods))
                                     ?initializer))))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (<const> in type || type.is_array() || !_braced(initializer))
          continue;
        List copy = c.sym.introduce(%"${binding.list().last()}_x2c_initial");
        for (int i = 0; i < (int) units.len(); i++)
          if (units[i].equal(declaration))
            units[i] = %(declare $spec (bindings
              (op = $bound $initializer)
              (op = (bind $copy $mods) $initializer)));
        copies[binding] = %(expr $type (ident $copy));
      }
  return copies;
}

static int _braced(Var node) {
  if (node is not <list>) return 0;
  if (((List) node).car() == <composite>) return 1;
  foreach (Var part, (List) node) if (_braced(part)) return 1;
  return 0;
}

/* The group's entry in the shape `x2c build --kind meta-module` writes:
   the stamp, `x2c_module_reset`, which reinitializes each mutable `meta
   static` value, and `x2c_module_targets`, a Map from the name of each
   group function and of the reset entry to a `Func` that calls it. The
   exported names end in `suffix`, so several groups link into one
   program. */
static List _entry(Compiler c, String stamp, Map initials, String suffix) {
  List resets = _resets(c, initials);
  List reset = _entry_function(
    c, %(void), %"x2c_module_reset$suffix", %(block @resets));
  List table = _targets(c, _named(c, reset));
  List stamp_binding = c.sym.introduce(%"x2c_module_stamp$suffix");
  String literal = %"\"$stamp\"";
  return %(
    (declare (const char)
      (bindings (op = (bind $stamp_binding ((dim)))
                     (expr (* char) (literal (* char) $literal)))))
    $reset
    ${_entry_function(
      c, %("Map"), %"x2c_module_targets$suffix",
      %(block (return ("Map") $table)))});
}

/* An assignment of each mutable `meta static` value's initializer, or of
   the unchanging copy `initials` holds for a braced one. */
static List _resets(Compiler c, Map initials) {
  Array resets = [];
  foreach (List entry, c.meta_group)
    match (entry)
      case %(static (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding *))
                                     ?initializer)))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (<const> in type || type.is_array()) continue;
        Var initial;
        if (initials.try_get(binding, initial)) initializer = initial;
        resets.push(
          %(stmnt (expr $type
            (op = (expr $type (ident $binding)) $initializer))));
      }
  return resets.list_free();
}

/* The reset entry and each group function as `(name binding type)`. */
static List _named(Compiler c, List reset) {
  List named = %(("x2c_module_reset" ${reset.caddr().cadr()}
                  ((func ((void))) void)));
  foreach (List entry, c.meta_group)
    match (entry) case %(function ?fn ?(String name) ?(Type type) *):
      named = named.append(%(($name ${fn.caddr().cadr()} $type)));
  return named;
}

/* The Map `x2c_module_targets` returns, with a Func for each of `named`.
   A function whose values have no Var form, such as C's `bool` or a
   record pointer, is called only from other group code. */
static List _targets(Compiler c, List named) {
  Array targets = [];
  int count = 0;
  foreach (List row, named) {
    (String name, List binding, Type type) = row;
    List function = NULL;
    try function = c.convert_expression(
      %(expr $type (ident $binding)), %("Func"));
    catch %(malformed *): continue;
    targets.push(_call("String_var", %(${x2c_literal_string(name)})));
    targets.push(_call("Func_var", %($function)));
    count++;
  }
  List update = _call(
    "Map_update_n",
    %(${_call("Map_new", %())} ${x2c_literal_int(count)}
      @{targets.list_free()}));
  return c.bind_syntax(update, AST_EXPRESSION, NULL);
}

/* A function definition with no parameters. */
static List _entry_function(
  Compiler c, List result, String name, List body) =>
  %(function $result
      (bind ${c.sym.introduce(name)}
        ((fnmod (params (param (void) (bind () ()))))))
      $body);

static List _call(String name, List arguments) =>
  %(expr () (call (expr () (ident ("x2c.ident" $name))) (args @arguments)));

// refusing a call

/** Returns why the group function `name` has no compile-time entry, from
    its type. */
String Compiler.meta_call_missing(Compiler c, String name) {
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

/** Reports at `site` that the `meta` function `name` cannot run at compile
    time, and `why`. */
void Compiler.refuse_meta_call(
  Compiler c, String name, Token site, String why) {
  c.report_error(
    <macro>, "this function cannot run at compile time", site,
    %("function: $name" "reason: $why"));
}

/** Reports at `site` that the group function `name` cannot run at compile
    time when its result is a struct or union, which its type alone
    decides. */
void Compiler.refuse_record_meta_call(Compiler c, String name, Token site) {
  String missing = c.meta_call_missing(name);
  if (missing.startswith("a struct")) c.refuse_meta_call(name, site, missing);
}

/* Why the group cannot link, or NULL: a function it calls is a bodyless
   `meta` prototype that nothing supplies. */
static String _unbound(Compiler c) {
  foreach (List entry, c.meta_group)
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
  match (node) case %(ident (binding ? ?(String name))): {
    String unbound = %"<unbound $name>";
    return unbound in c.meta_group_bound ||
           (name in c.native_meta && !c.macro_lisp.try_get(name, bound) &&
            !c.bind_native_meta(name)) ? name : NULL;
  }
  foreach (Var child, (List) node) {
    String name = _unbound_callee(c, child);
    if (name) return name;
  }
  return NULL;
}

// the project meta build

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
  String failure = _unbound(c);
  List code = failure ? NULL : _code(
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

// a session group, staged in process

/* Holds what staged `meta static` values allocate. */
static Scope session_meta_scope = NULL;

/** Binds the session's group function `name` when it is not bound yet, by
    staging the group, and reports at `site` a function that cannot run. */
void Compiler.bind_meta_group(Compiler c, String name, Token site) {
  if (name in c.meta_group_bound) return;
  String failure = NULL;
  if (!c._stage(failure)) c.refuse_meta_call(name, site, failure);
  if (!(name in c.meta_group_bound))
    c.refuse_meta_call(name, site, c.meta_call_missing(name));
}

/* Builds and loads the session's `meta` group, then binds each
   group function in the session not yet bound. Returns the loaded module,
   or NULL with `failure` set when the group does not stage. */
static String Compiler._stage(Compiler c, String &failure) {
  failure = c.groups_meta() ? _unbound(c) : "native modules are unavailable";
  String module = failure ? NULL : _module(c, failure);
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

/* The group's native module under the cache root, named by the SHA-256 of
   its emitted C, the compiler stamp, the C compiler's identity, and the
   runtime headers' directory: one an earlier submission built, or else a
   new build. Returns its path, or NULL with `failure` set when there is no
   cache or the group does not build. */
static String _module(Compiler c, String &failure) {
  String root = script_cache_root(), stamp = build_module_stamp();
  if (!root || !stamp) {
    failure = "native modules need a cache directory and a known compiler";
    return NULL;
  }
  List code = _code(c, stamp, "group", "", failure);
  if (!code) return NULL;
  (String hfile, String header, String cfile, String source) = code;
  String key = String.sha256(
    %"$header\n$source\n$stamp\n" +
    %"${Compiler.meta_cc_identity(meta_cc)}\n$meta_include_dir");
  String directory = %"$root/meta/$key";
  String module = %"$directory/group.module";
  if (Path.is_file(module)) return module;
  failure = _build_module(directory, module, code);
  return failure ? NULL : module;
}

/* Compiles the group `code` in `directory` into `module`, and returns NULL
   or the C compiler's error. The output carries this process's id until it
   moves into place. */
static String _build_module(String directory, String module, List code) {
  (String hfile, String header, String cfile, String source) = code;
  String output = %"$module.${"%ld".printf((long) getpid())}";
  Path.make_dirs(directory);
  Path.write_text(%"$directory/$hfile", header);
  Path.write_text(%"$directory/$cfile", source);
  Toolchain linker = toolchain_meta(meta_cc);
  List arguments = linker.module_action(
    output,
    %("-fsigned-char" "-fPIC" "-O0" "-iquote" $directory
      "-iquote" $meta_include_dir ${%"$directory/$cfile"})).arguments;
  String failure = Compiler.meta_cc_run(arguments, directory);
  if (!failure) Path.move_to(output, module);
  return failure;
}
