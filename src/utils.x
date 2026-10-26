/*  utils.x -- System utilities for environment discovery and workers

    Copyright (c) 2025 Gary William Flake

    Owns the environment the driver modules share: where the executable,
    home, stage, and packages are, which files are x2c source, the
    compiler's identity, how a file is locked or replaced, and the
    driver's fatal error line. Host tools run through
    `lib/process.x`.
*/

#pragma once
#include "path.x"
#include "process.x"
#include "sourceview.x"

/* The 64-bit FNV-1a offset basis, which starts every FNV hash. */
#define FNV_OFFSET_BASIS 0xcbf29ce484222325ULL

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <unistd.h>

/** Names the translation state that `src/compiler/compiler.x` defines. */
typedef struct Compiler *Compiler;

/** Names the positioned diagnostic store that `src/diagnostics.x` defines. */
typedef struct Diagnostics *Diagnostics;

// command reports

static macro Stmt $fail.utils_identity_mismatch(Expr $detail) =>
  Diagnostics.driver_error(%"compiler identity mismatch: $($detail)");

static macro Stmt $fail.utils_lock_failed(Expr $p) =>
  Diagnostics.driver_error(%"cannot lock $($p)");

static macro Stmt $fail.utils_host_failed(
  Expr $detail, Expr $subject, Expr $error) =>
  Diagnostics.driver_error(
    %"$($detail.assoc(<operation>)) $($subject): $(
      String.new(strerror($error)))");

static macro Stmt $fail.utils_command_missing(Expr $name) =>
  Diagnostics.driver_error(
    %"missing x2c-$($name) command; install the matching x2c commands");

// environment state

/* Environment setup fills these once per process, and `x2c_set_root` may
   replace the root and its include `List`s. The root is the home when
   `root_found` is set and the current directory otherwise. */
static String executable_path = NULL, root_path = NULL;
static String active_identity = NULL;
static int external_command = 0;
static int root_found = 0;
static List default_includes = NULL, cpp_includes = NULL;

// environment setup

/** Initializes compiler paths and default include `List`s once.
    The executable is resolved from the host, `argv0`, or `PATH`. The home is
    `X2C_HOME` when it is set and not empty; otherwise discovery walks from
    the executable and then from the current directory to a directory holding
    `include/` and `etc/compiler-prelude.x`, a source checkout or an
    installed prefix alike. The root is kept absolute with symbolic links
    resolved, the one spelling every path below the home is compared in.
    Without a home the root is the current directory and `Compiler.home_dir`
    reports none. The compiler identity is taken here, before any later work
    could observe a replaced executable. An already configured root leaves all
    state unchanged.
*/
void x2c_initialize_environment(const char *argv0) {
  _initialize_environment(argv0, NULL);
}

/** Initializes an external command with the compiler identity embedded when
    it was built. A driver-supplied identity must match that compiler.
*/
void x2c_initialize_command_environment(
  const char *argv0, String embedded_identity) {
  String supplied = Env.get("X2C_IDENTITY");
  if (supplied && supplied != embedded_identity) {
    String command = _executable(argv0), driver = Env.get("X2C");
    if (!command) command = String.new(argv0);
    if (!driver) driver = "(unnamed)";
    String detail = %"command $command has $embedded_identity, " +
      %"driver $driver has $supplied";
    $fail.utils_identity_mismatch(detail);
  }
  _initialize_environment(argv0, embedded_identity);
}

static void _initialize_environment(
  const char *argv0, String embedded_identity) {
  if (root_path) return;
  _default_search_path();
  executable_path = _executable(argv0);
  external_command = embedded_identity != NULL;
  active_identity = embedded_identity ? embedded_identity : _identity();
  String home = Env.get("X2C_HOME");
  if (home && !home[0]) home = NULL;
  String root = home ? home.rstrip("/") : _locate_home(executable_path);
  if (!root) root = _locate_home(Path.absolute("."));
  root_found = root != NULL;
  root_path = Path.absolute(root ? root : ".");
  _prepare_include_dirs();
}

/* Without PATH, `execvp` searches the C library's default path, but a host
   tool it starts that way, such as the GCC driver looking for `cc1`, finds
   nothing. Setting that path lets the tools search where `execvp` does. */
static void _default_search_path(void) {
  if (Env.get("PATH")) return;
  char buffer[PATH_MAX];
  size_t length = confstr(_CS_PATH, buffer, sizeof(buffer));
  if (length && length <= sizeof(buffer)) setenv("PATH", buffer, 1);
}

