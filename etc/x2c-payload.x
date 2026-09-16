#!/usr/bin/env -S x2c script
/*  x2c-payload.x -- materialize compiler support; install or remove a
    native dedicated prefix

    An installed prefix is an x2c home: bin, include, lib, etc, packages,
    examples, and licenses. The APE support payload also carries src so the
    bootstrap can rebuild the compiler; an application install does not.
    Copies keep their source's permission bits and times, and each tree is
    inventoried in a manifest of FNV-1a digests.
*/
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static String INSTALL_MANIFEST = ".x2c-install-manifest";

static String root;

static void fail(String message) {
  raise %(bad-arg (why $message));
}

static uint64_t fnv64(uint64_t value, const unsigned char *bytes, size_t n) {
  for (size_t i = 0; i < n; i++)
    value = (value ^ bytes[i]) * 1099511628211ULL;
  return value;
}

static String hex(uint64_t value) =>
  %"%016llx".printf((unsigned long long) value);

static uint64_t file_digest(String path) {
  File file = $auto(File.open(path, "rb"));
  unsigned char buffer[1 << 16];
  uint64_t value = 1469598103934665603ULL;
  size_t count;
  while ((count = file.read(buffer, 1, sizeof(buffer))))
    value = fnv64(value, buffer, count);
  return value;
}

static int is_link(String path) {
  struct stat info;
  return lstat(path, &info) == 0 && S_ISLNK(info.st_mode);
}

/* Spells `path` as a Python `PurePosixPath` does, so printed paths match
   what the Makefile and the installer have always shown. */
static String normal(String path) {
  Array parts = %[];
  foreach (String part, path.split("/"))
    if (part && part != ".") parts.push(part);
  String joined = parts.len() ? parts.join("/") : NULL;
  if (path.startswith("/")) return joined ? %"/$joined" : %"/";
  return joined ? joined : %".";
}

static String absolute(String path) {
  if (path.startswith("/")) return path;
  char buffer[4096];
  if (!getcwd(buffer, sizeof(buffer))) {
    int error = errno;
    raise %(io-fail (operation "getcwd") (errno $error));
  }
  return String.new(buffer).join_path(path);
}

static void copy(String source, String target) {
  target.dirname().make_dirs();
  source.copy_file(target);
  struct stat info;
  if (stat(source, &info)) return;
#ifdef __APPLE__
  struct timespec times[2] = { info.st_atimespec, info.st_mtimespec };
#else
  struct timespec times[2] = { info.st_atim, info.st_mtim };
#endif
  utimensat(AT_FDCWD, target, times, 0);
}

static void copy_support(String destination, int sources) {
  List rows = %(
    ("lib" ("*.x" "*.xmacro" "*.xlisp") ("lib" "include/x2c"))
    ("builds/0/lib" ("*.h") ("include/x2c"))
    ("builds/0/lib" ("*.xi") ("lib"))
    ("etc" ("*.xlisp" "*.xmacro") ("etc"))
    ("." ("LICENSE") ("licenses")));
  if (sources) rows = %(("src" ("*.x" "*.xmacro") ("src")) @rows);
  foreach (List row, rows) {
    String folder = row.car().str();
    foreach (Var pattern, row.cadr()) {
      List matches = root.join_path(folder).join_path(pattern.str()).glob();
      if (!matches) {
        String message =
          %"no ${pattern.str()} under $folder; run 'make build' first";
        raise %(not-found (why $message));
      }
      foreach (String source, matches)
        foreach (Var output, row.caddr())
          copy(source, destination.join_path(output.str())
                         .join_path(source.basename()));
    }
  }
}

static void copy_examples(String destination) {
  String examples = root.join_path("examples");
  foreach (String source, examples.walk()) {
    String relative = source[examples.len() + 1:];
    int skipped = 0;
    foreach (String part, relative.split("/"))
      if (%("build" "check.sh" "Makefile" "builds").contains(part))
        skipped = 1;
    if (source.is_file() && !skipped)
      copy(source, destination.join_path("examples").join_path(relative));
  }
}

static String write_manifest(String destination, String name, String kind) {
  Buffer rows = $auto(Buffer.new(0));
  foreach (String path, destination.walk()) {
    if (!path.is_file()) continue;
    String relative = path[destination.len() + 1:];
    rows.printf("%s %ld %s\n", hex(file_digest(path)), path.file_size(),
                relative);
  }
  String body = rows.str();
  uint64_t digest = fnv64(
    1469598103934665603ULL, (const unsigned char *) body, body.len());
  String identity = %"fnv64-${hex(digest)}";
  destination.join_path(name).write_text(%"$kind $identity\n$body");
  return identity;
}

static Map owned_files(String prefix) {
  Map files = %{};
  String manifest = prefix.join_path(INSTALL_MANIFEST);
  if (!manifest.exists()) return files;
  List lines = manifest.read_text().split_lines(0);
  if (!lines || !lines.car().str().startswith("x2c-native-v1 "))
    fail(%"unrecognized installation inventory: $manifest");
  foreach (String line, lines.cdr()) {
    int first = line.find(" ");
    int second = first < 0 ? -1 : line[first + 1:].find(" ");
    if (second < 0) fail(%"invalid installation inventory row: $line");
    String relative = line[first + second + 2:];
    if (relative.startswith("/") || relative.split("/").contains(%".."))
      fail(%"invalid installed file path: $relative");
    files[relative] = 1;
  }
  files[INSTALL_MANIFEST] = 1;
  return files;
}

static Array sorted_names(Map files) => files.keys().array().sort();

