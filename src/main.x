/*  main.x -- x2c command dispatch

    Copyright (c) 2025 Gary William Flake

    Initializes the process and drives preprocessing, parsing,
    transformation, and output generation from one typed CLI request.
*/

#pragma once
#pragma private
#include "build.x"
#include "project.x"
#include "frontend.x"
#include "meta-project.x"
#include "editor.x"
#include "install.x"
#include "script.x"
#include "toolchain.x"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
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
#include "protocol.x"

$(import "main-reports.xmacro")

// translating a unit

/* Compile one translation unit through the pipeline. An inspection prints
   its stage and returns, so every input is inspected and a failing later
   input still fails the command. */
static void _translate_unit(
  Frontend frontend, String filename, String output_dir) {
  CliRequest request = frontend.request;
  Symbol dump = request.dump;
  ParsedUnit unit;
  int started = frontend.start(filename, unit);
  defer unit.close();
  Compiler c = unit.compiler;
  if (!started) _fail(c);
  c.own_diagnostics();
  if (dump == <tokens>) {
    c.dump_tokens();
    return;
  }
  int collected = unit.collect(frontend);
  _report_diagnostics(c);
  if (!collected) exit(1);
  if (_inspect_collected(unit, dump)) return;
  if (!unit.parse()) _fail(c);
  c.recovery_depth = 0;
  if (_inspect_parsed(unit, filename, dump)) return;
  List ast = _transform_ast(c, c.generate_protocol_adapters(unit.ast));
  if (_inspect_transformed(c, ast, dump)) return;
  generate_code(c, ast, output_dir);
  if (!translation_depfile_write(request, c, filename, output_dir)) exit(1);
  // A unit that reaches here has no errors, so any diagnostic is a warning.
  if (request.fatal_warnings && c.diagnostics()) exit(1);
}

static void _fail(Compiler c) {
  _report_diagnostics(c);
  exit(1);
}

// Emit collected diagnostics when the compiler has not already logged them.
static void _report_diagnostics(Compiler c) {
  if (c.diagnostics.printer) return;
  List entries = c.diagnostics();
  if (entries) report_suspend();
  foreach (Var entry, entries) c.print_diagnostic(entry);
}

static List _transform_ast(Compiler c, List ast) {
  ast = c.transform(ast);
  if (c.error_count()) _fail(c);
  return ast;
}

/* Each inspection prints one stage's view of the unit and returns 1 when
   `dump` selects it. A unit collected with `--no-cpp` has no preprocessor
   output to print. */
static int _inspect_collected(ParsedUnit &unit, Symbol dump) {
  Compiler cpp = unit.preprocessor;
  String text = unit.preprocessor_output;
  switch (dump) {
    case <dump-cpp>:   if (text) printf("%s", text); break;
    case <cpp-tokens>: if (cpp) cpp.dump_tokens(); break;
    case <dump-csym>:  if (cpp) cpp.dump_symbol_table(unit.globals); break;
    default:           return 0;
  }
  return 1;
}

static int _inspect_parsed(ParsedUnit &unit, String filename, Symbol dump) {
  Compiler c = unit.compiler;
  switch (dump) {
    case <dump-cache>: c.dump_cache(); break;
    case <symbols>:    c.dump_symbol_table(c.sym.current_symbols()); break;
    case <dump-ast>:   _print_ast(unit.ast); break;
    case <conform>:    _print_conformance(c, filename, unit.globals); break;
    default:           return 0;
  }
  return 1;
}

static int _inspect_transformed(Compiler c, List ast, Symbol dump) {
  switch (dump) {
    case <transforms>: _print_ast(ast); break;
    case <dump-defs>:  c.dump_definitions(ast); break;
    case <dump-code>:
      puts(c.code_pretty_string(c.emit(ast, NULL), NULL)); break;
    default:           return 0;
  }
  return 1;
}

