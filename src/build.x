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
    borrows
    the supplied request pointer without copying it; that request must outlive
    the `Build` and may belong outside the per-target
    `Context`. `Toolchain` and
    `Array` storage allocated during preparation follow the current `Scope`,
    while referenced `String`s and `List`s keep their canonical pool lifetimes.
    `cleanup` manages only a temporary filesystem tree.
*/
typedef struct Build {
  CliRequest request;
  Toolchain toolchain;
  String work_dir, gen_root, obj_root, dep_root, state_root, output;
  int temporary, Array c_sources, gen_dirs, native_inputs, objects, units;
  String compile_directory, Array compile_commands;
  unsigned long started_at;
  unsigned long xlat_start;
  unsigned long cc_start;
  unsigned long final_at;
  unsigned long long gen_bytes;
  int xlat_n, xlat_done, xlat_cached, cc_n, cc_done, cc_cached, final_cached;
} *Build;

#pragma private

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include "report.x"

/* Artifact directories and object, dependency, and state paths all use this
   spelling-derived key. The input path is not canonicalized, so its spelling
   is part of incremental cache identity. */
static String _key(String path) {
  String stem = Path.stem(path);
  return %"$stem-%08x".printf(String.hash(path));
}

/* Every incremental fingerprint starts with the state format, project or
   direct-build seed, and compiler and selected tool contents. Translation
   adds its request modes and depfile inputs; native actions add arguments and
   their input contents. C compilation uses the current native preprocessor
   output, so changed include resolution and conditional availability count.
   A missing or unreadable input clears `ok`; state writes are best effort and
   use a temporary followed by rename. */
static uint64_t _state_bytes(uint64_t hash, const void *bytes, size_t length) {
  const unsigned char *data = bytes;
  for (size_t i = 0; i < length; i++) {
    hash ^= data[i];
    hash *= UINT64_C(1099511628211);
  }
  return hash;
}

/* Null text uses 0xff, present text ends with NUL, and each List ends with
   0xfe. These separators distinguish adjacent ordered fingerprint fields. */
static uint64_t _state_text(uint64_t hash, String text) {
  if (!text) return _state_bytes(hash, "\xff", 1);
  hash = _state_bytes(hash, text, strlen(text));
  return _state_bytes(hash, "\0", 1);
}

static uint64_t _state_list(uint64_t hash, List values) {
  foreach (String value, values) hash = _state_text(hash, value);
  return _state_bytes(hash, "\xfe", 1);
}

static uint64_t _state_file(uint64_t hash, String path, int *ok) {
  File input = fopen(path, "rb");
  if (!input) {
    *ok = 0;
    return _state_text(hash, path);
  }
  hash = _state_text(hash, path);
  unsigned char buffer[16384], size_t length;
  while ((length = fread(buffer, 1, sizeof(buffer), input)))
    hash = _state_bytes(hash, buffer, length);
  if (ferror(input)) *ok = 0;
  input.close();
  return hash;
}

static uint64_t _state_tool(uint64_t hash, String tool, int *ok) {
  if (!tool) {
    *ok = 0;
    return hash;
  }
  if (strchr(tool, '/')) return _state_file(hash, tool, ok);
  const char *path = getenv("PATH");
  List dirs = path ? String.new(path).split(%":") : NULL;
  foreach (String dir, dirs) {
    String candidate = dir && dir[0] ? %"$dir/$tool" : tool;
    if (!access(candidate, X_OK)) return _state_file(hash, candidate, ok);
  }
  *ok = 0;
  return _state_text(hash, tool);
}

static uint64_t _state_base(CliRequest request, String tool, int *ok) {
  uint64_t hash = UINT64_C(1469598103934665603);
  hash = _state_text(hash, %"x2c-state-v1");
  hash = _state_text(hash, request.state_seed);
  hash = _state_tool(hash, x2c_get_executable(), ok);
  hash = _state_tool(hash, tool, ok);
  return hash;
}

static List _state_dep_inputs(String depfile) {
  File input = fopen(depfile, "r");
  if (!input) return NULL;
  String text = NULL;
  try text = input.string_close();
  catch %(io-fail *): return NULL;
  return translation_depfile_parse(text);
}

static uint64_t _state_dependencies(uint64_t hash, String depfile, int *ok) {
  List inputs = _state_dep_inputs(depfile);
  if (!inputs) {
    *ok = 0;
    return hash;
  }
  foreach (String input, inputs) hash = _state_file(hash, input, ok);
  return hash;
}

static int _state_matches(String path, uint64_t hash) {
  File input = fopen(path, "r");
  if (!input) return 0;
  char line[80], extra;
  unsigned long long saved = 0;
  int matched =
    fgets(line, sizeof(line), input) &&
    sscanf(line, "x2c-state-v1 %llx %c", &saved, &extra) == 1;
  input.close();
  if (!matched) return 0;
  return saved == (unsigned long long) hash;
}

/* Lines after the fingerprint name the files it covers, for a reader that
   must check it without rebuilding the list. */
