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
#include "editor.x"
#include "install.x"
#include "script.x"
#include "toolchain.x"
#pragma private

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
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
  if (!diag || diag.printer) return;
  List entries = compiler.diagnostics();
  foreach (Var entry, entries) compiler.print_diagnostic(entry);
}

static void _preprocessor_errors(String text) {
  Stderr.printf("%s", text);
}

// pipeline utilities

static String _ast_inspection_repr(List node) {
  match (node)
    case %(macrodef (name ?name) *):
      return %"(macrodef <macro $name>)";
  return node.repr();
}

static List _transform_ast(Compiler compiler, List ast) {
  List Compiler.transform(Compiler compiler, List ast);
  ast = compiler.transform(ast);
  if (compiler.error_count()) {
    _report_diagnostics(compiler);
    exit(1);
  }
  return ast;
}

// public entry point

/* Compile one translation unit through the pipeline. An inspection prints
   its stage and returns, so every input is inspected and a failing later
   input still fails the command. */
static void _translate_unit(
  Frontend frontend, String filename, String output_dir) {
  CliRequest request = frontend.request;
  ParsedUnit unit;
  int ok = frontend.start(filename, unit);
  defer unit.close();
  Compiler compiler = unit.compiler;
  if (!ok) {
    _report_diagnostics(compiler);
    exit(1);
  }
  /* While the shared compile-time parent is still pending, this unit may
     unwind and run again, so its diagnostics are held until it finishes
     rather than printed by the attempt that produced them. */
  int macro_library_pending(void);
  int deferred = macro_library_pending();
  if (!deferred) compiler.own_diagnostics();
  if (request.dump == <tokens>) {
    compiler.dump_tokens();
    return;
  }
  ok = unit.collect(frontend);
  if (!deferred || !ok) _report_diagnostics(compiler);
  if (!ok) exit(1);
  switch (request.dump) {
    case <dump-cpp>:
      if (unit.preprocessor_output)
        printf("%s", unit.preprocessor_output);
      return;
    case <cpp-tokens>:
      if (unit.preprocessor) unit.preprocessor.dump_tokens();
      return;
    case <dump-csym>:
      if (unit.preprocessor)
        unit.preprocessor.dump_symbol_table(unit.globals);
      return;
  }
  if (!unit.parse()) {
    _report_diagnostics(compiler);
    exit(1);
  }
  compiler.recovery_depth = 0;
  List ast = unit.ast;
  switch (request.dump) {
    case <dump-cache>:
      compiler.dump_cache();
      return;
    case <symbols>:
      compiler.dump_symbol_table(compiler.sym.current_symbols());
      return;
    case <dump-ast>:
      foreach (List node, ast) printf("\n%s\n", _ast_inspection_repr(node));
      return;
  }
  if (request.dump == <conform>) {
    printf("(unit %s)\n", filename);
    compiler.dump_conformance(unit.globals);
    return;
  }
  ast = compiler.generate_protocol_adapters(ast);
  ast = _transform_ast(compiler, ast);
  switch (request.dump) {
    case <transforms>:
      foreach (List node, ast) printf("\n%s\n", _ast_inspection_repr(node));
      return;
    case <dump-defs>:
      compiler.dump_definitions(ast);
      return;
    case <dump-code>:
      puts(compiler.code_pretty_string(compiler.emit(ast), NULL));
      return;
  }
  generate_code(compiler, ast, output_dir);
  if (!translation_depfile_write(request, compiler, filename, output_dir))
    exit(1);
  if (deferred) _report_diagnostics(compiler);
  // A unit that reaches here has no errors, so any diagnostic is a warning.
  if (request.fatal_warnings && compiler.diagnostics()) exit(1);
}

/* Translates one unit, building the shared compile-time parent between
   units when this one turns out to need it. The unit unwinds before it has
   written anything, so the second attempt is its only visible one. A unit
   restarts at most once: the parent is settled by then, either built or
   recorded as unavailable. */
static void _compile_file(
  Frontend frontend, String filename, String output_dir) {
  try _translate_unit(frontend, filename, output_dir);
  catch %(lisp-late *): {
    if (!frontend.preload_macro_libraries()) exit(1);
    _translate_unit(frontend, filename, output_dir);
  }
}

