/*  install.x -- Package installation into the x2c home

    Copyright (c) 2026 Gary William Flake.

    `x2c install`, `remove`, and `list` manage `<home>/packages`. Fetching
    and extraction run host tools as child processes. A package is staged in
    a sibling directory, built there when it is source, and published with
    one rename. Installs and removals in one home run one at a time.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "build.x"

#pragma private

#include <stdio.h>
#include <sys/utsname.h>
#include <unistd.h>

#include "digest.x"
#include "json.x"

/* The packages lock this process holds, and the staging directory it is
   filling. `x2c_driver_error` exits without running deferred cleanup, so
   every failing exit below releases both first. */
static int _packages_lock = -1;
static String _staging = NULL;

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
  x2c_driver_error(%"install: $message");
}

static void _host_error(List detail) {
  _release_packages();
  x2c_host_error(detail);
}

// host

static String _home_packages(String command) {
  String packages = x2c_home_packages();
  if (!packages)
    x2c_driver_error(
      %"$command: no x2c home: install the compiler or set X2C_HOME");
  return packages;
}

static String _platform(void) {
  struct utsname host;
  if (uname(&host)) _error("cannot identify the host platform");
  return %"${String.new(host.sysname).lower()}-${String.new(host.machine)}";
}

/* Runs one host tool and returns its stdout, or exits with its stderr. */
static String _run(List arguments, const char *what) {
  String output = NULL, errors = NULL;
  if (!tool_capture(arguments, &output, &errors)) return output;
  _error(%"$what failed (${arguments.car()}): ${errors.strip(" \n")}");
  return NULL;
}

static List _entries(String directory) =>
  Path.list_dir(directory).filter(%!(String name) => !name.startswith("."));

static List _files_with(String directory, String suffix) {
  Array paths = [];
  foreach (String name, _entries(directory))
    if (name.endswith(suffix)) paths.push(%"$directory/$name");
  return paths.list_free();
}

static int _remote(String spec) =>
  spec.startswith("http://") || spec.startswith("https://") ||
  spec.startswith("file://");

// fetch and verify

static String _fetch(String url, String directory, String name) {
  String target = %"$directory/$name";
  _run(%( "curl" "-fsSL" "-o" $target $url ), "download");
  return target;
}

static void _verify(Path p, String expected) {
  File input = $auto(File.open(p, "rb"));
  String actual = input.sha256();
  if (actual != expected.lower())
    _error(%"sha256 mismatch for $p: expected $expected, got $actual");
}

// index

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

static List _index_row(CliRequest request, String name, String work) {
  String location = request.index ? request.index :
    "https://x2c-lang.dev/packages/index.txt";
  String path =
    _remote(location) ? _fetch(location, work, "index.txt") : location;
  String platform = _platform(), text = NULL, List source = NULL;
  try text = Path.read_text(path);
  catch %(not-found *): _error(%"no package index at $location");
  foreach (List row, install_rows(text)) {
    if (row.car() != name) continue;
    String kind = row.nth_cdr(2).car(), target = row.nth_cdr(3).car();
    if (kind == "bundle" && target == platform) return row;
    if (kind == "source") source = row;
  }
  if (source) return source;
  _error(%"no package '$name' for $platform in $location");
  return NULL;
}

// staging

/* A tarball unpacks to exactly one top directory, the package. */
static String _unpack(String tarball, String work) {
  Path extracted = %"$work/extracted";
  extracted.make_dirs();
  _run(%( "tar" "-xzf" $tarball "-C" $extracted ), "extract");
  List top = _entries(extracted);
  if (!top || top.cdr() || !Path.is_dir(%"$extracted/${top.car()}"))
    _error(%"$tarball must contain one package directory");
  return %"$extracted/${top.car()}";
}

/* The string `field` of the JSON object at `path`, or NULL when the file is
   absent, is not readable JSON, is not an object, or records no such string.
   A damaged marker refuses its command instead of aborting it. */
static String _marker_string(String path, String field) {
  Var marker = NULL;
  try marker = Json.read_file(path);
  catch: return NULL;
  if (!(marker is <map>)) return NULL;
  Var value = marker[field];
  return value is <string> ? value : NULL;
}

