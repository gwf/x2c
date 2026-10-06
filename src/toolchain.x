/*  toolchain.x -- Host preprocessing, compilation, archive, and link actions

    Copyright (c) 2026 Gary William Flake.

    Resolves host tools and builds typed argv. Every action runs as a
    `lib/process.x` command, without a shell.
*/

#pragma once
#include "cli.x"
#include "path.x"
#include "process.x"

/** Holds resolved host tools, native layout, and borrowed option `List`s.
    The record returned by `toolchain_new` is `Scope`-owned. Its `String`s
    follow their owning canonical pools, which may be ancestors; `cpp_args`,
    `cc_args`, and `ld_args` are retained without copying.
*/
typedef struct Toolchain {
  String cc, ar, include_dir, runtime_lib, List cpp_args, cc_args, ld_args;
  int verbose, dry_run, keep_system_includes;
} *Toolchain;

/** Describes one `Scope`-owned host-tool argv action and its reporting policy.
    The `arguments` `List` is retained without copying, follows its owning
    canonical pool, and must remain valid through the action's execution.
*/
typedef struct ToolAction {
  Symbol phase, List arguments, int verbose, dry_run, inherit_stdio, report;
} *ToolAction;

/** Tracks one `Scope`-owned started action and its job.
    A tool that could not start has no job and keeps the message its
    `ToolRun.wait` reports. The borrowed action must remain valid through
    that wait.
*/
typedef struct ToolRun {
  ToolAction action, Job job, String start_error;
} *ToolRun;


#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "report.x"
#include "utils.x"

// command reports

static macro Stmt $report.toolchain.tool_failed(Expr $phase, Expr $status) {
  fprintf(
    stderr, "x2c: %s failed with status %d\n", $phase, $status);
}

// tool selection

/** Creates a `Scope`-owned host toolchain with the tools, native options,
    and verbose and dry-run modes of `request`, and resolves its native
    layout. Tool
    selection is explicit value, `X2C_CC` or `X2C_AR`, `CC` or `AR`, the
    installed toolchain record, then `cc` or `ar`. Explicit tool `String`s and
    option `List`s are borrowed.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the toolchain
    or its canonical layout.
*/
Toolchain toolchain_new(CliRequest request) {
  Toolchain t = _toolchain(request.cc, request.ar);
  t.cpp_args = request.cpp_args; t.cc_args = request.cc_args;
  t.ld_args = request.ld_args;
  t.verbose = request.verbose; t.dry_run = request.dry_run;
  return t;
}

/** Creates the toolchain that builds meta code with `cc`. It selects the
    archiver as `toolchain_new` does and has no native options.
*/
Toolchain toolchain_meta(String cc) => _toolchain(cc, NULL);

static Toolchain _toolchain(String cc, String ar) {
  Toolchain t = Scope.calloc(1, sizeof(struct Toolchain));
  t.cc = _tool(cc, "CC", "cc");
  t.ar = _tool(ar, "AR", "ar");
  t._layout();
  return t;
}

/* The explicit tool, `X2C_<NAME>`, `<NAME>`, the installed toolchain
   record's `<NAME>=` line, then `fallback`. */
static String _tool(String explicit, String name, String fallback) {
  if (explicit) return explicit;
  String value = Env.get(%"X2C_$name");
  if (!value) value = Env.get(name);
  if (!value) value = _recorded_tool(name);
  return value ? value : fallback;
}

static String _recorded_tool(String name) {
  String home = home_dir(), record = NULL;
  if (!home) return NULL;
  try record = Path.read_text(%"$home/lib/x2c/toolchain");
  catch %(not-found *): {}
  foreach (String line, record.split_lines(0))
    if (line.startswith(%"$name=")) return line.remove_prefix(%"$name=");
  return NULL;
}

/* A staged compiler links its stage-local runtime. A compiler with a home
   uses `<home>/lib/libx2c.a`, or in a checkout the stage 0 archive built
   with the headers `<home>/include/x2c` names. Without a home, the layout is
   read from the executable's own prefix. No compiler links an unrelated
   runtime.
*/
static void Toolchain._layout(Toolchain t) {
  String home = home_dir(), stage = stage_dir();
  String executable = x2c_get_executable(), prefix = home;
  if (!prefix)
    prefix = Path.dirname(executable ? Path.dirname(executable) : ".");
  t.include_dir = %"$prefix/include/x2c";
  t.runtime_lib = %"$prefix/lib/libx2c.a";
  if (stage) t.runtime_lib = %"$stage/libx2c.a";
  else if (home && !Path.is_file(t.runtime_lib))
    t.runtime_lib = %"$home/builds/0/libx2c.a";
}

