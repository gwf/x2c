/*  meta-group.x -- a unit's meta group, emitted as C

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function a project defines runs as native code: in the
    project's helper program, which the project meta build compiles from
    each unit's `meta` group before translation (`meta-project.x`), or in a
    native module that a session stages in process. This module owns the
    group, from the functions it holds to the C it emits.
*/
#pragma once
#include "compiler.x"

/* In-process staging loads native modules, which these platforms lack. */
#if defined(_WIN32) || defined(__CYGWIN__)
#define X2C_NATIVE_MODULES 0
#else
#define X2C_NATIVE_MODULES 1
#endif

#include "grammar.x"
#include "ast-rewrite.x"
#include "type.x"
#include "generate.x"
#include "macros.x"
#include "utils.x"
#include "toolchain.x"
#include "transform.x"
#include <unistd.h>

// diagnostics

static macro Stmt $fail.meta_group_main_signature(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "loaded main must take void or (int, char **) and return int",
    $site, NULL);

static macro Stmt $fail.meta_group_function_unavailable(
  Expr $c, Expr $site, Expr $name, Expr $why) {
  $c.report_error(
    <macro>,
    "this function cannot run at compile time",
    $site, %("function: ${$name}" "reason: ${$why}"));
}

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
  String stage = Compiler.stage_dir();
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
  String path = "/" in cc ? cc : Env.find_program(cc);
  String hash = Path.content_identity(path);
  return hash ? %"$path $hash" : cc;
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
    parses the unit or a session stages it. */
int Compiler.groups_meta(Compiler c) =>
  meta_cc && !c.macro_holes && (void *) c.meta_group &&
  (c.meta_build || (!c.meta_helper && X2C_NATIVE_MODULES && meta_in_process));

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

// loaded program entries

/* Parameter arrays have pointer calling conventions, and typedef spellings
   do not change the two standard main signatures. */
static int _main_arity(Compiler c, Type type) {
  List parameters = NULL;
  Type result = NULL;
  type.function_parts(parameters, result);
  if (c.sym.normalize_declared_type(result).canonicalize() != %(int))
    return -1;
  if (!parameters) return 0;
  if (parameters.len() != 2) return -1;
  Type count = c.sym.normalize_declared_type(parameters.car()).canonicalize();
  Type values = c.sym.normalize_declared_type(parameters.cadr());
  if (values.is_array()) values = values.dereference().reference();
  return count == %(int) && values.canonicalize() == %(* * char) ? 2 : -1;
}

/* Keep the source binding and calling convention for recursion and other
   native callers. Only the helper's public entry takes independent data. */
static List _loaded_entry(Compiler c, List binding, Type type) {
  int arity = _main_arity(c, type);
  if (arity < 0)
    $fail.meta_group_main_signature(c, NULL);
  c.ensure_macro_lisp();
  List entry = c.sym.introduce(c.fresh_name("loaded_entry"));
  List target = %(expr $type (ident $binding));
  if (!arity)
    return c.bind_syntax(
      $!Unit{ static int $entry(void) { return $target(); } }, <unit>, NULL);
  return c.bind_syntax(
    $!Unit{
      static int $entry(Array values) {
        int count = values.len();
        char **argv = Scope.calloc((size_t) count + 1, sizeof(char *));
        for (int i = 0; i < count; i++) {
          String text = values[i];
          size_t size = text.len();
          argv[i] = Scope.calloc(size + 1, 1);
          if (size) memcpy(argv[i], (char *) text, size);
        }
        return $target(count, argv);
      }
    }, <unit>, NULL);
}

/** Exposes a loaded unit's main through the ordinary helper target table.
    Native calls retain its declared signature; the public argc/argv entry
    takes an Array of Strings. A renamed main still returns zero on falling
    through its closing brace. Source text and tokens are unchanged. */
void Compiler.prepare_loaded_main(Compiler c, Array nodes) {
  for (int i = 0; i < nodes.len(); i++)
    match (nodes[i])
      case %(function ?spec (!set ?declarator
              (bind (!set ?binding (binding ? "main")) *)) (block *body)): {
        Type type = %(declare $spec (bindings $declarator)).type_from_ast();
        List entry = _loaded_entry(c, binding, type);
        nodes[i] = %(function $spec $declarator
          (block @body (return (int) ${$!int{ 0 }})));
        for (int j = c.meta_group.len() - 1; j >= 0; j--)
          if (List.match(c.meta_group[j], %(function ? "main" ?)))
            c.meta_group.remove(j);
        Type adapted = %(declare ${entry.cadr()}
          (bindings ${entry.caddr()})).type_from_ast();
        c.meta_group.push(
          %(function $entry "main" ${c.func_signature(adapted)}));
        return;
      }
}

