/*  project.x -- x2c project manifests

    Copyright (c) 2026 Gary William Flake.

    A project manifest defines source membership, deterministic glob
    expansion, target relationships, and named profiles. Resolved targets
    lower to the same CliRequest a direct build uses.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "build.x"

/** Links native build requests in dependency-first order.
    `project_plan` returns the head. Each node and copied `CliRequest` struct
    is owned by the current `Scope` and needs no individual cleanup; its
    `String`
    and `List` fields retain their canonical pool lifetimes and may share
    values
    with the command request.
*/
typedef struct ProjectBuild {
  CliRequest request;
  struct ProjectBuild *next;
} *ProjectBuild;

#pragma private

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.x"
#include "install.x"

typedef struct ProjectProfile {
  String name, optimization, int debug, List defines, c_flags, link_flags;
  Map seen, int declared, struct ProjectProfile *next;
} *ProjectProfile;

typedef struct ProjectTarget {
  String name, Symbol kind, String output, List sources, exclude, dependencies;
  List include_dirs, package_dirs, defines, c_flags, library_dirs, libraries;
  List link_flags;
  ProjectProfile profiles;
  Map seen, int declared, visiting, visited, planned;
  struct ProjectTarget *next;
} *ProjectTarget;

typedef struct ProjectDependency {
  String name, version;
  struct ProjectDependency *next;
} *ProjectDependency;

typedef struct Project {
  String path, root, text, default_target, build_dir, build_root, Map seen;
  ProjectDependency dependencies;
  Map dependency_seen;
  int declared;
  SourceView sources;
  ProjectTarget targets;
  ProjectBuild head;
  ProjectBuild tail;
} *Project;

static void _error(Project p, int line, String message) {
  String at = line ? ":%d".printf(line) : NULL;
  if (p && p.path) message = %"manifest '${p.path}'$at: $message";
  fprintf(stderr, "x2c: error: %s\n", message);
  exit(2);
}

static void _error_name(Project p, int line, String message, String name) {
  _error(p, line, %"$message '$name'");
}

static char *_trim(char *text) {
  while (isspace((unsigned char) *text)) text++;
  char *end = text + strlen(text);
  while (end > text && isspace((unsigned char) end[-1])) end--;
  *end = 0;
  return text;
}

static void _strip_comment(char *line) {
  int quoted = 0, escaped = 0;
  for (char *ch = line; *ch; ch++) {
    if (escaped) {
      escaped = 0;
      continue;
    }
    if (quoted && *ch == '\\') {
      escaped = 1;
      continue;
    }
    if (*ch == '"') {
      quoted = !quoted;
      continue;
    }
    if (!quoted && *ch == '#') {
      *ch = 0;
      return;
    }
  }
}

static int _name_ok(String name) {
  if (!name || !name[0]) return 0;
  foreach (char raw, name) {
    unsigned char ch = raw;
    if (!(isalnum(ch) || ch == '_' || ch == '-')) return 0;
  }
  return 1;
}

static String _parse_string(Project project, int line, const char **cursor) {
  const char *ch = *cursor ? *cursor : "";
  while (isspace((unsigned char) *ch)) ch++;
  if (*ch != '"') _error(project, line, "expected a quoted string");
  ch++;
  Buffer output = Buffer.new(0);
  while (*ch && *ch != '"') {
    if (*ch != '\\') {
      output.write_char(*ch++);
      continue;
    }
    ch++;
    if (*ch == '"' || *ch == '\\') output.write_char(*ch++);
    else if (*ch == 'n') {
      output.write_char('\n');
      ch++;
    }
    else if (*ch == 't') {
      output.write_char('\t');
      ch++;
    }
    else _error(project, line, "unsupported string escape");
  }
  if (*ch != '"') _error(project, line, "unterminated quoted string");
  ch++;
  String result = output.str_free();
  *cursor = ch;
  return result;
}

static String _string_value(Project project, int line, String value) {
  const char *cursor = value;
  String result = _parse_string(project, line, &cursor);
  while (isspace((unsigned char) *cursor)) cursor++;
  if (*cursor) _error(project, line, "unexpected text after string");
  return result;
}

