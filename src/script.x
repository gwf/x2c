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

#pragma private

#include <errno.h>
#include <string.h>
#include <unistd.h>

/** Returns the per-user cache root: `X2C_CACHE_DIR`, `XDG_CACHE_HOME/x2c`,
    or `~/.cache/x2c`, whichever is set first, or NULL when none is.
*/
String script_cache_root(void) {
  String explicit = Env.get("X2C_CACHE_DIR"), xdg = Env.get("XDG_CACHE_HOME");
  String home = Env.get("HOME");
  return explicit ? explicit : xdg ? %"$xdg/x2c" :
         home ? %"$home/.cache/x2c" : NULL;
}

static void _exec(CliRequest c) {
  String executable = %"${c.build_dir}/run";
  if (c.verbose)
    tool_action_new(<run>, %($executable @{c.run_args}), 1, 1).start();
  char **argv = Scope.calloc(c.run_args.len() + 2, sizeof(char *));
  int index = 0;
  argv[index++] = c.inputs.car().str();
  // An empty word is a NULL String, which would end the vector early.
  foreach (String argument, c.run_args)
    argv[index++] = argument ? argument : "";
  fflush(NULL);
  execv(executable, argv);
  x2c_driver_error(
    %"cannot run $executable: ${String.new(strerror(errno))}");
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

/** Points `request` at its script's cache directory and executes the cached
    executable when it is current; that path does not return. Otherwise it
    locks the directory against concurrent builds of the same script, removes
    the entries of scripts that no longer exist, and returns 0; the caller
    builds `request` and calls `script_run`. A `--clean` request removes the
    script's entry and returns 1.
*/
int script_prepare(CliRequest c) {
  String root = script_cache_root();
  if (!root) x2c_driver_error("no cache directory: set X2C_CACHE_DIR");
  String script = Path.absolute(c.inputs.car());
  // The stem is interpolated, never a format: a path may contain a percent.
  String stem = Path.stem(script), digest = "%08x".printf(String.hash(script));
  c.build_dir = %"$root/scripts/$stem-$digest";
  if (c.clean) {
    if (!Path.is_dir(c.build_dir)) return 1;
    int lock = file_lock(%"${c.build_dir}/lock", 1);
    try Path.remove_tree(c.build_dir);
    catch %(io-fail *detail): x2c_host_error(detail);
    close(lock);
    return 1;
  }
  if (!Path.is_file(script))
    x2c_driver_error(%"script does not exist: $script");
  c.inputs = %($script);
  c.state_seed = "direct";
  if (!c.verbose) c.quiet = 1;
  c.output = %"${c.build_dir}/run";
  if (c.dry_run) return 0;
  if (!c.rebuild && c.script_current(c.build_dir)) _exec(c);
  try Path.make_dirs(c.build_dir);
  catch %(io-fail *detail): x2c_host_error(detail);
  file_lock(%"${c.build_dir}/lock", 1);
  if (!c.rebuild && c.script_current(c.build_dir)) _exec(c);
  Path.write_text(%"${c.build_dir}/source", script);
  _prune(%"$root/scripts");
  String pid = "%ld".printf((long) getpid());
  c.output = %"${c.output}.$pid";
  return 0;
}

/** Executes a script that `script_prepare` pointed at the cache and the
    caller built; that path does not return. A dry run prints the action and
    returns zero.
*/
int script_run(CliRequest c) {
  if (!c.dry_run) _exec(c);
  String executable = %"${c.build_dir}/run";
  tool_action_new(<run>, %($executable @{c.run_args}), 0, 1).start();
  return 0;
}
