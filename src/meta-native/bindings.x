/*  bindings.x -- native meta bindings

    Copyright (c) 2026 Gary William Flake.
*/

/* the binding table

   A unit's compile-time callables by name: stubs, staged group functions,
   and the targets bound on first use. The record, its Map, and moved stubs
   live in `scope`; what their calls allocate lives in `values`, which goes
   first. */
struct MetaBindings {
  Scope scope, values;
  Map functions;
};

/** Creates an empty table in Scopes of its own, so creating it under a
    narrower Context leaves nothing there. */
MetaBindings MetaBindings.new(void) {
  Scope scope = Scope.new_named("meta bindings");
  MetaBindings b = Scope.calloc_in(&scope, 1, sizeof(struct MetaBindings));
  b.scope = scope;
  b.values = Scope.new_named("meta values");
  auto (&b.scope) b.functions = {};
  return b;
}

/** Destroys the table's values, then the table. */
void MetaBindings.destroy(MetaBindings b) {
  if (!b) return;
  Scope.destroy(b.values);
  Scope.destroy(b.scope);
}

/** Writes the binding of `name` to `out` and returns 1, or returns 0. */
int MetaBindings.try_get(MetaBindings b, String name, Var &out) =>
  b.functions.try_get(Atom.intern(name), out);

/** Binds `name` to `function`, which the table borrows. */
void MetaBindings.set(MetaBindings b, String name, Var function) {
  auto (&b.scope) b.functions[Atom.intern(name)] = function;
}

/** Binds `name` to `function` and moves its storage into the table. */
void MetaBindings.bind(MetaBindings b, String name, Func function) {
  function.move(&b.scope);
  b.set(name, function);
}

/** Returns the unit's binding table, creating it on first use. */
MetaBindings Compiler.bindings(Compiler c) {
  if (!c.meta_bindings) c.meta_bindings = MetaBindings.new();
  return c.meta_bindings;
}

/** Writes the callable compile-time code reaches as `name` to `out`: the
    unit's binding, or else a built-in algorithm or one of the compiler's
    own operations. Returns whether there is one. */
int Compiler.meta_binding(Compiler c, String name, Var &out) =>
  c.bindings().try_get(name, out) ||
  Compiler.builtin_module().try_get(name, out) ||
  Compiler.compiler_targets().try_get(name, out);

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
  String path = Compiler.portable_path(Path.resolved_absolute(c.filename));
  Type type = declaration.type_from_ast().canonicalize();
  if (type.is_static()) return;
  String name = _native_meta_name(c, declaration, marker);
  if (%(function $name) in c.sym.file_statics()) return;
  c.sym.set(
    %("source-node" (declaration $path ${marker.pos})),
    %(native-meta $name ${c.func_signature(type)}));
}

module String _native_meta_name(
  Compiler c, List declaration, Token marker) {
  String name = NULL;
  match (declaration)
    case %(declare ? (bindings (bind (binding ? ?(String spelling)) *))):
      name = spelling;
  if (!name)
    $fail.meta_native_meta_name(c, marker);
  return name;
}

/** Records the native advertisements retained by included interfaces. Each
    binds on first use, so a unit with no compile-time code pays nothing. */
void Compiler.install_native_meta_effects(Compiler c, Map globs) {
  List unit = %(${Path.resolved_absolute(c.filename)});
  foreach (Var (key, value) in globs) {
    if (_declared_in(key, unit)) continue;
    if (value is <list>) c.install_project_meta_effect(value);
  }
  foreach (Var (key, value) in globs) {
    if (_declared_in(key, unit)) continue;
    foreach (List row in _native_meta_rows(c, value)) {
      (String name, List signature) = row;
      if (name in c.project_meta) continue;
      c.native_meta[name] = signature;
      _certify_native_meta(c, name, signature, NULL);
    }
  }
}

/** Binds an included native `meta` function the first time compile-time
    code calls `name`. Returns whether the unit now binds it. A
    declaration-producing macro can call one during collection, before
    the parse installs the advertisements, so the first lookup there
    installs the ones visible so far. */
