/*  build.x -- Typed native build request and artifact graph

    Copyright (c) 2026 Gary William Flake.

    Direct operands and project targets use the same CliRequest. This module
    places native artifacts and lowers them to toolchain actions; translation
    remains with the compiler driver.
*/

#pragma once
#include "cli.x"
#include "deps.x"
#include "toolchain.x"

/** Holds `Scope`-owned mutable state for one prepared native build target.
    `CliRequest.prepare` allocates the record in the current `Scope` and
    borrows the supplied request pointer without copying it; that request
    must outlive the `Build` and may belong outside the per-target
    `Context`. `Toolchain` and `Array` storage allocated during preparation
    follow the current `Scope`, while referenced `String`s and `List`s keep
    their canonical pool lifetimes. `cleanup` manages only a temporary
    filesystem tree.
*/
typedef struct Build {
  CliRequest request, Toolchain toolchain;
  String work_dir, gen_root, obj_root, dep_root, state_root, output;
  int temporary, Array c_sources, gen_dirs, native_inputs, objects, units;
  String compile_directory, Array compile_commands;
  unsigned long started_at;
  double started_wall;
  unsigned long xlat_start, cc_start, final_at;
  unsigned long long gen_bytes;
  int xlat_n, xlat_done, xlat_cached, cc_n, cc_done, cc_cached, final_cached;
} *Build;

#pragma private

#include <errno.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "json.x"
#include "report.x"

// artifact paths

/* Artifact directories and object, dependency, and state paths all use this
   spelling-derived key. The input path is not canonicalized, so its spelling
   is part of incremental cache identity. */
static String _key(String path) {
  // The stem is interpolated, never a format: a path may contain a percent.
  String stem = Path.stem(path), digest = "%08x".printf(path.hash());
  return %"$stem-$digest";
}

static String Build._unit_dir(Build b, String unit) =>
  %"${b.gen_root}/${_key(unit)}";

/* A unit's generated C, header, interface, and depfile share its stem. */
static String _unit_file(String directory, String unit, String suffix) =>
  %"$directory/${Path.stem(unit)}$suffix";

/* The state record of one artifact, keyed like the artifact. */
static String Build._state_path(Build b, String kind, String path) =>
  %"${b.state_root}/$kind-${_key(path)}";

/* The suffix of one process's private sibling of a shared artifact path.
   Concurrent builds in one project write through these and publish with
   rename, so no destination is ever absent or half written. */
static String _process_suffix(void) => "tmp.%ld".printf((long) getpid());

// preparing a build

/** Validates a native build request and returns its `Scope`-owned build state.
    It writes the default state seed and selected compiler and archiver back
    to `request`, chooses output and intermediate paths, and creates artifact
    directories unless this is a dry run. Invalid inputs or setup print a
    diagnostic and exit with status 2.
*/
Build CliRequest.prepare(CliRequest request) {
  request._add_extensions();
  if (!request.inputs)
    x2c_driver_error("build requires input operands or a project manifest");
  Build b = Scope.calloc(1, sizeof(struct Build));
  *b = (struct Build) {
    .request = request, .c_sources = [], .gen_dirs = [], .units = [],
    .native_inputs = [], .objects = []};
  b._add_inputs();
  if (request.compile_only) b._check_compile_only();
  if (!request.state_seed) request.state_seed = "direct";
  b._select_tools();
  if (request.compile_commands && !request.dry_run) b.compile_commands = [];
  b.output = _default_output(request);
  b.started_at = report_now_us();
  b.started_wall = _wall_seconds();
  b._make_work_dirs();
  b._check_runtime();
  return b;
}

/* A linked package's sources are units, translated in package mode. */
static void CliRequest._add_extensions(CliRequest request) {
  foreach (String package, request.extensions) {
    String root = Path.absolute(package), parent = Path.dirname(root);
    request.package_dirs = request.package_dirs.append(%($parent));
    request.inputs = request.inputs.append(Path.glob(%"$root/src/*.x"))
      .append(Path.glob(%"$root/src/*.c"));
  }
}

/* x2c sources translate, C sources compile, and objects and archives link
   as given. */
static void Build._add_inputs(Build b) {
  CliRequest request = b.request;
  foreach (String input, request.inputs) {
    // A dry run runs nothing and reads nothing, and a planned target's
    // archive exists only after the build it is printing would run.
    if (!request.dry_run) build_check_input(input);
    if (x2c_source_file(input)) b.xlat_n++;
    else if (input.endswith(".c")) b.c_sources.push(input);
    else if (input.endswith(".o") || input.endswith(".a"))
      b.native_inputs.push(input);
    else x2c_driver_error(%"unsupported build input: $input");
    if (request.kind == <static-lib> && input.endswith(".a"))
      x2c_driver_error(%"cannot nest an archive in a static library: $input");
  }
}

/** Exits with a driver error unless `input` names a regular file.
    A wildcard or directory operand adds a note on what to pass instead.
*/
void build_check_input(String input) {
  if (!input) x2c_driver_error("input path is empty");
  if (Path.is_file(input)) return;
  if (Path.is_dir(input)) {
    fprintf(stderr, "x2c: error: input is a directory: %s\n", input);
    fputs(
      "note: pass source files, use a shell wildcard, or define a "
      "manifest target\n", stderr);
    exit(2);
  }
  if (Path.exists(input))
    x2c_driver_error(%"input is not a regular file: $input");
  fprintf(stderr, "x2c: error: input does not exist: %s\n", input);
  if (strpbrk(input, "*?["))
    fputs("note: x2c does not expand wildcard operands\n", stderr);
  exit(2);
}

/* Compile-only builds make one object per source, so every input compiles
   and several objects need a build directory. */
static void Build._check_compile_only(Build b) {
  List inputs = b.request.inputs;
  if (b.native_inputs)
    x2c_driver_error("compile-only accepts only .x and .c inputs");
  if (inputs.cdr() && b.request.output)
    x2c_driver_error(
      "--output is ambiguous with multiple compile-only inputs");
  if (inputs.cdr() && !b.request.build_dir)
    x2c_driver_error("multiple compile-only inputs require --build-dir");
}