static void _state_write_lines(String path, uint64_t hash, List lines) {
  String temporary = %"$path.tmp.%ld".printf((long) getpid());
  File output = fopen(temporary, "w");
  if (!output) return;
  int ok = output.printf(
    "x2c-state-v1 %016llx\n", (unsigned long long) hash) >= 0;
  foreach (String line, lines)
    if (output.printf("%s\n", line) < 0) ok = 0;
  if (output.close()) ok = 0;
  if (!ok || rename(temporary, path)) unlink(temporary);
}

static void _state_write(String path, uint64_t hash) {
  _state_write_lines(path, hash, NULL);
}

/* Creates `path` and missing parents, returning zero when it cannot. */
int _build_mkdirs(String path) {
  try Path.make_dirs(path);
  catch %(not-found *): return 0;
  catch %(io-fail *): return 0;
  return 1;
}

static void _require_directory(String path) {
  if (!_build_mkdirs(path))
    x2c_driver_error(%"cannot create build directory: $path");
}

static void _validate_input(String input) {
  struct stat info;
  if (!input || stat(input, &info))
    x2c_driver_error(%"input does not exist: $input");
  if (S_ISDIR(info.st_mode))
    x2c_driver_error(%"input is a directory: $input");
  if (!S_ISREG(info.st_mode))
    x2c_driver_error(%"input is not a regular file: $input");
  if (!(input.endswith(%".x") || input.endswith(%".c") ||
        input.endswith(%".o") || input.endswith(%".a")))
    x2c_driver_error(%"unsupported build input: $input");
}

/** Validates a native build request and returns its `Scope`-owned build state.
    It writes the default state seed and selected compiler and archiver back
    to `request`, chooses output and intermediate paths, and creates artifact
    directories unless this is a dry run. Invalid inputs or setup print a
    diagnostic and exit with status 2.
*/
Build CliRequest.prepare(CliRequest c) {
  if (!c.inputs)
    x2c_driver_error("build requires input operands or a project manifest");
  int compilable = 0, input_count = 0;
  foreach (String input, c.inputs) {
    input_count++;
    _validate_input(input);
    if (input.endswith(%".x") || input.endswith(%".c")) compilable++;
    if (c.kind == <static-lib> && input.endswith(%".a"))
      x2c_driver_error(
        %"cannot nest an archive in a static library: $input");
  }
  if (c.compile_only) {
    if (compilable != input_count)
      x2c_driver_error("compile-only accepts only .x and .c inputs");
    if (c.inputs.cdr() && c.output)
      x2c_driver_error(
        "--output is ambiguous with multiple compile-only inputs");
    if (c.inputs.cdr() && !c.build_dir)
      x2c_driver_error("multiple compile-only inputs require --build-dir");
  }
  Build state = Scope.calloc(1, sizeof(struct Build));
  state.request = c;
  if (!c.state_seed) c.state_seed = "direct";
  state.toolchain = toolchain_new(
    c.cc, c.ar, c.cpp_args, c.cc_args,
    c.ld_args, c.verbose, c.dry_run);
  c.cc = state.toolchain.cc; c.ar = state.toolchain.ar;
  state.c_sources = %[];
  state.gen_dirs = %[];
  state.units = %[];
  state.native_inputs = %[];
  state.objects = %[];
  if (c.compile_commands && !c.dry_run) state.compile_commands = %[];
  if (c.output) state.output = c.output;
  else if (c.command == <run>) state.output = NULL;
  else if (c.compile_only && c.inputs && !c.inputs.cdr())
    state.output = %"${Path.stem(c.inputs.car().string())}.o";
  else if (c.kind == <static-lib>) {
    String stem = c.inputs ?
                  Path.stem(c.inputs.car().string()) : %"target";
    state.output = %"lib$stem.a";
  }
  else state.output = "a.out";
  state.started_at = report_now_us();
  if (c.build_dir) state.work_dir = c.build_dir;
  else if (c.temps_dir) state.work_dir = c.temps_dir;
  else if (c.save_temps) state.work_dir = ".x2c-build";
  else if (c.dry_run) {
    state.work_dir = "/tmp/x2c-build-dry-run";
    state.temporary = 1;
  }
  else {
    char work[] = "/tmp/x2c-build-XXXXXX", *directory = mkdtemp(work);
    if (!directory)
      x2c_driver_error("cannot create temporary build directory");
    state.work_dir = String.new(directory);
    state.temporary = 1;
  }
  state.gen_root = %"${state.work_dir}/gen";
  state.obj_root = %"${state.work_dir}/obj";
  state.dep_root = %"${state.work_dir}/dep";
  if (c.build_dir) state.state_root = %"${state.work_dir}/.x2c-state";
  if (!c.dry_run) {
    _require_directory(state.work_dir);
    _require_directory(state.gen_root);
    _require_directory(state.obj_root);
    _require_directory(state.dep_root);
    if (state.state_root) _require_directory(state.state_root);
  }
  foreach (String input, c.inputs) {
    if (input.endswith(%".x")) state.xlat_n++;
    if (input.endswith(%".c")) state.c_sources.push(input);
    else if (input.endswith(%".o") || input.endswith(%".a"))
      state.native_inputs.push(input);
  }
  String runtime_lib = state.toolchain.runtime_lib;
  if (!c.compile_only && c.kind == <executable> &&
      access(runtime_lib, R_OK))
    x2c_driver_error(%"matching x2c runtime is unavailable: $runtime_lib");
  return state;
}