static void _preflight_translation(CliRequest c, Map unit_dirs) {
  String out_dir = c.out_dir;
  int checked = !c.inspects() && !unit_dirs, Map stems = {};
  if (!c.inspects()) {
    if (!Path.exists(out_dir))
      x2c_driver_error(%"output directory does not exist: $out_dir");
    if (!Path.is_dir(out_dir))
      x2c_driver_error(%"output is not a directory: $out_dir");
    if (access(out_dir, W_OK | X_OK))
      x2c_driver_error(%"output directory is not writable: $out_dir");
  }
  foreach (String input, c.inputs) {
    build_check_input(input);
    if (!x2c_source_file(input))
      x2c_driver_error(%"translation input is not an .x file: $input");
    String stem = Path.stem(input);
    if (checked && stem in stems) {
      String first = stems[stem];
      fprintf(
        stderr, "x2c: error: inputs produce the same output stem '%s'\n"
        "  first input: %s\n  other input: %s\n  output: %s/%s.c\n",
        stem, first, input, out_dir, stem);
      exit(2);
    }
    stems[stem] = input;
  }
}

/* Where one unit's generated C, header, and depfile are written. A build
   gives each unit its own directory so units sharing an output stem cannot
   collide; `x2c translate` writes them all to the shared `--out-dir`. */
static String _unit_output_dir(CliRequest c, Map unit_dirs, String input) {
  if (!unit_dirs) return c.out_dir;
  String directory = unit_dirs[input];
  return directory;
}

/* Translate `inputs` in forked workers, at most `jobs` at a time.
   A worker inherits the process collection cache rather than filling it
   again, and keeps its slice of the input list to the end, so
   the only shared state is the output directory, where no two units write
   the same file. The parent reports progress as workers finish. Returns the
   number that failed. */
static int _translate_workers(
  Frontend frontend, Array chunks, Map unit_dirs, int total, Build build) {
  CliRequest request = frontend.request;
  int jobs = request.jobs, slices = chunks.len();
  if (jobs > slices) jobs = slices;
  if (request.verbose)
    fprintf(
      stderr, "x2c: translate with %d workers over %d files\n", jobs, total);
  // Each live worker retains its input slice for completion reporting.
  long *running = Scope.calloc(jobs, sizeof(long));
  List *carried = Scope.calloc(jobs, sizeof(List));
  int running_count = 0, failed = 0, done = 0, next = 0;
  while (next < slices || running_count) {
    while (next < slices && running_count < jobs) {
      List slice = chunks[next];
      next++;
      if (build) build.begin_translation(slice.car());
      long pid = worker_fork();
      if (!pid) {
        foreach (String input, slice)
          _compile_file(
            frontend, input, _unit_output_dir(request, unit_dirs, input));
        worker_exit(0);
      }
      if (pid < 0) {
        report_line(<error>, "could not start a translation worker");
        failed++;
        continue;
      }
      carried[running_count] = slice;
      running[running_count++] = pid;
    }
    if (!running_count) continue;
    int status, slot = worker_wait_any(running, running_count, status);
    if (status) failed++;
    List slice = carried[slot];
    if (build && !status) build.end_translation(slice.car(), 0);
    done += slice.len();
    running_count--;
    running[slot] = running[running_count];
    carried[slot] = carried[running_count];
    if (!build) report_progress(<translate>, done, total, NULL);
  }
  Scope.free(carried);
  Scope.free(running);
  return failed;
}

/* The packages the top-level `import` declarations of the file at `path`
   name. A token scan suffices: an import is legal only at file scope. */
static List _imported_packages(String path) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return NULL;
  Tokenizer tokens = Tokenizer.new(text, <x2c>);
  tokens.scan();
  Array names = [];
  int depth = 0;
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

/* Loads the native modules of the packages the inputs import before the
   workers fork, so each worker inherits them: the packages a unit's own
   imports name, and those its previous depfile records, which include
   imports reached through a header. A worker loads a module this misses
   itself when its import needs it. */
static void _preload_package_modules(CliRequest c, Map unit_dirs) {
  List roots = c.package_roots();
  if (!roots) return;
  Map names = {};
  foreach (String input, c.inputs) {
    foreach (String name, _imported_packages(input)) names[name] = 1;
    String directory = _unit_output_dir(c, unit_dirs, input);
    String depfile = %"$directory/${Path.stem(input)}.d", text = NULL;
    try text = Path.read_text(depfile);
    catch %((!or not-found io-fail) *): continue;
    foreach (String dependency, translation_depfile_parse(text)) {
      String package = x2c_package_directory(roots, dependency);
      if (package) names[Path.basename(package)] = 1;
    }
  }
  foreach (String name, names.keys()) {
    String root = NULL;
    if (!x2c_package_entry(c.sources, roots, name, root) ||
        Compiler.links_extension(name)) continue;
    String module = %"$root/builds/$name.module";
    if (Path.is_file(module)) Compiler.preload_native_module(module);
  }
}