/** Returns the host C compiler that builds meta code, which runs in this
    process's host: `explicit`, `X2C_META_CC`, `META_CC`, or `cc`, never
    the target compiler.
*/
String toolchain_meta_cc(String explicit) => _tool(explicit, "META_CC", "cc");

// actions

/** Creates a `Scope`-owned action that reports nonzero status by default.
    The action retains `arguments` without copying them.

    Raises: `<alloc-fail>` when the action cannot be allocated.
*/
ToolAction tool_action_new(
  Symbol phase, List arguments, int verbose, int dry_run) {
  ToolAction action = Scope.calloc(1, sizeof(struct ToolAction));
  *action = (struct ToolAction) {
    .phase = phase, .arguments = arguments, .verbose = verbose,
    .dry_run = dry_run, .report = 1};
  return action;
}

/** Inherits the standard streams and suppresses the failure summary. */
void ToolAction.as_program(ToolAction action) {
  action.inherit_stdio = 1;
  action.report = 0;
}

static ToolAction Toolchain._action(
  Toolchain t, Symbol phase, List arguments) =>
  tool_action_new(phase, arguments, t.verbose, t.dry_run);

/** Builds but does not start one C compilation action.
    Generated include directories precede the x2c include directory and
    configured compiler arguments. The action requests dependency output at
    `depfile` with `object` as its target.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.compile_action(
  Toolchain t, String source, String object, String depfile, List gen_dirs) =>
  t._action(
    <compile>,
    %(@{t._compile_arguments(gen_dirs)} "-MMD" "-MP" "-MF" $depfile
      "-MT" $object "-c" $source "-o" $object));

/** Builds the preprocessor action whose output identifies an object.
    It uses the compilation's native flags and include order and keeps line
    markers, so source locations belong to the identity.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.preprocess_action(
  Toolchain t, String source, String output, List gen_dirs) =>
  t._action(
    <preprocess>,
    %(@{t._compile_arguments(gen_dirs)} "-E" $source "-o" $output));

static List Toolchain._compile_arguments(Toolchain t, List gen_dirs) => %(
  ${t.cc} "-fsigned-char"
  @{gen_dirs.map(%!(directory) => %("-iquote" $directory)).flatten()}
  "-iquote" ${t.include_dir} @{t.cc_args});

/** Builds but does not start an `ar rcs` action in object-list order.
    The action does not remove an existing archive, so callers requiring exact
    membership must unlink `output` before it runs.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.archive_action(
  Toolchain t, String output, List objects) =>
  t._action(<archive>, %(${t.ar} "rcs" $output @objects));

/** Builds but does not start a host-compiler link action.
    Input order is preserved; configured linker arguments, the matching x2c
    runtime archive, and `-lm` follow the inputs.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.link_action(Toolchain t, String output, List inputs) =>
  t._action(
    <link>,
    %(${t.cc} @inputs @{t.ld_args} ${t.runtime_lib} "-lm" "-o" $output));

/** Builds but does not start the link of a native module. The module leaves
    the x2c runtime unresolved and uses the loading compiler's copy. macOS
    links a bundle against the running compiler, so a runtime function the
    compiler lacks fails this link. Other hosts link a shared object whose
    calls to its own functions never bind to a same-named compiler function;
    a missing runtime function fails when the compiler loads it.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.module_action(Toolchain t, String output, List inputs) =>
  t._action(
    <link>, %(${t.cc} @inputs @{t.ld_args} @{_module_shape()} "-o" $output));

static List _module_shape(void) {
#ifdef __APPLE__
  return %("-bundle" "-bundle_loader" ${x2c_get_executable()});
#else
  return %("-shared" "-Wl,-Bsymbolic-functions");
#endif
}

// running tools

/** Starts and waits for the action, returning its final status.

    Raises: the same construction and capture-reading causes as
    `ToolAction.start` and `ToolRun.wait`.
*/
int ToolAction.run(ToolAction action) => action.start().wait();