static void _check_bundle(CliRequest request, String package, String name) {
  String built = _marker_string(%"$package/BUNDLE.json", "x2c_version");
  String current = cli_version();
  if (!built) _error(%"bundle $name has no readable BUNDLE.json version");
  if (built != current && !request.force)
    _error(
      %"bundle $name was built for '$built', not '$current'; use --force");
  if (!Path.is_file(%"$package/builds/lib$name.a"))
    _error(%"bundle $name has no builds/lib$name.a");
}

/* A source package translates in package mode under its staged parent, so
   its public names carry the `<name>__` prefix, then archives. It is the
   same pair of commands `packages/package.mk` runs. */
static void _build_source(String package, String name, String spec) {
  List units = NULL;
  try units = _files_with(%"$package/src", ".x")
    .append(_files_with(%"$package/src", ".xp"));
  catch %(not-found *): {}
  if (!units.contains(%"$package/src/$name.x") &&
      !units.contains(%"$package/src/$name.xp"))
    _error(%"$spec has no src/$name.x entry unit");
  foreach (String manifest, _files_with(package, ".json"))
    if (manifest.endswith("dependency.json") ||
        Path.stem(manifest).startswith("dependency-"))
      _error(%"$name needs native dependencies; install its bundle");
  // Only what this compiler builds belongs in the installed package, so a
  // builds directory the source tree carried is not archived with it.
  Path builds = %"$package/builds", String x2c = x2c_get_executable();
  try builds.remove_tree();
  catch %(io-fail *detail): _host_error(detail);
  builds.make_dirs();
  _run(%( $x2c "translate" "--out-dir" $builds
          "--x-include-dir" "$package/src"
          "--package-dir" ${Path.dirname(package)} )
         .append(units), "translate");
  List inputs = _files_with(builds, ".c")
    .append(_files_with(%"$package/src", ".c"));
  _run(%( $x2c "build" "--kind" "static-library"
          "--output" "$builds/lib$name.a"
          "--build-dir" "$builds/cc" ).append(inputs), "build");
  Path.write_text(%"$builds/$name.native.rsp", NULL);
}

/* `bundle` or `source` for an installed package, or NULL for a directory
   without an install marker. */
static String _installed_kind(String package) =>
  Path.exists(%"$package/BUNDLE.json") ? "bundle" :
  Path.exists(%"$package/SOURCE.json") ? "source" : NULL;

/* The version an installed package's marker records, or NULL. */
static String _installed_version(String package) {
  String kind = _installed_kind(package);
  if (!kind) return NULL;
  return _marker_string(
    %"$package/${kind.upper()}.json",
    kind == "bundle" ? "dependency_version" : "version");
}

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
      fprintf(
        stderr, "x2c: waiting for another install or removal in %s\n",
        packages);
    held = file_lock(lock, 1);
  }
  _packages_lock = held;
  return packages;
}

/* Publishes the staged package with one rename, replacing an installed
   package of the same name; a directory that is not an installed package is
   never replaced. The replaced package moves aside inside the work
   directory, which the caller removes. */
