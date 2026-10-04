/*  meta-project.x -- the project meta build

    Copyright (c) 2026 Gary William Flake.

    Before a translation starts, the bodied `meta` functions its inputs
    reach are compiled into one helper program linked against the runtime,
    which the translation then calls (`src/meta-helper-client.x`). They
    come from each project `.xmacro` file an input imports, directly,
    through an included header, or through a package, and from an input
    or included file that defines its own until those move to `.xmacro`
    files. Meta code under the x2c root's `lib`, `src`, and `etc` is the
    compiler's own, linked into it.

    Each input that reaches any, and each included file that defines its
    own, gets a table of its own, parsed from the file itself so its
    imports see the declarations they are used with. Each table's object
    keeps only its entry global, so copies of one import in several
    tables link together. The helper is cached under the x2c cache root,
    keyed by the SHA-256 of those sources, the compiler stamp, the C
    compiler's identity, and the flags, and is built again when a file its
    build read, x2c source or C header, changes.
*/

#pragma once
#include "frontend.x"

#pragma private

#include "datum.x"
#include "digest.x"
#include "deps.x"
#include "meta-helper-client.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <unistd.h>

// helper table source

macro Stmt $output.helper.header(Expr $out) {
  $out.write("#include \"x2c.h\"\n");
}

macro Stmt $output.helper.target(Expr $out, Expr $index) {
  $out.printf("Map x2c_module_targets_%d(void);\n", $index);
}

macro Stmt $output.helper.dispatch_begin(Expr $out) {
  $out.write("Map x2c_meta_helper_table(int index) {\n  switch (index) {\n");
}

macro Stmt $output.helper.dispatch_case(Expr $out, Expr $index) {
  $out.printf(
    "    case %d: return x2c_module_targets_%d();\n", $index, $index);
}

macro Stmt $output.helper.dispatch_end(Expr $out) {
  $out.write("  }\n  return NULL;\n}\n");
}

macro Stmt $output.helper.count(Expr $out, Expr $count) {
  $out.printf("int x2c_meta_helper_count(void) { return %d; }\n", $count);
}

// preparing the helper

/* One project meta build. The Kth owner, an input that reaches meta code,
   parses into table K, and `reaches` holds the imports of an owner without
   meta code of its own. A build records the files it reads in `deps` and
   the result of each table in the fields after it. */
typedef struct Helper {
  Frontend frontend, Array imports, owners, Map reaches, packages;
  Toolchain toolchain, String include, identity, directory;
  List flags, Array modules;
  Map deps, before, Array groups, built, failures, objects, int changed;
} Helper;

/** Builds the helper that runs the project `meta` functions `inputs`
    reach, or finds it in the cache, and makes it the one their translation
    calls. Inputs that reach none use no helper. A group or helper that
    does not build is reported at the first call that needs it. */
void Frontend.prepare_meta(Frontend f, List inputs) {
  Helper h = {
    .frontend = f, .imports = [], .owners = [], .reaches = {},
    .packages = {}, .deps = {}, .before = {}, .groups = [], .built = [],
    .failures = [], .objects = []};
  h.scan(inputs);
  String include = NULL, cc = Compiler.meta_cc(include);
  String root = script_cache_root(), stamp = build_module_stamp();
  if (!h.owners.len() || !cc || !root || !stamp) {
    Compiler.use_meta_helper(NULL, NULL, NULL);
    return;
  }
  h.toolchain = toolchain_meta(cc);
  String compiler = Compiler.meta_cc_identity(cc);
  h.include = include;
  h.flags = _group_flags(f.request, h.packages);
  h.modules = _modules(f.request, h.packages);
  h.identity = h.identify(stamp, compiler);
  h.directory = _directory(root, h.identity, h.imports, h.owners);
  h.use(h.manifest());
}

/* The manifest of the helper in the build directory: the one a previous
   build left while every file it read is unchanged, or a new build's. One
   process at a time does either, under the directory's lock. */
