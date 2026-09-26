/*  meta-project.x -- the project meta build

    Copyright (c) 2026 Gary William Flake.

    Before a translation starts, the bodied `meta` functions its inputs
    reach are compiled into one helper program linked against the runtime,
    which the translation then calls (`src/stage.x`). They come from each
    project `.xmacro` file an input imports, directly, through an included
    header, or through a package, and from an input that defines its own
    until those move to `.xmacro` files. Meta code under the x2c root's
    `lib`, `src`, and `etc` is the compiler's own, linked into it.

    Table 0 holds the functions of every imported `.xmacro` file, parsed as
    one unit that imports them all. An input that defines its own gets a
    table of its own, which holds its imports as well. The helper is cached
    under the x2c cache root, keyed by the SHA-256 of those sources, the
    compiler stamp, the C compiler's identity, and the flags, and is built
    again when a file its build read, x2c source or C header, changes.
*/

#pragma once
#include "frontend.x"

#pragma private

#include "datum.x"
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
  CliRequest request, String path, Array imports, Map seen) {
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
          _meta_scan(request, file, imports, seen))
        imports.push(file);
    }
    else if (word == "import") {
      String name = _meta_quoted(tokens.next()), root = NULL;
      String entry = name ? x2c_package_entry(
        request.sources, request.package_roots(), name, root) : NULL;
      if (entry) _meta_scan(request, entry, imports, seen);
    }
    else if (token.type == <preproc> && word.startswith("#include \"") &&
             word.endswith(".x\"")) {
      String file = %"$directory/${word[10:word.len() - 1]}";
      if (Path.is_file(file) && !_meta_owned(Path.absolute(file)))
        _meta_scan(request, Path.absolute(file), imports, seen);
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
  if (started && unit.collect(f)) unit.parse();
}

/* Runs `arguments`, a C compiler command, and returns NULL, or its first
   error. */
static String _meta_cc(List arguments) {
  String printed = NULL, errors = NULL;
  if (!tool_capture(arguments, printed, errors)) return NULL;
  return Compiler.meta_cc_error(errors);
}

/* The object of `etc/meta-helper.x`, the helper's protocol loop, which
   this compiler translates once per `identity`, or NULL with `failure`
   set. */
static String _meta_support(
  Toolchain t, String include, String identity, String &failure) {
  String source = %"${x2c_get_root()}/etc/meta-helper.x";
  String text = NULL;
  try text = Path.read_text(source);
  catch %((!or not-found io-fail) *): {
    failure = %"cannot read $source";
    return NULL;
  }
  String key = String.sha256(%"$identity\n${text.sha256()}");
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

/* Adds each dependency of the depfile at `path` to `deps`. */
static void _meta_depfile(String path, Map deps) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return;
  foreach (String dependency, translation_depfile_parse(text))
    deps[Path.absolute(dependency)] = 1;
}

/* Parses each source into its group, compiles the groups, and links the
   helper in `directory` with the runtime. Returns the manifest: `(groups
   (K ...))` for each table that has a group, `(failures ((K WHY) ...))`
   for those that do not build, `(failure WHY)`, empty unless the helper
   does not link, and `(deps ((PATH DIGEST) ...))` for every file the
   build read. */