static String _executable(const char *argv0) {
  char buffer[PATH_MAX];
  ssize_t length = readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
  if (length >= 0) {
    buffer[length] = 0;
    return String.new(buffer);
  }
  String name = String.new(argv0);
  // A bare name came from PATH; only a path resolves against the cwd.
  if (name && !("/" in name)) name = Env.find_program(name);
  return Path.exists(name) ? Path.absolute(name) : NULL;
}

/* Linux names the running image itself, which stays the same file even if
   the executable's path is replaced while the process runs. */
static String _identity(void) =>
  Path.content_identity(
    Path.exists("/proc/self/exe") ? "/proc/self/exe" : executable_path);

static String _locate_home(Path p) {
  if (!p) return NULL;
  Path directory = p.is_dir() ? p : p.dirname();
  while (!_is_home(directory)) {
    if (directory == "/") return NULL;
    directory = directory.dirname();
  }
  return directory;
}

static int _is_home(Path p) =>
  p.join("include").is_dir() && p.join("etc/compiler-prelude.x").is_file();

static void _prepare_include_dirs(void) {
  String include_dir = %"$root_path/include/x2c";
  String src_dir = %"$root_path/src", lib_dir = %"$root_path/lib";
  default_includes = cons(include_dir, NULL);
  cpp_includes = Path.is_dir(src_dir) ? $(lib_dir, src_dir) : $(lib_dir);
}

/** Overrides the repository root and rebuilds its default include `List`s.
    The root is resolved as environment setup resolves it. The rebuilt values
    must remain valid until the next override or the process no longer uses
    them.
*/
void x2c_set_root(String root) {
  root_path = Path.absolute(root);
  root_found = 1;
  _prepare_include_dirs();
}

// environment queries

/** Returns the borrowed repository root, or NULL before it is configured.
    The root is absolute with symbolic links resolved, the one spelling
    paths below the home are compared in.
*/
String x2c_get_root(void) => root_path;

/** Returns the borrowed resolved executable path, or NULL when unavailable. */
String x2c_get_executable(void) => executable_path;

/** Returns the matching compiler executable for a recursive translation.
    External commands use the driver's X2C path or their adjacent installed
    compiler. An unavailable or changed compiler returns NULL.
*/
String Compiler.driver_executable(void) {
  if (!external_command) return executable_path;
  String path = Env.get("X2C");
  if (!path) {
    String parent = Path.dirname(executable_path);
    String stage = Path.dirname(parent);
    String prefix = Path.basename(parent) == "x2c"
      ? Path.dirname(stage) : root_path;
    path = Path.dirname(stage) == %"$root_path/builds"
      ? %"$stage/x2c" : %"$prefix/bin/x2c";
  }
  path = Path.absolute(path);
  return Path.content_identity(path) == active_identity ? path : NULL;
}

/** Returns the discovered or configured home, or NULL when there is none. */
String Compiler.home_dir(void) => root_found ? root_path : NULL;

/** Returns the directory of a compiler staged at `<home>/builds/<stage>/`,
    or NULL for any other compiler.
*/
String Compiler.stage_dir(void) {
  String driver = Compiler.driver_executable();
  if (!driver) return NULL;
  String stage = Path.dirname(driver);
  return Path.dirname(stage) == %"$root_path/builds" ? stage : NULL;
}

/** Returns the checked-in bootstrap's runtime directory when this process
    is the bootstrap compiler, or NULL. Its headers and archive match the
    runtime the bootstrap compiler was built with.
*/
String Compiler.bootstrap_runtime_dir(void) {
  String executable = x2c_get_executable();
  if (!executable || !root_path) return NULL;
  return Path.basename(executable) == "x2c-bootstrap" &&
         Path.dirname(executable) == %"$root_path/bin"
       ? %"$root_path/bootstrap/lib" : NULL;
}

/** Returns `<home>/packages`, which may not exist, or NULL without a home. */
String Compiler.home_packages(void) {
  String home = Compiler.home_dir();
  return home ? %"$home/packages" : NULL;
}

/** Returns the command directory for this checkout or installed home. */
String Compiler.home_libexec(void) {
  String stage = Compiler.stage_dir();
  if (stage) return %"$stage/libexec";
  String home = Compiler.home_dir();
  if (!home) {
    String driver = Compiler.driver_executable();
    if (driver) home = Path.dirname(Path.dirname(driver));
  }
  return home ? %"$home/libexec/x2c" : NULL;
}

