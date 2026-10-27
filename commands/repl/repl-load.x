/*  repl-load.x -- native source definitions for an interpreted session

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "collect/collect.x"
#include "meta-group/meta-group.x"
#include "meta-project.x"
#include "datum.x"
#include "ast-rewrite.x"

static typedef struct LoadedSource {
  ReplResult result;
  Map symbols, globals;
} LoadedSource;

static typedef struct LoadedCall {
  ReplSession session;
  ReplLoadedFile file;
  String name;
} LoadedCall;

/* Collection selects the requested public names and complete type families.
   Generated accessor functions remain private helper targets. */
static List _public_definitions(Compiler c, Map &symbols, Map globals) {
  Array candidates = auto [], names = [];
  foreach (List entry, c.meta_group)
    match (entry) {
      case %(function ?fn ?(String name) ?):
        if (name == "main" || c.public_native_function(fn, name))
          candidates.push(name);
      case %(global ?(String name) ?paths): {
        candidates.push(name);
        globals[name] = paths;
      }
    }
  symbols = c.callable_symbols(candidates);
  if (c.load_source)
    foreach (List entry, c.meta_group)
      match (entry) case %(function ? "main" ?type):
        symbols[%("main")] = type;
  foreach (String name, candidates)
    if ($(name) in symbols) names.push(name);
  return names.list_free();
}

/* Anonymous tags are numbered within each source parse. Match their
   identities through named declarations, then through the referenced field
   families. A new earlier typedef must not rename an existing prompt type. */
static typedef struct ReloadTypes {
  Map forward, reverse;
  Array pairs;
} ReloadTypes;

static void _changed(String detail) {
  raise %(repl (reason $(detail + "; start a new session")));
}

static Var _anonymous_family(List key) {
  match (key)
    case %((!or struct union enum) (!set ?name (gensym ? ?)) *): return name;
  return void;
}

static void _pair_types(Var before, Var after, ReloadTypes &types) {
  if (before is not <list> || after is not <list>) return;
  List a = before, b = after;
  match (a) case %(gensym ? ?): {
    if (!b.match(%(gensym ? ?))) return;
    Var paired;
    if (types.forward.try_get(a, paired)) {
      if (paired.equal(b)) return;
    }
    else if (!(b in types.reverse)) {
      types.forward[a] = b;
      types.reverse[b] = a;
      types.pairs.push($(a, b));
      return;
    }
    _changed("public type identity changed");
  }
  while (a && b) {
    _pair_types(a.car(), b.car(), types);
    a = a.cdr();
    b = b.cdr();
  }
}

static void _new_types(Compiler c, Var value, Map names, Array pending) {
  List node;
  $ast.walk(value, node) {
    match (node) case %(gensym ? ?): {
      if (!(node in names)) {
        names[node] = c.gensym().car();
        pending.push(node);
      }
      continue;
    }
  }
}

/* Reuse visible identities and mint new ones only for newly reachable
   anonymous types. Unnamed families with no public reference are omitted. */
static Map _stable_types(Compiler c, Map visible, Map symbols) {
  auto Map forward = {}, reverse = {};
  Array pairs = auto [];
  ReloadTypes types = {.forward = forward, .reverse = reverse, .pairs = pairs};
  foreach (Var (key, value), symbols) {
    Var old;
    if (_anonymous_family(key) is void && visible.try_get(key, old))
      _pair_types(old, value, types);
  }
  for (int i = 0; i < types.pairs.len(); i++) {
    List pair = types.pairs[i];
    foreach (Var (key, value), visible)
      match (key) case %(?kind ?name *tail): {
        if (name != pair.car()) continue;
        Var replacement;
        if (symbols.try_get($(kind, pair.cadr(), @tail), replacement))
          _pair_types(value, replacement, types);
      }
  }
  Array pending = auto [];
  foreach (Var name, types.reverse.keys()) pending.push(name);
  foreach (Var (key, value), symbols)
    if (_anonymous_family(key) is void)
      _new_types(c, value, types.reverse, pending);
  for (int i = 0; i < pending.len(); i++)
    foreach (Var (key, value), symbols)
      if (_anonymous_family(key) == pending[i])
        _new_types(c, value, types.reverse, pending);
  Map replacements = auto {}, normalized = {};
  foreach (Var (name, identity), types.reverse)
    replacements[(void *) name.list()] = identity;
  foreach (Var (key, value), symbols) {
    Var family = _anonymous_family(key);
    if (family is not void && !(family in types.reverse)) continue;
    normalized[Ast.replace_nodes(key, replacements)] =
      Ast.replace_nodes(value, replacements);
  }
  return normalized;
}

