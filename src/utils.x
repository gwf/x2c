/*  utils.x -- System utilities for environment discovery and child processes

    Copyright (c) 2025 Gary William Flake

    Finds the repository, prints the driver's fatal error line, and starts
    child processes. Process paths remain argv data; stdout, stderr, and the
    child status are captured independently.
  */

#pragma once
$(import "../lib/private-keywords.xmacro")

/** Holds a `Scope`-owned child process and its stdout and stderr captures.
    `process_start` records a successful child with a nonnegative `pid` and a
    local start failure with `pid == -1` and `start_error`. Only successful
    capture setup leaves live streams for `ChildProcess.wait`; such a child
    must be waited exactly once.
*/
typedef struct ChildProcess {
  long pid;
  int finished, status;
  File output, errors, String start_error;
} *ChildProcess;

/** Initializes compiler paths and default include `List`s once.
    The executable is resolved from the host, `argv0`, or `PATH`; repository
    discovery then walks from that path and the current directory before
    falling back to `.`. An already configured root leaves all state unchanged.
*/
void x2c_initialize_environment(const char *argv0) {
  if (x2c_root_path) return;
  char exec_path[PATH_MAX] = { 0 };
  if (_resolve_executable_path(argv0, exec_path, sizeof(exec_path)))
    x2c_executable_path = exec_path;
  char root_path[PATH_MAX] = { 0 };
  if (!_locate_repo_root(exec_path, root_path, sizeof(root_path))) {
    char *cwd = getcwd(NULL, 0);
    if (cwd) {
      _locate_repo_root(cwd, root_path, sizeof(root_path));
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

/** Returns the directory part of `path`, or "." when it has no slash. */
String x2c_path_dir(String path) {
  int slash = path.rfind("/");
  if (slash < 0) return %".";
  return slash ? path[:slash] : %"/";
}

/** Returns the final path component without its final extension.
    A leading dot belongs to the name, so `.x2crc` keeps its spelling while
    `parse.x` becomes `parse`. A null or empty final component returns the
    empty `String`.
*/
String x2c_path_stem(String path) {
  String base = path.split("/").last(), int dot = base.rfind(".");
  return dot > 0 ? base[:dot] : base;
}

/** Returns the package directory containing `path` below a registered root.
    Callers establish path identity and own any package-name restrictions.
*/
String x2c_package_directory(String root, String path) {
  String prefix = %"$root/";
  if (!path.startswith(prefix)) return NULL;
  int slash = path[prefix.len():].find("/");
  return slash > 0 ? path[:prefix.len() + slash] : NULL;
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
    Returns NULL before environment setup.
*/
List x2c_cpp_include_dirs(void) => x2c_repo_cpp_include_dirs;

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

static int _is_repo_root(const char *path) {
  char probe[PATH_MAX];
  if (!_dir_exists(path)) return 0;
  snprintf(probe, sizeof(probe), "%s/src", path);
  if (!_dir_exists(probe)) return 0;
  snprintf(probe, sizeof(probe), "%s/include", path);
  if (!_dir_exists(probe)) return 0;
  snprintf(probe, sizeof(probe), "%s/lib", path);
  return _dir_exists(probe);
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
  if (argv0 && realpath(argv0, out)) return 1;
  if (argv0 && argv0[0] && _resolve_with_path(argv0, out, size)) return 1;
  return 0;
}

static int _locate_repo_root(const char *start, char *out, size_t size) {
  if (!start || !start[0]) return 0;
  char probe[PATH_MAX];
  strncpy(probe, start, sizeof(probe));
  probe[sizeof(probe) - 1] = 0;
  if (!_dir_exists(probe)) _dirname_in_place(probe);
  loop {
    if (_is_repo_root(probe)) {
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
  String include_dir = %"%s/include".printf(root);
  String src_dir = %"%s/src".printf(root), lib_dir = %"%s/lib".printf(root);
  x2c_base_include_dirs = cons(include_dir, NULL);
  x2c_repo_cpp_include_dirs = %( $src_dir $lib_dir );
}

// child processes

static int _cpp_status(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
  return -1;
}

static int _cpp_wait(pid_t pid) {
  int status;
  while (waitpid(pid, &status, 0) < 0) {
    if (errno == EINTR) continue;
    return -1;
  }
  return _cpp_status(status);
}

/* After both regular temporary files open, the parent can wait before reading
   without pipe backpressure. The child duplicates them onto stdout and stderr,
   while the parent retains the original streams until wait consumes them. A
   partial setup failure closes the stream that opened but leaves its field
   recorded, so that failure handle is not safe to wait. */
/** Starts a direct child action. With `capture`, stdout and stderr go to
    separate temporary files; otherwise all standard streams are inherited.
    `argv` must be a NULL-terminated vector with a non-NULL first element and
    need remain valid only through this call. The returned handle is
    `Scope`-owned. An invalid action or fork failure is recorded as `pid == -1`
    with `start_error`; an `execvp` failure is a child exit with status 127.
    Capture setup failure closes any stream that opened, but a partial failure
    leaves that closed field recorded and does not produce a waitable handle.
*/
ChildProcess process_start(char **argv, int capture) {
  ChildProcess process = Scope.calloc(1, sizeof(struct ChildProcess));
  if (!argv || !argv[0]) {
    process.pid = -1;
    process.start_error = "invalid empty process action";
    return process;
  }
  if (capture) {
    process.output = tmpfile();
    process.errors = tmpfile();
    if (!process.output || !process.errors) {
      if (process.output) process.output.close();
      if (process.errors) process.errors.close();
      process.pid = -1;
      process.start_error = "unable to create process capture files";
      return process;
    }
  }
  pid_t pid = fork();
  process.pid = pid;
  if (pid == 0) {
    if (capture) {
      int out_fd = process.output.fileno(), err_fd = process.errors.fileno();
      if (dup2(out_fd, STDOUT_FILENO) < 0 || dup2(err_fd, STDERR_FILENO) < 0) {
        dprintf(
          STDERR_FILENO, "x2c: unable to capture child output: %s\n",
          strerror(errno));
        _exit(127);
      }
      if (out_fd != STDOUT_FILENO) close(out_fd);
      if (err_fd != STDERR_FILENO) close(err_fd);
    }
    execvp(argv[0], argv);
    dprintf(
      STDERR_FILENO, "x2c: unable to execute %s: %s\n",
      argv[0], strerror(errno));
    _exit(127);
  }
  if (pid < 0) process.start_error = "unable to fork child process";
  return process;
}

/** Checks whether an owned child has finished, without blocking. Reaps only
    this child and retains its status for `wait`, which must still be called
    exactly once to consume captured streams. Start and wait failures are
    ready results; partial capture setup remains invalid input to `wait`.
*/
int ChildProcess.ready(ChildProcess c) {
  if (c.pid < 0 || c.finished) return 1;
  int status;
  pid_t pid;
  do pid = waitpid((pid_t) c.pid, &status, WNOHANG);
  while (pid < 0 && errno == EINTR);
  if (!pid) return 0;
  c.status = pid < 0 ? -1 : _cpp_status(status);
  c.finished = 1;
  return 1;
}

/** Waits for `process`, then reads and closes its captured streams.
    Both output pointers are required and are cleared before validation. On a
    returning call they receive canonical `String`s or the empty `String`. The
    result is the exit status, `128 + signal`, or -1 for invalid arguments, an
    invalid action, fork failure, or wait failure. An `execvp` failure returns
    127 with its diagnostic in `errors`; an invalid action or fork failure
    places `start_error` there instead. A partial capture setup failure is not
    a valid input to this method.

    Raises: `<io-fail>`, `<bad-arg>`, `<size-limit>`, or `<alloc-fail>` while
    reading either capture as a `String`. A failure may leave capture streams
    open.
*/
int ChildProcess.wait(ChildProcess c, String *output, String *errors) {
  if (output) *output = NULL;
  if (errors) *errors = NULL;
  if (!c || !output || !errors) return -1;
  int result =
    c.finished ? c.status : c.pid < 0 ? -1 : _cpp_wait((pid_t) c.pid);
  if (c.output) {
    c.output.rewind();
    *output = c.output.string();
    c.output.close();
  }
  if (c.errors) {
    c.errors.rewind();
    *errors = c.errors.string();
    c.errors.close();
  }
  if (c.start_error) *errors = c.start_error;
  return result;
}

/** Starts and waits for one direct child action.
    After capture setup succeeds, output, status, and failure behavior follow
    `process_start` and `ChildProcess.wait`. A partial capture setup failure
    returns no defined status; its closed field remains recorded.
*/
int process_run(char **argv, String *output, String *errors) {
  ChildProcess process = process_start(argv, 1);
  return process.wait(output, errors);
}

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
int worker_wait(long pid) => _cpp_wait((pid_t) pid);

/** Hashes unit filename spelling for stable generated C identifiers. */
String x2c_filename_hash(String filename) {
  unsigned hash = 0;
  foreach (char byte, filename) hash = hash * 31 + (unsigned char) byte;
  return %"%08X".printf(hash);
}