/** Adds a loaded unit's public functions and object accessors to its targets.
    Meta closure must finish first so these entries retain runtime semantics.
    Existing meta entries and the adapted main keep their original targets. */
void Compiler.prepare_loaded_functions(Compiler c, Array nodes) {
  Map present = {};
  foreach (List entry, c.meta_group)
    match (entry) case %(function ? ?name ?): present[name] = 1;
  Var identity, String name;
  foreach (List node, nodes)
    if (_function_identity(node, identity, name) &&
        c.public_native_function(node, name) && !(name in present)) {
      c.group_meta_function(node);
      present[name] = 1;
    }
  foreach (List node, nodes)
    match (node) case %(declare ?spec (bindings *rows)):
      foreach (List row, rows) _loaded_global(c, spec, row, present);
}

/* Each path has one accessor, with one parameter per array dimension.
   Native sizeof owns extents, including bounds inferred from initializers. */
static typedef struct LoadedPath {
  Compiler compiler;
  Array descriptions;
  String name;
  List parameters, checks;
} LoadedPath;

static Type _loaded_scalar(Compiler c, Type type) {
  if (type.is_bitfield()) type = type.base_type();
  if (c.sym.is_string_type(type)) return %("String");
  if (c.sym.is_named_value_type(type, "Symbol")) return %("Symbol");
  if (c.sym.is_named_value_type(type, "bool") ||
      c.sym.is_named_value_type(type, "_Bool")) return %(int);
  Type numeric = c.sym.resolve_numeric_type(type);
  if (!numeric || !numeric.is_number()) return NULL;
  return numeric.is_enum() ? numeric.promote() : numeric.canonicalize();
}

static Type _loaded_shape(Compiler c, Type type) =>
  c.sym.resolve_key(c.sym.normalize_declared_type(type));

static int _loaded_aggregate(Compiler c, Type type, int root) {
  Type shape = _loaded_shape(c, type);
  if (shape.match(%(struct ?))) return !!c.sym.field_order(shape);
  if (!shape.is_array()) return 0;
  List dimension = shape.car();
  return root || (dimension.cdr() && dimension.cadr().list());
}

static List _loaded_length(List target) =>
  $!size_t{ sizeof($target) / sizeof($target[0]) };

/* Snapshot traversal consumes one shared budget, including containers.
   Unsupported fields stay visible without exposing their native storage. */
static List _loaded_snapshot(
  Compiler c, Type type, List target,
  List budget, int root, Array statements) {
  Type scalar = _loaded_scalar(c, type);
  if (scalar) return $!($scalar){ ($scalar) $target };
  if (!_loaded_aggregate(c, type, root))
    return $!String{ String.new("<unavailable>") };
  Type shape = _loaded_shape(c, type);
  List value = c.sym.introduce(c.fresh_name("snapshot"));
  List body;
  if (shape.is_array()) {
    List index = c.sym.introduce(c.fresh_name("index"));
    Type element = c.sym.normalize_declared_type(type).dereference();
    List selected = %(expr $element
      (index $target ${$!(unsigned long long){ $index }}));
    Array items = $auto([]);
    List item = _loaded_snapshot(c, element, selected, budget, 0, items);
    body = $!{
      Array $value = [];
      unsigned long long $index = 0;
      for (; $index < ${_loaded_length(target)}; $index++) {
        if ($budget <= 0) { $value.push("..."); break; }
        $budget--;
        @{items.list()}
        $value.push($item);
      }
    };
  }
  else {
    Array fields = $auto([]);
    _loaded_snapshot_fields(c, type, target, value, budget, fields);
    body = $!{ Map $value = {}; @{fields.list()} };
  }
  statements.push(body);
  return shape.is_array() ? $!Array{ $value } : $!Map{ $value };
}

