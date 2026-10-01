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
    `String` and `List` fields retain their canonical pool lifetimes and may
    share values with the command request.
*/
typedef struct ProjectBuild {
  CliRequest request;
  struct ProjectBuild *next;
} *ProjectBuild;

#pragma private
$(import "../src/project-errors.xmacro")

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.x"
#include "install.x"

// the manifest model

/* A target or profile exists from its first mention. `declared` records
   that its own section appeared, and `seen` holds the keys that section
   set. */
typedef struct ProjectProfile {
  String name, optimization, int debug, List defines, c_flags, link_flags;
  Map seen, int declared, struct ProjectProfile *next;
} *ProjectProfile;

typedef struct ProjectTarget {
  String name, Symbol kind, String output, List sources, exclude, dependencies;
  List native_modules, include_dirs, package_dirs, defines, c_flags;
  List library_dirs, libraries, link_flags;
  ProjectProfile profiles;
  Map seen, int declared, visiting, visited, planned;
  struct ProjectTarget *next;
} *ProjectTarget;

typedef struct ProjectDependency {
  String name, version;
  struct ProjectDependency *next;
} *ProjectDependency;

/* A project holds its manifest's settings, the command request it serves,
   and, while it plans, the selected target and the build list. */
typedef struct Project {
  String path, root, text, default_target, build_dir, build_root, Map seen;
  ProjectDependency dependencies;
  Map dependency_seen;
  int declared, dependency_declared;
  SourceView sources;
  ProjectTarget targets;
  CliRequest command, ProjectTarget selected;
  ProjectBuild head;
  ProjectBuild tail;
} *Project;

// planning

/** Parses a project manifest and returns its selected target's build plan.
    `request` must be a build or run request with no explicit operands. The
    result contains each dependency once before its consumer and lowers
    manifest fields and command-line overrides to ordinary `CliRequest` values
    without executing build actions. Manifest discovery, parsing, validation,
    or target-selection failures print a diagnostic and exit with status 2.
*/
ProjectBuild project_plan(CliRequest request) {
  Project p = _open_project(request);
  _parse_manifest(p);
  for (ProjectTarget target = p.targets; target; target = target.next)
    _validate_target(p, target);
  p.selected = _selected_target(p);
  // Nothing outside the manifest changes until the request is known good.
  _resolve_dependencies(p);
  p.build_root = _build_root(p);
  _plan_target(p, p.selected);
  return p.head;
}

