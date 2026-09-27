/*  meta-project.x -- the project meta build

    Copyright (c) 2026 Gary William Flake.

    Before a translation starts, the bodied `meta` functions its inputs
    reach are compiled into one helper program linked against the runtime,
    which the translation then calls (`src/stage.x`). They come from each
    project `.xmacro` file an input imports, directly, through an included
    header, or through a package, and from an input that defines its own
    until those move to `.xmacro` files. Meta code under the x2c root's
    `lib`, `src`, and `etc` is the compiler's own, linked into it.

    Each input that reaches any gets a table of its own, parsed from the
    input itself so its imports see the declarations they are used with.
    Each table's object keeps only its entry global, so copies of one
    import in several tables link together. The helper is cached
    under the x2c cache root, keyed by the SHA-256 of those sources, the
    compiler stamp, the C compiler's identity, and the flags, and is built
    again when a file its build read, x2c source or C header, changes.
*/

#pragma once
#include "frontend.x"

#pragma private

#include "datum.x"
#include "digest.x"
#include "deps.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <unistd.h>

/* The C compiler flags of meta code, besides its include directories. */
static List _meta_flags(void) => %("-fsigned-char" "-O1");

/* Whether `path` is meta code the compiler owns and links. */
static int _meta_owned(String path) {
  String root = x2c_get_root();
  foreach (String directory, %("lib" "src" "etc"))
    if (path.startswith(%"$root/$directory/")) return 1;
  return 0;
}

/* The file the quoted `spelling` names from `directory`, or else from the
   runtime's `lib`, as an import resolves it, or NULL. */
static String _meta_resolve(String directory, String spelling) {
  String local = spelling.startswith("/") ? spelling
                                          : %"$directory/$spelling";
  if (Path.is_file(local)) return Path.absolute(local);
  String system = %"${x2c_get_root()}/lib/$spelling";
  return Path.is_file(system) ? system : NULL;
}

/* The text between a string token's quotes. */
static String _meta_quoted(Token token) =>
  token.len >= 2 && token.text[0] == '"'
    ? String.new_len(token.text + 1, token.len - 2).unescape() : NULL;

/* Reads the tokens of the file at `path` for what reaches project meta
   code, once per file in `seen`, and returns whether the file holds a
   file-scope `meta` marker other than `meta native`. Each project
   `.xmacro` it imports that holds one joins `imports`, after those it
   imports; a quoted include of a project `.x` file and an imported
   package's entry are read for imports the same way. */
static int _meta_scan(
  CliRequest request, String path, Array imports, Map seen, Map packages) {
  if (path in seen) return 0;
  seen[path] = 1;
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return 0;
  String directory = Path.dirname(path);
  Tokenizer tokens = Tokenizer.new(text, <x2c>);
  tokens.scan();
  int depth = 0, meta = 0;
  for (Token token = tokens.next(); token.type != <eof>;
       token = tokens.next()) {
    String word = token.text;
    if (word == "{") depth++;
    else if (word == "}") depth--;
    else if (depth) continue;
    else if (word == "meta") {
      /* `meta native T name(` binds a native function; in `meta native
         name(`, `native` is a type. */
      if (tokens.next().text != "native") meta = 1;
      else {
        tokens.next();
        if (tokens.next().text == "(") meta = 1;
      }
    }
    else if (word == "$(" && tokens.next().text == "import") {
      String spelling = _meta_quoted(tokens.next());
      String file = spelling ? _meta_resolve(directory, spelling) : NULL;
      if (file && file.endswith(".xmacro") && !_meta_owned(file) &&
          _meta_scan(request, file, imports, seen, packages))
        imports.push(file);
    }
    else if (word == "import") {
      String name = _meta_quoted(tokens.next()), root = NULL;
      String entry = name ? x2c_package_entry(
        request.sources, request.package_roots(), name, root) : NULL;
      if (entry) packages[root] = 1;
      if (entry) _meta_scan(request, entry, imports, seen, packages);
    }
    else if (token.type == <preproc>) {
      int angle = 0;
      String target = preproc_include_target(word, angle);
      String file = target && target.endswith(".x")
        ? collect_resolve_include(
            request.sources, request.include_dirs, directory, target, angle)
        : NULL;
      if (file && !_meta_owned(Path.absolute(file)))
        _meta_scan(request, Path.absolute(file), imports, seen, packages);
    }
  }
  return meta;
}

