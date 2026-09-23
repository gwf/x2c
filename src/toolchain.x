/*  toolchain.x -- Host preprocessing, compilation, archive, and link actions

    Copyright (c) 2026 Gary William Flake.

    Resolves host tools and builds typed argv. Every action runs as a
    `lib/process.x` command, without a shell.
*/

#pragma once
#include "path.x"
#include "process.x"

/** Holds resolved host tools, native layout, and borrowed option `List`s.
    The record returned by `toolchain_new` is `Scope`-owned. Its `String`s
    follow
    their owning canonical pools, which may be ancestors; `cpp_args`,
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
  ToolAction action;
  Job job;
  String start_error;
} *ToolRun;

#pragma private

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "report.x"
#include "utils.x"

/* The explicit tool, `X2C_<NAME>`, `<NAME>`, the installed toolchain
   record's `<NAME>=` line, then `fallback`. */
static String _tool(String explicit, String name, String fallback) {
  if (explicit) return explicit;
  String home = x2c_home(), record = NULL;
  String value = Env.get(%"X2C_$name");
  if (!value) value = Env.get(name);
  if (!value && home) {
    try record = Path.read_text(%"$home/lib/x2c/toolchain");
    catch %(not-found *): {}
    foreach (String line, record.split_lines(0))
      if (line.startswith(%"$name=")) {
        value = line.remove_prefix(%"$name=");
        break;
      }
  }
  return value ? value : fallback;
}

/* A staged compiler links its stage-local runtime. A compiler with a home
   uses `<home>/lib/libx2c.a`, or in a checkout the stage 0 archive built
   with the headers `<home>/include/x2c` names. Without a home, the layout is
   read from the executable's own prefix. No compiler links an unrelated
   runtime.
*/
static void Toolchain._layout(Toolchain t) {
  String home = x2c_home(), stage = x2c_stage_dir();
  String executable = x2c_get_executable(), prefix = home;
  if (!prefix)
    prefix = Path.dirname(executable ? Path.dirname(executable) : ".");
  t.include_dir = %"$prefix/include/x2c";
  t.runtime_lib = %"$prefix/lib/libx2c.a";
  if (stage) t.runtime_lib = %"$stage/libx2c.a";
  else if (home && !Path.is_file(t.runtime_lib))
    t.runtime_lib = %"$home/builds/0/libx2c.a";
}

/** Creates a `Scope`-owned host toolchain and resolves its native layout.
    Tool selection is explicit value, `X2C_CC` or `X2C_AR`, `CC` or `AR`, the
    installed toolchain record, then `cc` or `ar`. Explicit tool `String`s and
    option `List`s are borrowed.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the toolchain
    or its canonical layout.
*/
Toolchain toolchain_new(
  String cc, String ar, List cpp_args, List cc_args, List ld_args, int verbose,
  int dry_run) {
  Toolchain t = Scope.calloc(1, sizeof(struct Toolchain));
  t.cc = _tool(cc, "CC", "cc");
  t.ar = _tool(ar, "AR", "ar");
  t.cpp_args = cpp_args;
  t.cc_args = cc_args;
  t.ld_args = ld_args;
  t.verbose = verbose;
  t.dry_run = dry_run;
  t._layout();
  return t;
}

static List _compile_arguments(Toolchain t, List gen_dirs) => %(
  ${t.cc} "-fsigned-char"
  @{gen_dirs.map(%!(directory) => %("-iquote" $directory)).flatten()}
  "-iquote" ${t.include_dir} @{t.cc_args});