static void _loaded_snapshot_fields(
  Compiler c, Type type, List target, List value, List budget, Array fields) {
  foreach (List row, c.sym.field_order(_loaded_shape(c, type)).cdr()) {
    (String name, Type field) = row;
    field = field.qualify(c.sym.normalize_declared_type(type));
    if (!name) {
      if (_loaded_shape(c, field).match(%(struct ?)))
        _loaded_snapshot_fields(c, field, target, value, budget, fields);
      continue;
    }
    List selected = %(expr $field (op . $target ($name)));
    Array items = $auto([]);
    List item = _loaded_snapshot(c, field, selected, budget, 0, items);
    fields.push(
      $!{
        if ($budget > 0) {
          $budget--;
          @{items.list()}
          $value[$name] = $item;
        }
        else $value["..."] = "...";
      });
  }
}

static void _loaded_accessor(
  LoadedPath path, Type bridge, List body, int setter) {
  Compiler c = path.compiler;
  List name = c.sym.introduce(c.fresh_name("loaded_access"));
  List parameters = path.parameters;
  if (setter) parameters = %(@parameters
    (param $bridge (bind ${c.sym.introduce("value")} ()))
    (param (int) (bind ${c.sym.introduce("operation")} ())));
  List function = c.bind_syntax(
    %(function (static @bridge)
      (bind $name ((fnmod (params @parameters))))
      (block @{path.checks} $body)), <unit>, NULL);
  Type type = %(declare ${function.cadr()}
    (bindings ${function.caddr()})).type_from_ast();
  String request = (setter ? "set global " : "get global ") + path.name;
  c.meta_group.push(%(function $function $request ${c.func_signature(type)}));
}

static void _loaded_path(LoadedPath path, Type type, List target, int root) {
  Compiler c = path.compiler;
  Type bridge = _loaded_scalar(c, type);
  if (!bridge && !_loaded_aggregate(c, type, root)) return;
  int writable = bridge &&
    !(<const> in c.sym.normalize_declared_type(type));
  if (bridge) {
    _loaded_accessor(path, bridge, $!{ return ($bridge) $target; }, 0);
    if (writable)
      _loaded_accessor(path, bridge, _loaded_setter(bridge, target), 1);
  }
  else {
    bridge = %("Var");
    List budget = c.sym.introduce(c.fresh_name("remaining"));
    Array statements = $auto([]);
    List snapshot = _loaded_snapshot(
      c, type, target, budget, root, statements);
    _loaded_accessor(
      path, bridge,
      $!{ int $budget = 100; @{statements.list()} return $snapshot; }, 0);
  }
  path.descriptions.push(
    %(${path.name} $bridge $writable ${path.parameters.len()}));
  Type shape = _loaded_shape(c, type);
  if (shape.is_array()) {
    List index = c.sym.introduce(c.fresh_name("index"));
    List argument = $!(long long){ $index };
    path.parameters = %(@{path.parameters}
      (param (long long) (bind $index ())));
    path.checks = %(@{path.checks} ${$!{
      if ($argument < 0 || (unsigned long long) $argument >=
          ${_loaded_length(target)})
        raise %(repl (reason "loaded array index out of bounds"));
    }});
    path.name += "[]";
    Type element = c.sym.normalize_declared_type(type).dereference();
    _loaded_path(
      path, element, %(expr $element (index $target $argument)), 0);
  }
  else if (shape.match(%(struct ?)))
    _loaded_fields(path, type, target);
}

static void _loaded_fields(LoadedPath path, Type type, List target) {
  Compiler c = path.compiler;
  foreach (List row, c.sym.field_order(_loaded_shape(c, type)).cdr()) {
    (String name, Type field) = row;
    field = field.qualify(c.sym.normalize_declared_type(type));
    if (!name) {
      if (_loaded_shape(c, field).match(%(struct ?)))
        _loaded_fields(path, field, target);
      continue;
    }
    LoadedPath selected = path;
    selected.name += "." + name;
    _loaded_path(
      selected, field, %(expr $field (op . $target ($name))), 0);
  }
}