/** Returns the generated-file directory for `input`.
    The directory is derived from the input path and created unless this is
    a dry run. Native registration belongs to `Build.add_generated`.
*/
String Build.generated_dir(Build state, String input) {
  String directory = %"${state.gen_root}/${_key(input)}";
  if (!state.request.dry_run) _require_directory(directory);
  return directory;
}

static uint64_t _translation_fingerprint(
  Build state, String input, String directory, int *ok) {
  uint64_t hash = _state_base(state.request, state.toolchain.cc, ok);
  hash = _state_text(hash, %"translate");
  hash = _state_text(hash, input);
  CliRequest request = state.request;
  hash = _state_list(hash, request.include_dirs);
  hash = _state_list(hash, request.package_roots());
  hash = _state_list(hash, request.cpp_args);
  hash = _state_text(hash, request.no_cpp ? %"no-cpp" : %"cpp");
  hash = _state_text(hash, request.live_symbols ? %"live" : %"prelude");
  hash = _state_text(hash, request.cpp_symbols ? %"cpp-symbols" : %"raw");
  hash = _state_text(
    hash, request.source_map ? %"source-map" : %"generated-lines");
  String depfile = %"$directory/${Path.stem(input)}.d";
  return _state_dependencies(hash, depfile, ok);
}

/** Reports whether translated C and header artifacts match current inputs.
    Returns zero without retained state, during a dry run, when either output
    is absent, or when any compiler, tool, option, depfile, or dependency
    fingerprint cannot be read or differs.
*/
int Build.translation_current(Build state, String input, String directory) {
  if (!state.state_root || state.request.dry_run) return 0;
  String stem = Path.stem(input);
  if (access(%"$directory/$stem.c", R_OK)) return 0;
  if (access(%"$directory/$stem.h", R_OK)) return 0;
  if (access(%"$directory/$stem.xi", R_OK)) return 0;
  int ok = 1;
  uint64_t hash = _translation_fingerprint(state, input, directory, &ok);
  String path = %"${state.state_root}/x-${_key(input)}";
  int current = ok && _state_matches(path, hash);
  if (current && state.request.verbose)
    fprintf(stderr, "x2c: up-to-date translate %s\n", input);
  return current;
}

/** Records the successful translation fingerprint when retained state exists.
    Dry runs and incomplete fingerprints are ignored. Writing the private
    state file is best effort; after a write or rename failure, cleanup
    attempts to unlink the temporary file but cannot guarantee its removal.
*/
void Build.record_translation(Build state, String input, String directory) {
  if (!state.state_root || state.request.dry_run) return;
  int ok = 1;
  uint64_t hash = _translation_fingerprint(state, input, directory, &ok);
  if (ok) _state_write(%"${state.state_root}/x-${_key(input)}", hash);
}

/* A file under a registered --package-dir root belongs to the package
   directory named by the next path component. */
static String _package_directory(List roots, String path) {
  char buffer[PATH_MAX];
  if (!realpath(path, buffer)) return NULL;
  String canonical = %"$buffer";
  foreach (String candidate, roots) {
    if (!realpath(candidate, buffer)) continue;
    String directory = x2c_package_directory(%"$buffer", canonical);
    if (directory) return directory;
  }
  return NULL;
}

/* A package's own sources are the files the compiler puts in package mode;
   a test or example inside the package directory imports it instead, so it
   links the archive like any other consumer. */
static String _package_source_directory(List roots, String path) {
  char buffer[PATH_MAX], String directory = _package_directory(roots, path);
  if (!directory || !realpath(path, buffer)) return NULL;
  return x2c_package_source(directory, %"$buffer") ? directory : NULL;
}

/* The one line of link flags the package needs besides its archive. Both
   files come from the package's build target, so a missing one is the same
   unbuilt-package mistake the archive check above reports; dropping the
   flags instead leaves the consumer with undefined symbols at link. */
static void _package_link_flags(Build state, String name, String path) {
  if (access(path, R_OK))
    x2c_driver_error(%"package '$name' is not built: $path");
  File input = fopen(path, "r");
  if (!input) return;
  String text = NULL;
  try text = input.string_close();
  catch %(io-fail *): return;
  Toolchain toolchain = state.toolchain;
  Array flags = %[];
  foreach (Var word, text.words()) flags.push(word);
  toolchain.ld_args = toolchain.ld_args.append(flags.list_free());
}

/* Imported packages reach the build through the unit's recorded
   dependencies. Only an import pulls a package file into a consumer, and
   the record is present even when the translation result was reused. */
