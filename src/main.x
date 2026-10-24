/*  main.x -- x2c command dispatch

    Copyright (c) 2025 Gary William Flake
*/

#pragma once
#include "cli/cli.x"
#include "frontend.x"
#include "translation.x"
#include "toolchain.x"
#include "logger.x"
#include "utils.x"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static macro Stmt $fail.main_env_unknown(Expr $wanted) =>
  Diagnostics.driver_error(%"unknown env name '${$wanted}'");

static macro Stmt $fail.main_external_failed(Expr $path) =>
  Diagnostics.driver_error(
    %"cannot run external command '${$path}': ${String.new(strerror(errno))}");

static macro Stmt $fail.main_diagnostics_unwritable(Expr $diagnostics) =>
  Diagnostics.driver_error(%"cannot open diagnostics file '${$diagnostics}'");

// environment

/* `x2c env` prints every resolved value as `name = value`, or one bare value
   when a name is given. Package roots join with `:` like `PATH`. */
static int _run_env(CliRequest request) {
  String wanted = NULL;
  if (request.inputs) wanted = request.inputs.car();
  foreach (List row in _env_rows(request)) {
    String (name, value) = row;
    const char *text = value ? value : "";
    if (!wanted) printf("%s = %s\n", name, text);
    else if (name == wanted) {
      printf("%s\n", text);
      return 0;
    }
  }
  if (wanted) $fail.main_env_unknown(wanted);
  return 0;
}

// The resolved values in print order. An absent value prints empty.
static List _env_rows(CliRequest request) {
  Toolchain toolchain = Toolchain.new(request);
  String executable = x2c_get_executable();
  String roots = ":".join(request.package_roots());
  Compiler.configure_interfaces(request.out_dir, 0);
  return %(
    ("home" ${x2c_get_root()})
    ("executable" $executable)
    ("libexec" ${Compiler.home_libexec()})
    ("identity" ${Compiler.identity()})
    ("include_dir" ${toolchain.include_dir})
    ("runtime_lib" ${toolchain.runtime_lib})
    ("prelude" ${Compiler.prelude_interface()})
    ("package_dirs" $roots)
    ("cc" ${toolchain.cc})
    ("ar" ${toolchain.ar})
    ("cache_dir" ${Compiler.cache_root()}));
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
  if (!_external_name(name) || CliRequest.is_builtin(name)) return NULL;
  return Compiler.command_path(String.new(name));
}

static int _external_name(const char *name) {
  if (!name || !isalpha((unsigned char) *name)) return 0;
  for (const char *p = name + 1; *p; p++)
    if (!isalnum((unsigned char) *p) && *p != '-' && *p != '_') return 0;
  return 1;
}

static void _exec(String path, char **args) {
  foreach (String (name, value) in Compiler.command_environment())
    setenv(name, value, 1);
  args[0] = path;
  execv(path, args);
  $fail.main_external_failed(path);
}

/* Initial argument reading belongs to the driver. The command receives that
   exact vector, so response files are never expanded a second time. */
static void _run_command(Array arguments) {
  if (!arguments.len()) return;
  String operation = arguments[0];
  String command = NULL;
  switch (operation) {
    case "build": case "run": case "script": command = "build"; break;
    case "new": command = "new"; break;
    case "install": case "remove": case "list": command = "package"; break;
    default: return;
  }
  String path = Compiler.command_path(command);
  if (!path) {
    if (command != "build") CliRequest.parse_arguments(arguments);
    Diagnostics.driver_error(
      %"missing x2c-$command command; install the matching x2c commands");
  }
  char **args = xcalloc(arguments.len() + 3, sizeof(char *));
  args[1] = "--driver-arguments";
  for (int i = 0; i < arguments.len(); i++) {
    String argument = arguments[i];
    args[i + 2] = argument ? argument : "";
  }
  _exec(path, args);
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
  if (argc > 1) _run_external(argc, argv);
  Array arguments = auto CliRequest.read_arguments(argc, argv);
  _run_command(arguments);
  CliRequest request = CliRequest.parse_arguments(arguments);
  String diagnostics = request.diagnostics_file;
  if (diagnostics && !diagnostics_write_json(diagnostics))
    $fail.main_diagnostics_unwritable(diagnostics);
  report_configure(
    request.quiet, request.plain, request.color_mode,
    request.verbose || request.debugging,
    request.dry_run, request.inspects());
  if (request.command == <env>) return _run_env(request);
  return _run_compiler(request);
}

/* A translation runs inside the command Context. */
static int _run_compiler(CliRequest request) {
  _configure_logging(request.debugging);
  /* Initialize process caches above the command Context so its cleanup cannot
     invalidate their canonical values. */
  Frontend.load_support(request);
  /* Reclaim command-owned Scope allocations and canonical values. */
  Context command = Context.open_isolated_named("compiler command");
  int status = translate_request(request, NULL, NULL, NULL);
  command.close();
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
