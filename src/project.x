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
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "buffer.x"

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

typedef struct Project {
  String path, root, text, default_target, build_dir, build_root, Map seen;
  int declared;
  SourceView sources;
  ProjectTarget targets;
  ProjectBuild head;
  ProjectBuild tail;
} *Project;

static void _error(Project project, int line, const char *message) {
  if (project && project.path && line)
    fprintf(
      stderr, "x2c: error: manifest '%s':%d: %s\n",
      project.path, line, message);
  else if (project && project.path)
    fprintf(stderr, "x2c: error: manifest '%s': %s\n", project.path, message);
  else fprintf(stderr, "x2c: error: %s\n", message);
  exit(2);
}

static void _error_name(
  Project project, int line, const char *message, String name) {
  if (line)
    fprintf(
      stderr, "x2c: error: manifest '%s':%d: %s '%s'\n",
      project.path, line, message, name);
  else
    fprintf(
      stderr, "x2c: error: manifest '%s': %s '%s'\n",
      project.path, message, name);
  exit(2);
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
  Array values = %[];
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
  List result = values.list_free();
  return result;
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
  target.seen = %{};
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
  profile.seen = %{};
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
      _error(
        p, line,
        "shared-library is not supported by this compiler");
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

static void _parse_manifest(Project p) {
  enum { NONE, PROJECT, TARGET, PROFILE } section = NONE;
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
      List parts = name.split(%"."), int count = parts.len();
      String first = parts.car();
      String second = parts.cdr() ? parts.cdr().car().string() : NULL;
      String third = parts.cdr() && parts.cdr().cdr() ?
                     parts.cdr().cdr().car().string() : NULL;
      String fourth =
        parts.cdr() && parts.cdr().cdr() &&
        parts.cdr().cdr().cdr() ?
        parts.cdr().cdr().cdr().car().string() : NULL;
      if ((count != 2 && count != 4) ||
          first != "target" ||
          !_name_ok(second) ||
          (count == 4 && (third != "profile" || !_name_ok(fourth))))
        _error(p, line_number, "unknown manifest section");
      target = _target(p, second, 1);
      if (count == 2) {
        if (target.declared)
          _error_name(
            p, line_number, "duplicate target section", second);
        target.declared = 1;
        section = TARGET;
        profile = NULL;
      }
      else {
        section = PROFILE;
        profile = _profile(target, fourth, 1);
        if (profile.declared)
          _error_name(
            p, line_number, "duplicate profile section", fourth);
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
      section == TARGET ? target.seen : profile.seen,
      key
    );
    if (section == PROJECT) _set_project_field(p, line_number, key, value);
    else if (section == TARGET)
      _set_target_field(p, target, line_number, key, value);
    else _set_profile_field(p, profile, line_number, key, value);
  }
  if (!p.targets) _error(p, 0, "manifest defines no targets");
}

static String _absolute(Project project, String path) {
  if (path && path[0] == '/') return path;
  return %"${project.root}/$path";
}

static int _has_glob(String pattern) => pattern && strpbrk(pattern, "*?[");

static int _class_match(const char **pattern, unsigned char value) {
  const char *ch = *pattern, int negate = *ch == '!' || *ch == '^';
  if (negate) ch++;
  int matched = 0;
  while (*ch && *ch != ']') {
    unsigned char first = *ch++;
    if (*ch == '-' && ch[1] && ch[1] != ']') {
      ch++;
      unsigned char last = *ch++;
      if (value >= first && value <= last) matched = 1;
    }
    else if (value == first) matched = 1;
  }
  if (*ch != ']') return -1;
  *pattern = ch + 1;
  return negate ? !matched : matched;
}

static int _glob_match(const char *pattern, const char *text) {
  if (!*pattern) return !*text;
  if (pattern[0] == '*' && pattern[1] == '*') {
    pattern += 2;
    if (*pattern == '/') {
      if (_glob_match(pattern + 1, text)) return 1;
      for (const char *ch = text; *ch; ch++)
        if (_glob_match(pattern - 2, ch + 1)) return 1;
      return 0;
    }
    if (_glob_match(pattern, text)) return 1;
    return *text && _glob_match(pattern - 2, text + 1);
  }
  if (*pattern == '*') {
    pattern++;
    if (_glob_match(pattern, text)) return 1;
    return *text && *text != '/' && _glob_match(pattern - 1, text + 1);
  }
  if (*pattern == '?')
    return *text && *text != '/' &&
           _glob_match(pattern + 1, text + 1);
  if (*pattern == '[') {
    if (!*text || *text == '/') return 0;
    const char *rest = pattern + 1;
    int matched = _class_match(&rest, (unsigned char) *text);
    if (matched < 0) return *text == '[' && _glob_match(pattern + 1, text + 1);
    return matched && _glob_match(rest, text + 1);
  }
  if (*pattern == '\\' && pattern[1]) pattern++;
  return *pattern == *text && _glob_match(pattern + 1, text + 1);
}