static void Build._link_packages(Build state, String input, String directory) {
  List roots = state.request.package_roots();
  if (!roots) return;
  String own = _package_source_directory(roots, input);
  String depfile = %"$directory/${Path.stem(input)}.d";
  foreach (String dependency, _state_dep_inputs(depfile)) {
    String package = _package_directory(roots, dependency);
    if (!package || (own && package == own)) continue;
    String builds = %"$package/builds";
    if (state.gen_dirs.contains(builds)) continue;
    state.gen_dirs.push(builds);
    // A package may publish a vendored foreign header from its src.
    state.gen_dirs.push(%"$package/src");
    String name = package.split(%"/").last();
    String response = %"$builds/$name.native.rsp";
    CliRequest native = NULL;
    if (!access(response, F_OK)) {
      native = cli_package_options(response, package);
      state.toolchain.cc_args = state.toolchain.cc_args.append(native.cc_args);
    }
    // Libraries take native compile options too; only programs link archives.
    if (state.request.kind == <static-lib>) continue;
    String archive = %"$builds/lib$name.a";
    if (access(archive, R_OK))
      x2c_driver_error(%"package '$name' is not built: $archive");
    state.native_inputs.push(archive);
    if (native)
      state.toolchain.ld_args = state.toolchain.ld_args.append(native.ld_args);
    else _package_link_flags(state, name, %"$builds/$name.link");
  }
}

/** Registers generated artifacts for native compilation.
    Counts the C and header bytes, appends the C source, and adds include
    directories and native compile options for imported packages. Programs
    also add ordered package archives and link flags; an absent archive prints
    a diagnostic and exits with status 2. Static libraries skip link inputs.
*/
void Build.add_generated(Build state, String input, String directory) {
  String stem = Path.stem(input), source = %"$directory/$stem.c";
  String header = %"$directory/$stem.h";
  state.gen_bytes += report_file_bytes(source);
  state.gen_bytes += report_file_bytes(header);
  state.c_sources.push(source);
  state.units.push(input);
  if (!state.gen_dirs.contains(directory)) state.gen_dirs.push(directory);
  state._link_packages(input, directory);
}

/** Starts translation reporting for `input` and initializes timing when unset.
*/
void Build.begin_translation(Build state, String input) {
  if (!state.xlat_start) state.xlat_start = report_now_us();
  report_progress(<translate>, state.xlat_done, state.xlat_n, input);
}

/** Records one completed translation and reports the phase when all finish.
    A nonzero `cached` value also increments the cached-translation count.
*/
void Build.end_translation(Build state, String input, int cached) {
  state.xlat_done++;
  if (cached) state.xlat_cached++;
  report_progress(<translate>, state.xlat_done, state.xlat_n, input);
  if (state.xlat_done == state.xlat_n) {
    unsigned long elapsed = report_now_us() - state.xlat_start;
    report_phase(
      <translate>, state.xlat_n,
      state.xlat_n == 1 ? %"x2c file" : %"x2c files",
      state.xlat_cached, elapsed);
  }
}

typedef struct CcJob {
  ToolRun execution;
  ToolAction action;
  String source, object, depfile, state_path, preprocessed;
  uint64_t fingerprint;
} CcJob;

static uint64_t _action_fingerprint(
  Build state, ToolAction action, List inputs, int *ok) {
  String tool = action.arguments ? action.arguments.car().string() : NULL;
  uint64_t hash = _state_base(state.request, tool, ok);
  hash = _state_text(hash, action.phase);
  hash = _state_list(hash, action.arguments);
  foreach (String input, inputs) hash = _state_file(hash, input, ok);
  return hash;
}

/* Returns -1 when preprocessing starts a compile in the same job slot. */
static int _finish_compile(Build state, CcJob *pending) {
  int status = pending->execution.wait();
  if (pending->preprocessed) {
    int ok = !status;
    String preprocessed = pending->preprocessed;
    if (ok)
      pending->fingerprint = _action_fingerprint(
        state, pending->action, %($preprocessed), &ok);
    unlink(pending->preprocessed);
    pending->preprocessed = NULL;
    if (!ok) return 1;
    if (!access(pending->object, R_OK) && !access(pending->depfile, R_OK) &&
        _state_matches(pending->state_path, pending->fingerprint)) {
      if (state.request.verbose)
        fprintf(stderr, "x2c: up-to-date compile %s\n", pending->source);
      state.cc_cached++;
    }
    else {
      pending->execution = pending->action.start();
      return -1;
    }
  }
  else if (!status && state.state_root && !state.request.dry_run)
    _state_write(pending->state_path, pending->fingerprint);
  if (!status) {
    state.cc_done++;
    report_progress(<compile>, state.cc_done, state.cc_n, pending->source);
  }
  return status != 0;
}

static String _compile_command(
  Build state, ToolAction action, String source, String object) {
  Buffer out = Buffer.new(0);
  out.write("  {\"directory\": ");
  report_json_string(out, state.compile_directory);
  out.write(", \"file\": ");
  report_json_string(out, source);
  out.write(", \"output\": ");
  report_json_string(out, object);
  out.write(", \"arguments\": [");
  int first = 1;
  foreach (String argument, action.arguments) {
    if (!first) out.write(", ");
    report_json_string(out, argument);
    first = 0;
  }
  out.write("]}");
  return out.str_free();
}