static void _loaded_global(Compiler c, Type spec, List row, Map present) {
  int initialized = 0;
  match (row) case %(op = ?bound ?): { row = bound; initialized = 1; }
  if (spec.is_static() || (spec.is_extern() && !initialized)) return;
  match (row) case %(bind ?binding ?): {
    String name = Ast.binding_spelling(binding);
    if (!name || name in present || %($name) in c.sym.file_statics()) return;
    Type type = %(declare $spec (bindings $row)).type_from_ast();
    if (!_loaded_scalar(c, type) &&
        !_loaded_aggregate(c, type, initialized)) return;
    c.ensure_macro_lisp();
    LoadedPath path = {.compiler = c, .descriptions = [], .name = name};
    _loaded_path(
      path, type,
      %(expr ${type.declared()} (ident $binding)), initialized);
    c.meta_group.push(%(global $name ${path.descriptions.list_free()}));
    present[name] = 1;
  }
}

/* Native postfix updates read and write once, including volatile objects. */
static List _loaded_setter(Type bridge, List target) =>
  bridge.is_number() ? $!{
    if (operation == 1) return ($bridge) $target++;
    if (operation == 2) return ($bridge) $target--;
    return ($bridge) ($target = value);
  } : $!{
    (void) operation;
    return ($bridge) ($target = value);
  };

/** Answers whether a `meta` body reaches the compiler itself: it names a
    compile-time-only function or a compiler operation, or constructs a
    template. Such a function has no runtime form. */
int Compiler.meta_reaches_compile_time(Compiler c, Var node) {
  if (node is not <list>) return 0;
  List syntax = node;
  match (syntax) {
    case %((!or tpl-call meta-call) *): return 1;
    case $source_identifier_content(%((binding ? ?name))): {
      if (name is not <string>) break;
      String spelling = name;
      /* Expansion can insert a call typed by its macro definition. */
      if (spelling in c.native_meta) c.bind_native_meta(spelling);
      return spelling in c.meta_comptime ||
             Compiler.supplies_native_meta(spelling);
    }
  }
  foreach (Var child, syntax) if (c.meta_reaches_compile_time(child)) return 1;
  return 0;
}

/** Closes compile-time-only calls across later meta definitions.
    Retained group bodies hold the bound calls, including literal insertions.
    Select runtime definitions only after that relation is complete. */
void Compiler.finish_meta_functions(Compiler c, Array nodes) {
  int grew = 1;
  while (grew) {
    grew = 0;
    foreach (List entry, c.meta_group)
      match (entry) case %(function ?fn ?(String name) ?):
        if (!(name in c.meta_comptime) && c.meta_reaches_compile_time(fn)) {
          c.record_comptime(name);
          grew = 1;
        }
  }
  int check_calls = 0;
  foreach (List entry, c.meta_group)
    match (entry) case %(function ? ?(String name) ?):
      if (name in c.meta_comptime) check_calls = 1;
  int retained = 0;
  foreach (List node, nodes) {
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
        $let(c.origin, origin) _check_runtime_meta_calls(c, inner);
        continue;
      }
      case %(call ?(List callee) ?): c.check_meta_call(callee, NULL);
    }
  }
}

// emitting the group

/* Emits the group through the ordinary backend as `(hfile htext cfile
   ctext)` named by `stem`, with exported names ending in `suffix`, or
   returns NULL with `failure` set when it does not lower. The emission
   borrows the unit's bindings and types and leaves the unit as it found
   it: generated names, literal caches, helpers, initializers, and semantic
   rows are its own. */
static List _emit(
  Compiler c, String stamp, String stem, String suffix, String &failure) {
  return _emit_prepared(c, stamp, stem, suffix, NULL, NULL, failure);
}

static List _emit_prepared(
  Compiler c, String stamp, String stem, String suffix,
  List declarations, Func prepare, String &failure) {
  Array units = prepare ? NULL : _units(c);
  String provider = c.filename;
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
    if (prepare) {
      c.meta_group = [];
      c.unit_nodes = declarations;
      c.group_meta_function(prepare(c));
      units = _units(c);
    }
    if (c.meta_build) _name_provider_bindings(c, provider, units, saved.deps);
    List lowered = _lower(c, units, stamp, suffix);
    /* The unit's protocol adapters and their registration belong to the
       program; group code reaches the runtime's own. */
    List ast = c.transform(lowered);
    code = c.generate_code_text(ast, stem);
  }
  catch %(?kind *detail): {
    List entries = c.diagnostics.entries();
    failure = entries ? _diagnostic_line(entries.car())
                      : cons(kind, detail).repr();
    code = NULL;
  }
  *c = saved;
  *c.names = names;
  transaction.rollback();
  return code;
}

