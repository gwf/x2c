/*  meta-native.x -- meta functions and the native code they call

    Copyright (c) 2026 Gary William Flake.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"

#pragma private
$(import "../src/grammar.xmacro")
#include "macros.x"
#include "meta-group.x"
#include "meta-sdk.x"
#include "meta.x"
#include "utils.x"
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* meta functions

   A bodied `meta` function runs at compile time through a stub in the
   unit's session. The stub calls the function's compiled copy in the
   project's helper, or in the REPL the group's native code. */

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
        c.report_error(
          <parse>, "a meta value must have file-static storage", marker,
          %("declaration: '$name'"));
      if (c.groups_meta()) c.meta_group.push(%(static $declaration));
      return;
    }
  }
  c.report_error(
    <parse>, "meta requires a function or one initialized static value",
    marker, NULL);
}

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
  _ensure_lisp(c);
  c.check_meta_regions(fn);
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) *) ?): {
      if (c.meta_reaches_compile_time(fn)) _record_comptime(c, name);
      if (c.macro_holes) return;
      c.group_meta_function(fn);
      if (c.meta_build) return;
      if (!macro_library_filling() && !_shared_meta_definition(c, name))
        _install_stub(c, name, marker);
    }
}

/* A session refuses to replace a name an ancestor binds, which reaches the
   developer here, at the marker. */
static void _install_stub(Compiler c, String name, Token marker) {
  Type type = ((List) c.meta_group[-1]).last();
  try c.macro_lisp.set_global(
    name,
    Func.new_context(
      _meta_stub, c.func_signature(type), (char *) name, name.len() + 1));
  catch %(?code *detail): {
    List cause = cons(code, detail);
    c.report_error(
      <macro>, "this meta function could not be installed", marker,
      %("reason: ${cause.repr()}"));
  }
}

/* Adapts a call of a bodied `meta` function's session binding, whose
   context holds the function's name, to a call in the project's helper,
   or in the REPL to a call of the group's native code, which the first
   call stages and binds under the name. */
static Var _meta_stub(Func function, const FuncArg *argv) {
  Array values = _stub_arguments(function, argv);
  String name = String.new((const char *) Func.context(function));
  Token site;
  Compiler c = _stub_compiler(name, site);
  List rows = _subject_rows(c, values);
  Var previous = Macro.subject();
  Macro.use_subject(rows);
  defer Macro.use_subject(previous);
  if (!c.groups_meta())
    return c.meta_helper_call(name, site, values.list_free());
  c.bind_meta_group(name, site);
  Var bound;
  c.macro_lisp.try_get(name, bound);
  return _meta_apply(c, bound, values.list_free());
}

static Array _stub_arguments(Func function, const FuncArg *argv) {
  List parameters = Func.signature(function).car().list().cadr();
  if (parameters.equal(%((void)))) parameters = NULL;
  Array values = [];
  for (int i = 0; i < parameters.len(); i++)
    values.push(argv[i].data.value);
  return values;
}

/* The compiler that runs a stub's call, and where the call stands. */
static Compiler _stub_compiler(String name, Token &site) {
  Compiler c = Compiler.expanding();
  if (!c) MetaContext.reject(%"$name used outside compilation", NULL);
  site = MetaContext.current().site;
  if (!site) site = c.token;
  return c;
}

/* The caller's global bindings and source-name projections for bindings in
   the arguments, carried through the existing helper subject context. */
static List _subject_rows(Compiler c, Array values) {
  Map globals = {}, source_names = {};
  foreach (Var value, values)
    _subject_globals(c, value, globals, source_names);
  Array rows = [];
  foreach (Var (spelling, binding), globals) rows.push(%($spelling $binding));
  foreach (Var (binding, spelling), source_names)
    rows.push(%(source-spelling $binding $spelling));
  return rows.list_free();
}

