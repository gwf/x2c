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
  Map symbols, signatures, globals;
} LoadedSource;

static typedef struct LoadedCall {
  ReplSession session;
  ReplLoadedFile file;
  String name;
} LoadedCall;

/* Collection selects the requested public names and complete type families.
   Generated accessor functions remain private helper targets. */
static List _public_definitions(Compiler c, Map &symbols, Map globals) {
  Array candidates = $auto([]), names = [];
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
    if (%($name) in symbols) names.push(name);
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
  raise %(repl (reason ${detail + "; start a new session"}));
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
      types.pairs.push(%($a $b));
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
  Map forward = $auto({}), reverse = $auto({});
  Array pairs = $auto([]);
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
        if (symbols.try_get(%($kind ${pair.cadr()} @tail), replacement))
          _pair_types(value, replacement, types);
      }
  }
  Array pending = $auto([]);
  foreach (Var name, types.reverse.keys()) pending.push(name);
  foreach (Var (key, value), symbols)
    if (_anonymous_family(key) is void)
      _new_types(c, value, types.reverse, pending);
  for (int i = 0; i < pending.len(); i++)
    foreach (Var (key, value), symbols)
      if (_anonymous_family(key) == pending[i])
        _new_types(c, value, types.reverse, pending);
  Map replacements = $auto({}), normalized = {};
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
      case %((!set ?kind (!or typedef struct union enum)) ?name *):
        family = %($kind $name);
      case %(?name "layout-attribute"): family = %(typedef $name);
    }
    if (family && family in after && !(key in after))
      raise %(repl (reason ${%"conflicting declaration: ${key.repr()}"}));
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
    if (file && %($name) in file.symbols) continue;
    if (retired && name in retired.signatures) continue;
    Var existing;
    if (%($name) in visible || name in session.names ||
        name.startswith("__repl_") ||
        session.evaluator.try_get(name, existing))
      raise %(repl (reason ${%"name already defined: $name"}));
  }
  foreach (Var (key, value), symbols) {
    Var existing;
    String name = _type_name(key, value);
    if (name) {
      List entry = session.inspect(name);
      if (name in names || name.startswith("__repl_") ||
          (entry && entry.car() != <type>) ||
          (!entry && session.evaluator.try_get(name, existing)))
        raise %(repl (reason ${%"name already defined: $name"}));
    }
    if (file && key in file.symbols) continue;
    if (visible.try_get(key, existing) && !existing.equal(value))
      raise %(repl (reason ${%"conflicting declaration: ${key.repr()}"}));
  }
  _check_type_rows(visible, symbols);
  _check_type_rows(symbols, visible);
}

/* Existing prompt code keeps its calling types and layouts. Function
   signatures omit parameter names; receiver metadata and type rows retain
   their exact declared meaning. Returns the functions the file no longer
   defines; no prompt code refers to them. */
static List _check_replacement(
  ReplSession session, ReplLoadedFile file, Map symbols, Map signatures) {
  Array removed = [];
  foreach (Var (name, signature), file.signatures) {
    Var replacement;
    if (!signatures.try_get(name, replacement)) {
      _check_unreferenced(session, name);
      removed.push(name);
      continue;
    }
    if (!signature.equal(replacement))
      _changed(%"function type changed: $name");
    List receiver = %(self $name);
    if (!file.symbols[receiver].equal(symbols[receiver]))
      _changed(%"receiver type changed: $name");
  }
  foreach (Var (key, declaration), file.symbols) {
    match (key) {
      case %(?name): if (name in file.signatures) continue;
      case %(self ?name): if (name in file.signatures) continue;
    }
    Var replacement;
    if (!symbols.try_get(key, replacement) || !declaration.equal(replacement))
      _changed(%"declaration changed or removed: ${key.repr()}");
  }
  return removed.sort().list_free();
}

/* A removed function leaves no prompt function that calls it and no prompt
   variable that holds its Func. */
static void _check_unreferenced(ReplSession session, String name) {
  Compiler c = session.compiler;
  List binding = c.sym.resolve_global(%($name), NULL);
  Var callable = void, stored = void;
  session.evaluator.try_get(name, callable);
  session.evaluator.try_get("C.globals", stored);
  foreach (Var (referrer, entry), session.names)
    match (entry) {
      case %(function (typed ?syntax) *):
        if (_mentions(syntax, binding))
          raise %(repl (reason ${
            %"$name is called by prompt function $referrer"}));
      case %(value):
        if (_holds(c, referrer, stored, callable))
          raise %(repl (reason ${
            %"$name is saved in prompt variable $referrer"}));
    }
}

