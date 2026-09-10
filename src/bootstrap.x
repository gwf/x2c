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

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define BOOTSTRAP_MANIFEST "/zip/x2c/.x2c-bootstrap-manifest"

static void _error(const char *message) {
  x2c_driver_error(%"bootstrap: $message");
}

static void _error_path(const char *message, String path) {
  x2c_driver_error(%"bootstrap: $message: $path");
}

static String _absolute(String path) {
  if (!path || !path[0]) _error("empty installation prefix");
  if (path == "/") _error("refusing root installation prefix");
  char resolved[PATH_MAX];
  if (!access(path, F_OK)) {
    if (!realpath(path, resolved))
      _error_path("cannot resolve installation prefix", path);
    return String.new(resolved);
  }
  String parent = x2c_path_dir(path);
  if (!realpath(parent, resolved))
    _error_path("installation parent does not exist", parent);
  const char *base = strrchr(path, '/');
  base = base ? base + 1 : path;
  if (!base[0] || strcmp(base, ".") == 0 || strcmp(base, "..") == 0)
    _error_path("invalid installation prefix", path);
  return %"${String.new(resolved)}/${String.new(base)}";
}

static int _safe_path(const char *path) {
  if (!path || !path[0] || path[0] == '/') return 0;
  const char *component = path, *ch = path;
  loop {
    if (*ch != '/' && *ch) {
      ch++;
      continue;
    }
    int length = (int) (ch - component);
    if (!length ||
        (length == 1 && component[0] == '.') ||
        (length == 2 && component[0] == '.' && component[1] == '.'))
      return 0;
    if (!*ch) break;
    component = ch + 1;
    ch++;
  }
  return 1;
}

static uint64_t _hash(File input, File output, size_t *length) {
  uint64_t hash = UINT64_C(1469598103934665603), unsigned char bytes[16384];
  size_t count, total = 0;
  while ((count = fread(bytes, 1, sizeof(bytes), input))) {
    for (size_t i = 0; i < count; i++) {
      hash ^= bytes[i];
      hash *= UINT64_C(1099511628211);
    }
    if (output && fwrite(bytes, 1, count, output) != count)
      _error("cannot write extracted payload");
    total += count;
  }
  if (ferror(input)) _error("cannot read embedded payload");
  if (length) *length = total;
  return hash;
}

static int _read_marker(String path, String identity) {
  File input = fopen(path, "r");
  if (!input) return 0;
  char line[128], int matched = fgets(line, sizeof(line), input) != NULL;
  input.close();
  if (!matched) return 0;
  line[strcspn(line, "\r\n")] = 0;
  return identity == String.new(line);
}

static void _write_marker(String path, String identity) {
  File output = fopen(path, "w");
  if (!output || output.printf("%s\n", identity) < 0 || output.close())
    _error_path("cannot write installation marker", path);
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
      _error_path(
        "another bootstrap is in progress",
        payload.prefix);
    if (unlink(payload.lock_path) && errno != ENOENT)
      _error_path(
        "cannot recover stale bootstrap lock",
        payload.lock_path);
  }
  _error("cannot acquire bootstrap lock");
}

static char *_manifest(String *identity) {
  File input = fopen(BOOTSTRAP_MANIFEST, "rb");
  if (!input)
    _error("this executable has no embedded source payload");
  String content = NULL;
  try content = input.string_close();
  catch %(io-fail *): _error("cannot read embedded source manifest");
  char *text = strdup(content ? content : "");
  if (!text) _error("cannot allocate source manifest");
  char *newline = strchr(text, '\n');
  if (!newline) _error("malformed embedded source manifest");
  *newline = 0;
  const char *prefix = "x2c-bootstrap-v1 ";
  if (strncmp(text, prefix, strlen(prefix)) != 0 || !text[strlen(prefix)])
    _error("unsupported embedded source manifest");
  *identity = String.new(text + strlen(prefix));
  *newline = '\n';
  return text;
}

static int _record(
  char *line, unsigned long long *hash, size_t *size, char path[1024]) {
  char extra;
  return sscanf(line, "%llx %zu %1023s %c", hash, size, path, &extra) == 3;
}

static void _collect(Bootstrap payload, String relative) {
  String installed = %"${payload.prefix}/$relative";
  if (relative.startswith("lib/") && relative.endswith(".x"))
    payload.runtime_srcs = cons(installed, payload.runtime_srcs);
  else if (relative.startswith("src/") && relative.endswith(".x"))
    payload.compiler_srcs = cons(installed, payload.compiler_srcs);
}