/** Starts the action without a shell and returns a `Scope`-owned execution.
    Verbose and dry-run actions print their quoted argv to stderr. A dry run
    starts no child.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the execution
    or argv.
*/
ToolRun ToolAction.start(ToolAction action) {
  if (action.verbose || action.dry_run) {
    report_suspend();
    _print_action(action.phase, action.arguments);
  }
  ToolRun execution = Scope.calloc(1, sizeof(struct ToolRun));
  execution.action = action;
  if (action.dry_run) return execution;
  Job command = action.inherit_stdio ?
    action.arguments.job().live() : _captured(action.arguments);
  execution.job = _start_tool(
    command, action.arguments.car(), execution.start_error);
  return execution;
}

/** Checks whether an execution can be waited without blocking. A dry run
    and a tool that could not start are ready immediately.
*/
int ToolRun.ready(ToolRun t) => !t.job || t.job.ready();

/** Waits for an execution, forwards its captured streams, and returns its
    shell-style status. Signals return `128 + signal`, a tool that could not
    start returns 127, and a dry run returns 0. Captured output goes to
    stderr; program actions inherit standard streams.

    Raises: `<io-fail>`, `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` while
    reading either capture as a `String`.
*/
int ToolRun.wait(ToolRun execution) {
  ToolAction action = execution.action;
  if (action.dry_run) return 0;
  Job job = execution.job;
  int status = job ? job.status() : 127;
  String output = job ? job.output_text : NULL;
  String errors = job ? job.errors_text : execution.start_error;
  report_suspend();
  if (output) fputs(output, stderr);
  if (errors) fputs(errors, stderr);
  if (status && action.report)
    $report.toolchain.tool_failed(action.phase.str(), status);
  return status;
}

/** Runs the host tool `arguments` without a shell, captures both streams,
    and returns its shell-style status. A tool that cannot start returns 127
    and leaves the reason in `errors`.
*/
int tool_capture(List arguments, String &output, String &errors) =>
  _capture(_captured(arguments), arguments.car(), output, errors);

static int _capture(
  Job command, String program, String &output, String &errors) {
  Job job = _start_tool(command, program, errors);
  if (!job) return 127;
  int status = job.status();
  output = job.output_text;
  errors = job.errors_text;
  return status;
}

static Job _captured(List arguments) =>
  arguments.job().options({stdout: <capture>, stderr: <capture>});

/* A tool that cannot start reports like a child that exited 127, the status
   a shell gives a missing program, so every caller keeps one failure path. */
static Job _start_tool(Job command, String program, String &failure) {
  Job job = NULL;
  try job = command.start();
  catch %((!or not-found io-fail) *detail):
    failure = _start_failure(program, detail);
  return job;
}

static String _start_failure(String program, List detail) {
  long error = detail.assoc(<"errno">);
  String reason = String.new(strerror((int) error));
  return %"x2c: unable to execute $program: $reason\n";
}

// host preprocessing

/** Runs the configured C preprocessor without a shell.
    System headers keep their include directives when the host supports
    that mode. `output`, `errors`, and `dependencies` are cleared before
    use. Source and include paths remain distinct argv elements, and stdout
    and stderr are captured separately. The temporary depfile is read into
    `dependencies` when possible and removed on returning paths, including a
    handled `<io-fail>` while reading it. A non-returning
    `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` may transfer before removal.
    Returns the shell-style child status, 127 when the preprocessor cannot
    start, or -1 for invalid arguments or local setup failure. This operation
    does not consult `dry_run`.

    Raises: `<io-fail>`, `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` while
    constructing arguments or reading captured text.
*/
int Toolchain.preprocess(
  Toolchain t, const char *fname, List include_dirs, const char *imacros,
  String &output, String &errors, String &dependencies) {
  output = NULL; errors = NULL; dependencies = NULL;
  if (!fname) return -1;
  if (!t.keep_system_includes)
    t.keep_system_includes = _keeps_system_includes(t.cc);
  Path scratch = Path.temp_dir();
  String depfile = %"$scratch/cpp.d";
  List arguments = t._cpp_arguments(include_dirs, imacros, depfile, fname);
  if (t.verbose) _print_action(<preprocess>, arguments);
  /* The empty standard input is the main file, so the unit is an included
     file whose own `#pragma once` stops an include cycle from splicing it
     again. The host ignores that pragma in a main file. */
  Job command = _captured(arguments).options({input: ""});
  int status = _capture(command, arguments.car(), output, errors);
  /* The dependency file is consumed and removed even after host failure. The
     returned status tells the caller whether stdout is usable. */
  try dependencies = Path.read_text(depfile);
  catch %(not-found *): {}
  scratch.remove_tree();
  return status;
}

