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


#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "build.x"
#include "collect.x"
#include "deps.x"
#include "utils.x"

// diagnostics

static macro Stmt $report.driver.input_read(Expr $c, Expr $filename) {
  $c.report_error(
    <driver>,
    "cannot read input file",
    NULL, %("stage: driver" "file: ${$filename}" "reason: cannot open"));
}

static macro Stmt $report.driver.script_symbols(Expr $c, Expr $site) {
  $c.report_error(
    <driver>,
    "script units use the default symbol collection",
    $site, %("the host preprocessor reads the #! line as C, so --cpp-symbols,"
    "--live-symbols, and the --dump-cpp modes cannot read a script"));
}

static macro Stmt $report.driver.indent_symbols(Expr $c, Expr $site) {
  $c.report_error(
    <driver>,
    "indented units use the default symbol collection",
    $site, %("the host preprocessor does not keep the indentation, so"
    "--cpp-symbols, --live-symbols, and the --dump-cpp modes cannot read"
    "an indented unit"));
}

static macro Stmt $report.driver.cpp_failed(Expr $c, Expr $site, Expr $status) {
  $c.report_error(
    <driver>,
    "failed to run C preprocessor",
    $site, %("stage: preprocess" "status: ${$status}"));
}

// source units

/** Runs the source stages. On either result, the caller must close the
    unit.
*/
int Frontend.open(Frontend f, String filename, ParsedUnit &unit) =>
  f.start(filename, unit) && unit.collect(f) && unit.parse();

/** Runs the source stages for a command that reports to stderr. Collection
    and parsing print each diagnostic as it is reported; a tokenizing
    failure prints its diagnostics afterward. A failed unit is closed; the
    caller must close a successful one.
*/
int Frontend.open_reporting(Frontend f, String filename, ParsedUnit &unit) {
  if (f.start(filename, unit)) {
    unit.compiler.own_diagnostics();
    if (unit.collect(f) && unit.parse()) return 1;
  }
  else foreach (Var entry, unit.compiler.diagnostics())
    unit.compiler.print_diagnostic(entry);
  unit.close();
  return 0;
}

/** Opens an empty submission unit with the ordinary runtime prelude.
    Preload macro libraries first. The caller must close the unit on either
    result; submissions and inspection results borrow its Context. */
int Frontend.open_session(Frontend frontend, ParsedUnit &unit) =>
  (Compiler.stage_meta_in_process(), 1) && _start(
    frontend, NULL, unit, _unit_context(), "$(begin)\n"
    "void print(String text);\n"
    "void println(String text);\n") &&
  unit.collect(frontend) && unit.parse();

/** Tokenizes one input into a fresh unit with its own isolated `Context`.
    The caller must close the unit on either result.
*/
int Frontend.start(Frontend frontend, String filename, ParsedUnit &unit) =>
  _start(frontend, filename, unit, _unit_context(), NULL);

/** Collects symbols and retains preprocessor outputs for adapter
    inspection.
*/
int ParsedUnit.collect(ParsedUnit &unit, Frontend frontend) {
  Compiler c = unit.compiler;
  try {
    unit.globals = _preprocess_input(frontend, unit);
    if (unit.preprocessor) c.take_diagnostics(unit.preprocessor);
    c.sym.seed_var_tags(unit.globals);
  }
  catch %(malformed *): {
    if (unit.preprocessor) c.close_child(unit.preprocessor);
    unit.preprocessor = NULL;
    return 0;
  }
  return !c.error_count();
}

/** Parses a collected unit, retaining both its AST and unsuccessful
    reports.
*/
int ParsedUnit.parse(ParsedUnit &p) {
  Compiler c = p.compiler;
  if (c.error_count()) return 0;
  try p.ast = c.full_parse(p.globals, p.generated_symbols);
  catch %(malformed *): return 0;
  return !c.error_count();
}

