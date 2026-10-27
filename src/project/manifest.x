/*  manifest.x -- manifest parsing and model construction */

// manifest lines

/* The parser's place in a manifest: the line it reads and the section that
   line belongs to, with the section's target or profile. A field whose
   array spans lines keeps its key, its value so far, and the line it starts
   on until a bracket closes the array. */
static typedef struct Manifest {
  Project project, int line, Symbol section;
  ProjectTarget target, ProjectProfile profile;
  String key, value, int start;
} Manifest;

// values

/** Returns whether a target, profile, or manifest field name contains only
    letters, digits, underscores, and hyphens, and is not empty.
*/
int ProjectBuild.valid_name(String name) {
  if (!name) return 0;
  foreach (char raw in name) {
    unsigned char ch = raw;
    if (!(isalnum(ch) || ch == '_' || ch == '-')) return 0;
  }
  return 1;
}

// manifest parsing and model construction

/* Each line is a section header, a `key = value` field, or the next line of
   a field whose array is open. A `#` outside a string starts a comment. */
module void _parse_manifest(Project p) {
  Manifest m = {.project = p};
  foreach (String text in p.text.split_lines(0)) {
    m.line++;
    char *line = _content(text);
    if (!*line) continue;
    if (m.key) _extend(m, line);
    else if (*line == '[') _header(m, line);
    else _field(m, line);
  }
  if (m.key) _error(p, m.start, "unterminated array");
  if (!p.targets) _error(p, 0, "manifest defines no targets");
}

/* A copy of the line that the parser may write into, without its comment
   and surrounding space. */
