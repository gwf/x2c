/*  install.x -- Package installation into the x2c home

    Copyright (c) 2026 Gary William Flake.

    `x2c install`, `remove`, and `list` manage `<home>/packages`. Fetching
    and extraction run host tools as child processes. A package is staged in
    a sibling directory, built there when it is source, and published with
    one rename. Installs and removals in one home run one at a time.
*/

#pragma once
#include "../lib/private-keywords.x"
#include "build.x"


#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

#include "digest.x"
#include "json.x"


/* install command reports. */

static macro Stmt $report.install.version_pinned(
  Expr $name, Expr $resolved, Expr $version) =>
  _error(%"the index has ${$name} ${$resolved}, not the pinned ${$version}");

static macro Stmt $report.install.spec_unknown(Expr $spec) =>
  _error(%"unknown package spec '${$spec}'");

static macro Stmt $report.install.name_invalid(Expr $name) =>
  _error(%"'${$name}' is not a package name");

static macro Stmt $report.install.target_unmanaged(Expr $target) =>
  _error(%"${$target} exists and is not an installed package");

static macro Stmt $report.install.bundle_version_missing(Expr $name) =>
  _error(%"bundle ${$name} has no readable BUNDLE.json version");

static macro Stmt $report.install.bundle_version_wrong(
  Expr $name, Expr $built, Expr $current) =>
  _error(
    %"bundle ${$name} was built for '${$built}', not '${
      $current}'; use --force");

static macro Stmt $report.install.bundle_archive_missing(Expr $name) =>
  _error(%"bundle ${$name} has no builds/lib${$name}.a");

static macro Stmt $report.install.entry_missing(Expr $spec, Expr $name) =>
  _error(%"${$spec} has no src/${$name}.x entry unit");

static macro Stmt $report.install.dependencies_missing(Expr $name) =>
  _error(%"${$name} needs native dependencies; install its bundle");

static macro Stmt $report.install.index_missing(Expr $location) =>
  _error(%"no package index at ${$location}");

static macro Stmt $report.install.package_missing(
  Expr $name, Expr $platform, Expr $location) =>
  _error(%"no package '${$name}' for ${$platform} in ${$location}");

static macro Stmt $report.install.home_missing(Expr $command) =>
  driver_error(
    %"${$command}: no x2c home: install the compiler or set X2C_HOME");

static macro Stmt $report.install.tool_failed(
  Expr $what, Expr $arguments, Expr $errors) =>
  _error(%"${$what} failed (${$arguments.car()}): ${$errors.strip(" \n")}");

static macro Stmt $report.install.digest_mismatch(
  Expr $p, Expr $expected, Expr $actual) =>
  _error(%"sha256 mismatch for ${$p}: expected ${$expected}, got ${$actual}");

static macro Stmt $report.install.archive_shape(Expr $tarball) =>
  _error(%"${$tarball} must contain one package directory");

static macro Stmt $report.install.remove_missing(Expr $name) =>
  driver_error(%"remove: no installed package '${$name}'");

static macro Stmt $report.install.remove_unmanaged(Expr $target) =>
  driver_error(
    %"remove: ${$target} is not an installed package; remove it by hand");

static macro Stmt $report.install.lock_waiting(Expr $packages) =>
  fprintf(
    stderr, "x2c: waiting for another install or removal in %s\n", $packages);

static macro Stmt $report.install.installed(Expr $packages, Expr $name) =>
  fprintf(stderr, "x2c: installed %s/%s\n", $packages, $name);

static macro Stmt $report.install.removed(Expr $target) =>
  fprintf(stderr, "x2c: removed %s\n", $target);

static macro Expression $report.install.start_failed(Expr $program, Expr $error) =>
  %"x2c: unable to execute ${$program}: ${
    String.new(strerror((int) $error))}\n";


// the packages lock

/* The packages lock this process holds, and the staging directory it is
   filling. `driver_error` exits without running deferred cleanup, so
   every failing exit below releases both first. */
static int _packages_lock = -1;
static String _staging = NULL;