/* Metadata added to an existing type is also a definition change. */
static void _check_type_rows(Map before, Map after) {
  foreach (Var key, before.keys()) {
    List family = NULL;
    match (key) {
      case %((!or ?kind typedef struct union enum) ?name *):
        family = $(kind, name);
      case %(?name "layout-attribute"): family = %(typedef $name);
    }
    if (family && family in after && !(key in after))
      raise %(repl (reason $(%"conflicting declaration: $(key.repr())")));
  }
}

static String _type_name(List key, Type type) {
  match (key) {
    case %(?(String name)): if (type.is_typedef()) return name;
    case %((!or struct union enum) ?(String name)): return name;
  }
  return NULL;
}

/* Source declarations cannot change the types or meanings of live values. */
static void _check_names(
  ReplSession session, ReplLoadedFile file, ReplLoadedFile retired,
  Map visible, Map symbols, List names) {
  foreach (String name, names) {
    if (file && $(name) in file.symbols) continue;
    if (retired && $(name) in retired.symbols) continue;
    Var existing;
    if ($(name) in visible || name in session.names ||
        name.startswith("__repl_") ||
        session.evaluator.try_get(name, existing))
      raise %(repl (reason $(%"name already defined: $name")));
  }
  foreach (Var (key, value), symbols) {
    Var existing;
    String name = _type_name(key, value);
    if (name) {
      List entry = session.inspect(name);
      if (name in names || name.startswith("__repl_") ||
          (entry && entry.car() != <type>) ||
          (!entry && session.evaluator.try_get(name, existing)))
        raise %(repl (reason $(%"name already defined: $name")));
    }
    if (file && key in file.symbols) continue;
    if (visible.try_get(key, existing) && !existing.equal(value))
      raise %(repl (reason $(%"conflicting declaration: $(key.repr())")));
  }
  _check_type_rows(visible, symbols);
  _check_type_rows(symbols, visible);
}

/* Existing prompt code keeps its calling types and layouts. Function
   signatures omit parameter names; receiver metadata and type rows retain
   their exact declared meaning. Declarations the file no longer publishes
   are removals, which `_check_removed` checks. */
static void _check_replacement(
  Compiler c, ReplLoadedFile file, Map symbols) {
  foreach (Var (key, declaration), file.symbols)
    match (key) case %(?(String name)): {
      Type type = declaration, replacement = _function_type(symbols, name);
      if (!type.is_function() || !replacement) continue;
      if (!c.func_signature(type).equal(c.func_signature(replacement)))
        _changed(%"function type changed: $name");
      List receiver = %(self $name);
      if (!file.symbols[receiver].equal(symbols[receiver]))
        _changed(%"receiver type changed: $name");
    }
  foreach (Var (key, declaration), file.symbols) {
    match (key) {
      case %(?name): if (_function_type(file.symbols, name)) continue;
      case %(self ?name): if (_function_type(file.symbols, name)) continue;
    }
    Var replacement;
    if (symbols.try_get(key, replacement) && !declaration.equal(replacement))
      _changed(%"declaration changed: $(key.repr())");
  }
}

/* The public name a symbol row declares: a function, global, or type. */
static String _row_name(List key) {
  match (key) {
    case %(?(String name)): return name;
    case %((!or typedef struct union enum) ?(String name)): return name;
  }
  return NULL;
}

