/*  meta-native.x -- meta functions and the native code they call

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function runs at compile time through a stub that calls
    its compiled copy, and a bodyless `meta` prototype binds a native
    function that the compiler links, a selected native module defines, or
    a linked package supplies. This unit owns those bindings, the region
    summaries a native signature implies, and the native modules, which a
    request loads once per process and never unloads.
*/

#pragma once
#include "../lib/private-keywords.x"
#include "compiler.x"

#include "grammar.x"
static $(import "../etc/lisp-bindings.xlisp")
#include "macros.x"
#include "meta-group.x"
#include "meta-sdk.x"
#include "meta.x"
#include "stage.x"
#include "utils.x"
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* meta-native diagnostics. */

static macro Stmt $report.macro.function_install(
  Expr $c, Expr $site, Expr $cause) =>
  $c.report_error(
    <macro>,
    "this meta function could not be installed",
    $site, %("reason: ${$cause.repr()}"));

static macro Stmt $report.parse.meta_decl(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "meta requires a function or one initialized static value",
    $site, NULL);

static macro Stmt $report.parse.meta_storage(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <parse>,
    "a meta value must have file-static storage",
    $site, %("declaration: '${$name}'"));

static macro Stmt $report.macro.call_depth(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>,
    "explicit meta call was stopped",
    $site, %("reason: its compile-time form nested too deep"));

static macro Stmt $report.macro.call_deferred(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>,
    "this meta call is left for the translation",
    $site, NULL);

static macro Stmt $report.macro.call_target(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>,
    "explicit meta call cannot be resolved",
    $site, %("only a call to a meta function runs at compile time"));

static macro Stmt $report.macro.call_binding(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <macro>,
    "explicit meta call cannot be resolved",
    $site, %("no binding for ${$name}"));

static macro Stmt $report.parse.meta_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "native meta function requires one direct name",
    $site, NULL);

static macro Stmt $report.type.meta_signature(Expr $c, Expr $site, Expr $n) =>
  $c.report_error(
    <type>,
    "native meta function declaration does not match its target",
    $site, %("name: ${$n.name}" "signature: ${$n.signature.repr()}"));

static macro Stmt $report.type.meta_lifetime(
  Expr $c, Expr $site, Expr $name, Expr $signature) =>
  $c.report_error(
    <type>,
    "unproved native meta lifetime",
    $site, %("name: ${$name}" "signature: ${$signature.repr()}"
    "it might return or keep its argument; ownership cannot be inferred"));

static macro Stmt $report.driver.module_platform(
  Expr $c, Expr $site, Expr $name, Expr $module) =>
  $c.report_error(
    <driver>,
    "native modules are not supported on this platform",
    $site, %("package: ${$name}" "module: ${$module}"));

static macro Stmt $report.driver.module_compiler(
  Expr $c, Expr $site, Expr $name, Expr $module) =>
  $c.report_error(
    <driver>,
    %"package '${$name}' was built by another compiler; rebuild it",
    $site, %("module: ${$module}"));

static macro Stmt $report.macro.outside_compilation(Expr $name) =>
  MetaContext.reject(%"${$name} used outside compilation", NULL);

static macro Stmt $report.native.module_platform() =>
  driver_error("native modules are not supported on this platform");

static macro Stmt $report.native.module_invalid(Expr $path) =>
  driver_error(%"not an x2c native module: ${$path}");

static macro Stmt $report.native.module_compiler(Expr $path) =>
  driver_error(
    %"native module '${$path}' was built by another compiler; rebuild it");

static macro Stmt $report.native.compiler_read(Expr $path) =>
  driver_error(
    %"cannot read the running compiler to check native module '${$path}'");

static macro Stmt $report.native.module_read(Expr $path, Expr $cause) =>
  driver_error(%"cannot read native module '${$path}': ${$cause}");

static macro Stmt $report.native.module_load(Expr $path, Expr $cause) =>
  driver_error(%"cannot load native module '${$path}': ${$cause}");

/* meta functions

   A bodied `meta` function runs at compile time through a stub in the
   unit's session. The stub calls the function's compiled copy in the
   project's helper, or in the REPL the group's native code. */

/** Installs a bodied `meta` function. The project meta build compiled it
    into the project's helper, so the session holds a stub that calls it
    there; the REPL's stub stages the session's group at the first call
    instead, and the project meta build's own parse only groups it. A
    function whose body reaches a compiler operation, a template, or a
    compile-time-only function has no runtime form. A body that lets its
    own storage outlive a call is rejected where the storage leaves.
*/
void Compiler.install_meta_function(Compiler c, List fn, Token marker) {
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  c.check_meta_regions(fn);
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) *) ?): {
      c.native_meta.del(name);
      c.meta_group_bound.del(%"<unbound $name>");
      if (c.meta_reaches_compile_time(fn)) c.record_comptime(name);
      if (c.macro_holes) return;
      c.group_meta_function(fn);
      if (c.meta_build) return;
      if (!macro_library_filling() && !c.shares_meta_definition(name))
        c._install_stub(name, ((List) c.meta_group[-1]).last(), NULL, marker);
    }
}

/** Installs the stub of the bodied `meta` definition `declaration` whose
    body collection skips, so a file-scope constant after it can call it in
    the project's helper. The full parse installs it again. The
    compiler's linked copy answers while its source hashes agree; otherwise
    the definition replaces an earlier binding with a helper stub. A group
    that stages in process waits for the full parse. */
void Compiler.install_collected_meta_function(
  Compiler c, List declaration, Token marker) {
  if (c.source_private < 0) return;
  if (c.signature_only || c.macro_holes || macro_library_filling()) return;
  String name = c._native_meta_name(declaration, marker);
  if (c.shares_meta_definition(name)) return;
  c.ensure_macro_lisp();
  Map linked = _linked_module();
  if (c.groups_meta() && !(name in linked)) return;
  c._install_stub(
    name, declaration.type_from_ast().canonicalize(), NULL, marker);
}