/* Returns the home's packages directory, created and locked for this
   install or removal, so another one waits for it to finish and, unless
   `quiet`, says so. `_release_packages` drops the lock as soon as the
   packages are in place; a `run` that installed a dependency must not hold
   it while the program runs. */
static String _locked_packages(String command, int quiet) {
  Path packages = _home_packages(command), lock = %"$packages/.lock";
  if (_packages_lock >= 0) return packages;
  try packages.make_dirs();
  catch %(io-fail *detail): _host_error(detail);
  int held = file_lock(lock, 0);
  if (held < 0) {
    if (!quiet)
      $report.install.lock_waiting(packages);
    held = file_lock(lock, 1);
  }
  _packages_lock = held;
  return packages;
}

/* Staging directories left by an interrupted install are removed first; the
   caller holds the packages lock, so none belongs to a running install. */
static String _work_directory(String packages) {
  foreach (String name, Path.list_dir(packages))
    if (name.startswith(".install.")) Path.remove_tree(%"$packages/$name");
  Path work = %"$packages/.install.%ld".printf((long) getpid());
  work.make_dirs();
  _staging = work;
  return work;
}

/* Removes the staging directory and then releases the lock, so a waiting
   install never meets a half-removed directory. Both are absent after a
   successful command, which makes this safe to repeat. */
static void _release_packages(void) {
  String work = _staging;
  _staging = NULL;
  if (work) {
    try Path.remove_tree(work);
    catch: {}
  }
  if (_packages_lock >= 0) close(_packages_lock);
  _packages_lock = -1;
}

static void _error(const char *message) {
  _release_packages();
  driver_error(%"install: $message");
}

static void _host_error(List detail) {
  _release_packages();
  host_error(detail);
}

// installing

/* One install under the packages lock. The package comes from the local
   directory or tarball `source`, or from the archive at `url`; `sha256`
   checks a download or a tarball. `spec` is the operand that named the
   package, and `version` the version it resolved to. `packages` is the
   home's packages directory and `work` the staging directory. */
static typedef struct Install {
  CliRequest request, String spec, source, url, sha256, version;
  String packages, work;
} Install;

/** Installs the package named by the request's one operand and returns 0.
    The operand is a local directory, a local `.tar.gz`, a URL with
    `--sha256`, or a name resolved through the package index. A bundle is
    verified against this compiler's version unless `--force`; a pure-x2c
    source package is built by this compiler. Failures exit with status 2.
*/
int install_command(CliRequest request) {
  Install i = _locked_install(request, request.inputs.car());
  defer _release_packages();
  i.sha256 = request.sha256;
  i.locate();
  i.run();
  return 0;
}

/** Returns the row that records `name` at `version`, installing the package
    under the x2c home first unless one already records that version.
    `locked` is the lockfile row to reproduce, so a package a lockfile pins
    comes from the archive that lockfile recorded; NULL resolves the index
    instead. The row has the `install_rows` shape, and an already satisfied
    dependency reaches no network. Failures exit with status 2.
*/
List install_require(
  CliRequest request, String name, String version, List locked) {
  Install i = _locked_install(request, name);
  defer _release_packages();
  List row = locked ? locked : _index_row(request, name, i.work);
  String resolved = row[1];
  if (resolved != version)
    $report.install.version_pinned(name, resolved, version);
  if (_installed_version(%"${i.packages}/$name") != version) {
    i.resolve(row);
    i.run();
  }
  return row;
}

/* An install of `spec` that holds the packages lock and owns a fresh
   staging directory; the caller defers `_release_packages`. */
static Install _locked_install(CliRequest request, String spec) {
  String packages = _locked_packages("install", request.quiet);
  return (Install) {
    .request = request, .spec = spec, .packages = packages,
    .work = _work_directory(packages)};
}