/** Releases the unit after its caller has inspected or exported its
    results.
*/
void ParsedUnit.close(ParsedUnit &unit) {
  if (!unit.context) return;
  Compiler c = unit.compiler;
  if (unit.preprocessor) c.close_child(unit.preprocessor);
  c.free_lisp();
  Type.end_unit();
  unit.context.close();
  unit = (ParsedUnit) { 0 };
}

// starting a unit

/* Opens and tokenizes a source unit in `context` without printing
   diagnostics: the file `filename`, or the session text `source` when
   `filename` is NULL. A failed unit remains open so its diagnostics can be
   inspected. Close it before opening the next unit; Type and collection
   caches are process-global. */
static int _start(
  Frontend frontend, String filename, ParsedUnit &unit, Context context,
  String source) {
  Compiler c = _begin_unit(frontend, unit, context);
  try {
    if (!filename) _tokenize_session(frontend, c, source);
    else {
      _configure_package(c, frontend.request, filename);
      _tokenize_input(frontend, unit, filename);
      c.inherited_lisp = Compiler.inherits_import(Path.absolute(filename));
      Compiler.begin_meta_unit(c.filename);
    }
  }
  catch %(malformed *): return 0;
  return !c.error_count();
}

static Context _unit_context(void) =>
  Context.open_isolated_named("translation unit");

/* The unit's compiler takes the request's error limit and source options,
   and records source facts when the request asks for them. */
static Compiler _begin_unit(
  Frontend frontend, ParsedUnit &unit, Context context) {
  CliRequest request = frontend.request;
  unit = (ParsedUnit) { 0 };
  unit.generated_symbols = !request.no_cpp &&
    (!request.dump || request.dump == <dump-defs>);
  unit.context = context;
  Type.begin_unit();
  unit.compiler = Compiler.new();
  Compiler c = unit.compiler;
  c.diagnostics.limit = request.max_errors;
  c.source_map = request.source_map;
  c.sources = request.sources;
  c.source_facts = request.source_facts;
  c.source_primary = 1;
  if (c.source_facts) {
    c.source_occurrences = [];
    c.source_definitions = {};
    c.source_declarations = {};
    c.source_texts = {};
  }
  c.recovery_depth++;
  return c;
}

static void _tokenize_session(Frontend frontend, Compiler c, String source) {
  c.filename = "<repl>";
  c.prelude = c.runtime_inc = 1;
  c.include_dirs = frontend.include_dirs;
  c.tokenize(source ? source : "$(begin)");
}

/* A unit compiles in package mode only when it is one of that package's own
   files below `<root>/<name>/src/` or the single-file `<root>/<name>/<name>.x`
   under an explicit --package-dir root. The comparison uses the canonical
   path, so symlinked or relative spellings of one file agree; a test or
   example elsewhere in the package directory is a consumer and reaches the
   package through `import`. */
static void _configure_package(
  Compiler c, CliRequest request, String filename) {
  c.package_dirs = request.package_roots();
  String source = Path.absolute(filename);
  String package = package_directory(request.package_dirs, source);
  if (!package || !package_source(package, source)) return;
  String name = Path.basename(package);
  c.package = name;
  c.package_roots[name] = package;
}

static void _tokenize_input(
  Frontend frontend, ParsedUnit &unit, String filename) {
  Compiler c = unit.compiler;
  c.filename = _input_name(c, filename);
  char source[PATH_MAX];
  int resolved = realpath(c.filename, source) != NULL;
  _runtime_roles(c, resolved ? source : NULL);
  String text = _read_input(c);
  if (text && text.startswith("#!"))
    text = _script(c, text, resolved ? String.new(source) : c.filename);
  c.include_dirs = frontend.include_dirs;
  unit.source_lines = _source_lines(text);
  c.tokenize(text);
  if (c.script) c.script.defines_main = c.defines_main();
}

/* An absolute spelling of a home source resolves its directory as
   collection resolves an includer's, so the file shares the home-relative
   identity of the prelude's copy and keeps its own name. */
