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
    actual canonical pool lifetimes, which may belong to ancestor pools.
*/
typedef struct Bootstrap {
  String prefix, identity, List runtime_srcs, compiler_srcs;
  int complete;
} *Bootstrap;

#pragma private

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

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

/* The embedded manifest's records, after its header supplies the payload
   identity. */
static List Bootstrap._manifest(Bootstrap b) {
  String text = NULL;
  try text = Path.read_text("/zip/x2c/.x2c-bootstrap-manifest");
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
   Returns zero when a concurrent bootstrap published the prefix first.
*/
static int Bootstrap._extract(Bootstrap b, List records) {
  String pid = "%ld".printf((long) getpid());
  Path temporary = %"${b.prefix}.source.tmp.$pid";
  temporary.remove_tree();
  b._verify(records, temporary);
  if (!b.runtime_srcs || !b.compiler_srcs)
    _error("embedded payload has no compiler or runtime sources");
  Path.write_text(%"$temporary/.x2c-source-id", %"${b.identity}\n");
  int published = 1;
  try temporary.move_to(b.prefix);
  catch %(io-fail *detail): {
    if (!Path.exists(b.prefix)) x2c_host_error(detail);
    published = 0;
  }
  temporary.remove_tree();
  return published;
}

/** Verifies and materializes the APE source payload at `request.prefix`.
    The prefix must be nonempty and must not be `/`. An existing tree is reused
    only when its source identity matches and every manifest entry verifies.
    On success the process holds the exclusive lock on
    `<prefix>/.x2c-bootstrap.lock` until it exits; the file stays in place.
    `complete` additionally requires the matching completion marker,
    executable compiler, and readable runtime archive. Validation, locking,
    or filesystem failure prints a bootstrap diagnostic and exits with
    status 2.

    Raises: `<bad-arg>` for embedded manifest bytes that are not `String` text,
    or `<alloc-fail>` or `<size-limit>` while reading the manifest or
    constructing the result.
*/
Bootstrap bootstrap_materialize(CliRequest request) {
  Bootstrap b = Scope.calloc(1, sizeof(struct Bootstrap));
  b.prefix = _prefix(request.prefix);
  List records = b._manifest();
  if (Path.exists(b.prefix) || !b._extract(records)) {
    if (!_marker_matches(%"${b.prefix}/.x2c-source-id", b.identity))
      _error_path(
        "prefix exists but does not contain this source payload", b.prefix);
    b._verify(records, b.prefix);
  }
  if (file_lock(%"${b.prefix}/.x2c-bootstrap.lock", 0) < 0)
    _error_path("another bootstrap is in progress", b.prefix);
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
