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

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include "digest.x"

#define INSTALL_INDEX "https://x2c-lang.dev/packages/index.txt"

static void _error(const char *message) {
  x2c_driver_error(%"install: $message");
}

// host

static String _home_packages(void) {
  String home = x2c_get_root();
  if (!home || home == ".")
    _error("no x2c home: install the compiler or set X2C_HOME");
  String packages = %"$home/packages";
  if (!_build_mkdirs(packages)) _error(%"cannot create $packages");
  return packages;
}

static String _platform(void) {
  struct utsname host;
  if (uname(&host)) _error("cannot identify the host platform");
  return %"${String.new(host.sysname).lower()}-${String.new(host.machine)}";
}

/* Runs one host tool and returns its stdout, or exits with its stderr. */
static String _run(List arguments, const char *what) {
  String tool = arguments.car(), errors = "not found";
  try {
    Job job = arguments.options(%{stdout: capture, stderr: capture}).start();
    if (!job.wait()) return job.output();
    errors = job.errors();
  }
  catch %(not-found *): {}
  _error(%"$what failed ($tool): ${errors ? errors.strip(" \n") : %""}");
  return NULL;
}

static String _read_text(String path) {
  File input = fopen(path, "r");
  if (!input) _error(%"cannot read $path");
  return input.string_close();
}

static void _write_text(String path, String text) {
  File output = fopen(path, "w");
  if (!output || (text && output.printf("%s", text.str()) < 0) ||
      output.close())
    _error(%"cannot write $path");
}

static List _entries(String directory) =>
  directory.list_dir().filter(%!(name) => !name.str().startswith("."));

static List _files_with(String directory, String suffix) {
  Array paths = %[];
  foreach (String name, _entries(directory))
    if (name.endswith(suffix)) paths.push(%"$directory/$name");
  return paths.list_free();
}

// fetch and verify

static String _fetch(String url, String directory, String name) {
  String target = %"$directory/$name";
  _run(%( "curl" "-fsSL" "-o" $target $url ), "download");
  return target;
}

static void _verify(String path, String expected) {
  File input = fopen(path, "rb");
  if (!input) _error(%"cannot read $path");
  defer input.close();
  String actual = input.sha256();
  if (actual != expected.lower())
    _error(%"sha256 mismatch for $path: expected $expected, got $actual");
}

// index

/* One index line is `name version kind platform url sha256`; `kind` is
   `source` or `bundle`, and a source row's platform is `-`. */
static List _index_row(CliRequest request, String name, String work) {
  String location = request.index ? request.index : String.new(INSTALL_INDEX);
  String path = location.startswith("http://") ||
                location.startswith("https://") ||
                location.startswith("file://")
    ? _fetch(location, work, "index.txt") : location;
  String platform = _platform(), List source = NULL;
  foreach (String line, _read_text(path).split_lines(0)) {
    if (!line || line.startswith("#")) continue;
    Array fields = %[];
    foreach (String field, line.split(" "))
      if (field) fields.push(field);
    if (fields.len() != 6 || fields[0] != name) continue;
    String kind = fields[2], target = fields[3];
    if (kind == "bundle" && target == platform) return fields.list_free();
    if (kind == "source") source = fields.list_free();
  }
  if (source) return source;
  _error(%"no package '$name' for $platform in $location");
  return NULL;
}

// staging

/* A tarball unpacks to exactly one top directory, the package. */
static String _unpack(String tarball, String work) {
  String extracted = %"$work/extracted";
  if (!_build_mkdirs(extracted)) _error(%"cannot create $extracted");
  _run(%( "tar" "-xzf" $tarball "-C" $extracted ), "extract");
  List top = _entries(extracted);
  if (!top || top.cdr() || !%"$extracted/${top.car()}".is_dir())
    _error(%"$tarball must contain one package directory");
  return %"$extracted/${top.car()}";
}

static void _copy_tree(String source, String target) {
  try source.copy_tree(target);
  catch %(not-found *): _error(%"cannot copy $source");
  catch %(io-fail *): _error(%"cannot copy $source");
}