/** Builds but does not start one C compilation action.
    Generated include directories precede the x2c include directory and
    configured compiler arguments. The action requests dependency output at
    `depfile` with `object` as its target.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.compile_action(
  Toolchain t, String source, String object, String depfile, List gen_dirs) =>
  tool_action_new(
    <compile>,
    %(@{_compile_arguments(t, gen_dirs)} "-MMD" "-MP" "-MF" $depfile
      "-MT" $object "-c" $source "-o" $object),
    t.verbose, t.dry_run);

/** Captures the native preprocessor view used to identify reusable objects.
    Uses the compilation's native flags and include order, retaining line
    markers so source locations also belong to the identity.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.preprocess_action(
  Toolchain t, String source, String output, List gen_dirs) =>
  tool_action_new(
    <preprocess>,
    %(@{_compile_arguments(t, gen_dirs)} "-E" $source "-o" $output),
    t.verbose, t.dry_run);

/** Builds but does not start an `ar rcs` action in object-list order.
    The action does not remove an existing archive, so callers requiring exact
    membership must unlink `output` before it runs.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.archive_action(
  Toolchain t, String output, List objects) =>
  tool_action_new(
    <archive>, %(${t.ar} "rcs" $output @objects), t.verbose, t.dry_run);

/** Builds but does not start a host-compiler link action.
    Input order is preserved; configured linker arguments, the matching x2c
    runtime archive, and `-lm` follow the inputs.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.link_action(Toolchain t, String output, List inputs) =>
  tool_action_new(
    <link>,
    %(${t.cc} @inputs @{t.ld_args} ${t.runtime_lib} "-lm" "-o" $output),
    t.verbose, t.dry_run);

/** Builds but does not start the link of a native module. The module leaves
    the x2c runtime unresolved, so a loading compiler supplies its own copy.
    macOS links a bundle and other hosts a shared object whose calls to its
    own functions never bind to a same-named function of the compiler.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.module_action(Toolchain t, String output, List inputs) {
  List shape = %("-shared" "-Wl,-Bsymbolic-functions");
#ifdef __APPLE__
  shape = %("-bundle" "-undefined" "dynamic_lookup");
#endif
  return tool_action_new(
    <link>, %(${t.cc} @inputs @{t.ld_args} @shape "-o" $output),
    t.verbose, t.dry_run);
}

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

/** Inherits the standard streams and suppresses the failure summary.
*/
void ToolAction.as_program(ToolAction action) {
  action.inherit_stdio = 1;
  action.report = 0;
}

static int _shell_safe(String argument) {
  if (!argument || !argument[0]) return 0;
  foreach (char raw, argument) {
    unsigned char ch = raw;
    if (!(isalnum(ch) || strchr("_+-=.,/:@", ch))) return 0;
  }
  return 1;
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

static void _print_action(Symbol phase, List arguments) {
  fprintf(stderr, "x2c: %s", phase.str());
  foreach (String argument, arguments) {
    fputc(' ', stderr);
    _print_argument(argument);
  }
  fputc('\n', stderr);
}

static String _start_failure(String program, List detail) {
  long error = detail.assoc(<errno>);
  String reason = String.new(strerror((int) error));
  return %"x2c: unable to execute $program: $reason\n";
}

/* A tool that cannot start reports like a child that exited 127, the status
   a shell gives a missing program, so every caller keeps one failure path. */
static Job _start_tool(Job command, String program, String *failure) {
  Job job = NULL;
  try job = command.start();
  catch %(not-found *detail): *failure = _start_failure(program, detail);
  catch %(io-fail *detail): *failure = _start_failure(program, detail);
  return job;
}

/** Runs the host tool `arguments` without a shell, captures both streams,
    and returns its shell-style status. A tool that cannot start returns 127
    and leaves the reason in `errors`.
*/
int tool_capture(List arguments, String *output, String *errors) {
  Job command =
    arguments.job().options({stdout: <capture>, stderr: <capture>});
  Job j = _start_tool(command, arguments.car(), errors);
  if (!j) return 127;
  int status = j.status();
  *output = j.output_text;
  *errors = j.errors_text;
  return status;
}

/** Returns the directories the C compiler searches for headers and libraries
    without explicit options, as it reports them, plus the `lib` directory
    beside each reported `include` directory. A compiler that reports none
    contributes none.
*/
List Toolchain.search_directories(Toolchain t) {
  Array directories = [];
  List flags = t.cc_args;
  String output = NULL, errors = NULL;
  if (!tool_capture(%(${t.cc} @flags "-E" "-v" "-x" "c" "/dev/null"),
                    &output, &errors)) {
    int listing = 0;
    foreach (String line, errors.split_lines(0)) {
      if (line.startswith("End of search list")) break;
      if (line.contains("search starts here")) {
        listing = 1;
        continue;
      }
      if (!listing) continue;
      String directory = line.strip(" ");
      int note = directory.find(" (");
      if (note >= 0) directory = directory[:note];
      directories.push(directory);
      if (directory.endswith("/include"))
        directories.push(Path.dirname(directory).join("lib"));
    }
  }
  if (!tool_capture(%(${t.cc} @flags "-print-search-dirs"), &output, &errors))
    foreach (String line, output.split_lines(0)) {
      if (!line.startswith("libraries: ")) continue;
      String list = line.remove_prefix("libraries: ").remove_prefix("=");
      foreach (String directory, list.split(":"))
        if (directory) directories.push(directory);
    }
  return directories.list_free();
}

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
  Job command = action.inherit_stdio ? action.arguments.job().live() :
    action.arguments.job().options({stdout: <capture>, stderr: <capture>});
  execution.job = _start_tool(
    command, action.arguments.car(), &execution.start_error);
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
    fprintf(
      stderr, "x2c: %s failed with status %d\n",
      action.phase.str(), status);
  return status;
}