/** Publishes collected native compilation entries as one JSON database.
    `commands` holds serialized entries from each completed build target.
    The destination's parent must exist. Writes a process-specific sibling
    before rename; handled open, write, close, or rename failure preserves
    the existing database, reports a diagnostic, and returns zero.
*/
int compile_commands_write(String path, Array commands) {
  String temporary = %"$path.tmp.%ld".printf((long) getpid());
  File output = fopen(temporary, "w");
  if (!output) {
    fprintf(
      stderr, "x2c: error: cannot open compilation database: %s\n", path);
    return 0;
  }
  int ok = output.puts("[\n") != EOF, first = 1;
  foreach (String entry, commands) {
    if (!first && output.puts(",\n") == EOF) ok = 0;
    if (output.puts(entry) == EOF) ok = 0;
    first = 0;
  }
  if (output.puts("\n]\n") == EOF) ok = 0;
  if (output.close()) ok = 0;
  if (!ok || rename(temporary, path)) {
    unlink(temporary);
    fprintf(
      stderr, "x2c: error: cannot write compilation database: %s\n", path);
    return 0;
  }
  report_line(<muted>, %"  Compilation database $path");
  return 1;
}

/* Finish ready owned jobs, optionally waiting for at least one. A lone job
   uses the ordinary blocking wait; parallel jobs retain their own statuses
   and captures. The short idle delay bounds polling without a global child
   signal handler or consuming another owner's child status. */
static int _finish_compiles(
  Build state, CcJob *running, int *count, int wait) {
  int failed = 0;
  for (;;) {
    for (int i = 0; i < *count;) {
      if ((wait && *count == 1) || running[i].execution.ready()) {
        int status = _finish_compile(state, running + i);
        if (status < 0) {
          i++;
          continue;
        }
        if (status) failed = 1;
        (*count)--;
        memmove(running + i, running + i + 1, (*count - i) * sizeof(CcJob));
        wait = 0;
      }
      else i++;
    }
    if (!wait) return failed;
    usleep(1000);
  }
}

static int _compile_sources(Build b) {
  if ((void *) b.compile_commands != NULL) {
    char current[PATH_MAX];
    if (!getcwd(current, sizeof(current)))
      x2c_driver_error("cannot read compilation working directory");
    b.compile_directory = String.new(current);
  }
  CcJob *running =
    Scope.calloc(b.request.jobs, sizeof(CcJob));
  int running_count = 0, failed = 0;
  b.cc_n = b.c_sources.length;
  b.cc_start = report_now_us();
  foreach (Var value, b.c_sources) {
    String source = value;
    report_progress(<compile>, b.cc_done, b.cc_n, source);
    String key = _key(source), object = %"${b.obj_root}/$key.o";
    if (b.request.compile_only && !b.request.inputs.cdr() &&
        b.output)
      object = b.output;
    String depfile = %"${b.dep_root}/$key.d", Array include_dirs = %[];
    if (source.startswith(b.gen_root))
      include_dirs.push(Path.dirname(source));
    foreach (Var directory, b.gen_dirs)
      if (!include_dirs.contains(directory)) include_dirs.push(directory);
    List directories = include_dirs.list_free();
    ToolAction action = b.toolchain.compile_action(
      source, object, depfile, directories);
    b.objects.push(object);
    if ((void *) b.compile_commands != NULL)
      b.compile_commands.push(_compile_command(b, action, source, object));
    String state_path =
      b.state_root ?
      %"${b.state_root}/c-${_key(source)}" : NULL;
    if (_finish_compiles(b, running, &running_count, 0)) {
      failed = 1;
      break;
    }
    CcJob pending = {
      .action = action, .source = source, .object = object,
      .depfile = depfile, .state_path = state_path
    };
    if (state_path && !b.request.dry_run) {
      pending.preprocessed = %"${b.dep_root}/$key.i";
      pending.execution = b.toolchain.preprocess_action(
        source, pending.preprocessed, directories).start();
    }
    else pending.execution = action.start();
    running[running_count++] = pending;
    if (running_count >= b.request.jobs &&
        _finish_compiles(b, running, &running_count, 1)) {
      failed = 1;
      break;
    }
  }
  while (running_count)
    if (_finish_compiles(b, running, &running_count, 1)) failed = 1;
  Scope.free(running);
  if (!failed && b.cc_n) {
    unsigned long elapsed = report_now_us() - b.cc_start;
    report_phase(
      <compile>, b.cc_n,
      b.cc_n == 1 ? %"C file" : %"C files",
      b.cc_cached, elapsed);
  }
  return failed;
}

static List _native_action_inputs(Build state) {
  Array inputs = %[];
  foreach (Var value, state.objects) inputs.push(value);
  foreach (Var value, state.native_inputs) inputs.push(value);
  List result = inputs.list_free();
  return result;
}

