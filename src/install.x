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

static void _error(const char *message) {
  x2c_driver_error(%"install: $message");
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

static void _check_bundle(CliRequest request, String package, String name) {
  String built = Json.read_file(%"$package/BUNDLE.json")["x2c_version"];
  String current = cli_version();
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
  List units = _files_with(%"$package/src", ".x");
  if (!units.contains(%"$package/src/$name.x"))
    _error(%"$spec has no src/$name.x entry unit");
  foreach (String manifest, _files_with(package, ".json"))
    if (manifest.endswith("dependency.json") ||
        Path.stem(manifest).startswith("dependency-"))
      _error(%"$name needs native dependencies; install its bundle");
  Path builds = %"$package/builds", String x2c = x2c_get_executable();
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
  Var marker = Json.read_file(%"$package/${kind.upper()}.json");
  Var version = marker[kind == "bundle" ? "dependency_version" : "version"];
  return version is <string> ? version : NULL;
}

/* Returns the home's packages directory, created and locked until the
   process exits, so another install or removal waits for this one to finish
   and, unless `quiet`, says so. */
static String _locked_packages(String command, int quiet) {
  static int locked = 0;
  Path packages = _home_packages(command), lock = %"$packages/.lock";
  if (locked) return packages;
  try packages.make_dirs();
  catch %(io-fail *detail): x2c_host_error(detail);
  if (file_lock(lock, 0) < 0) {
    if (!quiet)
      fprintf(
        stderr, "x2c: waiting for another install or removal in %s\n",
        packages);
    file_lock(lock, 1);
  }
  locked = 1;
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
  catch %(io-fail *detail): x2c_host_error(detail);
  if (Path.exists(%"$staged/BUNDLE.json"))
    _check_bundle(request, staged, name);
  else {
    _build_source(staged, name, spec);
    Map record = {
      "package": name, "version": version, "source": url ? url : spec,
      "sha256": sha256, "x2c_version": cli_version()
    };
    Path.write_text(%"$staged/SOURCE.json", %"${Var.pretty_json(record)}\n");
  }
  _publish(staged, packages, name);
  if (!request.quiet) printf("x2c: installed %s/%s\n", packages, name);
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
  defer work.remove_tree();
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

/** Returns the index row for `name`, installing it under the x2c home first
    unless an installed package already records `version`. The row has the
    `install_rows` shape. An already satisfied dependency reaches no network.
    Failures exit with status 2.
*/
List install_require(CliRequest request, String name, String version) {
  String packages = _locked_packages("install", request.quiet);
  Path work = _work_directory(packages);
  defer work.remove_tree();
  List row = _index_row(request, name, work);
  String resolved = row.nth_cdr(1).car();
  if (resolved != version)
    _error(%"the index has $name $resolved, not the pinned $version");
  if (_installed_version(%"$packages/$name") != version)
    (void) _install(
      request, name, NULL, row.nth_cdr(4).car(), row.nth_cdr(5).car(),
      resolved, packages, work);
  return row;
}

/** Removes the installed package named by the request's one operand.
    A directory without an install marker is left alone. Returns 0.
*/
int remove_command(CliRequest request) {
  String name = request.inputs.car();
  String target = %"${_home_packages("remove")}/$name";
  if (!name.is_identifier() || !Path.exists(target))
    x2c_driver_error(%"remove: no installed package '$name'");
  if (!_installed_kind(target))
    x2c_driver_error(
      %"remove: $target is not an installed package; remove it by hand");
  _locked_packages("remove", request.quiet);
  try Path.remove_tree(target);
  catch %(io-fail *detail): x2c_host_error(detail);
  if (!request.quiet) printf("x2c: removed %s\n", target);
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