/* The type family a row belongs to, or NULL for a function or global. */
static List _row_family(List key, Var declaration) {
  match (key) {
    case %((!or ?kind typedef struct union enum) ?name *):
      return $(kind, name);
    case %(?name "layout-attribute"): return %(typedef $name);
    case %(?name): if (declaration == %(typedef $name)) return declaration;
  }
  return NULL;
}

/* Rows of `file` that no loaded file publishes after this load leave the
   session with their public names, unless prompt code refers to those
   names. A replaced file also loses its functions and globals, whose
   adapters name that file. Adds the rows to `dropped` and returns the
   sorted names. */
static List _check_removed(
  ReplSession session, ReplLoadedFile file, Map published, int retiring,
  Map dropped) {
  Array names = auto [];
  foreach (Var (key, declaration), file.symbols) {
    List family = _row_family(key, declaration);
    // Another file or the runtime introduced this type.
    if (family && !file.types.contains(family)) continue;
    String name = _row_name(key);
    Var current;
    if (published.try_get(key, current) && current.equal(declaration)) {
      if (!retiring || family || !name) continue;
    }
    else {
      if (!retiring && family && !family.equal(key) && family in published)
        _changed(%"declaration changed: $(key.repr())");
      dropped[key] = 1;
    }
    if (name && name in session.names && !(name in names)) {
      _check_unreferenced(session, name);
      names.push(name);
    }
  }
  return names.sort();
}

/* A removed name leaves no prompt definition that refers to it. */
static void _check_unreferenced(ReplSession session, String name) {
  Symbol kind = session.inspect(name).car();
  if (kind == <type>) _check_type_unreferenced(session, name);
  else _check_value_unreferenced(session, name, kind);
}

/* Prompt functions refer to a function or global by binding; prompt
   variables can hold a function as a Func. */
static void _check_value_unreferenced(
  ReplSession session, String name, Symbol kind) {
  Compiler c = session.compiler;
  List binding = c.sym.resolve_global($(name), NULL);
  String use = kind == <native> ? "called" : "used";
  Var callable = void, stored = void;
  session.evaluator.try_get(name, callable);
  session.evaluator.try_get("C.globals", stored);
  foreach (Var (referrer, entry), session.names)
    match (entry) {
      case %(function (typed ?syntax) *):
        if (_mentions(syntax, binding))
          _referred(%"$name is $use by prompt function $referrer");
      case %(value):
        if (_holds(c, referrer, stored, callable))
          _referred(%"$name is saved in prompt variable $referrer");
    }
}

/* Types appear by name in typed syntax, variable types, and prompt type
   declarations. */
static void _check_type_unreferenced(ReplSession session, String name) {
  Compiler c = session.compiler;
  foreach (Var (referrer, entry), session.names)
    match (entry) {
      case %(function (typed ?syntax) *):
        if (_mentions_type(syntax, name))
          _referred(%"$name is used by prompt function $referrer");
      case %(value):
        if (_mentions_type(c.sym.get_exact($(referrer)), name))
          _referred(%"$name is used by prompt variable $referrer");
    }
  foreach (List declaration, session.declarations) {
    if (!_mentions_type(declaration, name)) continue;
    Array declared = auto [];
    _type_submission_names(declaration, declared);
    _referred(%"$name is used by prompt type $(declared[0])");
  }
}

static void _referred(String why) { raise %(repl (reason $why)); }

static int _mentions(Var syntax, List binding) {
  List node;
  $ast.walk(syntax, node) {
    match (node) case %(ident ?found): if (found.equal(binding)) return 1;
  }
  return 0;
}

static int _mentions_type(Var syntax, String name) {
  List node;
  $ast.walk(syntax, node) {
    match (node) {
      case %(?(String found)): if (found == name) return 1;
      case %((!or struct union enum) ?(String found) *):
        if (found == name) return 1;
    }
  }
  return 0;
}

/* Prompt variables are native objects addressed through `C.globals`. */
static int _holds(Compiler c, String name, Map globals, Var callable) {
  Type type = NULL;
  List binding = c.sym.resolve_global($(name), type);
  if (callable is not <func> || type != %("Func")) return 0;
  Var address = globals[binding.cadr()];
  return *(Func *) address.pointer() == callable.pointer();
}