// Native flags are ordered: an explicit -g0 can override a profile's -g.
static int _mapped_debug(Build state) {
#ifdef __APPLE__
  if (!state.request.source_map || state.request.kind == <static-lib>)
    return 0;
  int enabled = 0;
  foreach (String flag, state.toolchain.cc_args) {
    if (flag == "-g0" || flag == "-ggdb0") enabled = 0;
    else if (flag == "-g" || flag == "-g1" || flag == "-g2" ||
             flag == "-g3" || flag == "-ggdb" || flag == "-ggdb1" ||
             flag == "-ggdb2" || flag == "-ggdb3" ||
             flag == "-gline-tables-only" || flag == "-gmlt" ||
             flag.startswith("-gdwarf")) enabled = 1;
  }
  return enabled;
#else
  return 0;
#endif
}

/* A unit that includes another unit through a directory, as in
   `#include "lib/inner.x"`, names that unit's generated header by the same
   path from its own generated directory. Copying the header to that path
   lets the include resolve as it does beside the sources. */
static void Build._place_unit_headers(Build b) {
  if (b.request.dry_run || b.units.len() < 2) return;
  Map headers = %{};
  foreach (String unit, b.units)
    headers[Path.absolute(unit)] =
      %"${b.gen_root}/${_key(unit)}/${Path.stem(unit)}.h";
  foreach (String unit, b.units) {
    String directory = %"${b.gen_root}/${_key(unit)}";
    String stem = Path.stem(unit);
    List searched = %(${Path.dirname(unit)} @{b.request.include_dirs});
    List outputs = %(${%"$directory/$stem.h"} ${%"$directory/$stem.c"});
    foreach (String generated, outputs)
      foreach (String line, Path.read_text(generated).split_lines(0)) {
        String text = line.strip(" \t");
        if (!text.startswith("#include \"") || !text.endswith(".h\""))
          continue;
        String target = text[10:text.len() - 1];
        if (!target.contains("/")) continue;
        String source = %"${target[:target.len() - 2]}.x";
        foreach (String dir, searched) {
          Var header;
          if (!headers.try_get(Path.join(dir, source).absolute(), &header))
            continue;
          Path placed = Path.join(directory, target);
          placed.dirname().make_dirs();
          Path.copy_file(header.str(), placed);
          break;
        }
      }
  }
}

/** Compiles registered C sources and then archives or links the final output.
    Returns zero for success and one when compilation or the final native
    action fails. Compile-only requests stop after objects. Static archives
    reuse their recorded inputs; executables always link because library
    selection and implicit linker inputs are not in the fingerprint. Mapped
    macOS debug executables also produce a companion dSYM before cleanup;
    failed symbol assembly fails the build and preserves intermediates.
*/
int Build.finish(Build b) {
  b._place_unit_headers();
  if (_compile_sources(b)) return 1;
  if (b.request.compile_only) return 0;
  List inputs = _native_action_inputs(b);
  ToolAction action = NULL;
  if (b.request.kind == <static-lib>)
    action = b.toolchain.archive_action(b.output, inputs);
  else {
    String output = b.output;
    if (b.request.command == <run> && !output)
      output = %"${b.work_dir}/run";
    b.output = output;
    action = b.toolchain.link_action(output, inputs);
  }
  b.final_at = report_now_us();
  report_progress(action.phase, 0, 1, b.output);
  String state_path =
    b.state_root && b.request.kind == <static-lib> ?
    %"${b.state_root}/final-${_key(b.output)}" : NULL;
  if (state_path && !b.request.dry_run &&
      !access(b.output, R_OK)) {
    int ok = 1;
    uint64_t hash = _action_fingerprint(b, action, inputs, &ok);
    if (ok && _state_matches(state_path, hash)) {
      if (b.request.verbose)
        fprintf(
          stderr, "x2c: up-to-date %s %s\n",
          action.phase.str(), b.output);
      b.final_cached = 1;
      report_progress(action.phase, 1, 1, b.output);
      int input_count = inputs.len();
      String noun = input_count == 1 ? %"object" : %"objects";
      report_phase(
        action.phase, input_count, noun, input_count,
        report_now_us() - b.final_at);
      return 0;
    }
  }
  if (b.request.kind == <static-lib> && !b.request.dry_run) unlink(b.output);
  if (action.run()) return 1;
  if (_mapped_debug(b)) {
    String output = b.output, symbols = %"$output.dSYM";
    ToolAction debug = tool_action_new(
      <dsym>, %("dsymutil" $output "-o" $symbols),
      b.request.verbose, b.request.dry_run);
    if (debug.run()) return 1;
  }
  report_progress(action.phase, 1, 1, b.output);
  int input_count = inputs.len();
  String noun = action.phase == <archive> ?
                (input_count == 1 ? %"object" : %"objects") :
                (input_count == 1 ? %"input" : %"inputs");
  report_phase(
    action.phase, input_count, noun, 0,
    report_now_us() - b.final_at);
  if (state_path) {
    int ok = 1;
    uint64_t hash = _action_fingerprint(b, action, inputs, &ok);
    if (ok) _state_write(state_path, hash);
  }
  return 0;
}

static int _all_cached(Build state) {
  if (state.xlat_n &&
      state.xlat_cached != state.xlat_n)
    return 0;
  if (state.cc_n && state.cc_cached != state.cc_n) return 0;
  if (!state.request.compile_only && !state.final_cached) return 0;
  return state.xlat_n || state.cc_n || state.final_cached;
}