static void _print_conformance(Compiler c, String filename, Map globals) {
  printf("(unit %s)\n", filename);
  c.dump_conformance(globals);
}

static void _print_ast(List ast) {
  foreach (List node, ast) printf("\n%s\n", _node_repr(node));
}

static String _node_repr(List node) {
  match (node)
    case %(macrodef (name ?name) *): return %"(macrodef <macro $name>)";
  return node.repr();
}

// translation requests

/* One request's units share a frontend. `unit_dirs` maps each input to its
   own output directory on the build path, where `build` reports progress;
   `x2c translate` has neither. */
typedef struct Translation {
  CliRequest request, Frontend frontend, Map unit_dirs, Build build;
  int total;
} Translation;

static int _run_translation(CliRequest request, Map unit_dirs, Build build) {
  unsigned long started_at = report_now_us();
  if (!request.out_dir) request.out_dir = ".";
  Translation t = {
    .request = request, .unit_dirs = unit_dirs, .build = build,
    .total = request.inputs.len()};
  t.preflight();
  if (request.verbose || request.dry_run) _print_command(request);
  if (request.dry_run) return 0;
  t.frontend = Frontend.new(request);
  t.frontend.preprocessor_errors = _preprocessor_errors;
  /* Each worker inherits what this process has already built, so the
     parent builds it once for all of them. */
  if (!t.frontend.preload_macro_libraries()) return 1;
  t.frontend.prepare_meta(request.inputs);
  /* A dump writes one ordered stream to stdout, and inspection modes report
     per unit, so those stay in this process. The rest may run in parallel. */
  if (request.jobs > 1 && t.total > 1 && !request.inspects()) {
    if (t.translate_parallel()) return 1;
  }
  else t.translate_serial();
  if (!build && !request.inspects()) t.report(started_at);
  return 0;
}

/* Each input must be a regular `.x` file. Units that write to the shared
   `--out-dir` must not share an output stem; inspection writes nothing. */
static void Translation.preflight(Translation &t) {
  CliRequest request = t.request;
  if (!request.inspects()) _check_out_dir(request.out_dir);
  int shared = !request.inspects() && !t.unit_dirs, Map stems = {};
  foreach (String input, request.inputs) {
    build_check_input(input);
    if (!is_source_file(input))
      $report.main.input_not_x(input);
    String stem = Path.stem(input);
    if (shared && stem in stems)
      _stem_collision(stem, stems[stem], input, request.out_dir);
    stems[stem] = input;
  }
}

static void _check_out_dir(String out_dir) {
  if (!Path.exists(out_dir))
    $report.main.directory_missing(out_dir);
  if (!Path.is_dir(out_dir))
    $report.main.directory_not_dir(out_dir);
  if (access(out_dir, W_OK | X_OK))
    $report.main.directory_unwritable(out_dir);
}

static void _stem_collision(
  String stem, String first, String other, String out_dir) {
  $report.main.stem_collision(stem, first, other, out_dir);
  exit(2);
}

static void _print_command(CliRequest request) {
  fprintf(stderr, "x2c: translate");
  fprintf(stderr, " --out-dir %s", request.out_dir);
  foreach (String input, request.inputs) fprintf(stderr, " %s", input);
  fputc('\n', stderr);
}

static void _preprocessor_errors(String text) {
  Stderr.printf("%s", text);
}

static void Translation.translate_serial(Translation &t) {
  int done = 0;
  foreach (String input, t.request.inputs) {
    if (t.build) t.build.begin_translation(input);
    else report_progress(<translate>, done, t.total, input);
    t.translate(input);
    done++;
    if (t.build) t.build.end_translation(input, 0);
    else report_progress(<translate>, done, t.total, input);
  }
}

static void Translation.translate(Translation &t, String input) =>
  _translate_unit(t.frontend, input, t.output_dir(input));

/* Where one unit's generated C, header, and depfile are written. A build
   gives each unit its own directory so units sharing an output stem cannot
   collide; `x2c translate` writes them all to the shared `--out-dir`. */