static String installed_path(String prefix, String relative) {
  String path = prefix.join_path(relative);
  for (String parent = path.dirname(); parent != prefix;
       parent = parent.dirname()) {
    if (is_link(parent))
      fail(%"installation directory is a symlink: $parent");
    if (parent == "/") break;
  }
  return path;
}

static String make_stage(String parent) {
  String pattern = parent.join_path(".x2c-install-XXXXXX");
  char buffer[4096];
  snprintf(buffer, sizeof(buffer), "%s", pattern);
  if (!mkdtemp(buffer)) {
    int error = errno;
    raise %(io-fail (operation "mkdtemp") (path $pattern) (errno $error));
  }
  return String.new(buffer);
}

static void install(String prefix, String destdir) {
  if (!prefix.startswith("/"))
    fail("PREFIX must be an absolute dedicated x2c prefix");
  String target = absolute(destdir ? normal(%"$destdir$prefix") : prefix);
  target.dirname().make_dirs();
  if (is_link(target)) fail(%"installation prefix is a symlink: $target");
  String identity;
  {
    String stage = make_stage(target.dirname());
    defer stage.remove_tree();
    copy_support(stage, 0);
    copy_examples(stage);
    stage.join_path("packages").make_dirs();
    stage.join_path("packages/.keep").write_text(NULL);
    stage.join_path("bin").make_dirs();
    copy(root.join_path("builds/0/x2c"), stage.join_path("bin/x2c"));
    copy(root.join_path("builds/0/libx2c.a"), stage.join_path("lib/libx2c.a"));
    stage.join_path("lib/x2c").make_dirs();
    stage.join_path("lib/x2c/toolchain").write_text("CC=cc\nAR=ar\n");
    identity = write_manifest(stage, INSTALL_MANIFEST, "x2c-native-v1");
    Map previous = owned_files(target), current = owned_files(stage);
    foreach (String relative,
             sorted_names(previous.copy().merge(current))) {
      String path = installed_path(target, relative);
      if ((path.exists() || is_link(path)) && !previous.contains(relative))
        fail(%"refusing to replace unowned: $path");
      if (path.is_dir()) fail(%"installed file is a directory: $path");
    }
    target.make_dirs();
    foreach (String relative, sorted_names(current)) {
      if (relative == INSTALL_MANIFEST) continue;
      String path = installed_path(target, relative);
      path.dirname().make_dirs();
      stage.join_path(relative).move_to(path);
    }
    foreach (String relative, sorted_names(previous))
      if (!current.contains(relative))
        installed_path(target, relative).remove_file();
    stage.join_path(INSTALL_MANIFEST)
      .move_to(target.join_path(INSTALL_MANIFEST));
  }
  printf("x2c: installed %s/bin/x2c (%s)\n", target, identity);
}

static void remove_empty_dirs(String prefix) {
  Array paths = prefix.walk().array();
  for (int i = paths.len() - 1; i >= 0; i--) {
    String path = paths[i];
    if (path.is_dir() && !is_link(path) && !path.list_dir()) rmdir(path);
  }
}

static void uninstall(String prefix) {
  if (!prefix.startswith("/"))
    fail("PREFIX must be an absolute dedicated x2c prefix");
  if (!prefix.join_path(INSTALL_MANIFEST).is_file()) {
    String message = %"no x2c installation at $prefix";
    raise %(not-found (why $message));
  }
  foreach (String relative, sorted_names(owned_files(prefix)))
    installed_path(prefix, relative).remove_file();
  remove_empty_dirs(prefix);
  if (!prefix.list_dir()) {
    rmdir(prefix);
    printf("x2c: removed %s\n", prefix);
  }
  else printf("x2c: removed the compiler; %s keeps unowned files\n", prefix);
}

static void support(String destination, String licenses) {
  copy_support(destination, 1);
  if (licenses)
    foreach (String source, licenses.join_path("LICENSE.*").glob())
      copy(source, destination.join_path("licenses")
                     .join_path(%"cosmopolitan-${source.basename()}"));
  printf("%s\n", write_manifest(destination, ".x2c-bootstrap-manifest",
                                "x2c-bootstrap-v1"));
}

root = String.new(argv[0]).absolute_path().dirname().dirname();
String program = String.new(argv[0]).basename();
List commands = %(
  (support (destination required) (--licenses (value dir)))
  (install (--prefix (value path) required) (--destdir (value dir)))
  (uninstall (--prefix (value path) required)));
String command = args ? args.car().str() : NULL;
List spec = NULL;
foreach (List row, commands)
  if (row.car().str() == command) spec = row.cdr();
if (!spec) {
  foreach (List row, commands)
    Stderr.printf("%s", row.cdr().usage(%"$program ${row.car().str()}"));
  return 2;
}

Map options = NULL;
try options = args.cdr().parse_args(spec);
catch %(bad-arg *detail): {
  String why = detail.assoc(<why>).str(), subject = detail[2].cadr().str();
  Stderr.printf("%sx2c: %s: %s\n", spec.usage(%"$program $command"), why,
                subject);
  return 2;
}

try {
  if (command == "support")
    support(normal(options["destination"].str()),
            options["licenses"] ? normal(options["licenses"].str()) : NULL);
  else if (command == "install")
    install(normal(options["prefix"].str()), options["destdir"].str());
  else uninstall(normal(options["prefix"].str()));
}
catch %(?code *detail): {
  Var why = detail.assoc(<why>);
  if (why is void) Stderr.printf("x2c: %s %s\n", code.str(), detail.repr());
  else Stderr.printf("x2c: %s\n", why.str());
  return 1;
}