static void _walk_matches(
  Project project, String directory, String relative, String pattern,
  Array matches) {
  DIR *input = opendir(directory);
  if (!input) return;
  struct dirent *entry;
  while ((entry = readdir(input))) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
      continue;
    String name = String.new(entry->d_name);
    String child_relative = relative ? %"$relative/$name" : name;
    String child = %"${project.root}/$child_relative", struct stat info;
    if (lstat(child, &info)) continue;
    if (S_ISDIR(info.st_mode)) {
      if (project.build_root && child == project.build_root) continue;
      _walk_matches(project, child, child_relative, pattern, matches);
      continue;
    }
    if (S_ISREG(info.st_mode) &&
        _glob_match(pattern, child_relative) &&
        !matches.contains(child))
      matches.push(child);
  }
  closedir(input);
}

static Array _expand_pattern(
  Project project, String pattern, const char *owner) {
  Array matches = %[];
  if (!_has_glob(pattern)) {
    String path = _absolute(project, pattern), struct stat info;
    int present = project.sources ? project.sources.exists(path) :
      !stat(path, &info) && S_ISREG(info.st_mode);
    if (present) matches.push(path);
  }
  else {
    _walk_matches(project, project.root, NULL, pattern, matches);
    if (project.sources) {
      String prefix = project.root == "/" ? %"/" : %"${project.root}/";
      foreach (String path, project.sources.overlays.keys()) {
        if (!path.startswith(prefix)) continue;
        if (project.build_root &&
            path.startswith(%"${project.build_root}/")) continue;
        String relative = path[prefix.len():];
        if (_glob_match(pattern, relative) && !matches.contains(path))
          matches.push(path);
      }
    }
  }
  if (!matches.len()) {
    fprintf(
      stderr, "x2c: error: manifest '%s': unmatched %s pattern '%s'\n",
      project.path, owner, pattern);
    exit(2);
  }
  matches.sort();
  return matches;
}