static void _publish(String staged, String packages, String name) {
  Path target = %"$packages/$name";
  if (target.exists()) {
    if (!_installed_kind(target))
      _error(%"$target exists and is not an installed package");
    target.move_to(%"$staged.previous");
  }
  Path.move_to(staged, target);
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

/* Stages, builds, and publishes one package. `source` is a local directory
   or tarball, or NULL when `url` names the archive to fetch. */
static String _install(
  CliRequest request, String spec, String source, String url, String sha256,
  String version, String packages, String work) {
  if (url) {
    source = _fetch(url, work, "package.tar.gz");
    _verify(source, sha256);
  }
  else if (sha256 && !Path.is_dir(source)) _verify(source, sha256);
  String package = Path.is_dir(source) ? source : _unpack(source, work);
  String name = Path.basename(package);
  if (!name.is_identifier()) _error(%"'$name' is not a package name");
  String staged = %"$work/$name";
  try Path.copy_tree(package, staged);
  catch %(io-fail *detail): _host_error(detail);
  if (Path.exists(%"$staged/BUNDLE.json"))
    _check_bundle(request, staged, name);
  else {
    _build_source(staged, name, spec);
    // A local path carries no version of its own. The package it replaces
    // recorded one, and a project pin matches a name and a version, so
    // dropping it would send the next build back to the index.
    if (!version) version = _installed_version(%"$packages/$name");
    Map record = {
      "package": name, "source": url ? url : Path.absolute(spec),
      "x2c_version": cli_version()
    };
    if (version) record["version"] = version;
    if (sha256) record["sha256"] = sha256;
    Path.write_text(%"$staged/SOURCE.json", %"${Var.pretty_json(record)}\n");
  }
  _publish(staged, packages, name);
  if (!request.quiet)
    fprintf(stderr, "x2c: installed %s/%s\n", packages, name);
  return name;
}

/** Installs the package named by the request's one operand and returns 0.
    The operand is a local directory, a local `.tar.gz`, a URL with
    `--sha256`, or a name resolved through the package index. A bundle is
    verified against this compiler's version unless `--force`; a pure-x2c
    source package is built by this compiler. Failures exit with status 2.
*/
int install_command(CliRequest request) {
  String spec = request.inputs.car();
  String packages = _locked_packages("install", request.quiet);
  Path work = _work_directory(packages);
  defer _release_packages();
  String source = NULL, sha256 = request.sha256, version = NULL, url = NULL;
  if (_remote(spec)) {
    if (!sha256) _error("a URL needs --sha256 <hex>");
    url = spec;
  }
  else if (Path.exists(spec)) source = spec;
  else if (spec.is_identifier()) {
    List row = _index_row(request, spec, work);
    version = row.nth_cdr(1).car();
    url = row.nth_cdr(4).car();
    sha256 = row.nth_cdr(5).car();
  }
  else _error(%"unknown package spec '$spec'");
  (void) _install(
    request, spec, source, url, sha256, version, packages, work);
  return 0;
}

/** Returns the version an installed package records, or NULL when no package
    of that name is installed or it records no version. Reaches no network.
*/
String install_version(String name) =>
  _installed_version(%"${_home_packages("install")}/$name");

/** Returns the row that records `name` at `version`, installing the package
    under the x2c home first unless one already records that version.
    `locked` is the lockfile row to reproduce, so a package a lockfile pins
    comes from the archive that lockfile recorded; NULL resolves the index
    instead. The row has the `install_rows` shape, and an already satisfied
    dependency reaches no network. Failures exit with status 2.
*/
List install_require(
  CliRequest request, String name, String version, List locked) {
  String packages = _locked_packages("install", request.quiet);
  Path work = _work_directory(packages);
  defer _release_packages();
  List row = locked ? locked : _index_row(request, name, work);
  String resolved = row.nth_cdr(1).car();
  if (resolved != version)
    _error(%"the index has $name $resolved, not the pinned $version");
  if (_installed_version(%"$packages/$name") != version)
    (void) _install(
      request, name, NULL, row.nth_cdr(4).car(), row.nth_cdr(5).car(),
      resolved, packages, work);
  return row;
}

/* Refuses a removal that has nothing to remove, naming which case it is. */
static void _check_removable(String target, String name) {
  if (!Path.exists(target))
    x2c_driver_error(%"remove: no installed package '$name'");
  if (!_installed_kind(target))
    x2c_driver_error(
      %"remove: $target is not an installed package; remove it by hand");
}

/** Removes the installed package named by the request's one operand.
    A directory without an install marker is left alone. Returns 0.
*/
int remove_command(CliRequest request) {
  String name = request.inputs.car();
  String target = %"${_home_packages("remove")}/$name";
  if (!name.is_identifier())
    x2c_driver_error(%"remove: no installed package '$name'");
  // A removal with nothing to remove refuses without taking the lock, and
  // the same decision is made again under it, since another removal may
  // have taken the package while this one waited.
  _check_removable(target, name);
  _locked_packages("remove", request.quiet);
  defer _release_packages();
  _check_removable(target, name);
  try Path.remove_tree(target);
  catch %(io-fail *detail): _host_error(detail);
  if (!request.quiet) fprintf(stderr, "x2c: removed %s\n", target);
  return 0;
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