/* A host binding remains in this session; installation failures report at
   the declaration marker. */
static void Compiler._install_stub(
  Compiler c, String name, Type type, String provider, Token marker) {
  String context = %"$name\n${provider ? provider : ""}";
  try c.macro_lisp.set_global(
    name,
    Func.new_context(
      _meta_stub, c.func_signature(type),
      (char *) context, context.len() + 1));
  catch %(?code *detail): {
    List cause = cons(code, detail);
    $report.macro.function_install(c, marker, cause);
  }
}

/* Adapts a call of a bodied `meta` function's session binding, whose
   context holds the function's name, to a call in the project's helper,
   or in the REPL to a call of the group's native code, which the first
   call stages and binds under the name. */
static Var _meta_stub(Func function, const FuncArg *argv) {
  Array values = _stub_arguments(function, argv);
  String context = String.new((const char *) Func.context(function));
  int split = context.find("\n");
  String name = context[:split], provider = context[split + 1:];
  Compiler c = Compiler.expanding();
  if (!c) $report.macro.outside_compilation(name);
  Token site = MetaContext.current().site;
  if (!site) site = c.token;
  if (!provider.len()) {
    Map linked = _linked_module();
    if (name in linked) {
      if (c.shallow && !c._linked_copy(name, linked)) c.complete_meta_hashes();
      if (c._linked_copy(name, linked))
        return c._meta_apply(linked[name], values.list_free());
    }
  }
  if (c.meta_build) raise %(meta-later (name $name));
  List rows = c._subject_rows(values);
  Var previous = Macro.subject();
  Macro.use_subject(rows);
  defer Macro.use_subject(previous);
  if (!c.groups_meta())
    return c.meta_helper_call(name, site, values.list_free(), provider);
  c.bind_meta_group(name, site);
  Var bound;
  c.macro_lisp.try_get(name, bound);
  return c._meta_apply(bound, values.list_free());
}

static Array _stub_arguments(Func function, const FuncArg *argv) {
  List parameters = Func.signature(function).car().list().cadr();
  if (parameters == %((void))) parameters = NULL;
  Array values = [];
  int count = parameters.len();
  for (int i = 0; i < count; i++) values.push(argv[i].data.value);
  return values;
}

/* The caller's global bindings and source-name projections for bindings in
   the arguments, carried through the existing helper subject context. */
static List Compiler._subject_rows(Compiler c, Array values) {
  Map globals = {}, source_names = {};
  foreach (Var value, values) c._subject_globals(value, globals, source_names);
  Array rows = [];
  foreach (Var (spelling, binding), globals) rows.push(%($spelling $binding));
  foreach (Var (binding, spelling), source_names)
    rows.push(%(source-spelling $binding $spelling));
  return rows.list_free();
}

/* Records global identities and source spellings from argument syntax. */
static void Compiler._subject_globals(
  Compiler c, Var value, Map globals, Map source_names) {
  if (value is not <list>) return;
  String spelling = NULL;
  if (binding_identity_try_parts(value, NULL, spelling)) {
    Var source;
    if (c.semantic_binding_facts().try_get(%(source-spelling $value), source))
      source_names[value] = source;
    List global = c.sym.resolve_global(%($spelling), NULL);
    if (global && List.compare(global, value) == 0) globals[spelling] = value;
    return;
  }
  foreach (Var child, value.list())
    c._subject_globals(child, globals, source_names);
}

/* Calls the session value `function` with the evaluated `arguments`. */
static Var Compiler._meta_apply(Compiler c, Var function, List arguments) {
  Array quoted = [%(quote $function)];
  foreach (Var argument, arguments) quoted.push(%(quote $argument));
  return c.macro_lisp.eval(quoted.list_free());
}

/** Applies a contextual `meta` marker to one initialized file-static value.
    The unit's staged `meta` group holds the compile-time instance, which
    its module initializes for each unit. */
void Compiler.install_meta_declaration(
  Compiler c, List declaration, Token marker) {
  match (declaration) {
    case %(declare ?spec
           (bindings
             (op = (bind (binding ? ?(String name)) *) ?))): {
      if (!spec.type().is_static())
        $report.parse.meta_storage(c, marker, name);
      if (c.groups_meta()) c.meta_group.push(%(static $declaration));
      return;
    }
  }
  $report.parse.meta_decl(c, marker);
}

/* explicit meta calls

   A `$f(...)` call of a `meta` function outside a `meta` body runs at
   compile time, and its value becomes syntax at the call. */

/** Executes an explicit meta call and inserts its result at a code
    boundary. */
List Compiler.evaluate_meta_expression(
  Compiler c, List expression, Token site) =>
  c._meta_result(expression, c.evaluate_meta_value(expression, site, 0), site);

/** Executes an explicit meta call written as a whole statement at
    `context`. A code List result binds there, so the call may return a
    statement as well as an expression. */
List Compiler.evaluate_meta_statement(
  Compiler c, List expression, AstPos context, Token site) {
  Var value = c.evaluate_meta_value(expression, site, 0);
  if (c._code_result(value) && !value.is_nil())
    return c.bind_macro_lisp_statement(value, context);
  return %(stmnt ${c._meta_result(expression, value, site)});
}