/** Starts and waits for the action, returning its final status.

    Raises: the same construction and capture-reading causes as
    `ToolAction.start` and `ToolRun.wait`.
*/
int ToolAction.run(ToolAction action) => action.start().wait();

static List _includes(List directories) =>
  directories.map(%!(directory) => %("-I" $directory)).flatten();

/** Runs the configured C preprocessor without a shell.
    `expand_system_headers` requests declarations from system headers rather
    than retaining their include directives when the host supports that mode.
    `fname`, `output`, and `errors` are required; output pointers are cleared
    before use. Source and include paths remain distinct argv elements, and
    stdout and stderr are captured separately. When `dependencies` is present,
    its temporary depfile is read when possible and removed on returning paths,
    including a handled `<io-fail>` while reading it. A non-returning
    `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` may transfer before removal.
    Returns the shell-style child status, 127 when the preprocessor cannot
    start, or -1 for invalid arguments or local setup failure. This operation
    does not consult `dry_run`.

    Raises: `<io-fail>`, `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` while
    constructing arguments or reading captured text.
*/
int Toolchain.preprocess(
  Toolchain t, const char *fname, List include_dirs, const char *imacros,
  int expand_system_headers,
  String *output, String *errors, String *dependencies) {
  if (output) *output = NULL;
  if (errors) *errors = NULL;
  if (dependencies) *dependencies = NULL;
  if (!fname || !output || !errors) return -1;
  String source = fname, macros = imacros;
  if (!expand_system_headers && !t.keep_system_includes) {
    String probe_output = NULL, probe_errors = NULL;
    t.keep_system_includes = tool_capture(
      %(${t.cc} "-E" "-x" "c" "-fkeep-system-includes" "/dev/null"),
      &probe_output, &probe_errors) == 0 ? 1 : -1;
  }
  Path scratch = dependencies ? Path.temp_dir() : NULL;
  String depfile = %"$scratch/cpp.d";
  /* Headers place attributes where x2c does not parse them, and a packing
     attribute changes the layout of its struct. Each one becomes a marked
     string, so tokenizing can erase it and keep that fact. */
  List arguments = %(
    ${t.cc} "-E" "-P" "-x" "c"
    "-D__asm(x)=" "-D__asm__(x)=" "-D__attribute__(x)=__x2c_attribute__ #x"
    "-D__format__(x)=" "-D__printf__(x)=" "-D__inline__="
    "-D__inline=" "-D_Nullable=" "-D_Nonnull=" "-DX2CCPP"
    "-D__restrict=" "-D__extension__=" "-Wno-unicode"
    "-Wno-invalid-pp-token" "-Wno-pragma-once-outside-header"
    @{!expand_system_headers && t.keep_system_includes > 0
      ? %("-fkeep-system-includes") : NULL}
    @{expand_system_headers ? %("-D_Atomic(T)=T") : NULL}
    "-I" "." @{_includes(x2c_cpp_include_dirs())} @{_includes(include_dirs)}
    @{t.cpp_args} @{macros ? %("-imacros" $macros) : NULL}
    @{scratch ? %("-MMD" "-MF" $depfile "-MT" "x2c-dependencies") : NULL}
    $source);
  if (t.verbose) _print_action(<preprocess>, arguments);
  int result = tool_capture(arguments, output, errors);
  /* The dependency file is consumed and removed even after host failure. The
     returned status tells the caller whether stdout is usable. */
  if (scratch) {
    try *dependencies = Path.read_text(depfile);
    catch %(not-found *): {}
    scratch.remove_tree();
  }
  return result;
}
