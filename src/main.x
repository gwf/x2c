/*  main.x -- x2c command dispatch

    Copyright (c) 2025 Gary William Flake

    Initializes the process and drives preprocessing, parsing,
    transformation, and output generation from one typed CLI request.
*/

#pragma once
#include "build.x"
#include "bootstrap.x"
#include "project.x"
#include "toolchain.x"
#pragma private

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "report.x"
#include "collect.x"
#include "cli.x"
#include "compiler.x"
#include "deps.x"
#include "logger.x"
#include "utils.x"
#include "emit.x"
#include "generate.x"
#include "format.x"
#include "snapshot.x"
#include "protocol.x"

// global state

/* The active top-level or nested translation request. Its producing Scope and
   canonical pools outlive every pipeline call that reads these borrowed
   fields. A nested request may instead be produced by its target Context. */
static CliRequest opts = NULL;

// The dumps whose output only the host preprocessor can supply.
static const SymbolSet cpp_dumps =
  %<<dump-cpp cpp-tokens dump-csym snapshot>>;

// request.include_dirs plus the installed defaults
static List include_dirs = NULL;
static Toolchain host_toolchain = NULL;
// logging & diagnostics

/* Only --debug logs. Without it there is no sink, so log_should_log is
   false and nothing is rendered or written. */
static void _configure_logging(int debugging) {
  Logger logger = log_get_global_logger();
  if (!logger) return;
  logger.clear_sinks();
  if (!debugging) return;
  logger.set_min_level(<debug>);
  logger.add_stderr_sink();
}

// Emit collected diagnostics when the compiler has not already logged them.
static void _report_diagnostics(Compiler compiler) {
  report_suspend();
  Diagnostics diag = compiler ? compiler.diagnostics : NULL;
  if (!diag || diag.has_emitter()) return;
  List entries = compiler.diagnostics();
  foreach (Var entry, entries) compiler.print_diagnostic(entry);
}

// pipeline utilities

static Map _filter_static_symbols(Map globs, Map statics) {
  Map result = %{};
  foreach (Var (key, value), globs)
    if (!statics.contains(key)) result[key] = value;
  return result;
}

// pipeline stages

// Report an unusable primary input as a located <driver> diagnostic.
// report_error does not return, so the NULL is only for the reader.
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
  // A zero-byte input is an empty translation unit. gcc and clang both
  // accept one, and x2c already accepted its newline-only and comment-only
  // spellings. It compiles to an empty .c/.h pair.
  return text;
}

