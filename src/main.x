/*  main.x -- x2c command dispatch

    Copyright (c) 2025 Gary William Flake

    Initializes the process and drives preprocessing, parsing,
    transformation, and output generation from one typed CLI request.
*/

#pragma once
#include "build.x"
#include "bootstrap.x"
#include "project.x"
#include "frontend.x"
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

static void _preprocessor_errors(String text) {
  Stderr.printf("%s", text);
}

// pipeline utilities

static Map _filter_static_symbols(Map globs, Map statics) {
  Map result = %{};
  foreach (Var (key, value), globs)
    if (!statics.contains(key)) result[key] = value;
  return result;
}

static String _ast_inspection_repr(List node) {
  match (node)
    case %(macrodef (name ?name) *):
      return %"(macrodef <macro ${name.str()}>)";
  return node.repr();
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

// Compile one translation unit through the pipeline.
static void _compile_file(
  Frontend frontend, String filename, String output_dir) {
  CliRequest request = frontend.request;
  ParsedUnit unit;
  _stage_stats(filename, "start");
  int ok = frontend.start(filename, &unit);
  defer unit.close();
  Compiler compiler = unit.compiler;
  if (!ok) {
    _report_diagnostics(compiler);
    exit(1);
  }
  compiler.own_diagnostics();
  if (opts.dump == <tokens>) {
    compiler.dump_tokens();
    exit(0);
  }
  _stage_stats(filename, "tokenize");
  ok = unit.collect(frontend);
  _report_diagnostics(compiler);
  if (!ok) exit(1);
  switch (opts.dump) {
    case <dump-cpp>:
      if (unit.preprocessor_output)
        Stderr.printf("%s", unit.preprocessor_output);
      exit(0);
    case <cpp-tokens>:
      if (unit.preprocessor) unit.preprocessor.dump_tokens();
      exit(0);
    case <dump-csym>:
      if (unit.preprocessor)
        unit.preprocessor.dump_symbol_table(unit.globals);
      exit(0);
  }
  _stage_stats(filename, "symbols");
  if (!unit.parse()) {
    _report_diagnostics(compiler);
    exit(1);
  }
  compiler.recovery_depth = 0;
  List ast = unit.ast;
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
  if (opts.dump == <snapshot>) {
    Map statics = unit.snapshot_statics ? unit.snapshot_statics : %{};
    Map.merge(statics, compiler.sym.file_statics());
    Map snapshot = _filter_static_symbols(
      compiler.sym.global_symbols(), statics);
    if (!symbol_snapshot_write(snapshot, compiler.fn_defs, Stdout))
      exit(1);
    exit(0);
  }
  if (opts.dump == <conform>) {
    printf("(unit %s)\n", filename);
    compiler.dump_conformance(unit.globals);
    return;
  }
  ast = compiler.generate_protocol_adapters(ast);
  if (opts.dump == <hdr-syms>) return;
  _stage_stats(filename, "parse");
  ast = _transform_ast(compiler, ast);
  _stage_stats(filename, "transform");
  if (opts.dump == <dump-code>) {
    ast = compiler.emit(ast);
    puts(compiler.code_pretty_string(ast, NULL));
    exit(0);
  }
  generate_code(compiler, ast, output_dir);
  if (!translation_depfile_write(request, compiler, filename, output_dir))
    exit(1);
  _stage_stats(filename, "generate");
}

static void _preflight_translation(CliRequest c) {
  struct stat info;
  if (!c.inspects()) {
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

/* Translate `inputs` in forked workers, at most `jobs` at a time.
   A worker inherits the loaded snapshot and header artifact rather than
   reading them again, and keeps its slice of the input list to the end, so
   the only shared state is the output directory, where no two units write
   the same file. The parent reports progress as workers finish. Returns the
   number that failed. */
static int _translate_workers(
  Frontend frontend, Array chunks, String output_dir, int total) {
  CliRequest request = frontend.request;
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
          _compile_file(frontend, input, output_dir);
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
  if (!c.out_dir) c.out_dir = %".";
  opts = c;
  _preflight_translation(c);
  if (c.verbose || c.dry_run) {
    fprintf(stderr, "x2c: translate");
    fprintf(stderr, " --out-dir %s", c.out_dir);
    foreach (String input, c.inputs) fprintf(stderr, " %s", input);
    fputc('\n', stderr);
  }
  if (c.dry_run) return 0;
  Frontend frontend = Frontend.new(c);
  frontend.preprocessor_errors = _preprocessor_errors;
  String output_dir = c.out_dir;
  int total = c.inputs.len(), completed = 0;
  unsigned long long gen_bytes = 0;
  /* A dump writes one ordered stream to stdout, and inspection modes report
     per unit, so those stay in this process. The rest may run in parallel. */
  int parallel = c.jobs > 1 && total > 1 &&
                 !c.dump && !c.inspects();
  if (parallel) {
    Array chunks = _translation_chunks(c.inputs, total, c.jobs);
    int failed = _translate_workers(frontend, chunks, output_dir, total);
    chunks.free();
    if (failed) return 1;
    completed = total;
  }
  foreach (String input, parallel ? (List) NULL : c.inputs) {
    if (!c.nested) report_progress(<translate>, completed, total, input);
    _compile_file(frontend, input, output_dir);
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
      !Frontend.write_header_symbols(Stdout))
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

static int _run_build_request(CliRequest c, Array commands) {
  if (!c.dry_run) {
    foreach (String input, c.inputs) {
      if (!input.endswith(%".x")) continue;
      Frontend.load_support(c);
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
  if ((void *) commands != NULL)
    foreach (String entry, state.compile_commands)
      commands.push(target.export(entry));
  if ((void *) commands != NULL && c.command == <run> &&
      !compile_commands_write(c.compile_commands, commands)) {
    state.cleanup(0);
    return 1;
  }
  state.report_success();
  if (c.command == <run>) result = state.run_program();
  state.cleanup(1);
  return result;
}

static int _run_build(CliRequest request) {
  Array commands =
    request.compile_commands && !request.dry_run ? %[] : NULL;
  if (request.inputs) {
    if (request.manifest) {
      fputs(
        "x2c: error: --manifest-path conflicts with explicit inputs\n",
        stderr);
      exit(2);
    }
    int result = _run_build_request(request, commands);
    if (result) return result;
  }
  else {
    ProjectBuild plan = project_plan(request);
    for (ProjectBuild node = plan; node; node = node.next) {
      int result = _run_build_request(node.request, commands);
      if (result) return result;
    }
  }
  if ((void *) commands != NULL && request.command != <run> &&
      !compile_commands_write(request.compile_commands, commands))
    return 1;
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
  Frontend.load_support(runtime_request);
  /* A source-bearing APE is one-shot. A nonzero status returned by either
     build closes build and lock state and flushes stdio before `_Exit`. */
  Context build = Context.open_isolated_named("bootstrap build");
  int result = _run_build_request(runtime_request, NULL);
  if (result) {
    build.close();
    bootstrap_release(payload);
    fflush(NULL);
    _Exit(result);
  }

  CliRequest compiler_request =
    bootstrap_build_request(command, payload, <compiler>);
  compiler_request.label = "compiler";
  result = _run_build_request(compiler_request, NULL);
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
  Frontend.load_support(request);
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