static char *_content(String text) {
  const char *source = text;
  char *line = xmemdup(source ? source : "", (size_t) text.len() + 1);
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

// sections

/* A header opens `[project]`, `[dependencies]`, `[target.<name>]`, or
   `[target.<name>.profile.<name>]`, and each section appears once. */
static void _header(Manifest &m, char *line) {
  int length = strlen(line);
  if (length < 3 || line[length - 1] != ']')
    _error(m.project, m.line, "malformed section header");
  line[length - 1] = 0;
  String name = String.new(line + 1);
  if (name == "project") _enter_project(m);
  else if (name == "dependencies") _enter_dependencies(m);
  else _target_header(m, name);
}

static void _enter_project(Manifest &m) {
  Project p = m.project;
  if (p.declared) _error(p, m.line, "duplicate project section");
  p.declared = 1;
  m.section = <project>;
}

static void _enter_dependencies(Manifest &m) {
  Project p = m.project;
  if (p.dependency_declared)
    _error(p, m.line, "duplicate dependencies section");
  p.dependency_declared = 1;
  p.dependency_seen = {};
  m.section = <deps>;
}

/* A profile header mentions its target too, so the target exists even
   before its own section. */
static void _target_header(Manifest &m, String header) {
  Project p = m.project;
  String name = header.remove_prefix("target."), profile = NULL;
  int split = name.find(".profile.");
  if (split >= 0) {
    profile = name[split + 9:];
    name = name[:split];
  }
  if (!header.startswith("target.") || !ProjectBuild.valid_name(name) ||
      (split >= 0 && !ProjectBuild.valid_name(profile)))
    _error(p, m.line, "unknown manifest section");
  ProjectTarget target = _target(p, name);
  if (!target) target = _new_target(p, name);
  if (split < 0) _enter_target(m, target);
  else _enter_profile(m, target, profile);
}

static void _enter_target(Manifest &m, ProjectTarget target) {
  if (target.declared)
    _error_name(m.project, m.line, "duplicate target section", target.name);
  target.declared = 1;
  m.section = <target>;
  m.target = target;
}

static void _enter_profile(Manifest &m, ProjectTarget target, String name) {
  ProjectProfile profile = _profile(target, name);
  if (!profile) profile = _new_profile(target, name);
  if (profile.declared)
    _error_name(m.project, m.line, "duplicate profile section", name);
  profile.declared = 1;
  m.section = <profile>;
  m.profile = profile;
}

// fields

/* Associates `key = value` with the current section. */
static void _field(Manifest &m, char *line) {
  Project p = m.project;
  if (m.section == 0) _error(p, m.line, "field appears before a section");
  char *equals = strchr(line, '=');
  if (!equals) _error(p, m.line, "expected key = value");
  *equals = 0;
  String key = String.new(_trim(line)), value = String.new(_trim(equals + 1));
  if (!ProjectBuild.valid_name(key)) _error(p, m.line, "invalid field name");
  _claim(m, key);
  m.key = key;
  m.value = value;
  m.start = m.line;
  _settle(m);
}

static char *_trim(char *text) {
  text = _skip_space(text);
  char *end = text + strlen(text);
  while (end > text && isspace((unsigned char) end[-1])) end--;
  *end = 0;
  return text;
}

/* The next line of an open array continues its field's value. */
static void _extend(Manifest &m, char *line) {
  m.value = %"$(m.value) $(String.new(line))";
  _settle(m);
}

/* Each section takes a key once. */
static void _claim(Manifest &m, String key) {
  Map keys = _keys(m);
  if (key in keys) _error(m.project, m.line, "duplicate manifest field");
  keys[key] = 1;
}

static Map _keys(Manifest &m) {
  if (m.section == <project>) return m.project.seen;
  if (m.section == <deps>) return m.project.dependency_seen;
  return m.section == <target> ? m.target.seen : m.profile.seen;
}

/* A field whose value leaves an array open waits for the line that closes
   it; any other field is set now. */
static void _settle(Manifest &m) {
  if (_array_open(m.value)) return;
  Project p = m.project;
  int line = m.start;
  String key = m.key, value = m.value;
  if (m.section == <project>) _set_project_field(p, line, key, value);
  else if (m.section == <deps>) _set_dependency(p, line, key, value);
  else if (m.section == <target>)
    _set_target_field(p, m.target, line, key, value);
  else _set_profile_field(p, m.profile, line, key, value);
  m.key = NULL;
}

static void _set_project_field(Project p, int line, String key, String value) {
  switch (key) {
    case "name": (void) _string_value(p, line, value); break;
    case "default-target":
      p.default_target = _string_value(p, line, value); break;
    case "build-dir": p.build_dir = _string_value(p, line, value); break;
    default: _error_name(p, line, "unknown project field", key);
  }
}

/* One `[dependencies]` entry: an index package name and its exact version. */
static void _set_dependency(Project p, int line, String key, String value) {
  ProjectDependency entry = xcalloc(1, sizeof(struct ProjectDependency));
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
  else _error_name(p, line, "unknown target field", key);
}

static List *_target_list(ProjectTarget target, String key) {
  switch (key) {
    case "sources": return &target.sources;
    case "exclude": return &target.exclude;
    case "dependencies": return &target.dependencies;
    case "native-modules": return &target.native_modules;
    case "include-dirs": return &target.include_dirs;
    case "package-dirs": return &target.package_dirs;
    case "defines": return &target.defines;
    case "c-flags": return &target.c_flags;
    case "library-dirs": return &target.library_dirs;
    case "libraries": return &target.libraries;
    case "link-flags": return &target.link_flags;
  }
  return NULL;
}

static void _set_kind(
  Project p, ProjectTarget target, int line, String value) {
  String kind = _string_value(p, line, value), refusal = NULL;
  target.kind = TargetKind.named(kind, refusal);
  if (refusal) _error(p, line, refusal);
  if (!target.kind) _error_name(p, line, "unknown target kind", kind);
}

static void _set_profile_field(
  Project p, ProjectProfile profile, int line, String key, String value) {
  switch (key) {
    case "optimization":
      profile.optimization = _string_value(p, line, value); break;
    case "debug": profile.debug = _bool_value(p, line, value); break;
    case "defines": profile.defines = _string_array(p, line, value); break;
    case "c-flags": profile.c_flags = _string_array(p, line, value); break;
    case "link-flags":
      profile.link_flags = _string_array(p, line, value); break;
    default: _error_name(p, line, "unknown profile field", key);
  }
}



static String _string_value(Project p, int line, String value) {
  char *at = value;
  String text = _parse_string(p, line, &at);
  if (*_skip_space(at)) _error(p, line, "unexpected text after string");
  return text;
}

static List _string_array(Project p, int line, String value) {
  char *at = _skip_space(value ? value : "");
  if (*at != '[') _error(p, line, "expected an array of quoted strings");
  at = _skip_space(at + 1);
  Array values = [];
  while (*at != ']') {
    values.push(_parse_string(p, line, &at));
    at = _skip_space(at);
    if (*at == ',') at = _skip_space(at + 1);
    else if (*at != ']') _error(p, line, "expected ',' or ']' in array");
  }
  if (*_skip_space(at + 1)) _error(p, line, "unexpected text after array");
  return values.list_free();
}

/* Reads the quoted string at `*cursor` and moves the cursor past it. */
static String _parse_string(Project p, int line, char **cursor) {
  char *at = _skip_space(*cursor ? *cursor : "");
  if (*at != '"') _error(p, line, "expected a quoted string");
  Buffer out = Buffer.new(0);
  for (at++; *at && *at != '"'; at++) {
    char ch = *at;
    if (ch == '\\') ch = _escape(p, line, *++at);
    out.write_char(ch);
  }
  if (*at != '"') _error(p, line, "unterminated quoted string");
  *cursor = at + 1;
  return out.str_free();
}

/* The character that a backslash before `ch` stands for. */
static char _escape(Project p, int line, char ch) {
  if (ch == '"' || ch == '\\') return ch;
  if (ch == 'n') return '\n';
  if (ch == 't') return '\t';
  _error(p, line, "unsupported string escape");
}

static int _bool_value(Project p, int line, String value) {
  if (value && value == "true") return 1;
  if (value && value == "false") return 0;
  _error(p, line, "expected true or false");
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

static char *_skip_space(char *at) {
  while (isspace((unsigned char) *at)) at++;
  return at;
}

// targets

module ProjectTarget _target(Project p, String name) {
  ProjectTarget target = p.targets;
  while (target && target.name != name) target = target.next;
  return target;
}

static ProjectTarget _new_target(Project p, String name) {
  ProjectTarget target = xcalloc(1, sizeof(struct ProjectTarget));
  *target = (struct ProjectTarget) {
    .name = name, .kind = <executable>, .seen = {}, .next = p.targets};
  p.targets = target;
  return target;
}

module ProjectProfile _profile(ProjectTarget target, String name) {
  ProjectProfile profile = target.profiles;
  while (profile && profile.name != name) profile = profile.next;
  return profile;
}

static ProjectProfile _new_profile(ProjectTarget target, String name) {
  ProjectProfile profile = xcalloc(1, sizeof(struct ProjectProfile));
  *profile = (struct ProjectProfile) {
    .name = name, .seen = {}, .next = target.profiles};
  target.profiles = profile;
  return profile;
}

// diagnostics

module void _error_name(Project p, int line, String message, String name) {
  _error(p, line, %"$message '$name'");
}



module void _error(Project p, int line, String message) {
  String at = line ? ":%d".printf(line) : NULL;
  if (p && p.path) message = %"manifest '$(p.path)'$at: $message";
  fprintf(stderr, "x2c: error: %s\n", message);
  exit(2);
}
