/*  utils.x -- System utilities for environment discovery and workers

    Copyright (c) 2025 Gary William Flake

    Finds the repository, prints the driver's fatal error line, and forks
    translation workers. Host tools run through `lib/process.x`.
  */

#pragma once
$(import "../lib/private-keywords.xmacro")

/** Initializes compiler paths and default include `List`s once.
    The executable is resolved from the host, `argv0`, or `PATH`. The home is
    `X2C_HOME` as given when set; otherwise discovery walks from the
    executable and then from the current directory to a directory holding
    `include/` and `etc/compiler-sdk.xlisp`, a source checkout or an
    installed prefix alike, before falling back to `.`. An already configured
    root leaves all state unchanged.
*/
void x2c_initialize_environment(const char *argv0) {
  if (x2c_root_path) return;
  char exec_path[PATH_MAX] = { 0 };
  if (_resolve_executable_path(argv0, exec_path, sizeof(exec_path)))
    x2c_executable_path = exec_path;
  char root_path[PATH_MAX] = { 0 };
  const char *home = getenv("X2C_HOME");
  if (home && *home) {
    snprintf(root_path, sizeof(root_path), "%s", home);
    _strip_trailing_slash(root_path);
  }
  else if (!_locate_home(exec_path, root_path, sizeof(root_path))) {
    char *cwd = getcwd(NULL, 0);
    if (cwd) {
      _locate_home(cwd, root_path, sizeof(root_path));
      free(cwd);
    }
  }
  if (root_path[0]) x2c_root_path = root_path;
  if (!x2c_root_path) x2c_root_path = ".";
  _prepare_repo_defaults();
}

/** Overrides the repository root and rebuilds its default include `List`s.
    `root` is retained without copying. It and the rebuilt values must remain
    valid until the next override or the process no longer uses them.
*/
void x2c_set_root(String root) {
  x2c_root_path = root;
  x2c_base_include_dirs = NULL;
  x2c_repo_cpp_include_dirs = NULL;
  _prepare_repo_defaults();
}

/** Returns the borrowed repository root, or NULL before it is configured. */
String x2c_get_root(void) => x2c_root_path;

/** Returns the borrowed resolved executable path, or NULL when unavailable. */
String x2c_get_executable(void) => x2c_executable_path;

/** Returns the package directory containing `path` below a registered root.
    Callers establish path identity and own any package-name restrictions.
*/
String x2c_package_directory(String root, String path) {
  String prefix = %"$root/";
  if (!path.startswith(prefix)) return NULL;
  int slash = path[prefix.len():].find("/");
  return slash > 0 ? path[:prefix.len() + slash] : NULL;
}

/** Reports whether `path` is x2c source: a `.x` file, or a file of any
    other name whose first line is a shebang, which is a script.
*/
int x2c_source_file(String path) {
  if (path.endswith(".x")) return 1;
  if (path.endswith(".c") || path.endswith(".h") || path.endswith(".o") ||
      path.endswith(".a")) return 0;
  FILE *file = fopen(path, "r");
  if (!file) return 0;
  char head[2];
  int shebang = fread(head, 1, 2, file) == 2 && head[0] == '#' &&
                head[1] == '!';
  fclose(file);
  return shebang;
}

/** Recognizes a package's `src/` files or its package-named legacy entry.
    Other files under the package directory are consumers.
*/
int x2c_package_source(String directory, String path) {
  if (path.startswith(%"$directory/src/")) return 1;
  String name = directory[directory.rfind("/") + 1:];
  return path == %"$directory/$name.x";
}

/** Returns the borrowed default include `List` containing `<root>/include`.
    Returns NULL before environment setup.
*/
List x2c_default_include_dirs(void) => x2c_base_include_dirs;

/** Returns the borrowed preprocessor `List` `<root>/src`, then `<root>/lib`.
    `<root>/src` is present only when the home has that directory. Returns
    NULL before environment setup.
*/
List x2c_cpp_include_dirs(void) => x2c_repo_cpp_include_dirs;

/** Returns `<root>/packages` when a discovered home has that directory, or
    NULL for a missing directory or the `.` fallback.
*/
String x2c_home_packages(void) {
  if (!x2c_root_path || x2c_root_path == ".") return NULL;
  String packages = %"$x2c_root_path/packages";
  return _dir_exists(packages) ? packages : NULL;
}

/** Prints `x2c: error: <message>` to stderr and exits with status 2. */
void x2c_driver_error(const char *message) {
  fprintf(stderr, "x2c: error: %s\n", message);
  exit(2);
}

#pragma private

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

// module state

