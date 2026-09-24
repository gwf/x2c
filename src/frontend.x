/*  frontend.x -- configured compiler sessions and sequential source units

    Copyright (c) 2025 Gary William Flake

    Shares source setup, collection, parsing, and unit lifetimes between the
    command-line compiler and internal tools. Adapters own printing and exit.
*/

#pragma once
#include "cli.x"
#include "compiler.x"
#include "toolchain.x"

/** Receives borrowed native-preprocessor stderr synchronously during
    collect.
*/
typedef void (*FrontendErrorSink)(String text);

/** Borrows a configured request and owns shared native-preprocessor setup.
    Units open sequentially; process caches must outlive the session.
    The optional stderr sink runs synchronously; units also retain that text.
*/
typedef struct Frontend {
  CliRequest request;
  List include_dirs;
  Toolchain toolchain;
  FrontendErrorSink preprocessor_errors;
} *Frontend;

/** Owns one isolated source lifetime, including unsuccessful diagnostics.
    Results remain borrowed until close; export values that must survive it.
*/
typedef struct ParsedUnit {
  Context context;
  Compiler compiler, preprocessor;
  Map globals;
  List ast;
  String preprocessor_output, preprocessor_errors;
  int source_lines, generated_symbols;
} ParsedUnit;

#pragma private

#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "build.x"
#include "collect.x"
#include "deps.x"
#include "utils.x"

static const SymbolSet cpp_dumps = %<<dump-cpp cpp-tokens dump-csym>>;

static int _source_lines(String text) {
  if (!text) return 0;
  int lines = text[text.len() - 1] == '\n' ? 0 : 1;
  for (char *ch = text; *ch; ch++)
    if (*ch == '\n') lines++;
  return lines;
}

static Token _first_preprocessor_token(Compiler compiler) {
  for (Token token = compiler.tokenizer.tokens; token.type != <eof>; token++)
    if (token.type == <preproc>) return token;
  return compiler.token;
}

/* Checks the stamp in the bytes of the module at `path` against the running
   compiler. Loading runs a module's code, so a module from another compiler
   is rejected before it is loaded. */
static void _check_module_stamp(String path) {
  String expected = build_module_stamp();
  if (!expected)
    x2c_driver_error(
      %"cannot read the running compiler to check native module '$path'");
  File input = fopen(path, "rb");
  if (!input)
    x2c_driver_error(
      %"cannot read native module '$path': ${String.new(strerror(errno))}");
  fseek(input, 0, SEEK_END);
  long end = ftell(input);
  rewind(input);
  char *data = Scope.malloc(end > 0 ? (size_t) end : 1);
  size_t size = end > 0 ? fread(data, 1, (size_t) end, input) : 0;
  input.close();
  /* The entry writes exactly one stamp; a file with any other count, or
     whose one stamp differs, was not built by this compiler. */
  String marker = "x2c-module-stamp:";
  int stamps = 0, current = 0, width = expected.len();
  for (size_t i = 0; i + marker.len() <= size; i++)
    if (!memcmp(data + i, marker, marker.len())) {
      stamps++;
      current = i + width <= size && !memcmp(data + i, expected, width);
    }
  Scope.free(data);
  if (stamps == 1 && current) return;
  if (!stamps) x2c_driver_error(%"not an x2c native module: $path");
  x2c_driver_error(
    %"native module '$path' was built by another compiler; rebuild it");
}

/* Loads the native module at `path` once per process and returns its
   absolute path. Loading runs the module's code inside the compiler, so it
   happens only on request. A module is never unloaded, because its Funcs
   borrow its code. */
static String _load_native_module(String path) {
#if defined(__COSMOPOLITAN__) || defined(_WIN32) || defined(__CYGWIN__)
  x2c_driver_error("native modules are not supported on this platform");
#endif
  String absolute = Path.absolute(path);
  if (Compiler.native_module_loaded(absolute)) return absolute;
  _check_module_stamp(path);
  void *handle = dlopen(absolute, RTLD_NOW | RTLD_LOCAL);
  if (!handle)
    x2c_driver_error(
      %"cannot load native module '$path': ${String.new(dlerror())}");
  Map (*entry)(void) = (Map (*)(void)) dlsym(handle, "x2c_module_targets");
  if (!entry) x2c_driver_error(%"not an x2c native module: $path");
  Compiler.add_native_module(absolute, entry);
  return absolute;
}