static String _json_field(String text, const char *key) {
  String marker = %"\"$key\": \"";
  int start = text.find(marker);
  if (start < 0) return NULL;
  String rest = text[start + marker.len():];
  int end = rest.find("\"");
  return end < 0 ? NULL : rest[:end];
}

static void _check_bundle(CliRequest request, String package, String name) {
  String text = _read_text(%"$package/BUNDLE.json");
  String built = _json_field(text, "x2c_version"), current = cli_version();
  if (built != current && !request.force)
    _error(
      %"bundle $name was built for '$built', not '$current'; use --force");
  if (access(%"$package/builds/lib$name.a", R_OK))
    _error(%"bundle $name has no builds/lib$name.a");
}

/* A source package translates in package mode under its staged parent, so
   its public names carry the `<name>__` prefix, then archives. It is the
   same pair of commands `packages/package.mk` runs. */
static void _build_source(String package, String name, String spec) {
  List units = _files_with(%"$package/src", ".x");
  if (!units.contains(%"$package/src/$name.x"))
    _error(%"$spec has no src/$name.x entry unit");
  foreach (String manifest, _files_with(package, ".json"))
    if (manifest.endswith("dependency.json") ||
        manifest.stem().startswith("dependency-"))
      _error(%"$name needs native dependencies; install its bundle");
  String builds = %"$package/builds", x2c = x2c_get_executable();
  if (!_build_mkdirs(builds)) _error(%"cannot create $builds");
  _run(%( $x2c "translate" "--out-dir" $builds
          "--x-include-dir" ${%"$package/src"}
          "--package-dir" ${package.dirname()} )
         .append(units), "translate");
  List inputs = _files_with(builds, ".c")
    .append(_files_with(%"$package/src", ".c"));
  _run(%( $x2c "build" "--kind" "static-library"
          "--output" ${%"$builds/lib$name.a"}
          "--build-dir" ${%"$builds/cc"} ).append(inputs), "build");
  _write_text(%"$builds/$name.link", %"");
}

static int _installed(String package) =>
  !access(%"$package/BUNDLE.json", F_OK) ||
  !access(%"$package/SOURCE.json", F_OK);

/* The version an installed package records, or NULL when it is not one. */
static String _installed_version(String package) {
  String marker = %"$package/BUNDLE.json", key = "dependency_version";
  if (access(marker, F_OK)) {
    marker = %"$package/SOURCE.json";
    key = "version";
  }
  if (access(marker, F_OK)) return NULL;
  String version = _json_field(_read_text(marker), key);
  return version ? version : %"";
}

/* Returns the home's packages directory, holding its lock until the process
   exits, so another install or removal waits for this one to finish and,
   unless `quiet`, says so. */
static String _locked_packages(int quiet) {
  static int locked = 0;
  String packages = _home_packages(), lock = %"$packages/.lock";
  if (locked) return packages;
  if (_build_lock(lock, 0) < 0) {
    if (!quiet)
      fprintf(
        stderr, "x2c: waiting for another install or removal in %s\n",
        packages.str());
    _build_lock(lock, 1);
  }
  locked = 1;
  return packages;
}

/* Publishes the staged package with one rename, replacing an installed
   package of the same name; a directory that is not an installed package is
   never replaced. The replaced package moves aside inside the work
   directory. */
static void _publish(String staged, String packages, String name) {
  String target = %"$packages/$name", previous = %"$staged.previous";
  if (!access(target, F_OK)) {
    if (!_installed(target))
      _error(%"$target exists and is not an installed package");
    if (rename(target, previous)) _error(%"cannot replace $target");
  }
  if (rename(staged, target)) _error(%"cannot publish $target");
  _build_remove_tree(previous);
}

/* Staging directories left by an interrupted install are removed first; the
   caller holds the packages lock, so none belongs to a running install. */
