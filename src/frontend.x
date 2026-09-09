/*  frontend.x -- configured compiler sessions and sequential source units

    Copyright (c) 2025 Gary William Flake

    Shares source setup, collection, parsing, and unit lifetimes between the
    command-line compiler and internal tools. Adapters own printing and exit.
*/

#pragma once
#include "cli.x"
#include "compiler.x"
#include "toolchain.x"

/** Receives borrowed native-preprocessor stderr synchronously during collect. */
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
  Map globals, snapshot_statics;
  List ast;
  String preprocessor_output, preprocessor_errors;
  int source_lines;
} ParsedUnit;

#pragma private

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "collect.x"
#include "deps.x"
#include "snapshot.x"
#include "utils.x"

static const SymbolSet cpp_dumps =
  %<<dump-cpp cpp-tokens dump-csym snapshot>>;

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

// Process-lifetime symbol snapshot, loaded once in the root epoch so
// every translation unit shares the interned rows.
static Map snapshot_globals;
static Map snapshot_function_definitions, static String snapshot_error;
static int snapshot_gensym, snapshot_loaded;

/* Generated-name counter for the whole process rather than per unit. The
   header-contribution cache outlives a unit, and its rows embed the gensym
   numbers allocated when the header was first walked. Restarting the counter
   at the snapshot base for every unit let a later unit mint a number a
   cached row already held. Two anonymous aggregates then shared one key
   and the second won. The numbers are compiler-internal and no emission
   path prints one, so they need only be unique. */
static int gensym_cursor;
static int header_symbols_loaded;

// Load the symbol snapshot once; errors are reported per file because
// diagnostics need a tokenized compiler for their anchor token.
static void _load_snapshot_once(void) {
  if (snapshot_loaded) return;
  snapshot_loaded = 1;
  String snapshot_path = %"${x2c_get_root()}/etc/symbols.xlisp";
  try snapshot_globals = symbol_snapshot_load(
    snapshot_path, &snapshot_function_definitions, &snapshot_gensym);
  catch %(not-found *):
    snapshot_error = %"missing symbol snapshot: $snapshot_path";
  catch %(io-fail *):
    snapshot_error = %"cannot read symbol snapshot: $snapshot_path";
  catch %(incomplete *):
    snapshot_error = %"incomplete symbol snapshot: $snapshot_path";
  catch %(malformed *):
    snapshot_error = %"malformed symbol snapshot: $snapshot_path";
}

/** Loads process-owned type, snapshot, and header support before units. */
void Frontend.load_support(CliRequest request) {
  Type.initialize();
  header_symbols_initialize();
  if (!request.live_symbols && !request.no_cpp) _load_snapshot_once();
  if (request.no_cpp || request.source_facts ||
      request.dump == <hdr-syms> ||
      request.live_symbols || header_symbols_loaded)
    return;
  String artifact = %"${x2c_get_root()}/etc/header-symbols.xlisp";
  header_symbols_open(artifact, snapshot_gensym);
  header_symbols_loaded = 1;
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

/** Writes collected header symbols using the loaded snapshot's name base. */
int Frontend.write_header_symbols(File output) {
  return header_symbols_write(output, snapshot_gensym);
}

static String _unreadable_input(
  Compiler compiler, String filename, String reason) {
  List notes = %("stage: driver" "file: $filename" "reason: $reason");
  compiler.report_error(<driver>, "cannot read input file", NULL, notes);
}

// Read the primary source file. fopen() opens directories on some
// platforms and then reads nothing, so the handle is checked for a regular
// file before its text is taken. An empty file yields the canonical empty
// String (a NULL pointer), which the rest of the pipeline treats as an
// empty translation unit.
static String _read_input_text(Compiler compiler, String filename) {
  if (compiler.sources) {
    String text;
    if (!compiler.read_source(filename, &text))
      return _unreadable_input(compiler, filename, "cannot open");
    return text;
  }
  File file = NULL;
  try file = filename.open("r");
  catch %(not-found *):
    return _unreadable_input(compiler, filename, "cannot open");
  catch %(io-fail *):
    return _unreadable_input(compiler, filename, "cannot open");
  struct stat info;
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    return _unreadable_input(compiler, filename, "not a regular file");
  }
  String text = NULL;
  try text = file.string_close();
  catch %(io-fail *):
    return _unreadable_input(compiler, filename, "read failed");
  return text;
}