static String Translation.output_dir(Translation &t, String input) {
  if (!t.unit_dirs) return t.request.out_dir;
  return t.unit_dirs[input];
}

static void Translation.report(Translation &t, unsigned long started_at) {
  String out_dir = t.request.out_dir;
  unsigned long long bytes = 0;
  foreach (String input, t.request.inputs) {
    String stem = Path.stem(input);
    bytes += report_file_bytes(%"$out_dir/$stem.c");
    bytes += report_file_bytes(%"$out_dir/$stem.h");
  }
  String duration = report_duration(report_now_us() - started_at);
  int n = t.total;
  String noun = n == 1 ? "file" : "files";
  $report.main.translated(n, noun, out_dir, duration);
  report_generated(n, bytes);
}

// translation workers

/* The live workers of one parallel translation. Each live slot keeps its
   worker's pid, the index of the slice it carries, and the file that
   captures its standard error. `output` holds each ended slice's captured
   bytes until every earlier slice has shown its own. */
typedef struct Workers {
  Translation *t, Array slices, long *pids, int *carried, File *captures;
  Block *output;
  int live, started, shown, failed, done;
} Workers;

/* The running parallel translation. A stop signal reaches its live
   workers. A worker has none of its own. */
static Workers _workers;

/* Translate the inputs in forked workers. Returns the number of slices
   that failed. */
static int Translation.translate_parallel(Translation &t) {
  t.preload_modules();
  int count = t.unit_dirs ? t.total : t.request.jobs;
  Array slices = _slices(t.request.inputs, t.total, count);
  int failed = t.run_workers(slices);
  slices.free();
  return failed;
}

/* Loads the native modules of the packages the inputs import before the
   workers fork, so each worker inherits them. A worker loads a module this
   misses itself when its import needs it. */
static void Translation.preload_modules(Translation &t) {
  List roots = t.request.package_roots();
  if (!roots) return;
  foreach (String name, t.package_names(roots).keys()) {
    String root = NULL;
    if (!package_entry(t.request.sources, roots, name, root) ||
        Compiler.links_extension(name)) continue;
    String module = %"$root/builds/$name.module";
    if (Path.is_file(module)) Compiler.preload_native_module(module);
  }
}

/* The packages a unit's own imports name, and those its previous depfile
   records, which include imports reached through a header. */
static Map Translation.package_names(Translation &t, List roots) {
  Map names = {};
  foreach (String input, t.request.inputs) {
    foreach (String name, _imported_packages(input)) names[name] = 1;
    String depfile = %"${t.output_dir(input)}/${Path.stem(input)}.d";
    String text = NULL;
    try text = Path.read_text(depfile);
    catch %((!or not-found io-fail) *): continue;
    foreach (String dependency, translation_depfile_parse(text)) {
      String package = package_directory(roots, dependency);
      if (package) names[Path.basename(package)] = 1;
    }
  }
  return names;
}

/* The packages the top-level `import` declarations of the file at `path`
   name. A token scan suffices: an import is legal only at file scope. */
static List _imported_packages(String path) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return NULL;
  Tokenizer tokens = Tokenizer.new(text, <x2c>);
  tokens.scan();
  Array names = [], int depth = 0;
  for (Token token = tokens.next(); token.type != <eof>;
       token = tokens.next()) {
    if (token.text == "{") depth++;
    else if (token.text == "}") depth--;
    else if (!depth && token.text == "import") {
      token = tokens.next();
      if (token.type == <lit-char*>) names.push(token.text[1:-1]);
    }
  }
  return names.list_free();
}

/* One slice per worker. Fewer, larger slices measured better than more,
   smaller ones. The fork and the copy-on-write faults behind it cost more
   than the imbalance a long unit at the tail of a slice can cause.

   A build asks for one slice per unit. Each of its units then translates in
   a worker that has translated nothing else, so a unit records the headers
   its own parse reads and none that an earlier unit in the same worker put
   in the process cache. Build reuse is decided from those recorded
   prerequisites, so they must not depend on how units were grouped. */
