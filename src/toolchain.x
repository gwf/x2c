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
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "report.x"
#include "utils.x"

static String _tool_selection(
  String explicit, const char *preferred_env, const char *fallback_env,
  String installed, const char *fallback) {
  if (explicit) return explicit;
  const char *value = getenv(preferred_env);
  if (value && *value) return String.new(value);
  value = getenv(fallback_env);
  if (value && *value) return String.new(value);
  if (installed) return installed;
  return String.new(fallback);
}

static String _installed_tool(const char *name) {
  String home = x2c_get_root();
  if (!home || home == ".") return NULL;
  String path = %"$home/lib/x2c/toolchain", File input = fopen(path, "r");
  if (!input) return NULL;
  char line[PATH_MAX], String result = NULL, int name_length = strlen(name);
  while (fgets(line, sizeof(line), input)) {
    if (strncmp(line, name, name_length) != 0 || line[name_length] != '=')
      continue;
    char *value = line + name_length + 1;
    value[strcspn(value, "\r\n")] = 0;
    if (*value) result = String.new(value);
    break;
  }
  input.close();
  return result;
}

/* A staged compiler links its stage-local runtime. A compiler with a home,
   checkout or installed prefix alike, uses `<home>/lib/libx2c.a` or the
   checkout's bootstrap fallback. Without a home, the layout is read from
   the executable's own prefix. No compiler links an unrelated runtime.
*/
static void _toolchain_layout(String *include_dir, String *runtime_lib) {
  String root = x2c_get_root(), executable = x2c_get_executable();
  String stage_dir = executable ? executable.dirname() : NULL;
  if (stage_dir && stage_dir.dirname() == %"$root/builds") {
    *include_dir = %"$root/include/x2c";
    *runtime_lib = %"$stage_dir/libx2c.a";
    return;
  }
  if (root && root != ".") {
    *include_dir = %"$root/include/x2c";
    String installed = %"$root/lib/libx2c.a";
    *runtime_lib = !access(installed, R_OK) ?
                       installed :
                       %"$root/bootstrap/lib/libx2c.a";
    return;
  }
  String bin_dir = executable ? executable.dirname() : %".";
  String prefix = bin_dir.dirname();
  *include_dir = %"$prefix/include/x2c";
  *runtime_lib = %"$prefix/lib/libx2c.a";
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
  Toolchain toolchain = Scope.calloc(1, sizeof(struct Toolchain));
  toolchain.cc = _tool_selection(
    cc, "X2C_CC", "CC", _installed_tool("CC"), "cc");
  toolchain.ar = _tool_selection(
    ar, "X2C_AR", "AR", _installed_tool("AR"), "ar");
  toolchain.cpp_args = cpp_args;
  toolchain.cc_args = cc_args;
  toolchain.ld_args = ld_args;
  toolchain.verbose = verbose;
  toolchain.dry_run = dry_run;
  _toolchain_layout(&toolchain.include_dir, &toolchain.runtime_lib);
  return toolchain;
}

static void _append_list(Array output, List values) {
  foreach (Var value, values) output.push(value);
}

static Array _compile_arguments(Toolchain toolchain, List gen_dirs) {
  Array arguments = %[];
  arguments.push(toolchain.cc);
  arguments.push("-fsigned-char");
  foreach (String directory, gen_dirs) {
    arguments.push("-iquote");
    arguments.push(directory);
  }
  arguments.push("-iquote");
  arguments.push(toolchain.include_dir);
  _append_list(arguments, toolchain.cc_args);
  return arguments;
}