/* A helper owns replacement bodies separately from the linked runtime.
   Included definitions take their provider's spelling; this file's public
   definitions take its own. Evaluator names remain source spellings. */
static void _name_provider_bindings(
  Compiler c, String provider, Array units, Map dependencies) {
  foreach (Var (path, index), meta_build_tables)
    if (path != provider && path in dependencies)
      c.name_meta_provider_bindings(path, index);
  int index = c.meta_build - 1;
  c.name_meta_provider_bindings(provider, index);
  Var identity, String name;
  foreach (List item, units)
    if (_function_identity(item, identity, name) &&
        (c.public_native_function(item, name) ||
         (c.load_source && name == "main"))) {
      List binding = item.caddr().cadr();
      c.set_fact(
        %(emitted $binding), %"_x2c_gensym_meta_group_${index}_$name");
    }
}

/* A diagnostic the emission reported, as one line that names its place in
   the `meta` body: `FILE:LINE:COLUMN: CODE: MESSAGE`, then its notes. */
static String _diagnostic_line(List entry) {
  String line = entry.repr();
  match (entry)
    case %((code ?code) * (message ?(String message))
           (location ((file ?file) (line ?row) (column ?column) *))
           (notes ?(List notes))): {
      line = %"$file:$row:$column: $code: $message";
      foreach (Var note, notes)
        if (note is <string>) line = %"$line; $note";
    }
  return line;
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
    _.pending.reset();
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
    _.permanent_literals = !c.meta_build;
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
static List _lower(
  Compiler c, Array units, String stamp, String suffix) {
  List binding = c.sym.introduce("x2c_template_call");
  Type type = $!Type{ List (Var, List) };
  List callee = %(expr $type (ident $binding));
  for (int i = 0; i < (int) units.len(); i++)
    units[i] = _template_calls(c, units[i], callee);
  if (c.meta_build) _native_lookups(c, units);
  int after = _after_directives(units);
  units.insert(
    after, c.rebuild_statement($!{ List $binding(Var, List); }).cadr());
  if (c.meta_build) {
    List start = c.sym.introduce("x2c_meta_helper_start");
    units.insert(
      after, c.rebuild_statement($!{ void $start(String); }).cadr());
    _native_entries(c, units, start);
  }
  Map initials = _initial_copies(c, units);
  foreach (
    Var unit, _entry(c, stamp, initials, _public_functions(c, units), suffix))
    units.push(unit);
  return units.list_free();
}

/* A meta build calls a native module's function through the address
   `x2c_meta_native_symbol` finds in the module. */
static void _native_lookups(Compiler c, Array units) {
  Type lookup_type = $!Type{ void *(String, String) };
  List lookup_binding = c.sym.introduce("x2c_meta_native_symbol");
  List lookup = %(expr $lookup_type (ident $lookup_binding));
  units.push(
    c.rebuild_statement($!{ void *$lookup_binding(String, String); }).cadr());
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
   directives, declarations, included providers, reached functions, and
   compile-time-only functions that the unit itself never emits. */
static Array _units(Compiler c) {
  String lib = %"${x2c_get_root()}/lib/";
  Array ordered = _runtime_includes(c, lib);
  _source_order(c, ordered, lib);
  Map reached = _roots(c, ordered);
  _close(ordered, reached);
  return _reachable(c, ordered, reached);
}

/* The runtime prelude declares more than `x2c.h` includes, and a body can
   name any of it, so the group includes each runtime unit the translation
   read, and the prelude and the compile-time surface when a collection
   pass has read none. */
static Array _runtime_includes(Compiler c, String lib) {
  Array ordered = [];
  foreach (String header, %("x2c.x" "meta.x"))
    ordered.push(%(preproc ${%"#include \"$header\""}));
  foreach (Var (path, hash), c.deps) {
    if (hash is <string> && String.startswith(hash, "search:")) continue;
    if (c.canonical_path(path) == c.canonical_path(c.filename)) continue;
    String dependency = path;
    if (dependency.startswith(lib) && dependency.endswith(".x") &&
        !("/" in dependency[lib.len():])) {
      String header = Path.basename(dependency);
      Var index;
      if (meta_build_tables.try_get(Path.absolute(dependency), index))
        header = %"meta_group_$index.h";
      ordered.push(%(preproc ${%"#include \"$header\""}));
    }
  }
  return ordered;
}

static void _source_order(Compiler c, Array ordered, String lib) {
  Map placeholders = _placeholders(c);
  foreach (Var unit, c.unit_nodes) {
    Var node = _group_include(c, unit, lib);
    if (node is not void) ordered.push(_uninitialized(node, placeholders));
  }
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
      return %(preproc ${%"#include \"meta_group_$index.h\""});
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
    if (_function_identity(item, identity, name)) {
      present[identity] = 1;
      if (c.meta_build && c.public_native_function(item, name))
        reached[identity] = 1;
    }
  foreach (List entry, c.meta_group)
    match (entry) case %(function ?fn *): {
      Ast.collect_binding_references(fn, reached);
      if (_function_identity(fn, identity, name) && !(identity in present))
        ordered.push(fn);
      reached[identity] = 1;
    }
  foreach (List item, ordered)
    if (!_function_identity(item, identity, name))
      Ast.collect_binding_references(item, reached);
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
        Ast.collect_binding_references(item, reached);
        grew = 1;
      }
  }
}