/* Parses the unit at `path` for the group of table `index`, which the
   parse writes into the build directory. Diagnostics are the translation's
   to report; a unit that does not parse leaves the part it reached. */
static void _meta_unit(Frontend f, String path, int index) {
  ParsedUnit unit;
  int started = f.start(path, unit);
  defer unit.close();
  unit.compiler.meta_build = index + 1;
  unit.compiler.diagnostics.limit = 0;
  if (!started) return;
  /* A call of a project function the collection meets fails before the
     helper exists; the parse still reaches every definition. */
  unit.collect(f);
  unit.compiler.diagnostics.reset();
  unit.parse();
}

/* Runs `arguments`, a C compiler command, and returns NULL, or its first
   error. */
static String _meta_cc(List arguments) =>
  Compiler.meta_cc_run(arguments, NULL);

/* The object of `etc/meta-helper.x`, the helper's protocol loop, which
   this compiler translates once per `identity`, or NULL with `failure`
   set. */
static String _meta_support(
  Toolchain t, String include, String identity, String &failure) {
  String source = %"${x2c_get_root()}/etc/meta-helper.x";
  if (!Path.is_file(source)) {
    failure = %"cannot read $source";
    return NULL;
  }
  String key = String.sha256(
    %"$identity\n${Path.read_text(source).sha256()}");
  String directory = %"${script_cache_root()}/meta/support-$key";
  String object = %"$directory/meta-helper.o";
  if (Path.is_file(object)) return object;
  Path.make_dirs(directory);
  int lock = file_lock(%"$directory/lock", 1);
  defer close(lock);
  if (Path.is_file(object)) return object;
  String printed = NULL, errors = NULL;
  if (tool_capture(%(${x2c_get_executable()} "translate" "--out-dir"
                     $directory $source), printed, errors)) {
    failure = %"cannot translate $source: ${errors.strip(NULL)}";
    return NULL;
  }
  String output = %"$object.${"%ld".printf((long) getpid())}";
  failure = _meta_cc(%(${t.cc} @{_meta_flags()} "-iquote" $directory
                       "-iquote" $include "-c" ${%"$directory/meta-helper.c"}
                       "-o" $output));
  if (failure) return NULL;
  Path.move_to(output, object);
  return object;
}

/* The unit that gives the helper each built table by index. */
static String _meta_tables(List built, int count) {
  Buffer out = Buffer.new(0);
  out.write("#include \"x2c.h\"\n");
  foreach (Var index, built)
    out.printf("Map x2c_module_targets_%d(void);\n", (int) index.integer());
  out.write("Map x2c_meta_helper_table(int index) {\n  switch (index) {\n");
  foreach (Var index, built)
    out.printf("    case %d: return x2c_module_targets_%d();\n",
               (int) index.integer(), (int) index.integer());
  out.write("  }\n  return NULL;\n}\n");
  out.printf("int x2c_meta_helper_count(void) { return %d; }\n", count);
  return out;
}

/* Leaves `x2c_module_targets_K` the only global symbol of the object
   `base.o` of table K, so the groups of several units, each holding its own
   copy of what it imports, link into one program. */