/* The operand is a URL, a local path, or a name the index resolves. */
static void Install.locate(Install &i) {
  String spec = i.spec;
  if (_remote(spec)) {
    if (!i.sha256) _error("a URL needs --sha256 <hex>");
    i.url = spec;
  }
  else if (Path.exists(spec)) i.source = spec;
  else if (spec.is_identifier())
    i.resolve(_index_row(i.request, spec, i.work));
  else $report.install.spec_unknown(spec);
}

/* A resolved row names the version to record and the archive to fetch. */
static void Install.resolve(Install &i, List row) {
  i.version = row[1];
  i.url = row[4];
  i.sha256 = row[5];
}

/* Stages, builds, and publishes one package. */
static void Install.run(Install &i) {
  String package = i.unpacked(), name = Path.basename(package);
  if (!name.is_identifier()) $report.install.name_invalid(name);
  String staged = %"${i.work}/$name";
  try Path.copy_tree(package, staged);
  catch %(io-fail *detail): _host_error(detail);
  if (Path.exists(%"$staged/BUNDLE.json"))
    _check_bundle(i.request, staged, name);
  else {
    _build_source(staged, name, i.spec);
    i.mark_source(staged, name);
  }
  _publish(staged, i.packages, name);
  if (!i.request.quiet)
    $report.install.installed(i.packages, name);
}

/* The package directory: `source` itself, or the tarball that `source`
   names or `url` downloads, checked and unpacked in the work directory. */
static String Install.unpacked(Install &i) {
  String source = i.source;
  if (i.url) {
    source = _fetch(i.url, i.work, "package.tar.gz");
    _verify(source, i.sha256);
  }
  else if (i.sha256 && !Path.is_dir(source)) _verify(source, i.sha256);
  return Path.is_dir(source) ? source : _unpack(source, i.work);
}

/* SOURCE.json records where a source package came from. A local path
   carries no version of its own. The package it replaces recorded one, and
   a project pin matches a name and a version, so dropping it would send the
   next build back to the index. */
static void Install.mark_source(Install &i, String staged, String name) {
  String version = i.version;
  if (!version) version = _installed_version(%"${i.packages}/$name");
  Map record = {
    "package": name, "source": i.url ? i.url : Path.absolute(i.spec),
    "x2c_version": cli_version()
  };
  if (version) record["version"] = version;
  if (i.sha256) record["sha256"] = i.sha256;
  Path.write_text(%"$staged/SOURCE.json", %"${Var.pretty_json(record)}\n");
}

/* Publishes the staged package with one rename, replacing an installed
   package of the same name; a directory that is not an installed package is
   never replaced. The replaced package moves aside inside the work
   directory, which the caller removes. */
static void _publish(String staged, String packages, String name) {
  Path target = %"$packages/$name";
  if (target.exists()) {
    if (!_installed_kind(target))
      $report.install.target_unmanaged(target);
    target.move_to(%"$staged.previous");
  }
  Path.move_to(staged, target);
}

// bundles and source packages

static void _check_bundle(CliRequest request, String package, String name) {
  String built = _marker_string(%"$package/BUNDLE.json", "x2c_version");
  String current = cli_version();
  if (!built) $report.install.bundle_version_missing(name);
  if (built != current && !request.force)
    $report.install.bundle_version_wrong(name, built, current);
  if (!Path.is_file(%"$package/builds/lib$name.a"))
    $report.install.bundle_archive_missing(name);
}

/* A source package translates in package mode under its staged parent, so
   its public names carry the `<name>__` prefix, then archives. When the
   interfaces translation wrote record a native `meta` prototype of its own,
   it also builds the module an import loads. These are the commands
   `packages/package.mk` runs. */
static void _build_source(String package, String name, String spec) {
  String src = %"$package/src", x2c = x2c_get_executable();
  List units = _source_units(src, name, spec);
  _refuse_native(package, name);
  Path builds = _empty_builds(package);
  List paths =
    %("--x-include-dir" $src "--package-dir" ${Path.dirname(package)});
  _run(%($x2c "translate" "--out-dir" $builds @paths @units), "translate");
  _run(
    %($x2c "build" "--kind" ${TargetKind.of(<static-lib>).spelling}
      "--output" "$builds/lib$name.a"
      "--build-dir" "$builds/cc" @{_files_with(builds, ".c")}
      @{_files_with(src, ".c")}),
    "build");
  if (_native_meta(builds, name))
    _run(
      %($x2c "build" "--kind" ${TargetKind.of(<module>).spelling}
        "--output" "$builds/$name.module"
        "--build-dir" "$builds/module" @paths @units
        @{_files_with(src, ".c")}),
      "module build");
  Path.write_text(%"$builds/$name.native.rsp", NULL);
}