/* Build and verify a complete sibling tree before publishing it with rename.
   A failure before rename cannot expose a partial installation at the prefix.
*/
static void _extract(Bootstrap payload, char *manifest) {
  String temporary = %"${payload.prefix}.source.tmp.%ld".printf(
    (long) getpid());
  if (access(temporary, F_OK) == 0 && !_build_remove_tree(temporary))
    _error_path("cannot clear temporary source tree", temporary);
  if (!_build_mkdirs(temporary))
    _error_path("cannot create temporary source tree", temporary);

  char *save = NULL;
  strtok_r(manifest, "\n", &save);
  char *line = strtok_r(NULL, "\n", &save);
  while (line) {
    unsigned long long expected_hash = 0;
    size_t expected_size = 0, char relative[1024];
    if (!_record(line, &expected_hash, &expected_size, relative) ||
        !_safe_path(relative))
      _error("malformed embedded source record");
    String source = %"/zip/x2c/${String.new(relative)}";
    String target = %"$temporary/${String.new(relative)}";
    String parent = x2c_path_dir(target);
    if (!_build_mkdirs(parent))
      _error_path("cannot create payload directory", parent);
    File input = fopen(source, "rb"), output = fopen(target, "wb");
    if (!input || !output)
      _error_path("cannot extract embedded source", relative);
    size_t actual_size = 0;
    uint64_t actual_hash = _hash(input, output, &actual_size);
    int close_error = input.close() || output.close();
    if (close_error || actual_size != expected_size ||
        actual_hash != (uint64_t) expected_hash)
      _error_path("embedded source failed verification", relative);
    _collect(payload, String.new(relative));
    line = strtok_r(NULL, "\n", &save);
  }
  if (!payload.runtime_srcs || !payload.compiler_srcs)
    _error("embedded payload has no compiler or runtime sources");
  _write_marker(%"$temporary/.x2c-source-id", payload.identity);
  if (rename(temporary, payload.prefix))
    _error_path(
      "cannot publish extracted source tree",
      payload.prefix);
}

static void _collect_existing(Bootstrap payload, char *manifest) {
  char *save = NULL;
  strtok_r(manifest, "\n", &save);
  char *line = strtok_r(NULL, "\n", &save);
  while (line) {
    unsigned long long hash = 0;
    size_t size = 0, char relative[1024];
    if (!_record(line, &hash, &size, relative) ||
        !_safe_path(relative))
      _error("malformed embedded source record");
    String installed = %"${payload.prefix}/${String.new(relative)}";
    File input = fopen(installed, "rb");
    if (!input)
      _error_path("materialized source is missing", installed);
    size_t actual_size = 0;
    uint64_t actual_hash = _hash(input, NULL, &actual_size);
    int close_error = input.close();
    if (close_error || actual_size != size || actual_hash != (uint64_t) hash)
      _error_path(
        "materialized source failed verification",
        installed);
    _collect(payload, String.new(relative));
    line = strtok_r(NULL, "\n", &save);
  }
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
  Bootstrap payload = Scope.calloc(1, sizeof(struct Bootstrap));
  payload.prefix = _absolute(request.prefix);
  char *manifest = _manifest(&payload.identity);
  _acquire(payload);
  String source_marker = %"${payload.prefix}/.x2c-source-id";
  String complete_marker = %"${payload.prefix}/.x2c-bootstrap-complete";
  if (!access(payload.prefix, F_OK)) {
    if (!_read_marker(source_marker, payload.identity)) {
      bootstrap_release(payload);
      _error_path(
        "prefix exists but does not contain this source payload",
        payload.prefix);
    }
    _collect_existing(payload, manifest);
  }
  else _extract(payload, manifest);
  payload.runtime_srcs = payload.runtime_srcs.reverse();
  payload.compiler_srcs = payload.compiler_srcs.reverse();
  free(manifest);
  payload.complete =
    _read_marker(complete_marker, payload.identity) &&
    !access(%"${payload.prefix}/bin/x2c", X_OK) &&
    !access(%"${payload.prefix}/lib/libx2c.a", R_OK);
  if (!_build_mkdirs(%"${payload.prefix}/bin") ||
      !_build_mkdirs(%"${payload.prefix}/lib"))
    _error_path(
      "cannot create installation directories",
      payload.prefix);
  return payload;
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
  request.output = component == <runtime> ?
    %"${payload.prefix}/lib/libx2c.a" :
    %"${payload.prefix}/bin/x2c";
  request.build_dir = component == <runtime> ?
    %"${payload.prefix}/.x2c-build/runtime" :
    %"${payload.prefix}/.x2c-build/compiler";
  request.include_dirs = cons(%"${payload.prefix}/include", NULL);
  request.cc_args = command.cc_args;
  request.cc = command.cc;
  request.ar = command.ar;
  request.jobs = command.jobs;
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
void bootstrap_record_install(Bootstrap payload, String cc, String ar) {
  String directory = %"${payload.prefix}/lib/x2c";
  if (!_build_mkdirs(directory))
    _error_path(
      "cannot create toolchain record directory",
      directory);
  String record = %"$directory/toolchain", File output = fopen(record, "w");
  if (!output ||
      output.printf("CC=%s\nAR=%s\n", cc, ar) < 0 ||
      output.close())
    _error_path("cannot write toolchain record", record);
  _write_marker(
    %"${payload.prefix}/.x2c-bootstrap-complete", payload.identity);
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