static String _meta_localize(Toolchain t, String base, int index) {
  String entry = %"x2c_module_targets_$index", object = %"$base.o";
  String merged = %"$base.r.o";
#ifdef __APPLE__
  String failure = _meta_cc(%(${t.cc} "-r" "-nostdlib"
    ${%"-Wl,-exported_symbol,_$entry"} $object "-o" $merged));
#else
  String failure = _meta_cc(%(${t.cc} "-r" "-nostdlib" $object "-o" $merged));
  if (!failure)
    failure = _meta_cc(%("objcopy" ${%"--keep-global-symbol=$entry"}
                         $merged));
#endif
  if (!failure) Path.move_to(merged, object);
  return failure;
}

/* The SHA-256 of the bytes of the file at `path`, or NULL when it cannot
   be read. */
static String _meta_digest(String path) {
  File input = fopen(path, "rb");
  if (!input) return NULL;
  defer input.close();
  return input.sha256();
}

/* Adds each dependency of the depfile at `path` to `deps`. */
static void _meta_depfile(String path, Map deps) {
  if (!Path.is_file(path)) return;
  foreach (String dependency,
           translation_depfile_parse(Path.read_text(path)))
    deps[Path.absolute(dependency)] = 1;
}

/* Removes what a parse of table `index` in `directory` left. */
static void _meta_clear(String directory, int index) {
  foreach (String suffix, %(".c" ".deps" ".failure")) {
    String file = %"$directory/group-$index$suffix";
    if (Path.exists(file)) Path.remove_file(file);
  }
}

/* Compiles the group a parse left for table `index`, adding the files it
   read to `deps`. A quoted include resolves from the directory of `unit`.
   Returns NULL when its object is built, or else why not. */
static String _meta_compile(
  String directory, int index, String unit, List flags, Toolchain t,
  String include, Map deps) {
  String base = %"$directory/group-$index";
  if (!Path.is_file(%"$base.deps")) return "the unit has no group";
  foreach (String path, Path.read_text(%"$base.deps").split("\n"))
    if (path) deps[path] = 1;
  if (Path.is_file(%"$base.failure")) return Path.read_text(%"$base.failure");
  String failure = Compiler.meta_cc_run(
    %(${t.cc} @{_meta_flags()} "-iquote" $directory
      "-iquote" ${Path.dirname(unit)} "-iquote" $include @flags
      "-MD" "-MF" ${%"$base.d"} "-c" ${%"$base.c"} "-o" ${%"$base.o"}),
    directory);
  if (!failure) failure = _meta_localize(t, base, index);
  _meta_depfile(%"$base.d", deps);
  return failure;
}

/* Parses each source into its group, compiles the groups, and links the
   helper in `directory` with the runtime when an object or the table
   changed, so a change to program code alone keeps the helper. Returns
   the manifest: `(groups (K ...))` for each table that has a group,
   `(failures ((K WHY) ...))` for those that do not build, `(failure WHY)`,
   empty unless the helper does not link, and `(deps ((PATH DIGEST) ...))`
   for every file the build read. */