/* The selected compiler and archiver go back to the request. */
static void Build._select_tools(Build b) {
  CliRequest request = b.request;
  b.toolchain = toolchain_new(request);
  request.cc = b.toolchain.cc; request.ar = b.toolchain.ar;
  // A module's code is placed wherever the loader maps it.
  if (request.kind == <module>)
    b.toolchain.cc_args = %("-fPIC" @{b.toolchain.cc_args});
}

/* An unnamed output is named for the first input and the kind.
   `Build.finish` places a run's output in the work directory. */
static String _default_output(CliRequest request) {
  if (request.output) return request.output;
  if (request.command == <run>) return NULL;
  String stem = Path.stem(request.inputs.car());
  if (request.compile_only && !request.inputs.cdr()) return %"$stem.o";
  if (request.kind == <static-lib>) return %"lib$stem.a";
  if (request.kind == <module>) return %"$stem.so";
  return "a.out";
}

/* Intermediates go to the requested directory, which the build keeps, or to
   a temporary one that a successful build removes. */
static void Build._make_work_dirs(Build b) {
  CliRequest request = b.request;
  b.work_dir = _kept_dir(request);
  b.temporary = !b.work_dir;
  try {
    if (!b.work_dir && request.dry_run) b.work_dir = "/tmp/x2c-build-dry-run";
    if (!b.work_dir) b.work_dir = Path.temp_dir();
    b.gen_root = %"${b.work_dir}/gen";
    b.obj_root = %"${b.work_dir}/obj";
    b.dep_root = %"${b.work_dir}/dep";
    if (request.build_dir) b.state_root = %"${b.work_dir}/.x2c-state";
    List roots = %(${b.gen_root} ${b.obj_root} ${b.dep_root} ${b.state_root});
    if (!request.dry_run)
      foreach (Path root, roots) if (root) root.make_dirs();
  }
  catch %(io-fail *detail): x2c_host_error(detail);
}

static String _kept_dir(CliRequest request) {
  if (request.build_dir) return request.build_dir;
  if (request.temps_dir) return request.temps_dir;
  return request.save_temps ? ".x2c-build" : NULL;
}

/* An executable links the runtime archive that matches this compiler. */
static void Build._check_runtime(Build b) {
  if (b.request.compile_only || b.request.kind != <executable>) return;
  String runtime = b.toolchain.runtime_lib;
  if (access(runtime, R_OK))
    x2c_driver_error(%"matching x2c runtime is unavailable: $runtime");
}

// translated units

/** Returns the generated-file directory for `input`.
    The directory is derived from the input path and created unless this is
    a dry run. Native registration belongs to `Build.add_generated`.
*/
String Build.generated_dir(Build b, String input) {
  String directory = b._unit_dir(input);
  if (!b.request.dry_run) Path.make_dirs(directory);
  return directory;
}

/** Reports whether translated C and header artifacts match current inputs.
    Returns zero without retained state, during a dry run, when either output
    is absent, or when any compiler, tool, option, depfile, or dependency
    fingerprint cannot be read or differs.
*/
int Build.translation_current(Build b, String input, String directory) {
  if (!b.state_root || b.request.dry_run) return 0;
  foreach (String suffix, %(".c" ".h" ".xi"))
    if (!Path.is_file(_unit_file(directory, input, suffix))) return 0;
  int ok = 1;
  uint64_t hash = b._translation_fingerprint(input, directory, ok);
  int current = ok && _state_matches(b._state_path("x", input), hash);
  if (current && b.request.verbose)
    fprintf(stderr, "x2c: up-to-date translate %s\n", input);
  return current;
}

static uint64_t Build._translation_fingerprint(
  Build b, String input, String directory, int &ok) {
  CliRequest request = b.request;
  uint64_t hash = _state_base(request, b.toolchain.cc, ok);
  hash = _state_text(hash, "translate");
  hash = _state_text(hash, input);
  hash = _state_list(hash, request.include_dirs);
  hash = _state_list(hash, request.package_roots());
  hash = _state_list(hash, request.cpp_args);
  // The project meta build compiles with these and its own C compiler.
  hash = _state_list(hash, request.cc_args);
  hash = _state_tool(hash, toolchain_meta_cc(request.meta_cc), ok);
  hash = _state_text(hash, request.no_cpp ? "no-cpp" : "cpp");
  hash = _state_text(hash, request.live_symbols ? "live" : "prelude");
  hash = _state_text(hash, request.cpp_symbols ? "cpp-symbols" : "raw");
  hash = _state_text(
    hash, request.source_map ? "source-map" : "generated-lines");
  // A loaded module's functions can compute what the translation emits.
  foreach (String module, request.native_modules)
    hash = _state_file(hash, module, ok);
  return _state_dependencies(hash, _unit_file(directory, input, ".d"), ok);
}

/** Starts translation reporting for `input` and initializes timing when unset.
*/
void Build.begin_translation(Build b, String input) {
  if (!b.xlat_start) b.xlat_start = report_now_us();
  report_progress(<translate>, b.xlat_done, b.xlat_n, input);
}

/** Records one completed translation and reports the phase when all finish.
    A nonzero `cached` value also increments the cached-translation count.
*/
void Build.end_translation(Build b, String input, int cached) {
  b.xlat_done++;
  if (cached) b.xlat_cached++;
  report_progress(<translate>, b.xlat_done, b.xlat_n, input);
  if (b.xlat_done != b.xlat_n) return;
  String noun = b.xlat_n == 1 ? "x2c file" : "x2c files";
  report_phase(
    <translate>, b.xlat_n, noun, b.xlat_cached,
    report_now_us() - b.xlat_start);
}

/** Records the successful translation fingerprint when retained state exists.
    Dry runs, incomplete fingerprints, and a source edited while the build ran
    are ignored, so the generated C is never reused for an input it does not
    match. Writing the private state file is best effort; after a write or
    rename failure, cleanup attempts to unlink the temporary file but cannot
    guarantee its removal.
*/
void Build.record_translation(Build b, String input, String directory) {
  if (!b.state_root || b.request.dry_run) return;
  String depfile = _unit_file(directory, input, ".d");
  int ok = 1;
  uint64_t hash = b._translation_fingerprint(input, directory, ok);
  if (ok && b._files_unchanged(_depfile_inputs(depfile)))
    _state_write(b._state_path("x", input), hash);
}