/* The expression a meta call's `value` becomes at its call. */
static List Compiler._meta_result(
  Compiler c, List expression, Var value, Token site) {
  if (value is void && c.meta_build) {
    List placeholder = %(expr (int) (literal (int) "0"));
    c.meta_group.push(%(later $placeholder));
    return placeholder;
  }
  Type declared = expression.cadr();
  match (expression) case %(expr ? (meta-call (expr ?signature ?) ?)):
    declared = signature.cdr();
  if (declared === %(void))
    return %(expr (void) (cast (void) (expr (int) (literal (int) "0"))));
  if (c._code_result(value)) return c.lift_macro_lisp_expression(value, site);
  List result = c.meta_value_expression(declared, value, site);
  return result ? result : c.lift_macro_lisp_expression(value, site);
}

/* Whether a meta call's result is code. Inside an expansion every List
   is. Elsewhere code is an expression, an identifier, or a pending
   quotation or macro application; other Lists, and any List a pattern
   inserts, are data. */
static int Compiler._code_result(Compiler c, Var value) {
  if (value is not <list>) return 0;
  if (c.macro_stack) return 1;
  if (c.in_pattern) return 0;
  match (value)
    case %((!or expr macro-invoke "x2c.quoted" "x2c.template" "x2c.ident")
           *):
      return 1;
  return binding_identity_try_parts(value, NULL, NULL);
}

/** Runs the explicit meta call `expression` at `site`. The project meta
    build's own parse leaves a project function's call for the translation:
    an expression takes a placeholder, and a template `slot`, which has
    none, is reported. */
Var Compiler.run_meta_call(
  Compiler c, List expression, Token site, int slot) {
  Var value;
  meta_call_form = NULL;
  try value = _meta_call_value(c, expression, site);
  catch %(meta-later *): {
    value = void;
    if (slot)
      $report.macro.call_deferred(c, site);
  }
  catch %(malformed (category ?category)):
    raise %(malformed (category $category));
  catch %(call-stack *):
    $report.macro.call_depth(c, site);
  catch %(?code *detail):
    c.report_lisp_failure(site, cons(code, detail), meta_call_form.repr());
  return value;
}

/* The last call a `$` expression made, which a failure renders. A unit's
   Pool holds it, so each `$` expression starts without one. */
static List meta_call_form = NULL;

/* Calls a `meta` function named at a code boundary with its evaluated
   arguments. */
static Var _meta_call_value(Compiler c, List expression, Token site) {
  match (expression)
    case %(expr ? (meta-call
        (expr ?callee ${$source_identifier_content(
          %((!or (binding ? ?name)
                 ((!or binding-name binding-global) ?name))))})
        (args *arguments))): {
      if (name is not <string>) break;
      String spelling = name;
      Array values = c._meta_values(callee, arguments, site);
      Var function = c._meta_function(spelling, site);
      List applied = values.list_free();
      meta_call_form = cons(Atom.intern(spelling), applied);
      return c._meta_apply(function, applied);
    }
  $report.macro.call_target(c, site);
}

/* Each argument evaluates as the type its parameter declares wants. */
static Array Compiler._meta_values(
  Compiler c, Var callee, List arguments, Token site) {
  List params = NULL;
  match (callee) case %((func ?declared) *): params = declared;
  Array values = [];
  foreach (List argument, arguments) {
    Type want = NULL;
    if (params) {
      want = params.car();
      params = params.cdr();
    }
    values.push(c.meta_argument(argument, want, site, _meta_call_value));
  }
  return values;
}

/* The session's binding of `name`, binding an included native function on
   first use. The project meta build's own parse has no helper yet, so a
   call to a project function there is left for the translation. */
static Var Compiler._meta_function(Compiler c, String name, Token site) {
  Var function = void;
  if (!c.macro_lisp.try_get(name, function) && c.bind_project_meta(name))
    c.macro_lisp.try_get(name, function);
  if (!c.macro_lisp.try_get(name, function) && c.bind_native_meta(name))
    c.macro_lisp.try_get(name, function);
  if (function is void && c.meta_build) raise %(meta-later (name $name));
  if (function is void)
    $report.macro.call_binding(c, site, name);
  return function;
}

/** Records the provider of a public bodied meta function in its interface.
    The provider owns both its native body and its compile-time state. */
void Compiler.record_project_meta_effect(
  Compiler c, List declaration, Token marker) {
  if (c.source_private < 0) return;
  Type type = declaration.type_from_ast().canonicalize();
  if (type.is_static()) return;
  String path = home_portable_path(absolute_path(c.filename));
  String name = c._native_meta_name(declaration, marker);
  if (%(function $name) in c.sym.file_statics()) return;
  c.sym.set(
    %("source-node" (declaration $path ${marker.pos})),
    %(project-meta $name ${c.func_signature(type)} $path ${c.meta_hashes}));
}

/** Installs an included meta function's evaluator advertisement. */
void Compiler.install_project_meta_effect(Compiler c, List row) {
  match (row) case %(project-meta ?name ?signature ?provider ?hashes): {
    c.project_meta[name] = %($signature $provider $hashes);
    c.native_meta.del(name);
    c.meta_group_bound.del(%"<unbound $name>");
    if (!c.meta_build) {
      c.ensure_macro_lisp();
      c._bind_project_meta(name, 1);
    }
  }
}

/** Binds an advertised meta function and reports whether it was found.
    Its provider supplies the helper table and private helpers. */
int Compiler.bind_project_meta(Compiler c, String name) {
  if (!c.project_meta.len())
    c.install_native_meta_effects(c.sym.unit_symbols());
  return c._bind_project_meta(name, 0);
}

/* An include installs its provider at that position. Later lookups keep
   any Lisp definition the unit installs after the include. */