static List Helper.manifest(Helper &h) {
  Path.make_dirs(h.directory);
  int lock = file_lock(%"${h.directory}/lock", 1);
  defer close(lock);
  List manifest = _current(h.directory);
  if (manifest) return manifest;
  return h.build();
}

/* Each owner with a group calls its table, and a table or a helper that
   does not build keeps its reason for the first call that needs it. */
static void Helper.use(Helper &h, List manifest) {
  Map failures = {}, units = {}, groups = {};
  foreach (Var index, manifest.assoc(<groups>)) groups[index] = 1;
  foreach (List row, manifest.assoc(<failures>))
    failures[row.car()] = row.cadr();
  int index = 1;
  foreach (String owner, h.owners) {
    if (index in groups) units[owner] = index;
    index++;
  }
  String failure = manifest.assoc(<failure>);
  if (failure.len()) failures[-1] = failure;
  Compiler.use_meta_helper(
    failure.len() ? NULL : %"${h.directory}/helper", failures, units);
}

// reaching meta code

/* The scan of one input. `imports` collects each project `.xmacro` file
   that holds meta code, after the files it imports, and `units` each
   included file that holds its own; `seen` holds each file read, and
   `packages` the root of each package imported. */
typedef struct Scan {
  CliRequest request, Array imports, units, Map seen, packages;
} Scan;

/* Each input that reaches meta code becomes an owner. One without meta
   code of its own keeps the files it imports, for a group of those alone.
   An included file with meta code of its own becomes an owner too, so the
   constants it computes run in its own table when a unit collects it.
   Its path is canonical, as collection spells it. */
static void Helper.scan(Helper &h, List inputs) {
  Map known = {}, owned = {};
  foreach (String input, inputs) {
    String path = Path.absolute(input);
    Scan s = {
      .request = h.frontend.request, .imports = [], .units = [], .seen = {},
      .packages = h.packages};
    int own = s.file(path);
    Array reached = s.imports;
    if (own || reached.len()) h.own(path, owned);
    if (!own && reached.len()) h.reaches[path] = reached.list();
    foreach (String unit, s.units) h.own(unit, owned);
    foreach (String file, reached)
      if (!(file in known)) {
        known[file] = 1;
        h.imports.push(file);
      }
  }
}

static void Helper.own(Helper &h, String path, Map owned) {
  if (path in owned) return;
  owned[path] = 1;
  h.owners.push(path);
}

/* Reads the file at `path` once per scan, and returns whether it holds a
   file-scope `meta` marker other than `meta native`. */
static int Scan.file(Scan &s, String path) {
  if (path in s.seen) return 0;
  s.seen[path] = 1;
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return 0;
  Tokenizer tokens = Tokenizer.new(text, <x2c>);
  tokens.layout = is_layout_file(path);
  tokens.scan();
  return s.file_scope(tokens, Path.dirname(path));
}

/* Only file-scope tokens count. Each arm reads the tokens that follow its
   word. */
static int Scan.file_scope(Scan &s, Tokenizer tokens, String directory) {
  int depth = 0, meta = 0;
  for (Token token = tokens.next(); token.type != <eof>;
       token = tokens.next()) {
    String word = token.text;
    switch (token.type) {
      case <"{">: case <"%{">: case <"${">: case <"@{">:
        depth++;
        continue;
      case <"}">: depth--; continue;
    }
    if (depth) continue;
    if (word == "meta") meta |= _marker(tokens);
    else if (word == "$(") s.macro_import(tokens, directory);
    else if (word == "import") s.package(tokens);
    else if (token.type == <preproc>) s.include(word, directory);
  }
  return meta;
}

/* Whether the words after `meta` mark project meta code: `meta native T
   name(` binds a native function, while in `meta native name(`, `native`
   is a type. */
static int _marker(Tokenizer tokens) {
  if (tokens.next().text != "native") return 1;
  tokens.next();
  return tokens.next().text == "(";
}

/* A project `.xmacro` or `.xpmacro` file that `$(import` names joins
   `imports` after the files it imports, when it holds meta code. */