/* The loaded file that defines main, or NULL. */
static ReplLoadedFile _main_owner(ReplSession session) {
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    if (_function_type(file.symbols, "main")) return file;
  }
  return NULL;
}

/* Collection names a file's native definitions before its helper builds. */
static int _defines_main(Frontend frontend, String filename) {
  ParsedUnit unit;
  int opened = frontend.start(filename, unit);
  defer unit.close();
  unit.compiler.load_source = 1;
  return opened && unit.collect(frontend) &&
    "main" in unit.compiler.loaded_provider().car().map();
}

/* Whether another loaded file also publishes the row `key`. */
static int _shared(ReplSession session, ReplLoadedFile retired, List key) {
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    if (file != retired && key in file.symbols) return 1;
  }
  return 0;
}

/* Removes a public name from the prompt with its callable and adapters.
   Hidden adapter names stay reserved so later adapters number uniquely. */
static void _unpublish(ReplSession session, String name) {
  match (session.inspect(name)) {
    case %(native * (objects ?adapter)): {
      _forget(session, adapter);
      session.evaluator.remove_global(name);
    }
    case %(global ? ?paths):
      foreach (Var (path, accessors), paths.map())
        foreach (Var accessor, accessors.list()) _forget(session, accessor);
  }
  session.names.del(name);
}

/* A file that still publishes a type the replaced file introduced
   introduces it now. */
static void _adopt_type(ReplSession session, List family) {
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    if (!(family in file.symbols)) continue;
    file.types = cons(family, file.types);
    return;
  }
}

static void _forget(ReplSession session, Var adapter) {
  match (adapter) case %(expr ? (ident ?binding)): {
    String hidden = Ast.binding_spelling(binding);
    session.compiler.sym.undefine_global($(hidden));
    session.evaluator.remove_global(hidden);
  }
}

/* Applies checked removals before the remaining files publish. Returns the
   types the replaced file introduced that another file still publishes. */
static List _remove(
  ReplSession session, List removed, Map dropped, ReplLoadedFile retired) {
  foreach (List row, removed)
    foreach (String name, row.cadr()) _unpublish(session, name);
  foreach (Var key, dropped.keys()) session.compiler.sym.undefine_global(key);
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    file.types = file.types.filter(%!(List family) => !(family in dropped));
  }
  if (!retired) return NULL;
  session.files.del(retired.path);
  List kept = retired.types.filter(%!(List family) => !(family in dropped));
  retired.symbols.cleanup();
  xfree(retired);
  return kept;
}

/* The function declaration already retained in a file's public symbols. */
static Type _function_type(Map symbols, String name) {
  Var declaration;
  if (!symbols.try_get($(name), declaration)) return NULL;
  Type type = declaration;
  return type.is_function() ? type : NULL;
}

/* Declarations leave the source Context; every file uses the candidate
   helper while preparing the replacement session. */
static LoadedSource _prepare(
  Frontend frontend, String filename, MetaHelper helper) {
  LoadedSource loaded = {.result = {.status = <rejected>, .value = void}};
  ParsedUnit unit;
  int opened = frontend.start(filename, unit);
  defer unit.close();
  Compiler c = unit.compiler;
  c.load_source = 1;
  c.meta_helper = helper;
  c.begin_meta_unit(c.filename);
  opened = opened && unit.collect(frontend) && unit.parse();
  try {
    if (opened) {
      Map symbols = NULL;
      Map globals = {};
      List names = _public_definitions(c, symbols, globals);
      if (!names)
        raise %(repl (reason "no public functions or supported globals found"));
      loaded.globals = unit.context.export(globals);
      loaded.symbols = unit.context.export(symbols);
      loaded.result.value = unit.context.export(names);
      loaded.result.status = <loaded>;
    }
  }
  catch %(malformed *): {}
  catch %(repl (reason ?why)):
    loaded.result.message = unit.context.export(why);
  loaded.result.source = unit.context.export(c.text);
  loaded.result.diagnostics = unit.context.export(c.diagnostics());
  return loaded;
}