static Array _slices(List inputs, int total, int count) {
  if (count > total) count = total;
  if (count < 1) count = 1;
  int size = (total + count - 1) / count, Array slices = [];
  List at = inputs;
  while (at) {
    Array slice = [];
    for (int n = 0; n < size && at; n++, at = at.cdr()) slice.push(at.car());
    slices.push(slice.list_free());
  }
  return slices;
}

/* Runs one worker per slice, at most `jobs` at a time. A worker inherits the
   process collection cache and keeps its slice of the input list to the
   end, so the only state workers share is the output directory, where no
   two units write the same file. The parent reports progress as workers
   finish and prints their standard error in input order. */
static int Translation.run_workers(Translation &t, Array slices) {
  int jobs = t.request.jobs, count = slices.len();
  if (jobs > count) jobs = count;
  if (t.request.verbose)
    $report.main.workers_started(jobs, t.total);
  _workers = (Workers) {
    .t = &t, .slices = slices, .pids = Scope.calloc(jobs, sizeof(long)),
    .carried = Scope.calloc(jobs, sizeof(int)),
    .captures = Scope.calloc(jobs, sizeof(File)),
    .output = Scope.calloc(count, sizeof(Block))};
  struct sigaction term, interrupt;
  _forward_stop_signal(SIGTERM, &term);
  _forward_stop_signal(SIGINT, &interrupt);
  while (_workers.started < count || _workers.live) {
    if (_workers.started < count && _workers.live < jobs) _workers.start();
    else _workers.reap();
    _workers.show();
  }
  sigaction(SIGTERM, &term, NULL);
  sigaction(SIGINT, &interrupt, NULL);
  Scope.free(_workers.output);
  Scope.free(_workers.captures);
  Scope.free(_workers.carried);
  Scope.free(_workers.pids);
  return _workers.failed;
}

/* Starts the next slice. A slice that cannot start counts as one failure.
   Stop signals wait until the parent records the worker, so a forwarded
   stop reaches every worker. */
static void Workers.start(Workers &w) {
  int index = w.started++;
  List slice = w.slices[index];
  if (w.t.build) w.t.build.begin_translation(slice.car());
  File capture = tmpfile();
  sigset_t unblocked = _block_stop_signals();
  long pid = capture ? worker_fork() : -1;
  if (!pid) {
    w.live = 0;
    sigprocmask(SIG_SETMASK, &unblocked, NULL);
    dup2(capture.fileno(), STDERR_FILENO);
    (*w.t).work(slice);
  }
  if (pid > 0) {
    w.carried[w.live] = index;
    w.captures[w.live] = capture;
    w.pids[w.live] = pid;
    w.live++;
  }
  sigprocmask(SIG_SETMASK, &unblocked, NULL);
  if (pid > 0) return;
  if (capture) capture.close();
  report_line(<error>, "could not start a translation worker");
  w.failed++;
}

// A forked worker exits after its slice, or at the first unit that fails.
static void Translation.work(Translation &t, List slice) {
  foreach (String input, slice) t.translate(input);
  Compiler.stop_meta_helper();
  worker_exit(0);
}

/* Keeps the ended worker's captured bytes for `show`. The last live worker
   moves into the slot of the one that finished. */
static void Workers.reap(Workers &w) {
  int status, slot = worker_wait_any(w.pids, w.live, status);
  if (status) w.failed++;
  int index = w.carried[slot];
  List slice = w.slices[index];
  File capture = w.captures[slot];
  defer capture.close();
  capture.rewind();
  Block output = Block.new(sizeof(char));
  capture.read_into(output);
  w.output[index] = output;
  if (w.t.build && !status) w.t.build.end_translation(slice.car(), 0);
  w.done += slice.len();
  sigset_t unblocked = _block_stop_signals();
  w.live--;
  w.pids[slot] = w.pids[w.live];
  w.carried[slot] = w.carried[w.live];
  w.captures[slot] = w.captures[w.live];
  sigprocmask(SIG_SETMASK, &unblocked, NULL);
  if (!w.t.build) report_progress(<translate>, w.done, w.t.total, NULL);
}

