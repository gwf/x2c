/*  script.x -- Build-once execution of scripts and explicit programs

    Copyright (c) 2026 Gary William Flake.

    `x2c script` and `x2c run` build each program into a directory under the
    per-user cache. When everything the executable was built from is
    unchanged, a run executes it before any compiler state loads. Otherwise
    the build runs under a lock on that directory, publishes the executable,
    and executes it.
*/

#pragma once
#include "build.x"

#include <errno.h>
#include <string.h>
#include <unistd.h>

// command reports

static macro Stmt $fail.script_source_missing(Expr $script) =>
  Diagnostics.driver_error(%"script does not exist: $($script)");

static macro Stmt $fail.script_execute_failed(Expr $executable) =>
  Diagnostics.driver_error(
    %"cannot run $($executable): $(String.new(strerror(errno)))");

/* cache entries

   Entries are `scripts/STEM-HASH` or `runs/STEM-HASH` under the cache root.
   Each holds the executable `run`, the first input's path in `source`,
   and `lock`, which one build holds at a time. */

/** Points `c` at its program's cache directory and executes the cached
    executable when it is current; that path does not return. Otherwise it
    locks the directory against concurrent builds, prunes entries whose first
    input no longer exists, and returns 0; the caller builds `c` and calls
    `CliRequest.run_script`. A `--clean` request removes the entry and returns 1.
*/
int CliRequest.prepare_script(CliRequest c) {
  String root = Compiler.cache_root();
  if (!root) Diagnostics.driver_error("no cache directory: set X2C_CACHE_DIR");
  Array inputs = [];
  foreach (String input, c.inputs) inputs.push(Path.absolute(input));
  c.inputs = inputs.list_free();
  String script = c.inputs.car();
  c.build_dir = _entry(root, c);
  if (c.clean) {
    _clean(c.build_dir);
    return 1;
  }
  if ((!c.dry_run || c.command == <script>) && !Path.is_file(script))
    $fail.script_source_missing(script);
  _configure(c);
  if (c.dry_run) return 0;
  _exec_current(c);
  try Path.make_dirs(c.build_dir);
  catch %(io-fail *detail): Diagnostics.host_error(detail);
  // This process holds the lock until it ends or executes the script.
  Path.lock_file(%"$(c.build_dir)/lock", 1);
  // A build of the same script may have finished while this one waited.
  _exec_current(c);
  Path.write_text(%"$(c.build_dir)/source", script);
  Compiler.prune_cache(%"$root/scripts");
  Compiler.prune_cache(%"$root/runs");
  c.output = %"$(c.output).$("%ld".printf((long) getpid()))";
  return 0;
}

/* The stem is interpolated, never a format: a path may contain a percent. */
static String _entry(String root, CliRequest c) {
  String stem = Path.stem(c.inputs.car());
  String digest = "%08x".printf(String.hash("\n".join(c.inputs)));
  String directory = c.command == <script> ? "scripts" : "runs";
  return %"$root/$directory/$stem-$digest";
}

/* Removes the entry once no build holds it. */
static void _clean(String entry) {
  if (!Path.is_dir(entry)) return;
  int lock = Path.lock_file(%"$entry/lock", 1);
  try Path.remove_tree(entry);
  catch %(io-fail *detail): Diagnostics.host_error(detail);
  close(lock);
}

/* Scripts suppress the build receipt unless verbose; runs keep it. */
static void _configure(CliRequest c) {
  c.state_seed = "direct";
  if (c.command == <script> && !c.verbose) c.quiet = 1;
  c.output = _executable(c);
}

static String _executable(CliRequest c) => %"$(c.build_dir)/run";

/* Unless the request rebuilds, a current entry's executable runs in place
   of this process. */
static void _exec_current(CliRequest c) {
  if (!c.rebuild && c.script_current(c.build_dir)) _exec(c);
}

// running a script

/** Executes a script that `CliRequest.prepare_script` pointed at the cache
    and the caller built; that path does not return. A dry run prints the
    action and returns zero.
*/
int CliRequest.run_script(CliRequest c) {
  if (!c.dry_run) _exec(c);
  _print_run(c);
  return 0;
}

/* Replaces this process with the entry's executable, whose `argv[0]` is
   the script's path. */
static void _exec(CliRequest c) {
  String executable = _executable(c);
  if (c.verbose && !c.quiet) _print_run(c);
  char **argv = xcalloc(c.run_args.len() + 2, sizeof(char *));
  int n = 0;
  argv[n++] = c.inputs.car().str();
  // An empty word is a NULL String, which would end the vector early.
  foreach (String argument, c.run_args) argv[n++] = argument ? argument : "";
  fflush(NULL);
  execv(executable, argv);
  $fail.script_execute_failed(executable);
}

/* Prints the command that executes the script, without running it. */
static void _print_run(CliRequest c) {
  ToolAction.new(<run>, $(_executable(c), @(c.run_args)), 0, 1).start();
}