/** Registers generated artifacts for native compilation.
    Counts the C and header bytes, appends the C source, and adds include
    directories and native compile options for imported packages. Programs
    also add ordered package archives and link flags; an absent archive prints
    a diagnostic and exits with status 2. Static libraries skip link inputs.
*/
void Build.add_generated(Build b, String input, String directory) {
  String source = _unit_file(directory, input, ".c");
  b.gen_bytes += report_file_bytes(source);
  b.gen_bytes += report_file_bytes(_unit_file(directory, input, ".h"));
  b.c_sources.push(source);
  b.units.push(input);
  if (!(directory in b.gen_dirs)) b.gen_dirs.push(directory);
  b._link_packages(input, directory);
}

/* Imported packages reach the build through the unit's recorded
   dependencies. Only an import pulls a package file into a consumer, and
   the record is present even when the translation result was reused. */
static void Build._link_packages(Build b, String input, String directory) {
  List roots = b.request.package_roots();
  if (!roots) return;
  String self = Path.absolute(input);
  String depfile = _unit_file(directory, input, ".d");
  foreach (String dependency, _depfile_inputs(depfile)) {
    // A unit under a package directory that is not the package's own
    // source, such as a script kept beside it, consumes nothing by itself.
    if (dependency == self || dependency == input) continue;
    String package = x2c_package_directory(roots, dependency);
    if (package && !b._package_built_here(roots, package))
      b._link_package(package);
  }
}

/* Whether one of the request's inputs is a source of `package`. A package's
   own sources, and a module built from them, link no archive of their own;
   a test or example inside the package directory imports the package like
   any consumer. */
static int Build._package_built_here(Build b, List roots, String package) {
  foreach (String input, b.request.inputs) {
    String source = Path.absolute(input);
    if (x2c_package_directory(roots, source) == package &&
        x2c_package_source(package, source)) return 1;
  }
  return 0;
}

/* A package's generated headers and native compile options reach every
   consumer, and a program also links its archive and link inputs. */
static void Build._link_package(Build b, String package) {
  String builds = %"$package/builds";
  if (builds in b.gen_dirs) return;
  b.gen_dirs.push(builds);
  // A package may publish a vendored foreign header from its src.
  b.gen_dirs.push(%"$package/src");
  String name = package.split("/").last();
  String response = %"$builds/$name.native.rsp";
  CliRequest native = NULL;
  if (!access(response, F_OK)) {
    native = cli_package_options(response, package);
    b.toolchain.cc_args = b.toolchain.cc_args.append(native.cc_args);
  }
  // Libraries take native compile options too; only programs link archives.
  if (b.request.kind == <static-lib>) return;
  String archive = %"$builds/lib$name.a";
  if (access(archive, R_OK))
    x2c_driver_error(%"package '$name' is not built: $archive");
  // The response file carries the link inputs the archive needs, so a
  // package built before it existed is the same unbuilt-package mistake
  // and is rebuilt; dropping them leaves undefined symbols at link.
  if (!native) x2c_driver_error(%"package '$name' is not built: $response");
  b.native_inputs.push(archive);
  b.toolchain.ld_args = b.toolchain.ld_args.append(native.ld_args);
}

// entry units