static List _string_array(Project project, int line, String value) {
  const char *cursor = value ? value : "";
  while (isspace((unsigned char) *cursor)) cursor++;
  if (*cursor != '[')
    _error(project, line, "expected an array of quoted strings");
  cursor++;
  Array values = [];
  loop {
    while (isspace((unsigned char) *cursor)) cursor++;
    if (*cursor == ']') {
      cursor++;
      break;
    }
    values.push(_parse_string(project, line, &cursor));
    while (isspace((unsigned char) *cursor)) cursor++;
    if (*cursor == ',') {
      cursor++;
      continue;
    }
    if (*cursor != ']')
      _error(project, line, "expected ',' or ']' in array");
  }
  while (isspace((unsigned char) *cursor)) cursor++;
  if (*cursor) _error(project, line, "unexpected text after array");
  return values.list_free();
}

static int _bool_value(Project project, int line, String value) {
  if (value && value == "true") return 1;
  if (value && value == "false") return 0;
  _error(project, line, "expected true or false");
}

static ProjectTarget _target(Project project, String name, int create) {
  for (ProjectTarget target = project.targets; target; target = target.next)
    if (target.name == name) return target;
  if (!create) return NULL;
  ProjectTarget target = Scope.calloc(1, sizeof(struct ProjectTarget));
  target.name = name;
  target.seen = {};
  target.kind = <executable>;
  target.next = project.targets;
  project.targets = target;
  return target;
}

static ProjectProfile _profile(ProjectTarget target, String name, int create) {
  for (ProjectProfile profile = target.profiles; profile;
       profile = profile.next)
    if (profile.name == name) return profile;
  if (!create) return NULL;
  ProjectProfile profile = Scope.calloc(1, sizeof(struct ProjectProfile));
  profile.name = name;
  profile.seen = {};
  profile.next = target.profiles;
  target.profiles = profile;
  return profile;
}

// Each section object records the keys it has taken. A repeated key is an
// error, and `debug = false` stays distinguishable from an absent `debug`.
static void _set_once(Project project, int line, Map seen, String key) {
  if (seen.contains(key))
    _error(project, line, "duplicate manifest field");
  seen[key] = 1;
}

static void _set_project_field(
  Project project, int line, String key, String value) {
  if (key == "name") (void) _string_value(project, line, value);
  else if (key == "default-target")
    project.default_target = _string_value(project, line, value);
  else if (key == "build-dir")
    project.build_dir = _string_value(project, line, value);
  else _error_name(project, line, "unknown project field", key);
}

static void _set_target_field(
  Project p, ProjectTarget target, int line, String key, String value) {
  if (key == "kind") {
    String kind = _string_value(p, line, value);
    if (kind == "executable") target.kind = <executable>;
    else if (kind == "static-library") target.kind = <static-lib>;
    else if (kind == "shared-library")
      _error(p, line, "shared-library is not supported by this compiler");
    else _error_name(p, line, "unknown target kind", kind);
  }
  else if (key == "sources") target.sources = _string_array(p, line, value);
  else if (key == "exclude") target.exclude = _string_array(p, line, value);
  else if (key == "dependencies")
    target.dependencies = _string_array(p, line, value);
  else if (key == "include-dirs")
    target.include_dirs = _string_array(p, line, value);
  else if (key == "package-dirs")
    target.package_dirs = _string_array(p, line, value);
  else if (key == "defines") target.defines = _string_array(p, line, value);
  else if (key == "c-flags") target.c_flags = _string_array(p, line, value);
  else if (key == "library-dirs")
    target.library_dirs = _string_array(p, line, value);
  else if (key == "libraries")
    target.libraries = _string_array(p, line, value);
  else if (key == "link-flags")
    target.link_flags = _string_array(p, line, value);
  else if (key == "output") target.output = _string_value(p, line, value);
  else _error_name(p, line, "unknown target field", key);
}

static void _set_profile_field(
  Project project, ProjectProfile profile, int line, String key,
  String value) {
  if (key == "optimization")
    profile.optimization = _string_value(project, line, value);
  else if (key == "debug") profile.debug = _bool_value(project, line, value);
  else if (key == "defines")
    profile.defines = _string_array(project, line, value);
  else if (key == "c-flags")
    profile.c_flags = _string_array(project, line, value);
  else if (key == "link-flags")
    profile.link_flags = _string_array(project, line, value);
  else _error_name(project, line, "unknown profile field", key);
}

