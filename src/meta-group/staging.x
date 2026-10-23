/*  staging.x -- meta group staging

    Copyright (c) 2026 Gary William Flake.
*/

// the project meta build

/* Where the project meta build writes each unit's group, while it runs. */
static String meta_build_directory = NULL;

/** Directs each provider group into `directory`, using `owners` to name
    their headers by table, or stops that when `directory` is NULL. */
void Compiler.use_meta_build_directory(
  String directory, Array owners, Map providers) {
  meta_build_directory = directory;
  meta_build_tables = {};
  meta_build_providers = providers;
  int index = 1;
  foreach (String owner in owners) meta_build_tables[owner] = index++;
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
  foreach ((String path, Var _) in c.deps) sources.push(path);
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
  foreach (List entry in c.meta_group)
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