/** Returns an executable command in this compiler's libexec, or NULL. */
String Compiler.command_path(String name) {
  String libexec = Compiler.home_libexec();
  if (!libexec) return NULL;
  String path = %"$libexec/x2c-$name";
  return Path.is_executable(path) ? path : NULL;
}

/** Returns the home, driver, and identity supplied to external commands. */
Map Compiler.command_environment(void) {
  Map environment = {};
  String home = Compiler.home_dir(), driver = Compiler.driver_executable();
  String identity = Compiler.identity();
  if (home) environment["X2C_HOME"] = home;
  if (driver) environment["X2C"] = driver;
  if (identity) environment["X2C_IDENTITY"] = identity;
  return environment;
}

/** Runs an external command with inherited streams and returns its status.
    Resolves only this compiler's libexec and passes literal arguments without
    a shell. An unavailable command reports an error and exits with status 2.
*/
int Compiler.run_command(String name, List arguments) {
  String path = Compiler.command_path(name);
  if (!path)
    $fail.utils_command_missing(name);
  Map options = {env: Compiler.command_environment(), stdout: <inherit>};
  try return $(path, @arguments).job().options(options).status();
  catch %((!or not-found io-fail) *detail): Diagnostics.host_error(detail);
  return 2;
}

/** Returns the borrowed default include `List`, `<root>/include/x2c`.
    Returns NULL before environment setup.
*/
List Compiler.default_include_dirs(void) => default_includes;

/** Returns the borrowed preprocessor `List` `<root>/lib`, then `<root>/src`.
    `<root>/src` is present only when the home has that directory. Returns
    NULL before environment setup.
*/
List Compiler.cpp_include_dirs(void) => cpp_includes;

/** Returns the spelling of the first `PATH` candidate for the program `name`
    that this process may execute, searched as `execvp` searches, or NULL.
    An empty entry names the current directory.
*/
String Env.find_program(String name) {
  foreach (String directory in Env.get("PATH").split(":")) {
    Path candidate = Path.join(directory, name);
    if (candidate.is_executable()) return candidate;
  }
  return NULL;
}

// source files and packages