/* One `[dependencies]` entry: an index package name and its exact version. */
static void _set_dependency(Project p, int line, String key, String value) {
  ProjectDependency entry = Scope.calloc(1, sizeof(struct ProjectDependency));
  entry.name = key;
  entry.version = _string_value(p, line, value);
  ProjectDependency *link = &p.dependencies;
  while (*link) link = &(*link).next;
  *link = entry;
}

static void _parse_manifest(Project p) {
  enum { NONE, PROJECT, TARGET, PROFILE, DEPENDENCIES } section = NONE;
  ProjectTarget target = NULL;
  ProjectProfile profile = NULL;
  List lines = p.text.split_lines(0), int line_number = 0;
  foreach (String owned, lines) {
    line_number++;
    int owned_length = owned ? strlen(owned) : 0;
    char *line_storage = Scope.malloc(owned_length + 1);
    if (owned_length) memcpy(line_storage, owned, owned_length);
    line_storage[owned_length] = 0;
    char *line = line_storage;
    _strip_comment(line);
    line = _trim(line);
    if (!*line) continue;
    if (*line == '[') {
      int length = strlen(line);
      if (length < 3 || line[length - 1] != ']')
        _error(p, line_number, "malformed section header");
      line[length - 1] = 0;
      String name = String.new(line + 1);
      if (name == "project") {
        if (p.declared)
          _error(p, line_number, "duplicate project section");
        p.declared = 1;
        section = PROJECT;
        target = NULL;
        profile = NULL;
        continue;
      }
      if (name == "dependencies") {
        if (p.dependency_seen)
          _error(p, line_number, "duplicate dependencies section");
        p.dependency_seen = {};
        section = DEPENDENCIES;
        target = NULL;
        profile = NULL;
        continue;
      }
      // `[target.<name>]` or `[target.<name>.profile.<profile>]`
      String second = name.remove_prefix("target."), fourth = NULL;
      int split = second.find(".profile.");
      if (split >= 0) {
        fourth = second[split + 9:];
        second = second[:split];
      }
      if (!name.startswith("target.") || !_name_ok(second) ||
          (split >= 0 && !_name_ok(fourth)))
        _error(p, line_number, "unknown manifest section");
      target = _target(p, second, 1);
      if (split < 0) {
        if (target.declared)
          _error_name(p, line_number, "duplicate target section", second);
        target.declared = 1;
        section = TARGET;
        profile = NULL;
      }
      else {
        section = PROFILE;
        profile = _profile(target, fourth, 1);
        if (profile.declared)
          _error_name(p, line_number, "duplicate profile section", fourth);
        profile.declared = 1;
      }
      continue;
    }
    if (section == NONE)
      _error(p, line_number, "field appears before a section");
    char *equals = strchr(line, '=');
    if (!equals) _error(p, line_number, "expected key = value");
    *equals = 0;
    String key = String.new(_trim(line));
    String value = String.new(_trim(equals + 1));
    if (!_name_ok(key)) _error(p, line_number, "invalid field name");
    _set_once(
      p, line_number,
      section == PROJECT ? p.seen :
      section == DEPENDENCIES ? p.dependency_seen :
      section == TARGET ? target.seen : profile.seen,
      key
    );
    if (section == PROJECT) _set_project_field(p, line_number, key, value);
    else if (section == DEPENDENCIES)
      _set_dependency(p, line_number, key, value);
    else if (section == TARGET)
      _set_target_field(p, target, line_number, key, value);
    else _set_profile_field(p, profile, line_number, key, value);
  }
  if (!p.targets) _error(p, 0, "manifest defines no targets");
}

static int _has_glob(String pattern) => pattern && strpbrk(pattern, "*?[");

/* A pattern matches the files, or the links to files, that its glob names
   below the project root, outside the build root, and the overlay files
   there too. A pattern without a wildcard names one file. */