/** Loads process-owned collection support and the native modules `request`
    names before units, and selects those modules, in order, for its
    compile-time calls.
*/
void Frontend.load_support(CliRequest request) {
  interface_configure(request.out_dir, request.no_interfaces);
  Compiler.select_native_modules(
    request.native_modules.map(%!(String path) => _load_native_module(path)));
}

/** Borrows a configured request for sequential units. The request and this
    session must outlive its units. Initialize process support above any
    temporary command Context before creating a session inside that Context.
*/
Frontend Frontend.new(CliRequest request) {
  Frontend.load_support(request);
  Frontend frontend = Scope.calloc(1, sizeof(struct Frontend));
  frontend.request = request;
  frontend.include_dirs =
    request.include_dirs.append(x2c_default_include_dirs());
  frontend.toolchain = toolchain_new(
    request.cc, request.ar, request.cpp_args, request.cc_args,
    request.ld_args, request.verbose, request.dry_run);
  return frontend;
}

/* A `#!` first line makes the file a script unit, and that line reads as an
   include of `scripting.x`. Only the first line changes, so every later
   line number stays in place. */
static String _script_text(String text) {
  int end = text.find("\n");
  return %"#include \"scripting.x\"${end < 0 ? "" : text[end:]}";
}

static void _tokenize_input(
  Frontend frontend, ParsedUnit *unit, String filename) {
  Compiler c = unit.compiler;
  /* An absolute spelling of a home source resolves its directory as
     collection resolves an includer's, so the file shares the home-relative
     identity of the prelude's copy and keeps its own name. */
  if (filename.startswith("/")) {
    String canonical = %"${c.canonical_path(Path.dirname(filename))}/${
      Path.basename(filename)}";
    if (home_portable_path(canonical) != canonical) filename = canonical;
  }
  c.filename = filename;
  char source_path[PATH_MAX], runtime_path[PATH_MAX], lib_path[PATH_MAX];
  String lib = %"${x2c_get_root()}/lib", runtime = %"$lib/x2c.x";
  int source_resolved = realpath(filename, source_path) != NULL;
  int lib_resolved = realpath(lib, lib_path) != NULL;
  c.prelude =
    !(source_resolved &&
      realpath(runtime, runtime_path) &&
      !strcmp(source_path, runtime_path));
  int lib_length = lib_resolved ? strlen(lib_path) : 0;
  c.runtime_inc =
    !(source_resolved && lib_resolved &&
      !strncmp(source_path, lib_path, lib_length) &&
      source_path[lib_length] == '/');
  String text = NULL;
  if (!c.read_source(filename, &text))
    c.report_error(
      <driver>, "cannot read input file", NULL,
      %("stage: driver" "file: $filename" "reason: cannot open"));
  if (text && text.startswith("#!")) {
    int end = text.find("\n");
    ScriptUnit script = Scope.calloc(1, sizeof(struct ScriptUnit));
    script.path = source_resolved ? String.new(source_path) : filename;
    script.shebang = end < 0 ? text : text[:end];
    c.unit_script = script;
    text = _script_text(text);
  }
  c.include_dirs = frontend.include_dirs;
  unit.source_lines = _source_lines(text);
  c.tokenize(text);
  if (c.script) c.script.defines_main = c.defines_main();
}

/* A unit compiles in package mode only when it is one of that package's own
   files below `<root>/<name>/src/` or the single-file `<root>/<name>/<name>.x`
   under a registered --package-dir root. The comparison uses the canonical
   path, so symlinked or relative spellings of one file agree; a test or
   example elsewhere in the package directory is a consumer and reaches the
   package through `import`. */
static void _configure_package(
  Compiler c, CliRequest request, String filename) {
  c.package_dirs = request.package_roots();
  String source = Path.absolute(filename);
  String package = x2c_package_directory(c.package_dirs, source);
  if (!package || !x2c_package_source(package, source)) return;
  String name = Path.basename(package);
  c.package = name;
  c.package_roots[name] = package;
}

