/*  translation.x -- synchronous compiler translation requests

    Copyright (c) 2026 Gary William Flake.
*/

#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "frontend.x"
#include "meta-project.x"
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

static macro Stmt $report.main_stem_collision(
  Expr $stem, Expr $first, Expr $other, Expr $directory) =>
  fprintf(
    stderr, "x2c: error: inputs produce the same output stem '%s'\n"
    "  first input: %s\n  other input: %s\n  output: %s/%s.c\n",
    $stem, $first, $other, $directory, $stem);

static macro Stmt $progress.main_workers_started(Expr $jobs, Expr $total) =>
  fprintf(
    stderr, "x2c: translate with %d workers over %d files\n",
    $jobs, $total);

static macro Stmt $fail.main_input_not_x(Expr $input) =>
  Diagnostics.driver_error(%"translation input is not an .x file: ${$input}");

static macro Stmt $fail.main_directory_missing(Expr $out_dir) =>
  Diagnostics.driver_error(%"output directory does not exist: ${$out_dir}");

static macro Stmt $fail.main_directory_not_dir(Expr $out_dir) =>
  Diagnostics.driver_error(%"output is not a directory: ${$out_dir}");

static macro Stmt $fail.main_directory_unwritable(Expr $out_dir) =>
  Diagnostics.driver_error(%"output directory is not writable: ${$out_dir}");

static macro Stmt $progress.main_translated(
  Expr $n, Expr $noun, Expr $out_dir, Expr $duration) =>
  report_line(
    <success>, %"Translated ${$n} x2c ${$noun} to ${$out_dir} in ${
      $duration}");

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
  c.generate_code(ast, output_dir);
  if (!c.write_depfile(request, filename, output_dir)) exit(1);
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
  foreach (List node, _renumbered_bindings(ast))
    printf("\n%s\n", _node_repr(node));
}

/* A binding number counts every binding the unit has issued, collection's
   included, so it depends on whether the includes replayed or were parsed
   cold. A dump numbers bindings by their first appearance in its text. */
static List _renumbered_bindings(List ast) {
  Map numbers = {}, replaced = {};
  Array pending = $auto([ast]);
  while (pending.len()) {
    Var node = pending.take_last();
    if (node is not <list> || node.is_nil()) continue;
    match (node.list()) case %(binding ?identity ?spelling): {
      if (!(identity in numbers)) numbers[identity] = (int) numbers.len() + 1;
      replaced[(void *) node.list()] =
        %(binding ${numbers[identity]} $spelling);
      continue;
    }
    foreach (Var child, node.list().reverse()) pending.push(child);
  }
  return Ast.replace_nodes(ast, replaced);
}

static String _node_repr(List node) {
  match (node)
    case %(macrodef (name ?name) *): return %"(macrodef <macro $name>)";
  return node.repr();
}

// translation requests

/* One request's units share a frontend. `unit_dirs` maps each input to its
   own output directory on the build path, where the caller reports progress;
   `x2c translate` has neither. */
static typedef struct Translation {
  CliRequest request, Frontend frontend, Map unit_dirs;
  void *context;
  void (*progress)(void *context, String input, int completed);
  int total;
} Translation;

/** Translates a request synchronously. Optional per-input directories and a
    parent-process progress callback let a caller own build state. Without a
    callback, translation reports its own progress and receipt. */
int translate_request(
  CliRequest request, Map unit_dirs, void *context,
  void (*progress)(void *context, String input, int completed)) {
  unsigned long started_at = report_now_us();
  if (!request.out_dir) request.out_dir = ".";
  Translation t = {
    .request = request, .unit_dirs = unit_dirs, .context = context,
    .progress = progress,
    .total = request.inputs.len()};
  _preflight(t);
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
    if (_translate_parallel(t)) return 1;
  }
  else _translate_serial(t);
  if (!progress && !request.inspects()) _report(t, started_at);
  return 0;
}

/* Each input must be a regular `.x` file. Units that write to the shared
   `--out-dir` must not share an output stem; inspection writes nothing. */
static void _preflight(Translation &t) {
  CliRequest request = t.request;
  if (!request.inspects()) _check_out_dir(request.out_dir);
  int shared = !request.inspects() && !t.unit_dirs, Map stems = {};
  foreach (String input, request.inputs) {
    CliRequest.require_input(input);
    if (!Path.is_x2c_source(input))
      $fail.main_input_not_x(input);
    String stem = Path.stem(input);
    if (shared && stem in stems)
      _stem_collision(stem, stems[stem], input, request.out_dir);
    stems[stem] = input;
  }
}