static int Compiler._bind_project_meta(
  Compiler c, String name, int install) {
  Var target;
  if (!c.project_meta.try_get(name, target)) return 0;
  if (c.meta_build) return 0;
  Var bound;
  if (!install && c.macro_lisp.try_get(name, bound)) return 1;
  Var (signature, provider, hashes) = target;
  if (c.project_meta_uses_linked(name, provider, hashes) &&
      c._bind_linked_target(name, signature)) return 1;
  c._install_stub(name, signature, provider, NULL);
  return 1;
}

/** Answers whether a provider's function can use its linked body.
    Copied definitions retain precise callees; runtime bodies retain their
    provider's source dependencies, including private helpers. */
int Compiler.project_meta_uses_linked(
  Compiler c, String name, String provider, Map hashes) {
  Map linked = _linked_module();
  if (!(name in linked)) return 0;
  $let(c.filename, home_absolute_path(provider))
  $let(c.meta_hashes, hashes) $let(c.meta_calls, {})
    return c._linked_copy(name, linked);
}

/* Shipped meta definitions already have Func adapters in their linked
   inventory, separately from the ordinary native prototype registry. */
static int Compiler._bind_linked_target(
  Compiler c, String name, List signature) {
  Var function = _linked_module()[name];
  if (!c.native_meta_accepts(function, signature)) return 0;
  Var bound;
  if (!c.macro_lisp.try_get(name, bound) || !bound.equal(function))
    c.macro_lisp.set_global(name, function);
  return 1;
}

/* native meta functions

   A bodyless `meta` prototype declares a native function compile-time code
   may call. Its advertisement reaches other units through their
   interfaces, and each binds the function on first use. */

/** The shallow interface retains the advertisement separately from the C
    declaration. That lets a client install the trusted evaluator binding
    without repeating the marker in every translation unit. */
void Compiler.record_native_meta_effect(
  Compiler c, List declaration, Token marker) {
  if (c.source_private < 0) return;
  if (!declaration.type_from_ast().is_function()) return;
  String path = home_portable_path(absolute_path(c.filename));
  Type type = declaration.type_from_ast().canonicalize();
  if (type.is_static()) return;
  String name = c._native_meta_name(declaration, marker);
  if (%(function $name) in c.sym.file_statics()) return;
  c.sym.set(
    %("source-node" (declaration $path ${marker.pos})),
    %(native-meta $name ${c.func_signature(type)}));
}

static String Compiler._native_meta_name(
  Compiler c, List declaration, Token marker) {
  String name = NULL;
  match (declaration)
    case %(declare ? (bindings (bind (binding ? ?(String spelling)) *))):
      name = spelling;
  if (!name)
    $report.parse.meta_name(c, marker);
  return name;
}

/** Records the native advertisements retained by included interfaces. Each
    binds on first use, so a unit with no compile-time code pays nothing. */
void Compiler.install_native_meta_effects(Compiler c, Map globs) {
  List unit = %(${absolute_path(c.filename)});
  foreach (Var (key, value), globs) {
    if (_declared_in(key, unit)) continue;
    if (value is <list>) c.install_project_meta_effect(value);
  }
  foreach (Var (key, value), globs) {
    if (_declared_in(key, unit)) continue;
    foreach (List row, c._native_meta_rows(value)) {
      (String name, List signature) = row;
      if (name in c.project_meta) continue;
      c.native_meta[name] = signature;
      c._certify_native_meta(name, signature, NULL);
    }
  }
}

/** Binds an included native `meta` function the first time compile-time
    code calls `name`. Returns whether the macro session now binds it. A
    declaration-producing macro can call one during collection, before
    the parse installs the advertisements, so the first lookup there
    installs the ones visible so far. */
int Compiler.bind_native_meta(Compiler c, String name) {
  if (c.bind_project_meta(name)) return 1;
  Var signature, bound;
  if (!c.native_meta.len())
    c.install_native_meta_effects(c.sym.unit_symbols());
  if (!c.native_meta.try_get(name, signature)) return 0;
  c._bind_native_meta(name, signature, NULL);
  return c.macro_lisp.try_get(name, bound);
}

/** Installs a prototype-only `meta` function from the compiler's trusted
    native target registry. The declaration keeps its ordinary runtime form.
*/
void Compiler.install_native_meta_function(
  Compiler c, List declaration, Token marker) {
  Type type = declaration.type_from_ast().canonicalize();
  String name = c._native_meta_name(declaration, marker);
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  List signature = c.func_signature(type);
  if (c.bind_project_meta(name)) return;
  c.native_meta[name] = signature;
  c._bind_native_meta(name, signature, marker);
}

/* One declared native function while it binds. An iterator operation's
   `target` is `NAME_into`, and `suppliers` lists the selected modules that
   define the target. */
static typedef struct NativeBinding {
  Compiler c, String name, target, List signature, suppliers, Token marker;
  int iterator;
} NativeBinding;

/* Binds a declared native function to the compiler's own linked target of
   the same name, or an iterator operation to its `_into` target, or else to
   a selected native module's target. A declaration with neither binds
   nothing, and a meta body that calls it reports the missing binding. */
static void Compiler._bind_native_meta(
  Compiler c, String name, List signature, Token marker) {
  c._certify_native_meta(name, signature, marker);
  int iterator = _iterator_operation(signature);
  String target = iterator ? %"${name}_into" : name;
  NativeBinding n = {
    .c = c, .name = name, .target = target, .signature = signature,
    .suppliers = _native_module_suppliers(target), .marker = marker,
    .iterator = iterator};
  Var bound, function;
  int present = c.macro_lisp.try_get(name, bound);
  if (present && !iterator) function = bound;
  else {
    try function = n.linked();
    catch %(no-symbol *): {
      /* Staged code that calls it cannot link; the call reports why. */
      if (!n.suppliers) {
        c.meta_group_bound[%"<unbound $name>"] = 1;
        return;
      }
      function = n.module_target();
    }
  }
  n.check(function);
  if (!present) n.install(function);
}

