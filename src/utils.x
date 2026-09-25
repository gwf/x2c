/*  utils.x -- System utilities for environment discovery and workers

    Copyright (c) 2025 Gary William Flake

    Owns the environment the driver modules share: where the executable,
    home, stage, and packages are, how a file is locked or replaced, the
    driver's fatal error line, and translation workers. Host tools run
    through `lib/process.x`.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "path.x"
#include "process.x"
#include "sourceview.x"

/* Initializes ordinary and external command paths with the chosen identity. */
static void _initialize_environment(
  const char *argv0, String embedded_identity) {
  if (x2c_root_path) return;
  x2c_executable_path = _executable(argv0);
  x2c_identity = embedded_identity ? embedded_identity : _identity();
  String home = Env.get("X2C_HOME");
  if (home && !home[0]) home = NULL;
  String root = home ? home.rstrip("/") : _locate_home(x2c_executable_path);
  if (!root) root = _locate_home(Path.absolute("."));
  x2c_root_found = root != NULL;
  x2c_root_path = Path.absolute(root ? root : ".");
  _prepare_repo_defaults();
}

/** Initializes compiler paths and default include `List`s once.
    The executable is resolved from the host, `argv0`, or `PATH`. The home is
    `X2C_HOME` when it is set and not empty; otherwise discovery walks from
    the executable and then from the current directory to a directory holding
    `include/` and `etc/compiler-sdk.xlisp`, a source checkout or an
    installed prefix alike. The root is kept absolute with symbolic links
    resolved, the one spelling every path below the home is compared in.
    Without a home the root is the current directory and `x2c_home` reports
    none. The compiler identity is taken here, before any later work could
    observe a replaced executable. An already configured root leaves all
    state unchanged.
*/
void x2c_initialize_environment(const char *argv0) {
  _initialize_environment(argv0, NULL);
}

/** Initializes an external command with the compiler identity embedded when
    it was built. A driver-supplied identity must match that compiler. */
void x2c_initialize_command_environment(
  const char *argv0, String embedded_identity) {
  String supplied = Env.get("X2C_IDENTITY");
  if (supplied && supplied != embedded_identity) {
    String detail = %"command $embedded_identity, driver $supplied";
    x2c_driver_error(%"compiler identity mismatch: $detail");
  }
  _initialize_environment(argv0, embedded_identity);
}

/** Overrides the repository root and rebuilds its default include `List`s.
    The root is resolved as environment setup resolves it. The rebuilt values
    must remain valid until the next override or the process no longer uses
    them.
*/
void x2c_set_root(String root) {
  x2c_root_path = Path.absolute(root);
  x2c_root_found = 1;
  x2c_base_include_dirs = NULL;
  x2c_repo_cpp_include_dirs = NULL;
  _prepare_repo_defaults();
}

/** Returns the borrowed repository root, or NULL before it is configured.
    The root is absolute with symbolic links resolved, the one spelling
    paths below the home are compared in.
*/
String x2c_get_root(void) => x2c_root_path;

/** Returns the borrowed resolved executable path, or NULL when unavailable. */
String x2c_get_executable(void) => x2c_executable_path;

/** Returns the package directory that holds `path` below one of `roots`:
    the root's child on the way to `path`, compared by canonical path, when
    that child's name is an identifier. Returns NULL for any other path.
*/
String x2c_package_directory(List roots, String path) {
  String source = Path.absolute(path);
  foreach (String root, roots) {
    String prefix = %"${Path.absolute(root)}/";
    if (!source.startswith(prefix)) continue;
    String name = source.remove_prefix(prefix).split("/").car();
    if (name.is_identifier() && source != %"$prefix$name")
      return %"$prefix$name";
  }
  return NULL;
}

/** Resolves the first readable package entry under `roots`, using the same
    source view as the importing compiler. Returns its canonical directory
    through `directory`, or NULL when the package does not exist. */
String x2c_package_entry(
  SourceView sources, List roots, String name, String &directory) {
  foreach (String package_dir, roots) {
    String root = %"${Path.absolute(package_dir)}/$name";
    String nested = %"$root/src/$name.x";
    String entry = sources.exists(nested) ? nested : %"$root/$name.x";
    if (!sources.exists(entry)) continue;
    directory = root;
    return Path.absolute(entry);
  }
  return NULL;
}