/** Builds but does not start one C compilation action.
    Generated include directories precede the x2c include directory and
    configured compiler arguments. The action requests dependency output at
    `depfile` with `object` as its target.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.compile_action(
  Toolchain toolchain, String source, String object, String depfile,
  List gen_dirs) {
  Array arguments = _compile_arguments(toolchain, gen_dirs);
  arguments.push("-MMD");
  arguments.push("-MP");
  arguments.push("-MF");
  arguments.push(depfile);
  arguments.push("-MT");
  arguments.push(object);
  arguments.push("-c");
  arguments.push(source);
  arguments.push("-o");
  arguments.push(object);
  return tool_action_new(
    <compile>, arguments.list_free(), toolchain.verbose, toolchain.dry_run);
}

/** Captures the native preprocessor view used to identify reusable objects.
    Uses the compilation's native flags and include order, retaining line
    markers so source locations also belong to the identity.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.preprocess_action(
  Toolchain toolchain, String source, String output, List gen_dirs) {
  Array arguments = _compile_arguments(toolchain, gen_dirs);
  arguments.push("-E");
  arguments.push(source);
  arguments.push("-o");
  arguments.push(output);
  return tool_action_new(
    <preprocess>, arguments.list_free(), toolchain.verbose, toolchain.dry_run);
}

/** Builds but does not start an `ar rcs` action in object-list order.
    The action does not remove an existing archive, so callers requiring exact
    membership must unlink `output` before it runs.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.archive_action(
  Toolchain toolchain, String output, List objects) {
  Array arguments = %[];
  arguments.push(toolchain.ar);
  arguments.push("rcs");
  arguments.push(output);
  _append_list(arguments, objects);
  return tool_action_new(
    <archive>, arguments.list_free(), toolchain.verbose, toolchain.dry_run);
}

/** Builds but does not start a host-compiler link action.
    Input order is preserved; configured linker arguments, the matching x2c
    runtime archive, and `-lm` follow the inputs.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.link_action(
  Toolchain toolchain, String output, List inputs) {
  Array arguments = %[];
  arguments.push(toolchain.cc);
  _append_list(arguments, inputs);
  _append_list(arguments, toolchain.ld_args);
  arguments.push(toolchain.runtime_lib);
  arguments.push("-lm");
  arguments.push("-o");
  arguments.push(output);
  return tool_action_new(
    <link>, arguments.list_free(), toolchain.verbose, toolchain.dry_run);
}

/** Creates a `Scope`-owned action that reports nonzero status by default.
    The action retains `arguments` without copying them.

    Raises: `<alloc-fail>` when the action cannot be allocated.
*/
ToolAction tool_action_new(
  Symbol phase, List arguments, int verbose, int dry_run) {
  ToolAction action = Scope.calloc(1, sizeof(struct ToolAction));
  action.phase = phase;
  action.arguments = arguments;
  action.verbose = verbose;
  action.dry_run = dry_run;
  action.report = 1;
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
  long error = detail.assoc(Symbol.new("errno")).integer();
  String reason = String.new(strerror((int) error));
  return %"x2c: unable to execute $program: $reason\n";
}

/* A tool that cannot start reports like a child that exited 127, the status
   a shell gives a missing program, so every caller keeps one failure path. */
static Job _start_tool(List command, String program, String *failure) {
  Job job = NULL;
  try job = command.start();
  catch %(not-found *detail): *failure = _start_failure(program, detail);
  catch %(io-fail *detail): *failure = _start_failure(program, detail);
  return job;
}

static int _run_captured(List arguments, String *output, String *errors) {
  List command = arguments.options(%{stdout: capture, stderr: capture});
  Job job = _start_tool(command, arguments.car(), errors);
  if (!job) return 127;
  int status = job.wait();
  *output = job.output();
  *errors = job.errors();
  return status;
}

/** Returns the directories the C compiler searches for headers and libraries
    without explicit options, as it reports them, plus the `lib` directory
    beside each reported `include` directory. A compiler that reports none
    contributes none.
*/
List Toolchain.search_directories(Toolchain toolchain) {
  Array directories = %[];
  List flags = toolchain.cc_args;
  String output = NULL, errors = NULL;
  if (!_run_captured(%(${toolchain.cc} @flags "-E" "-v" "-x" "c" "/dev/null"),
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
        directories.push(directory.dirname().join_path("lib"));
    }
  }
  if (!_run_captured(%(${toolchain.cc} @flags "-print-search-dirs"),
                     &output, &errors))
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
  List command = action.inherit_stdio ? action.arguments :
    action.arguments.options(%{stdout: capture, stderr: capture});
  execution.job = _start_tool(
    command, action.arguments.car(), &execution.start_error);
  return execution;
}