/* The compiler's own linked target, which hides any module's. */
static Var NativeBinding.linked(NativeBinding &n) {
  Compiler c = n.c;
  Var function = c.macro_lisp.eval(
    %(bind ${n.target} (quote ${n.signature})));
  if (n.suppliers)
    c.report_warning(
      <native>, "the compiler's own function hides a native module's",
      n.marker, %("name: ${n.name}"));
  return function;
}

static Var NativeBinding.module_target(NativeBinding &n) {
  String first = n.suppliers.car();
  return ((Map) native_modules[first])[n.target];
}

/* A second module that defines the function is reported, and the
   declaration must match the target it binds. */
static void NativeBinding.check(NativeBinding &n, Var function) {
  Compiler c = n.c;
  List suppliers = n.suppliers;
  if (suppliers.cdr() && function == n.module_target())
    c.report_warning(
      <native>, "more than one native module defines this function",
      n.marker, %("name: ${n.name}" "supplied by: ${suppliers.car()}"
                  "also defined by: ${", ".join(suppliers.cdr())}"));
  if (!c.native_meta_accepts(function, n.signature))
    $report.type.meta_signature(c, n.marker, n);
}

/* An iterator operation binds through a call that allocates the
   destination a call omits. */
static void NativeBinding.install(NativeBinding &n, Var function) {
  Compiler c = n.c;
  if (n.iterator) {
    int arity = n.signature.car().list().cadr().list().len() - 1;
    function = c.macro_lisp.eval(
      %(C.iterator.call (quote $function) $arity));
  }
  c.macro_lisp.set_global(n.name, function);
}

/** Answers whether the native target `function` matches the declared
    `signature`. A declared `Func` parameter matches a target's `Var`
    parameter, which takes the compile-time callable and adapts it. Aliases
    of one native type match each other. */
int Compiler.native_meta_accepts(Compiler c, Var function, List signature) {
  if (function is not <func>) return 0;
  List target =
    c._native_signature_type(((Func) function.pointer()).signature());
  match (signature)
    case %((func ?(List parameters)) *result): {
      List boxed = parameters.search_replace(%("Func"), %("Var"));
      return target == c._native_signature_type(signature) ||
             target == c._native_signature_type(%((func $boxed) @result));
    }
  return 0;
}

/* The native type a signature names: each parameter, reference target,
   and result with its aliases resolved. */
static List Compiler._native_signature_type(Compiler c, List signature) {
  match (signature)
    case %((func ?(List parameters)) *result): {
      Array resolved = [];
      foreach (Type parameter, parameters)
        resolved.push(c._native_parameter(parameter));
      Type native = c.sym.normalize_declared_type(result);
      return %((func ${resolved.list_free()}) @native);
    }
  return signature;
}

static List Compiler._native_parameter(Compiler c, Type parameter) {
  if (parameter.is_reference())
    return cons(
      parameter.car(), c.sym.normalize_declared_type(parameter.cdr()));
  return c.sym.normalize_declared_type(parameter);
}

/** Returns the selected file-backed native module that supplies `name`,
    with its native `type`, or NULL for a linked or absent target. */
String Compiler.native_meta_module(Compiler c, String name, Type &type) {
  if (!c.bind_native_meta(name)) return NULL;
  List suppliers = _native_module_suppliers(name);
  if (!suppliers) return NULL;
  String path = suppliers.car();
  if (!path.startswith("/")) return NULL;
  Var target = ((Map) native_modules[path])[name];
  Var bound;
  if (!c.macro_lisp.try_get(name, bound) || bound != target) return NULL;
  type = ((Func) target.pointer()).signature();
  return path;
}

/* The paths of the selected native modules that define `name`, in order. */
static List _native_module_suppliers(String name) =>
  native_module_order.filter(
    %!(String path) => name in ((Map) native_modules[path]));

/* native lifetimes

   A `meta` body's region walk needs to know what a native function's
   result owns. A function without a runtime row takes the summary its
   signature implies, or is rejected where it is declared. */

/* A declaration whose signature implies no summary is rejected at its
   `marker`; an advertisement read from an interface records nothing. */
static void Compiler._certify_native_meta(
  Compiler c, String name, List signature, Token marker) {
  if (Compiler.has_region_row(name)) return;
  List summary = c._native_meta_summary(signature);
  if (summary) {
    c.meta_regions[name] = summary;
    return;
  }
  if (marker)
    $report.type.meta_lifetime(c, marker, name, signature);
}

/* The region summary of a native function without a runtime row, from its
   signature: a returned handle is a fresh allocation in the active Scope,
   and a handle argument is borrowed for the call. A function that takes a
   handle and returns one, neither owned by its cleanup, might return or
   keep its argument, so it has none. */
static List Compiler._native_meta_summary(Compiler c, List signature) {
  match (signature) case %((func ?(List parameters)) *result): {
    int takes = 0, gives = c._native_handle(result, 0);
    foreach (List parameter, parameters)
      takes = takes ||
              (c._native_handle(parameter, 1) && !c._native_owned(parameter));
    if (takes && gives && !c._native_owned(result)) return NULL;
    return gives ? %(1 ()) : %(0 ());
  }
  return %(0 ());
}

/* Whether a signature type is a native handle: storage the evaluator
   cannot hold as a value, so its lifetime is unknown without a region row.
   Scalars and the value types are not; a parameter pointing at one is an
   input or an output the call finishes with before it returns. */