/* Prints each ended slice's captured standard error once every earlier
   slice has printed its own. A slice has ended when it has started and no
   live worker carries it. */
static void Workers.show(Workers &w) {
  while (w.shown < w.started && !w.carries(w.shown)) {
    Block output = w.output[w.shown++];
    if (output == NULL) continue;
    defer output.free();
    if (!output.length) continue;
    report_suspend();
    File.write_all(stderr, output.bytes, output.length);
  }
}

static int Workers.carries(Workers &w, int index) {
  for (int slot = 0; slot < w.live; slot++)
    if (w.carried[slot] == index) return 1;
  return 0;
}

// stop signals

/* Sends TERM or INT on to each live worker, then stops this process as the
   signal's default action does. */
static void _forward_stop(int number) {
  for (int slot = 0; slot < _workers.live; slot++)
    kill((pid_t) _workers.pids[slot], number);
  signal(number, SIG_DFL);
  kill(getpid(), number);
}

/* Routes `number` through `_forward_stop` unless this process ignores it.
   `previous` receives the action to restore. */
static void _forward_stop_signal(int number, struct sigaction *previous) {
  struct sigaction forward = {.sa_handler = _forward_stop};
  sigaction(number, NULL, previous);
  if (previous->sa_handler != SIG_IGN) sigaction(number, &forward, NULL);
}

/* Blocks TERM and INT and returns the mask that unblocks them again. */
static sigset_t _block_stop_signals(void) {
  sigset_t stops, previous;
  sigemptyset(&stops);
  sigaddset(&stops, SIGTERM);
  sigaddset(&stops, SIGINT);
  sigprocmask(SIG_BLOCK, &stops, &previous);
  return previous;
}

// builds

/* A build runs its explicit inputs as one target, or each target of its
   project manifest. Every target adds its compile commands to one
   database. */
static int _run_build(CliRequest request) {
  Array commands = request.compile_commands && !request.dry_run ? [] : NULL;
  int status = request.inputs
    ? _build_inputs(request, commands) : _build_manifest(request, commands);
  if (status || commands == NULL || request.command == <run>) return status;
  return !compile_commands_write(request.compile_commands, commands);
}

static int _build_inputs(CliRequest request, Array commands) {
  /* Manifest options have no meaning without a manifest. The build fails
     before it builds something the command did not describe. */
  if (request.manifest)
    driver_error("--manifest-path conflicts with explicit inputs");
  if (request.target)
    driver_error("--target conflicts with explicit inputs");
  if (request.profile)
    driver_error("--profile conflicts with explicit inputs");
  return _build_target(request, commands);
}

static int _build_manifest(CliRequest request, Array commands) {
  if (request.compile_only)
    driver_error("--compile-only needs input operands, not a manifest");
  for (ProjectBuild node = project_plan(request); node; node = node.next) {
    int status = _build_target(node.request, commands);
    if (status) return status;
  }
  return 0;
}

static int _build_target(CliRequest request, Array commands) {
  /* A target has its own build graph and native-action scratch. Isolate
     its Scope allocations and canonical values so a manifest dependency is
     reclaimed before the next target starts. */
  Context target = $auto(Context.open_isolated_named("build target"));
  defer macro_library_reset();
  Build b = request.prepare();
  request.cc = target.export(request.cc);
  request.meta_cc = target.export(request.meta_cc);
  request.ar = target.export(request.ar);
  int status = _translate_target(request, b);
  if (!status) status = b.finish();
  if (!status) status = _add_commands(request, b, target, commands);
  if (status) {
    b.cleanup(0);
    return status;
  }
  b.report_success();
  if (request.command == <run>) status = b.run_program();
  else if (request.command == <script> && !request.dry_run)
    b.publish_script(%"${request.build_dir}/run");
  b.cleanup(1);
  return status;
}