static void _tokenize_input(
  Frontend frontend, ParsedUnit *unit, String filename) {
  Compiler c = unit->compiler;
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
  String text = _read_input_text(c, filename);
  unit->source_lines = _source_lines(text);
  c.tokenize(text);
  c.include_dirs = frontend.include_dirs;
}

/* A unit compiles in package mode only when it is one of that package's own
   files below `<root>/<name>/src/` or the single-file `<root>/<name>/<name>.x`
   under a registered --package-dir root. The comparison uses the canonical
   path, so symlinked or relative spellings of one file agree; a test or
   example elsewhere in the package directory is a consumer and reaches the
   package through `import`. */
static void _configure_package(
  Compiler compiler, CliRequest request, String filename) {
  char buffer[PATH_MAX];
  compiler.package_dirs = request.package_dirs;
  if (!request.package_dirs) return;
  String source;
  if (compiler.sources) source = SourceView.path(filename);
  else {
    if (!realpath(filename, buffer)) return;
    source = %"$buffer";
  }
  foreach (String directory, request.package_dirs) {
    String root;
    if (compiler.sources) root = %"${SourceView.path(directory)}/";
    else {
      if (!realpath(directory, buffer)) continue;
      root = %"$buffer/";
    }
    if (!source.startswith(root)) continue;
    String rest = source[root.len():], int slash = rest.find("/");
    if (slash <= 0) continue;
    String name = rest[:slash], tail = rest[slash + 1:];
    if (!name.is_identifier()) continue;
    if (!tail.startswith("src/") && tail != %"$name.x") continue;
    compiler.package = name;
    compiler.package_roots[name] = %"$root$name";
    return;
  }
}

static Map _preprocess_input(Frontend frontend, ParsedUnit *unit) {
  Compiler c = unit->compiler;
  CliRequest request = frontend.request;
  String filename = c.filename;
  if (request.no_cpp) return NULL;
  String root = x2c_get_root(), int use_snapshot = !request.live_symbols;
  Map globs = NULL;
  if (use_snapshot) {
    if ((void *) snapshot_globals == NULL)
      c.report_error(
        <driver>, snapshot_error,
        _first_preprocessor_token(c), NULL);
    // One copy per translation unit. collect_symbols merges the unit's
    // own symbols into its argument, and units must not see each other's
    // additions.
    globs = snapshot_globals.copy();
    c.fn_defs = snapshot_function_definitions.copy();
    if (gensym_cursor < snapshot_gensym) gensym_cursor = snapshot_gensym;
    c.set_gensym(gensym_cursor);
  }
  int use_cpp = request.cpp_symbols || request.live_symbols ||
                cpp_dumps.contains(request.dump);
  if (use_snapshot && !use_cpp) {
    Map result = c.collect_symbols(globs);
    return result;
  }
  Compiler cppcompiler = Compiler.new_shared(c);
  unit->preprocessor = cppcompiler;
  cppcompiler.filename = filename;
  String text = NULL, errors = NULL, dependency_text = NULL;
  String runtime = c.prelude ? %"$root/lib/x2c.x" : NULL, imacros = runtime;
  String force_include = NULL;
  int status = frontend.toolchain.preprocess(
    filename, c.include_dirs, imacros, force_include,
    &text, &errors,
    &dependency_text);
  unit->preprocessor_output = text;
  unit->preprocessor_errors = errors;
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
  if (request.live_symbols) {
    c.runtime_hdrs = 1;
    globs = c.collect_symbols(globs);
  }
  Map saved_counters = NULL;
  int saved_gensym = 0;
  if (!request.live_symbols) {
    saved_counters = c.names.counters;
    saved_gensym = c.names.gensym_count;
    c.names.counters = c.names.counters.copy();
  }
  cppcompiler.shallow_parse(globs);
  globs = cppcompiler.sym.global_symbols();
  if (request.live_symbols && !request.dump)
    c.install_generated_protocol_symbols(globs);
  if (!request.live_symbols) {
    /* The raw walk below sees the same source again. Do not count names from
       both symbol passes before the full parse. */
    c.names.counters = saved_counters;
    c.names.gensym_count = saved_gensym;
    globs = c.collect_symbols(globs);
  }
  if (request.dump == <snapshot>)
    unit->snapshot_statics =
      cppcompiler.sym.file_statics().copy();
  return globs;
}

