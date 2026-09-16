#!/usr/bin/env -S x2c script
/*  gen-package-index.x -- write the index `x2c install <name>` resolves

    Each row is `name version kind platform url sha256`. Source rows come from
    pure-x2c packages (a `src/<name>.x` tree with no dependency manifest);
    bundle rows come from `<name>-native.tar.gz` files named on the command
    line, one per platform, tagged by their BUNDLE.json and copied beside the
    index as `<name>-<platform>-native.tar.gz`. URLs are `<base>/<file>`.
    The system `tar` makes and reads the archives, as `x2c install` does.
*/
#include "json.x"

static String root;

/* Spells `path` as Python's `PurePosixPath` does, so the printed index path
   matches the tool this replaced. */
static String normal(String path) {
  Array parts = %[];
  foreach (String part, path.split("/"))
    if (part && part != ".") parts.push(part);
  String joined = parts.len() ? parts.join("/") : NULL;
  if (path.startswith("/")) return joined ? %"/$joined" : %"/";
  return joined ? joined : %".";
}

static String digest(String path) {
  File file = $auto(File.open(path, "rb"));
  return file.sha256();
}

/* The walk visits parents first and siblings in sorted order, and each member
   is archived without recursion, so the archive lists exactly this walk less
   build products and prepared dependencies at any depth. */
static String source_archive(String package, String output) {
  String name = package.basename();
  String archive = output.absolute_path().join_path(%"$name-source.tar.gz");
  Array members = %[];
  foreach (String path, package.walk()) {
    String relative = path[package.len() + 1:];
    List parts = relative.split("/");
    if (!parts.contains("builds") && !parts.contains("deps"))
      members.push(%"$name/$relative");
  }
  // COPYFILE_DISABLE keeps macOS tar from adding AppleDouble members.
  List command = %(tar -czf $archive -C ${package.dirname()} --no-recursion
                   @{members.list_free()});
  command.options(%{env: {COPYFILE_DISABLE: 1}}).run();
  return archive;
}

static void source_rows(
  String directory, String output, String base, Array rows) {
  foreach (String name, directory.list_dir()) {
    String package = directory.join_path(name);
    if (!package.is_dir() || package.join_path("dependency*.json").glob() ||
        !package.join_path(%"src/$name.x").is_file())
      continue;
    String archive = source_archive(package, output);
    String url = %"$base/${archive.basename()}";
    rows.push(%"$name 0 source - $url ${digest(archive)}");
  }
}

static String field(Map identity, String name) {
  Var value;
  if (!identity.try_get(name, &value))
    raise %(bad-arg (why "BUNDLE.json has no $name"));
  return value.str();
}

static String bundle_row(String tarball, String output, String base) {
  String member = NULL;
  foreach (String entry, %(tar -tzf $tarball).lines())
    if (!member && entry.endswith("/BUNDLE.json")) member = entry;
  if (!member) raise %(bad-arg (why "$tarball has no BUNDLE.json"));
  Map identity = Json.parse(%(tar -xOzf $tarball $member).output());
  String package = field(identity, "package");
  String platform =
    %"${field(identity, "platform")}-${field(identity, "machine")}";
  Var dependency = identity.getdefault("dependency_version", NULL);
  String version = dependency ? dependency.str() : %"0";
  // Every platform's bundle is named <name>-native.tar.gz by its producer,
  // so the published copy carries the platform to keep them apart.
  String published = output.join_path(%"$package-$platform-native.tar.gz");
  if (tarball.absolute_path() != published.absolute_path())
    tarball.copy_file(published);
  String url = %"$base/${published.basename()}";
  return %"$package $version bundle $platform $url ${digest(published)}";
}

root = String.new(argv[0]).absolute_path().dirname().dirname();
String program = String.new(argv[0]).basename();
List spec = %(
  (--base (value url) required
   (help "URL prefix under which the files are published"))
  (--output (value dir) required
   (help "directory receiving index.txt and source archives"))
  (--package-dir (value dir) repeated
   (help "directory of source packages; defaults to packages"))
  (--x2c-version (value line)
   (help "index header version; defaults to builds/0/x2c --version"))
  (bundles repeated (help "<name>-native.tar.gz bundles to list")));
if (args.contains("-h") || args.contains("--help")) {
  printf("%s", spec.usage(program));
  return 0;
}

Map options = NULL;
try options = args.parse_args(spec);
catch %(bad-arg *detail): {
  String why = detail.assoc(<why>).str(), subject = detail[2].cadr().str();
  Stderr.printf("%sx2c: %s: %s\n", spec.usage(program), why, subject);
  return 2;
}

try {
  String output = options["output"].str(), base = options["base"].str();
  output.make_dirs();
  Array rows = %[];
  List directories = options["package-dir"];
  if (!directories) directories = %(${root.join_path("packages")});
  foreach (Var directory, directories)
    source_rows(directory.str(), output, base, rows);
  foreach (Var tarball, options["bundles"])
    rows.push(bundle_row(tarball.str(), output, base));
  String version = options["x2c-version"].str();
  if (!version)
    version = %(${root.join_path("builds/0/x2c")} --version).output()
                .strip(NULL);
  Array lines = %["# x2c package index for $version",
                  "# name version kind platform url sha256"];
  foreach (Var row, rows.sort()) lines.push(row);
  String index = normal(output).join_path("index.txt");
  index.write_text(%"${lines.join("\n")}\n");
  printf("x2c: wrote %s (%d rows)\n", index, (int) rows.len());
}
catch %(?code *detail): {
  Var why = detail.assoc(<why>);
  if (why is void) Stderr.printf("x2c: %s %s\n", code.str(), detail.repr());
  else Stderr.printf("x2c: %s\n", why.str());
  return 1;
}
