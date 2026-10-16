/*  repl-load.x -- native source definitions for an interpreted session

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "collect.x"
#include "meta-group.x"
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
  ReplSession session, ReplLoadedFile file, Map visible,
  Map symbols, List names) {
  foreach (String name, names) {
    if (file && %($name) in file.symbols) continue;
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
   their exact declared meaning. */
static void _check_replacement(
  ReplLoadedFile file, Map symbols, Map signatures) {
  foreach (Var (name, signature), file.signatures) {
    Var replacement;
    if (!signatures.try_get(name, replacement))
      _changed(%"function removed: $name");
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
      foreach (String name, names) {
        if (name in globals) {
          foreach (List description, globals[name].list()) {
            (String path, Type bridge, int writable, int dimensions) =
              description;
            MetaHelper.check(c.meta_helper, c, "get global " + path, c.filename);
            if (writable) MetaHelper.check(
              c.meta_helper, c, "set global " + path, c.filename);
          }
        }
        else MetaHelper.check(c.meta_helper, c, name, c.filename);
      }
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

/* Native adapters in the helper check declared value types. This adapter
   refuses references before reading their carrier as a value. */
static Var _call(Func function, const FuncArg *argv) {
  const LoadedCall *call = Func.context(function);
  List parameters = function.signature().car().list().cadr();
  int count = parameters == %((void)) ? 0 : parameters.len();
  Array arguments = $auto([]);
  for (int i = 0; i < count; i++)
    arguments.push(x2c_func_value_argument(function, argv, i, <var>));
  List problem = datum_result_problem(arguments, {});
  if (problem)
    raise %(repl (reason "loaded function arguments must be independent data values")
                 (detail $problem));
  Compiler c = call.session.compiler;
  $let(c.meta_helper, call.session.helper)
    return c.meta_helper_call(call.name, c.token, arguments, call.file.path);
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
    session.names[name] = %(native (source $filename));
  }
  if (file.symbols) file.symbols.cleanup();
  if (file.signatures) file.signatures.cleanup();
  file.symbols = loaded.symbols;
  file.signatures = loaded.signatures;
  loaded.symbols = loaded.signatures = NULL;
  session.files[filename] = (void *) file;
}

/** Builds all loaded files and dependencies in one replacement helper.
    Successful loads reset all loaded native state and preserve prompt values
    and callable adapters. Rejected loads preserve the running helper and its
    state. Top-level prompt evaluation remains interpreted. */
ReplResult ReplSession.load(
  ReplSession session, Frontend frontend, String filename) {
  filename = Path.absolute(filename);
  int replacing = filename in session.files;
  Array paths = $auto(session.files.keys());
  if (!replacing) paths.push(filename);
  paths.sort();
  Compiler.refresh_source_collections();
  MetaHelper helper = frontend.build_loaded(paths.list());
  Map prepared = $auto({});
  ReplResult result = {.status = <rejected>, .value = void};
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
  try {
    helper.check_all(session.compiler);
    Map visible = $auto(session.compiler.sym.unit_symbols());
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
      if (file) _check_replacement(file, normalized, loaded->signatures);
      _check_names(session, file, visible, normalized, names);
      foreach (Var (key, value), normalized) visible[key] = value;
    }
    helper.retain_executable();
    // Declaration inspection may have called meta code. Runtime starts fresh.
    helper.close();
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
  foreach (String path, paths) {
    LoadedSource *loaded = prepared[path].pointer();
    _publish(session, path, *loaded);
  }
  MetaHelper previous = session.helper;
  session.helper = helper;
  helper = NULL;
  Scope.free(previous);
  result.status = replacing ? <reloaded> : <loaded>;
  return result;
}