/** Opens and tokenizes an isolated source unit without printing diagnostics.
    A failed unit remains open so its diagnostics can be inspected. Close it
    before opening the next unit; Type and header caches are process-global.
*/
int Frontend.start(Frontend frontend, String filename, ParsedUnit *unit) {
  *unit = (ParsedUnit) { 0 };
  unit->context = Context.open_isolated_named("translation unit");
  Type.begin_unit();
  unit->compiler = Compiler.new();
  Compiler compiler = unit->compiler;
  compiler.source_map = frontend.request.source_map;
  compiler.sources = frontend.request.sources;
  compiler.source_facts = frontend.request.source_facts;
  compiler.source_primary = 1;
  if (compiler.source_facts) {
    compiler.source_occurrences = %[];
    compiler.source_definitions = %{};
    compiler.source_declarations = %{};
    compiler.source_texts = %{};
  }
  compiler.diagnostics.set_emitter(NULL, NULL);
  compiler.recovery_depth++;
  try {
    _configure_package(compiler, frontend.request, filename);
    _tokenize_input(frontend, unit, filename);
  }
  catch %(malformed *): return 0;
  return !compiler.error_count();
}

/** Collects symbols and retains preprocessor outputs for adapter inspection. */
int ParsedUnit.collect(ParsedUnit *unit, Frontend frontend) {
  Compiler compiler = unit->compiler;
  try {
    unit->globals = _preprocess_input(frontend, unit);
    if (unit->preprocessor)
      compiler.take_diagnostics(unit->preprocessor);
    if (!frontend.request.no_cpp) header_symbols_begin_generated();
    compiler.sym.seed_var_tags(unit->globals);
  }
  catch %(malformed *): {
    if (unit->preprocessor) {
      compiler.close_child(unit->preprocessor);
      unit->preprocessor = NULL;
    }
    return 0;
  }
  return !compiler.error_count();
}

/** Parses a collected unit, retaining both its AST and unsuccessful reports. */
int ParsedUnit.parse(ParsedUnit *unit) {
  Compiler compiler = unit->compiler;
  if (compiler.error_count()) return 0;
  Diagnostics diagnostics = compiler.diagnostics;
  Array collected = diagnostics.entries;
  diagnostics.entries = %[];
  int ok = 1;
  try unit->ast = unit->compiler.full_parse(unit->globals);
  catch %(malformed *): ok = 0;
  foreach (Var entry, diagnostics.entries) collected.push(entry);
  diagnostics.entries.free();
  diagnostics.entries = collected;
  return ok && !compiler.error_count();
}

/** Runs the source stages. On either result, the caller must close the unit. */
int Frontend.open(Frontend frontend, String filename, ParsedUnit *unit) {
  return frontend.start(filename, unit) && unit.collect(frontend) &&
         unit.parse();
}

/** Releases the unit after its caller has inspected or exported its results. */
void ParsedUnit.close(ParsedUnit *unit) {
  if (!unit->context) return;
  Compiler compiler = unit->compiler;
  if (gensym_cursor < compiler.names.gensym_count)
    gensym_cursor = compiler.names.gensym_count;
  if (unit->preprocessor) compiler.close_child(unit->preprocessor);
  compiler.free_lisp();
  Type.end_unit();
  unit->context.close();
  *unit = (ParsedUnit) { 0 };
}