/** Reports whether `path` is x2c source: a `.x` or `.xp` file, or a file
    of any other name whose first line is a shebang, which is a script.
*/
int x2c_source_file(String path) {
  if (path.endswith(".x") || path.endswith(".xp")) return 1;
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

/** Reports whether `path` names a file in the indentation syntax. */
int x2c_layout_file(String path) =>
  path && (path.endswith(".xp") || path.endswith(".xpmacro"));

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

/** Returns the discovered or configured home, or NULL when there is none. */
String x2c_home(void) => x2c_root_found ? x2c_root_path : NULL;

/** Returns `<home>/packages`, which may not exist, or NULL without a home. */
String x2c_home_packages(void) {
  String home = x2c_home();
  return home ? %"$home/packages" : NULL;
}

/** Returns the command directory for this checkout or installed home. */
String x2c_home_libexec(void) {
  String stage = x2c_stage_dir();
  if (stage) return %"$stage/libexec";
  String home = x2c_home();
  return home ? %"$home/libexec/x2c" : NULL;
}

/** Returns the directory of a compiler staged at `<home>/builds/<stage>/`,
    or NULL for any other compiler.
*/
String x2c_stage_dir(void) {
  if (!x2c_executable_path) return NULL;
  String stage = Path.dirname(x2c_executable_path);
  return Path.dirname(stage) == %"$x2c_root_path/builds" ? stage : NULL;
}

/** Returns the spelling of the first `PATH` candidate for the program `name`
    that this process may execute, searched as `execvp` searches, or NULL.
    An empty entry names the current directory.
*/
String x2c_find_program(String name) {
  foreach (String directory, Env.get("PATH").split(":")) {
    Path candidate = Path.join(directory, name);
    if (candidate.is_executable()) return candidate;
  }
  return NULL;
}

/** Prints `x2c: error: <message>` to stderr and exits with status 2.
    The streams are flushed and `atexit` handlers do not run, so the call is
    safe inside a `try` body or a catch arm, whose records those handlers
    would otherwise find still live.
*/
void x2c_driver_error(const char *message) {
  fprintf(stderr, "x2c: error: %s\n", message);
  fflush(NULL);
  _exit(2);
}

/** Reports a caught `<not-found>` or `<io-fail>` through `x2c_driver_error`
    as its operation, path or program, and system reason.
*/
void x2c_host_error(List detail) {
  Var subject = detail.assoc(<path>);
  if (subject is void) subject = detail.assoc(<program>);
  long error = detail.assoc(<errno>);
  x2c_driver_error(
    %"${detail.assoc(<operation>)} $subject: ${String.new(strerror(error))}");
}

/** Locks the file `p`, creating it, and returns a descriptor that holds the
    lock until it is closed or the process exits. Returns -1 when `wait` is
    zero and another process holds the lock.
*/
int file_lock(Path p, int wait) {
  int lock = open(p, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  if (lock < 0) x2c_driver_error(%"cannot lock $p");
  int operation = wait ? LOCK_EX : LOCK_EX | LOCK_NB;
  while (flock(lock, operation)) {
    if (errno == EINTR) continue;
    close(lock);
    return -1;
  }
  return lock;
}

/** Replaces each file named in `outputs`, a List of alternating paths and
    texts. Every text is written and closed in a process-specific sibling of
    its path before the first rename, so a failed write replaces no
    destination. The renames then run in order: each destination holds its
    old contents or its new ones, and a failed rename leaves the earlier
    destinations replaced.
    Raises: `<not-found>` or `<io-fail>`, after removing the siblings.
*/
void file_publish(List outputs) {
  String suffix = ".tmp.%ld".printf((long) getpid());
  defer for (List rest = outputs; rest; rest = rest.cddr())
    Path.remove_file(%"${rest.car()}$suffix");
  for (List rest = outputs; rest; rest = rest.cddr())
    Path.write_text(%"${rest.car()}$suffix", rest.cadr());
  for (List rest = outputs; rest; rest = rest.cddr()) {
    String target = rest.car();
    if (rename(%"$target$suffix", target))
      File.path_error(<rename>, target, errno);
  }
}

#pragma private

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <unistd.h>

// module state

static String x2c_executable_path = NULL, x2c_root_path = NULL;
static String x2c_identity = NULL;
static int x2c_root_found = 0;
static List x2c_base_include_dirs = NULL, x2c_repo_cpp_include_dirs = NULL;

// environment discovery

static String _executable(const char *argv0) {
  char buffer[PATH_MAX];
  ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (length >= 0) {
    buffer[length] = 0;
    return String.new(buffer);
  }
  String name = String.new(argv0);
  // A bare name came from PATH; only a path resolves against the cwd.
  if (name && !name.contains("/")) name = x2c_find_program(name);
  return Path.exists(name) ? Path.absolute(name) : NULL;
}

/* Linux names the running image itself, which stays the same file even if
   the executable's path is replaced while the process runs. */
static String _identity(void) {
  String path = Path.exists("/proc/self/exe") ? %"/proc/self/exe"
                                               : x2c_executable_path;
  int ok = path != NULL;
  uint64_t hash = UINT64_C(1469598103934665603);
  if (ok) hash = x2c_fnv_file(hash, path, ok);
  return ok ? "%016llx".printf((unsigned long long) hash) : NULL;
}

static int _is_home(Path p) =>
  p.join("include").is_dir() && p.join("etc/compiler-sdk.xlisp").is_file();

static String _locate_home(Path p) {
  if (!p) return NULL;
  Path directory = p.is_dir() ? p : p.dirname();
  while (!_is_home(directory)) {
    if (directory == "/") return NULL;
    directory = directory.dirname();
  }
  return directory;
}

static void _prepare_repo_defaults(void) {
  if (!x2c_root_path) return;
  String include_dir = %"$x2c_root_path/include/x2c";
  String src_dir = %"$x2c_root_path/src", lib_dir = %"$x2c_root_path/lib";
  x2c_base_include_dirs = cons(include_dir, NULL);
  x2c_repo_cpp_include_dirs = Path.is_dir(src_dir)
    ? %( $src_dir $lib_dir ) : %( $lib_dir );
}

// content identity

/** Returns `hash` extended with `length` `bytes` by 64-bit FNV-1a. */
uint64_t x2c_fnv_bytes(uint64_t hash, const void *bytes, size_t length) {
  const unsigned char *data = bytes;
  for (size_t i = 0; i < length; i++) {
    hash ^= data[i];
    hash *= UINT64_C(1099511628211);
  }
  return hash;
}

/** Returns `hash` extended with the contents of the file at `path`.
    A missing or unreadable file clears `ok`.
*/
uint64_t x2c_fnv_file(uint64_t hash, String path, int &ok) {
  File input = fopen(path, "rb");
  if (!input) {
    ok = 0;
    return hash;
  }
  unsigned char buffer[16384], size_t length;
  while ((length = fread(buffer, 1, sizeof(buffer), input)))
    hash = x2c_fnv_bytes(hash, buffer, length);
  if (ferror(input)) ok = 0;
  input.close();
  return hash;
}

/** Returns the active compiler's identity in 16 hexadecimal digits.
    Ordinary compiler startup hashes its executable with FNV-1a; an external
    command uses the identity embedded from the compiler that built it.
    Returns NULL if ordinary startup could not read its executable.
*/
String x2c_compiler_identity(void) => x2c_identity;

/** Returns the stamp a native module records: `x2c-module-stamp:` and the
    running compiler's identity. Returns NULL when the executable cannot be
    read. Only the compiler that built a module loads it.
*/
String build_module_stamp(void) {
  String identity = x2c_compiler_identity();
  return identity ? %"x2c-module-stamp:$identity" : NULL;
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

/** Waits until one of the `count` workers in `pids` exits and returns its
    index, storing its shell-style status: the exit status, `128 + signal`,
    or -1 when it cannot be waited. Other children stay unreaped, so the
    wait polls with a short sleep.
*/
int worker_wait_any(long *pids, int count, int &status) {
  loop {
    for (int i = 0; i < count; i++) {
      int raw;
      pid_t done = waitpid((pid_t) pids[i], &raw, WNOHANG);
      if (!done || (done < 0 && errno == EINTR)) continue;
      status = done < 0 ? -1 : WIFEXITED(raw) ? WEXITSTATUS(raw) :
                WIFSIGNALED(raw) ? 128 + WTERMSIG(raw) : -1;
      return i;
    }
    usleep(1000);
  }
}

/** Hashes unit filename spelling for stable generated C identifiers. */
String x2c_filename_hash(String filename) {
  unsigned hash = 0;
  foreach (char byte, filename) hash = hash * 31 + (unsigned char) byte;
  return "%08X".printf(hash);
}