/* A struct or union passes by value as a native address, which data
   cannot carry across the helper boundary. */
static int _is_record(Compiler c, Type type) {
  if (!c.sym.is_var_type(type)) type = c.sym.resolve_key(type);
  return type.is_aggregate();
}

/* The helper reports a loaded call's failure in compile-time terms at the
   prompt's last token. The prompt reports it once, as a failure of the
   named function. Warnings the body makes still print. */
static Var _helper_run(
  const LoadedCall *call, Type result, List arguments, Symbol operation) {
  Compiler c = call.session.compiler;
  DiagnosticsHold hold = c.diagnostics.hold();
  Var value = void;
  try {
    with (c.meta_helper = call.session.helper) {
      value = operation == <load-call>
        ? c.loaded_helper_call(call.name, c.token, arguments, call.file.path)
        : c.meta_helper_call(call.name, c.token, arguments, call.file.path);
    }
  }
  catch %(malformed *): {
    List failure = NULL;
    foreach (List entry, c.diagnostics()) failure = entry;
    c.diagnostics.release(hold, 0);
    raise %(repl (reason $(_call_failure(c, call.name, result, failure))));
  }
  c.diagnostics.release(hold, 1);
  return value;
}

/* The helper names why it stopped in a `reason:` note; a result it cannot
   return is a record or a native pointer. */
static String _call_failure(
  Compiler c, String name, Type result, List entry) {
  String why = "the call failed";
  match (entry) case %(* (message ?(String message)) * (notes ?notes)): {
    why = message;
    foreach (Var note, notes)
      if (note is <string> && note.str().startswith("reason: "))
        why = note.str().remove_prefix("reason: ");
    if (why == "compile-time result is a compiler address")
      why = _is_record(c, result)
        ? "record values cannot cross the helper boundary"
        : "native pointers cannot cross the helper boundary";
  }
  return %"$name failed: $why";
}

/* Native adapters in the helper check declared value types. This adapter
   refuses records and references before reading their carrier as a
   value. */
static Var _call(Func function, const FuncArg *argv) {
  const LoadedCall *call = Func.context(function);
  Compiler c = call.session.compiler;
  List signature = function.signature();
  List parameters = signature.car().list().cadr();
  int count = parameters == %((void)) ? 0 : parameters.len();
  Array arguments = auto [];
  List parameter = parameters;
  for (int i = 0; i < count; i++, parameter = parameter.cdr()) {
    if (_is_record(c, parameter.car()))
      raise %(repl (reason $(call.name + " failed: record values cannot "
                                             "cross the helper boundary")));
    Var value = x2c_func_value_argument(function, argv, i, <var>);
    if (parameter.car() == %(....))
      foreach (Var item, value.list()) arguments.push(item);
    else if (parameter.car() == %(.... "Map")) {
      Map entries = value;
      foreach (Var (key, item), entries)
        arguments.push(key), arguments.push(item);
    }
    else arguments.push(value);
  }
  List problem = Var.independent_data_problem(arguments, {});
  if (problem)
    raise %(repl (reason "loaded function arguments must be independent data values")
                 (detail $problem));
  return _helper_run(call, signature.cdr(), arguments, <call>);
}

/* The prompt has already checked native argument types. Envelopes contain
   only data; the helper supplies the addresses to its native adapters. */
static Var _call_objects(Func function, const FuncArg *argv) {
  const LoadedCall *call = Func.context(function);
  List arguments = x2c_func_value_argument(function, argv, 0, <list>);
  List problem = Var.independent_data_problem(arguments, {});
  if (problem)
    raise %(repl (reason "loaded function arguments must be independent data values")
                 (detail $problem));
  return _helper_run(call, function.signature().cdr(), arguments, <load-call>);
}

