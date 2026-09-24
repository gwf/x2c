/*  probe.x -- what the gate probe scripts share

    A probe runs from any directory. Its repository root comes from the
    probe's own path, and `X2C`, `CC`, and `AR` in the environment replace
    the stage compiler and host tools.
*/
#include "path.x"
#include "process.x"

/** Returns the repository root above the probe at `program`. */
Path probe_root(char *program) =>
  Path.new(program).absolute().dirname().dirname().dirname();

/** Returns the environment variable `name`, or `fallback` when unset. */
String probe_env(String name, String fallback) {
  String value = Env.get(name);
  return value ? value : fallback;
}

/** Prints `message` on standard error and ends the probe with status 1. */
void probe_fail(String message) {
  Stderr.printf("%s\n", message);
  exit(1);
}

/** Returns the C compiler flags for the mode in `etc/build-mode`, which is
    `debug` when the file is absent. An unknown mode ends the probe with
    status 2.
*/
List probe_mode_flags(Path root) {
  Path file = root.join("etc/build-mode");
  String mode = file.exists() ? file.read_text().strip(NULL) : "debug";
  if (mode == "debug") return %("-g");
  if (mode == "optimize") return %("-O2");
  Stderr.printf("unknown build mode: %s\n", mode);
  exit(2);
}

/** Returns an empty scratch directory `unittest/build/<name>`. */
Path probe_scratch(Path root, String name) {
  Path build = root.join("unittest/build").join(name);
  build.remove_tree();
  build.make_dirs();
  return build;
}