static void Scan.macro_import(Scan &s, Tokenizer tokens, String directory) {
  if (tokens.next().text != "import") return;
  String spelling = _quoted(tokens.next());
  String file = spelling ? _resolve(directory, spelling) : NULL;
  if (file && (file.endswith(".xmacro") || file.endswith(".xpmacro")) &&
      !_compiler_owns(file) && s.file(file))
    s.imports.push(file);
}

/* An imported package's entry is read for imports like an input. */
static void Scan.package(Scan &s, Tokenizer tokens) {
  String name = _quoted(tokens.next()), root = NULL;
  String entry = name ? package_entry(
    s.request.sources, s.request.package_roots(), name, root) : NULL;
  if (!entry) return;
  s.packages[root] = 1;
  s.file(entry);
}

/* An included project `.x` or `.xp` file is read for imports too, and
   joins `units` when it holds meta code of its own. */
static void Scan.include(Scan &s, String directive, String directory) {
  int angle = 0;
  String target = preproc_include_target(directive, angle);
  if (!target || !(target.endswith(".x") || target.endswith(".xp"))) return;
  String file = collect_resolve_include(
    s.request.sources, s.request.include_dirs, directory, target, angle);
  if (!file) return;
  String path = Path.absolute(file);
  if (!_compiler_owns(path) && s.file(path))
    s.units.push(absolute_path(path));
}

/* The text between a string token's quotes. */
static String _quoted(Token token) =>
  token.len >= 2 && token.text[0] == '"'
    ? String.new_len(token.text + 1, token.len - 2).unescape() : NULL;

/* The file the quoted `spelling` names from `directory`, or else from the
   runtime's `lib`, as an import resolves it, or NULL. */
static String _resolve(String directory, String spelling) {
  String local = spelling.startswith("/") ? spelling : %"$directory/$spelling";
  if (Path.is_file(local)) return Path.absolute(local);
  String system = %"${x2c_get_root()}/lib/$spelling";
  return Path.is_file(system) ? system : NULL;
}

static int _compiler_owns(String path) {
  String root = x2c_get_root();
  foreach (String directory, %("lib" "src" "etc"))
    if (path.startswith(%"$root/$directory/")) return 1;
  return 0;
}

// the cache key

/* A unit's group includes what the unit includes: the request's C
   directories and each imported package's headers. A package linked into
   the compiler uses the headers of its build. */
static List _group_flags(CliRequest request, Map packages) {
  List includes = request.include_dirs.map(%!(dir) => %("-I" $dir)).flatten();
  List flags = %(@includes @{_host_args(request.cc_args)});
  foreach (Var (root, _), packages)
    flags = %(@flags "-iquote" ${%"$root/builds"} "-iquote" ${%"$root/src"});
  String archive = Compiler.extension_archive();
  if (archive)
    flags = %("-iquote" ${%"${Path.dirname(archive)}/include"} @flags);
  return flags;
}

/* `cc_args` without the flags that select a target architecture, ABI, or
   system root, since the helper runs on the host. */
static List _host_args(List cc_args) {
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
  return kept;
}

/* The request's native modules and the module of each imported package
   that the compiler does not link. */
static Array _modules(CliRequest request, Map packages) {
  Array modules = request.native_modules.map(
    %!(String path) => Path.absolute(path));
  foreach (Var (root, _), packages) {
    String name = Path.basename(root);
    String module = %"$root/builds/$name.module";
    if (!Compiler.links_extension(name) && Path.is_file(module) &&
        !(module in modules)) modules.push(module);
  }
  return modules;
}

/* Everything the helper is built with besides its sources. The helper's
   own source is read at build time, not linked into the compiler, so the
   stamp does not cover it. */
static String Helper.identify(Helper &h, String stamp, String compiler) {
  String loop = _loop_source();
  return %"$stamp\n$compiler\n${_cc_flags().repr()}\n"
    + %"${h.flags.repr()}\n${h.include}\n${h.toolchain.runtime_lib}\n"
    + %"${h.modules.list().repr()}\n"
    + (Path.is_file(loop) ? Path.read_text(loop).sha256() : "");
}