/* One slice per worker. Fewer, larger slices measured better than more,
   smaller ones. The fork and the copy-on-write faults behind it cost more
   than the imbalance a long unit at the tail of a slice can cause.

   A build passes `slices == total`. Each of its units then translates in a
   worker that has translated nothing else, so a unit records the headers its
   own parse reads rather than inheriting what an earlier unit in the same
   worker already put in the process cache. Build reuse is decided from those
   recorded prerequisites, so they must not depend on how units were
   grouped. */
static Array _translation_chunks(List inputs, int total, int slices) {
  if (slices > total) slices = total;
  if (slices < 1) slices = 1;
  int size = (total + slices - 1) / slices, Array chunks = [];
  List cur = inputs;
  while (cur) {
    Array slice = [];
    for (int n = 0; n < size && cur; n++, cur = cur.cdr())
      slice.push(cur.car());
    chunks.push(slice.list_free());
  }
  return chunks;
}

/* `unit_dirs` maps each input to its own output directory on the build path
   and is absent for `x2c translate`. */
static int _run_translation(CliRequest c, Map unit_dirs, Build build) {
  unsigned long started_at = report_now_us();
  if (!c.out_dir) c.out_dir = ".";
  _preflight_translation(c, unit_dirs);
  if (c.verbose || c.dry_run) {
    fprintf(stderr, "x2c: translate");
    fprintf(stderr, " --out-dir %s", c.out_dir);
    foreach (String input, c.inputs) fprintf(stderr, " %s", input);
    fputc('\n', stderr);
  }
  if (c.dry_run) return 0;
  Frontend frontend = Frontend.new(c);
  frontend.preprocessor_errors = _preprocessor_errors;
  int total = c.inputs.len(), completed = 0;
  unsigned long long gen_bytes = 0;
  /* A dump writes one ordered stream to stdout, and inspection modes report
     per unit, so those stay in this process. The rest may run in parallel. */
  int parallel = c.jobs > 1 && total > 1 &&
                 !c.dump && !c.inspects();
  /* Each worker inherits what this process has already built, so the parent
     is built once here rather than in every worker. A dump interleaves
     diagnostics with its own stream, which a restart would reorder. A unit
     translated in this process otherwise builds the parent only when it
     needs one, which many small programs never do. */
  void macro_library_defer(void);
  if (parallel || c.dump) {
    if (!frontend.preload_macro_libraries()) return 1;
  }
  else macro_library_defer();
  if (parallel) {
    _preload_package_modules(c, unit_dirs);
    Array chunks =
      _translation_chunks(c.inputs, total, unit_dirs ? total : c.jobs);
    int failed = _translate_workers(frontend, chunks, unit_dirs, total, build);
    chunks.free();
    if (failed) return 1;
    completed = total;
  }
  foreach (String input, parallel ? %() : c.inputs) {
    if (!build) report_progress(<translate>, completed, total, input);
    if (build) build.begin_translation(input);
    _compile_file(frontend, input, _unit_output_dir(c, unit_dirs, input));
    if (build) build.end_translation(input, 0);
    completed++;
    if (!build) report_progress(<translate>, completed, total, input);
  }
  if (!build)
    foreach (String input, c.inputs) {
      String stem = Path.stem(input);
      gen_bytes += report_file_bytes(%"${c.out_dir}/$stem.c");
      gen_bytes += report_file_bytes(%"${c.out_dir}/$stem.h");
    }
  if (!build && !c.inspects()) {
    String duration = report_duration(report_now_us() - started_at);
    String noun = total == 1 ? "file" : "files";
    report_line(
      <success>,
      %"Translated $total x2c $noun to ${c.out_dir} in $duration");
    String size = report_size(gen_bytes);
    String c_noun = total == 1 ? "C file" : "C files";
    String h_noun = total == 1 ? "header" : "headers";
    report_line(
      <muted>,
      %"  Generated $total $c_noun and $total $h_noun ($size)");
  }
  return 0;
}

/* Translates the stale `units` and registers every unit's generated files.
   Current units are skipped; the rest translate together, so one request
   can fill every job. Each unit keeps its own generated directory,
   so no two workers write the same file. */