static String _input_name(Compiler c, String filename) {
  if (!filename.startswith("/")) return filename;
  String canonical = %"${c.canonical_path(Path.dirname(filename))}/${
    Path.basename(filename)}";
  return home_portable_path(canonical) != canonical ? canonical : filename;
}

/* A unit reads the runtime prelude unless it is `lib/x2c.x`, and the
   runtime headers unless it lies under `lib/`. `source` is the unit's
   resolved path, or NULL. */
static void _runtime_roles(Compiler c, const char *source) {
  char runtime[PATH_MAX], lib[PATH_MAX];
  String dir = %"${x2c_get_root()}/lib";
  c.prelude =
    !(source && realpath(%"$dir/x2c.x", runtime) && !strcmp(source, runtime));
  c.runtime_inc = !(source && realpath(dir, lib) && _inside(source, lib));
}

static int _inside(const char *path, const char *dir) {
  size_t n = strlen(dir);
  return !strncmp(path, dir, n) && path[n] == '/';
}

static String _read_input(Compiler c) {
  String filename = c.filename, text = NULL;
  if (c.read_source(filename, text)) return text;
  $report.driver.input_read(c, filename);
}

/* A `#!` first line makes the file a script unit, and that line reads as an
   include of `scripting.x`. Only the first line changes, so every later
   line number stays in place. */
static String _script(Compiler c, String text, String path) {
  int end = text.find("\n");
  ScriptUnit script = Scope.calloc(1, sizeof(struct ScriptUnit));
  script.path = path;
  script.shebang = end < 0 ? text : text[:end];
  c.unit_script = script;
  return %"#include \"scripting.x\"${end < 0 ? "" : text[end:]}";
}

static int _source_lines(String text) {
  if (!text) return 0;
  int lines = text[text.len() - 1] == '\n' ? 0 : 1;
  for (char *ch = text; *ch; ch++) if (*ch == '\n') lines++;
  return lines;
}

// symbol collection

static const SymbolSet cpp_dumps = %<<dump-cpp cpp-tokens dump-csym>>;

/* Without a host-preprocessor mode, a unit collects only its own
   declarations. With one, a child compiler that shares the unit's package
   and name state also parses the preprocessed text, unless a dump of that
   text or its tokens stops first. */
static Map _preprocess_input(Frontend frontend, ParsedUnit &unit) {
  Compiler c = unit.compiler;
  CliRequest request = frontend.request;
  if (request.no_cpp) return NULL;
  int use_cpp = request.cpp_symbols || request.live_symbols ||
                request.dump in cpp_dumps;
  if (!use_cpp) return _collect_input(frontend, unit);
  _check_cpp_unit(c);
  Compiler cpp = _run_cpp(frontend, unit);
  String text = unit.preprocessor_output;
  if (!text || request.dump == <dump-cpp>) return NULL;
  _tokenize_cpp(cpp, text);
  if (request.dump == <cpp-tokens>) return NULL;
  if (request.live_symbols) c.runtime_hdrs = 1;
  Map globs = _collect_input(frontend, unit);
  List private_rows = _unit_private_rows(c, globs);
  _share_session(cpp, c);
  /* Owning-source collection already counted declaration names. CPP adds
     host declarations without counting the same source's names again. */
  if (request.live_symbols) cpp.shallow_parse(globs);
  else $let(c.names.counters, c.names.counters.copy())
    cpp.shallow_parse(globs);
  Map symbols = cpp.sym.global_symbols();
  foreach (List row, private_rows) {
    if (row.len() == 1) symbols.del(row.car());
    else symbols[row.car()] = row.cadr();
  }
  return symbols;
}

/* Host preprocessing sees included function bodies, but source collection
   already established which unit owns each static function. */