static int _mentions(Var syntax, List binding) {
  List node;
  $ast.walk(syntax, node) {
    match (node) case %(ident ?found): if (found.equal(binding)) return 1;
  }
  return 0;
}

/* Prompt variables are native objects addressed through `C.globals`. */
static int _holds(Compiler c, String name, Map globals, Var callable) {
  Type type = NULL;
  List binding = c.sym.resolve_global(%($name), type);
  if (callable is not <func> || type != %("Func")) return 0;
  Var address = globals[binding.cadr()];
  return *(Func *) address.pointer() == callable.pointer();
}

/* The loaded file that defines main, or NULL. */
static ReplLoadedFile _main_owner(ReplSession session) {
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    if ("main" in file.signatures) return file;
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

/* A newer main replaces the file that defines main. Its functions leave the
   session as a reload removes them. Public types and globals that only this
   file publishes refuse the replacement, as they refuse a reload. */
static void _check_retired(ReplSession session, ReplLoadedFile retired) {
  String replacing = %"replacing ${retired.path} would remove";
  foreach (List family, retired.types)
    if (!_shared(session, retired, family))
      _changed(%"$replacing ${family.car()} ${family.cadr()}");
  foreach (Var (name, entry), session.names)
    match (entry) case %(global (source ${retired.path}) *):
      _changed(%"$replacing global $name");
  foreach (Var name, retired.signatures.keys())
    _check_unreferenced(session, name);
}

/* Whether another loaded file also publishes the type `family`. */
static int _shared(ReplSession session, ReplLoadedFile retired, List family) {
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    if (file != retired && family in file.symbols) return 1;
  }
  return 0;
}

/* Removes a loaded function's prompt name, callable, and object adapter. The
   adapter's hidden name stays reserved so later adapters number uniquely. */
static void _unpublish(ReplSession session, String name) {
  Compiler c = session.compiler;
  match (session.inspect(name))
    case %(native * (objects (expr ? (ident ?binding)))):
      _forget(session, Ast.binding_spelling(binding));
  _forget(session, name);
  c.sym.undefine_global(%(self $name));
  session.names.del(name);
}

static void _forget(ReplSession session, String name) {
  session.compiler.sym.undefine_global(%($name));
  session.evaluator.remove_global(name);
}

static void _retire(ReplSession session, ReplLoadedFile retired) {
  foreach (Var name, retired.signatures.keys()) _unpublish(session, name);
  session.files.del(retired.path);
  retired.symbols.cleanup();
  retired.signatures.cleanup();
  Scope.free(retired);
}

static Map _signatures(Compiler c, Map symbols, List names) {
  Map signatures = {};
  foreach (String name, names) {
    Type type = symbols[%($name)];
    if (type.is_function()) signatures[name] = c.func_signature(type);
  }
  return signatures;
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
    $let(c.meta_helper, call.session.helper)
      value = operation == <load-call>
        ? c.loaded_helper_call(call.name, c.token, arguments, call.file.path)
        : c.meta_helper_call(call.name, c.token, arguments, call.file.path);
  }
  catch %(malformed *): {
    List failure = NULL;
    foreach (List entry, c.diagnostics()) failure = entry;
    c.diagnostics.release(hold, 0);
    raise %(repl (reason ${_call_failure(c, call.name, result, failure)}));
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
  Array arguments = $auto([]);
  List parameter = parameters;
  for (int i = 0; i < count; i++, parameter = parameter.cdr()) {
    if (_is_record(c, parameter.car()))
      raise %(repl (reason ${call.name + " failed: record values cannot "
                                             "cross the helper boundary"}));
    arguments.push(x2c_func_value_argument(function, argv, i, <var>));
  }
  List problem = datum_result_problem(arguments, {});
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
  List problem = datum_result_problem(arguments, {});
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
  String hidden = %"__repl_call_${session.accessors.len()}";
  c.sym.define_global(%($hidden), type);
  List binding = c.sym.resolve_global(%($hidden), NULL);
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
  Array parameters = $auto([]);
  for (int i = 0; i < dimensions; i++) parameters.push(%(long long));
  if (setter) { parameters.push(bridge); parameters.push(%(int)); }
  if (!parameters.len()) parameters.push(%(void));
  Type type = %((func ${parameters.list()}) @bridge);
  String request = (setter ? "set global " : "get global ") + name;
  String hidden = %"__repl_global_${session.accessors.len()}";
  c.sym.define_global(%($hidden), type);
  List binding = c.sym.resolve_global(%($hidden), NULL);
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
      paths[path] = %($get $set);
    }
    session.names[name] = %(global (source ${file.path}) $paths);
  }
}