static int _translate_units(CliRequest c, Build state, List units) {
  Array stale = [];
  Map stale_dirs = {};
  foreach (String input, units) {
    if (!x2c_source_file(input)) continue;
    String directory = state.generated_dir(input);
    if (state.translation_current(input, directory)) {
      state.begin_translation(input);
      state.end_translation(input, 1);
      continue;
    }
    stale_dirs[input] = directory;
    stale.push(input);
  }
  List inputs = stale.list_free();
  if (!c.dry_run && inputs) {
    CliRequest translation = Scope.memdup(c, sizeof(struct CliRequest));
    translation.inputs = inputs;
    translation.out_dir = state.gen_root;
    if (_run_translation(translation, stale_dirs, state)) return 1;
  }
  /* Restore input order, including package directories inserted between
     generated directories, before native compilation and linking. */
  foreach (String input, units) {
    if (!x2c_source_file(input)) continue;
    int cached = !stale_dirs.contains(input);
    String directory = state.generated_dir(input);
    if (c.dry_run && !cached) {
      state.begin_translation(input);
      fprintf(stderr, "x2c: translate --out-dir %s %s\n", directory, input);
      state.end_translation(input, 0);
    }
    if (!c.dry_run && !cached)
      state.record_translation(input, directory);
    state.add_generated(input, directory);
  }
  return 0;
}

static int _run_build_request(CliRequest c, Array commands) {
  /* A target has its own build graph and native-action scratch. Isolate
     its Scope allocations and canonical values so a manifest dependency is
     reclaimed before the next target starts. */
  Context target = $auto(Context.open_isolated_named("build target"));
  defer macro_library_reset();
  Build state = c.prepare();
  c.cc = target.export(c.cc);
  c.ar = target.export(c.ar);
  int result = _translate_units(c, state, c.inputs);
  /* A script's local `.x` includes are units of its program too; their
     objects have no other source. */
  if (!result && c.command == <script> && !c.dry_run)
    result = _translate_units(c, state, state.script_helpers());
  if (!result && !c.dry_run && (c.kind == <module> || c.extensions)) {
    CliRequest entry =
      c.kind == <module> ? state.module_entry() : state.extension_entries();
    result = _translate_units(entry, state, entry.inputs);
  }
  if (result) {
    state.cleanup(0);
    return 1;
  }
  result = state.finish();
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
  else if (c.command == <script> && !c.dry_run)
    state.publish_script(%"${c.build_dir}/run");
  state.cleanup(1);
  return result;
}