static List _meta_build(
  Frontend f, String directory, List imports, List owners, Map reaches,
  List modules, List flags, Toolchain t, String include, String identity) {
  int count = owners.len() + 1;
  Map before = {};
  for (int index = 0; index < count; index++) {
    before[index] = _meta_digest(%"$directory/group-$index.o");
    _meta_clear(directory, index);
  }
  Map deps = {};
  String loop = %"${x2c_get_root()}/etc/meta-helper.x";
  foreach (String path, %(@imports @owners @modules $loop)) deps[path] = 1;
  Array groups = [], built = [], failures = [], objects = [];
  int changed = 0;
  Compiler.use_meta_build_directory(directory);
  int index = 1;
  foreach (String owner, owners) {
    _meta_unit(f, owner, index);
    String failure =
      _meta_compile(directory, index, owner, flags, t, include, deps);
    /* An input that only imports its meta code, and whose own group does
       not build, gets the group of its imports alone. */
    List reached = reaches[owner];
    String base = %"$directory/group-$index";
    if (reached && failure) {
      _meta_clear(directory, index);
      Array lines = [];
      foreach (String path, reached)
        lines.push(String.new("$(import ").add(path.repr()).add(")"));
      String source = %"$base-imports.x";
      Path.write_text(source, "\n".join(lines.list_free()).add("\n"));
      _meta_unit(f, source, index);
      failure =
        _meta_compile(directory, index, owner, flags, t, include, deps);
    }
    if (Path.is_file(%"$base.deps")) {
      groups.push(index);
      if (failure) failures.push(%($index $failure));
      else {
        built.push(index);
        objects.push(%"$base.o");
        if (_meta_digest(%"$base.o") != before[index]) changed = 1;
      }
    }
    index++;
  }
  Compiler.use_meta_build_directory(NULL);
  String failure = NULL;
  String support = _meta_support(t, include, identity, failure);
  String tables = %"$directory/tables.c", table = _meta_tables(built, count);
  String helper = %"$directory/helper";
  if (support && (changed || !Path.is_file(tables) ||
                  Path.read_text(tables) != table ||
                  !Path.is_file(helper))) {
    Path.write_text(tables, table);
    String output = %"$directory/helper.${"%ld".printf((long) getpid())}";
    /* Native modules use their host's runtime, including units the helper
       itself never calls. Match the compiler's whole-runtime link. */
    List exports = NULL;
#ifdef __APPLE__
    exports = %(${%"-Wl,-force_load,${t.runtime_lib}"});
#else
    exports = %("-Wl,--export-dynamic,--whole-archive" ${t.runtime_lib}
                "-Wl,--no-whole-archive");
#endif
    t.ld_args = exports;
    List inputs = %(@{objects.list()} $tables $support);
    String archive = Compiler.extension_archive();
    if (archive) inputs = inputs.append(%($archive));
    ToolAction link = t.link_action(output, inputs);
    /* The link compiles the table, which includes the runtime headers. */
    failure = _meta_cc(
      %(@{link.arguments} @{_meta_flags()} "-iquote" $include));
    if (!failure) Path.move_to(output, helper);
    else if (Path.exists(helper)) Path.remove_file(helper);
  }
  Array rows = [];
  foreach (Var (path, _), deps) {
    String digest = _meta_digest(path);
    if (digest) rows.push(%($path $digest));
  }
  List manifest = %((groups ${groups.list()}) (failures ${failures.list()})
                    (failure ${failure ? failure : ""})
                    (deps ${rows.sort().list()}));
  Buffer out = $auto(Buffer.new(0));
  datum_write(out, manifest, 0);
  Path.write_text(%"$directory/manifest", out);
  return manifest;
}

/* The manifest a previous build left in `directory` when every file it
   read is unchanged, or NULL. */
static List _meta_current(String directory) {
  String path = %"$directory/manifest";
  if (!Path.is_file(path)) return NULL;
  String text = Path.read_text(path);
  unsigned cursor = 0;
  Var manifest = void;
  try datum_read(text, cursor, manifest);
  catch %((!or incomplete malformed) *): return NULL;
  if (manifest is not <list>) return NULL;
  /* A failure may come from a file the build could not read, such as a
     missing header, which no digest covers; build again. */
  if (((List) manifest).assoc(<failures>) ||
      ((String) ((List) manifest).assoc(<failure>)).len())
    return NULL;
  foreach (List row, ((List) manifest).assoc(<deps>)) {
    (String path, String digest) = row;
    if (_meta_digest(path) != digest) return NULL;
  }
  return manifest;
}

/* `cc_args` without the flags that select a target architecture, ABI, or
   system root, since the helper runs on the host. */
static List _meta_host_args(List cc_args) {
  Array kept = [];
  for (List rest = cc_args; rest; rest = rest.cdr()) {
    String arg = rest.car();
    if (arg == "-target" || arg == "--target" || arg == "-arch" ||
        arg == "--sysroot" || arg == "-isysroot") {
      if (rest.cdr()) rest = rest.cdr();
    }
    else if (!arg.startswith("--target=") && !arg.startswith("--sysroot=") &&
             !arg.startswith("-m"))
      kept.push(arg);
  }
  return kept.list();
}