/* The C compiler flags of meta code, besides its include directories. */
static List _cc_flags(void) => %("-fsigned-char" "-O1");

/* Every helper links this unit, which answers the compiler's calls. */
static String _loop_source(void) => %"${x2c_get_root()}/etc/meta-helper.x";

/* The build directory is keyed by the identity and the paths of the
   sources. A changed source builds the same directory again, which keeps
   the helper when no group object changes. */
static String _directory(
  String root, String identity, Array imports, Array owners) {
  Array key = [identity];
  foreach (String path, %(@imports "--" @owners)) key.push(path);
  return %"$root/meta/project-${String.sha256("\n".join(key))}";
}

// building the helper

/* Parses each owner into the group of its table, compiles the groups, and
   links the helper, keeping what an earlier build left when it is
   unchanged. The parses collect included files with placeholders for
   their meta calls, so translation collects those files again. Returns
   the manifest the build writes. */
static List Helper.build(Helper &h) {
  int count = h.owners.len() + 1;
  for (int index = 0; index < count; index++) {
    String base = h.base(index);
    h.before[index] = _digest(%"$base.o");
    _clear(base);
  }
  String loop = _loop_source();
  foreach (String path, %(@{h.imports} @{h.owners} @{h.modules} $loop))
    h.deps[path] = 1;
  Compiler.use_meta_build_directory(h.directory);
  int index = 1;
  foreach (String owner, h.owners) h.group(owner, index++);
  Compiler.use_meta_build_directory(NULL);
  collect_forget_provisional_entries();
  return h.write_manifest(h.link(count));
}

/* The path of table `index`'s group files, without their suffixes. */
static String Helper.base(Helper &h, int index) =>
  %"${h.directory}/group-$index";

/* Removes what a parse left of the group at `base`. */
static void _clear(String base) {
  foreach (String suffix, %(".c" ".deps" ".failure")) {
    String file = %"$base$suffix";
    if (Path.exists(file)) Path.remove_file(file);
  }
}

/* Builds the group of table `index` from the input `owner`. An input that
   only imports its meta code, and whose own group does not build, gets
   the group of its imports alone. */
static void Helper.group(Helper &h, String owner, int index) {
  h.parse(owner, index);
  String failure = h.compile(index, owner);
  List reached = h.reaches[owner];
  if (reached && failure) {
    _clear(h.base(index));
    h.parse(_imports_unit(h.base(index), reached), index);
    failure = h.compile(index, owner);
  }
  h.record(index, failure);
}

/* Parses the unit at `path` for the group of table `index`, which the
   parse writes into the build directory. Diagnostics are the translation's
   to report; a unit that does not parse leaves the part it reached. */
