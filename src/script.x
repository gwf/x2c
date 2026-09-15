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
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>

/** Returns the per-user cache root: `X2C_CACHE_DIR`, `XDG_CACHE_HOME/x2c`,
    or `~/.cache/x2c`, whichever is set first, or NULL when none is.
*/
String script_cache_root(void) {
  const char *explicit = getenv("X2C_CACHE_DIR");
  if (explicit && *explicit) return String.new(explicit);
  const char *xdg = getenv("XDG_CACHE_HOME");
  if (xdg && *xdg) return %"${String.new(xdg)}/x2c";
  const char *home = getenv("HOME");
  return home && *home ? %"${String.new(home)}/.cache/x2c" : NULL;
}

static void _exec(CliRequest c) {
  String executable = %"${c.build_dir}/run";
  if (c.verbose)
    tool_action_new(<run>, %($executable @{c.run_args}), 1, 1).start();
  char **argv = Scope.calloc(c.run_args.len() + 2, sizeof(char *));
  int index = 0;
  argv[index++] = c.inputs.car().str();
  foreach (String argument, c.run_args) argv[index++] = argument;
  fflush(NULL);
  execv(executable, argv);
  x2c_driver_error(
    %"cannot run $executable: ${String.new(strerror(errno))}");
}

/** Points `request` at its script's cache directory and executes the cached
    executable when it is current; that path does not return. Otherwise it
    locks the directory against concurrent builds of the same script and
    returns, and the caller builds `request` and calls `script_run`.
*/
void script_prepare(CliRequest c) {
  String root = script_cache_root();
  if (!root) x2c_driver_error("no cache directory: set X2C_CACHE_DIR");
  String script = c.inputs.car().string().absolute_path();
  if (!script.is_file()) x2c_driver_error(%"script does not exist: $script");
  c.inputs = %($script);
  c.state_seed = "direct";
  c.build_dir = %"$root/scripts/${script.stem()}-%08x".printf(
    String.hash(script));
  if (!c.verbose) c.quiet = 1;
  c.output = %"${c.build_dir}/run";
  if (c.dry_run) return;
  if (!c.rebuild && c.script_current(c.build_dir)) _exec(c);
  if (!_build_mkdirs(c.build_dir))
    x2c_driver_error(%"cannot create script cache: ${c.build_dir}");
  int lock = open(%"${c.build_dir}/lock", O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  if (lock < 0) x2c_driver_error(%"cannot lock script cache: ${c.build_dir}");
  while (flock(lock, LOCK_EX) && errno == EINTR) {}
  if (!c.rebuild && c.script_current(c.build_dir)) _exec(c);
  c.output = %"${c.output}.%ld".printf((long) getpid());
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