static Compiler _tokenize_input(Compiler c, String filename) {
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
  c.tokenize(_read_input_text(c, filename));
  if (opts.dump == <tokens>) {
    c.dump_tokens();
    exit(0);
  }
  c.include_dirs = include_dirs;
  return c;
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

static void _load_translation_support(CliRequest request) {
  Type.initialize();
  header_symbols_initialize();
  if (!request.live_symbols && !request.no_cpp) _load_snapshot_once();
  if (request.no_cpp || request.dump == <hdr-syms> ||
      request.live_symbols || header_symbols_loaded)
    return;
  String artifact = %"${x2c_get_root()}/etc/header-symbols.xlisp";
  header_symbols_open(artifact, snapshot_gensym);
  header_symbols_loaded = 1;
}

// Run the C preprocessor and return collected globals for downstream stages.
static Map _preprocess_input(
  Compiler c, String filename, Map *snapshot_statics) {
  extern File Stderr;
  if (snapshot_statics) *snapshot_statics = NULL;
  if (opts.no_cpp) return NULL;
  String root = x2c_get_root(), int use_snapshot = !opts.live_symbols;
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
  int use_cpp = opts.cpp_symbols || opts.live_symbols ||
                cpp_dumps.contains(opts.dump);
  if (use_snapshot && !use_cpp) {
    Map result = c.collect_symbols(globs);
    return result;
  }
  Compiler cppcompiler = Compiler.new_shared(c);
  cppcompiler.filename = filename;
  String text = NULL, errors = NULL, dependency_text = NULL;
  String runtime = c.prelude ? %"$root/lib/x2c.x" : NULL, imacros = runtime;
  String force_include = NULL;
  int status = host_toolchain.preprocess(
    filename, c.include_dirs, imacros, force_include,
    &text, &errors,
    &dependency_text);
  if (status) {
    if (errors) Stderr.printf("%s", errors);
    List notes = %("stage: preprocess" "status: $status");
    c.report_error(
      <driver>, "failed to run C preprocessor",
      _first_preprocessor_token(c), notes);
  }
  if (errors) Stderr.printf("%s", errors);
  foreach (String dependency, translation_depfile_parse(dependency_text))
    c.add_translation_dependency(dependency);
  if (!text) return NULL;
  if (opts.dump == <dump-cpp>) {
    Stderr.printf("%s", text);
    exit(0);
  }
  cppcompiler.tokenize(text);
  cppcompiler.source_private = -1;
  cppcompiler.collect_protocols = 0;
  if (opts.dump == <cpp-tokens>) {
    cppcompiler.dump_tokens();
    exit(0);
  }
  if (opts.live_symbols) {
    c.runtime_hdrs = 1;
    globs = c.collect_symbols(globs);
  }
  Map saved_counters = NULL;
  int saved_gensym = 0;
  if (!opts.live_symbols) {
    saved_counters = c.names.counters;
    saved_gensym = c.names.gensym_count;
    c.names.counters = c.names.counters.copy();
  }
  cppcompiler.shallow_parse(globs);
  globs = cppcompiler.sym.global_symbols();
  if (opts.live_symbols && !opts.dump)
    c.install_generated_protocol_symbols(globs);
  if (!opts.live_symbols) {
    /* The raw walk below sees the same source again. Do not count names from
       both symbol passes before the full parse. */
    c.names.counters = saved_counters;
    c.names.gensym_count = saved_gensym;
    globs = c.collect_symbols(globs);
  }
  if (opts.dump == <snapshot> && snapshot_statics)
    *snapshot_statics =
      cppcompiler.sym.file_statics().copy();
  if (opts.dump == <dump-csym>) {
    cppcompiler.dump_symbol_table(globs);
    exit(0);
  }
  cppcompiler.free_lisp();
  return globs;
}

static String _ast_inspection_repr(List node) {
  match (node)
    case %(macrodef (name ?name) *):
      return %"(macrodef <macro ${name.str()}>)";
  return node.repr();
}

static List _parse_input(Compiler compiler, Map globs) {
  List ast = compiler.full_parse(globs);
  if (compiler.error_count()) {
    _report_diagnostics(compiler);
    exit(1);
  }
  switch (opts.dump) {
    case <dump-cache>:
      compiler.dump_cache();
      exit(0);
    case <symbols>:
      compiler.dump_symbol_table(compiler.sym.current_symbols());
      exit(0);
    case <dump-ast>:
      foreach (List node, ast) printf("\n%s\n", _ast_inspection_repr(node));
      exit(0);
  }
  return ast;
}

static List _transform_ast(Compiler compiler, List ast) {
  List Compiler.transform(Compiler compiler, List ast);
  ast = compiler.transform(ast);
  if (compiler.error_count()) {
    _report_diagnostics(compiler);
    exit(1);
  }
  if (opts.dump == <transforms>) {
    foreach (List node, ast) printf("\n%s\n", _ast_inspection_repr(node));
    exit(0);
  }
  return ast;
}

// public entry point

static void _stage_stats(String filename, const char *stage) {
  if (!getenv("X2C_STAGE_STATS")) return;
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  unsigned long now_us =
    (unsigned long) ts.tv_sec * 1000000ul + ts.tv_nsec / 1000;
  ScopeStats s = Scope.stats();
  fprintf(
    stderr, "stage-stats,%s,%s,%zu,%zu,%zu,%lu\n", filename, stage,
    s.live_allocations, s.allocation_calls, s.requested_bytes,
    now_us);
}

/* A unit compiles in package mode only when it is one of that package's own
   files below `<root>/<name>/src/` or the single-file `<root>/<name>/<name>.x`
   under a registered --package-dir root. The comparison uses the canonical
   path, so symlinked or relative spellings of one file agree; a test or
   example elsewhere in the package directory is a consumer and reaches the
   package through `import`. */
static void _configure_package(Compiler compiler, String filename) {
  char buffer[PATH_MAX];
  compiler.package_dirs = opts.package_dirs;
  if (!opts.package_dirs || !realpath(filename, buffer)) return;
  String source = %"$buffer";
  foreach (String directory, opts.package_dirs) {
    if (!realpath(directory, buffer)) continue;
    String root = %"$buffer/";
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

// Compile one translation unit through the pipeline.
static void _compile_file(
  CliRequest request, String filename, String output_dir) {
  Compiler compiler = Compiler.new();
  _configure_package(compiler, filename);
  _stage_stats(filename, "start");
  _tokenize_input(compiler, filename);
  _stage_stats(filename, "tokenize");
  Map snapshot_statics = NULL;
  Map globs = _preprocess_input(compiler, filename, &snapshot_statics);
  if (opts.dump == <hdr-syms>) header_symbols_begin_generated();
  compiler.sym.seed_var_tags(globs);
  _stage_stats(filename, "symbols");
  List ast = _parse_input(compiler, globs);
  if (opts.dump == <snapshot>) {
    Map statics = snapshot_statics
      ? snapshot_statics : %{};
    Map.merge(statics, compiler.sym.file_statics());
    Map snapshot = _filter_static_symbols(
      compiler.sym.global_symbols(), statics);
    if (!symbol_snapshot_write(snapshot, compiler.fn_defs, Stdout))
      exit(1);
    exit(0);
  }
  if (opts.dump == <conform>) {
    printf("(unit %s)\n", filename);
    compiler.dump_conformance(globs);
    gensym_cursor = compiler.names.gensym_count;
    compiler.free_lisp();
    return;
  }
  ast = compiler.generate_protocol_adapters(ast);
  if (opts.dump == <hdr-syms>) {
    gensym_cursor = compiler.names.gensym_count;
    compiler.free_lisp();
    return;
  }
  _stage_stats(filename, "parse");
  ast = _transform_ast(compiler, ast);
  _stage_stats(filename, "transform");
  if (opts.dump == <dump-code>) {
    ast = compiler.emit(ast);
    puts(code_pretty_string(ast));
    exit(0);
  }
  generate_code(compiler, ast, output_dir);
  if (!translation_depfile_write(request, compiler, filename, output_dir))
    exit(1);
  _stage_stats(filename, "generate");
  gensym_cursor = compiler.names.gensym_count;
  compiler.free_lisp();
}

static void _preflight_translation(CliRequest c) {
  struct stat info;
  if (!c.inspects()) {
    if (!c.out_dir) {
      fprintf(stderr, "x2c: error: translate requires '--out-dir <dir>'\n");
      exit(2);
    }
    if (stat(c.out_dir, &info)) {
      fprintf(
        stderr, "x2c: error: output directory does not exist: %s\n",
        c.out_dir);
      exit(2);
    }
    if (!S_ISDIR(info.st_mode)) {
      fprintf(
        stderr, "x2c: error: output is not a directory: %s\n",
        c.out_dir);
      exit(2);
    }
    if (access(c.out_dir, W_OK | X_OK)) {
      fprintf(
        stderr, "x2c: error: output directory is not writable: %s\n",
        c.out_dir);
      exit(2);
    }
  }
  List stems = NULL, stem_inputs = NULL;
  foreach (String input, c.inputs) {
    if (!input) {
      fputs("x2c: error: input path is empty\n", stderr);
      exit(2);
    }
    if (stat(input, &info)) {
      fprintf(stderr, "x2c: error: input does not exist: %s\n", input);
      if (strpbrk(input, "*?["))
        fprintf(stderr, "note: x2c does not expand wildcard operands\n");
      exit(2);
    }
    if (S_ISDIR(info.st_mode)) {
      fprintf(stderr, "x2c: error: input is a directory: %s\n", input);
      fputs(
        "note: pass source files, use a shell wildcard, or define a ",
        stderr);
      fputs("manifest target\n", stderr);
      exit(2);
    }
    if (!S_ISREG(info.st_mode)) {
      fprintf(
        stderr, "x2c: error: input is not a regular file: %s\n", input);
      exit(2);
    }
    if (!input.endswith(%".x")) {
      fprintf(
        stderr, "x2c: error: translation input is not an .x file: %s\n",
        input);
      exit(2);
    }
    String stem = x2c_path_stem(input);
    if (!c.inspects()) {
      List prior_stem = stems, prior_input = stem_inputs;
      while (prior_stem) {
        if (prior_stem.car().string() == stem) {
          fprintf(
            stderr,
            "x2c: error: inputs produce the same output stem '%s'\n", stem);
          fprintf(stderr, "  first input: %s\n", prior_input.car().string());
          fprintf(stderr, "  other input: %s\n", input);
          fprintf(stderr, "  output: %s/%s.c\n", c.out_dir, stem);
          exit(2);
        }
        prior_stem = prior_stem.cdr();
        prior_input = prior_input.cdr();
      }
    }
    stems = cons(stem, stems);
    stem_inputs = cons(input, stem_inputs);
  }
}

static void _apply_cli_request(CliRequest request) {
  opts = request;
  include_dirs = request.include_dirs.append(x2c_default_include_dirs());
  host_toolchain = toolchain_new(
    request.cc, request.ar, request.cpp_args, request.cc_args,
    request.ld_args, request.verbose, request.dry_run);
}

// Translate one unit. Each runs inside an isolated Context: its transient
// allocations, Strings, cons cells, Error state, and Match cache are
// released together, so batch peak memory stays near single-file peak. Outputs
// are on disk; nothing exports except cached header rows.
static void _translate_unit(
  CliRequest request, String input, String output_dir) {
  Context unit = Context.open_isolated_named("translation unit");
  defer unit.close();
  Type.begin_unit();
  defer Type.end_unit();
  _compile_file(request, input, output_dir);
}

/* Translate `inputs` in forked workers, at most `jobs` at a time.
   A worker inherits the loaded snapshot and header artifact rather than
   reading them again, and keeps its slice of the input list to the end, so
   the only shared state is the output directory, where no two units write
   the same file. The parent reports progress as workers finish. Returns the
   number that failed. */
static int _translate_workers(
  CliRequest request, Array chunks, String output_dir, int total) {
  int jobs = request.jobs, slices = chunks.len();
  if (jobs > slices) jobs = slices;
  // One entry per live worker: its pid and how many units it carries, so a
  // finished worker counts its own slice rather than the oldest one.
  long *running = Scope.calloc(jobs, sizeof(long));
  int *carried = Scope.calloc(jobs, sizeof(int));
  int running_count = 0, failed = 0, done = 0, next = 0;
  while (next < slices || running_count) {
    while (next < slices && running_count < jobs) {
      List slice = chunks[next];
      next++;
      long pid = worker_fork();
      if (!pid) {
        foreach (String input, slice)
          _translate_unit(request, input, output_dir);
        worker_exit(0);
      }
      if (pid < 0) {
        report_line(<error>, %"could not start a translation worker");
        failed++;
        continue;
      }
      carried[running_count] = slice.len();
      running[running_count++] = pid;
    }
    if (!running_count) continue;
    if (worker_wait(running[0])) failed++;
    done += carried[0];
    running_count--;
    if (running_count) {
      memmove(running, running + 1, running_count * sizeof(long));
      memmove(carried, carried + 1, running_count * sizeof(int));
    }
    if (!request.nested) report_progress(<translate>, done, total, NULL);
  }
  Scope.free(carried);
  Scope.free(running);
  return failed;
}

/* One slice per worker. Fewer, larger slices measured better than more,
   smaller ones. The fork and the copy-on-write faults behind it cost more
   than the imbalance a long unit at the tail of a slice can cause. */
static Array _translation_chunks(List inputs, int total, int jobs) {
  int slices = jobs;
  if (slices > total) slices = total;
  if (slices < 1) slices = 1;
  int size = (total + slices - 1) / slices, Array chunks = %[];
  List cur = inputs;
  while (cur) {
    Array slice = %[];
    for (int n = 0; n < size && cur; n++, cur = cur.cdr())
      slice.push(cur.car());
    chunks.push(slice.list_free());
  }
  return chunks;
}

static int _run_translation(CliRequest c) {
  unsigned long started_at = report_now_us();
  _apply_cli_request(c);
  _preflight_translation(c);
  if (c.verbose || c.dry_run) {
    fprintf(stderr, "x2c: translate");
    if (c.out_dir) fprintf(stderr, " --out-dir %s", c.out_dir);
    foreach (String input, c.inputs) fprintf(stderr, " %s", input);
    fputc('\n', stderr);
  }
  if (c.dry_run) return 0;
  _load_translation_support(c);
  String output_dir = c.out_dir ? c.out_dir : %".";
  int total = c.inputs.len(), completed = 0;
  unsigned long long gen_bytes = 0;
  /* A dump writes one ordered stream to stdout, and inspection modes report
     per unit, so those stay in this process. The rest may run in parallel. */
  int parallel = c.jobs > 1 && total > 1 &&
                 !c.dump && !c.inspects();
  if (parallel) {
    Array chunks = _translation_chunks(c.inputs, total, c.jobs);
    int failed = _translate_workers(c, chunks, output_dir, total);
    chunks.free();
    if (failed) return 1;
    completed = total;
  }
  foreach (String input, parallel ? (List) NULL : c.inputs) {
    if (!c.nested) report_progress(<translate>, completed, total, input);
    _translate_unit(c, input, output_dir);
    completed++;
    if (!c.nested) report_progress(<translate>, completed, total, input);
  }
  if (!c.nested)
    foreach (String input, c.inputs) {
      String stem = x2c_path_stem(input);
      gen_bytes += report_file_bytes(%"$output_dir/$stem.c");
      gen_bytes += report_file_bytes(%"$output_dir/$stem.h");
    }
  if (opts.dump == <hdr-syms> &&
      !header_symbols_write(Stdout, snapshot_gensym))
    return 1;
  if (!c.nested && !c.inspects()) {
    String duration = report_duration(report_now_us() - started_at);
    String noun = total == 1 ? %"file" : %"files";
    report_line(
      <success>,
      %"Translated $total x2c $noun to $output_dir in $duration");
    String size = report_size(gen_bytes);
    String c_noun = total == 1 ? %"C file" : %"C files";
    String h_noun = total == 1 ? %"header" : %"headers";
    report_line(
      <muted>,
      %"  Generated $total $c_noun and $total $h_noun ($size)");
  }
  return 0;
}

static CliRequest _build_translation_request(
  CliRequest source, String input, String output_dir) {
  CliRequest request = Scope.malloc(sizeof(struct CliRequest));
  *request = *source;
  request.command = <translate>;
  request.inputs = cons(input, NULL);
  request.run_args = NULL;
  request.out_dir = output_dir;
  request.dep_file = NULL;
  request.dep_target = NULL;
  request.no_deps = 0;
  request.no_phony_deps = 0;
  request.nested = 1;
  return request;
}

static int _run_build_request(CliRequest c) {
  if (!c.dry_run) {
    foreach (String input, c.inputs) {
      if (!input.endswith(%".x")) continue;
      _load_translation_support(c);
      break;
    }
  }
  /* A target has its own build graph and native-action scratch. Isolate
     its Scope allocations and canonical values so a manifest dependency is
     reclaimed before the next target starts. */
  Context target = Context.open_isolated_named("build target");
  defer target.close();
  Build state = c.prepare();
  c.cc = target.export(c.cc);
  c.ar = target.export(c.ar);
  foreach (String input, c.inputs) {
    if (!input.endswith(%".x")) continue;
    state.begin_translation(input);
    String directory = state.generated_dir(input);
    if (state.translation_current(input, directory)) {
      state.add_generated(input, directory);
      state.end_translation(input, 1);
      continue;
    }
    CliRequest translation =
      _build_translation_request(c, input, directory);
    if (!c.dry_run && _run_translation(translation)) {
      state.cleanup(0);
      return 1;
    }
    if (c.dry_run)
      fprintf(stderr, "x2c: translate --out-dir %s %s\n", directory, input);
    if (!c.dry_run) state.record_translation(input, directory);
    state.add_generated(input, directory);
    state.end_translation(input, 0);
  }
  int result = state.finish();
  if (result) {
    state.cleanup(0);
    return result;
  }
  state.report_success();
  if (c.command == <run>) result = state.run_program();
  state.cleanup(1);
  return result;
}

static int _run_build(CliRequest request) {
  if (request.inputs) {
    if (request.manifest) {
      fputs(
        "x2c: error: --manifest-path conflicts with explicit inputs\n",
        stderr);
      exit(2);
    }
    return _run_build_request(request);
  }
  ProjectBuild plan = project_plan(request);
  for (ProjectBuild node = plan; node; node = node.next) {
    int result = _run_build_request(node.request);
    if (result) return result;
  }
  return 0;
}

static int _run_bootstrap(CliRequest command) {
  Bootstrap payload = bootstrap_materialize(command);
  if (payload.complete) {
    printf(
      "x2c: native compiler is already installed at %s/bin/x2c\n",
      payload.prefix);
    bootstrap_release(payload);
    return 0;
  }
  x2c_set_root(payload.prefix);
  _configure_logging(command.debugging);
  CliRequest runtime_request =
    bootstrap_build_request(command, payload, <runtime>);
  runtime_request.label = "runtime";
  _load_translation_support(runtime_request);
  /* A source-bearing APE is one-shot. A nonzero status returned by either
     build closes build and lock state and flushes stdio before `_Exit`. */
  Context build = Context.open_isolated_named("bootstrap build");
  int result = _run_build_request(runtime_request);
  if (result) {
    build.close();
    bootstrap_release(payload);
    fflush(NULL);
    _Exit(result);
  }

  CliRequest compiler_request =
    bootstrap_build_request(command, payload, <compiler>);
  compiler_request.label = "compiler";
  result = _run_build_request(compiler_request);
  if (result) {
    build.close();
    bootstrap_release(payload);
    fflush(NULL);
    _Exit(result);
  }
  bootstrap_record_install(payload, compiler_request.cc, compiler_request.ar);
  printf("x2c: installed native compiler at %s/bin/x2c\n", payload.prefix);
  build.close();
  bootstrap_release(payload);
  fflush(NULL);
  _Exit(0);
  return 0;
}

/** Initializes x2c and dispatches one command from `argv`.
    `argv[0]` locates the installation. The process status is zero for a
    successful translation, build, or bootstrap, one for compiler or tool
    failure, and the executed program's status for `run`. Help and version exit
    with zero, while invalid CLI and preflight input exit with status two.
*/
int main(int argc, char **argv) {
  x2c_initialize_environment(argv[0]);
  CliRequest request = cli_parse(argc, argv);
  report_configure(
    request.quiet, request.plain, request.color_mode,
    request.verbose || request.debugging,
    request.dry_run, request.inspects());
  if (request.command == <bootstrap>) return _run_bootstrap(request);
  _configure_logging(request.debugging);
  /* Initialize process caches above the command Context so its cleanup cannot
     invalidate their canonical values. */
  _load_translation_support(request);
  /* Reclaim command-owned Scope allocations and canonical values. */
  Context command = Context.open_isolated_named("compiler command");
  int result = request.command == <translate>
    ? _run_translation(request)
    : _run_build(request);
  command.close();
#ifdef __COSMOPOLITAN__
  fflush(NULL);
  _Exit(result);
#endif
  return result;
}