static void Helper.parse(Helper &h, String path, int index) {
  Frontend f = h.frontend;
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

/* Compiles the group a parse left for table `index`, adding the files it
   read to `deps`. A quoted include resolves from the directory of `unit`.
   Returns NULL when its object is built, or else why not. */
static String Helper.compile(Helper &h, int index, String unit) {
  String base = h.base(index);
  if (!Path.is_file(%"$base.deps")) return "the unit has no group";
  foreach (String path, Path.read_text(%"$base.deps").split("\n"))
    if (path) h.deps[path] = 1;
  if (Path.is_file(%"$base.failure")) return Path.read_text(%"$base.failure");
  Toolchain t = h.toolchain;
  String failure = Compiler.meta_cc_run(
    %(${t.cc} @{_cc_flags()} "-iquote" ${h.directory}
      "-iquote" ${Path.dirname(unit)} "-iquote" ${h.include} @{h.flags}
      "-MD" "-MF" ${%"$base.d"} "-c" ${%"$base.c"} "-o" ${%"$base.o"}),
    h.directory);
  if (!failure) failure = _localize(t, base, index);
  _add_depfile(%"$base.d", h.deps);
  return failure;
}

/* Leaves `x2c_module_targets_K` the only global symbol of the object
   `base.o` of table K, so the groups of several units, each holding its own
   copy of what it imports, link into one program. */
static String _localize(Toolchain t, String base, int index) {
  String entry = %"x2c_module_targets_$index", object = %"$base.o";
  String merged = %"$base.r.o";
#ifdef __APPLE__
  String failure = Compiler.meta_cc_run(
    %(${t.cc} "-r" "-nostdlib" ${%"-Wl,-exported_symbol,_$entry"} $object
      "-o" $merged), NULL);
#else
  String failure = Compiler.meta_cc_run(
    %(${t.cc} "-r" "-nostdlib" $object "-o" $merged), NULL);
  if (!failure)
    failure = Compiler.meta_cc_run(
      %("objcopy" ${%"--keep-global-symbol=$entry"} $merged), NULL);
#endif
  if (!failure) Path.move_to(merged, object);
  return failure;
}

/* Adds each dependency of the depfile at `path` to `deps`. */
static void _add_depfile(String path, Map deps) {
  if (!Path.is_file(path)) return;
  foreach (String dependency, translation_depfile_parse(Path.read_text(path)))
    deps[Path.absolute(dependency)] = 1;
}

/* Writes a unit that imports each of `reached` beside the group files at
   `base`, and returns its path. */
static String _imports_unit(String base, List reached) {
  Array lines = [];
  foreach (String path, reached)
    lines.push(String.new("$(import ").add(path.repr()).add(")"));
  String source = %"$base-imports.x";
  Path.write_text(source, "\n".join(lines.list_free()).add("\n"));
  return source;
}

/* A table whose parse left a group joins the groups, with why it does not
   build or with its object. An object that differs from the earlier
   build's changes the helper. */
static void Helper.record(Helper &h, int index, String failure) {
  String base = h.base(index);
  if (!Path.is_file(%"$base.deps")) return;
  h.groups.push(index);
  if (failure) h.failures.push(%($index $failure));
  else {
    h.built.push(index);
    h.objects.push(%"$base.o");
    if (_digest(%"$base.o") != h.before[index]) h.changed = 1;
  }
}

// linking

/* Links the helper with the runtime when an object or the table changed,
   so a change to program code alone keeps the helper. Returns why the
   helper does not link, or NULL. */
static String Helper.link(Helper &h, int count) {
  String failure = NULL;
  String support = h.support(failure);
  if (!support) return failure;
  String tables = %"${h.directory}/tables.c", table = _tables(h.built, count);
  String helper = %"${h.directory}/helper";
  if (!h.changed && Path.is_file(tables) && Path.read_text(tables) == table &&
      Path.is_file(helper)) return NULL;
  Path.write_text(tables, table);
  String output = _temporary(helper);
  failure = Compiler.meta_cc_run(
    h.link_arguments(output, tables, support), NULL);
  if (!failure) Path.move_to(output, helper);
  else if (Path.exists(helper)) Path.remove_file(helper);
  return failure;
}

/* The object of the helper's protocol loop, which this compiler translates
   once per identity, or NULL with `failure` set. */
static String Helper.support(Helper &h, String &failure) {
  String source = _loop_source();
  if (!Path.is_file(source)) {
    failure = %"cannot read $source";
    return NULL;
  }
  String key = String.sha256(
    %"${h.identity}\n${Path.read_text(source).sha256()}");
  String directory = %"${script_cache_root()}/meta/support-$key";
  String object = %"$directory/meta-helper.o";
  if (Path.is_file(object)) return object;
  Path.make_dirs(directory);
  int lock = file_lock(%"$directory/lock", 1);
  defer close(lock);
  if (Path.is_file(object)) return object;
  failure = h.compile_support(source, directory, object);
  return failure ? NULL : object;
}

/* Translates the loop's `source` into `directory` and compiles it to
   `object`. Returns why not, or NULL. */
static String Helper.compile_support(
  Helper &h, String source, String directory, String object) {
  String printed = NULL, errors = NULL;
  if (tool_capture(
    %(${x2c_get_executable()} "translate" "--out-dir" $directory $source),
    printed, errors))
    return %"cannot translate $source: ${errors.strip(NULL)}";
  Toolchain t = h.toolchain;
  String include = h.include, output = _temporary(object);
  String failure = Compiler.meta_cc_run(
    %(${t.cc} @{_cc_flags()} "-iquote" $directory "-iquote" $include
      "-c" ${%"$directory/meta-helper.c"} "-o" $output), NULL);
  if (!failure) Path.move_to(output, object);
  return failure;
}

/* The path a process writes before it moves the result to `path`. */
static String _temporary(String path) =>
  %"$path.${"%ld".printf((long) getpid())}";

/* The unit that gives the helper each built table by index. */
static String _tables(Array built, int count) {
  Buffer out = Buffer.new(0);
  $output.helper.header(out);
  foreach (int index, built)
    $output.helper.target(out, index);
  $output.helper.dispatch_begin(out);
  foreach (int index, built)
    $output.helper.dispatch_case(out, index);
  $output.helper.dispatch_end(out);
  $output.helper.count(out, count);
  return out;
}

/* Native modules use their host's runtime, including units the helper
   itself never calls, so the link matches the compiler's whole-runtime
   link. It also compiles the table, which includes the runtime headers. */
static List Helper.link_arguments(
  Helper &h, String output, String tables, String support) {
  Toolchain t = h.toolchain;
#ifdef __APPLE__
  t.ld_args = %(${%"-Wl,-force_load,${t.runtime_lib}"});
#else
  t.ld_args = %("-Wl,--export-dynamic,--whole-archive" ${t.runtime_lib}
                "-Wl,--no-whole-archive");
#endif
  List inputs = %(@{h.objects.list()} $tables $support);
  String archive = Compiler.extension_archive();
  if (archive) inputs = inputs.append(%($archive));
  ToolAction link = t.link_action(output, inputs);
  return %(@{link.arguments} @{_cc_flags()} "-iquote" ${h.include});
}

// manifests

/* Writes the manifest into the build directory and returns it:
   `(groups (K ...))` for each table that has a group, `(failures ((K WHY)
   ...))` for those that do not build, `(failure WHY)`, empty unless the
   helper does not link, and `(deps ((PATH DIGEST) ...))` for every file
   the build read. */
static List Helper.write_manifest(Helper &h, String failure) {
  List manifest = %(
    (groups ${h.groups.list()}) (failures ${h.failures.list()})
    (failure ${failure ? failure : ""}) (deps ${_digests(h.deps)}));
  Buffer out = $auto(Buffer.new(0));
  datum_write(out, manifest, 0);
  Path.write_text(%"${h.directory}/manifest", out);
  return manifest;
}

/* Each file of `paths` that can be read, with its digest, in order. */
static List _digests(Map paths) {
  Array rows = [];
  foreach (Var (path, _), paths) {
    String digest = _digest(path);
    if (digest) rows.push(%($path $digest));
  }
  return rows.sort();
}

/* The manifest a previous build left in `directory` when every file it
   read is unchanged, or NULL. */
static List _current(String directory) {
  String path = %"$directory/manifest";
  if (!Path.is_file(path)) return NULL;
  String text = Path.read_text(path);
  unsigned cursor = 0;
  Var datum = void;
  try datum_read(text, cursor, datum);
  catch %((!or incomplete malformed) *): return NULL;
  if (datum is not <list>) return NULL;
  List manifest = datum;
  /* A failure may come from a file the build could not read, such as a
     missing header, which no digest covers; build again. */
  if (manifest.assoc(<failures>) ||
      ((String) manifest.assoc(<failure>)).len())
    return NULL;
  foreach (List row, manifest.assoc(<deps>)) {
    (String file, String digest) = row;
    if (_digest(file) != digest) return NULL;
  }
  return manifest;
}

/* The SHA-256 of the bytes of the file at `path`, or NULL when it cannot
   be read. */
static String _digest(String path) {
  File input = fopen(path, "rb");
  if (!input) return NULL;
  defer input.close();
  return input.sha256();
}
