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

static Path root;

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

static uint64_t file_digest(Path path) {
  File file = $auto(File.open(path, "rb"));
  unsigned char buffer[1 << 16];
  uint64_t value = 1469598103934665603ULL;
  size_t count;
  while ((count = file.read(buffer, 1, sizeof(buffer))))
    value = fnv64(value, buffer, count);
  return value;
}

static int is_link(Path path) {
  struct stat info;
  return lstat(path, &info) == 0 && S_ISLNK(info.st_mode);
}

/* Spells `path` as a Python `PurePosixPath` does, so printed paths match
   what the Makefile and the installer have always shown. */
static Path normal(Path path) {
  Array parts = [];
  foreach (String part, path.split("/"))
    if (part && part != ".") parts.push(part);
  String joined = parts.len() ? parts.join("/") : NULL;
  if (path.startswith("/")) return joined ? %"/$joined" : %"/";
  return joined ? joined : %".";
}

static void copy(Path source, Path target) {
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

static void copy_support(Path destination, int sources) {
  List rows = %(
    ("lib" ("*.x" "*.xmacro" "*.xlisp") ("lib" "include/x2c"))
    ("builds/0/lib" ("*.h") ("include/x2c"))
    ("builds/0/lib" ("*.xi") ("lib"))
    ("etc" ("*.xlisp" "*.xmacro") ("etc"))
    ("." ("LICENSE") ("licenses")));
  if (sources) rows = %(("src" ("*.x" "*.xmacro") ("src")) @rows);
  foreach (List row, rows) {
    String folder = row.car();
    foreach (Var pattern, row.cadr()) {
      List matches = root.join(folder).join(pattern).glob();
      if (!matches) {
        String message =
          %"no $pattern under $folder; run 'make build' first";
        raise %(not-found (why $message));
      }
      foreach (Path source, matches)
        foreach (Var output, row.caddr())
          copy(source, destination.join(output)
                         .join(source.basename()));
    }
  }
}

static void copy_examples(Path destination) {
  Path examples = root.join("examples");
  foreach (Path source, examples.walk()) {
    String relative = source.remove_prefix(%"$examples/");
    int skipped = 0;
    foreach (String part, relative.split("/"))
      if (%("build" "check.sh" "Makefile" "builds").contains(part))
        skipped = 1;
    if (source.is_file() && !skipped)
      copy(source, destination.join("examples").join(relative));
  }
}

static String write_manifest(Path destination, String name, String kind) {
  Buffer rows = $auto(Buffer.new(0));
  foreach (Path path, destination.walk()) {
    if (!path.is_file()) continue;
    String relative = path.remove_prefix(%"$destination/");
    rows.printf("%s %ld %s\n", hex(file_digest(path)), path.size(),
                relative);
  }
  String body = rows;
  uint64_t digest = fnv64(
    1469598103934665603ULL, (const unsigned char *) body, body.len());
  String identity = %"fnv64-${hex(digest)}";
  destination.join(name).write_text(%"$kind $identity\n$body");
  return identity;
}

static Map owned_files(Path prefix) {
  Map files = {};
  Path manifest = prefix.join(INSTALL_MANIFEST);
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

static Path installed_path(Path prefix, String relative) {
  Path path = prefix.join(relative);
  for (Path parent = path.dirname(); parent != prefix;
       parent = parent.dirname()) {
    if (is_link(parent))
      fail(%"installation directory is a symlink: $parent");
    if (parent == "/") break;
  }
  return path;
}

static Path make_stage(Path parent) {
  Path pattern = parent.join(".x2c-install-XXXXXX");
  char buffer[4096];
  snprintf(buffer, sizeof(buffer), "%s", pattern);
  if (!mkdtemp(buffer)) {
    int error = errno;
    raise %(io-fail (operation "mkdtemp") (path $pattern) (errno $error));
  }
  return String.new(buffer);
}

static void install(Path prefix, Path destdir) {
  if (!prefix.startswith("/"))
    fail("PREFIX must be an absolute dedicated x2c prefix");
  Path target =
    Path.absolute(".").join(destdir ? normal(%"$destdir$prefix") : prefix);
  target.dirname().make_dirs();
  if (is_link(target)) fail(%"installation prefix is a symlink: $target");
  String identity;
  {
    Path stage = make_stage(target.dirname());
    defer stage.remove_tree();
    copy_support(stage, 0);
    copy_examples(stage);
    stage.join("packages").make_dirs();
    stage.join("packages/.keep").write_text(NULL);
    stage.join("bin").make_dirs();
    copy(root.join("builds/0/x2c"), stage.join("bin/x2c"));
    copy(root.join("builds/0/libx2c.a"), stage.join("lib/libx2c.a"));
    stage.join("lib/x2c").make_dirs();
    stage.join("lib/x2c/toolchain").write_text("CC=cc\nAR=ar\n");
    identity = write_manifest(stage, INSTALL_MANIFEST, "x2c-native-v1");
    Map previous = owned_files(target), current = owned_files(stage);
    foreach (String relative,
             sorted_names(previous.copy().merge(current))) {
      Path path = installed_path(target, relative);
      if ((path.exists() || is_link(path)) && !previous.contains(relative))
        fail(%"refusing to replace unowned: $path");
      if (path.is_dir()) fail(%"installed file is a directory: $path");
    }
    target.make_dirs();
    foreach (String relative, sorted_names(current)) {
      if (relative == INSTALL_MANIFEST) continue;
      Path path = installed_path(target, relative);
      path.dirname().make_dirs();
      stage.join(relative).move_to(path);
    }
    foreach (String relative, sorted_names(previous))
      if (!current.contains(relative))
        installed_path(target, relative).remove_file();
    stage.join(INSTALL_MANIFEST).move_to(target.join(INSTALL_MANIFEST));
  }
  printf("x2c: installed %s/bin/x2c (%s)\n", target, identity);
}

static void remove_empty_dirs(Path prefix) {
  Array paths = prefix.walk();
  for (int i = paths.len() - 1; i >= 0; i--) {
    Path path = paths[i];
    if (path.is_dir() && !is_link(path) && !path.list_dir()) rmdir(path);
  }
}

static void uninstall(Path prefix) {
  if (!prefix.startswith("/"))
    fail("PREFIX must be an absolute dedicated x2c prefix");
  if (!prefix.join(INSTALL_MANIFEST).is_file()) {
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

static void support(Path destination, Path licenses) {
  copy_support(destination, 1);
  if (licenses)
    foreach (Path source, licenses.join("LICENSE.*").glob())
      copy(source, destination.join("licenses")
                     .join(%"cosmopolitan-${source.basename()}"));
  printf("%s\n", write_manifest(destination, ".x2c-bootstrap-manifest",
                                "x2c-bootstrap-v1"));
}

root = Path.absolute(argv[0]).dirname().dirname();
String program = Path.basename(argv[0]);
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
    Stderr.printf(
      "%s", Args.usage(row.cdr(), %"$program ${row.car()}"));
  return 2;
}

Map options = NULL;
try options = Args.parse(args.cdr(), spec);
catch %(bad-arg *detail): {
  String why = detail.assoc(<why>), subject = detail[2].cadr();
  Stderr.printf("%sx2c: %s: %s\n", Args.usage(spec, %"$program $command"),
                why, subject);
  return 2;
}

try {
  if (command == "support")
    support(normal(options["destination"]),
            options["licenses"] ? normal(options["licenses"]) : NULL);
  else if (command == "install")
    install(normal(options["prefix"]), options["destdir"]);
  else uninstall(normal(options["prefix"]));
}
catch %(?code *detail): {
  Var why = detail.assoc(<why>);
  if (why is void) Stderr.printf("x2c: %s %s\n", code.str(), detail.repr());
  else Stderr.printf("x2c: %s\n", why.str());
  return 1;
}