/* A target translates its inputs, then a script's local includes, then a
   module's or its extensions' entry units. */
static int _translate_target(CliRequest request, Build b) {
  int status = _translate_units(request, b, request.inputs);
  /* A script's local `.x` includes are units of its program too; their
     objects have no other source. */
  if (!status && request.command == <script> && !request.dry_run)
    status = _translate_units(request, b, b.script_helpers());
  if (status || request.dry_run) return status;
  if (request.kind != <module> && !request.extensions) return 0;
  CliRequest entry =
    request.kind == <module> ? b.module_entry() : b.extension_entries();
  return _translate_units(entry, b, entry.inputs);
}

/* A target's compile commands join the build's database, which `run`
   writes before its program runs. */
static int _add_commands(
  CliRequest request, Build b, Context target, Array commands) {
  if (commands == NULL) return 0;
  foreach (String entry, b.compile_commands)
    commands.push(target.export(entry));
  if (request.command != <run>) return 0;
  return !compile_commands_write(request.compile_commands, commands);
}

/* Translates the stale `units` and registers every unit's generated files.
   Current units are skipped; the rest translate together, so one request
   can fill every job. Each unit keeps its own generated directory,
   so no two workers write the same file. */
static int _translate_units(CliRequest request, Build b, List units) {
  Map stale = {};
  List inputs = _stale_inputs(b, units, stale);
  if (!request.dry_run && inputs) {
    CliRequest translation = Scope.memdup(request, sizeof(struct CliRequest));
    translation.inputs = inputs;
    translation.out_dir = b.gen_root;
    if (_run_translation(translation, stale, b)) return 1;
  }
  _register_units(request, b, units, stale);
  return 0;
}

/* The units whose translation is not current, in order, with each one's
   generated directory in `stale`. A current unit counts as cached. */
static List _stale_inputs(Build b, List units, Map stale) {
  Array inputs = [];
  foreach (String input, units) {
    if (!is_source_file(input)) continue;
    String directory = b.generated_dir(input);
    if (b.translation_current(input, directory)) {
      b.begin_translation(input);
      b.end_translation(input, 1);
      continue;
    }
    stale[input] = directory;
    inputs.push(input);
  }
  return inputs.list_free();
}

/* Registers every unit's generated files in input order, including package
   directories inserted between generated directories, before native
   compilation and linking. A dry run prints each stale unit's translation,
   and a real one records its fingerprint. */
static void _register_units(
  CliRequest request, Build b, List units, Map stale) {
  foreach (String input, units) {
    if (!is_source_file(input)) continue;
    String directory = b.generated_dir(input);
    if (input in stale && request.dry_run) {
      b.begin_translation(input);
      $report.main.translation_verbose(directory, input);
      b.end_translation(input, 0);
    }
    else if (input in stale) b.record_translation(input, directory);
    b.add_generated(input, directory);
  }
}

// environment

/* `x2c env` prints every resolved value as `name = value`, or one bare value
   when a name is given. Package roots join with `:` like `PATH`. */
static int _run_env(CliRequest request) {
  String wanted = NULL;
  if (request.inputs) wanted = request.inputs.car();
  foreach (List row, _env_rows(request)) {
    String (name, value) = row;
    const char *text = value ? value : "";
    if (!wanted) printf("%s = %s\n", name, text);
    else if (name == wanted) {
      printf("%s\n", text);
      return 0;
    }
  }
  if (wanted) $report.main.env_unknown(wanted);
  return 0;
}