/** Prints the completed build receipt and artifact details when enabled. */
void Build.report_success(Build b) {
  if (!report_receipts()) return;
  unsigned long elapsed = report_now_us() - b.started_at;
  String duration = report_duration(elapsed);
  String cache = _all_cached(b) ? %" (up to date)" : %"";
  String label = b.request.label ?
                 %" target '${b.request.label}'" : %"";
  String result;
  if (b.request.compile_only) {
    if (b.objects.length == 1)
      result =
        %"Built$label object ${b.output} in $duration$cache";
    else
      result =
        %"Built$label ${b.objects.length} object files in " +
        %"${b.obj_root} in $duration$cache";
  }
  else {
    String kind = b.request.kind == <static-lib> ?
                  %"static library" : %"executable";
    result = %"Built$label $kind ${b.output} in $duration$cache";
  }
  report_line(<success>, result);
  if (b.xlat_n) {
    String size = report_size(b.gen_bytes);
    String c_noun = b.xlat_n == 1 ? %"C file" : %"C files";
    String h_noun = b.xlat_n == 1 ? %"header" : %"headers";
    report_line(
      <muted>,
      %"  Generated ${b.xlat_n} $c_noun and " +
      %"${b.xlat_n} $h_noun ($size)"
    );
  }
  if (b.cc_n) {
    int count = b.request.jobs;
    String jobs = count == 1 ? %"1 job" : %"$count jobs";
    report_line(
      <muted>,
      %"  Compiled with ${b.toolchain.cc} using $jobs");
  }
  if (!b.request.compile_only) {
    if (b.request.kind == <static-lib>)
      report_line(<muted>, %"  Archived with ${b.toolchain.ar}");
    else report_line(<muted>, %"  Linked with ${b.toolchain.cc}");
  }
  String retention = !b.temporary ? %"retained" :
    b.request.command == <run> ? %"temporary; removed after run" :
                                 %"temporary; removed after build";
  report_line(<muted>, %"  Intermediates ${b.work_dir} ($retention)");
  if (!b.request.compile_only) {
    String size = report_size(report_file_bytes(b.output));
    report_line(<muted>, %"  Output ${b.output} ($size)");
    if (_mapped_debug(b))
      report_line(<muted>, %"  Debug symbols ${b.output}.dSYM");
  }
}

/** Runs the built output with the request's arguments and returns its status.
    A dry run prints the action without launching the program.
*/
int Build.run_program(Build state) {
  report_line(<phase>, %"Running ${state.output}");
  Array arguments = %[];
  arguments.push(state.output);
  foreach (String argument, state.request.run_args) arguments.push(argument);
  ToolAction action = tool_action_new(
    <run>, arguments.list_free(),
    state.request.verbose, state.request.dry_run);
  action.as_program();
  return action.run();
}

/* Removes `path` and everything below it, returning zero when any entry
   could not be removed. An absent path counts as removed. */
int _build_remove_tree(String path) {
  try Path.remove_tree(path);
  catch %(io-fail *): return 0;
  return 1;
}

/* Locks the file `path`, creating it, and returns a descriptor that holds
   the lock until it is closed or the process exits. Returns -1 when `wait`
   is zero and another process holds the lock. */
int _build_lock(String path, int wait) {
  int lock = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
  if (lock < 0) x2c_driver_error(%"cannot lock $path");
  int operation = wait ? LOCK_EX : LOCK_EX | LOCK_NB;
  while (flock(lock, operation)) {
    if (errno == EINTR) continue;
    close(lock);
    return -1;
  }
  return lock;
}

/** Removes the temporary work tree after a successful real build.
    Failed builds, retained directories, and dry runs are left untouched; a
    removal failure emits a warning and is not returned to the caller.
*/
void Build.cleanup(Build state, int success) {
  if (!success || !state.temporary || state.request.dry_run) return;
  if (!_build_remove_tree(state.work_dir)) {
    fputs("x2c: warning: cannot remove temporary build directory: ", stderr);
    fprintf(stderr, "%s\n", state.work_dir);
  }
}

/* A script's executable is reused without translating, preprocessing, or
   linking, so its fingerprint names everything those steps would read: the
   request's options, the environment the C compiler and linker consult, the
   contents of every recorded file, and the modification time of every
   recorded directory. A directory entry ends in `/`; a header or library
   added where a search would now find it changes that time. */
static uint64_t _script_fingerprint(
  CliRequest c, String cc, List prerequisites, int *ok) {
  uint64_t hash = _state_base(c, cc, ok);
  hash = _state_text(hash, %"script");
  hash = _state_list(hash, c.inputs);
  hash = _state_list(hash, c.include_dirs);
  hash = _state_list(hash, c.package_roots());
  hash = _state_list(hash, c.cpp_args);
  hash = _state_list(hash, c.cc_args);
  hash = _state_list(hash, c.ld_args);
  hash = _state_text(
    hash, c.source_map ? %"source-map" : %"generated-lines");
  foreach (String name, %("CPATH" "C_INCLUDE_PATH" "LIBRARY_PATH" "SDKROOT")) {
    const char *value = getenv(name);
    hash = _state_text(hash, value ? String.new(value) : NULL);
  }
  foreach (String path, prerequisites) {
    if (!path.endswith("/")) {
      hash = _state_file(hash, path, ok);
      continue;
    }
    hash = _state_text(hash, path);
    hash = _state_text(hash, Path.is_dir(path)
      ? %"%.9f".printf(Path.modified_time(path)) : %"absent");
  }
  return hash;
}