/* 1 when the host preprocessor accepts `-fkeep-system-includes`, which keeps
   system include directives, and -1 otherwise. */
static int _keeps_system_includes(String cc) {
  String output = NULL, errors = NULL;
  List probe = %($cc "-E" "-x" "c" "-fkeep-system-includes" "/dev/null");
  return tool_capture(probe, output, errors) == 0 ? 1 : -1;
}

static List Toolchain._cpp_arguments(
  Toolchain t, List include_dirs, String macros, String depfile,
  String source) => %(
    ${t.cc} "-E" "-x" "c"
    "-D__asm(x)=" "-D__asm__(x)=" "-D__attribute__(x)="
    "-D__format__(x)=" "-D__printf__(x)=" "-D__inline__="
    "-D__inline=" "-D_Nullable=" "-D_Nonnull=" "-DX2CCPP"
    "-D__restrict=" "-D__extension__=" "-Wno-unicode"
    "-Wno-invalid-pp-token"
    @{t.keep_system_includes > 0 ? %("-fkeep-system-includes") : NULL}
    "-I" "." @{_includes(cpp_include_dirs())} @{_includes(include_dirs)}
    @{t.cpp_args} @{macros ? %("-imacros" $macros) : NULL}
    "-MMD" "-MF" $depfile "-MT" "x2c-dependencies"
    "-include" $source "-");

static List _includes(List directories) =>
  directories.map(%!(directory) => %("-I" $directory)).flatten();

// default search paths

/** Returns the directories the C compiler searches for headers and libraries
    without explicit options, as it reports them, plus the `lib` directory
    beside each reported `include` directory. A compiler that reports none
    contributes none.
*/
List Toolchain.search_directories(Toolchain t) {
  Array directories = [];
  List flags = t.cc_args;
  String output = NULL, errors = NULL;
  List search = %(${t.cc} @flags "-E" "-v" "-x" "c" "/dev/null");
  if (!tool_capture(search, output, errors))
    _add_include_directories(directories, errors);
  if (!tool_capture(%(${t.cc} @flags "-print-search-dirs"), output, errors))
    _add_library_directories(directories, output);
  return directories.list_free();
}

/* `-v` lists the header search after each `search starts here` line and
   stops at `End of search list`. */
static void _add_include_directories(Array directories, String listing) {
  int listed = 0;
  foreach (String line, listing.split_lines(0)) {
    if (line.startswith("End of search list")) return;
    if ("search starts here" in line) listed = 1;
    else if (listed) _add_include_directory(directories, line);
  }
}

/* A listed directory may carry a note such as ` (framework directory)`. */
static void _add_include_directory(Array directories, String line) {
  String directory = line.strip(" ");
  int note = directory.find(" (");
  if (note >= 0) directory = directory[:note];
  directories.push(directory);
  if (directory.endswith("/include"))
    directories.push(Path.dirname(directory).join("lib"));
}

static void _add_library_directories(Array directories, String output) {
  foreach (String line, output.split_lines(0)) {
    if (!line.startswith("libraries: ")) continue;
    String list = line.remove_prefix("libraries: ").remove_prefix("=");
    foreach (String directory, list.split(":"))
      if (directory) directories.push(directory);
  }
}

// quoted argv

static void _print_action(Symbol phase, List arguments) {
  fprintf(stderr, "x2c: %s", phase.str());
  foreach (String argument, arguments) {
    fputc(' ', stderr);
    _print_argument(argument);
  }
  fputc('\n', stderr);
}

static void _print_argument(String argument) {
  if (_shell_safe(argument)) {
    fputs(argument, stderr);
    return;
  }
  fputc('\'', stderr);
  foreach (char ch, argument) {
    if (ch == '\'') fputs("'\\''", stderr);
    else fputc(ch, stderr);
  }
  fputc('\'', stderr);
}

static int _shell_safe(String argument) {
  if (!argument || !argument[0]) return 0;
  foreach (char raw, argument) {
    unsigned char ch = raw;
    if (!(isalnum(ch) || strchr("_+-=.,/:@", ch))) return 0;
  }
  return 1;
}