// The resolved values in print order. An absent value prints empty.
static List _env_rows(CliRequest request) {
  Toolchain toolchain = toolchain_new(request);
  String executable = x2c_get_executable();
  String roots = ":".join(request.package_roots());
  interface_configure(request.out_dir, 0);
  return %(
    ("home" ${x2c_get_root()})
    ("executable" $executable)
    ("libexec" ${home_libexec()})
    ("identity" ${compiler_identity()})
    ("include_dir" ${toolchain.include_dir})
    ("runtime_lib" ${toolchain.runtime_lib})
    ("prelude" ${interface_prelude()})
    ("package_dirs" $roots)
    ("cc" ${toolchain.cc})
    ("ar" ${toolchain.ar})
    ("cache_dir" ${script_cache_root()}));
}

// external commands

/* An installed external command replaces this process, and `x2c help
   <name>` runs it with `--help`. */
static void _run_external(int argc, char **argv) {
  String path = _external_path(argv[1]);
  if (path) _exec(path, argv + 1);
  if (argc != 3 || strcmp(argv[1], "help")) return;
  char *args[] = { NULL, "--help", NULL };
  path = _external_path(argv[2]);
  if (path) _exec(path, args);
}

static String _external_path(const char *name) {
  if (!_external_name(name) || cli_builtin_command(name)) return NULL;
  String libexec = home_libexec();
  if (!libexec) return NULL;
  String path = %"$libexec/x2c-$name";
  return Path.is_executable(path) ? path : NULL;
}

static int _external_name(const char *name) {
  if (!name || !isalpha((unsigned char) *name)) return 0;
  for (const char *p = name + 1; *p; p++)
    if (!isalnum((unsigned char) *p) && *p != '-' && *p != '_') return 0;
  return 1;
}

static void _exec(String path, char **args) {
  String home = home_dir(), executable = x2c_get_executable();
  String identity = compiler_identity();
  if (home) setenv("X2C_HOME", home, 1);
  if (executable) setenv("X2C", executable, 1);
  if (identity) setenv("X2C_IDENTITY", identity, 1);
  args[0] = path;
  execv(path, args);
  $report.main.external_failed(path);
}

// entry point

/** Initializes x2c and dispatches one command from `argv`.
    `argv[0]` locates the installation. The process status is zero for a
    successful translation or build, one for compiler or tool
    failure, and the executed program's status for `run`. Help and version exit
    with zero, while invalid CLI and preflight input exit with status two.
    An external command replaces this process and returns its own status.
*/
int main(int argc, char **argv) {
  x2c_initialize_environment(argv[0]);
  if (argc > 1 && !strcmp(argv[1], "editor")) {
    argv[1] = argv[0];
    return editor_request(argc - 1, argv + 1);
  }
  if (argc > 1) _run_external(argc, argv);
  CliRequest request = cli_parse(argc, argv);
  String diagnostics = request.diagnostics_file;
  if (diagnostics && !diagnostics_write_json(diagnostics))
    $report.main.diagnostics_unwritable(diagnostics);
  if (request.command == <script> && script_prepare(request)) return 0;
  report_configure(
    request.quiet, request.plain, request.color_mode,
    request.verbose || request.debugging,
    request.dry_run, request.inspects());
  switch (request.command) {
    case <env>:     return _run_env(request);
    case <install>: return install_command(request);
    case <remove>:  return remove_command(request);
    case <list>:    return list_command(request);
    case <new>:     return new_command(request);
  }
  return _run_compiler(request);
}

/* A translation or build runs inside the command Context, and a script's
   program runs after that Context closes. */
static int _run_compiler(CliRequest request) {
  _configure_logging(request.debugging);
  /* Initialize process caches above the command Context so its cleanup cannot
     invalidate their canonical values. */
  Frontend.load_support(request);
  /* Reclaim command-owned Scope allocations and canonical values. */
  Context command = Context.open_isolated_named("compiler command");
  int status = request.command == <translate>
    ? _run_translation(request, NULL, NULL) : _run_build(request);
  command.close();
  if (request.command == <script> && !status) status = script_run(request);
  return status;
}

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
