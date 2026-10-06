/*  script.x -- Build-once execution of x2c scripts

    Copyright (c) 2026 Gary William Flake.

    `x2c script` builds each script into its own directory under the
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

static macro Stmt $report.script.source_missing(Expr $script) {
  driver_error(%"script does not exist: ${$script}");
}

static macro Stmt $report.script.execute_failed(Expr $executable) {
  driver_error(%"cannot run ${$executable}: ${String.new(strerror(errno))}");
}

/* cache entries

   A script's entry under the cache root is `scripts/STEM-HASH`. Its files
   include the executable `run`, the script's path in `source`, and `lock`,
   which one build of the script holds at a time. */

/** Returns the per-user cache root: `X2C_CACHE_DIR`, `XDG_CACHE_HOME/x2c`,
    or `~/.cache/x2c`, whichever is set first, or NULL when none is.
*/
String script_cache_root(void) {
  String explicit = Env.get("X2C_CACHE_DIR"), xdg = Env.get("XDG_CACHE_HOME");
  String home = Env.get("HOME");
  return explicit ? explicit : xdg ? %"$xdg/x2c" :
         home ? %"$home/.cache/x2c" : NULL;
}

/** Points `request` at its script's cache directory and executes the cached
    executable when it is current; that path does not return. Otherwise it
    locks the directory against concurrent builds of the same script, removes
    the entries of scripts that no longer exist, and returns 0; the caller
    builds `request` and calls `script_run`. A `--clean` request removes the
    script's entry and returns 1.
*/
int script_prepare(CliRequest c) {
  String root = script_cache_root();
  if (!root) driver_error("no cache directory: set X2C_CACHE_DIR");
  String script = Path.absolute(c.inputs.car());
  c.build_dir = _entry(root, script);
  if (c.clean) {
    _clean(c.build_dir);
    return 1;
  }
  if (!Path.is_file(script))
    $report.script.source_missing(script);
  _configure(c, script);
  if (c.dry_run) return 0;
  _exec_current(c);
  try Path.make_dirs(c.build_dir);
  catch %(io-fail *detail): host_error(detail);
  // This process holds the lock until it ends or executes the script.
  file_lock(%"${c.build_dir}/lock", 1);
  // A build of the same script may have finished while this one waited.
  _exec_current(c);
  Path.write_text(%"${c.build_dir}/source", script);
  _prune(%"$root/scripts");
  c.output = %"${c.output}.${"%ld".printf((long) getpid())}";
  return 0;
}

/* The stem is interpolated, never a format: a path may contain a percent. */
static String _entry(String root, String script) {
  String stem = Path.stem(script), digest = "%08x".printf(String.hash(script));
  return %"$root/scripts/$stem-$digest";
}

/* Removes the entry once no build holds it. */
static void _clean(String entry) {
  if (!Path.is_dir(entry)) return;
  int lock = file_lock(%"$entry/lock", 1);
  try Path.remove_tree(entry);
  catch %(io-fail *detail): host_error(detail);
  close(lock);
}

/* The request builds the one script into the entry's executable, quietly
   unless it is verbose. */
static void _configure(CliRequest c, String script) {
  c.inputs = %($script);
  c.state_seed = "direct";
  if (!c.verbose) c.quiet = 1;
  c.output = _executable(c);
}

static String _executable(CliRequest c) => %"${c.build_dir}/run";

/* Unless the request rebuilds, a current entry's executable runs in place
   of this process. */
static void _exec_current(CliRequest c) {
  if (!c.rebuild && c.script_current(c.build_dir)) _exec(c);
}

/* Removes each cache entry under `scripts` whose recorded script no longer
   exists and that no other run holds.
*/
static void _prune(String scripts) {
  foreach (String name, Path.list_dir(scripts)) {
    String directory = Path.join(scripts, name);
    Path source = %"$directory/source";
    if (!source.is_file() || Path.is_file(source.read_text())) continue;
    int lock = file_lock(%"$directory/lock", 0);
    if (lock < 0) continue;
    try Path.remove_tree(directory);
    catch %(io-fail *): {}
    close(lock);
  }
}

// running a script

/** Executes a script that `script_prepare` pointed at the cache and the
    caller built; that path does not return. A dry run prints the action and
    returns zero.
*/
int script_run(CliRequest c) {
  if (!c.dry_run) _exec(c);
  _print_run(c);
  return 0;
}

/* Replaces this process with the entry's executable, whose `argv[0]` is
   the script's path. */
static void _exec(CliRequest c) {
  String executable = _executable(c);
  if (c.verbose) _print_run(c);
  char **argv = Scope.calloc(c.run_args.len() + 2, sizeof(char *));
  int n = 0;
  argv[n++] = c.inputs.car().str();
  // An empty word is a NULL String, which would end the vector early.
  foreach (String argument, c.run_args) argv[n++] = argument ? argument : "";
  fflush(NULL);
  execv(executable, argv);
  $report.script.execute_failed(executable);
}

/* Prints the command that executes the script, without running it. */
static void _print_run(CliRequest c) {
  tool_action_new(<run>, %(${_executable(c)} @{c.run_args}), 0, 1).start();
}