static List _unit_private_rows(Compiler c, Map globs) {
  Array rows = [];
  String unit = c.canonical_path(c.filename);
  foreach (Var (key, owner), globs)
    match (key) case %("unit-static" ?name): {
      String path = home_absolute_path(owner.list().car());
      if (c.canonical_path(path) == unit) continue;
      rows.push(_unit_private_row(globs, %($name)));
      rows.push(_unit_private_row(globs, %(self $name)));
    }
  return rows.list_free();
}

static List _unit_private_row(Map globs, List key) {
  Var value = globs[key];
  return value is void ? %($key) : %($key $value);
}

/* A helper parse continues after a declaration producer fails before its
   helper exists. Keep the collected prefix for that recovery parse. */
static Map _collect_input(Frontend frontend, ParsedUnit &unit) {
  Compiler c = unit.compiler;
  unit.globals = {};
  $let(c.package, c.package) {
    _enter_package(frontend, c);
    return c.collect_symbols(unit.globals);
  }
}

/* A generated registration unit collects as a member of the package it
   registers. */
static void _enter_package(Frontend frontend, Compiler c) {
  Map packages = frontend.request.collection_packages;
  if (packages == NULL) return;
  Var root = packages[Path.absolute(c.filename)];
  if (root is void) return;
  c.package = Path.basename(root);
  c.package_roots[c.package] = root;
}

/* The host preprocessor keeps neither a unit's indentation nor its `#!`
   line. */
static void _check_cpp_unit(Compiler c) {
  if (c.layout)
    $report.driver.indent_symbols(c, _first_directive(c));
  if (c.script)
    $report.driver.script_symbols(c, _first_directive(c));
}

static Token _first_directive(Compiler c) {
  for (Token token = c.tokenizer.tokens; token.type != <eof>; token++)
    if (token.type == <preproc>) return token;
  return c.token;
}

/* Runs the host preprocessor for a child compiler that shares the unit's
   package and name state. The unit keeps the output and the errors, which
   the frontend's sink also receives, and the unit depends on every file
   the preprocessor read. */
static Compiler _run_cpp(Frontend frontend, ParsedUnit &unit) {
  Compiler c = unit.compiler, cpp = Compiler.new_shared(c);
  unit.preprocessor = cpp;
  cpp.filename = c.filename;
  String text = NULL, errors = NULL, dependency_text = NULL;
  String runtime = c.prelude ? %"${x2c_get_root()}/lib/x2c.x" : NULL;
  int status = frontend.toolchain.preprocess(
    c.filename, c.include_dirs, runtime, text, errors, dependency_text);
  unit.preprocessor_output = text ? _take_line_markers(cpp, text) : NULL;
  unit.preprocessor_errors = errors;
  if (errors && frontend.preprocessor_errors)
    frontend.preprocessor_errors(errors);
  if (status)
    $report.driver.cpp_failed(c, _first_directive(c), status);
  foreach (String dependency, translation_depfile_parse(dependency_text))
    c.add_translation_dependency(dependency);
  return cpp;
}

/* The host's line markers leave the text the compiler reads, since one can
   fall inside a multi-line literal. Each becomes the row
   `(position text-line file line)`: the text from byte `position`, which
   begins its line `text-line`, came from line `line` of `file`. */
static String _take_line_markers(Compiler cpp, String text) {
  Array kept = [], markers = [];
  int position = 0, text_line = 1;
  foreach (String line, text.split("\n")) {
    int number = 0;
    String file = line.startswith("#")
                ? preproc_marker_file(line, number) : NULL;
    if (!file) {
      kept.push(line);
      position += line.len() + 1;
      text_line++;
    }
    else if (!file.startswith("<"))
      markers.push(%($position $text_line $file $number));
  }
  cpp.line_markers = markers;
  return "\n".join(kept.list_free());
}

static void _tokenize_cpp(Compiler cpp, String text) {
  cpp.tokenize(text);
  // Expanded CPP offsets cannot describe the physical input files.
  cpp.source_facts = 0;
  cpp.source_private = -1;
  cpp.collect_protocols = 0;
}