/* The package's x2c units, which include its `src/<name>.x` entry unit. */
static List _source_units(String src, String name, String spec) {
  List units = NULL;
  try units = _files_with(src, ".x").append(_files_with(src, ".xp"));
  catch %(not-found *): {}
  if (!units.contains(%"$src/$name.x") && !units.contains(%"$src/$name.xp"))
    $report.install.entry_missing(spec, name);
  return units;
}

/* A package that needs native dependencies installs only as a bundle. */
static void _refuse_native(String package, String name) {
  foreach (String manifest, _files_with(package, ".json"))
    if (manifest.endswith("dependency.json") ||
        Path.stem(manifest).startswith("dependency-"))
      $report.install.dependencies_missing(name);
}

/* Only what this compiler builds belongs in the installed package, so a
   builds directory the source tree carried is not archived with it. */
static Path _empty_builds(String package) {
  Path builds = %"$package/builds";
  try builds.remove_tree();
  catch %(io-fail *detail): _host_error(detail);
  builds.make_dirs();
  return builds;
}

/* Whether translation recorded a native `meta` prototype that the package
   owns, so an import loads its module. */
static int _native_meta(String builds, String name) {
  String row = %"native-meta \"${name}__";
  return _files_with(builds, ".xi").any(
    %!(String path) => row in Path.read_text(path));
}

// installed packages

/** Returns the version an installed package records, or NULL when no package
    of that name is installed or it records no version. Reaches no network.
*/
String install_version(String name) =>
  _installed_version(%"${_home_packages("install")}/$name");

static String _installed_version(String package) {
  String kind = _installed_kind(package);
  if (!kind) return NULL;
  return _marker_string(
    %"$package/${kind.upper()}.json",
    kind == "bundle" ? "dependency_version" : "version");
}

/* `bundle` or `source` for an installed package, or NULL for a directory
   without an install marker. */
static String _installed_kind(String package) {
  if (Path.exists(%"$package/BUNDLE.json")) return "bundle";
  return Path.exists(%"$package/SOURCE.json") ? "source" : NULL;
}

/* The string `field` of the JSON object at `path`, or NULL when the file is
   absent, is not readable JSON, is not an object, or records no such string.
   A damaged marker refuses its command instead of aborting it. */
static String _marker_string(String path, String field) {
  Var marker = NULL;
  try marker = Json.read_file(path);
  catch: return NULL;
  if (marker is not <map>) return NULL;
  Var value = marker[field];
  return value is <string> ? value : NULL;
}

// the index

/** Returns the package rows of `text`: its lines holding the six fields
    `name version kind platform url sha256`, where `kind` is `source` or
    `bundle` and a source row's platform is `-`. Blank lines, `#` comments,
    and lines with another field count are skipped. The package index and a
    project lockfile share this format.
*/
List install_rows(String text) {
  Array rows = [];
  foreach (String line, text.split_lines(0)) {
    List fields = line.split(" ").filter(%!(String field) => field != NULL);
    if (!line.startswith("#") && fields.len() == 6) rows.push(fields);
  }
  return rows.list_free();
}

/* The index's first bundle row for `name` on this platform, else its last
   source row for `name`. */
static List _index_row(CliRequest request, String name, String work) {
  String location = request.index ? request.index :
    "https://x2c-lang.dev/packages/index.txt";
  String path =
    _remote(location) ? _fetch(location, work, "index.txt") : location;
  String platform = _platform(), text = NULL, List source = NULL;
  try text = Path.read_text(path);
  catch %(not-found *): $report.install.index_missing(location);
  foreach (List row, install_rows(text)) {
    if (row.car() != name) continue;
    String kind = row[2], target = row[3];
    if (kind == "bundle" && target == platform) return row;
    if (kind == "source") source = row;
  }
  if (source) return source;
  $report.install.package_missing(name, platform, location);
  return NULL;
}