/** Checks whether an execution can be waited without blocking. A dry run
    and a tool that could not start are ready immediately.
*/
int ToolRun.ready(ToolRun execution) =>
  !execution.job || execution.job.ready();

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
  int status = job ? job.wait() : 127;
  String output = job ? job.output() : NULL;
  String errors = job ? job.errors() : execution.start_error;
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

static void _append_includes(Array arguments, List dirs) {
  foreach (Var value, dirs) {
    if (value is not <string>) continue;
    arguments.push("-I");
    arguments.push(value);
  }
}

/** Runs the configured C preprocessor without a shell.
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
  Toolchain toolchain, const char *fname, List include_dirs,
  const char *imacros, String *output, String *errors, String *dependencies) {
  if (output) *output = NULL;
  if (errors) *errors = NULL;
  if (dependencies) *dependencies = NULL;
  if (!fname || !output || !errors) return -1;
  if (!toolchain.keep_system_includes) {
    String probe_output = NULL, probe_errors = NULL;
    toolchain.keep_system_includes = _run_captured(
      %(${toolchain.cc} "-E" "-x" "c" "-fkeep-system-includes" "/dev/null"),
      &probe_output, &probe_errors) == 0 ? 1 : -1;
  }
  char *base[] = {
    "-E", "-P", "-x", "c",
    "-D__asm(x)=", "-D__asm__(x)=", "-D__attribute__(x)=",
    "-D__format__(x)=", "-D__printf__(x)=", "-D__inline__=",
    "-D__inline=", "-D_Nullable=", "-D_Nonnull=", "-DX2CCPP",
    "-D__restrict=", "-D__extension__=", "-Wno-unicode",
    "-Wno-invalid-pp-token", "-Wno-pragma-once-outside-header"
  };
  List repo_dirs = x2c_cpp_include_dirs();
  Array arguments = %[], char dependency_path[] = "/tmp/x2c-cpp-deps-XXXXXX";
  if (dependencies) {
    int fd = mkstemp(dependency_path);
    if (fd < 0) {
      *errors = "unable to create preprocessor dependency file";
      return -1;
    }
    close(fd);
  }
  arguments.push(toolchain.cc);
  for (int i = 0; i < sizeof(base) / sizeof(base[0]); i++)
    arguments.push(base[i]);
  if (toolchain.keep_system_includes > 0)
    arguments.push("-fkeep-system-includes");
  arguments.push("-I");
  arguments.push(".");
  _append_includes(arguments, repo_dirs);
  _append_includes(arguments, include_dirs);
  foreach (Var argument, toolchain.cpp_args) arguments.push(argument);
  if (imacros) {
    arguments.push("-imacros");
    arguments.push(imacros);
  }
  if (dependencies) {
    arguments.push("-MMD");
    arguments.push("-MF");
    arguments.push(dependency_path);
    arguments.push("-MT");
    arguments.push("x2c-dependencies");
  }
  arguments.push(fname);
  List argument_list = arguments.list_free();
  if (toolchain.verbose) _print_action(<preprocess>, argument_list);
  int result = _run_captured(argument_list, output, errors);
  /* The dependency file is consumed and its unlink attempted even after host
     failure. The returned status tells the caller whether stdout is usable. */
  if (dependencies) {
    File dep = fopen(dependency_path, "r");
    if (dep) {
      try *dependencies = dep.string_close();
      catch %(io-fail *): *dependencies = NULL;
    }
    unlink(dependency_path);
  }
  return result;
}
