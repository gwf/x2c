/*  linked.x -- native meta linked

    Copyright (c) 2026 Gary William Flake.
*/

/* The linked bodies that prelude advertisements have bound. A body whose
   texts and signature agreed once in the process agrees in every later
   unit, since the prelude's providers do not change; a refusal can come
   from a context that has not installed the provider's callees yet. */
static Map shipped_targets = NULL;

/* The linked body an advertisement binds when its texts and signature
   agree, or 0. */
module Var _linked_target(
  Compiler c, String name, List signature, String provider) {
  List key = %($name $signature $provider);
  Var function = 0;
  if (shipped_targets && shipped_targets.try_get(key, function))
    return function;
  if (!c.project_meta_uses_linked(name, provider)) return 0;
  function = _linked_module()[name];
  if (!c.native_meta_accepts(function, signature)) return 0;
  if (c.builtin_defs) $scope(&native_module_scope) {
    if (!shipped_targets) shipped_targets = {};
    key.try_own();
    shipped_targets[key] = function;
  }
  return function;
}

/** Answers whether a provider's function can use its linked body.
    Copied definitions retain precise callees; runtime bodies retain their
    provider's source dependencies, including private helpers. */
int Compiler.project_meta_uses_linked(
  Compiler c, String name, String provider) {
  Map linked = _linked_module();
  if (!(name in linked)) return 0;
  Map hashes = c.meta_provider_hashes(provider);
  $let(c.filename, Compiler.absolute_home_path(provider))
  $let(c.meta_hashes, hashes) $let(c.meta_calls, {})
    return _linked_copy(c, name, linked);
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
    same, or always for a prelude component's, instead of staging it.
    Returns whether it did; another edited definition is staged as user
    code.
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
  if (!_linked_copy(c, name, linked)) return 0;
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  if (!c.native_meta_accepts(function, c.func_signature(type))) return 0;
  /* Shared preload keeps private helpers in the native code alone. */
  if (!(Compiler.library_filling() && fn.cadr().type().is_static()) &&
      (!c.macro_lisp.try_get(name, bound) || bound != function))
    c.macro_lisp.set_global(name, function);
  if (c.meta_reaches_compile_time(fn)) c.record_comptime(name);
  return 1;
}

/* The linked module's targets, loaded with the definition hashes on first
   use. */
module Map _linked_module(void) {
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

/** Reports whether the compiler links the `meta` function `name`. */
int Compiler.links_meta_function(String name) => name in _linked_module();

/** Returns a linked provider's source and dependency hashes. */
List Compiler.linked_meta_provider_source(String provider) {
  _linked_module();
  return linked_hashes[provider];
}

/* A row without a hash is the runtime library's own compiled definition
   of a `lib/meta.x` builder, which has no copy to compare; only
   `lib/meta.x` itself binds it. */
module int _linked_copy(Compiler c, String name, Map linked) {
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
  Var hash, own, names = void;
  String file = c.canonical_path(c.filename);
  String key = %"${Compiler.portable_path(file)}:$name";
  if (!c.meta_hashes.try_get(name, own)) {
    Var advertisement;
    if (c.project_meta.try_get(name, advertisement)) {
      Var (_, provider) = advertisement;
      Map hashes = c.meta_provider_hashes(provider);
      if (!(name in hashes)) return 0;
      $let(c.filename, Compiler.absolute_home_path(provider))
      $let(c.meta_hashes, hashes) $let(c.meta_calls, {})
        return _linked_texts_match(c, name, linked, reached);
    }
    return !(name in linked_hashes);
  }
  /* A prelude component's definitions belong to this compiler, as its
     kernel does: an edited one keeps its linked copy until a compiler is
     built from the edit, so no translation needs a helper for it. */
  if (Compiler.is_prelude_source(file)) return name in linked;
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
    return c.linked_meta_definitions_current(
      Compiler.absolute_home_path(names));
  if (names is <list>)
    foreach (String callee, names.list())
      if (!_linked_texts_match(c, callee, linked, reached)) return 0;
  return 1;
}