static List _meta_build(
  Frontend f, String directory, List imports, List owners, Toolchain t,
  String include, String identity) {
  int count = owners.len() + 1;
  for (int index = 0; index < count; index++)
    foreach (String suffix, %(".c" ".h" ".o" ".d" ".deps" ".failure")) {
      String file = %"$directory/group-$index$suffix";
      if (Path.exists(file)) Path.remove_file(file);
    }
  Compiler.use_meta_build_directory(directory);
  if (imports) {
    Array lines = [];
    foreach (String path, imports)
      lines.push(String.new("$(import ").add(path.repr()).add(")"));
    String source = %"$directory/meta-imports.x";
    Path.write_text(source, "\n".join(lines.list_free()).add("\n"));
    _meta_unit(f, source, 0);
  }
  int index = 1;
  foreach (String owner, owners) _meta_unit(f, owner, index++);
  Compiler.use_meta_build_directory(NULL);

  Map deps = {};
  foreach (String path, %(@imports @owners)) deps[path] = 1;
  Array groups = [], built = [], failures = [], objects = [];
  for (index = 0; index < count; index++) {
    String base = %"$directory/group-$index";
    if (!Path.is_file(%"$base.deps")) continue;
    groups.push(index);
    foreach (String path, Path.read_text(%"$base.deps").split("\n"))
      if (path) deps[path] = 1;
    String failure = NULL;
    if (Path.is_file(%"$base.failure"))
      failure = Path.read_text(%"$base.failure");
    else {
      failure = _meta_cc(%(${t.cc} @{_meta_flags()} "-iquote" $directory
                           "-iquote" $include "-MD" "-MF" ${%"$base.d"}
                           "-c" ${%"$base.c"} "-o" ${%"$base.o"}));
      if (failure && !failure.contains(directory))
        failure = %"$failure; the group's C is in $directory";
      _meta_depfile(%"$base.d", deps);
    }
    if (failure) failures.push(%($index $failure));
    else {
      built.push(index);
      objects.push(%"$base.o");
    }
  }
  String failure = NULL;
  String support = _meta_support(t, include, identity, failure);
  if (support) {
    String tables = %"$directory/tables.c";
    Path.write_text(tables, _meta_tables(built, count));
    String output = %"$directory/helper.${"%ld".printf((long) getpid())}";
    ToolAction link = t.link_action(
      output, %(@{objects.list()} $tables $support));
    failure = _meta_cc(%(@{link.arguments} "-iquote" $include));
    if (!failure) Path.move_to(output, %"$directory/helper");
  }
  Array rows = [];
  foreach (Var (path, _), deps) {
    String text = NULL;
    try text = Path.read_text(path);
    catch %((!or not-found io-fail) *): continue;
    rows.push(%($path ${text.sha256()}));
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
  String text = NULL;
  try text = Path.read_text(%"$directory/manifest");
  catch %((!or not-found io-fail) *): return NULL;
  unsigned cursor = 0;
  Var manifest = void;
  try datum_read(text, cursor, manifest);
  catch %((!or incomplete malformed) *): return NULL;
  if (manifest is not <list>) return NULL;
  foreach (List row, ((List) manifest).assoc(<deps>)) {
    (String path, String digest) = row;
    String current = NULL;
    try current = Path.read_text(path);
    catch %((!or not-found io-fail) *): return NULL;
    if (current.sha256() != digest) return NULL;
  }
  return manifest;
}

/** Builds the helper that runs the project `meta` functions `inputs`
    reach, or finds it in the cache, and makes it the one their translation
    calls. Inputs that reach none use no helper. A group or helper that
    does not build is reported at the first call that needs it. */
void Frontend.prepare_meta(Frontend f, List inputs) {
  Array imports = [], owners = [];
  Map seen = {};
  foreach (String input, inputs) {
    String path = Path.absolute(input);
    if (_meta_scan(f.request, path, imports, seen)) owners.push(path);
  }
  String include = NULL, cc = Compiler.meta_cc(include);
  String root = script_cache_root(), stamp = build_module_stamp();
  if ((!imports.len() && !owners.len()) || !cc || !root || !stamp) {
    Compiler.use_meta_helper(NULL, NULL, NULL);
    return;
  }
  Toolchain t = toolchain_new(cc, NULL, NULL, NULL, NULL, 0, 0);
  String compiler = Compiler.meta_cc_identity(cc);
  String flags = _meta_flags().repr();
  String identity =
    %"$stamp\n$compiler\n$flags\n$include\n${t.runtime_lib}";
  Array key = [identity];
  foreach (String path, %(@imports "--" @owners)) {
    String text = NULL;
    try text = Path.read_text(path);
    catch %((!or not-found io-fail) *): text = "";
    key.push(%"$path ${text.sha256()}");
  }
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
        f, directory, imports, owners, t, include, identity);
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