static String _work_directory(String packages) {
  foreach (String name, packages.list_dir())
    if (name.startswith(".install.")) _build_remove_tree(%"$packages/$name");
  String work = %"$packages/.install.%ld".printf((long) getpid());
  if (!_build_mkdirs(work)) _error(%"cannot create $work");
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
  else if (sha256 && !source.is_dir()) _verify(source, sha256);
  String package = source.is_dir() ? source : _unpack(source, work);
  String name = package.split("/").last();
  if (!name.is_identifier()) _error(%"'$name' is not a package name");
  String staged = %"$work/$name";
  _copy_tree(package, staged);
  if (!access(%"$staged/BUNDLE.json", F_OK))
    _check_bundle(request, staged, name);
  else {
    _build_source(staged, name, spec);
    String origin = url ? url : spec, digest = sha256 ? sha256 : %"";
    String label = version ? version : %"";
    _write_text(%"$staged/SOURCE.json", %"{
  \"package\": \"$name\",
  \"version\": \"$label\",
  \"source\": \"$origin\",
  \"sha256\": \"$digest\",
  \"x2c_version\": \"${cli_version()}\"
}
");
  }
  _publish(staged, packages, name);
  if (!request.quiet)
    printf("x2c: installed %s/%s\n", packages.str(), name.str());
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
  String packages = _locked_packages(request.quiet);
  String work = _work_directory(packages);
  String source = NULL, sha256 = request.sha256, version = NULL, url = NULL;
  int remote = spec.startswith("http://") || spec.startswith("https://") ||
               spec.startswith("file://");
  if (remote) {
    if (!sha256) _error("a URL needs --sha256 <hex>");
    url = spec;
  }
  else if (!access(spec, F_OK)) source = spec;
  else if (spec.is_identifier()) {
    List row = _index_row(request, spec, work);
    version = row.nth_cdr(1).car();
    url = row.nth_cdr(4).car();
    sha256 = row.nth_cdr(5).car();
  }
  else _error(%"unknown package spec '$spec'");
  (void) _install(
    request, spec, source, url, sha256, version, packages, work);
  _build_remove_tree(work);
  return 0;
}

/** Returns the version an installed package records, or NULL when no package
    of that name is installed. A package installed without a recorded version
    returns the empty string. Reaches no network.
*/
String install_version(String name) =>
  _installed_version(%"${_home_packages()}/$name");

/** Returns the index row for `name`, installing it under the x2c home first
    unless an installed package already records `version`. The row is
    `name version kind platform url sha256`, the same shape the package index
    and a project lockfile hold. An already satisfied dependency reaches no
    network. Failures exit with status 2.
*/
List install_require(CliRequest request, String name, String version) {
  String packages = _locked_packages(request.quiet);
  String work = _work_directory(packages);
  List row = _index_row(request, name, work);
  String resolved = row.nth_cdr(1).car();
  if (resolved != version)
    _error(%"the index has $name $resolved, not the pinned $version");
  if (_installed_version(%"$packages/$name") != version)
    (void) _install(
      request, name, NULL, row.nth_cdr(4).car(), row.nth_cdr(5).car(),
      resolved, packages, work);
  _build_remove_tree(work);
  return row;
}

/** Removes the installed package named by the request's one operand.
    A directory without an install marker is left alone. Returns 0.
*/
int remove_command(CliRequest request) {
  String name = request.inputs.car();
  String packages = _locked_packages(request.quiet);
  String target = %"$packages/$name";
  if (!name.is_identifier() || access(target, F_OK))
    _error(%"no installed package '$name'");
  if (!_installed(target))
    _error(%"$target is not an installed package; remove it by hand");
  if (!_build_remove_tree(target)) _error(%"cannot remove $target");
  if (!request.quiet) printf("x2c: removed %s\n", target.str());
  return 0;
}

/** Lists installed packages as `name version kind` lines and returns 0. */
int list_command(CliRequest request) {
  String packages = _home_packages();
  foreach (String name, _entries(packages)) {
    String package = %"$packages/$name";
    if (!_installed(package)) continue;
    String bundle = %"$package/BUNDLE.json", kind = "bundle";
    if (access(bundle, F_OK)) {
      bundle = %"$package/SOURCE.json";
      kind = "source";
    }
    String text = _read_text(bundle);
    String version = _json_field(
      text, kind == "bundle" ? "dependency_version" : "version");
    printf("%s %s %s\n", name.str(), version ? version.str() : "-", kind);
  }
  return 0;
}