static Map _preprocess_input(Frontend frontend, ParsedUnit *unit) {
  Compiler c = unit.compiler;
  CliRequest request = frontend.request;
  String filename = c.filename;
  if (request.no_cpp) return NULL;
  String root = x2c_get_root(), int use_prelude = !request.live_symbols;
  Map globs = NULL;
  int use_cpp = request.cpp_symbols || request.live_symbols ||
                cpp_dumps.contains(request.dump);
  if (use_prelude && !use_cpp) return c.collect_symbols(NULL);
  if (c.layout)
    c.report_error(
      <driver>, "indented units use the default symbol collection",
      _first_preprocessor_token(c),
      %("the host preprocessor does not keep the indentation, so"
        "--cpp-symbols, --live-symbols, and the --dump-cpp modes cannot read"
        "an indented unit"));
  if (c.script)
    c.report_error(
      <driver>, "script units use the default symbol collection",
      _first_preprocessor_token(c),
      %("the host preprocessor reads the #! line as C, so --cpp-symbols,"
        "--live-symbols, and the --dump-cpp modes cannot read a script"));
  Compiler cppcompiler = Compiler.new_shared(c);
  unit.preprocessor = cppcompiler;
  cppcompiler.filename = filename;
  String text = NULL, errors = NULL, dependency_text = NULL;
  String runtime = c.prelude ? %"$root/lib/x2c.x" : NULL;
  int status = frontend.toolchain.preprocess(
    filename, c.include_dirs, runtime, &text, &errors, &dependency_text);
  unit.preprocessor_output = text;
  unit.preprocessor_errors = errors;
  if (errors && frontend.preprocessor_errors)
    frontend.preprocessor_errors(errors);
  if (status) {
    List notes = %("stage: preprocess" "status: $status");
    c.report_error(
      <driver>, "failed to run C preprocessor",
      _first_preprocessor_token(c), notes);
  }
  foreach (String dependency, translation_depfile_parse(dependency_text))
    c.add_translation_dependency(dependency);
  if (!text) return NULL;
  if (request.dump == <dump-cpp>) return globs;
  cppcompiler.tokenize(text);
  // Expanded CPP offsets cannot describe the physical input files.
  cppcompiler.source_facts = 0;
  cppcompiler.source_private = -1;
  cppcompiler.collect_protocols = 0;
  if (request.dump == <cpp-tokens>) return globs;
  if (request.live_symbols) c.runtime_hdrs = 1;
  globs = c.collect_symbols(globs);
  cppcompiler.imports = c.imports;
  cppcompiler.macro_lisp = c.macro_lisp;
  cppcompiler.borrowed_lisp = cppcompiler.macro_lisp != NULL;
  Map saved_counters = NULL;
  if (!request.live_symbols) {
    saved_counters = c.names.counters;
    c.names.counters = c.names.counters.copy();
  }
  cppcompiler.shallow_parse(globs);
  globs = cppcompiler.sym.global_symbols();
  /* Owning-source collection already counted declaration names. CPP adds
     host declarations without counting the same source's names again. */
  if (!request.live_symbols) c.names.counters = saved_counters;
  return globs;
}

/** Opens and tokenizes an isolated source unit without printing diagnostics.
    A failed unit remains open so its diagnostics can be inspected. Close
    it before opening the next unit; Type and collection caches are
    process-global.
*/
static int _start(
  Frontend frontend, String filename, ParsedUnit *unit, int shared_values,
  String session_source) {
  *unit = (ParsedUnit) { 0 };
  unit.generated_symbols =
    !frontend.request.no_cpp && !frontend.request.dump;
  unit.context = shared_values
    ? Context.open_named("shared translation unit")
    : Context.open_isolated_named("translation unit");
  Type.begin_unit();
  unit.compiler = Compiler.new();
  Compiler compiler = unit.compiler;
  compiler.diagnostics.limit = frontend.request.max_errors;
  compiler.source_map = frontend.request.source_map;
  compiler.sources = frontend.request.sources;
  compiler.source_facts = frontend.request.source_facts;
  compiler.source_syntax = frontend.request.dump == <source-ast>;
  compiler.source_primary = 1;
  if (compiler.source_facts) {
    compiler.source_occurrences = [];
    compiler.source_definitions = {};
    compiler.source_declarations = {};
    compiler.source_texts = {};
  }
  compiler.recovery_depth++;
  try {
    if (filename) {
      _configure_package(compiler, frontend.request, filename);
      _tokenize_input(frontend, unit, filename);
    }
    else {
      compiler.filename = "<repl>";
      compiler.prelude = compiler.runtime_inc = 1;
      compiler.include_dirs = frontend.include_dirs;
      compiler.tokenize(session_source ? session_source : "$(begin)");
    }
  }
  catch %(malformed *): return 0;
  return !compiler.error_count();
}

/** Tokenizes one input into a fresh unit with its own isolated `Context`.
    The caller must close the unit on either result.
*/
int Frontend.start(Frontend frontend, String filename, ParsedUnit *unit) =>
  _start(frontend, filename, unit, 0, NULL);

