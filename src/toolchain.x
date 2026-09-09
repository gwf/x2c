/*  toolchain.x -- Host preprocessing, compilation, archive, and link actions

    Copyright (c) 2026 Gary William Flake.

    Resolves host tools and builds typed argv. Every action runs through the
    child-process code in utils.x without a shell.
*/

#pragma once

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

/** Tracks one `Scope`-owned started action and its captured child process.
    After capture setup succeeds, a non-dry execution must be passed to
    `ToolRun.wait` exactly once; a returning wait consumes its stdout and
    stderr files. The borrowed action must remain valid through that wait.
    Partial capture setup leaves a non-waitable execution.
*/
typedef struct ToolRun {
  ToolAction action;
  void *process;
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
  String executable = x2c_get_executable();
  if (!executable) return NULL;
  String prefix = x2c_path_dir(x2c_path_dir(executable));
  String path = %"$prefix/lib/x2c/toolchain", File input = fopen(path, "r");
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

/* A staged compiler links its stage-local runtime. A repository compiler uses
   the root runtime or the bootstrap fallback, and an installed compiler uses
   its prefix. No compiler links an unrelated runtime.
*/
static void _toolchain_layout(String *include_dir, String *runtime_lib) {
  String root = x2c_get_root(), executable = x2c_get_executable();
  String marker = %"/builds/";
  int build = executable ? executable.find(marker) : -1;
  if (build >= 0) {
    String stage_dir = x2c_path_dir(executable);
    *include_dir = %"$root/include";
    *runtime_lib = %"$stage_dir/libx2c.a";
    return;
  }
  if (root && root != %".") {
    *include_dir = %"$root/include";
    String installed = %"$root/lib/libx2c.a";
    *runtime_lib = !access(installed, R_OK) ?
                       installed :
                       %"$root/bootstrap/lib/libx2c.a";
    return;
  }
  String bin_dir = executable ? x2c_path_dir(executable) : %".";
  String prefix = x2c_path_dir(bin_dir);
  *include_dir = %"$prefix/include";
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

/** Builds but does not start one C compilation action.
    Generated include directories precede the x2c include directory and
    configured compiler arguments. The action requests dependency output at
    `depfile` with `object` as its target.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the action.
*/
ToolAction Toolchain.compile_action(
  Toolchain toolchain, String source, String object, String depfile,
  List gen_dirs) {
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

static char **_action_argv(List arguments) {
  int count = arguments.len();
  char **argv = Scope.calloc(count + 1, sizeof(char *)), int index = 0;
  foreach (String argument, arguments) argv[index++] = argument;
  return argv;
}

/** Starts the action without a shell and returns a `Scope`-owned execution.
    Verbose and dry-run actions print their quoted argv to stderr. A dry run
    starts no child. After capture setup succeeds, a non-dry execution must be
    waited exactly once; partial capture setup leaves a non-waitable result.

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
  execution.process = process_start(
    _action_argv(action.arguments), !action.inherit_stdio);
  return execution;
}

/** Checks whether an execution can be waited without blocking. A dry run
    is ready immediately. A completed child retains its status and captures
    until the required `ToolRun.wait` call.
*/
int ToolRun.ready(ToolRun execution) {
  if (execution.action.dry_run) return 1;
  ChildProcess process = execution.process;
  return process.ready();
}

/** Waits once for an execution, forwards its captured streams, and returns its
    shell-style status. Signals return `128 + signal`; an invalid action, fork
    failure, or wait failure returns -1, and a dry run returns 0. Captured
    output goes to stderr; program actions inherit standard streams. An
    execution with partial capture setup is not valid input.

    Raises: `<io-fail>`, `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` while
    reading either capture as a `String`.
*/
int ToolRun.wait(ToolRun execution) {
  ToolAction action = execution.action;
  if (action.dry_run) return 0;
  String output = NULL, errors = NULL;
  ChildProcess process = execution.process;
  int status = process.wait(&output, &errors);
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
    A partial capture setup failure returns no defined status.

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
    Returns the shell-style child status, or -1 for invalid arguments, local
    setup failure, child start failure, or wait failure. Partial capture setup
    returns no defined status. This operation does not consult `dry_run`.

    Raises: `<io-fail>`, `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` while
    constructing arguments or reading captured text.
*/
int Toolchain.preprocess(
  Toolchain toolchain, const char *fname, List include_dirs,
  const char *imacros, const char *force_include, String *output,
  String *errors, String *dependencies) {
  if (output) *output = NULL;
  if (errors) *errors = NULL;
  if (dependencies) *dependencies = NULL;
  if (!fname || !output || !errors) return -1;
  if (!toolchain.keep_system_includes) {
    char *probe[] = {
      toolchain.cc, "-E", "-x", "c", "-fkeep-system-includes",
      "/dev/null", NULL
    };
    String probe_output = NULL, probe_errors = NULL;
    toolchain.keep_system_includes =
      process_run(probe, &probe_output, &probe_errors) == 0 ? 1 : -1;
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
  if (force_include) {
    arguments.push("-include");
    arguments.push(force_include);
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
  int result = process_run(_action_argv(argument_list), output, errors);
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