/* Records global identities and source spellings from argument syntax. */
static void _subject_globals(
  Compiler c, Var value, Map globals, Map source_names) {
  if (value is not <list>) return;
  String spelling = NULL;
  if (binding_identity_try_parts(value, NULL, spelling)) {
    Var source;
    if (c.semantic_binding_facts().try_get(
          %(source-spelling $value), source))
      source_names[value] = source;
    List global = c.sym.resolve_global(%($spelling), NULL);
    if (global && List.compare(global, value) == 0)
      globals[spelling] = value;
    return;
  }
  foreach (Var child, value.list())
    _subject_globals(c, child, globals, source_names);
}

/* Calls the session value `function` with the evaluated `arguments`. */
static Var _meta_apply(Compiler c, Var function, List arguments) {
  Array quoted = [%(quote $function)];
  foreach (Var argument, arguments) quoted.push(%(quote $argument));
  return c.macro_lisp.eval(quoted.list_free());
}

/* explicit meta calls

   A `$f(...)` call of a `meta` function outside a `meta` body runs at
   compile time, and its value becomes syntax at the call. */

/** Executes an explicit meta call and inserts its result at a code
    boundary. */
List Compiler.evaluate_meta_expression(
  Compiler c, List expression, Token site) {
  Var value = _evaluate_meta_value(c, expression, site, 0);
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
  if (c.macro_stack && value is <list>)
    return c.lift_macro_lisp_expression(value, site);
  List result = c.meta_value_expression(declared, value, site);
  return result ? result : c.lift_macro_lisp_expression(value, site);
}

/* Evaluates the explicit meta call `expression` at `site` with the active
   expansion's captures visible to the SDK. */
static Var _evaluate_meta_value(
  Compiler c, List expression, Token site, int slot) {
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  List active = c.macro_stack ? c.macro_stack.car() : NULL;
  List bindings = active ? active.caddr() : NULL;
  String source_file = active ? _definition_file(active.car()) : c.filename;
  MetaContext *context = MetaContext.current();
  $let(context.references, !!bindings)
  $let(context.captures, _source_captures(bindings))
  $let(context.file, source_file)
  $let(context.expansion, c)
  $let(context.evaluator, c)
  $let(context.site, site)
    return _run_meta_call(c, expression, site, slot);
}

/* The project meta build's own parse leaves a project function's call for
   the translation: an expression takes a placeholder, and a template
   `slot`, which has none, is reported. */
static Var _run_meta_call(Compiler c, List expression, Token site, int slot) {
  Var value;
  try value = _meta_call_value(c, expression, site);
  catch %(meta-later *): {
    value = void;
    if (slot)
      c.report_error(
        <macro>, "this meta call is left for the translation", site, NULL);
  }
  catch %(malformed (category ?category)):
    raise %(malformed (category $category));
  catch %(call-stack *):
    c.report_error(
      <macro>, "explicit meta call was stopped", site,
      %("reason: its compile-time form nested too deep"));
  catch %(?code *detail):
    _report_lisp_failure(c, site, cons(code, detail), meta_call_form);
  return value;
}

/* Both entry forms expose source only for complete captures in the active
   expansion. The keys are the same unwrapped values passed to the helper. */
static Map _source_captures(List bindings) {
  Map captures = {};
  foreach (List pair, bindings) {
    List source;
    Var syntax;
    if (pair && _source_capture_parts(pair.cadr(), source, syntax))
      captures[((ulong) syntax.u64)] = source;
  }
  return captures;
}

/* The last call a `$` expression made, as a failure reports it. */
static String meta_call_form = NULL;

/* Calls a `meta` function named at a code boundary with its evaluated
   arguments. */
static Var _meta_call_value(Compiler c, List expression, Token site) {
  match (expression)
    case %(expr ? (meta-call ?(List target) (args *arguments))): {
      List call_target = target;
      match (call_target)
        case %(expr ?callee ${$source_identifier_content(
            %((binding ? ?name)))}): {
          if (name is not <string>) break;
          String spelling = name;
          Array values = _meta_values(c, callee, arguments, site);
          Var function = _meta_function(c, spelling, site);
          List applied = values.list_free();
          meta_call_form = cons(Atom.intern(spelling), applied).repr();
          meta_call_form.try_own();
          return _meta_apply(c, function, applied);
        }
    }
  c.report_error(
    <macro>, "explicit meta call cannot be resolved", site,
    %("only a call to a meta function runs at compile time"));
}