static Array _expand_pattern(Project p, String pattern, String owner) {
  Array matches = [];
  if (!_has_glob(pattern)) {
    String path = Path.join(p.root, pattern);
    if (p.sources.exists(path)) matches.push(path);
  }
  else {
    String root = p.root.replace("\\", "\\\\").replace("*", "\\*")
      .replace("?", "\\?").replace("[", "\\[");
    String prefix = p.root == "/" ? "/" : %"${p.root}/";
    List found = Path.glob(Path.join(root, pattern));
    if (p.sources) found = found.append(p.sources.overlays.keys());
    foreach (String path, found)
      if (path.startswith(prefix) &&
          Path.glob_match(pattern, path.remove_prefix(prefix)) &&
          !(p.build_root && path.startswith(%"${p.build_root}/")) &&
          p.sources.exists(path) && !matches.contains(path))
        matches.push(path);
  }
  if (!matches.len())
    _error_name(p, 0, %"unmatched $owner pattern", pattern);
  return matches.sort();
}

static Array _target_sources(
  Project project, ProjectTarget target, int verbose) {
  if (!target.sources)
    _error_name(project, 0, "target has no sources", target.name);
  Array sources = [];
  foreach (String pattern, target.sources) {
    Array expanded = _expand_pattern(project, pattern, "source");
    foreach (Var value, expanded)
      if (!sources.contains(value)) sources.push(value);
    expanded.free();
  }
  Array excluded = [];
  foreach (String pattern, target.exclude) {
    Array expanded = _expand_pattern(project, pattern, "exclude");
    foreach (Var value, expanded)
      if (!excluded.contains(value)) excluded.push(value);
    expanded.free();
  }
  Array kept = [];
  foreach (Var value, sources) {
    if (excluded.contains(value)) {
      if (verbose)
        fprintf(
          stderr, "x2c: excluded %s from target %s\n",
          value.string(), target.name);
    }
    else kept.push(value);
  }
  sources.free();
  excluded.free();
  kept.sort();
  foreach (String path, kept) {
    if (!(x2c_source_file(path) || path.endswith(".c")))
      _error_name(project, 0, "manifest source is not .x or .c", path);
  }
  return kept;
}

static ProjectProfile _selected_profile(
  Project project, ProjectTarget target, String name) {
  if (!name) return NULL;
  ProjectProfile profile = _profile(target, name, 0);
  if (!profile) _error_name(project, 0, "target has no profile", name);
  return profile;
}

static void _validate_target(Project project, ProjectTarget target) {
  if (target.visited) return;
  if (target.visiting)
    _error_name(project, 0, "target dependency cycle reaches", target.name);
  target.visiting = 1;
  foreach (String name, target.dependencies) {
    ProjectTarget dependency = _target(project, name, 0);
    if (!dependency)
      _error_name(project, 0, "unknown target dependency", name);
    _validate_target(project, dependency);
  }
  target.visiting = 0;
  target.visited = 1;
}

static List _c_flags(Project p, List values) {
  foreach (String value, values)
    if (cli_dependency_pass_through(value))
      _error_name(p, 0, "C dependency option is driver-owned", value);
  return values;
}

static List _defines(List values) => values.map(%!(value) => %"-D$value");

static List _paths(String root, List values) =>
  values.map(%!(String value) => Path.join(root, value));

static List _path_options(String root, List values, String option) =>
  _paths(root, values).map(%!(path) => %($option $path)).flatten();

static String _target_output(
  Project project, ProjectTarget target, String build_root, Symbol kind) {
  if (target.output) return Path.join(project.root, target.output);
  if (kind == <static-lib>) return %"$build_root/lib${target.name}.a";
  return %"$build_root/${target.name}";
}

/* Each planned target receives a Scope-owned copy of the command request.
   Target-specific Lists are rebuilt, dependencies become archive inputs, and
   the per-target `.x2c` directory keeps artifacts and state separate. The
   state seed identifies the manifest, target, and profile. Effective settings
   enter fingerprints through the lowered request and action arguments. */
