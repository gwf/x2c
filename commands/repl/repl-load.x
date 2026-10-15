/*  repl-load.x -- native source definitions for an interpreted session

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "collect.x"
#include "meta-group.x"
#include "meta-project.x"
#include "datum.x"

static typedef struct LoadedSource {
  ReplResult result;
  Map symbols, signatures;
  MetaHelper helper;
} LoadedSource;

static typedef struct LoadedCall {
  Compiler compiler;
  MetaHelper helper;
  String name, provider;
} LoadedCall;

/* Collection already selected public declarations and complete type
   families. Only public bodied meta functions become prompt entry points. */
static List _public_functions(Compiler c, Map &symbols) {
  Array candidates = $auto([]), names = [];
  foreach (List entry, c.meta_group)
    match (entry) case %(function ? ?name ?): candidates.push(name);
  symbols = c.callable_symbols(candidates);
  foreach (String name, candidates)
    if (%($name) in symbols) names.push(name);
  return names.list_free();
}

/* Source declarations cannot change the types or meanings of live values. */
static void _check_names(ReplSession session, Map symbols, List names) {
  Map visible = session.compiler.sym.unit_symbols();
  foreach (String name, names) {
    Var existing;
    if (%($name) in visible || name in session.names ||
        name.startswith("__repl_") ||
        session.evaluator.try_get(name, existing))
      raise %(repl (reason ${%"name already defined: $name"}));
  }
  foreach (Var (key, value), symbols) {
    Var existing;
    if (visible.try_get(key, existing) && !existing.equal(value))
      raise %(repl (reason ${%"conflicting declaration: ${key.repr()}"}));
  }
}

static Map _signatures(Compiler c, Map symbols, List names) {
  Map signatures = {};
  foreach (String name, names) {
    MetaHelper.check(c.meta_helper, c, name, c.filename);
    signatures[name] = c.func_signature(symbols[%($name)]);
  }
  return signatures;
}

/* Each load keeps its own helper. Only declarations and diagnostics leave
   the source Context; native results later cross the existing datum protocol. */
static LoadedSource _prepare(
  ReplSession session, Frontend frontend, String filename) {
  Compiler.refresh_source_collections();
  LoadedSource loaded = {
    .result = {.status = <rejected>, .value = void},
    .helper = frontend.build_meta(%($filename))};
  defer if (loaded.result.status != <loaded>) loaded.helper.close();
  ParsedUnit unit;
  int opened = frontend.start(filename, unit);
  defer unit.close();
  Compiler c = unit.compiler;
  c.meta_helper = loaded.helper;
  c.begin_meta_unit(c.filename);
  opened = opened && unit.collect(frontend) && unit.parse();
  try {
    if (opened) {
      Map symbols = NULL;
      List names = _public_functions(c, symbols);
      if (!names)
        raise %(repl (reason "no public bodied meta functions found"));
      _check_names(session, symbols, names);
      Map signatures = _signatures(c, symbols, names);
      loaded.symbols = unit.context.export(symbols);
      loaded.signatures = unit.context.export(signatures);
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
  Compiler c = call.compiler;
  $let(c.meta_helper, call.helper)
    return c.meta_helper_call(call.name, c.token, arguments, call.provider);
}

static void _publish_types(ReplSession session, Map symbols) {
  foreach (Var (key, value), symbols) {
    String name = NULL;
    match (key) {
      case %(?(String spelling)):
        if (value.list().type().is_typedef()) name = spelling;
      case %((!or struct union enum) ?(String spelling)): name = spelling;
    }
    if (name) session.names[name] = %(type);
  }
}

/** Compiles a source file's public bodied meta functions and their source
    dependencies in an independent helper. Publishes their callable bindings
    and public types; prompt evaluation remains interpreted. Calls exchange
    values through the project meta helper's datum protocol. A rejected load
    leaves existing names and native static values unchanged.
    A loaded result's value is the List of published function names.
*/
ReplResult ReplSession.load(
  ReplSession session, Frontend frontend, String filename) {
  LoadedSource loaded = _prepare(session, frontend, filename);
  if (loaded.result.status != <loaded>) return loaded.result;
  try loaded.helper.retain_executable();
  catch %((!or not-found io-fail) *detail): {
    loaded.helper.close();
    loaded.result.status = <rejected>;
    loaded.result.message = %"cannot retain compiled helper: ${detail.repr()}";
    return loaded.result;
  }
  foreach (Var (key, type), loaded.symbols)
    session.compiler.sym.define_global(key, type);
  _publish_types(session, loaded.symbols);
  foreach (Var (name, signature), loaded.signatures) {
    LoadedCall call = {
      .compiler = session.compiler, .helper = loaded.helper,
      .name = name, .provider = Path.absolute(filename)};
    Func function = Func.new_context(_call, signature, &call, sizeof call);
    session.evaluator.set_global(name, function);
    session.names[name] = %(native);
  }
  session.helpers.push((void *) loaded.helper);
  return loaded.result;
}