/** Reports whether `path` is x2c source: a `.x` or `.xp` file, or a script
    that starts with a shebang. Files ending in `.c`, `.h`, `.o`, or `.a`
    are excluded even when they start with a shebang.
*/
int Path.is_x2c_source(String path) {
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
int Path.is_layout_source(String path) =>
  path && path.endswith(".xp");

/** Returns the package directory that holds `path` below one of `roots`:
    the root's child on the way to `path`, compared by canonical path, when
    that child's name is an identifier. Returns NULL for any other path.
*/
String Compiler.package_directory(List roots, String path) {
  String source = Path.absolute(path);
  foreach (String root in roots) {
    String prefix = %"$(Path.absolute(root))/";
    if (!source.startswith(prefix)) continue;
    String name = source.remove_prefix(prefix).split("/").car();
    if (name.is_identifier() && source != %"$prefix$name")
      return %"$prefix$name";
  }
  return NULL;
}

/** Resolves the first readable package entry under `roots`, preferring `.x`
    to `.xp`, using the importing compiler's source view. Returns its directory
    through `directory`, or NULL when the package does not exist.
*/
String SourceView.package_entry(
  SourceView sources, List roots, String name, String &directory) {
  foreach (String package_dir in roots) {
    String root = %"$(Path.absolute(package_dir))/$name";
    foreach (String suffix in %(".x" ".xp")) {
      String nested = %"$root/src/$name$suffix";
      String entry = sources.exists(nested) ? nested : %"$root/$name$suffix";
      if (!sources.exists(entry)) continue;
      directory = root;
      return Path.absolute(entry);
    }
  }
  return NULL;
}

/** Recognizes a package's `src/` files or its package-named legacy entry.
    Other files under the package directory are consumers.
*/
int Compiler.is_package_source(String directory, String path) {
  if (path.startswith(%"$directory/src/")) return 1;
  String name = directory[directory.rfind("/") + 1:];
  return path == %"$directory/$name.x" || path == %"$directory/$name.xp";
}

// identity

/** Returns the active compiler's identity in 16 hexadecimal digits.
    Ordinary compiler startup hashes its executable with FNV-1a; an external
    command uses the identity embedded from the compiler that built it.
    Returns NULL if ordinary startup could not read its executable.
*/
String Compiler.identity(void) => active_identity;

/** Returns the stamp a native module records: `x2c-module-stamp:` and the
    running compiler's identity. Returns NULL when the executable cannot be
    read. Only the compiler that built a module loads it.
*/
String Compiler.module_stamp(void) {
  String identity = Compiler.identity();
  return identity ? %"x2c-module-stamp:$identity" : NULL;
}

/** Returns the identity a compiler executable at `path` has when it runs:
    the FNV-1a hash of its bytes, or NULL when `path` is NULL or unreadable.
*/
String Path.content_identity(String path) {
  int ok = path != NULL;
  uint64_t hash = FNV_OFFSET_BASIS;
  if (ok) hash = fnv_file(hash, path, ok);
  return ok ? "%016llx".printf((unsigned long long) hash) : NULL;
}

/** Returns `hash` extended with the contents of the file at `path`.
    A missing or unreadable file clears `ok`.
*/
uint64_t fnv_file(uint64_t hash, String path, int &ok) {
  File input = fopen(path, "rb");
  if (!input) {
    ok = 0;
    return hash;
  }
  unsigned char buffer[16384], size_t length;
  while ((length = fread(buffer, 1, sizeof(buffer), input)))
    hash = fnv_bytes(hash, buffer, length);
  if (ferror(input)) ok = 0;
  input.close();
  return hash;
}

/** Returns `hash` extended with `length` `bytes` by 64-bit FNV-1a. */
uint64_t fnv_bytes(uint64_t hash, const void *bytes, size_t length) {
  const unsigned char *data = bytes;
  for (size_t i = 0; i < length; i++) {
    hash ^= data[i];
    hash *= UINT64_C(1099511628211);
  }
  return hash;
}

/** Hashes unit filename spelling for stable generated C identifiers. */
String Path.identifier_hash(String filename) {
  unsigned hash = 0;
  foreach (char byte in filename) hash = hash * 31 + (unsigned char) byte;
  return "%08X".printf(hash);
}

// locked and replaced files

/** Locks the file `p`, creating it, and returns a descriptor that holds the
    lock until it is closed or the process exits. Returns -1 when `wait` is
    zero and another process holds the lock.
*/
int Path.lock_file(Path p, int wait) {
  int lock = open(p, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  if (lock < 0) $fail.utils_lock_failed(p);
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
void Path.publish_files(List outputs) {
  String suffix = ".tmp.%ld".printf((long) getpid());
  defer for (List rest = outputs; rest; rest = rest.cddr())
    Path.remove_file(%"$(rest.car())$suffix");
  for (List rest = outputs; rest; rest = rest.cddr())
    Path.write_text(%"$(rest.car())$suffix", rest.cadr());
  for (List rest = outputs; rest; rest = rest.cddr()) {
    String target = rest.car();
    if (rename(%"$target$suffix", target))
      File.path_error(<rename>, target, errno);
  }
}

/** Decodes the wait status `raw` of a child that has ended. Returns its
    exit status, `128 + signal` when a signal ended it, or -1 otherwise,
    and stores that signal in `signal`, or 0 when no signal ended it.
*/
int Job.decode_wait_status(int raw, int &signal) {
  signal = WIFSIGNALED(raw) ? WTERMSIG(raw) : 0;
  if (WIFEXITED(raw)) return WEXITSTATUS(raw);
  return signal ? 128 + signal : -1;
}

// driver errors

/** Prints `x2c: error: <message>` to stderr and exits with status 2.
    The streams are flushed and `atexit` handlers do not run, so the call is
    safe inside a `try` body or a catch arm, whose records those handlers
    would otherwise find still live.
*/
void Diagnostics.driver_error(const char *message) {
  fprintf(stderr, "x2c: error: %s\n", message);
  fflush(NULL);
  _exit(2);
}

/** Reports a caught `<not-found>` or `<io-fail>` through
    `Diagnostics.driver_error` as its operation, path or program, and system
    reason.
*/
void Diagnostics.host_error(List detail) {
  Var subject = detail.assoc(<path>);
  if (subject is void) subject = detail.assoc(<program>);
  // Quoted, the key survives a host preprocessor that expands `errno`.
  long error = detail.assoc(<"errno">);
  $fail.utils_host_failed(detail, subject, error);
}

/** Returns the per-user cache root: `X2C_CACHE_DIR`, `XDG_CACHE_HOME/x2c`,
    or `~/.cache/x2c`, whichever is set first, or NULL when none is.
*/
String Compiler.cache_root(void) {
  String explicit = Env.get("X2C_CACHE_DIR"), xdg = Env.get("XDG_CACHE_HOME");
  String home = Env.get("HOME");
  return explicit ? explicit : xdg ? %"$xdg/x2c" :
         home ? %"$home/.cache/x2c" : NULL;
}