/* A project whose manifest text is read and not yet parsed. */
static Project _open_project(CliRequest request) {
  Project p = Scope.calloc(1, sizeof(struct Project));
  *p = (struct Project) {
    .seen = {}, .sources = request.sources, .command = request,
    .path = project_manifest(request)};
  if (!p.path) $project.error("manifest.missing");
  p.path = Path.absolute(p.path);
  if (!p.sources.read(p.path, p.text)) $project.error("manifest.read", p);
  p.root = Path.dirname(p.path);
  return p;
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

/* The target the command names, else the manifest's default, else the
   manifest's only target. The command must be able to build it as asked. */
static ProjectTarget _selected_target(Project p) {
  CliRequest request = p.command;
  String name = request.target ? request.target : p.default_target;
  if (!name && p.targets.next)
    $project.error("target.select", p);
  if (!name) name = p.targets.name;
  ProjectTarget selected = _target(p, name);
  if (!selected) $project.error("target.unknown", p, name);
  Symbol kind = request.kind_explicit ? request.kind : selected.kind;
  if (request.command == <run> && kind != <executable>)
    $project.error("target.run", p);
  (void) _selected_profile(p, selected, request.profile);
  return selected;
}

/* The command's build directory, relative to the working directory, else
   the manifest's, relative to the project root. */
static String _build_root(Project p) {
  String dir = p.command.build_dir;
  if (dir) return Path.absolute(".").join(dir);
  if (p.build_dir) return Path.join(p.root, p.build_dir);
  return %"${p.root}/.x2c-build";
}

// manifest lines

typedef enum ManifestSection {
  NONE, PROJECT, TARGET, PROFILE, DEPENDENCIES
} ManifestSection;

/* The parser's place in a manifest: the line it reads and the section that
   line belongs to, with the section's target or profile. A field whose
   array spans lines keeps its key, its value so far, and the line it starts
   on until a bracket closes the array. */
typedef struct Manifest {
  Project project, int line, ManifestSection section;
  ProjectTarget target, ProjectProfile profile;
  String key, value, int start;
} Manifest;

/* Each line is a section header, a `key = value` field, or the next line of
   a field whose array is open. A `#` outside a string starts a comment. */
static void _parse_manifest(Project p) {
  Manifest m = {.project = p};
  foreach (String text, p.text.split_lines(0)) {
    m.line++;
    char *line = _content(text);
    if (!*line) continue;
    if (m.key) m.extend(line);
    else if (*line == '[') m.header(line);
    else m.field(line);
  }
  if (m.key) $project.error("array.open", p, m.start);
  if (!p.targets) $project.error("target.none", p);
}

/* A copy of the line that the parser may write into, without its comment
   and surrounding space. */
static char *_content(String text) {
  int length = text ? strlen(text) : 0;
  char *line = Scope.malloc(length + 1);
  if (length) memcpy(line, text, length);
  line[length] = 0;
  _strip_comment(line);
  return _trim(line);
}

static void _strip_comment(char *line) {
  int quoted = 0;
  for (char *at = line; *at; at++) {
    if (quoted && *at == '\\' && at[1]) at++;
    else if (*at == '"') quoted = !quoted;
    else if (!quoted && *at == '#') {
      *at = 0;
      return;
    }
  }
}

static char *_trim(char *text) {
  text = _skip_space(text);
  char *end = text + strlen(text);
  while (end > text && isspace((unsigned char) end[-1])) end--;
  *end = 0;
  return text;
}

// sections

/* A header opens `[project]`, `[dependencies]`, `[target.<name>]`, or
   `[target.<name>.profile.<name>]`, and each section appears once. */
static void Manifest.header(Manifest &m, char *line) {
  int length = strlen(line);
  if (length < 3 || line[length - 1] != ']')
    $project.error("section.header", m.project, m.line);
  line[length - 1] = 0;
  String name = String.new(line + 1);
  if (name == "project") m.enter_project();
  else if (name == "dependencies") m.enter_dependencies();
  else m.target_header(name);
}

static void Manifest.enter_project(Manifest &m) {
  Project p = m.project;
  if (p.declared) $project.error("section.project", p, m.line);
  p.declared = 1;
  m.section = PROJECT;
}

static void Manifest.enter_dependencies(Manifest &m) {
  Project p = m.project;
  if (p.dependency_declared)
    $project.error("section.deps", p, m.line);
  p.dependency_declared = 1;
  p.dependency_seen = {};
  m.section = DEPENDENCIES;
}

/* A profile header mentions its target too, so the target exists even
   before its own section. */
static void Manifest.target_header(Manifest &m, String header) {
  Project p = m.project;
  String name = header.remove_prefix("target."), profile = NULL;
  int split = name.find(".profile.");
  if (split >= 0) {
    profile = name[split + 9:];
    name = name[:split];
  }
  if (!header.startswith("target.") || !_name_ok(name) ||
      (split >= 0 && !_name_ok(profile)))
    $project.error("section.unknown", p, m.line);
  ProjectTarget target = _target(p, name);
  if (!target) target = _new_target(p, name);
  if (split < 0) m.enter_target(target);
  else m.enter_profile(target, profile);
}

static void Manifest.enter_target(Manifest &m, ProjectTarget target) {
  if (target.declared)
    $project.error("section.target", m.project, m.line, target.name);
  target.declared = 1;
  m.section = TARGET;
  m.target = target;
}

static void Manifest.enter_profile(
  Manifest &m, ProjectTarget target, String name) {
  ProjectProfile profile = _profile(target, name);
  if (!profile) profile = _new_profile(target, name);
  if (profile.declared)
    $project.error("section.profile", m.project, m.line, name);
  profile.declared = 1;
  m.section = PROFILE;
  m.profile = profile;
}

// fields

/* A `key = value` field of the current section. */
static void Manifest.field(Manifest &m, char *line) {
  Project p = m.project;
  if (m.section == NONE) $project.error("field.section", p, m.line);
  char *equals = strchr(line, '=');
  if (!equals) $project.error("field.equals", p, m.line);
  *equals = 0;
  String key = String.new(_trim(line)), value = String.new(_trim(equals + 1));
  if (!_name_ok(key)) $project.error("field.name", p, m.line);
  m.claim(key);
  m.key = key;
  m.value = value;
  m.start = m.line;
  m.settle();
}

/* The next line of an open array continues its field's value. */
static void Manifest.extend(Manifest &m, char *line) {
  m.value = %"${m.value} ${String.new(line)}";
  m.settle();
}

/* Each section takes a key once. */
static void Manifest.claim(Manifest &m, String key) {
  Map keys = m.keys();
  if (key in keys) $project.error("field.duplicate", m.project, m.line);
  keys[key] = 1;
}

static Map Manifest.keys(Manifest &m) {
  if (m.section == PROJECT) return m.project.seen;
  if (m.section == DEPENDENCIES) return m.project.dependency_seen;
  return m.section == TARGET ? m.target.seen : m.profile.seen;
}

/* A field whose value leaves an array open waits for the line that closes
   it; any other field is set now. */
static void Manifest.settle(Manifest &m) {
  if (_array_open(m.value)) return;
  m.set();
  m.key = NULL;
}

static void Manifest.set(Manifest &m) {
  Project p = m.project;
  int line = m.start;
  String key = m.key, value = m.value;
  if (m.section == PROJECT) _set_project_field(p, line, key, value);
  else if (m.section == DEPENDENCIES) _set_dependency(p, line, key, value);
  else if (m.section == TARGET)
    _set_target_field(p, m.target, line, key, value);
  else _set_profile_field(p, m.profile, line, key, value);
}

static void _set_project_field(Project p, int line, String key, String value) {
  if (key == "name") (void) _string_value(p, line, value);
  else if (key == "default-target")
    p.default_target = _string_value(p, line, value);
  else if (key == "build-dir") p.build_dir = _string_value(p, line, value);
  else $project.error("field.project", p, line, key);
}

/* One `[dependencies]` entry: an index package name and its exact version. */
static void _set_dependency(Project p, int line, String key, String value) {
  ProjectDependency entry = Scope.calloc(1, sizeof(struct ProjectDependency));
  *entry = (struct ProjectDependency) {
    .name = key, .version = _string_value(p, line, value)};
  ProjectDependency *link = &p.dependencies;
  while (*link) link = &(*link).next;
  *link = entry;
}

static void _set_target_field(
  Project p, ProjectTarget target, int line, String key, String value) {
  List *list = _target_list(target, key);
  if (list) *list = _string_array(p, line, value);
  else if (key == "kind") _set_kind(p, target, line, value);
  else if (key == "output") target.output = _string_value(p, line, value);
  else $project.error("field.target", p, line, key);
}

static List *_target_list(ProjectTarget target, String key) {
  if (key == "sources") return &target.sources;
  if (key == "exclude") return &target.exclude;
  if (key == "dependencies") return &target.dependencies;
  if (key == "native-modules") return &target.native_modules;
  if (key == "include-dirs") return &target.include_dirs;
  if (key == "package-dirs") return &target.package_dirs;
  if (key == "defines") return &target.defines;
  if (key == "c-flags") return &target.c_flags;
  if (key == "library-dirs") return &target.library_dirs;
  if (key == "libraries") return &target.libraries;
  if (key == "link-flags") return &target.link_flags;
  return NULL;
}

static void _set_kind(
  Project p, ProjectTarget target, int line, String value) {
  String kind = _string_value(p, line, value);
  if (kind == "executable") target.kind = <executable>;
  else if (kind == "static-library") target.kind = <static-lib>;
  else if (kind == "meta-module") target.kind = <module>;
  else if (kind == "shared-library")
    $project.error("kind.shared", p, line);
  else $project.error("kind.unknown", p, line, kind);
}

static void _set_profile_field(
  Project p, ProjectProfile profile, int line, String key, String value) {
  if (key == "optimization")
    profile.optimization = _string_value(p, line, value);
  else if (key == "debug") profile.debug = _bool_value(p, line, value);
  else if (key == "defines") profile.defines = _string_array(p, line, value);
  else if (key == "c-flags") profile.c_flags = _string_array(p, line, value);
  else if (key == "link-flags")
    profile.link_flags = _string_array(p, line, value);
  else $project.error("field.profile", p, line, key);
}

// values

static String _string_value(Project p, int line, String value) {
  char *at = value;
  String text = _parse_string(p, line, &at);
  if (*_skip_space(at)) $project.error("string.tail", p, line);
  return text;
}

static List _string_array(Project p, int line, String value) {
  char *at = _skip_space(value ? value : "");
  if (*at != '[') $project.error("array.expected", p, line);
  at = _skip_space(at + 1);
  Array values = [];
  while (*at != ']') {
    values.push(_parse_string(p, line, &at));
    at = _skip_space(at);
    if (*at == ',') at = _skip_space(at + 1);
    else if (*at != ']') $project.error("array.separator", p, line);
  }
  if (*_skip_space(at + 1)) $project.error("array.tail", p, line);
  return values.list_free();
}

/* Reads the quoted string at `*cursor` and moves the cursor past it. */
static String _parse_string(Project p, int line, char **cursor) {
  char *at = _skip_space(*cursor ? *cursor : "");
  if (*at != '"') $project.error("string.expected", p, line);
  Buffer out = Buffer.new(0);
  for (at++; *at && *at != '"'; at++) {
    char ch = *at;
    if (ch == '\\') ch = _escape(p, line, *++at);
    out.write_char(ch);
  }
  if (*at != '"') $project.error("string.open", p, line);
  *cursor = at + 1;
  return out.str_free();
}

/* The character that a backslash before `ch` stands for. */
static char _escape(Project p, int line, char ch) {
  if (ch == '"' || ch == '\\') return ch;
  if (ch == 'n') return '\n';
  if (ch == 't') return '\t';
  $project.error("string.escape", p, line);
}

static int _bool_value(Project p, int line, String value) {
  if (value && value == "true") return 1;
  if (value && value == "false") return 0;
  $project.error("bool.expected", p, line);
}

/* Whether `value` opens an array that no later bracket closes, so the field
   continues on the next manifest line. A bracket inside a quoted string is
   part of the string. */
static int _array_open(String value) {
  int depth = 0, quoted = 0;
  for (const char *at = value ? value : ""; *at; at++) {
    if (quoted) {
      if (*at == '\\' && at[1]) at++;
      else if (*at == '"') quoted = 0;
    }
    else if (*at == '"') quoted = 1;
    else if (*at == '[') depth++;
    else if (*at == ']') depth--;
  }
  return depth > 0;
}

static int _name_ok(String name) {
  if (!name || !name[0]) return 0;
  foreach (char raw, name) {
    unsigned char ch = raw;
    if (!(isalnum(ch) || ch == '_' || ch == '-')) return 0;
  }
  return 1;
}

static char *_skip_space(char *at) {
  while (isspace((unsigned char) *at)) at++;
  return at;
}

// targets

static ProjectTarget _target(Project p, String name) {
  ProjectTarget target = p.targets;
  while (target && target.name != name) target = target.next;
  return target;
}

static ProjectTarget _new_target(Project p, String name) {
  ProjectTarget target = Scope.calloc(1, sizeof(struct ProjectTarget));
  *target = (struct ProjectTarget) {
    .name = name, .kind = <executable>, .seen = {}, .next = p.targets};
  p.targets = target;
  return target;
}

static ProjectProfile _profile(ProjectTarget target, String name) {
  ProjectProfile profile = target.profiles;
  while (profile && profile.name != name) profile = profile.next;
  return profile;
}

static ProjectProfile _new_profile(ProjectTarget target, String name) {
  ProjectProfile profile = Scope.calloc(1, sizeof(struct ProjectProfile));
  *profile = (struct ProjectProfile) {
    .name = name, .seen = {}, .next = target.profiles};
  target.profiles = profile;
  return profile;
}

/* Every prerequisite names a target, and no target reaches itself. */
static void _validate_target(Project p, ProjectTarget target) {
  if (target.visited) return;
  if (target.visiting)
    $project.error("target.cycle", p, target.name);
  target.visiting = 1;
  foreach (String name, _prerequisites(target)) {
    ProjectTarget prerequisite = _target(p, name);
    if (!prerequisite) $project.error("target.dep", p, name);
    _validate_target(p, prerequisite);
  }
  target.visiting = 0;
  target.visited = 1;
}

/* The targets built before `target`: the libraries it links and the
   native modules its translation loads. */
static List _prerequisites(ProjectTarget target) =>
  target.dependencies.append(target.native_modules);

static ProjectProfile _selected_profile(
  Project p, ProjectTarget target, String name) {
  if (!name) return NULL;
  ProjectProfile profile = _profile(target, name);
  if (!profile) $project.error("profile.unknown", p, name);
  return profile;
}

// package dependencies

/* Installs whatever the manifest pins that the home does not already hold,
   then records what was resolved beside the manifest. A pin the lockfile
   already covers is installed from the archive the lockfile recorded, which
   is what makes a later build reproduce the same packages; only a pin the
   lockfile does not cover reaches the index. A manifest with no pins has
   nothing to reproduce, so a lockfile left from an earlier `[dependencies]`
   section goes. The editor reads a source view and never installs, and a dry
   run creates nothing. */
static void _resolve_dependencies(Project p) {
  CliRequest request = p.command;
  if (p.sources || request.dry_run) return;
  String path = %"${p.root}/x2c.lock";
  if (!p.dependencies) {
    try Path.remove_file(path);
    catch %(io-fail *detail): host_error(detail);
    return;
  }
  List locked = _read_lock(path);
  if (_lock_satisfies(p, locked)) return;
  Array rows = [];
  for (ProjectDependency entry = p.dependencies; entry; entry = entry.next)
    rows.push(
      install_require(
        request, entry.name, entry.version, _locked_row(locked, entry)));
  _write_lock(path, rows.list_free());
}

/* The lockfile's rows, or NULL when it is absent. */
static List _read_lock(String path) {
  String text = NULL;
  try text = Path.read_text(path);
  catch %(not-found *): return NULL;
  return install_rows(text);
}

/* Every dependency is locked at its pinned version and already installed at
   that version, so the build needs no index and no network. */
static int _lock_satisfies(Project p, List rows) {
  if (!rows) return 0;
  for (ProjectDependency entry = p.dependencies; entry; entry = entry.next) {
    if (!_locked_row(rows, entry)) return 0;
    if (install_version(entry.name) != entry.version) return 0;
  }
  return 1;
}

/* The lockfile row that pins `entry` at its version, or NULL when the
   lockfile has none and the index has to resolve it. */
static List _locked_row(List rows, ProjectDependency entry) {
  List found = NULL;
  foreach (List row, rows)
    if (row.car() == entry.name && row.cadr() == entry.version) found = row;
  return found;
}

static void _write_lock(String path, List rows) {
  String text =
    "# x2c lockfile. Written by x2c build; keep it with the manifest.\n"
    "# name version kind platform url sha256\n";
  foreach (List row, rows) text = %"$text${" ".join(row)}\n";
  try file_publish(%($path $text));
  catch %(io-fail *detail): host_error(detail);
}

// build plans

/* A target plans after its prerequisites, and each target plans once. */
static void _plan_target(Project p, ProjectTarget target) {
  if (target.planned) return;
  foreach (String name, _prerequisites(target))
    _plan_target(p, _target(p, name));
  _append_plan(p, _target_request(p, target));
  target.planned = 1;
}

static void _append_plan(Project p, CliRequest request) {
  ProjectBuild node = Scope.calloc(1, sizeof(struct ProjectBuild));
  node.request = request;
  if (p.tail) p.tail.next = node;
  else p.head = node;
  p.tail = node;
}

/* Each planned target receives a Scope-owned copy of the command request.
   Target-specific Lists are rebuilt, dependencies become archive inputs, and
   the per-target `.x2c` directory keeps artifacts and state separate. The
   state seed identifies the manifest, target, and profile. Effective settings
   enter fingerprints through the lowered request and action arguments. */
static CliRequest _target_request(Project p, ProjectTarget target) {
  CliRequest command = p.command;
  CliRequest request = Scope.malloc(sizeof(struct CliRequest));
  *request = *command;
  _set_product(p, target, request);
  request.inputs = _target_inputs(p, target, request.kind);
  request.native_modules =
    %(@{command.native_modules} @{_target_modules(p, target)});
  request.include_dirs =
    %(@{command.include_dirs} @{_paths(p.root, target.include_dirs)});
  request.package_dirs =
    %(@{command.package_dirs} @{_paths(p.root, target.package_dirs)});
  _set_flags(p, target, request);
  request.label = target.name;
  request.state_seed =
    %"${p.path}\ntarget=${target.name}\nprofile=${command.profile}";
  return request;
}

/* The selected target builds or runs what the command asked for; every
   other target is a plain build of its own kind. No planned build keeps
   temporaries or stops at objects. */
static void _set_product(Project p, ProjectTarget target, CliRequest request) {
  CliRequest command = p.command;
  int chosen = target == p.selected;
  request.command = chosen ? command.command : <build>;
  request.run_args = chosen ? command.run_args : NULL;
  request.compile_only = 0;
  request.kind = chosen && command.kind_explicit ? command.kind : target.kind;
  request.output = chosen && command.output ?
    command.output : _target_output(p, target, request.kind);
  request.build_dir = %"${p.build_root}/.x2c/${target.name}";
  request.save_temps = 0;
  request.temps_dir = NULL;
}

static String _target_output(Project p, ProjectTarget target, Symbol kind) {
  String root = p.build_root;
  if (target.output) return Path.join(p.root, target.output);
  if (kind == <static-lib>) return %"$root/lib${target.name}.a";
  if (kind == <module>) return %"$root/${target.name}.so";
  return %"$root/${target.name}";
}

/* A target's sources, then the archives of the libraries it links. */
static List _target_inputs(Project p, ProjectTarget target, Symbol kind) {
  if (kind == <static-lib> && target.dependencies)
    $project.error("target.static.deps", p, target.name);
  Array inputs = _target_sources(p, target);
  foreach (String name, target.dependencies) {
    ProjectTarget dependency = _target(p, name);
    if (dependency.kind != <static-lib>)
      $project.error("target.dep.kind", p, dependency.name);
    inputs.push(_target_output(p, dependency, dependency.kind));
  }
  return inputs.list_free();
}

/* The modules a target's translation loads, each a meta-module target's
   output. */
static List _target_modules(Project p, ProjectTarget target) {
  Array modules = [];
  foreach (String name, target.native_modules) {
    ProjectTarget loaded = _target(p, name);
    if (loaded.kind != <module>)
      $project.error("target.module.kind", p, name);
    modules.push(_target_output(p, loaded, <module>));
  }
  return modules.list_free();
}

// sources

/* What the source patterns match, less what the exclude patterns match,
   sorted. Every source is x2c or C. */
static Array _target_sources(Project p, ProjectTarget target) {
  if (!target.sources) $project.error("source.none", p, target.name);
  Array sources = _expand_patterns(p, target.sources, "source");
  Array excluded = _expand_patterns(p, target.exclude, "exclude");
  Array kept = [];
  foreach (Var path, sources) {
    if (!(path in excluded)) kept.push(path);
    else if (p.command.verbose)
      fprintf(
        stderr, "x2c: excluded %s from target %s\n", path.string(),
        target.name);
  }
  sources.free();
  excluded.free();
  kept.sort();
  foreach (String path, kept)
    if (!(is_source_file(path) || path.endswith(".c")))
      $project.error("source.kind", p, path);
  return kept;
}

/* The files the patterns match, each once, in the order they first match. */
static Array _expand_patterns(Project p, List patterns, String owner) {
  Array files = [];
  foreach (String pattern, patterns) {
    Array expanded = _expand_pattern(p, pattern, owner);
    foreach (Var path, expanded) if (!(path in files)) files.push(path);
    expanded.free();
  }
  return files;
}

static Array _expand_pattern(Project p, String pattern, String owner) {
  Array matches =
    _has_glob(pattern) ? _glob(p, pattern) : _named_file(p, pattern);
  if (!matches.len()) $project.error("pattern.unmatched", p, owner, pattern);
  return matches.sort();
}

static int _has_glob(String pattern) => pattern && strpbrk(pattern, "*?[");

/* A pattern with a wildcard matches the files, or the links to files, that
   its glob names below the project root, outside the build root, and the
   overlay files there too. */
static Array _glob(Project p, String pattern) {
  String prefix = p.root == "/" ? "/" : %"${p.root}/";
  List found = Path.glob(Path.join(_glob_literal(p.root), pattern));
  if (p.sources) found = found.append(p.sources.overlays.keys());
  Array matches = [];
  foreach (String path, found)
    if (path.startswith(prefix) &&
        Path.glob_match(pattern, path.remove_prefix(prefix)) &&
        !(p.build_root && path.startswith(%"${p.build_root}/")) &&
        p.sources.exists(path) && !(path in matches))
      matches.push(path);
  return matches;
}

/* `text` with its glob wildcards escaped, so a glob matches it literally. */
static String _glob_literal(String text) =>
  text.replace("\\", "\\\\").replace("*", "\\*").replace("?", "\\?")
    .replace("[", "\\[");

/* A pattern without a wildcard names one file. */
static Array _named_file(Project p, String pattern) {
  Array matches = [];
  String path = Path.join(p.root, pattern);
  if (p.sources.exists(path)) matches.push(path);
  return matches;
}

// options

/* A profile's defines and flags follow the target's own. */
static void _set_flags(Project p, ProjectTarget target, CliRequest request) {
  CliRequest command = p.command;
  ProjectProfile profile = _target_profile(p, target);
  List defines = _defines(target.defines), profile_defines = NULL;
  List compile = NULL, link = NULL;
  if (profile) {
    profile_defines = _defines(profile.defines);
    compile = _profile_flags(p, profile);
    link = profile.link_flags;
  }
  request.cpp_args = %(@defines @profile_defines @{command.cpp_args});
  request.cc_args = %(
    @defines @{_c_flags(p, target.c_flags)} @profile_defines @compile
    @{command.cc_args} @{_path_options(p.root, target.include_dirs, "-I")});
  request.ld_args = %(
    @{_path_options(p.root, target.library_dirs, "-L")}
    @{target.libraries.map(%!(library) => %"-l$library")}
    @{target.link_flags} @link @{command.ld_args});
}

/* A dependency target takes the profile when it defines one; only the
   selected target must have the profile the command named. */
static ProjectProfile _target_profile(Project p, ProjectTarget target) {
  String name = p.command.profile;
  if (target == p.selected) return _selected_profile(p, target, name);
  return name ? _profile(target, name) : NULL;
}

/* A profile's C flags, optimization, and debug option. An -O or -g among
   the command's own C flags takes the place of the profile's. */
static List _profile_flags(Project p, ProjectProfile profile) {
  List cc_args = p.command.cc_args;
  int optimized = cc_args.any(%!(String flag) => flag.startswith("-O"));
  int debug = profile.debug && !("-g" in cc_args);
  return %(
    @{_c_flags(p, profile.c_flags)}
    @{profile.optimization && !optimized ?
      %("-${profile.optimization}") : NULL}
    @{debug ? %("-g") : NULL});
}

static List _c_flags(Project p, List values) {
  foreach (String value, values)
    if (cli_dependency_pass_through(value))
      $project.error("cflag.deps", p, value);
  return values;
}

static List _defines(List values) => values.map(%!(value) => %"-D$value");

static List _paths(String root, List values) =>
  values.map(%!(String value) => Path.join(root, value));

static List _path_options(String root, List values, String option) =>
  _paths(root, values).map(%!(path) => %($option $path)).flatten();

// diagnostics

static void _error(Project p, int line, String message) {
  String at = line ? ":%d".printf(line) : NULL;
  if (p && p.path) message = %"manifest '${p.path}'$at: $message";
  fprintf(stderr, "x2c: error: %s\n", message);
  exit(2);
}

static void _error_name(Project p, int line, String message, String name) {
  _error(p, line, %"$message '$name'");
}

// new projects

/** Creates the starter project for `x2c new` in the directory named by
    `request`'s one operand and returns 0. The directory may be missing or
    empty, and its last component names the target. Any other directory, an
    unusable name, or a failed write prints a diagnostic and exits with
    status 2.
*/
int new_command(CliRequest request) {
  Path dir = request.inputs.car();
  if (!dir) $project.error("new.empty");
  String name = _starter_name(dir);
  try _write_starter(dir, name);
  catch %(io-fail *detail): host_error(detail);
  if (!request.quiet) fprintf(stderr, "x2c: created %s\n", dir);
  return 0;
}

/* The operand's own last component names the target, so a symbolic link
   is named for the link and not for what it points at. */
static String _starter_name(Path dir) {
  String name = dir.basename();
  if (name == "." || name == ".." || name == "/")
    name = Path.absolute(dir).basename();
  if (!_name_ok(name))
    $project.error("new.name", name);
  return name;
}

static void _write_starter(Path dir, String name) {
  if (dir.exists() && (!dir.is_dir() || dir.list_dir()))
    $project.error("new.occupied", dir);
  dir.join("src").make_dirs();
  dir.join("x2c.toml").write_text(
    %"[target.$name]
sources = [\"src/*.x\"]
");
  dir.join("src/main.x").write_text(
    %"/*  main.x -- greet the name given on the command line */

#include <stdio.h>

int main(int argc, char **argv) {
  String name = argc > 1 ? argv[1] : \"world\";
  puts(%\"Hello, \$name!\");
  return 0;
}
");
  dir.join(".gitignore").write_text(".x2c-build/\n");
}