static CliRequest _target_request(
  Project p, ProjectTarget target, CliRequest command,
  ProjectTarget selected, String build_root) {
  CliRequest request = Scope.malloc(sizeof(struct CliRequest));
  *request = *command;
  int chosen = target == selected;
  request.command = chosen ? command.command : <build>;
  request.run_args = chosen ? command.run_args : NULL;
  request.compile_only = 0;
  request.kind = chosen && command.kind_explicit ? command.kind : target.kind;
  request.output = chosen && command.output ?
    command.output : _target_output(p, target, build_root, request.kind);
  request.build_dir = %"$build_root/.x2c/${target.name}";
  request.save_temps = 0;
  request.temps_dir = NULL;
  if (request.kind == <static-lib> && target.dependencies)
    _error_name(
      p, 0,
      "static-library target cannot contain target dependencies",
      target.name);

  Array inputs = _target_sources(p, target, command.verbose);
  foreach (String name, target.dependencies) {
    ProjectTarget dependency = _target(p, name, 0);
    if (dependency.kind != <static-lib>)
      _error_name(
        p, 0, "dependency target is not a static library",
        dependency.name);
    inputs.push(_target_output(p, dependency, build_root, dependency.kind));
  }
  request.inputs = inputs.list_free();
  request.include_dirs =
    %(@{command.include_dirs} @{_paths(p.root, target.include_dirs)});
  request.package_dirs =
    %(@{command.package_dirs} @{_paths(p.root, target.package_dirs)});

  ProjectProfile profile =
    chosen ? _selected_profile(p, target, command.profile) : NULL;
  List defines = _defines(target.defines), compile = NULL, link = NULL;
  if (profile) {
    List cc_args = command.cc_args;
    int optimized = cc_args.any(%!(String flag) => flag.startswith("-O"));
    int debug = profile.seen.contains("debug") && profile.debug &&
                !cc_args.contains("-g");
    defines = defines.append(_defines(profile.defines));
    compile = %(
      @{_c_flags(p, profile.c_flags)}
      @{profile.optimization && !optimized ?
        %("-${profile.optimization}") : NULL}
      @{debug ? %("-g") : NULL});
    link = profile.link_flags;
  }
  request.cpp_args = %(@defines @{command.cpp_args});
  request.cc_args = %(
    @{_defines(target.defines)} @{_c_flags(p, target.c_flags)}
    @{profile ? _defines(profile.defines) : NULL} @compile @{command.cc_args}
    @{_path_options(p.root, target.include_dirs, "-I")});
  request.ld_args = %(
    @{_path_options(p.root, target.library_dirs, "-L")}
    @{target.libraries.map(%!(library) => %"-l$library")}
    @{target.link_flags} @link @{command.ld_args});

  request.label = target.name;
  request.state_seed =
    %"${p.path}\n" +
    %"target=${target.name}\nprofile=${command.profile}";
  return request;
}

static void _append_plan(Project project, CliRequest request) {
  ProjectBuild node = Scope.calloc(1, sizeof(struct ProjectBuild));
  node.request = request;
  if (project.tail) project.tail.next = node;
  else project.head = node;
  project.tail = node;
}

static void _plan_target(
  Project project, ProjectTarget target, CliRequest command,
  ProjectTarget selected, String build_root) {
  if (target.planned) return;
  foreach (String dependency, target.dependencies)
    _plan_target(
      project, _target(project, dependency, 0),
      command, selected, build_root);
  _append_plan(
    project,
    _target_request(project, target, command, selected, build_root));
  target.planned = 1;
}

// dependencies

/* The lockfile's rows, or NULL when it is absent. */
static List _read_lock(String path) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %(not-found *): return NULL;
  return install_rows(text);
}

/* Every dependency is locked at its pinned version and already installed at
   that version, so the build needs no index and no network. */
static int _lock_satisfies(Project project, List rows) {
  if (!rows) return 0;
  for (ProjectDependency entry = project.dependencies; entry;
       entry = entry.next) {
    List found = NULL;
    foreach (List row, rows)
      if (row.car() == entry.name) found = row;
    if (!found || found.cdr().car() != entry.version) return 0;
    if (install_version(entry.name) != entry.version) return 0;
  }
  return 1;
}

static void _write_lock(String path, List rows) {
  String text =
    "# x2c lockfile. Written by x2c build; keep it with the manifest.\n"
    "# name version kind platform url sha256\n";
  foreach (List row, rows) text = %"$text${" ".join(row)}\n";
  try file_publish(path, text);
  catch %(io-fail *detail): x2c_host_error(detail);
}

/* Installs whatever the manifest pins that the home does not already hold,
   then records what was resolved beside the manifest. The editor reads a
   source view and never installs. */