static Array _target_sources(
  Project project, ProjectTarget target, int verbose) {
  if (!target.sources)
    _error_name(project, 0, "target has no sources", target.name);
  Array sources = %[];
  foreach (String pattern, target.sources) {
    Array expanded = _expand_pattern(project, pattern, "source");
    foreach (Var value, expanded)
      if (!sources.contains(value)) sources.push(value);
    expanded.free();
  }
  Array excluded = %[];
  foreach (String pattern, target.exclude) {
    Array expanded = _expand_pattern(project, pattern, "exclude");
    foreach (Var value, expanded)
      if (!excluded.contains(value)) excluded.push(value);
    expanded.free();
  }
  Array kept = %[];
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
  foreach (Var value, kept) {
    String path = value;
    if (!(path.endswith(%".x") || path.endswith(%".c")))
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
    _error_name(
      project, 0, "target dependency cycle reaches",
      target.name);
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

static void _append_values(Array output, List values) {
  foreach (Var value, values) output.push(value);
}

static void _append_c_flags(Project project, Array output, List values) {
  foreach (String value, values) {
    if (cli_dependency_pass_through(value))
      _error_name(
        project, 0, "C dependency option is driver-owned", value);
    output.push(value);
  }
}

static void _append_defines(Array output, List values) {
  foreach (String value, values) output.push(%"-D$value");
}

static void _append_paths(
  Project project, Array output, List values, String option) {
  foreach (String value, values) {
    output.push(option);
    output.push(_absolute(project, value));
  }
}

static String _target_output(
  Project project, ProjectTarget target, String build_root, Symbol kind) {
  if (target.output) return _absolute(project, target.output);
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
  request.command = target == selected ? command.command : <build>;
  request.run_args = target == selected ? command.run_args : NULL;
  request.compile_only = 0;
  request.kind =
    target == selected && command.kind_explicit ?
    command.kind : target.kind;
  request.output =
    target == selected && command.output ?
    command.output :
    _target_output(p, target, build_root, request.kind);
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

  Array x_paths = %[];
  _append_values(x_paths, command.include_dirs);
  foreach (String path, target.include_dirs)
    x_paths.push(_absolute(p, path));
  request.include_dirs = x_paths.list_free();

  Array package_paths = %[];
  _append_values(package_paths, command.package_dirs);
  foreach (String path, target.package_dirs)
    package_paths.push(_absolute(p, path));
  request.package_dirs = package_paths.list_free();

  ProjectProfile profile =
    target == selected ?
    _selected_profile(p, target, command.profile) : NULL;
  Array preprocess = %[];
  _append_defines(preprocess, target.defines);
  if (profile) _append_defines(preprocess, profile.defines);
  _append_values(preprocess, command.cpp_args);
  request.cpp_args = preprocess.list_free();

  Array compile = %[];
  _append_defines(compile, target.defines);
  _append_c_flags(p, compile, target.c_flags);
  if (profile) {
    int has_optimization = 0, has_debug = 0;
    foreach (String argument, command.cc_args) {
      if (argument && argument.startswith("-O")) has_optimization = 1;
      if (argument == "-g") has_debug = 1;
    }
    _append_defines(compile, profile.defines);
    _append_c_flags(p, compile, profile.c_flags);
    if (profile.optimization && !has_optimization)
      compile.push(%"-${profile.optimization}");
    if (profile.seen.contains(%"debug") && profile.debug &&
        !has_debug)
      compile.push("-g");
  }
  _append_values(compile, command.cc_args);
  _append_paths(p, compile, target.include_dirs, %"-I");
  request.cc_args = compile.list_free();

  Array link = %[];
  _append_paths(p, link, target.library_dirs, %"-L");
  foreach (String library, target.libraries) link.push(%"-l$library");
  _append_values(link, target.link_flags);
  if (profile) _append_values(link, profile.link_flags);
  _append_values(link, command.ld_args);
  request.ld_args = link.list_free();

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

/** Returns the explicit or nearest readable project manifest, or NULL.
    Discovery uses the same request view as project parsing.
*/
String project_manifest(CliRequest request) {
  if (request.manifest) return request.manifest;
  char current[PATH_MAX];
  if (!getcwd(current, sizeof(current)))
    _error(NULL, 0, "cannot read current directory");
  loop {
    String candidate = %"${String.new(current)}/x2c.toml";
    if (request.sources ? request.sources.exists(candidate) :
        !access(candidate, R_OK)) return candidate;
    if (strcmp(current, "/") == 0) break;
    char *slash = strrchr(current, '/');
    if (!slash) break;
    if (slash == current) current[1] = 0;
    else *slash = 0;
  }
  return NULL;
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
  project.seen = %{};
  project.sources = request.sources;
  project.path = project_manifest(request);
  if (!project.path)
    _error(NULL, 0, "no explicit inputs and no x2c.toml found");
  char resolved[PATH_MAX];
  if (realpath(project.path, resolved)) project.path = %"$resolved";
  if (project.sources) {
    project.path = SourceView.path(project.path);
    if (!project.sources.read(project.path, &project.text))
      _error(project, 0, "cannot read manifest");
  }
  else {
    File input = fopen(project.path, "r");
    if (!input) _error(project, 0, "cannot open manifest");
    try project.text = input.string_close();
    catch %(io-fail *): _error(project, 0, "cannot read manifest");
  }
  project.root = x2c_path_dir(project.path);
  _parse_manifest(project);
  for (ProjectTarget target = project.targets; target; target = target.next)
    _validate_target(project, target);

  String selected_name = request.target ? request.target :
                         project.default_target;
  if (!selected_name) {
    if (project.targets && !project.targets.next)
      selected_name = project.targets.name;
    else
      _error(
        project, 0,
        "select --target or set project.default-target");
  }
  ProjectTarget selected = _target(project, selected_name, 0);
  if (!selected)
    _error_name(project, 0, "unknown target", selected_name);
  Symbol selected_kind = request.kind_explicit ? request.kind : selected.kind;
  if (request.command == <run> && selected_kind != <executable>)
    _error(project, 0, "run requires an executable target");

  String build_root = request.build_dir;
  if (build_root && build_root[0] != '/') {
    char current[PATH_MAX];
    if (!getcwd(current, sizeof(current)))
      _error(project, 0, "cannot read current directory");
    build_root = %"${String.new(current)}/$build_root";
  }
  if (!build_root)
    build_root = project.build_dir ?
                 _absolute(project, project.build_dir) :
                 %"${project.root}/.x2c-build";
  project.build_root = build_root;
  _plan_target(project, selected, request, selected, build_root);
  return project.head;
}