static int _run_build(CliRequest request) {
  Array commands =
    request.compile_commands && !request.dry_run ? [] : NULL;
  if (request.inputs) {
    // Manifest options have no meaning without a manifest, so say so rather
    // than building something the command did not describe.
    if (request.manifest)
      x2c_driver_error("--manifest-path conflicts with explicit inputs");
    if (request.target)
      x2c_driver_error("--target conflicts with explicit inputs");
    if (request.profile)
      x2c_driver_error("--profile conflicts with explicit inputs");
    int result = _run_build_request(request, commands);
    if (result) return result;
  }
  else {
    if (request.compile_only)
      x2c_driver_error("--compile-only needs input operands, not a manifest");
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

/* `x2c env` prints every resolved value as `name = value`, or one bare value
   when a name is given. Package roots join with `:` like `PATH`. */
static int _run_env(CliRequest request) {
  Toolchain toolchain = toolchain_new(
    request.cc, request.ar, request.cpp_args, request.cc_args,
    request.ld_args, request.verbose, request.dry_run);
  String executable = x2c_get_executable();
  String roots = ":".join(request.package_roots());
  interface_configure(request.out_dir, 0);
  String prelude = interface_prelude();
  List rows = %(
    ("home" ${x2c_get_root()})
    ("executable" ${executable ? executable : %""})
    ("libexec" ${x2c_home_libexec() ? x2c_home_libexec() : %""})
    ("identity" ${x2c_compiler_identity() ? x2c_compiler_identity() : %""})
    ("include_dir" ${toolchain.include_dir})
    ("runtime_lib" ${toolchain.runtime_lib})
    ("prelude" ${prelude ? prelude : %""})
    ("package_dirs" ${roots ? roots : %""})
    ("cc" ${toolchain.cc})
    ("ar" ${toolchain.ar})
    ("cache_dir" ${script_cache_root()}) );
  String wanted = NULL;
  if (request.inputs) wanted = request.inputs.car();
  foreach (List row, rows) {
    String name = row.car(), value = row.cadr();
    const char *text = value ? value : "";
    if (!wanted) printf("%s = %s\n", name.str(), text);
    else if (name == wanted) {
      printf("%s\n", text);
      return 0;
    }
  }
  if (wanted) x2c_driver_error(%"unknown env name '$wanted'");
  return 0;
}

static int _run_bootstrap(CliRequest command) {
  Bootstrap payload = bootstrap_materialize(command);
  if (payload.complete) {
    printf(
      "x2c: native compiler is already installed at %s/bin/x2c\n",
      payload.prefix);
    return 0;
  }
  x2c_set_root(payload.prefix);
  _configure_logging(command.debugging);
  Frontend.load_support(bootstrap_build_request(command, payload, <runtime>));
  /* A source-bearing APE is one-shot: the runtime builds, then the compiler
     that links it, and either status closes build state and flushes stdio
     before `_Exit`. */
  Context build = Context.open_isolated_named("bootstrap build");
  int result = 0, CliRequest request = NULL;
  foreach (Symbol component, %(runtime compiler)) {
    request = bootstrap_build_request(command, payload, component);
    request.label = component;
    result = _run_build_request(request, NULL);
    if (result) break;
  }
  if (!result) {
    bootstrap_write_interfaces(payload);
    bootstrap_build_commands(payload);
    bootstrap_record_install(payload, request.cc, request.ar);
    printf("x2c: installed native compiler at %s/bin/x2c\n", payload.prefix);
  }
  build.close();
  fflush(NULL);
  _Exit(result);
}

static int _external_name(const char *name) {
  if (!name || !((*name >= 'a' && *name <= 'z') ||
                 (*name >= 'A' && *name <= 'Z'))) return 0;
  for (const char *p = name + 1; *p; p++)
    if (!( (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
           (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) return 0;
  return 1;
}

static String _external_path(const char *name) {
  if (!_external_name(name) || cli_builtin_command(name)) return NULL;
  String libexec = x2c_home_libexec();
  if (!libexec) return NULL;
  String path = %"$libexec/x2c-$name";
  return Path.is_executable(path) ? path : NULL;
}

static void _run_external(String path, char **args) {
  String home = x2c_home(), executable = x2c_get_executable();
  String identity = x2c_compiler_identity();
  if (home) setenv("X2C_HOME", home, 1);
  if (executable) setenv("X2C", executable, 1);
  if (identity) setenv("X2C_IDENTITY", identity, 1);
  args[0] = path;
  execv(path, args);
  x2c_driver_error(
    %"cannot run external command '$path': ${String.new(strerror(errno))}");
}

/** Initializes x2c and dispatches one command from `argv`.
    `argv[0]` locates the installation. The process status is zero for a
    successful translation, build, or bootstrap, one for compiler or tool
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
  if (argc > 1) {
    String path = _external_path(argv[1]);
    if (path) _run_external(path, argv + 1);
    if (argc == 3 && !strcmp(argv[1], "help")) {
      path = _external_path(argv[2]);
      if (path) {
        char *args[] = { NULL, "--help", NULL };
        _run_external(path, args);
      }
    }
  }
  CliRequest request = cli_parse(argc, argv);
  String diagnostics = request.diagnostics_file;
  if (diagnostics && !diagnostics_write_json(diagnostics))
    x2c_driver_error(%"cannot open diagnostics file '$diagnostics'");
  if (request.command == <script> && script_prepare(request)) return 0;
  report_configure(
    request.quiet, request.plain, request.color_mode,
    request.verbose || request.debugging,
    request.dry_run, request.inspects());
  if (request.command == <bootstrap>) return _run_bootstrap(request);
  if (request.command == <env>) return _run_env(request);
  if (request.command == <install>) return install_command(request);
  if (request.command == <remove>) return remove_command(request);
  if (request.command == <list>) return list_command(request);
  if (request.command == <new>) return new_command(request);
  _configure_logging(request.debugging);
  /* Initialize process caches above the command Context so its cleanup cannot
     invalidate their canonical values. */
  Frontend.load_support(request);
  /* Reclaim command-owned Scope allocations and canonical values. */
  Context command = Context.open_isolated_named("compiler command");
  int result = request.command == <translate>
    ? _run_translation(request, NULL, NULL) : _run_build(request);
  command.close();
  if (request.command == <script> && !result) result = script_run(request);
#ifdef __COSMOPOLITAN__
  fflush(NULL);
  _Exit(result);
#endif
  return result;
}