// host tools

static String _home_packages(String command) {
  String packages = home_packages();
  if (!packages)
    $report.install.home_missing(command);
  return packages;
}

static String _platform(void) {
  struct utsname host;
  if (uname(&host)) _error("cannot identify the host platform");
  return %"${String.new(host.sysname).lower()}-${String.new(host.machine)}";
}

/* Runs one host tool, or exits with what it wrote to stderr. */
static void _run(List arguments, const char *what) {
  Job job = NULL;
  String errors = NULL;
  try job = arguments.job().options({stderr: <capture>}).start();
  catch %((!or not-found io-fail) *detail): {
    long error = detail.assoc(<"errno">);
    errors = $report.install.start_failed(arguments.car(), error);
  }
  int status = job ? job.status() : 127;
  if (job) errors = job.errors_text;
  if (status)
    $report.install.tool_failed(what, arguments, errors);
}

static int _remote(String spec) =>
  spec.startswith("http://") || spec.startswith("https://") ||
  spec.startswith("file://");

static String _fetch(String url, String directory, String name) {
  String target = %"$directory/$name";
  _run(%("curl" "-fsSL" "-o" $target $url), "download");
  return target;
}

static void _verify(Path p, String expected) {
  File input = $auto(File.open(p, "rb"));
  String actual = input.sha256();
  if (actual != expected.lower())
    $report.install.digest_mismatch(p, expected, actual);
}

/* A tarball unpacks to exactly one top directory, the package. */
static String _unpack(String tarball, String work) {
  Path extracted = %"$work/extracted";
  extracted.make_dirs();
  _run(%("tar" "-xzf" $tarball "-C" $extracted), "extract");
  List top = _entries(extracted);
  if (!top || top.cdr() || !Path.is_dir(%"$extracted/${top.car()}"))
    $report.install.archive_shape(tarball);
  return %"$extracted/${top.car()}";
}

static List _entries(String directory) =>
  Path.list_dir(directory).filter(%!(String name) => !name.startswith("."));

static List _files_with(String directory, String suffix) {
  Array paths = [];
  foreach (String name, _entries(directory))
    if (name.endswith(suffix)) paths.push(%"$directory/$name");
  return paths.list_free();
}

// removing and listing

/** Removes the installed package named by the request's one operand.
    A directory without an install marker is left alone. Returns 0.
*/
int remove_command(CliRequest request) {
  String name = request.inputs.car();
  String target = %"${_home_packages("remove")}/$name";
  if (!name.is_identifier())
    $report.install.remove_missing(name);
  // A removal with nothing to remove refuses without taking the lock, and
  // the same decision is made again under it, since another removal may
  // have taken the package while this one waited.
  _check_removable(target, name);
  _locked_packages("remove", request.quiet);
  defer _release_packages();
  _check_removable(target, name);
  try Path.remove_tree(target);
  catch %(io-fail *detail): _host_error(detail);
  if (!request.quiet) $report.install.removed(target);
  return 0;
}

/* Refuses a removal that has nothing to remove, naming which case it is. */
static void _check_removable(String target, String name) {
  if (!Path.exists(target))
    $report.install.remove_missing(name);
  if (!_installed_kind(target))
    $report.install.remove_unmanaged(target);
}

/** Lists installed packages as `name version kind` lines and returns 0. */
int list_command(CliRequest request) {
  String packages = _home_packages("list");
  foreach (String name, Path.is_dir(packages) ? _entries(packages) : NULL) {
    String package = %"$packages/$name", kind = _installed_kind(package);
    if (!kind) continue;
    String version = _installed_version(package);
    printf("%s %s %s\n", name, version ? version : "-", kind);
  }
  return 0;
}