/* Publishes already checked declarations while preserving existing adapters. */
static void _publish(
  ReplSession session, String filename, LoadedSource &loaded) {
  ReplLoadedFile file = session.files[filename].pointer();
  if (!file) {
    file = Scope.calloc(1, sizeof(struct ReplLoadedFile));
    file.path = filename;
  }
  Map visible = $auto(session.compiler.sym.unit_symbols());
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
  foreach (Var (name, signature), loaded.signatures) {
    if (file.signatures && name in file.signatures) continue;
    LoadedCall call = {.session = session, .file = file, .name = name};
    Func function = Func.new_context(_call, signature, &call, sizeof call);
    session.evaluator.set_global(name, function);
    List adapter = _object_adapter(session, file, name, signature);
    session.names[name] = %(native (source $filename) (objects $adapter));
  }
  if (file.signatures)
    foreach (Var name, file.signatures.keys())
      if (!(name in loaded.signatures)) _unpublish(session, name);
  if (file.symbols) file.symbols.cleanup();
  if (file.signatures) file.signatures.cleanup();
  file.symbols = loaded.symbols;
  file.signatures = loaded.signatures;
  loaded.symbols = loaded.signatures = NULL;
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
  _check_retired(session, owner);
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
  Array paths = $auto([]);
  foreach (String path, session.files.keys())
    if (!retired || path != retired.path) paths.push(path);
  if (!replacing) paths.push(filename);
  paths.sort();
  MetaHelper helper = frontend.build_loaded(paths);
  Map prepared = $auto({});
  Array removed = $auto([]);
  defer {
    if (helper) Scope.free(helper);
    foreach (Var (path, value), prepared) {
      LoadedSource *loaded = value.pointer();
      if (loaded->globals) loaded->globals.cleanup();
      if (loaded->symbols) loaded->symbols.cleanup();
      if (loaded->signatures) loaded->signatures.cleanup();
      Scope.free(loaded);
    }
  }
  String failure = helper.failure(filename);
  if (failure) {
    result.message = failure;
    return result;
  }
  try {
    Map visible = $auto(session.compiler.sym.unit_symbols());
    if (retired) {
      foreach (Var name, retired.signatures.keys()) {
        visible.del(%($name));
        visible.del(%(self $name));
      }
      removed.push(
        %(${retired.path} ${retired.signatures.keys().list().sort()}));
    }
    foreach (String path, paths) {
      LoadedSource *loaded = Scope.calloc(1, sizeof(LoadedSource));
      prepared[path] = (void *) loaded;
      *loaded = _prepare(frontend, path, helper);
      if (loaded->result.status != <loaded>) return loaded->result;
      if (path == filename) result = loaded->result;
      ReplLoadedFile file = session.files[path].pointer();
      Map normalized = _stable_types(session.compiler, visible, loaded->symbols);
      loaded->symbols.cleanup();
      loaded->symbols = normalized;
      List names = loaded->result.value;
      loaded->signatures = _signatures(session.compiler, normalized, names);
      List gone = file
        ? _check_replacement(session, file, normalized, loaded->signatures)
        : NULL;
      if (gone) removed.push(%($path $gone));
      _check_names(session, file, retired, visible, normalized, names);
      foreach (Var (key, value), normalized) visible[key] = value;
    }
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
    result.message = %"cannot retain compiled helper: ${detail.repr()}";
    return result;
  }
  if (retired) _retire(session, retired);
  foreach (String path, paths) {
    LoadedSource *loaded = prepared[path].pointer();
    _publish(session, path, *loaded);
  }
  result.removed = removed;
  MetaHelper previous = session.helper;
  session.helper = helper;
  helper = NULL;
  Scope.free(previous);
  result.status = replacing ? <reloaded> : <loaded>;
  return result;
}