// The child parses in the unit's compile-time session.
static void _share_session(Compiler cpp, Compiler c) {
  cpp.imports = c.imports;
  cpp.macro_lisp = c.macro_lisp;
  cpp.borrowed_lisp = cpp.macro_lisp != NULL;
  cpp.share_meta_group(c);
}

// compile-time libraries

/** Evaluates the compile-time libraries and installs the compiler surface's
    own definitions, once for the active build or translation target. Returns
    zero after reporting a failed preload, without publishing a partial
    session.
*/
int Frontend.preload_macro_libraries(Frontend frontend) {
  Compiler c = Compiler.new();
  Lisp shared = c.open_macro_library();
  if (shared && !_preload_meta_surface(frontend, shared)) {
    shared.destroy();
    c.publish_macro_library(NULL);
    collect_forget_provisional_entries();
    return 0;
  }
  c.publish_macro_library(shared);
  collect_forget_provisional_entries();
  return 1;
}

/* Installs the compile-time forms `lib/meta.x` defines into the shared
   session, each also under its Lisp name. Its values belong to the build
   target's shared library scope because they outlive every unit that calls
   them. The surface parses as an ordinary unit, whatever dump or symbol
   mode the request selects. */
static int _preload_meta_surface(Frontend frontend, Lisp shared) {
  struct CliRequest request = *frontend.request;
  request.dump = 0;
  request.no_cpp = request.live_symbols = request.cpp_symbols = 0;
  struct Frontend session = *frontend;
  session.request = &request;
  ParsedUnit unit;
  String path = %"${x2c_get_root()}/lib/meta.x";
  Context context = Context.open_named("shared translation unit");
  int started = _start(&session, path, unit, context, NULL);
  Compiler c = unit.compiler;
  c.macro_lisp = shared;
  c.borrowed_lisp = 1;
  defer unit.close();
  _declare_builders(c, shared);
  /* As in `Frontend.open_reporting`, the compiler that reports a diagnostic
     prints it, so an imported file's location shows that file's line. */
  if (started) c.own_diagnostics();
  else foreach (Var entry, c.diagnostics()) c.print_diagnostic(entry);
  if (!started || !unit.collect(&session) || !unit.parse()) return 0;
  foreach (String name, c.meta_hashes.keys()) {
    Var function;
    if (name.startswith("x2c_") && shared.try_get(name, function))
      Compiler.bind_meta_operation(shared, name, function);
  }
  return 1;
}

/* `lib/meta.x` includes `lib/varops.x`, whose included helpers lower calls
   to these builders before they are parsed. Until the parse installs them,
   each is a compile-time-only name. */
static void _declare_builders(Compiler c, Lisp shared) {
  List names =
    %("x2c_expr_ident" "x2c_expr_index" "x2c_expr_call" "x2c_expr_cast");
  foreach (String name, names) {
    shared.set_global(name, %());
    c.meta_comptime[name] = 1;
  }
}

// lifecycle

/** Loads process-owned collection support and the native modules `request`
    names before units, and selects those modules, in order, for its
    compile-time calls.
*/
void Frontend.load_support(CliRequest request) {
  interface_configure(request.out_dir, request.no_interfaces);
  Compiler.select_native_modules(
    request.native_modules.map(
      %!(String path) => Compiler.load_native_module(path)));
}

/** Borrows a configured request for sequential units. The request and this
    session must outlive its units. Initialize process support above any
    temporary command Context before creating a session inside that Context.
*/
Frontend Frontend.new(CliRequest request) {
  Frontend.load_support(request);
  Frontend f = Scope.calloc(1, sizeof(struct Frontend));
  f.request = request;
  f.include_dirs = request.include_dirs.append(default_include_dirs());
  f.toolchain = toolchain_new(request);
  Compiler.use_meta_toolchain(
    toolchain_meta_cc(request.meta_cc), f.toolchain.include_dir);
  return f;
}