/* Installs the compile-time forms `lib/meta.x` defines into the shared
   session, each also under its Lisp name. Its values belong to the build
   target's shared library scope because they outlive every unit that calls
   them. */
static int _preload_meta_surface(Frontend frontend, Lisp shared) {
  struct CliRequest request = *frontend.request;
  request.dump = 0;
  request.no_cpp = request.live_symbols = request.cpp_symbols = 0;
  struct Frontend session = *frontend;
  session.request = &request;
  frontend = &session;
  ParsedUnit unit;
  String path = %"${x2c_get_root()}/lib/meta.x";
  int started = _start(frontend, path, &unit, 1, NULL);
  unit.compiler.macro_lisp = shared;
  unit.compiler.borrowed_lisp = 1;
  defer unit.close();
  /* `lib/meta.x` includes `lib/varops.x`, whose imported helpers lower calls
     to these builders before they are parsed. Until the parse installs them,
     each is a compile-time-only name. */
  foreach (String name, %("x2c_expr_ident" "x2c_expr_index" "x2c_expr_call"
                          "x2c_expr_cast")) {
    shared.set_global(name, %());
    unit.compiler.meta_comptime[name] = 1;
  }
  if (!started || !unit.collect(frontend) || !unit.parse()) {
    foreach (List diagnostic, unit.compiler.diagnostics())
      unit.compiler.print_diagnostic(diagnostic);
    return 0;
  }
  foreach (String name, unit.compiler.meta_regions.keys()) {
    Var function;
    if (name.startswith("x2c_") && shared.try_get(name, &function))
      Compiler.bind_meta_operation(shared, name, function);
  }
  return 1;
}

/** Evaluates the compile-time libraries and installs the compiler surface's
    own definitions, once for the active build or translation target. Returns
    zero after reporting a failed preload, without publishing a partial
    session.
*/
int Frontend.preload_macro_libraries(Frontend frontend) {
  Compiler compiler = Compiler.new();
  Lisp shared = compiler.open_macro_library();
  if (shared && !_preload_meta_surface(frontend, shared)) {
    shared.destroy();
    compiler.publish_macro_library(NULL);
    collect_forget_preload_entries();
    return 0;
  }
  compiler.publish_macro_library(shared);
  collect_forget_preload_entries();
  return 1;
}

/** Collects symbols and retains preprocessor outputs for adapter
    inspection.
*/
int ParsedUnit.collect(ParsedUnit *unit, Frontend frontend) {
  Compiler compiler = unit.compiler;
  try {
    unit.globals = _preprocess_input(frontend, unit);
    if (unit.preprocessor)
      compiler.take_diagnostics(unit.preprocessor);
    compiler.sym.seed_var_tags(unit.globals);
  }
  catch %(malformed *): {
    if (unit.preprocessor) {
      compiler.close_child(unit.preprocessor);
      unit.preprocessor = NULL;
    }
    return 0;
  }
  return !compiler.error_count();
}

/** Parses a collected unit, retaining both its AST and unsuccessful
    reports.
*/
int ParsedUnit.parse(ParsedUnit *p) {
  Compiler compiler = p.compiler;
  if (compiler.error_count()) return 0;
  try p.ast = compiler.full_parse(p.globals, p.generated_symbols);
  catch %(malformed *): return 0;
  return !compiler.error_count();
}

/** Runs the source stages. On either result, the caller must close the
    unit.
*/
int Frontend.open(Frontend f, String filename, ParsedUnit *unit) =>
  f.start(filename, unit) && unit.collect(f) && unit.parse();

/** Opens an empty submission unit with the ordinary runtime prelude.
    Preload macro libraries first. The caller must close the unit on either
    result; submissions and inspection results borrow its Context. */
int Frontend.open_session(Frontend frontend, ParsedUnit *unit) =>
  _start(frontend, NULL, unit, 0, "$(begin)\n"
    "void print(String text);\n"
    "void println(String text);\n") &&
  unit.collect(frontend) && unit.parse();

/** Releases the unit after its caller has inspected or exported its
    results.
*/
void ParsedUnit.close(ParsedUnit *unit) {
  if (!unit.context) return;
  Compiler compiler = unit.compiler;
  if (unit.preprocessor) compiler.close_child(unit.preprocessor);
  compiler.free_lisp();
  Type.end_unit();
  unit.context.close();
  *unit = (ParsedUnit) { 0 };
}