int Compiler.bind_native_meta(Compiler c, String name) {
  if (_bind_project_meta(c, name)) return 1;
  Var signature, bound;
  if (!c.native_meta.len())
    c.install_native_meta_effects(c.sym.unit_symbols());
  if (!c.native_meta.try_get(name, signature)) return 0;
  _bind_native_meta(c, name, signature, NULL);
  return c.meta_binding(name, bound);
}

/** Installs a prototype-only `meta` function from the compiler's trusted
    native target registry. The declaration keeps its ordinary runtime form.
*/
void Compiler.install_native_meta_function(
  Compiler c, List declaration, Token marker) {
  Type type = declaration.type_from_ast().canonicalize();
  String name = _native_meta_name(c, declaration, marker);
  List signature = c.func_signature(type);
  if (_bind_project_meta(c, name)) return;
  c.native_meta[name] = signature;
  _bind_native_meta(c, name, signature, marker);
}

/* One declared native function while it binds. An iterator operation's
   `target` is `NAME_into`, and `suppliers` lists the selected modules that
   define the target. */
static typedef struct NativeBinding {
  Compiler c, String name, target, List signature, suppliers, Token marker;
} NativeBinding;

/* Binds a declared native function to the compiler's own linked target of
   the same name, or an iterator operation to its `_into` target, or else to
   a selected native module's target. A declaration with neither binds
   nothing, and a meta body that calls it reports the missing binding. */
static void _bind_native_meta(
  Compiler c, String name, List signature, Token marker) {
  _certify_native_meta(c, name, signature, marker);
  String target = _iterator_operation(signature) ? %"${name}_into" : name;
  NativeBinding n = {
    .c = c, .name = name, .target = target, .signature = signature,
    .suppliers = _native_module_suppliers(target), .marker = marker};
  Var function;
  int present = c.meta_binding(name, function);
  if (!present && !_linked(n, function)) {
    /* Staged code that calls it cannot link; the call reports why. */
    if (!n.suppliers) {
      c.meta_group_bound[%"<unbound $name>"] = 1;
      return;
    }
    function = _module_target(n);
  }
  _check(n, function);
  if (!present) c.bindings().set(name, function);
}

/* The compiler's own runtime target takes precedence over loaded modules. */
static int _linked(NativeBinding &n, Var &function) {
  if (!Compiler.native_targets().try_get(n.target, function)) return 0;
  if (n.suppliers)
    $warn.meta_native_function_hidden(n.c, n.marker, n);
  return 1;
}

static Var _module_target(NativeBinding &n) {
  String first = n.suppliers.car();
  return ((Map) native_modules[first])[n.target];
}

/* A second module that defines the function is reported, and the
   declaration must match the target it binds. */
static void _check(NativeBinding &n, Var function) {
  Compiler c = n.c;
  List suppliers = n.suppliers;
  if (suppliers.cdr() && function == _module_target(n))
    _meta_native_warn_duplicate(c, n.marker, n, suppliers);
  if (!c.native_meta_accepts(function, n.signature))
    $fail.meta_native_meta_signature(c, n.marker, n);
}

static void _meta_native_warn_duplicate(
  Compiler c, Token site, NativeBinding &n, List suppliers) {
  c.report_warning(
    <native>, "more than one native module defines this function",
    site, %("name: ${n.name}" "supplied by: ${suppliers.car()}"
            "also defined by: ${", ".join(suppliers.cdr())}"));
}

/** Answers whether the native target `function` matches the declared
    `signature`. A declared `Func` parameter matches a target's `Var`
    parameter, which takes the compile-time callable and adapts it. Aliases
    of one native type match each other. */
int Compiler.native_meta_accepts(Compiler c, Var function, List signature) {
  if (function is not <func>) return 0;
  List target =
    _native_signature_type(c, ((Func) function.pointer()).signature());
  match (signature)
    case %((func ?(List parameters)) *result): {
      List boxed = parameters.search_replace(%("Func"), %("Var"));
      return target == _native_signature_type(c, signature) ||
             target == _native_signature_type(c, %((func $boxed) @result));
    }
  return 0;
}

/* The native type a signature names: each parameter, reference target,
   and result with its aliases resolved. */
static List _native_signature_type(Compiler c, List signature) {
  match (signature)
    case %((func ?(List parameters)) *result): {
      Array resolved = [];
      foreach (Type parameter in parameters)
        resolved.push(_native_parameter(c, parameter));
      Type native = c.sym.normalize_declared_type(result);
      return %((func ${resolved.list_free()}) @native);
    }
  return signature;
}