/** Builds the helper that runs the project `meta` functions `inputs`
    reach, or finds it in the cache, and makes it the one their translation
    calls. Inputs that reach none use no helper. A group or helper that
    does not build is reported at the first call that needs it. */
void Frontend.prepare_meta(Frontend f, List inputs) {
  Array imports = [], owners = [];
  Map known = {}, reaches = {}, packages = {};
  foreach (String input, inputs) {
    String path = Path.absolute(input);
    Array reached = [];
    int own = _meta_scan(f.request, path, reached, {}, packages);
    if (own || reached.len()) owners.push(path);
    if (!own && reached.len()) reaches[path] = reached.list();
    foreach (String file, reached)
      if (!(file in known)) {
        known[file] = 1;
        imports.push(file);
      }
  }
  String include = NULL, cc = Compiler.meta_cc(include);
  String root = script_cache_root(), stamp = build_module_stamp();
  if ((!imports.len() && !owners.len()) || !cc || !root || !stamp) {
    Compiler.use_meta_helper(NULL, NULL, NULL);
    return;
  }
  Toolchain t = toolchain_new(cc, NULL, NULL, NULL, NULL, 0, 0);
  String compiler = Compiler.meta_cc_identity(cc);
  /* A unit's group includes what the unit includes: the request's C
     directories and each imported package's headers. */
  List flags = %(@{f.request.include_dirs.map(%!(dir) => %("-I" $dir))
                   .flatten()} @{_meta_host_args(f.request.cc_args)});
  foreach (Var (root, _), packages)
    flags = %(@flags "-iquote" ${%"$root/builds"} "-iquote" ${%"$root/src"});
  /* A package linked into the compiler uses the headers of its build. */
  String archive = Compiler.extension_archive();
  if (archive)
    flags = %("-iquote" ${%"${Path.dirname(archive)}/include"} @flags);
  Array modules = f.request.native_modules.map(
    %!(String path) => Path.absolute(path));
  foreach (Var (root, _), packages) {
    String name = Path.basename(root);
    String module = %"$root/builds/$name.module";
    if (!Compiler.links_extension(name) && Path.is_file(module) &&
        !(module in modules)) modules.push(module);
  }
  /* The helper's own source is read at build time, not linked into the
     compiler, so the stamp does not cover it. */
  String helper = %"${x2c_get_root()}/etc/meta-helper.x";
  String identity = %"$stamp\n$compiler\n${_meta_flags().repr()}\n"
                    + %"${flags.repr()}\n$include\n${t.runtime_lib}\n"
                    + %"${modules.list().repr()}\n"
                    + (Path.is_file(helper)
                       ? Path.read_text(helper).sha256() : "");
  /* A changed source builds the same directory again, which keeps the
     helper when no group object changes. */
  Array key = [identity];
  foreach (String path, %(@imports "--" @owners)) key.push(path);
  String directory =
    %"$root/meta/project-${String.sha256("\n".join(key))}";
  Path.make_dirs(directory);
  List manifest = NULL;
  {
    int lock = file_lock(%"$directory/lock", 1);
    defer close(lock);
    manifest = _meta_current(directory);
    if (!manifest)
      manifest = _meta_build(
        f, directory, imports, owners, reaches, modules, flags, t,
        include, identity);
  }
  Map failures = {}, units = {}, groups = {};
  foreach (Var index, manifest.assoc(<groups>)) groups[index] = 1;
  foreach (List row, manifest.assoc(<failures>))
    failures[row.car()] = row.cadr();
  int index = 1;
  foreach (String owner, owners) {
    if (index in groups) units[owner] = index;
    index++;
  }
  String failure = manifest.assoc(<failure>);
  if (failure.len()) failures[-1] = failure;
  Compiler.use_meta_helper(
    failure.len() ? NULL : %"$directory/helper", failures, units);
}