/** Writes the entry unit of a native module and returns the request that
    translates it. The entry defines `x2c_module_targets`, which returns the
    targets of the native `meta` prototypes the module's x2c sources
    declare, and `x2c_module_stamp`, which holds the stamp the loading
    compiler must match.
*/
CliRequest Build.module_entry(Build b) {
  String stamp = build_module_stamp();
  if (!stamp) x2c_driver_error("cannot read the running compiler to stamp");
  Path entry = %"${b.work_dir}/module/x2c_module.x";
  _write_entry(
    entry, b.units, %"const char x2c_module_stamp[] = \"$stamp\";
Map x2c_module_targets(void) => \$module.targets();
");
  return b._entry_request(%($entry));
}

/** Writes the registration unit of each package the request links in with
    `--extension` and returns the request that translates them. A
    constructor registers the targets of the native `meta` prototypes the
    package's sources declare under the package's name, so any number of
    packages link into one compiler, which selects them without loading a
    module.
*/
CliRequest Build.extension_entries(Build b) {
  Array entries = [], Map packages = {};
  foreach (String package, b.request.extensions) {
    String root = Path.absolute(package), name = Path.basename(root);
    Path entry = %"${b.work_dir}/extension/$name/x2c_extension_$name.x";
    _write_entry(
      entry, Path.glob(%"$root/src/*.x"),
      %"void x2c_register_extension(const char *, Map (*)(void));
static Map _targets(void) => \$module.targets();
__attribute__((constructor)) static void _register(void) {
  x2c_register_extension(\"$name\", _targets);
}
");
    entries.push(entry);
    packages[Path.absolute(entry)] = root;
  }
  CliRequest request = b._entry_request(entries.list_free());
  request.collection_packages = packages;
  return request;
}

static CliRequest Build._entry_request(Build b, List entries) {
  CliRequest request = Scope.memdup(b.request, sizeof(struct CliRequest));
  request.inputs = entries;
  b.xlat_n += entries.len();
  return request;
}

/* Writes the entry unit `entry`, which includes each of `units`, defines
   `$module.targets()`, a Map from the name of each native `meta` prototype
   they declare to a `Func` that calls it, and ends with `exports`. Units
   that declare no such prototype fail to translate. Each source is included
   by its absolute path through a link to the filesystem root beside the
   entry, so distinct sources with one name stay distinct and each unit's
   generated header is placed inside the entry's own generated directory.
   No include directory reaches the root. */
static void _write_entry(Path entry, List units, String exports) {
  String includes = "", Array sources = [];
  foreach (String unit, units) {
    String source = Path.absolute(unit);
    includes = %"$includes#include \"x2c-root$source\"\n";
    sources.push(source);
  }
  String declared = sources.list_free().repr(), root = x2c_get_root();
  Path link = entry.dirname().join("x2c-root");
  try {
    entry.dirname().make_dirs();
    if (!Path.exists(link)) link.symlink_to("/");
    entry.write_text(
      %"$includes\$(import \"$root/etc/lisp-bindings.xlisp\")
macro Expression \$module.targets() =>
  \$(lisp.native.targets (_x2c.native-meta.declared '$declared));
$exports");
  }
  catch %(io-fail *detail): x2c_host_error(detail);
}

// finishing a build

/** Compiles registered C sources and then archives or links the final output.
    Returns zero for success and one when compilation or the final native
    action fails. Compile-only requests stop after objects. Static archives
    reuse their recorded inputs. Native modules and executables always link
    because library selection and implicit linker inputs are not in the
    fingerprint. An identical relinked module keeps its old file so consumers
    stay current. The archiver or linker writes a private sibling that
    replaces the output by rename, so a concurrent build finds the whole
    previous artifact or the whole new one. Mapped macOS debug executables
    also produce a companion dSYM before cleanup; failed symbol assembly
    fails the build and preserves intermediates.
*/
int Build.finish(Build b) {
  b._place_unit_headers();
  if (b._compile_sources()) return 1;
  if (b.request.compile_only) return 0;
  if (b.request.command == <run> && !b.output) b.output = %"${b.work_dir}/run";
  List inputs = b._final_inputs();
  ToolAction action = b._final_action(b.output, inputs);
  Symbol phase = action.phase, int count = inputs.len();
  b.final_at = report_now_us();
  report_progress(phase, 0, 1, b.output);
  String record = b._final_record();
  int ok = 1;
  uint64_t hash = record ? b._action_fingerprint(action, inputs, ok) : 0;
  if (ok && b._archive_current(phase, record, hash))
    return b._keep_output(phase, count);
  int status = b.request.dry_run ? action.run() : b._publish(inputs);
  if (status < 0) return b._keep_output(phase, count);
  if (status || b._dsym() || b._archive_extensions()) return 1;
  b._report_final(phase, count, 0);
  if (record && ok) _state_write(record, hash);
  return 0;
}

/* A unit that includes another unit through a directory, as in
   `#include "lib/inner.x"`, names that unit's generated header by the same
   path from its own generated directory. Copying the header to that path
   lets the include resolve as it does beside the sources. */
static void Build._place_unit_headers(Build b) {
  if (b.request.dry_run || b.units.len() < 2) return;
  Map headers = {};
  foreach (String unit, b.units)
    headers[Path.absolute(unit)] = _unit_file(b._unit_dir(unit), unit, ".h");
  foreach (String unit, b.units) b._place_includes(headers, unit);
}

static void Build._place_includes(Build b, Map headers, String unit) {
  String directory = b._unit_dir(unit);
  List searched = %(${Path.dirname(unit)} @{b.request.include_dirs});
  foreach (String suffix, %(".h" ".c")) {
    String text = Path.read_text(_unit_file(directory, unit, suffix));
    foreach (String line, text.split_lines(0)) {
      String target = _unit_include(line);
      if (target) _place_header(headers, searched, directory, target);
    }
  }
}

/* The target of a generated `#include "dir/name.h"` line that reaches a
   header through a directory, or NULL. */
static String _unit_include(String line) {
  String text = line.strip(" \t");
  if (!text.startswith("#include \"") || !text.endswith(".h\"")) return NULL;
  String target = text[10:text.len() - 1];
  return "/" in target ? target : NULL;
}

/* Copies the generated header of the included unit, found along the include
   search, to `target` under `directory`. */
static void _place_header(
  Map headers, List searched, String directory, String target) {
  String source = %"${target[:target.len() - 2]}.x";
  foreach (String dir, searched) {
    Var header;
    if (!headers.try_get(Path.join(dir, source).absolute(), header)) continue;
    Path placed = Path.join(directory, target);
    placed.dirname().make_dirs();
    Path.copy_file(header, placed);
    return;
  }
}

// native compilation

/* One source's compile. A job with a state record first preprocesses into
   `preprocessed`, whose text completes its fingerprint, and compiles only
   when that fingerprint misses. */
typedef struct CcJob {
  ToolRun execution, ToolAction action;
  String source, object, depfile, state_path, preprocessed;
  uint64_t fingerprint;
  int fingerprinted;
} CcJob;

/* The jobs one build has running, at most `request.jobs`. */
typedef struct CcPool {
  Build b;
  CcJob *running;
  int count;
} CcPool;

/* Compiles every C source and reports the phase. Returns nonzero when a
   compile failed. */
static int Build._compile_sources(Build b) {
  if (b.compile_commands != NULL) b.compile_directory = Path.absolute(".");
  CcPool pool = {
    .b = b, .running = Scope.calloc(b.request.jobs, sizeof(CcJob))};
  b.cc_n = b.c_sources.len();
  b.cc_start = report_now_us();
  int failed = 0;
  foreach (String source, b.c_sources) {
    failed = pool.add(source);
    if (failed) break;
  }
  while (pool.count) failed |= pool.wait();
  Scope.free(pool.running);
  if (failed || !b.cc_n) return failed;
  String noun = b.cc_n == 1 ? "C file" : "C files";
  report_phase(
    <compile>, b.cc_n, noun, b.cc_cached, report_now_us() - b.cc_start);
  return 0;
}

/* Starts compiling `source` once the ready jobs finish, and waits for one
   when every slot is busy. Returns nonzero when a finished job failed. */
static int CcPool.add(CcPool *pool, String source) {
  Build b = pool.b;
  report_progress(<compile>, b.cc_done, b.cc_n, source);
  List directories = b._include_dirs(source);
  CcJob job = b._compile_job(source, directories);
  if (pool.reap(0)) return 1;
  ToolAction step = job.preprocessed ?
    b.toolchain.preprocess_action(source, job.preprocessed, directories) :
    job.action;
  job.execution = step.start();
  pool.running[pool.count++] = job;
  return pool.count >= b.request.jobs && pool.wait();
}

/* The compile of a generated source searches its own directory first, then
   each generated and package directory once. */
static List Build._include_dirs(Build b, String source) {
  Array directories = [];
  if (source.startswith(b.gen_root)) directories.push(Path.dirname(source));
  foreach (Var directory, b.gen_dirs)
    if (!(directory in directories)) directories.push(directory);
  return directories.list_free();
}

/* Plans the compile of `source` and records its object and compilation
   database entry. */
static CcJob Build._compile_job(Build b, String source, List directories) {
  String key = _key(source), object = %"${b.obj_root}/$key.o";
  if (b.request.compile_only && !b.request.inputs.cdr()) object = b.output;
  String depfile = %"${b.dep_root}/$key.d";
  CcJob job = {
    .action = b.toolchain.compile_action(source, object, depfile, directories),
    .source = source, .object = object, .depfile = depfile};
  b.objects.push(object);
  if (b.compile_commands != NULL)
    b.compile_commands.push(b._compile_command(job));
  if (!b.state_root) return job;
  job.state_path = b._state_path("c", source);
  // Per process: concurrent builds of one project share `dep_root`.
  if (!b.request.dry_run)
    job.preprocessed = %"${b.dep_root}/$key.${_process_suffix()}.i";
  return job;
}

static String Build._compile_command(Build b, CcJob job) {
  Map entry = {
    directory: b.compile_directory, file: job.source, output: job.object,
    arguments: job.action.arguments
  };
  return %"  ${Var.json(entry)}";
}

/** Publishes collected native compilation entries as one JSON database.
    `commands` holds serialized entries from each completed build target.
    The destination's parent must exist. A failed write preserves the
    existing database, reports a diagnostic, and returns zero.
*/
int compile_commands_write(String path, Array commands) {
  String text = %"[\n${",\n".join(commands)}\n]\n";
  try {
    file_publish(%($path $text));
    report_line(<muted>, %"  Compilation database $path");
    return 1;
  }
  catch %((!or not-found io-fail) *): {}
  fprintf(stderr, "x2c: error: cannot write compilation database: %s\n", path);
  return 0;
}

/* Finishes the ready jobs from slot `i` on. Returns nonzero when one
   failed. */
static int CcPool.reap(CcPool *pool, int i) {
  int failed = 0;
  while (i < pool.count) {
    int status = pool.running[i].execution.ready() ? pool.finish(i) : -1;
    if (status < 0) i++;
    else failed |= status;
  }
  return failed;
}

/* Waits until one job finishes, then finishes the ready jobs after it. A
   lone job uses the ordinary blocking wait; parallel jobs keep their own
   statuses and captures. The short idle delay bounds polling without a
   global child signal handler or consuming another owner's child status. */
static int CcPool.wait(CcPool *pool) {
  for (;;) {
    for (int i = 0; i < pool.count; i++) {
      if (pool.count > 1 && !pool.running[i].execution.ready()) continue;
      int status = pool.finish(i);
      if (status >= 0) return status | pool.reap(i);
    }
    usleep(1000);
  }
}

/* Finishes the step job `i` runs. A job that is done or failed leaves the
   pool; one whose preprocessing started its compile stays, for -1. */
static int CcPool.finish(CcPool *pool, int i) {
  CcJob *at = pool.running + i;
  int status = pool.b._finish_job(at);
  if (status < 0) return -1;
  pool.count--;
  memmove(at, at + 1, (pool.count - i) * sizeof(CcJob));
  return status;
}

/* Waits for the step `job` runs. Returns -1 when its preprocessing started
   the compile in the same slot, 1 when it failed, and 0 when it is done. */
static int Build._finish_job(Build b, CcJob *job) {
  int status = job.execution.wait();
  if (job.preprocessed) {
    int step = b._after_preprocess(job, status);
    if (step) return step;
  }
  else if (status) return 1;
  else if (job.fingerprinted && !b.request.dry_run)
    _state_write(job.state_path, job.fingerprint);
  b.cc_done++;
  report_progress(<compile>, b.cc_done, b.cc_n, job.source);
  return 0;
}

/* A fingerprint this run cannot read is a cache miss: the source compiles
   and records nothing. Only the preprocessing command itself failing is an
   error, and the C compiler has already said why. Returns -1 when the
   compile starts, 1 on failure, and 0 when the object is current. */
static int Build._after_preprocess(Build b, CcJob *job, int status) {
  int ok = 1;
  if (!status) job.fingerprint = b._compile_fingerprint(job, ok);
  unlink(job.preprocessed);
  job.preprocessed = NULL;
  if (status) return 1;
  job.fingerprinted = ok;
  if (ok && b._compile_current(job)) return 0;
  job.execution = job.action.start();
  return -1;
}

/* The preprocessed text is scratch named for this process, so only what it
   says extends the compile fingerprint. */
static uint64_t Build._compile_fingerprint(Build b, CcJob *job, int &ok) =>
  x2c_fnv_file(
    b._action_fingerprint(job.action, NULL, ok), job.preprocessed, ok);

static int Build._compile_current(Build b, CcJob *job) {
  if (access(job.object, R_OK) || access(job.depfile, R_OK)) return 0;
  if (!_state_matches(job.state_path, job.fingerprint)) return 0;
  if (b.request.verbose)
    fprintf(stderr, "x2c: up-to-date compile %s\n", job.source);
  b.cc_cached++;
  return 1;
}

// the final action

static List Build._final_inputs(Build b) {
  Array inputs = [];
  foreach (Var value, b.objects) inputs.push(value);
  foreach (Var value, b.native_inputs) inputs.push(value);
  return inputs.list_free();
}

static ToolAction Build._final_action(Build b, String output, List inputs) {
  if (b.request.kind == <static-lib>)
    return b.toolchain.archive_action(output, inputs);
  if (b.request.kind == <module>)
    return b.toolchain.module_action(output, inputs);
  return b.toolchain.link_action(output, inputs);
}

/* The build records a final fingerprint only for a static library. */
static String Build._final_record(Build b) =>
  b.state_root && b.request.kind == <static-lib> && !b.request.dry_run ?
    b._state_path("final", b.output) : NULL;

static int Build._archive_current(
  Build b, Symbol phase, String record, uint64_t hash) {
  if (!record || access(b.output, R_OK)) return 0;
  if (!_state_matches(record, hash)) return 0;
  if (b.request.verbose)
    fprintf(stderr, "x2c: up-to-date %s %s\n", phase.str(), b.output);
  return 1;
}

/* The published output stays: every input counts as cached, and the build
   succeeds. */
static int Build._keep_output(Build b, Symbol phase, int count) {
  b.final_cached = 1;
  b._report_final(phase, count, count);
  return 0;
}

static void Build._report_final(
  Build b, Symbol phase, int count, int cached) {
  report_progress(phase, 1, 1, b.output);
  report_phase(
    phase, count, _input_noun(phase, count), cached,
    report_now_us() - b.final_at);
}

static String _input_noun(Symbol phase, int count) {
  if (phase == <archive>) return count == 1 ? "object" : "objects";
  return count == 1 ? "input" : "inputs";
}

/* The tool writes the output in a private sibling directory, and rename
   puts it in place; the fingerprint and the receipts use the output's own
   path. The staged file keeps the output's basename, which a linker may
   record in the file (the macOS ad-hoc signature does), so its bytes carry
   no process-specific name. Returns -1 when a relinked module is
   unchanged. */
static int Build._publish(Build b, List inputs) {
  String name = Path.basename(b.output);
  String staging = %"${Path.dirname(b.output)}/.$name.${_process_suffix()}";
  Path.make_dirs(staging);
  String staged = %"$staging/$name";
  int status = b._replace(b._final_action(staged, inputs), staged);
  Path.remove_tree(staging);
  if (status < 0 && b.request.verbose)
    fprintf(stderr, "x2c: unchanged link %s\n", b.output.str());
  return status;
}

/* A module relinks even when its named operands are unchanged: -L/-l can
   select an archive whose bytes changed. An identical module keeps the
   published file, so consumers can reuse their translations. */
static int Build._replace(Build b, ToolAction action, String staged) {
  if (action.run()) return 1;
  if (b.request.kind == <module> && _same_file_bytes(staged, b.output))
    return -1;
  if (!rename(staged, b.output)) return 0;
  fprintf(
    stderr, "x2c: error: cannot replace %s: %s\n", b.output.str(),
    strerror(errno));
  return 1;
}

static int _same_file_bytes(String first, String second) {
  FILE *left = fopen(first.str(), "rb");
  if (!left) return 0;
  defer fclose(left);
  FILE *right = fopen(second.str(), "rb");
  if (!right) return 0;
  defer fclose(right);
  unsigned char a[16384], b[16384];
  for (;;) {
    size_t na = fread(a, 1, sizeof(a), left);
    size_t nb = fread(b, 1, sizeof(b), right);
    if (na != nb || memcmp(a, b, na)) return 0;
    if (na < sizeof(a)) return !ferror(left) && !ferror(right);
  }
}

// companion artifacts

/* A mapped macOS debug build keeps its symbols in a companion dSYM. */
static int Build._dsym(Build b) {
  if (!b._mapped_debug()) return 0;
  String output = b.output, symbols = %"$output.dSYM";
  return tool_action_new(
    <dsym>, %("dsymutil" $output "-o" $symbols), b.request.verbose,
    b.request.dry_run).run();
}

/* Native flags are ordered: an explicit -g0 can override a profile's -g. */
static int Build._mapped_debug(Build b) {
#ifdef __APPLE__
  if (!b.request.source_map || b.request.kind == <static-lib>) return 0;
  List levels = %(
    "-g" "-g1" "-g2" "-g3" "-ggdb" "-ggdb1" "-ggdb2" "-ggdb3"
    "-gline-tables-only" "-gmlt");
  int enabled = 0;
  foreach (String flag, b.toolchain.cc_args)
    if (flag in %("-g0" "-ggdb0")) enabled = 0;
    else if (flag in levels || flag.startswith("-gdwarf")) enabled = 1;
  return enabled;
#else
  return 0;
#endif
}

/* A compiler that links packages in keeps their objects beside it, in an
   archive named by its identity, and their headers, for the project meta
   helper to compile and link against. */
static int Build._archive_extensions(Build b) {
  if (!b.request.extensions || b.request.dry_run) return 0;
  String directory = %"${b.output}.extensions";
  if (Path.exists(directory)) Path.remove_tree(directory);
  String include = %"$directory/include";
  Path.make_dirs(include);
  Map sources = {};
  foreach (String package, b.request.extensions)
    b._extension_sources(package, include, sources);
  Array objects = [], int i = 0;
  foreach (String source, b.c_sources) {
    if (source in sources) objects.push(b.objects[i]);
    i++;
  }
  String identity = x2c_file_identity(b.output);
  return b.toolchain.archive_action(
    %"$directory/$identity.a", objects.list_free()).run();
}

/* Adds the C sources of `package`'s units to `sources` and copies the
   headers of its x2c units into `include`. */
static void Build._extension_sources(
  Build b, String package, String include, Map sources) {
  String root = %"${Path.absolute(package)}/src/";
  foreach (String input, b.request.inputs) {
    if (!input.startswith(root)) continue;
    if (input.endswith(".c")) {
      sources[input] = 1;
      continue;
    }
    String directory = b.generated_dir(input);
    sources[_unit_file(directory, input, ".c")] = 1;
    Path.write_text(
      _unit_file(include, input, ".h"),
      Path.read_text(_unit_file(directory, input, ".h")));
  }
}

// receipts

/** Prints the completed build receipt and artifact details when enabled. */
void Build.report_success(Build b) {
  if (!report_receipts()) return;
  report_line(<success>, b._headline());
  if (b.xlat_n) report_generated(b.xlat_n, b.gen_bytes);
  if (b.cc_n) {
    int n = b.request.jobs;
    String jobs = n == 1 ? "1 job" : %"$n jobs";
    report_line(<muted>, %"  Compiled with ${b.toolchain.cc} using $jobs");
  }
  if (!b.request.compile_only) report_line(<muted>, b._final_tool());
  report_line(<muted>, %"  Intermediates ${b.work_dir} (${b._retention()})");
  if (b.request.compile_only) return;
  String size = report_size(report_file_bytes(b.output));
  report_line(<muted>, %"  Output ${b.output} ($size)");
  if (b._mapped_debug())
    report_line(<muted>, %"  Debug symbols ${b.output}.dSYM");
}

static String Build._headline(Build b) {
  String duration = report_duration(report_now_us() - b.started_at);
  String cache = b._all_cached() ? " (up to date)" : "";
  String label = b.request.label ? %" target '${b.request.label}'" : "";
  String built = %"Built$label", tail = %"in $duration$cache";
  if (!b.request.compile_only)
    return %"$built ${_kind_name(b.request.kind)} ${b.output} $tail";
  int objects = b.objects.len();
  if (objects == 1) return %"$built object ${b.output} $tail";
  return %"$built $objects object files in ${b.obj_root} $tail";
}

static int Build._all_cached(Build b) {
  if (b.xlat_n && b.xlat_cached != b.xlat_n) return 0;
  if (b.cc_n && b.cc_cached != b.cc_n) return 0;
  if (!b.request.compile_only && !b.final_cached) return 0;
  return b.xlat_n || b.cc_n || b.final_cached;
}

static String _kind_name(Symbol kind) {
  if (kind == <static-lib>) return "static library";
  if (kind == <module>) return "native module";
  return "executable";
}

static String Build._final_tool(Build b) =>
  b.request.kind == <static-lib> ?
    %"  Archived with ${b.toolchain.ar}" : %"  Linked with ${b.toolchain.cc}";

static String Build._retention(Build b) {
  if (!b.temporary) return "retained";
  if (b.request.command == <run>) return "temporary; removed after run";
  return "temporary; removed after build";
}

// running and cleanup

/** Runs the built output with the request's arguments and returns its status.
    A dry run prints the action without launching the program.
*/
int Build.run_program(Build b) {
  report_line(<phase>, %"Running ${b.output}");
  ToolAction action = tool_action_new(
    <run>, %(${b.output} @{b.request.run_args}), b.request.verbose,
    b.request.dry_run);
  action.as_program();
  return action.run();
}

/** Removes the temporary work tree after a successful real build.
    Failed builds, retained directories, and dry runs are left untouched; a
    removal failure emits a warning and is not returned to the caller.
*/
void Build.cleanup(Build b, int success) {
  if (!success || !b.temporary || b.request.dry_run) return;
  try Path.remove_tree(b.work_dir);
  catch %(io-fail *):
    fprintf(
      stderr, "x2c: warning: cannot remove temporary build directory: %s\n",
      b.work_dir);
}

// scripts

/** Returns the local `.x` files a script unit includes, which the script's
    program must translate and link. The script's translation depfile already
    lists every file the translation read, so helpers of helpers appear too.
    Runtime and package sources are excluded; their objects are archived.
*/
List Build.script_helpers(Build b) {
  String script = b.request.inputs.car(), root = x2c_get_root();
  List excluded = %("$root/lib/" "$root/include/" "$root/builds/")
    .append(b.request.package_roots().map(%!(dir) => %"$dir/"));
  String depfile = _unit_file(b._unit_dir(script), script, ".d");
  Array helpers = [];
  foreach (String path, _depfile_inputs(depfile)) {
    if (!x2c_source_file(path) || path == script || path in helpers) continue;
    if (excluded.any(%!(String prefix) => path.startswith(prefix))) continue;
    helpers.push(path);
    b.xlat_n++;
  }
  return helpers.list_free();
}

/** Moves a script's built executable, and its debug symbols on macOS, to
    `executable` and records what it was built from, so
    `CliRequest.script_current` can reuse it. The record lists the script's
    translation and compile prerequisites, package archives, and the runtime
    archive. A file changed while the build ran records nothing, so the
    executable is never reused for source it was not built from.
    Raises: `<io-fail>` when the executable cannot be moved.
*/
void Build.publish_script(Build b, String executable) {
  Path.move_to(b.output, executable);
  if (b._mapped_debug()) {
    Path symbols = %"$executable.dSYM";
    symbols.remove_tree();
    Path.move_to(%"${b.output}.dSYM", symbols);
  }
  List files = b._script_files();
  List paths = files.append(b._script_directories(files));
  int ok = 1;
  uint64_t hash = _script_fingerprint(b.request, b.toolchain.cc, paths, ok);
  if (ok && b._files_unchanged(files))
    _state_write_lines(%"${b.state_root}/script", hash, paths);
}

static List Build._script_files(Build b) {
  String script = b.request.inputs.car();
  String depfile = _unit_file(b._unit_dir(script), script, ".d");
  Array files = [];
  foreach (String path, _depfile_inputs(depfile)) files.push(path);
  foreach (String source, b.c_sources)
    foreach (String path, _depfile_inputs(%"${b.dep_root}/${_key(source)}.d"))
      files.push(path);
  foreach (Var path, b.native_inputs) files.push(path);
  files.push(b.toolchain.runtime_lib);
  return files.list_free();
}

/* Every directory a compile or link of the script searches: explicit include
   and library options, the compiler's own search lists, and the directory of
   each prerequisite, where quoted includes look first. */
static List Build._script_directories(Build b, List prerequisites) {
  Array directories = [];
  foreach (Var directory, b.request.include_dirs) directories.push(directory);
  directories.push(b.toolchain.include_dir);
  _add_option_dirs(directories, b.toolchain.cc_args);
  _add_option_dirs(directories, b.toolchain.ld_args);
  foreach (String path, prerequisites) directories.push(Path.dirname(path));
  foreach (Var directory, b.toolchain.search_directories())
    directories.push(directory);
  return b._search_entries(directories);
}

/* An option's directory is joined to its flag or is the next argument. */
static void _add_option_dirs(Array directories, List args) {
  for (List p = args; p; p = p.cdr()) {
    String arg = p.car();
    foreach (String flag, %("-I" "-iquote" "-isystem" "-idirafter" "-L")) {
      if (!arg.startswith(flag)) continue;
      if (arg.len() > flag.len()) directories.push(arg[flag.len():]);
      else if (p.cdr()) directories.push(p.cadr());
      break;
    }
  }
}

/* Each directory once, absolute and ending in `/`, outside the work
   directory. */
static List Build._search_entries(Build b, Array directories) {
  Array unique = [];
  String work = Path.absolute(b.work_dir);
  foreach (Var value, directories) {
    String directory = Path.absolute(value);
    if (directory.startswith(work)) continue;
    String entry = directory.endswith("/") ? directory : %"$directory/";
    if (!(entry in unique)) unique.push(entry);
  }
  return unique.list_free();
}

/** Reports whether the script executable under `directory` still matches
    everything recorded when it was built.
*/
int CliRequest.script_current(CliRequest request, String directory) {
  String record = %"$directory/.x2c-state/script";
  if (access(%"$directory/run", X_OK) || access(record, R_OK)) return 0;
  List lines = NULL;
  try lines = Path.read_text(record).split_lines(0);
  catch %(io-fail *): return 0;
  String cc = toolchain_new(request).cc;
  int ok = 1;
  uint64_t hash = _script_fingerprint(request, cc, lines.cdr(), ok);
  return ok && _state_matches(record, hash);
}

/* A script's executable is reused without translating, preprocessing, or
   linking, so its fingerprint covers everything those steps would read: the
   request's options, the environment the C compiler and linker consult, the
   contents of every recorded file, and the modification time of every
   recorded directory. */
static uint64_t _script_fingerprint(
  CliRequest request, String cc, List prerequisites, int &ok) {
  uint64_t hash = _state_base(request, cc, ok);
  hash = _state_text(hash, "script");
  hash = _state_list(hash, request.inputs);
  hash = _state_list(hash, request.include_dirs);
  hash = _state_list(hash, request.package_roots());
  hash = _state_list(hash, request.cpp_args);
  hash = _state_list(hash, request.cc_args);
  hash = _state_list(hash, request.ld_args);
  hash = _state_text(
    hash, request.source_map ? "source-map" : "generated-lines");
  foreach (String name, %("CPATH" "C_INCLUDE_PATH" "LIBRARY_PATH" "SDKROOT"))
    hash = _state_text(hash, Env.get(name));
  foreach (String path, prerequisites) hash = _state_entry(hash, path, ok);
  return hash;
}

/* A directory entry ends in `/` and adds its modification time; a header or
   library added where a search would now find it changes that time. */
static uint64_t _state_entry(uint64_t hash, String path, int &ok) {
  if (!path.endswith("/")) return _state_file(hash, path, ok);
  String time =
    Path.is_dir(path) ? "%.9f".printf(Path.modified_time(path)) : "absent";
  return _state_text(_state_text(hash, path), time);
}

/* fingerprints

   Every fingerprint starts with the state format, the project or
   direct-build seed, and the compiler and tool contents. Translation adds
   its request modes and depfile inputs, native actions add arguments and
   input contents, and C compilation adds its preprocessor output, so
   changed include resolution and conditional availability count. A missing
   or unreadable input clears `ok`. */

static uint64_t _state_base(CliRequest request, String tool, int &ok) {
  uint64_t hash = UINT64_C(1469598103934665603);
  hash = _state_text(hash, "x2c-state-v1");
  hash = _state_text(hash, request.state_seed);
  String compiler = x2c_compiler_identity();
  if (!compiler) ok = 0;
  hash = _state_text(hash, compiler);
  hash = _state_tool(hash, tool, ok);
  return hash;
}

static uint64_t Build._action_fingerprint(
  Build b, ToolAction action, List inputs, int &ok) {
  uint64_t hash = _state_base(b.request, action.arguments.car(), ok);
  hash = _state_text(hash, action.phase);
  hash = _state_list(hash, action.arguments);
  foreach (String input, inputs) hash = _state_file(hash, input, ok);
  return hash;
}

/* Null text uses 0xff, present text ends with NUL, and each List ends with
   0xfe. These separators distinguish adjacent ordered fingerprint fields. */
static uint64_t _state_text(uint64_t hash, String text) {
  if (!text) return x2c_fnv_bytes(hash, "\xff", 1);
  hash = x2c_fnv_bytes(hash, text, strlen(text));
  return x2c_fnv_bytes(hash, "\0", 1);
}

static uint64_t _state_list(uint64_t hash, List values) {
  foreach (String value, values) hash = _state_text(hash, value);
  return x2c_fnv_bytes(hash, "\xfe", 1);
}

static uint64_t _state_file(uint64_t hash, String path, int &ok) =>
  x2c_fnv_file(_state_text(hash, path), path, ok);

static uint64_t _state_tool(uint64_t hash, String tool, int &ok) {
  String path = "/" in tool ? tool : x2c_find_program(tool);
  if (path) return _state_file(hash, path, ok);
  ok = 0;
  return _state_text(hash, tool);
}

static uint64_t _state_dependencies(uint64_t hash, String depfile, int &ok) {
  List inputs = _depfile_inputs(depfile);
  if (!inputs) ok = 0;
  foreach (String input, inputs) hash = _state_file(hash, input, ok);
  return hash;
}

static List _depfile_inputs(String depfile) {
  File input = fopen(depfile, "r");
  if (!input) return NULL;
  String text = NULL;
  try text = input.string_close();
  catch %(io-fail *): return NULL;
  return translation_depfile_parse(text);
}

// state records

static int _state_matches(String path, uint64_t hash) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %((!or not-found io-fail) *): return 0;
  List lines = text.split_lines(0);
  if (!lines) return 0;
  String first = lines.car();
  return first == _state_line(hash);
}

static String _state_line(uint64_t hash) =>
  "x2c-state-v1 %016llx".printf((unsigned long long) hash);

static void _state_write(String path, uint64_t hash) =>
  _state_write_lines(path, hash, NULL);

/* A write is best effort and publishes through a temporary and rename.
   Lines after the fingerprint list the files it covers, for a reader that
   must check it without rebuilding the list. */
static void _state_write_lines(String path, uint64_t hash, List lines) {
  String text = %"${_state_line(hash)}\n";
  foreach (String line, lines) text = %"$text$line\n";
  try file_publish(%($path $text));
  catch %((!or not-found io-fail) *): {}
}

/* Whether every file the build read still carries the contents it read. A
   fingerprint is taken after the work it describes, so a file written while
   the build ran would record contents the artifact was not built from.
   Recording nothing leaves the artifact in place and rebuilds it next time.
   Every caller asks after hashing, never before: a write that reached the
   hash has already moved the modification time this reads. The build's own
   output under the work directory is not one of those files. */
static int Build._files_unchanged(Build b, List files) {
  String work = %"${Path.absolute(b.work_dir)}/";
  foreach (String path, files) {
    if (Path.absolute(path).startswith(work)) continue;
    if (Path.is_file(path) && Path.modified_time(path) >= b.started_wall)
      return 0;
  }
  return 1;
}

/* Wall-clock seconds in the scale `Path.modified_time` reports, so a build
   can tell whether a file it read has been written since it started. */
static double _wall_seconds(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_REALTIME, &now)) return 0;
  return (double) now.tv_sec + (double) now.tv_nsec / 1e9;
}
