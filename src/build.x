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
  int temporary, Array c_sources, gen_dirs, native_inputs, objects;
  String compile_directory, Array compile_commands;
  unsigned long started_at;
  unsigned long xlat_start;
  unsigned long cc_start;
  unsigned long final_at;
  unsigned long long gen_bytes;
  int xlat_n, xlat_done, xlat_cached, cc_n, cc_done, cc_cached, final_cached;
} *Build;

#pragma private

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "report.x"

/* Artifact directories and object, dependency, and state paths all use this
   spelling-derived key. The input path is not canonicalized, so its spelling
   is part of incremental cache identity. */
static String _key(String path) {
  String stem = x2c_path_stem(path);
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

static uint64_t _state_base(Build state, String tool, int *ok) {
  uint64_t hash = UINT64_C(1469598103934665603);
  hash = _state_text(hash, %"x2c-state-v1");
  hash = _state_text(hash, state.request.state_seed);
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

static void _state_write(String path, uint64_t hash) {
  String temporary = %"$path.tmp.%ld".printf((long) getpid());
  File output = fopen(temporary, "w");
  if (!output) return;
  int ok = output.printf(
    "x2c-state-v1 %016llx\n", (unsigned long long) hash) >= 0;
  if (output.close()) ok = 0;
  if (!ok || rename(temporary, path)) unlink(temporary);
}

/* Creates `path` and missing parents. Returns nonzero when every `mkdir`
   succeeds or reports `EEXIST`; it does not verify that an existing final
   entry is a directory. */
int _build_mkdirs(String path) {
  if (!path || !path[0]) return 0;
  char buffer[PATH_MAX];
  if (strlen(path) >= sizeof(buffer)) return 0;
  strcpy(buffer, path);
  for (char *ch = buffer + 1; *ch; ch++) {
    if (*ch != '/') continue;
    *ch = 0;
    if (mkdir(buffer, 0777) && errno != EEXIST) return 0;
    *ch = '/';
  }
  return mkdir(buffer, 0777) == 0 || errno == EEXIST;
}

static void _require_directory(String path) {
  if (!_build_mkdirs(path))
    x2c_driver_error(%"cannot create build directory: $path");
  struct stat info;
  if (stat(path, &info) || !S_ISDIR(info.st_mode))
    x2c_driver_error(%"build path is not a directory: $path");
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
    directories. Invalid inputs or setup print a diagnostic and exit with
    status 2.
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
    c.cc, c.ar, c.cpp_args, c.cc_args, c.ld_args, c.verbose);
  c.cc = state.toolchain.cc; c.ar = state.toolchain.ar;
  state.c_sources = %[];
  state.gen_dirs = %[];
  state.native_inputs = %[];
  state.objects = %[];
  if (c.compile_commands) state.compile_commands = %[];
  if (c.output) state.output = c.output;
  else if (c.command == <run>) state.output = NULL;
  else if (c.compile_only && c.inputs && !c.inputs.cdr())
    state.output = %"${x2c_path_stem(c.inputs.car().string())}.o";
  else if (c.kind == <static-lib>) {
    String stem = c.inputs ?
                  x2c_path_stem(c.inputs.car()) : %"target";
    state.output = %"lib$stem.a";
  }
  else state.output = "a.out";
  state.started_at = report_now_us();
  if (c.build_dir) state.work_dir = c.build_dir;
  else if (c.temps_dir) state.work_dir = c.temps_dir;
  else if (c.save_temps) state.work_dir = ".x2c-build";
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
  _require_directory(state.work_dir);
  _require_directory(state.gen_root);
  _require_directory(state.obj_root);
  _require_directory(state.dep_root);
  if (state.state_root) _require_directory(state.state_root);
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

/** Returns and registers the generated-file directory for `input`.
    The directory is derived from the input path, created, and appended once
    to the build's generated include directories.
*/
String Build.generated_dir(Build state, String input) {
  String directory = %"${state.gen_root}/${_key(input)}";
  _require_directory(directory);
  if (!state.gen_dirs.contains(directory)) state.gen_dirs.push(directory);
  return directory;
}

static uint64_t _translation_fingerprint(
  Build state, String input, String directory, int *ok) {
  uint64_t hash = _state_base(state, state.toolchain.cc, ok);
  hash = _state_text(hash, %"translate");
  hash = _state_text(hash, input);
  CliRequest request = state.request;
  hash = _state_list(hash, request.include_dirs);
  hash = _state_list(hash, request.package_dirs);
  hash = _state_list(hash, request.cpp_args);
  hash = _state_text(hash, request.no_cpp ? %"no-cpp" : %"cpp");
  hash = _state_text(hash, %"generated-lines");
  String depfile = %"$directory/${x2c_path_stem(input)}.d";
  return _state_dependencies(hash, depfile, ok);
}

/** Reports whether translated C and header artifacts match current inputs.
    Returns zero without retained state, when either output is absent, or
    when any compiler, tool, option, depfile, or dependency fingerprint cannot
    be read or differs.
*/
int Build.translation_current(Build state, String input, String directory) {
  if (!state.state_root) return 0;
  String stem = x2c_path_stem(input);
  if (access(%"$directory/$stem.c", R_OK)) return 0;
  if (access(%"$directory/$stem.h", R_OK)) return 0;
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
  if (!state.state_root) return;
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
  List roots = state.request.package_dirs;
  if (!roots) return;
  String own = _package_source_directory(roots, input);
  String depfile = %"$directory/${x2c_path_stem(input)}.d";
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
  String stem = x2c_path_stem(input), source = %"$directory/$stem.c";
  String header = %"$directory/$stem.h";
  state.gen_bytes += report_file_bytes(source);
  state.gen_bytes += report_file_bytes(header);
  state.c_sources.push(source);
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
  uint64_t hash = _state_base(state, tool, ok);
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
  else if (!status && state.state_root)
    _state_write(pending->state_path, pending->fingerprint);
  if (!status) {
    state.cc_done++;
    report_progress(<compile>, state.cc_done, state.cc_n, pending->source);
  }
  return status != 0;
}

static void _json_string(Buffer out, String text) {
  out.write_char('"');
  for (const unsigned char *p = (const unsigned char *) text; p && *p; p++) {
    if (*p == '"' || *p == '\\') out.write_char('\\');
    if (*p < 32) out.printf("\\u%04x", *p);
    else out.write_char(*p);
  }
  out.write_char('"');
}

static String _compile_command(
  Build state, ToolAction action, String source, String object) {
  Buffer out = Buffer.new(0);
  out.write("  {\"directory\": ");
  _json_string(out, state.compile_directory);
  out.write(", \"file\": ");
  _json_string(out, source);
  out.write(", \"output\": ");
  _json_string(out, object);
  out.write(", \"arguments\": [");
  int first = 1;
  foreach (String argument, action.arguments) {
    if (!first) out.write(", ");
    _json_string(out, argument);
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
      include_dirs.push(x2c_path_dir(source));
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
    if (state_path) {
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

/** Compiles registered C sources and then archives or links the final output.
    Returns zero for success and one when compilation or the final native
    action fails. Compile-only requests stop after objects. Static archives
    reuse their recorded inputs; executables always link because library
    selection and implicit linker inputs are not in the fingerprint.
*/
int Build.finish(Build b) {
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
  if (state_path &&
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
  if (b.request.kind == <static-lib>) unlink(b.output);
  if (action.run()) return 1;
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
  }
}

/** Runs the built output with the request's arguments and returns its status.
*/
int Build.run_program(Build state) {
  report_line(<phase>, %"Running ${state.output}");
  Array arguments = %[];
  arguments.push(state.output);
  foreach (String argument, state.request.run_args) arguments.push(argument);
  ToolAction action = tool_action_new(
    <run>, arguments.list_free(), state.request.verbose);
  action.as_program();
  return action.run();
}

/* Recursively removes `path`, continuing through sibling entries after a
   failure. Returns nonzero when the path was absent or every entry and the
   root were removed. */
int _build_remove_tree(String path) {
  DIR *directory = opendir(path);
  if (!directory) return unlink(path) == 0 || errno == ENOENT;
  struct dirent *entry, int ok = 1;
  while ((entry = readdir(directory))) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
      continue;
    Context context = $auto(Context.open_isolated());
    String child = %"$path/${String.new(entry->d_name)}", struct stat info;
    if (lstat(child, &info)) {
      ok = 0;
      continue;
    }
    if (S_ISDIR(info.st_mode)) {
      if (!_build_remove_tree(child)) ok = 0;
    }
    else if (unlink(child)) ok = 0;
  }
  closedir(directory);
  if (rmdir(path)) ok = 0;
  return ok;
}

/** Removes the temporary work tree after a successful real build.
    Failed builds and retained directories are left untouched; a removal
    failure emits a warning and is not returned to the caller.
*/
void Build.cleanup(Build state, int success) {
  if (!success || !state.temporary) return;
  if (!_build_remove_tree(state.work_dir)) {
    fputs("x2c: warning: cannot remove temporary build directory: ", stderr);
    fprintf(stderr, "%s\n", state.work_dir);
  }
}