/* An unreached function keeps its prototype, which code generated for
   the unit's types, such as a protocol adapter, may name; the optimizer
   drops what nothing calls. */
static Array _reachable(Compiler c, Array ordered, Map reached) {
  Array units = [];
  Var identity, String name;
  foreach (List item, ordered) {
    if (!_function_identity(item, identity, name) ||
        (identity in reached && (name != "main" || c.load_source)))
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
  List child;
  $ast.rewrite_children(node, child, _template_calls(c, child, callee));
}

/* `node` with each use of a native module's function made through the
   address `lookup` finds in that module. A native module's C target lives
   in the module, not in the helper. */
static Var _native_targets(Compiler c, Var node, List lookup) {
  if (node is not <list>) return node;
  match (node) {
    case %(expr ?(Type result) ${$called(
        %(!set ?callee
          (expr ? ${$source_identifier_content(%((binding ? ?name)))})),
        %(*arguments))}): {
      if (name is not <string>) break;
      String spelling = name;
      List call = _native_call(c, callee, spelling, arguments, lookup);
      if (call) return c.convert_expression(call, result);
    }
    case %(expr ?(Type type) ${$source_identifier_content(
        %((binding ? ?name)))}): {
      if (name is not <string>) break;
      String spelling = name;
      List symbol = _native_symbol(c, type, spelling, lookup);
      if (symbol) return symbol;
    }
  }
  List child;
  $ast.rewrite_children(node, child, _native_targets(c, child, lookup));
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
  c.sym.normalize_declared_type(declared) ==
    c.sym.normalize_declared_type(%("Func")) &&
  c.sym.normalize_declared_type(parameter) ==
    c.sym.normalize_declared_type(%("Var"));

/* The native function `name` of `type` read through its module's address,
   or NULL when no native module supplies it. The read keeps the function
   type of the module that supplied the compiler's binding. */
static List _native_symbol(
  Compiler c, Type type, String name, List lookup) {
  if (!type.is_function() || !(name in c.native_meta)) return NULL;
  String module = c.native_meta_module(name, type);
  if (!module) return NULL;
  c.add_translation_dependency(module);
  Type pointer = type.reference();
  List target = %(expr (* void) (call $lookup
    (args ${$!String{ $module }}
          ${$!String{ $name }})));
  return %(expr $pointer (cast $pointer $target));
}

// the group's entry

/* A project group's mutable meta values initialize only in its reset.
   An anonymous aggregate needs a same-declaration copy because C cannot
   spell its type in the later assignment. Ordinary native modules keep
   their existing initializers and braced copies. */
static Map _initial_copies(Compiler c, Array units) {
  Map copies = {};
  foreach (List entry, c.meta_group)
    match (entry)
      case %(static (!set ?declaration (declare ?spec
                      (bindings (op = (!set ?bound (bind ?binding ?mods))
                                     ?initializer))))): {
        Type type =
          %(declare $spec (bindings $bound)).type_from_ast().declared();
        if (<const> in type) continue;
        if (type.is_array()) {
          List zero = _braced(initializer)
            ? c.zero_initializer(initializer) : initializer;
          if (c.meta_build)
            for (int i = 0; i < (int) units.len(); i++)
              if (units[i] == declaration)
                units[i] = %(declare $spec (bindings
                  (op = $bound $zero)));
          continue;
        }
        int copied = _braced(initializer) &&
                     (!c.meta_build || type.tag().car() is <list>);
        if (!c.meta_build && !copied) continue;
        List copy = copied
          ? c.sym.introduce(
            %"_x2c_gensym_meta_initial_${binding.list().last()}") : NULL;
        for (int i = 0; i < (int) units.len(); i++)
          if (units[i] == declaration) {
            List original = c.meta_build ? bound : %(op = $bound $initializer);
            List bindings = copied
              ? %($original (op = (bind $copy $mods) $initializer))
              : %($original);
            units[i] = %(declare $spec (bindings @bindings));
          }
        if (copied) copies[binding] = %(expr $type (ident $copy));
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
static List _entry(
  Compiler c, String stamp, Map initials, List functions, String suffix) {
  List resets = _resets(c, initials);
  List reset = c.initializer_function(
    %(void), c.sym.introduce(%"x2c_module_reset$suffix"), resets);
  List table = _targets(c, _named(c, reset), functions);
  List stamp_binding = c.sym.introduce(%"x2c_module_stamp$suffix");
  String literal = %"\"$stamp\"";
  return %(
    (declare (const char)
      (bindings (op = (bind $stamp_binding ((dim)))
                     (expr (* char) (literal (* char) $literal)))))
    $reset
    ${c.initializer_function(
      %("Map"), c.sym.introduce(%"x2c_module_targets$suffix"),
      %((return ("Map") $table)))});
}

/* Public native calls enter their own provider before the body runs. The
   protocol does the same for direct evaluator calls, including private
   functions. Unused provider objects do not start their tables. */
static void _native_entries(Compiler c, Array units, List start) {
  Var identity, String name;
  for (int i = 0; i < (int) units.len(); i++) {
    List item = units[i];
    if (!_function_identity(item, identity, name) ||
        !c.public_native_function(item, name)) continue;
    match (item) case %(function ?type ?declarator (block *body)): {
      List argument = $!String{ $name };
      List enter = c.rebuild_statement($!{ $start($argument); }).cadr();
      units[i] = %(function $type $declarator (block $enter @body));
    }
  }
}

/* Native provider ownership includes functions whose signatures cannot
   cross the evaluator boundary. Their names stay separate from Funcs. */
static List _public_functions(Compiler c, Array units) {
  Array functions = [];
  Var identity, String name;
  foreach (List item, units)
    if (_function_identity(item, identity, name) &&
        c.public_native_function(item, name))
      functions.push(name);
  return functions.list_free();
}

/** Answers whether a definition has public native linkage.
    Main is excluded because its process entry needs a separate adapter. */
int Compiler.public_native_function(
  Compiler c, List function, String name) =>
  name != "main" && !(%(function $name) in c.sym.file_statics()) &&
  !%(declare ${function.cadr()} (bindings ${function.caddr()}))
     .type_from_ast().is_static();

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
        if (<const> in type) continue;
        Var initial;
        if (initials.try_get(binding, initial)) initializer = initial;
        List target = %(expr $type (ident $binding));
        if (type.is_array()) {
          if (!_braced(initializer))
            initializer = %(expr () (composite (commas $initializer)));
          Type native = %("__typeof__" (parens $target));
          initializer = %(expr $type (cast $native
            ${c.convert_initializer(initializer, type, target)}));
          resets.push(
            c.rebuild_statement(
              $!{ memcpy($target, $initializer, sizeof($target)); }).cadr());
        }
        else resets.push(
          c.rebuild_statement($!{ $target = $initializer; }).cadr());
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
static List _targets(Compiler c, List named, List functions) {
  Array entries = [];
  if (c.meta_build)
    entries.push(
      %(map-entry ${$!Symbol{ ${<functions>} }}
        ${c.cache_literal_list(functions)}));
  foreach (List row, named) {
    (String name, List binding, Type type) = row;
    List function = NULL;
    try function = c.convert_expression(
      %(expr $type (ident $binding)), %("Func"));
    catch %(malformed *): continue;
    entries.push(%(map-entry ${$!String{ $name }} $function));
  }
  Macro shape = $map_value;
  return c.rebuild_expression(%("Map"), shape(entries.list_free()));
}

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
  $fail.meta_group_function_unavailable(c, site, name, why);
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
  match (node) case $source_identifier_content(%((binding ? ?name))): {
    if (name is not <string>) break;
    String spelling = name;
    String unbound = %"<unbound $spelling>";
    return unbound in c.meta_group_bound ||
           (spelling in c.native_meta &&
            !c.macro_lisp.try_get(spelling, bound) &&
            !c.bind_native_meta(spelling)) ? spelling : NULL;
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
static Map meta_build_tables = NULL;

/** Directs each provider group into `directory`, using `owners` to name
    their headers by table, or stops that when `directory` is NULL. */
void Compiler.use_meta_build_directory(String directory, Array owners) {
  meta_build_directory = directory;
  meta_build_tables = {};
  int index = 1;
  foreach (String owner, owners) meta_build_tables[owner] = index++;
}

/** Writes the group of a unit the project meta build parsed into the build
    directory as `group-K.c` and `group-K.h`, K being its table, with the
    x2c sources it read in `group-K.deps`, or its failure in
    `group-K.failure`. Included native and type providers use the same
    group header and object even when they have no `meta` functions. */
void Compiler.write_meta_build(Compiler c) {
  int index = c.meta_build - 1;
  if (!meta_build_directory) return;
  c.ensure_macro_lisp();
  String base = %"$meta_build_directory/group-$index";
  String failure = _unbound(c);
  List code = failure ? NULL : _emit(
    c, Compiler.module_stamp(), %"meta_group_$index", %"_$index", failure);
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
  if (!_stage(c, failure)) c.refuse_meta_call(name, site, failure);
  if (!(name in c.meta_group_bound))
    c.refuse_meta_call(name, site, c.meta_call_missing(name));
}

/* Builds and loads the session's `meta` group, then binds each
   group function in the session not yet bound. Returns the loaded module,
   or NULL with `failure` set when the group does not stage. */
static String _stage(Compiler c, String &failure) {
  failure = c.groups_meta() ? _unbound(c) : "native modules are unavailable";
  String module = failure ? NULL : _module(c, NULL, NULL, failure);
  if (!module) return NULL;
  module = Compiler.load_native_module(module);
  Map targets = Compiler.native_module_targets(module);
  if (!(module in c.meta_group_bound)) {
    c.meta_group_bound[module] = 1;
    $scope(&session_meta_scope)
      ((Func) targets["x2c_module_reset"].pointer()).apply(0, NULL);
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

/** Stages one session factory in an isolated native emission. `prepare`
    receives this compiler and returns the factory's typed definition; it
    can place supporting functions through the ordinary compiler APIs.
    `declarations` supplies session types. Returns the loaded module's
    targets, or NULL with `failure` set. Publishes no evaluator bindings. */
Map Compiler.stage_session_function(
  Compiler c, List declarations, Func prepare, String &failure) {
  failure = c.groups_meta() ? NULL : "native modules are unavailable";
  String module = failure ? NULL : _module(c, declarations, prepare, failure);
  if (!module) return NULL;
  return Compiler.native_module_targets(Compiler.load_native_module(module));
}

/* The group's native module under the cache root, named by the SHA-256 of
   its emitted C, the compiler stamp, the C compiler's identity, and the
   runtime headers' directory: one an earlier submission built, or else a
   new build. Returns its path, or NULL with `failure` set when there is no
   cache or the group does not build. */
static String _module(
  Compiler c, List declarations, Func prepare, String &failure) {
  String root = Compiler.cache_root(), stamp = Compiler.module_stamp();
  if (!root || !stamp) {
    failure = "native modules need a cache directory and a known compiler";
    return NULL;
  }
  List code = _emit_prepared(
    c, stamp, "group", "", declarations, prepare, failure);
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
  Toolchain linker = Toolchain.for_meta(meta_cc);
  List arguments = linker.module_action(
    output,
    %("-fsigned-char" "-fPIC" "-O0" "-iquote" $directory
      "-iquote" $meta_include_dir ${%"$directory/$cfile"}),
    x2c_get_executable()).arguments;
  String failure = Compiler.meta_cc_run(arguments, directory);
  if (!failure) Path.move_to(output, module);
  return failure;
}
