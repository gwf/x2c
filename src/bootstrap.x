/*  bootstrap.x -- Source-bearing APE to native x2c transition

    Copyright (c) 2026 Gary William Flake.

    The Cosmopolitan seed publishes the source and drives native build
    requests. Host tools never receive /zip paths, and the native compiler is
    linked only with the runtime built for that host.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "build.x"

/** Represents one verified source payload while its installation lock is held.
    The record is `Scope`-owned; its `String`s and source `List`s retain their
    actual
    canonical pool lifetimes, which may belong to ancestor pools. Every
    successful path must call `bootstrap_release` to remove the filesystem
    lock.
*/
typedef struct Bootstrap {
  String prefix, identity, lock_path, List runtime_srcs, compiler_srcs;
  int complete;
} *Bootstrap;

#pragma private

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define BOOTSTRAP_MANIFEST "/zip/x2c/.x2c-bootstrap-manifest"

static void _error(const char *message) {
  x2c_driver_error(%"bootstrap: $message");
}

static void _error_path(const char *message, String path) {
  x2c_driver_error(%"bootstrap: $message: $path");
}

/* A prefix that does not exist yet needs an existing parent, and the root
   directory is never a prefix however it is spelled. */
static String _prefix(String path) {
  if (!path) _error("empty installation prefix");
  if (!Path.exists(path) && !Path.is_dir(Path.dirname(path)))
    _error_path("installation parent does not exist", Path.dirname(path));
  String prefix = Path.absolute(path);
  if (prefix == "/") _error("refusing root installation prefix");
  return prefix;
}

static int _safe_path(String path) =>
  path && !path.split("/").any(
    %!(String part) => !part || part == "." || part == "..");

static int _marker_matches(String path, String identity) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %(not-found *): return 0;
  String first = text ? text.split_lines(0).car() : NULL;
  return text && first == identity;
}

/* The lock is an ownership token rather than a wait queue. A live recorded PID
   fails immediately; a dead owner is unlinked once before acquisition retries.
*/
static void _acquire(Bootstrap payload) {
  payload.lock_path = %"${payload.prefix}.bootstrap.lock";
  for (int attempt = 0; attempt < 2; attempt++) {
    int fd = open(payload.lock_path, O_WRONLY | O_CREAT | O_EXCL, 0666);
    if (fd >= 0) {
      char pid[40];
      int length = snprintf(pid, sizeof(pid), "%ld\n", (long) getpid());
      if (write(fd, pid, length) != length) {
        close(fd);
        unlink(payload.lock_path);
        _error("cannot write bootstrap lock");
      }
      close(fd);
      return;
    }
    if (errno != EEXIST)
      _error_path("cannot create bootstrap lock", payload.lock_path);
    File lock = fopen(payload.lock_path, "r");
    long pid = 0;
    if (lock) {
      fscanf(lock, "%ld", &pid);
      lock.close();
    }
    if (pid > 0 && (kill((pid_t) pid, 0) == 0 || errno == EPERM))
      _error_path("another bootstrap is in progress", payload.prefix);
    if (unlink(payload.lock_path) && errno != ENOENT)
      _error_path(
        "cannot recover stale bootstrap lock",
        payload.lock_path);
  }
  _error("cannot acquire bootstrap lock");
}

/* The embedded manifest's records, after its header supplies the payload
   identity. */
static List Bootstrap._manifest(Bootstrap b) {
  String text = NULL;
  try text = Path.read_text(BOOTSTRAP_MANIFEST);
  catch %(not-found *):
    _error("this executable has no embedded source payload");
  if (!text.contains("\n")) _error("malformed embedded source manifest");
  List lines = text.split_lines(0);
  String header = lines.car();
  b.identity = header.remove_prefix("x2c-bootstrap-v1 ");
  if (!header.startswith("x2c-bootstrap-v1 ") || !b.identity)
    _error("unsupported embedded source manifest");
  return lines.cdr();
}

/* Verifies the size and hash of every manifest record under `root`, first
   copying each record there from the payload when `root` is not the prefix,
   and collects the runtime and compiler sources in manifest order. */
static void Bootstrap._verify(Bootstrap b, List records, String root) {
  Array runtime = [], compiler = [];
  foreach (String record, records) {
    unsigned long long expected_hash = 0;
    size_t expected_size = 0;
    char spelling[1024], extra;
    if (sscanf(record, "%llx %zu %1023s %c", &expected_hash, &expected_size,
               spelling, &extra) != 3 || !_safe_path(String.new(spelling)))
      _error("malformed embedded source record");
    String relative = String.new(spelling);
    Path installed = %"$root/$relative";
    if (root != b.prefix) {
      installed.dirname().make_dirs();
      Path.copy_file(%"/zip/x2c/$relative", installed);
    }
    String text = installed.read_text();
    uint64_t hash = build_hash_bytes(
      UINT64_C(1469598103934665603), text, text.len());
    if (text.len() != expected_size || hash != (uint64_t) expected_hash)
      _error_path("source failed verification", installed);
    String source = %"${b.prefix}/$relative";
    if (relative.endswith(".x") && relative.startswith("lib/"))
      runtime.push(source);
    else if (relative.endswith(".x") && relative.startswith("src/"))
      compiler.push(source);
  }
  b.runtime_srcs = runtime.list_free();
  b.compiler_srcs = compiler.list_free();
}