static String x2c_executable_path = NULL, x2c_root_path = NULL;
static List x2c_base_include_dirs = NULL, x2c_repo_cpp_include_dirs = NULL;

static int _dir_exists(const char *path) {
  struct stat st;
  return path && stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static void _strip_trailing_slash(char *path) {
  size_t len = strlen(path);
  while (len > 1 && path[len - 1] == '/') path[--len] = 0;
}

static void _dirname_in_place(char *path) {
  _strip_trailing_slash(path);
  char *slash = strrchr(path, '/');
  if (!slash) {
    strcpy(path, ".");
    return;
  }
  if (slash == path) {
    path[1] = 0;
    return;
  }
  *slash = 0;
}

static int _is_home(const char *path) {
  char probe[PATH_MAX];
  snprintf(probe, sizeof(probe), "%s/include", path);
  if (!_dir_exists(probe)) return 0;
  snprintf(probe, sizeof(probe), "%s/etc/compiler-sdk.xlisp", path);
  return access(probe, R_OK) == 0;
}

// environment discovery

static int _resolve_with_path(const char *name, char *out, size_t size) {
  char *env = getenv("PATH");
  if (!env) return 0;
  char *paths = strdup(env);
  if (!paths) return 0;
  int found = 0;
  for (char *dir = strtok(paths, ":"); dir; dir = strtok(NULL, ":")) {
    if (!dir[0]) continue;
    char candidate[PATH_MAX];
    snprintf(candidate, sizeof(candidate), "%s/%s", dir, name);
    if (access(candidate, X_OK) != 0) continue;
    if (realpath(candidate, out)) {
      found = 1;
      break;
    }
  }
  free(paths);
  return found;
}

static int _resolve_executable_path(
  const char *argv0, char *out, size_t size) {
  ssize_t len = readlink("/proc/self/exe", out, size - 1);
  if (len >= 0) {
    out[len] = 0;
    return 1;
  }
  if (!argv0 || !argv0[0]) return 0;
  // A bare name came from PATH; only a path resolves against the cwd.
  if (!strchr(argv0, '/')) return _resolve_with_path(argv0, out, size);
  return realpath(argv0, out) != NULL;
}

static int _locate_home(const char *start, char *out, size_t size) {
  if (!start || !start[0]) return 0;
  char probe[PATH_MAX];
  strncpy(probe, start, sizeof(probe));
  probe[sizeof(probe) - 1] = 0;
  if (!_dir_exists(probe)) _dirname_in_place(probe);
  loop {
    if (_is_home(probe)) {
      strncpy(out, probe, size);
      out[size - 1] = 0;
      return 1;
    }
    if (strcmp(probe, "/") == 0) break;
    _dirname_in_place(probe);
  }
  return 0;
}

static void _prepare_repo_defaults(void) {
  if (!x2c_root_path) return;
  const char *root = x2c_root_path;
  String include_dir = "%s/include/x2c".printf(root);
  String src_dir = "%s/src".printf(root), lib_dir = "%s/lib".printf(root);
  x2c_base_include_dirs = cons(include_dir, NULL);
  x2c_repo_cpp_include_dirs = _dir_exists(src_dir)
    ? %( $src_dir $lib_dir ) : %( $lib_dir );
}

// workers

/** Forks a worker that continues the current program with inherited state.
    Returns zero in the child, its PID in the parent, or -1 on fork failure.
    The call attempts to flush all process streams before the fork so
    successfully flushed bytes cannot be written by both processes. Flush
    failure is ignored. The child must leave through `worker_exit`.
*/
long worker_fork(void) {
  fflush(NULL);
  pid_t pid = fork();
  return pid < 0 ? -1 : (long) pid;
}

/** Attempts to flush process streams and terminates a worker with `status`.
    Flush failure is ignored. This function does not return and does not run
    `atexit` handlers. Those belong to the parent process and would close its
    log and process-lifetime `Scope`s twice.
*/
void worker_exit(int status) {
  fflush(NULL);
  _exit(status);
}

/** Waits once for `pid` and returns its shell-style status.
    Normal exit returns the worker status, a signal returns `128 + signal`, and
    a wait failure returns -1. Interrupted waits are retried.
*/
int worker_wait(long pid) {
  int status;
  while (waitpid((pid_t) pid, &status, 0) < 0)
    if (errno != EINTR) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
}

/** Hashes unit filename spelling for stable generated C identifiers. */
String x2c_filename_hash(String filename) {
  unsigned hash = 0;
  foreach (char byte, filename) hash = hash * 31 + (unsigned char) byte;
  return "%08X".printf(hash);
}