static int Compiler._native_handle(Compiler c, List type, int parameter) {
  match (type) {
    case %((!quote *) *pointee) if (parameter):
      return pointee == %(void) || c._native_handle(pointee, 0);
    case %((!or "Var" "Symbol" "String" "List" "Array" "Map" "Func")):
      return 0;
  }
  Symbol tag = c.sym.var_tag_for_type(type, NULL);
  if (tag == <var> || tag == <symbol> || tag == <string> ||
      tag == <list> || tag == <array> || tag == <map> || tag == <func>)
    return 0;
  type = c.sym.normalize_declared_type(type);
  foreach (Var part, type) if (part is not Symbol || part == <*>) return 1;
  return 0;
}

/* Whether a handle's own cleanup owns it: a runtime class, or a type that
   adopts `Var` or `Cleanup`. A signature spells a `typedef struct X *X`
   handle as its pointer, so the adoption is read from the typedef `X`. */
static int Compiler._native_owned(Compiler c, List type) {
  match (type) case %((!quote *) struct ?(String tag)): type = %($tag);
  return c.sym.var_tag_for_type(type, NULL) ||
         c.protocol_members_for(type, %("Var")) ||
         c.protocol_members_for(type, %("Cleanup"));
}

/* native target inventory

   The native functions interface rows advertise, as `lib/lisp-targets.x`
   generates its target inventory from them. */

/** Returns the declared native targets advertised by `meta` interface
    rows, in the row form `lib/lisp-targets.x` generates its target
    inventory from, or only those declared in the files `paths` names when
    it is not empty. Sorting makes that inventory independent of Map order.
*/
List Compiler.native_meta_targets(List paths) {
  Compiler c = Compiler.expanding();
  if (!c) return %();
  Map selected = {};
  foreach (Var (key, value), c.sym.base_symbols()) {
    if (paths && !_declared_in(key, paths)) continue;
    foreach (List row, c._native_meta_rows(value)) {
      (String name, List signature) = row;
      if (_takes_callback(signature)) continue;
      String into = %"${name}_into";
      selected[name] = _iterator_operation(signature)
        ? %($name (as $into)) : %($name);
    }
  }
  Array names = selected.keys();
  List rows = %();
  foreach (String name, names.sort()) rows = cons(selected[name], rows);
  return rows.reverse();
}

/* Whether the symbol row under `key` was declared in one of the absolute
   source `paths`. */
static int _declared_in(Var key, List paths) {
  match (key)
    case %("source-node" (declaration ?(String path) ?)):
      return home_absolute_path(path) in paths;
  return 0;
}

/* The native functions one symbol row makes available to compile-time code,
   as `(name signature)` rows: a bodyless `meta` prototype, or each witness
   of a `meta protocol` adoption. */
static List Compiler._native_meta_rows(Compiler c, Var row) {
  match (row) {
    case %(native-meta ?name ?signature): return %(($name $signature));
    case %(meta-protocol ?(Type base) ?(Type participant)):
      return c._witness_rows(base, participant);
  }
  return %();
}

/* The witnesses include the forwarding function the conformance generates
   for a base default. An adoption that does not resolve makes none
   available. */
static List Compiler._witness_rows(Compiler c, Type base, Type participant) {
  List conformance = c.protocol_members_for(participant, base);
  List rows = %();
  if (!conformance) return rows;
  foreach (List member, conformance.last().list().cdr())
    match (member) {
      case %(? implmntd ?(String name) ?(Type type) *):
        rows = cons(%($name ${c.func_signature(type)}), rows);
      case %(?(String name) base-dflt ? ?(Type type) ordinary ?): {
        String forward = %"${participant.car()}_$name";
        rows = cons(%($forward ${c.func_signature(type)}), rows);
      }
    }
  return rows;
}

/* A Lisp callable reaches native code as a `Var`, so a native function that
   takes a `Func` binds through an adapter row in `lib/lisp.x`. */
static int _takes_callback(List signature) {
  match (signature)
    case %((func ?(List parameters)) *): return %("Func") in parameters;
  return 0;
}

/* An iterator operation takes its destination last. Its native target is
   `NAME_into`, and compile-time code calls it through `NAME`, which
   allocates the destination when a call omits it. */
static int _iterator_operation(List signature) {
  match (signature)
    case %((func ?(List parameters)) "Iter"):
      return parameters && parameters.last() == %("Iter");
  return 0;
}

/* linked meta definitions

   The shipped `meta` definitions compiled into the compiler
   (`src/linked-meta.x`) are a native module no request selects. A unit's
   definition binds its linked copy when the definition texts hash the
   same. */

static String linked_supplier = "<linked>";
static Map linked_hashes = NULL;

/** Binds the bodied `meta` definition `fn`, of function type `type`, to the
    compiler's linked copy of it when the two definition texts hash the
    same, instead of staging it. Returns whether it did; an edited
    definition is staged as user code.
*/
int Compiler.bind_linked_meta(Compiler c, List fn, Type type) {
  if (c.meta_build) return 0;
  String name = NULL;
  match (fn)
    case %(function ? (bind (binding ? ?(String own)) *) ?): name = own;
  if (!name) return 0;
  Map linked = _linked_module();
  Var function, bound;
  if (!linked.try_get(name, function)) return 0;
  if (!c._linked_copy(name, linked)) return 0;
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  if (!c.native_meta_accepts(function, c.func_signature(type))) return 0;
  /* Shared preload keeps private helpers in the native code alone. */
  if (!(macro_library_filling() && fn.cadr().type().is_static()) &&
      (!c.macro_lisp.try_get(name, bound) || bound != function))
    c.macro_lisp.set_global(name, function);
  if (c.meta_reaches_compile_time(fn)) c.record_comptime(name);
  return 1;
}

/* The linked module's targets, loaded with the definition hashes on first
   use. */