/* Build and verify a complete sibling tree before publishing it with rename.
   A failure before rename cannot expose a partial installation at the prefix.
*/
static void Bootstrap._extract(Bootstrap b, List records) {
  Path temporary = %"${b.prefix}.source.tmp.%ld".printf((long) getpid());
  temporary.remove_tree();
  b._verify(records, temporary);
  if (!b.runtime_srcs || !b.compiler_srcs)
    _error("embedded payload has no compiler or runtime sources");
  Path.write_text(%"$temporary/.x2c-source-id", %"${b.identity}\n");
  temporary.move_to(b.prefix);
}

/** Verifies and materializes the APE source payload at `request.prefix`.
    The prefix must be nonempty and must not be `/`. An existing tree is reused
    only when its source identity matches and every manifest entry verifies.
    On success the `Scope`-owned result retains the exclusive bootstrap lock;
    `complete` additionally requires the matching completion marker, executable
    compiler, and readable runtime archive. Validation, locking, or filesystem
    failure prints a bootstrap diagnostic and exits with status 2; a later
    invocation can recover its dead-PID lock.

    Raises: `<bad-arg>` for embedded manifest bytes that are not `String` text,
    or `<alloc-fail>` or `<size-limit>` while reading the manifest or
    constructing the result. If one transfers after lock acquisition, no
    payload is returned for release and the live process keeps the lock until
    it exits.
*/
Bootstrap bootstrap_materialize(CliRequest request) {
  Bootstrap b = Scope.calloc(1, sizeof(struct Bootstrap));
  b.prefix = _prefix(request.prefix);
  List records = b._manifest();
  _acquire(b);
  if (!Path.exists(b.prefix)) b._extract(records);
  else if (_marker_matches(%"${b.prefix}/.x2c-source-id", b.identity))
    b._verify(records, b.prefix);
  else {
    bootstrap_release(b);
    _error_path(
      "prefix exists but does not contain this source payload", b.prefix);
  }
  b.complete =
    _marker_matches(%"${b.prefix}/.x2c-bootstrap-complete", b.identity) &&
    Path.is_executable(%"${b.prefix}/bin/x2c") &&
    Path.is_file(%"${b.prefix}/lib/libx2c.a");
  Path.make_dirs(%"${b.prefix}/bin");
  Path.make_dirs(%"${b.prefix}/lib");
  return b;
}

/** Builds an ordinary native request for one materialized bootstrap component.
    `component` must be `<runtime>` or `<compiler>`. The former selects a
    static archive over `runtime_srcs`; the latter selects an executable over
    `compiler_srcs`. The `Scope`-owned result borrows the payload's source
    `List`
    and the command's compiler-argument `List`; its new `String`s and `List`
    retain
    their actual canonical pool lifetimes, which may belong to ancestor pools.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing the request.
*/
CliRequest bootstrap_build_request(
  CliRequest command, Bootstrap payload, Symbol component) {
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <build>;
  request.kind = component == <runtime> ? <static-lib> : <executable>;
  request.inputs = component == <runtime> ?
                   payload.runtime_srcs : payload.compiler_srcs;
  String prefix = payload.prefix;
  request.output =
    component == <runtime> ? %"$prefix/lib/libx2c.a" : %"$prefix/bin/x2c";
  request.build_dir = %"$prefix/.x2c-build/$component";
  request.include_dirs = cons(%"$prefix/include/x2c", NULL);
  request.cc_args = command.cc_args;
  request.cc = command.cc;
  request.ar = command.ar;
  request.jobs = command.jobs;
  request.max_errors = command.max_errors;
  request.verbose = command.verbose;
  return request;
}

/** Records the resolved host tools and then publishes bootstrap completion.
    The completion marker is written only after the toolchain record succeeds.
    The call does not update `payload.complete`. A directory, record, or marker
    failure prints a bootstrap diagnostic and exits with status 2.

    Raises: `<alloc-fail>` or `<size-limit>` while constructing canonical
    paths.
*/
void bootstrap_record_install(Bootstrap b, String cc, String ar) {
  Path directory = %"${b.prefix}/lib/x2c";
  directory.make_dirs();
  Path.write_text(%"$directory/toolchain", %"CC=$cc\nAR=$ar\n");
  Path.write_text(%"${b.prefix}/.x2c-bootstrap-complete", %"${b.identity}\n");
}

/** Attempts to remove a held bootstrap lock without freeing the payload.
    The lock path is cleared even if `unlink` fails. NULL payloads and repeated
    calls have no effect.
*/
void bootstrap_release(Bootstrap payload) {
  if (!payload || !payload.lock_path) return;
  unlink(payload.lock_path);
  payload.lock_path = NULL;
}