static List _object_adapter(
  ReplSession session, ReplLoadedFile file, String name, Type signature) {
  Compiler c = session.compiler;
  Type result = signature.apply();
  Type type = %((func (("List"))) @result);
  String hidden = %"__repl_call_$(session.accessors.len())";
  c.sym.define_global($(hidden), type);
  List binding = c.sym.resolve_global($(hidden), NULL);
  LoadedCall call = {.session = session, .file = file, .name = name};
  Func function = Func.new_context(
    _call_objects, c.func_signature(type), &call, sizeof call);
  session.evaluator.set_global(hidden, function);
  session.accessors[hidden] = 1;
  return %(expr $type (ident $binding));
}

static void _publish_types(ReplSession session, Map symbols) {
  foreach (Var (key, value), symbols) {
    String name = _type_name(key, value);
    if (name) session.names[name] = %(type);
  }
}

static List _accessor(
  ReplSession session, ReplLoadedFile file, String name, Type bridge,
  int dimensions, int setter) {
  Compiler c = session.compiler;
  Array parameters = auto [];
  for (int i = 0; i < dimensions; i++) parameters.push(%(long long));
  if (setter) { parameters.push(bridge); parameters.push(%(int)); }
  if (!parameters.len()) parameters.push(%(void));
  Type type = %((func $(parameters.list())) @bridge);
  String request = (setter ? "set global " : "get global ") + name;
  String hidden = %"__repl_global_$(session.accessors.len())";
  c.sym.define_global($(hidden), type);
  List binding = c.sym.resolve_global($(hidden), NULL);
  LoadedCall call = {.session = session, .file = file, .name = request};
  Func function = Func.new_context(
    _call, c.func_signature(type), &call, sizeof call);
  session.evaluator.set_global(hidden, function);
  session.accessors[hidden] = 1;
  return %(expr $type (ident $binding));
}

static void _publish_globals(
  ReplSession session, ReplLoadedFile file, Map globals) {
  foreach (Var (name, description), globals) {
    if (session.inspect(name)) continue;
    Map paths = {};
    foreach (List row, description.list()) {
      (String path, Type bridge, int writable, int dimensions) = row;
      List get = _accessor(session, file, path, bridge, dimensions, 0);
      List set = writable
        ? _accessor(session, file, path, bridge, dimensions, 1) : NULL;
      paths[path] = $(get, set);
    }
    session.names[name] = %(global (source $(file.path)) $paths);
  }
}

/* Publishes already checked declarations while preserving existing adapters. */
static void _publish(
  ReplSession session, String filename, LoadedSource &loaded) {
  ReplLoadedFile file = session.files[filename].pointer();
  if (!file) {
    file = xcalloc(1, sizeof(struct ReplLoadedFile));
    file.path = filename;
  }
  Map visible = auto session.compiler.sym.unit_symbols();
  foreach (Var (key, type), loaded.symbols) {
    if (!(key in visible))
      match (key)
        case %((!or typedef struct union enum) ?):
          file.types = cons(key, file.types);
    if (!file.symbols || !(key in file.symbols))
      session.compiler.sym.define_global(key, type);
  }
  _publish_types(session, loaded.symbols);
  _publish_globals(session, file, loaded.globals);
  foreach (String name, loaded.result.value.list()) {
    Type type = _function_type(loaded.symbols, name);
    if (!type || _function_type(file.symbols, name)) continue;
    List signature = session.compiler.func_signature(type);
    LoadedCall call = {.session = session, .file = file, .name = name};
    Func function = Func.new_context(_call, signature, &call, sizeof call);
    session.evaluator.set_global(name, function);
    List adapter = _object_adapter(session, file, name, signature);
    session.names[name] = %(native (source $filename) (objects $adapter));
  }
  if (file.symbols) file.symbols.cleanup();
  file.symbols = loaded.symbols;
  loaded.symbols = NULL;
  session.files[filename] = (void *) file;
}

/* The file a new `filename` that defines main replaces, or NULL. */
static ReplLoadedFile _retired(
  ReplSession session, Frontend frontend, String filename) {
  if (filename in session.files) return NULL;
  ReplLoadedFile owner = _main_owner(session);
  if (!owner || !_defines_main(frontend, filename)) return NULL;
  // The build collects again with its own helper and package roots.
  Compiler.refresh_source_collections();
  return owner;
}