static void _check_out_dir(String out_dir) {
  if (!Path.exists(out_dir))
    $fail.main_directory_missing(out_dir);
  if (!Path.is_dir(out_dir))
    $fail.main_directory_not_dir(out_dir);
  if (access(out_dir, W_OK | X_OK))
    $fail.main_directory_unwritable(out_dir);
}

static void _stem_collision(
  String stem, String first, String other, String out_dir) {
  $report.main_stem_collision(stem, first, other, out_dir);
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

static void _translate_serial(Translation &t) {
  int done = 0;
  foreach (String input, t.request.inputs) {
    if (t.progress) t.progress(t.context, input, 0);
    else report_progress(<translate>, done, t.total, input);
    _translate(t, input);
    done++;
    if (t.progress) t.progress(t.context, input, 1);
    else report_progress(<translate>, done, t.total, input);
  }
}

static void _translate(Translation &t, String input) =>
  _translate_unit(t.frontend, input, _output_dir(t, input));

/* Where one unit's generated C, header, and depfile are written. A build
   gives each unit its own directory so units sharing an output stem cannot
   collide; `x2c translate` writes them all to the shared `--out-dir`. */
static String _output_dir(Translation &t, String input) {
  if (!t.unit_dirs) return t.request.out_dir;
  return t.unit_dirs[input];
}

static void _report(Translation &t, unsigned long started_at) {
  String out_dir = t.request.out_dir;
  unsigned long long bytes = 0;
  foreach (String input, t.request.inputs) {
    String stem = Path.stem(input);
    bytes += Path.regular_bytes(%"$out_dir/$stem.c");
    bytes += Path.regular_bytes(%"$out_dir/$stem.h");
  }
  String duration = report_duration(report_now_us() - started_at);
  int n = t.total;
  String noun = n == 1 ? "file" : "files";
  $progress.main_translated(n, noun, out_dir, duration);
  report_generated(n, bytes);
}

// translation workers

/* The live workers of one parallel translation. Each live slot keeps its
   worker's pid, the index of the slice it carries, and the file that
   captures its standard error. `output` holds each ended slice's captured
   bytes until every earlier slice has shown its own. */
static typedef struct Workers {
  Translation *t, Array slices, long *pids, int *carried, File *captures;
  Block *output;
  int live, started, shown, failed, done;
} Workers;

/* The running parallel translation. A stop signal reaches its live
   workers. A worker has none of its own. */
static Workers _workers;

/* Translate the inputs in forked workers. Returns the number of slices
   that failed. */
static int _translate_parallel(Translation &t) {
  _preload_modules(t);
  int count = t.unit_dirs ? t.total : t.request.jobs;
  Array slices = _slices(t.request.inputs, t.total, count);
  int failed = _run_workers(t, slices);
  slices.free();
  return failed;
}

/* Loads the native modules of the packages the inputs import before the
   workers fork, so each worker inherits them. A worker loads a module this
   misses itself when its import needs it. */
static void _preload_modules(Translation &t) {
  List roots = t.request.package_roots();
  if (!roots) return;
  foreach (String name, _package_names(t, roots).keys()) {
    String root = NULL;
    if (!t.request.sources.package_entry(roots, name, root) ||
        Compiler.links_extension(name)) continue;
    String module = %"$root/builds/$name.module";
    if (Path.is_file(module)) Compiler.preload_native_module(module);
  }
}

/* The packages a unit's own imports name, and those its previous depfile
   records, which include imports reached through a header. */
static Map _package_names(Translation &t, List roots) {
  Map names = {};
  foreach (String input, t.request.inputs) {
    foreach (String name, _imported_packages(input)) names[name] = 1;
    String depfile = %"${_output_dir(t, input)}/${Path.stem(input)}.d";
    String text = NULL;
    try text = Path.read_text(depfile);
    catch %((!or not-found io-fail) *): continue;
    foreach (String dependency, translation_depfile_parse(text)) {
      String package = Compiler.package_directory(roots, dependency);
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
static int _run_workers(Translation &t, Array slices) {
  int jobs = t.request.jobs, count = slices.len();
  if (jobs > count) jobs = count;
  if (t.request.verbose)
    $progress.main_workers_started(jobs, t.total);
  _workers = (Workers) {
    .t = &t, .slices = slices, .pids = Scope.calloc(jobs, sizeof(long)),
    .carried = Scope.calloc(jobs, sizeof(int)),
    .captures = Scope.calloc(jobs, sizeof(File)),
    .output = Scope.calloc(count, sizeof(Block))};
  struct sigaction term, interrupt;
  _forward_stop_signal(SIGTERM, &term);
  _forward_stop_signal(SIGINT, &interrupt);
  while (_workers.started < count || _workers.live) {
    if (_workers.started < count && _workers.live < jobs) _start(_workers);
    else _reap(_workers);
    _show(_workers);
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
static void _start(Workers &w) {
  int index = w.started++;
  List slice = w.slices[index];
  if (w.t.progress) w.t.progress(w.t.context, slice.car(), 0);
  File capture = tmpfile();
  sigset_t unblocked = _block_stop_signals();
  long pid = capture ? _fork_worker() : -1;
  if (!pid) {
    w.live = 0;
    sigprocmask(SIG_SETMASK, &unblocked, NULL);
    dup2(capture.fileno(), STDERR_FILENO);
    _work((*w.t), slice);
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
static void _work(Translation &t, List slice) {
  foreach (String input, slice) _translate(t, input);
  Compiler.stop_meta_helper();
  _exit_worker(0);
}

/* Keeps the ended worker's captured bytes for `show`. The last live worker
   moves into the slot of the one that finished. */
static void _reap(Workers &w) {
  int status, slot = _wait_worker(w.pids, w.live, status);
  if (status) w.failed++;
  int index = w.carried[slot];
  List slice = w.slices[index];
  File capture = w.captures[slot];
  defer capture.close();
  capture.rewind();
  Block output = Block.new(sizeof(char));
  capture.read_into(output);
  w.output[index] = output;
  if (w.t.progress && !status) w.t.progress(w.t.context, slice.car(), 1);
  w.done += slice.len();
  sigset_t unblocked = _block_stop_signals();
  w.live--;
  w.pids[slot] = w.pids[w.live];
  w.carried[slot] = w.carried[w.live];
  w.captures[slot] = w.captures[w.live];
  sigprocmask(SIG_SETMASK, &unblocked, NULL);
  if (!w.t.progress) report_progress(<translate>, w.done, w.t.total, NULL);
}

/* Forks a worker that continues the current program with inherited state.
   Returns zero in the child, its PID in the parent, or -1 on fork failure.
   The call attempts to flush all process streams before the fork so
   successfully flushed bytes cannot be written by both processes. Flush
   failure is ignored. The child must leave through `_exit_worker`. */
static long _fork_worker(void) {
  fflush(NULL);
  pid_t pid = fork();
  return pid < 0 ? -1 : (long) pid;
}

/* Attempts to flush process streams and terminates a worker with `status`.
   Flush failure is ignored. This function does not return and does not run
   `atexit` handlers. Those belong to the parent process and would close its
   log and process-lifetime `Scope`s twice. */
static void _exit_worker(int status) {
  fflush(NULL);
  _exit(status);
}

/* Waits until one of the `count` workers in `pids` exits and returns its
   index, storing its shell-style status: the exit status, `128 + signal`,
   or -1 when it cannot be waited. Other children stay unreaped, so the
   wait polls with a short sleep. */
static int _wait_worker(long *pids, int count, int &status) {
  loop {
    for (int i = 0; i < count; i++) {
      int raw, signal;
      pid_t done = waitpid((pid_t) pids[i], &raw, WNOHANG);
      if (!done || (done < 0 && errno == EINTR)) continue;
      status = done < 0 ? -1 : Job.decode_wait_status(raw, signal);
      return i;
    }
    usleep(1000);
  }
}

/* Prints each ended slice's captured standard error once every earlier
   slice has printed its own. A slice has ended when it has started and no
   live worker carries it. */
static void _show(Workers &w) {
  while (w.shown < w.started && !_carries(w, w.shown)) {
    Block output = w.output[w.shown++];
    if (output == NULL) continue;
    defer output.free();
    if (!output.length) continue;
    report_suspend();
    File.write_all(stderr, output.bytes, output.length);
  }
}

static int _carries(Workers &w, int index) {
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