/* Each argument evaluates as the type its parameter declares wants. */
static Array _meta_values(
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
static Var _meta_function(Compiler c, String name, Token site) {
  Var function = void;
  if (!c.macro_lisp.try_get(name, function) && c.bind_native_meta(name))
    c.macro_lisp.try_get(name, function);
  if (function is void && c.meta_build) raise %(meta-later (name $name));
  if (function is void)
    c.report_error(
      <macro>, "explicit meta call cannot be resolved", site,
      %("no binding for $name"));
  return function;
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
  String path = home_portable_path(Path.absolute(c.filename));
  List key = %("source-node" (declaration $path ${marker.pos}));
  if (declaration.type_from_ast().is_function()) {
    Type type = declaration.type_from_ast().canonicalize();
    String name = _native_meta_name(c, declaration, marker);
    List signature = c.func_signature(type);
    c.sym.set(key, %(native-meta $name $signature));
  }
}

static String _native_meta_name(Compiler c, List declaration, Token marker) {
  String name = NULL;
  match (declaration)
    case %(declare ? (bindings (bind (binding ? ?(String spelling)) *))):
      name = spelling;
  if (!name)
    c.report_error(
      <parse>, "native meta function requires one direct name", marker, NULL);
  return name;
}

/** Records the native advertisements retained by included interfaces. Each
    binds on first use, so a unit with no compile-time code pays nothing. */
void Compiler.install_native_meta_effects(Compiler c, Map globs) {
  String unit = Path.absolute(c.filename);
  foreach (Var (key, value), globs) {
    if (_local_effect(unit, key)) continue;
    foreach (List row, _native_meta_rows(c, value)) {
      (String name, List signature) = row;
      c.native_meta[name] = signature;
      _certify_native_meta(c, name, signature, NULL);
    }
  }
}

static int _local_effect(String unit, Var key) {
  match (key)
    case %("source-node" (declaration ?(String path) ?)):
      return home_absolute_path(path).equal(unit);
  return 0;
}

/** Binds an included native `meta` function the first time compile-time
    code calls `name`. Returns whether the macro session now binds it. A
    macro import can call one during the caller's collection pass, before
    the parse installs the advertisements, so the first lookup there
    installs the ones visible so far. */
int Compiler.bind_native_meta(Compiler c, String name) {
  Var signature, bound;
  if (!c.native_meta.len())
    c.install_native_meta_effects(_visible_symbols(c));
  if (!c.native_meta.try_get(name, signature)) return 0;
  _bind_native_meta(c, name, signature, NULL);
  return c.macro_lisp.try_get(name, bound);
}

/* The unit's base symbols with the current scope's rows merged in. */
static Map _visible_symbols(Compiler c) {
  Map symbols = c.sym.base_symbols();
  Map current = c.sym.current_symbols();
  if (current) symbols.merge(current);
  return symbols;
}

/** Installs a prototype-only `meta` function from the compiler's trusted
    native target registry. The declaration keeps its ordinary runtime form.
*/
void Compiler.install_native_meta_function(
  Compiler c, List declaration, Token marker) {
  Type type = declaration.type_from_ast().canonicalize();
  String name = _native_meta_name(c, declaration, marker);
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  List signature = c.func_signature(type);
  c.native_meta[name] = signature;
  _bind_native_meta(c, name, signature, marker);
}

/* One declared native function while it binds. An iterator operation's
   `target` is `NAME_into`, and `suppliers` lists the selected modules that
   define the target. */
typedef struct NativeBinding {
  Compiler c, String name, target, List signature, suppliers, Token marker;
  int iterator;
} NativeBinding;

/* Binds a declared native function to the compiler's own linked target of
   the same name, or an iterator operation to its `_into` target, or else to
   a selected native module's target. A declaration with neither binds
   nothing, and a meta body that calls it reports the missing binding. */
static void _bind_native_meta(
  Compiler c, String name, List signature, Token marker) {
  _certify_native_meta(c, name, signature, marker);
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
static Var NativeBinding.linked(NativeBinding *n) {
  Compiler c = n.c;
  Var function = c.macro_lisp.eval(
    %(bind ${n.target} (quote ${n.signature})));
  if (n.suppliers)
    c.report_warning(
      <native>, "the compiler's own function hides a native module's",
      n.marker, %("name: ${n.name}"));
  return function;
}

static Var NativeBinding.module_target(NativeBinding *n) {
  String first = n.suppliers.car();
  return ((Map) native_modules[first])[n.target];
}

/* A second module that defines the function is reported, and the
   declaration must match the target it binds. */
static void NativeBinding.check(NativeBinding *n, Var function) {
  Compiler c = n.c;
  String name = n.name;
  List suppliers = n.suppliers;
  if (suppliers.cdr() &&
      function.equal(((Map) native_modules[suppliers.car()])[n.target]))
    c.report_warning(
      <native>, "more than one native module defines this function",
      n.marker, %("name: $name" "supplied by: ${suppliers.car()}"
                  "also defined by: ${", ".join(suppliers.cdr())}"));
  if (!c.native_meta_accepts(function, n.signature))
    c.report_error(
      <type>, "native meta function declaration does not match its target",
      n.marker, %("name: $name" "signature: ${n.signature.repr()}"));
}

/* An iterator operation binds through a call that allocates the
   destination a call omits. */
static void NativeBinding.install(NativeBinding *n, Var function) {
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
  List target = _native_signature_type(
    c, ((Func) function.pointer()).signature());
  match (signature)
    case %((func ?(List parameters)) *result): {
      List boxed = parameters.search_replace(%("Func"), %("Var"));
      return target.equal(_native_signature_type(c, signature)) ||
             target.equal(_native_signature_type(c, %((func $boxed) @result)));
    }
  return 0;
}

/* The native type a signature names: each parameter, reference target,
   and result with its aliases resolved. */
static List _native_signature_type(Compiler c, List signature) {
  match (signature)
    case %((func ?(List parameters)) *result): {
      Array resolved = [];
      foreach (Type parameter, parameters)
        resolved.push(_native_parameter(c, parameter));
      Type native = c.sym.normalize_declared_type(result);
      return %((func ${resolved.list_free()}) @native);
    }
  return signature;
}

static List _native_parameter(Compiler c, Type parameter) {
  if (parameter.car() == <&> || parameter.car() == <opt-ref>)
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
  if (!c.macro_lisp.try_get(name, bound) || !bound.equal(target)) return NULL;
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

/* A native function without a runtime row takes the summary its signature
   implies, so a `meta` body's walk knows what its result owns. */
static void _certify_native_meta(
  Compiler c, String name, List signature, Token marker) {
  if (Compiler.has_region_row(name)) return;
  List summary = _native_meta_summary(c, signature);
  if (summary) {
    c.meta_regions[name] = summary;
    return;
  }
  if (marker)
    c.report_error(
      <type>, "unproved native meta lifetime", marker,
      %("name: $name" "signature: ${signature.repr()}"
        "it might return or keep its argument; ownership cannot be inferred"));
}

/* The region summary of a native function without a runtime row, from its
   signature: a returned handle is a fresh allocation in the active Scope,
   and a handle argument is borrowed for the call. A function that takes a
   handle and returns one, neither owned by its cleanup, might return or
   keep its argument, so it has none. */
static List _native_meta_summary(Compiler c, List signature) {
  match (signature) case %((func ?(List parameters)) *result): {
    int takes = 0, gives = _native_handle(c, result, 0);
    foreach (List parameter, parameters)
      takes = takes ||
              (_native_handle(c, parameter, 1) &&
               !_native_owned(c, parameter));
    if (takes && gives && !_native_owned(c, result)) return NULL;
    return gives ? %(1 ()) : %(0 ());
  }
  return %(0 ());
}

/* Whether a signature type is a native handle: storage the evaluator
   cannot hold as a value, so its lifetime is unknown without a region row.
   Scalars and the value types are not; a parameter pointing at one is an
   input or an output the call finishes with before it returns. */
static int _native_handle(Compiler c, List type, int parameter) {
  match (type) {
    case %((!quote *) *pointee) if (parameter):
      return pointee.equal(%(void)) || _native_handle(c, pointee, 0);
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
static int _native_owned(Compiler c, List type) {
  match (type) case %((!quote *) struct ?(String tag)): type = %($tag);
  return c.sym.var_tag_for_type(type, NULL) ||
         c.protocol_members_for(type, %("Var")) ||
         c.protocol_members_for(type, %("Cleanup"));
}

/* native target inventory

   The native functions interface rows advertise, as `lib/lisp-targets.x`
   generates its target inventory from them. */

/* Returns the declared native targets advertised by `meta` interface rows,
   in the row form `lib/lisp-targets.x` generates its target inventory
   from, or only those declared in the files `paths` names when it is not
   empty. Sorting makes that inventory independent of Map order. */
static List _native_meta_targets(List paths) {
  Compiler compiler = Compiler.expanding();
  if (!compiler) return %();
  Map selected = {};
  foreach (Var (key, value), compiler.sym.base_symbols()) {
    if (paths && !_declared_in(key, paths)) continue;
    foreach (List row, _native_meta_rows(compiler, value)) {
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
static List _native_meta_rows(Compiler c, Var row) {
  match (row) {
    case %(native-meta ?name ?signature): return %(($name $signature));
    case %(meta-protocol ?(Type base) ?(Type participant)):
      return _witness_rows(c, base, participant);
  }
  return %();
}

/* The witnesses include the forwarding function the conformance generates
   for a base default. An adoption that does not resolve makes none
   available. */
static List _witness_rows(Compiler c, Type base, Type participant) {
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
      return parameters && parameters.last().equal(%("Iter"));
  return 0;
}

static List _sdk_meta_targets(void) => _native_meta_targets(NULL);

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _sdk_meta_declared(List paths) {
  List rows = _native_meta_targets(paths);
  if (!rows)
    MetaContext.reject(
      "native module sources declare no meta function",
      %("declare each exported function with a bodyless meta prototype"));
  return rows;
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
  String name = NULL;
  match (fn)
    case %(function ? (bind (binding ? ?(String own)) *) ?): name = own;
  if (!name) return 0;
  Map linked = _linked_module();
  Var function, bound;
  if (!linked.try_get(name, function)) return 0;
  if (!_linked_copy(c, name, linked)) return 0;
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  if (!c.native_meta_accepts(function, c.func_signature(type))) return 0;
  /* The shared session binds the copy once for every unit that imports the
     same file. */
  if (!c.macro_lisp.try_get(name, bound) || bound.equal(%()))
    c.macro_lisp.set_global(name, function);
  if (c.meta_reaches_compile_time(fn)) _record_comptime(c, name);
  return 1;
}

/* The linked module's targets, loaded with the definition hashes on first
   use. */
static Map _linked_module(void) {
  if (!Compiler.native_module_loaded(linked_supplier)) {
    Compiler.add_native_module(linked_supplier, linked_meta_targets);
    $scope(&native_module_scope) linked_hashes = linked_meta_hashes();
  }
  return native_modules[linked_supplier];
}

/* A row without a hash is the runtime library's own compiled definition
   of a `lib/meta.x` builder, which has no copy to compare; only
   `lib/meta.x` itself binds it. */
static int _linked_copy(Compiler c, String name, Map linked) {
  if (name in linked_hashes) return _linked_texts_match(c, name, linked, {});
  return c.filename &&
    Path.absolute(c.filename) == %"${x2c_get_root()}/lib/meta.x";
}

/* Whether the unit's definition `name` and every definition of the unit it
   reaches through references are the texts compiled into the linked
   copies, which freeze their callees into their own code. A reached
   runtime builder without a hash is the runtime's own definition. */
static int _linked_texts_match(
  Compiler c, String name, Map linked, Map reached) {
  Var hash, own, names;
  if (name in reached || !c.meta_hashes.try_get(name, own)) return 1;
  reached[name] = 1;
  if (linked_hashes.try_get(name, hash)) {
    if (!hash.equal(own)) return 0;
  }
  else if (!(name in linked)) return 0;
  if (c.meta_calls.try_get(name, names))
    foreach (String callee, (List) names)
      if (!_linked_texts_match(c, callee, linked, reached)) return 0;
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

/** Selects the loaded native modules, by absolute path, that bodyless `meta`
    prototypes bind in the current request. The first module in `paths`
    that defines a name supplies it.
*/
void Compiler.select_native_modules(List paths) {
  if (!Compiler.native_module_loaded(compiler_supplier))
    Compiler.add_native_module(compiler_supplier, _compiler_targets);
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
    c.report_error(
      <driver>, "native modules are not supported on this platform", token,
      %("package: $name" "module: $module"));
  c.add_translation_dependency(module);
  if (!Compiler.native_module_loaded(module))
    _load_package_module(c, name, module, token);
  if (module in native_module_order) return;
  $scope(&native_module_scope) {
    native_module_order = native_module_order.append(%($module));
    native_module_order.try_own();
  }
}

static void _load_package_module(
  Compiler c, String name, String module, Token token) {
  if (_module_stamp(module) != 1)
    c.report_error(
      <driver>,
      %"package '$name' was built by another compiler; rebuild it", token,
      %("module: $module"));
  _open_native_module(module);
}

/** Loads the native module at `path` once per process and returns its
    absolute path. Loading runs the module's code inside the compiler, so it
    happens only on request. A module from another compiler, a file that is
    not a module, or an unsupported platform prints a diagnostic and exits.
*/
String Compiler.load_native_module(String path) {
  if (!X2C_NATIVE_MODULES)
    driver_error("native modules are not supported on this platform");
  String absolute = Path.absolute(path);
  if (Compiler.native_module_loaded(absolute)) return absolute;
  int stamp = _module_stamp(path);
  if (stamp < 0) driver_error(%"not an x2c native module: $path");
  if (!stamp)
    driver_error(
      %"native module '$path' was built by another compiler; rebuild it");
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
    driver_error(
      %"cannot read the running compiler to check native module '$path'");
  File input = fopen(path, "rb");
  if (!input)
    driver_error(
      %"cannot read native module '$path': ${String.new(strerror(errno))}");
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
   its targets. A module is never unloaded, because its Funcs borrow its
   code. */
static void _open_native_module(String path) {
  void *handle = _module_handle(path);
  if (!handle)
    driver_error(
      %"cannot load native module '$path': ${String.new(dlerror())}");
  Map (*entry)(void) = (Map (*)(void)) dlsym(handle, "x2c_module_targets");
  if (!entry) driver_error(%"not an x2c native module: $path");
  Compiler.add_native_module(path, entry);
}

/* The module's constructors allocate its Funcs and literals, which last
   as long as its code. */
static void *_module_handle(String path) {
  $scope(&native_module_scope) return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}

/** Records the name-to-`Func` Map that the entry of the native module loaded
    from absolute `path` returns. The Funcs, names, signatures, and path last
    for the process.
*/
void Compiler.add_native_module(String path, Map (*entry)(void)) {
  Map targets = _module_targets(path, entry);
  path.try_own();
  foreach (Var (name, target), targets) {
    name.string().try_own();
    ((Func) target.pointer()).signature().try_own();
  }
}

static Map _module_targets(String path, Map (*entry)(void)) {
  $scope(&native_module_scope) {
    if (!(void *) native_modules) {
      Scope.shutdown_hook(_native_module_shutdown);
      native_modules = {};
    }
    Map targets = entry();
    native_modules[path] = targets;
    return targets;
  }
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