/* Every directory a compile or link of the script searches: explicit include
   and library options, the compiler's own search lists, and the directory of
   each prerequisite, where quoted includes look first. */
static List Build._script_directories(Build b, List prerequisites) {
  Array directories = %[];
  foreach (Var directory, b.request.include_dirs) directories.push(directory);
  directories.push(b.toolchain.include_dir);
  foreach (List args, %(${b.toolchain.cc_args} ${b.toolchain.ld_args})) {
    for (List p = args; p; p = p.cdr()) {
      String arg = p.car();
      foreach (Var flag, %("-I" "-iquote" "-isystem" "-idirafter" "-L")) {
        String spelling = flag.str();
        if (!arg.startswith(spelling)) continue;
        if (arg.len() > spelling.len()) directories.push(arg[spelling.len():]);
        else if (p.cdr()) directories.push(p.cadr());
        break;
      }
    }
  }
  foreach (String path, prerequisites)
    directories.push(Path.dirname(path));
  foreach (Var directory, b.toolchain.search_directories())
    directories.push(directory);
  Array unique = %[];
  foreach (Var value, directories) {
    String directory = Path.absolute(value.str());
    if (directory.startswith(Path.absolute(b.work_dir))) continue;
    String entry = directory.endswith("/") ? directory : %"$directory/";
    if (!unique.contains(entry)) unique.push(entry);
  }
  return unique.list_free();
}

/** Returns the local `.x` files a script unit includes, which the script's
    program must translate and link. The script's translation depfile already
    lists every file the translation read, so helpers of helpers appear too.
    Runtime and package sources are excluded; their objects are archived.
*/
List Build.script_helpers(Build b) {
  String script = b.request.inputs.car(), root = x2c_get_root();
  String translation =
    %"${b.gen_root}/${_key(script)}/${Path.stem(script)}.d";
  List excluded = %(${%"$root/lib/"} ${%"$root/include/"} ${%"$root/builds/"})
    .append(b.request.package_roots().map(%!(dir) => %"${dir.str()}/"));
  Array helpers = %[];
  foreach (String path, _state_dep_inputs(translation)) {
    if (!path.endswith(".x") || path == script || helpers.contains(path))
      continue;
    if (excluded.any(%!(prefix) => path.startswith(prefix.str()))) continue;
    helpers.push(path);
    b.xlat_n++;
  }
  return helpers.list_free();
}

/** Moves a script's built executable, and its debug symbols on macOS, to
    `executable` and records what it was built from, so
    `CliRequest.script_current` can reuse it. The record lists
    the script's translation and compile prerequisites, package archives, and
    the runtime archive.
    Raises: `<io-fail>` when the executable cannot be moved.
*/
void Build.publish_script(Build b, String executable) {
  Path.move_to(b.output, executable);
  if (_mapped_debug(b)) {
    Path symbols = %"$executable.dSYM";
    symbols.remove_tree();
    Path.move_to(%"${b.output}.dSYM", symbols);
  }
  String input = b.request.inputs.car();
  Array prerequisites = %[];
  String translation =
    %"${b.gen_root}/${_key(input)}/${Path.stem(input)}.d";
  foreach (String path, _state_dep_inputs(translation))
    prerequisites.push(path);
  foreach (String source, b.c_sources)
    foreach (String path,
             _state_dep_inputs(%"${b.dep_root}/${_key(source)}.d"))
      prerequisites.push(path);
  foreach (Var path, b.native_inputs) prerequisites.push(path);
  prerequisites.push(b.toolchain.runtime_lib);
  List files = prerequisites.list_free();
  List paths = files.append(b._script_directories(files));
  int ok = 1;
  uint64_t hash = _script_fingerprint(b.request, b.toolchain.cc, paths, &ok);
  if (ok) _state_write_lines(%"${b.state_root}/script", hash, paths);
}

/** Reports whether the script executable under `directory` still matches
    everything recorded when it was built.
*/
int CliRequest.script_current(CliRequest c, String directory) {
  String record = %"$directory/.x2c-state/script";
  if (access(%"$directory/run", X_OK) || access(record, R_OK)) return 0;
  List lines = NULL;
  try lines = Path.read_text(record).split_lines(0);
  catch %(io-fail *): return 0;
  Toolchain toolchain = toolchain_new(
    c.cc, c.ar, c.cpp_args, c.cc_args, c.ld_args, 0, 0);
  int ok = 1;
  uint64_t hash = _script_fingerprint(c, toolchain.cc, lines.cdr(), &ok);
  return ok && _state_matches(record, hash);
}