static Map _linked_module(void) {
  if (!Compiler.native_module_loaded(linked_supplier)) {
    Compiler.add_native_module(linked_supplier, linked_meta_targets);
    $scope(&native_module_scope) linked_hashes = linked_meta_hashes();
    foreach (Var (name, row), linked_hashes) {
      name.string().try_own();
      row.list().try_own();
    }
  }
  return native_modules[linked_supplier];
}

/** Returns the source and dependency hashes compiled into a linked provider. */
List linked_meta_provider_source(String provider) {
  _linked_module();
  return linked_hashes[provider];
}

/* A row without a hash is the runtime library's own compiled definition
   of a `lib/meta.x` builder, which has no copy to compare; only
   `lib/meta.x` itself binds it. */
static int Compiler._linked_copy(Compiler c, String name, Map linked) {
  if (name in linked_hashes) return c._linked_texts_match(name, linked, {});
  return c.filename &&
    Path.absolute(c.filename) == %"${x2c_get_root()}/lib/meta.x";
}

/* Whether the unit's definition `name` and every definition of the unit it
   reaches through references are the texts compiled into the linked
   copies, which freeze their callees into their own code. A reached
   runtime builder without a hash is the runtime's own definition. */
static int Compiler._linked_texts_match(
  Compiler c, String name, Map linked, Map reached) {
  Var hash, own, names = void;
  String key = %"${home_portable_path(c.canonical_path(c.filename))}:$name";
  if (!c.meta_hashes.try_get(name, own)) {
    Var advertisement;
    if (c.project_meta.try_get(name, advertisement)) {
      Var (_, provider, hashes) = advertisement;
      Map dependency = hashes;
      if (!(name in dependency)) return 0;
      $let(c.filename, home_absolute_path(provider))
      $let(c.meta_hashes, hashes) $let(c.meta_calls, {})
        return c._linked_texts_match(name, linked, reached);
    }
    return !(name in linked_hashes);
  }
  if (key in reached) return 1;
  reached[key] = 1;
  if (linked_hashes.try_get(name, hash)) {
    List row = hash;
    hash = row.car();
    names = row.cadr();
    if (hash != own) return 0;
  }
  else if (!(name in linked) && !(name in c.native_meta)) return 0;
  c.meta_calls.try_get(name, names);
  if (names is <string>)
    return c.linked_meta_provider_current(home_absolute_path(names));
  if (names is <list>)
    foreach (String callee, names.list())
      if (!c._linked_texts_match(callee, linked, reached)) return 0;
  return 1;
}

/* native modules

   A native module is a shared library whose entry returns its targets.
   Loading runs its code inside the compiler, so a module loads only on
   request, once per process, and never unloads. */

/* Each loaded native module's name-to-`Func` Map by absolute path, and the
   paths the current request names, in its order. A module stays loaded for
   the process, so its Map lives in a Scope that lasts as long, while each
   request binds only the modules it names. */
static Map native_modules = NULL;
static List native_module_order = NULL;
static Scope native_module_scope = NULL;

/* The compiler supplies the operations `lib/meta.x` declares with a bodyless
   `meta` prototype, the `x2c_` targets, as the native module
   `compiler_supplier`, which every request selects first. */
static macro Expression $compiler.targets() => $(lisp.native.targets
  (filter (lambda (row) (not (eq? (String.startswith (car row) "x2c_") 0)))
    (_x2c.native-meta.targets)));

static String compiler_supplier = "<compiler>";

static Map _compiler_targets(void) => $compiler.targets();

/** Returns the compiler's own targets, the operations `lib/meta.x` declares
    with a bodyless `meta` prototype, loaded as the native module every
    request selects first. */
Map Compiler.compiler_targets(void) {
  _load_compiler_module();
  return _compiler_targets();
}

static void _load_compiler_module(void) {
  if (!Compiler.native_module_loaded(compiler_supplier))
    Compiler.add_native_module(compiler_supplier, _compiler_targets);
}

/** Selects the loaded native modules, by absolute path, that bodyless `meta`
    prototypes bind in the current request. The first module in `paths`
    that defines a name supplies it.
*/
void Compiler.select_native_modules(List paths) {
  _load_compiler_module();
  Array linked = [];
  for (struct _Extension *e = extensions; e; e = e.next) {
    String key = %"<${String.new(e.name)}>";
    if (!Compiler.native_module_loaded(key))
      Compiler.add_native_module(key, e.targets);
    linked.push(key);
  }
  paths = %($compiler_supplier @paths @{linked.list_free()});
  paths.try_own();
  native_module_order = paths;
}

/** Selects package `name`'s native module, when it has one, after the
    modules already selected, and records it as a prerequisite of the unit.
    The module is `<root>/builds/<name>.module`; a worker loads it itself
    when the process has not. A module from another compiler, or one on a
    platform that loads none, is reported at the import `token`.
*/
void Compiler.select_package_module(
  Compiler c, String name, String root, Token token) {
  String module = %"$root/builds/$name.module";
  if (Compiler.links_extension(name) || !Path.is_file(module)) return;
  if (!X2C_NATIVE_MODULES)
    $report.driver.module_platform(c, token, name, module);
  c.add_translation_dependency(module);
  if (!Compiler.native_module_loaded(module))
    c._load_package_module(name, module, token);
  if (module in native_module_order) return;
  $scope(&native_module_scope) {
    native_module_order = native_module_order.append(%($module));
    native_module_order.try_own();
  }
}

static void Compiler._load_package_module(
  Compiler c, String name, String module, Token token) {
  if (_module_stamp(module) != 1)
    $report.driver.module_compiler(c, token, name, module);
  _open_native_module(module);
}