static void _resolve_dependencies(Project project, CliRequest request) {
  if (!project.dependencies || project.sources) return;
  String path = %"${project.root}/x2c.lock";
  List locked = _read_lock(path);
  if (_lock_satisfies(project, locked)) return;
  Array rows = [];
  for (ProjectDependency entry = project.dependencies; entry;
       entry = entry.next)
    rows.push(install_require(request, entry.name, entry.version));
  _write_lock(path, rows.list_free());
}

/** Returns the explicit or nearest readable project manifest, or NULL.
    Discovery uses the same request view as project parsing.
*/
String project_manifest(CliRequest c) {
  if (c.manifest) return c.manifest;
  for (Path directory = Path.absolute(".");; directory = directory.dirname()) {
    String candidate = directory.join("x2c.toml");
    if (c.sources.exists(candidate)) return candidate;
    if (directory == "/") return NULL;
  }
}

/** Parses a project manifest and returns its selected target's build plan.
    `request` must be a build or run request with no explicit operands. The
    result contains each dependency once before its consumer and lowers
    manifest fields and command-line overrides to ordinary `CliRequest` values
    without executing build actions. Manifest discovery, parsing, validation,
    or target-selection failures print a diagnostic and exit with status 2.
*/
ProjectBuild project_plan(CliRequest request) {
  Project project = Scope.calloc(1, sizeof(struct Project));
  project.seen = {};
  project.sources = request.sources;
  project.path = project_manifest(request);
  if (!project.path)
    _error(NULL, 0, "no explicit inputs and no x2c.toml found");
  project.path = Path.absolute(project.path);
  if (!project.sources.read(project.path, &project.text))
    _error(project, 0, "cannot read manifest");
  project.root = Path.dirname(project.path);
  _parse_manifest(project);
  for (ProjectTarget target = project.targets; target; target = target.next)
    _validate_target(project, target);
  _resolve_dependencies(project, request);

  String selected_name = request.target ? request.target :
                         project.default_target;
  if (!selected_name) {
    if (project.targets && !project.targets.next)
      selected_name = project.targets.name;
    else
      _error(project, 0, "select --target or set project.default-target");
  }
  ProjectTarget selected = _target(project, selected_name, 0);
  if (!selected)
    _error_name(project, 0, "unknown target", selected_name);
  Symbol selected_kind = request.kind_explicit ? request.kind : selected.kind;
  if (request.command == <run> && selected_kind != <executable>)
    _error(project, 0, "run requires an executable target");

  String build_root = request.build_dir;
  if (build_root) build_root = Path.absolute(".").join(build_root);
  else
    build_root = project.build_dir ?
                 Path.join(project.root, project.build_dir) :
                 %"${project.root}/.x2c-build";
  project.build_root = build_root;
  _plan_target(project, selected, request, selected, build_root);
  return project.head;
}

/** Creates the starter project for `x2c new` in the directory named by
    `request`'s one operand and returns 0. The directory may be missing or
    empty, and its last component names the target. Any other directory, an
    unusable name, or a failed write prints a diagnostic and exits with
    status 2.
*/
int new_command(CliRequest request) {
  Path dir = request.inputs.car();
  String name = Path.absolute(dir).basename();
  if (!_name_ok(name))
    x2c_driver_error(
      %"new: '$name' is not a target name; use letters, digits, '_', and '-'");
  try {
    if (dir.exists() && (!dir.is_dir() || dir.list_dir()))
      x2c_driver_error(%"new: $dir exists and is not an empty directory");
    dir.join("src").make_dirs();
    dir.join("x2c.toml").write_text(
      %"[target.$name]
sources = [\"src/*.x\"]
");
    // Symbol collection reads a line-leading `#include` inside a percent
    // string as a directive, so that line is inserted as a C string.
    dir.join("src/main.x").write_text(
      %"/*  main.x -- greet the name given on the command line */

${"#include <stdio.h>"}

int main(int argc, char **argv) {
  String name = argc > 1 ? argv[1] : \"world\";
  puts(%\"Hello, \$name!\");
  return 0;
}
");
    dir.join(".gitignore").write_text(".x2c-build/\n");
  }
  catch %(io-fail *detail): x2c_host_error(detail);
  if (!request.quiet) printf("x2c: created %s\n", dir);
  return 0;
}
