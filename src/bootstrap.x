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
#include <sys/utsname.h>

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
    uint64_t hash = x2c_fnv_bytes(
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

/* The link argument that links the prefix's whole runtime archive into a
   program that loads native modules, which bind to the program's own
   runtime, and on Linux exports its functions. NULL where modules do not
   load. */
static String _whole_runtime(String prefix) {
  struct utsname host;
  if (uname(&host)) return NULL;
  String system = String.new(host.sysname), archive = %"$prefix/lib/libx2c.a";
  if (system == "Darwin") return %"-Wl,-force_load,$archive";
  if (system == "Linux")
    return
      %"-Wl,--export-dynamic,--whole-archive,$archive,--no-whole-archive";
  return NULL;
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
  request.inputs =
    component == <runtime> ? payload.runtime_srcs : payload.compiler_srcs;
  String prefix = payload.prefix;
  request.output =
    component == <runtime> ? %"$prefix/lib/libx2c.a" : %"$prefix/bin/x2c";
  request.build_dir = %"$prefix/.x2c-build/$component";
  request.include_dirs = cons(%"$prefix/include/x2c", NULL);
  request.cc_args = command.cc_args;
  String whole = _whole_runtime(prefix);
  if (component == <compiler> && whole) request.ld_args = %($whole);
  if (component == <compiler>) request.extensions = command.extensions;
  request.cc = command.cc;
  request.ar = command.ar;
  request.jobs = command.jobs;
  request.max_errors = command.max_errors;
  request.verbose = command.verbose;
  return request;
}

/** Writes the prefix's runtime interfaces with its installed compiler.
    An interface replays only for the compiler that wrote it, so the native
    compiler translates the runtime sources as a stage build's library batch
    does, and each `lib/<stem>.xi` is then replaced atomically. Sources are
    named relative to the prefix, so their spelling matches the home the
    compiler resolves. The scratch translation directory is removed
    afterward. A translation that fails or cannot start prints a bootstrap
    diagnostic with any errors the compiler printed; a failed write prints
    the host error. Either exits with status 2.
*/
void bootstrap_write_interfaces(Bootstrap b) {
  String prefix = b.prefix, out = ".x2c-build/interfaces";
  Path.make_dirs(%"$prefix/$out");
  Array sources = [];
  foreach (String source, b.runtime_srcs)
    sources.push(source.remove_prefix(%"$prefix/"));
  Job translate =
    %("$prefix/bin/x2c" "translate" "--out-dir" $out @{sources.list()})
      .job().options({dir: prefix, env: {"X2C_HOME": "."},
                      stdout: <capture>, stderr: <capture>});
  int status = 127;
  try status = translate.status();
  catch %(not-found *): {}
  catch %(io-fail *): {}
  if (status)
    _error(%"cannot write runtime interfaces: ${translate.errors_text}");
  Array outputs = [];
  foreach (String source, b.runtime_srcs) {
    String name = %"${Path.stem(source)}.xi";
    outputs.push(%"$prefix/lib/$name");
    outputs.push(Path.read_text(%"$prefix/$out/$name"));
  }
  try file_publish(outputs.list_free());
  catch %(not-found *detail): x2c_host_error(detail);
  catch %(io-fail *detail): x2c_host_error(detail);
  Path.remove_tree(%"$prefix/$out");
}

/** Builds shipped commands from the verified APE source after the native
    compiler and runtime interfaces exist. The compiler object archive omits
    `main`, as the checkout command build does. An empty shipped manifest
    still creates the command directory and its empty installed manifest.
    Failure exits before the bootstrap completion marker is written.
*/
void bootstrap_build_commands(Bootstrap b) {
  String prefix = b.prefix;
  Path libexec = %"$prefix/libexec/x2c";
  libexec.make_dirs();
  Buffer shipped = $auto(Buffer.new(0));
  Array names = [];
  foreach (String row,
           Path.read_text(%"$prefix/commands/manifest.txt").split_lines(0)) {
    if (!row) continue;
    List fields = row.split("|");
    if (fields.cadr().str() != "shipped") continue;
    shipped.printf("%s\n", row.str());
    names.push(fields.car());
  }
  Path.write_text(%"$libexec/commands.txt", shipped);
  if (!names.len()) return;

  String compiler = %"$prefix/bin/x2c";
  Job identity_job = %($compiler "env" "identity").job()
    .options({env: {"X2C_HOME": prefix}, stdout: <capture>,
              stderr: <capture>});
  String identity = identity_job.output().strip("\n");
  Path commands_build = %"$prefix/.x2c-build/commands";
  commands_build.make_dirs();
  Path identity_source = %"$commands_build/identity.x";
  Path.write_text(identity_source,
                  %"String x2c_embedded_identity(void) => \"$identity\";\n");

  Array objects = [];
  foreach (Path object, Path.glob(%"$prefix/.x2c-build/compiler/obj/*.o"))
    if (!object.basename().startswith("main-")) objects.push(object);
  if (!objects.len()) _error("native compiler has no reusable objects");
  Path archive = %"$commands_build/libx2c-dev.a";
  Job library = %($compiler "build" "--plain" "--kind" "static-library"
    "--output" $archive @{objects.list()}).job()
    .options({env: {"X2C_HOME": prefix}, stdout: <capture>,
              stderr: <capture>});
  if (library.status())
    _error(%"cannot archive compiler objects: ${library.errors_text}");

  /* Bootstrap's per-unit generated C directories are not a flat stage
     directory. Gather their public headers for command C compilation. */
  Path headers = %"$commands_build/include";
  headers.make_dirs();
  foreach (Path source,
           Path.glob(%"$prefix/.x2c-build/compiler/gen/*/*.h"))
    Path.copy_file(source, headers.join(source.basename()));
  String whole = _whole_runtime(prefix);
  foreach (String name, names) {
    List sources = Path.glob(%"$prefix/commands/$name/*.x");
    String build_dir = %"$commands_build/$name";
    String output = %"$libexec/x2c-$name";
    String src_dir = %"$prefix/src";
    Array arguments = %($compiler "build" "--plain" "--build-dir"
      $build_dir "--output" $output
      "--x-include-dir" $prefix "--x-include-dir" $src_dir
      "--c-include-dir" $headers);
    if (whole) arguments.push(whole);
    foreach (Path source, sources) arguments.push(source);
    arguments.push(identity_source);
    arguments.push(archive);
    Job command = arguments.list_free().job()
      .options({env: {"X2C_HOME": prefix}, stdout: <capture>,
                stderr: <capture>});
    if (command.status())
      _error(%"cannot build command $name: ${command.errors_text}");
  }
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