static List _native_parameter(Compiler c, Type parameter) {
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
  if (!c.meta_binding(name, bound) || bound != target) return NULL;
  type = ((Func) target.pointer()).signature();
  return path;
}

/* native lifetimes

   A `meta` body's region walk needs to know what a native function's
   result owns. A function without a runtime row takes the summary its
   signature implies, or is rejected where it is declared. */

/* A declaration whose signature implies no summary is rejected at its
   `marker`; an advertisement read from an interface records nothing. */
static void _certify_native_meta(
  Compiler c, String name, List signature, Token marker) {
  if (Compiler.has_region_row(name)) return;
  List summary = _native_meta_summary(c, signature);
  if (summary) {
    c.meta_regions[name] = summary;
    return;
  }
  if (marker)
    $fail.meta_native_meta_lifetime(c, marker, name, signature);
}

/* The region summary of a native function without a runtime row, from its
   signature: a returned handle is a fresh allocation in the active Scope,
   and a handle argument is borrowed for the call. A function that takes a
   handle and returns one, neither owned by its cleanup, might return or
   keep its argument, so it has none. */
static List _native_meta_summary(Compiler c, List signature) {
  match (signature) case %((func ?(List parameters)) *result): {
    int takes = 0, gives = _native_handle(c, result, 0);
    foreach (List parameter in parameters)
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
      return pointee == %(void) || _native_handle(c, pointee, 0);
    case %((!or "Var" "Symbol" "String" "List" "Array" "Map" "Func")):
      return 0;
  }
  Symbol tag = c.sym.var_tag_for_type(type, NULL);
  if (tag == <var> || tag == <symbol> || tag == <string> ||
      tag == <list> || tag == <array> || tag == <map> || tag == <func>)
    return 0;
  type = c.sym.normalize_declared_type(type);
  foreach (Var part in type) if (part is not Symbol || part == <*>) return 1;
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

   The native functions interface rows advertise. The entry
   `lib/lisp-targets/lisp-targets.x` generates its target inventory from them. */

/** Returns the declared native targets advertised by `meta` interface
    rows, in the row form `lib/lisp-targets/lisp-targets.x` uses for its
    inventory, or only those declared in the files `paths` names when it is
    not empty. A target that takes a `Func` is left out unless `callbacks`
    is nonzero. Sorting makes that inventory independent of Map order.
*/
List Compiler.native_meta_targets(List paths, int callbacks) {
  Compiler c = Compiler.expanding();
  if (!c) return %();
  Map selected = {};
  foreach (Var (key, value) in c.sym.base_symbols()) {
    if (paths && !_declared_in(key, paths)) continue;
    foreach (List row in _native_meta_rows(c, value)) {
      (String name, List signature) = row;
      if (!callbacks && _takes_callback(signature)) continue;
      String into = %"${name}_into";
      selected[name] = _iterator_operation(signature)
        ? %($name (as $into)) : %($name);
    }
  }
  Array names = selected.keys();
  List rows = %();
  foreach (String name in names.sort()) rows = cons(selected[name], rows);
  return rows.reverse();
}

/* Whether the symbol row under `key` was declared in one of the absolute
   source `paths`. */
static int _declared_in(Var key, List paths) {
  match (key)
    case %("source-node" (declaration ?(String path) ?)):
      return Compiler.absolute_home_path(path) in paths;
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
  foreach (List member in conformance.last().list().cdr())
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
   takes a `Func` binds through an adapter row in `lib/lisp/lisp.x`. */
static int _takes_callback(List signature) {
  match (signature)
    case %((func ?(List parameters)) *): return %("Func") in parameters;
  return 0;
}

/* An iterator operation takes its destination last. Its native target is
   `NAME_into`, and a compile-time call of `NAME` that omits the
   destination gets one at the call. */
module int _iterator_operation(List signature) {
  match (signature)
    case %((func ?(List parameters)) "Iter"):
      return parameters && parameters.last() == %("Iter");
  return 0;
}

/* The number of parameters a signature declares. */
module int _parameter_count(List signature) =>
  signature.car().list().cadr().list().len();