/** Loads the native module at `path` once per process and returns its
    absolute path. Loading runs the module's code inside the compiler, so it
    happens only on request. A module from another compiler, a file that is
    not a module, or an unsupported platform prints a diagnostic and exits.
*/
String Compiler.load_native_module(String path) {
  if (!X2C_NATIVE_MODULES)
    $report.native.module_platform();
  String absolute = Path.absolute(path);
  if (Compiler.native_module_loaded(absolute)) return absolute;
  int stamp = _module_stamp(path);
  if (stamp < 0) $report.native.module_invalid(path);
  if (!stamp)
    $report.native.module_compiler(path);
  _open_native_module(absolute);
  return absolute;
}

/** Loads the native module at absolute `path` when this compiler built it
    and the platform loads modules. A process that loads a module before it
    forks translation workers lets them inherit it; anything else is left
    for the import to report.
*/
void Compiler.preload_native_module(String path) {
  if (X2C_NATIVE_MODULES && !Compiler.native_module_loaded(path) &&
      _module_stamp(path) == 1)
    _open_native_module(path);
}

/* Reads the stamp in the bytes of the module at `path`. Loading runs a
   module's code, so a module from another compiler is rejected before it
   is loaded. */
static int _module_stamp(String path) {
  String expected = build_module_stamp();
  if (!expected)
    $report.native.compiler_read(path);
  File input = fopen(path, "rb");
  if (!input)
    $report.native.module_read(path, String.new(strerror(errno)));
  fseek(input, 0, SEEK_END);
  long end = ftell(input);
  rewind(input);
  char *data = Scope.malloc(end > 0 ? (size_t) end : 1);
  size_t size = end > 0 ? fread(data, 1, (size_t) end, input) : 0;
  input.close();
  int stamp = _stamp_in(data, size, expected);
  Scope.free(data);
  return stamp;
}

/* 1 when the bytes hold one stamp and it names the running compiler, 0
   when it names another compiler or there is more than one, and -1 when
   they hold none. */
static int _stamp_in(char *data, size_t size, String expected) {
  String marker = "x2c-module-stamp:";
  int stamps = 0, current = 0, width = expected.len();
  for (size_t i = 0; i + marker.len() <= size; i++)
    if (!memcmp(data + i, marker, marker.len())) {
      stamps++;
      current = i + width <= size && !memcmp(data + i, expected, width);
    }
  return !stamps ? -1 : stamps == 1 && current;
}

/* Opens the module at absolute `path`, whose stamp was checked, and records
   its targets. Its constructors allocate its Funcs and literals in the
   module Scope, and it is never unloaded, because its Funcs borrow its
   code. */
static void _open_native_module(String path) {
  void *handle = NULL;
  $scope(&native_module_scope) handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!handle)
    $report.native.module_load(path, String.new(dlerror()));
  Map (*entry)(void) = (Map (*)(void)) dlsym(handle, "x2c_module_targets");
  if (!entry) $report.native.module_invalid(path);
  Compiler.add_native_module(path, entry);
}

/** Records the name-to-`Func` Map that the entry of the native module loaded
    from absolute `path` returns. The Funcs, names, signatures, and path last
    for the process.
*/
void Compiler.add_native_module(String path, Map (*entry)(void)) {
  Map targets = NULL;
  $scope(&native_module_scope) {
    if (!(void *) native_modules) {
      Scope.shutdown_hook(_native_module_shutdown);
      native_modules = {};
    }
    targets = entry();
    native_modules[path] = targets;
  }
  path.try_own();
  foreach (Var (name, target), targets) {
    name.string().try_own();
    ((Func) target.pointer()).signature().try_own();
  }
}

static void _native_module_shutdown(void) {
  native_module_scope.destroy();
  native_module_scope = NULL;
  native_modules = NULL;
  native_module_order = NULL;
}

/** Reports whether the native module at absolute `path` is loaded. */
int Compiler.native_module_loaded(String path) =>
  (void *) native_modules && path in native_modules;

/** Returns the name-to-`Func` Map of the loaded native module at absolute
    `path`. */
Map Compiler.native_module_targets(String path) => native_modules[path];

/** Reports whether the compiler itself supplies the native function `name`.
    Such a function exists only inside a compiler, so a `meta` function that
    reaches it has no runtime form.
*/
int Compiler.supplies_native_meta(String name) {
  Var targets;
  return (void *) native_modules &&
         native_modules.try_get(compiler_supplier, targets) &&
         name in ((Map) targets);
}

/* linked extensions

   The packages whose compile-time parts are linked into the compiler. Each
   registers from a constructor, before the runtime starts, so the list is
   plain C storage that lasts for the process. */

static struct _Extension {
  const char *name;
  Map (*targets)(void);
  struct _Extension *next;
} *extensions = NULL;

/** Registers package `name`'s compile-time part, linked into the compiler,
    whose `targets` returns its name-to-`Func` Map. The registration unit
    `x2c build --extension` generates calls it from a constructor.
*/
void x2c_register_extension(const char *name, Map (*targets)(void)) {
  struct _Extension *extension = malloc(sizeof *extension);
  if (!extension) abort();
  *extension = (struct _Extension) { name, targets, extensions };
  extensions = extension;
}

/** Reports whether package `name`'s compile-time part is linked into the
    compiler, so its import loads no module. */
int Compiler.links_extension(String name) {
  for (struct _Extension *e = extensions; e; e = e.next)
    if (!strcmp(name, e.name)) return 1;
  return 0;
}

/** Returns the archive of the linked packages' objects that the build of
    this compiler kept beside it, named by the compiler's identity, or NULL
    when the compiler links none. Project meta code links it. */
String Compiler.extension_archive(void) =>
  extensions ? %"${x2c_get_executable()}.extensions/"
               + %"${compiler_identity()}.a" : NULL;