/** Builds all loaded files and dependencies in one replacement helper.
    Successful loads reset all loaded native state and preserve prompt values
    and callable adapters. A new file that defines main replaces the file
    that defined it. Rejected loads preserve the running helper and its
    state. Top-level prompt evaluation remains interpreted. */
ReplResult ReplSession.load(
  ReplSession session, Frontend frontend, String filename) {
  session.compiler.diagnostics.reset();
  filename = Path.absolute(filename);
  int replacing = filename in session.files;
  ReplResult result = {.status = <rejected>, .value = void};
  Compiler.refresh_source_collections();
  ReplLoadedFile retired = NULL;
  try retired = _retired(session, frontend, filename);
  catch %(repl (reason ?why)): {
    result.message = why;
    return result;
  }
  Array paths = auto [];
  foreach (String path, session.files.keys())
    if (!retired || path != retired.path) paths.push(path);
  if (!replacing) paths.push(filename);
  paths.sort();
  MetaHelper helper = frontend.build_loaded(paths);
  auto Map prepared = {}, dropped = {};
  Array removed = auto [];
  defer {
    if (helper) xfree(helper);
    foreach (Var (path, value), prepared) {
      LoadedSource *loaded = value.pointer();
      if (loaded->globals) loaded->globals.cleanup();
      if (loaded->symbols) loaded->symbols.cleanup();
      xfree(loaded);
    }
  }
  String failure = helper.failure(filename);
  if (failure) {
    result.message = failure;
    return result;
  }
  try {
    Map visible = auto session.compiler.sym.unit_symbols();
    Map published = auto {};
    if (retired)
      foreach (Var key, retired.symbols.keys())
        if (!_shared(session, retired, key)) visible.del(key);
    foreach (String path, paths) {
      LoadedSource *loaded = xcalloc(1, sizeof(LoadedSource));
      prepared[path] = (void *) loaded;
      *loaded = _prepare(frontend, path, helper);
      if (loaded->result.status != <loaded>) return loaded->result;
      if (path == filename) result = loaded->result;
      ReplLoadedFile file = session.files[path].pointer();
      Map normalized = _stable_types(session.compiler, visible, loaded->symbols);
      loaded->symbols.cleanup();
      loaded->symbols = normalized;
      List names = loaded->result.value;
      if (file) _check_replacement(session.compiler, file, normalized);
      _check_names(session, file, retired, visible, normalized, names);
      visible.merge(normalized);
      published.merge(normalized);
    }
    foreach (String path, paths) {
      ReplLoadedFile file = session.files[path].pointer();
      List gone =
        file ? _check_removed(session, file, published, 0, dropped) : NULL;
      if (gone) removed.push($(path, gone));
    }
    if (retired)
      removed.push($(
        retired.path,
        _check_removed(session, retired, published, 1, dropped)));
    helper.retain_executable();
    // Declaration inspection may have called meta code. Runtime starts fresh.
    helper.restart();
  }
  catch %(repl (reason ?why)): {
    result.status = <rejected>;
    result.message = why;
    return result;
  }
  catch %(malformed *): {
    result.status = <rejected>;
    result.diagnostics = session.compiler.diagnostics();
    return result;
  }
  catch %((!or not-found io-fail) *detail): {
    result.status = <rejected>;
    result.message = %"cannot retain compiled helper: $(detail.repr())";
    return result;
  }
  List kept = _remove(session, removed, dropped, retired);
  foreach (String path, paths) {
    LoadedSource *loaded = prepared[path].pointer();
    _publish(session, path, *loaded);
  }
  foreach (List family, kept) _adopt_type(session, family);
  result.removed = removed;
  MetaHelper previous = session.helper;
  session.helper = helper;
  helper = NULL;
  xfree(previous);
  result.status = replacing ? <reloaded> : <loaded>;
  return result;
}
