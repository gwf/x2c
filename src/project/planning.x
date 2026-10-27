/*  planning.x -- discovery and dependency-ordered build requests */

// planning

/** Parses a project manifest and returns its selected target's build plan.
    `request` must be a build or run request with no explicit operands. The
    result contains each dependency once before its consumer and lowers
    manifest fields and command-line overrides to ordinary `CliRequest` values
    without executing build actions. Manifest discovery, parsing, validation,
    or target-selection failures print a diagnostic and exit with status 2.
*/
ProjectBuild ProjectBuild.plan(CliRequest request) {
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

/** Returns the explicit or nearest readable project manifest, or NULL.
    Discovery uses the same request view as project parsing.
*/
String CliRequest.project_manifest(CliRequest c) {
  if (c.manifest) return c.manifest;
  for (Path directory = Path.absolute(".");; directory = directory.dirname()) {
    String candidate = directory.join("x2c.toml");
    if (c.sources.exists(candidate)) return candidate;
    if (directory == "/") return NULL;
  }
}

// discovery and dependency-ordered build requests

/* A project whose manifest text is read and not yet parsed. */
static Project _open_project(CliRequest request) {
  Project p = xcalloc(1, sizeof(struct Project));
  *p = (struct Project) {
    .seen = {}, .sources = request.sources, .command = request,
    .path = request.project_manifest()};
  if (!p.path) _error(NULL, 0, "no explicit inputs and no x2c.toml found");
  p.path = Path.absolute(p.path);
  if (!p.sources.read(p.path, p.text)) _error(p, 0, "cannot read manifest");
  p.root = Path.dirname(p.path);
  return p;
}

/* The target the command names, else the manifest's default, else the
   manifest's only target. The command must be able to build it as asked. */
static ProjectTarget _selected_target(Project p) {
  CliRequest request = p.command;
  String name = request.target ? request.target : p.default_target;
  if (!name && p.targets.next)
    _error(p, 0, "select --target or set project.default-target");
  if (!name) name = p.targets.name;
  ProjectTarget selected = _target(p, name);
  if (!selected) _error_name(p, 0, "unknown target", name);
  Symbol kind = request.kind_explicit ? request.kind : selected.kind;
  if (request.command == <run> && kind != <executable>)
    _error(p, 0, "run requires an executable target");
  (void) _selected_profile(p, selected, request.profile);
  return selected;
}

/* The command's build directory, relative to the working directory, else
   the manifest's, relative to the project root. */
static String _build_root(Project p) {
  String dir = p.command.build_dir;
  if (dir) return Path.absolute(".").join(dir);
  if (p.build_dir) return Path.join(p.root, p.build_dir);
  return %"$(p.root)/.x2c-build";
}

/* Every prerequisite names a target, and no target reaches itself. */
static void _validate_target(Project p, ProjectTarget target) {
  if (target.visited) return;
  if (target.visiting)
    _error_name(p, 0, "target dependency cycle reaches", target.name);
  target.visiting = 1;
  foreach (String name in _prerequisites(target)) {
    ProjectTarget prerequisite = _target(p, name);
    if (!prerequisite) _error_name(p, 0, "unknown target dependency", name);
    _validate_target(p, prerequisite);
  }
  target.visiting = 0;
  target.visited = 1;
}

// package dependencies

/* The package command owns lockfile and installation state. Editor source
   views and dry runs do not prepare dependencies. */
static void _resolve_dependencies(Project p) {
  CliRequest request = p.command;
  if (p.sources || request.dry_run) return;
  String path = %"$(p.root)/x2c.lock";
  struct stat lock;
  if (!p.dependencies && lstat(path, &lock) && errno == ENOENT) return;
  Array args = ["ensure", "--lock", path];
  if (request.index) {
    args.push("--index");
    args.push(request.index);
  }
  if (request.quiet) args.push("--quiet");
  args.push("--");
  for (ProjectDependency entry = p.dependencies; entry; entry = entry.next) {
    args.push(entry.name);
    args.push(entry.version);
  }
  int status = Compiler.run_command("package", args);
  if (status) exit(status);
}

// build plans

/* A target plans after its prerequisites, and each target plans once. */
static void _plan_target(Project p, ProjectTarget target) {
  if (target.planned) return;
  foreach (String name in _prerequisites(target))
    _plan_target(p, _target(p, name));
  _append_plan(p, _target_request(p, target));
  target.planned = 1;
}

/* The targets built before `target`: the libraries it links and the
   native modules its translation loads. */
static List _prerequisites(ProjectTarget target) =>
  target.dependencies.append(target.native_modules);

static void _append_plan(Project p, CliRequest request) {
  ProjectBuild node = xcalloc(1, sizeof(struct ProjectBuild));
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
  CliRequest request = xmalloc(sizeof(struct CliRequest));
  *request = *command;
  _set_product(p, target, request);
  request.inputs = _target_inputs(p, target, request.kind);
  request.native_modules =
    %(@(command.native_modules) @(_target_modules(p, target)));
  request.include_dirs =
    %(@(command.include_dirs) @(_paths(p.root, target.include_dirs)));
  request.package_dirs =
    %(@(command.package_dirs) @(_paths(p.root, target.package_dirs)));
  _set_flags(p, target, request);
  request.label = target.name;
  request.state_seed =
    %"$(p.path)\ntarget=$(target.name)\nprofile=$(command.profile)";
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
  request.build_dir = %"$(p.build_root)/.x2c/$(target.name)";
  request.save_temps = 0;
}

/* A target's sources, then the archives of the libraries it links. */
static List _target_inputs(Project p, ProjectTarget target, Symbol kind) {
  if (kind == <static-lib> && target.dependencies)
    _error_name(
      p, 0, "static-library target cannot contain target dependencies",
      target.name);
  Array inputs = _target_sources(p, target);
  foreach (String name in target.dependencies) {
    ProjectTarget dependency = _target(p, name);
    if (dependency.kind != <static-lib>)
      _error_name(
        p, 0, "dependency target is not a static library", dependency.name);
    inputs.push(_target_output(p, dependency, dependency.kind));
  }
  return inputs.list_free();
}

/* The modules a target's translation loads, each a meta-module target's
   output. */
static List _target_modules(Project p, ProjectTarget target) {
  Array modules = [];
  foreach (String name in target.native_modules) {
    ProjectTarget loaded = _target(p, name);
    if (loaded.kind != <module>)
      _error_name(p, 0, "native module target is not a meta-module", name);
    modules.push(_target_output(p, loaded, <module>));
  }
  return modules.list_free();
}

static String _target_output(Project p, ProjectTarget target, Symbol kind) {
  if (target.output) return Path.join(p.root, target.output);
  TargetKind *row = TargetKind.of(kind);
  return %"$(p.build_root)/$(row.prefix)$(target.name)$(row.suffix)";
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
  request.cpp_args = %(@defines @profile_defines @(command.cpp_args));
  request.cc_args = %(
    @defines @(_c_flags(p, target.c_flags)) @profile_defines @compile
    @(command.cc_args) @(_path_options(p.root, target.include_dirs, "-I")));
  request.ld_args = %(
    @(_path_options(p.root, target.library_dirs, "-L"))
    @(target.libraries.map(%!(library) => %"-l$library"))
    @(target.link_flags) @link @(command.ld_args));
}

/* A dependency target takes the profile when it defines one; only the
   selected target must have the profile the command named. */
static ProjectProfile _target_profile(Project p, ProjectTarget target) {
  String name = p.command.profile;
  if (target == p.selected) return _selected_profile(p, target, name);
  return name ? _profile(target, name) : NULL;
}

static ProjectProfile _selected_profile(
  Project p, ProjectTarget target, String name) {
  if (!name) return NULL;
  ProjectProfile profile = _profile(target, name);
  if (!profile) _error_name(p, 0, "target has no profile", name);
  return profile;
}

/* A profile's C flags, optimization, and debug option. An -O or -g among
   the command's own C flags takes the place of the profile's. */
static List _profile_flags(Project p, ProjectProfile profile) {
  List cc_args = p.command.cc_args;
  int optimized = cc_args.any(%!(String flag) => flag.startswith("-O"));
  int debug = profile.debug && !("-g" in cc_args);
  return %(
    @(_c_flags(p, profile.c_flags))
    @(profile.optimization && !optimized ?
      %("-$(profile.optimization)") : NULL)
    @(debug ? %("-g") : NULL));
}

static List _c_flags(Project p, List values) {
  foreach (String value in values)
    if (CliRequest.dependency_option(value))
      _error_name(p, 0, "C dependency option is driver-owned", value);
  return values;
}

static List _defines(List values) => values.map(%!(value) => %"-D$value");

static List _path_options(String root, List values, String option) =>
  _paths(root, values).map(%!(path) => $(option, path)).flatten();

static List _paths(String root, List values) =>
  values.map(%!(String value) => Path.join(root, value));
