/*  x2c-bind.x -- the x2c bind command

    Copyright (c) 2026 Gary William Flake.

    Collects a C header and an empty unit through the host preprocessor and
    writes a package's raw tier from the rows the header adds. A later run
    rewrites only the marked region of the entry unit. README.md states the
    rules that name handles, methods, and releases.
*/
#include "frontend.x"
#include "args.x"
#include "survey.x"
#include "render.x"

// The command build links identity.x, which defines this for each stage.
String x2c_embedded_identity(void);

static List options_spec = %(
  (-h --help (help "Show this help"))
  (--package (value NAME) (help "Name the package and its entry unit"))
  (--header (value FILE) (help "Bind the C header FILE"))
  (--prefix (value PREFIX)
    (help "Strip PREFIX from method names (default: shared prefix)"))
  (-I (value DIR) repeated (help "Search DIR for the headers FILE includes"))
  (-l (value LIB) repeated (help "Link consumers with library LIB"))
  (-o (value DIR) (help "Write the package in DIR (default: packages/NAME)")));

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  Map options = NULL;
  try options = Args.parse(Args.from_argv(argc, argv), options_spec);
  catch %(bad-arg (operation "Args.parse") (reason ?why) *): {
    Diagnostics.driver_error(%"bind: $why");
  }
  if (options["help"].integer()) {
    fputs(Args.usage("x2c bind", options_spec), stdout);
    return 0;
  }
  BindRequest request = _request(options);
  Path work = Path.temp_dir();
  defer work.remove_tree();
  return _bind(request, work, options.getdefault("prefix", NULL));
}

/* Validates the options and fills in their defaults. */
static BindRequest _request(Map options) {
  String package = options.getdefault("package", NULL);
  String header = options.getdefault("header", NULL);
  if (!package || !header)
    Diagnostics.driver_error("bind: --package and --header are required");
  if (!package.is_identifier() || package.lower() != package)
    Diagnostics.driver_error(
      %"bind: package name '$package' must be a lower-case identifier");
  if (!Path.is_file(header))
    Diagnostics.driver_error(%"bind: no such header '$header'");
  BindRequest request = xcalloc(1, sizeof(struct BindRequest));
  request.package = package;
  request.header = Path.absolute(header);
  request.shim = %"$(Path.stem(header))-raw.h";
  request.out_dir = options.getdefault("o", %"packages/$package");
  request.include_dirs = options["I"].list().map(
    %!(String dir) => Path.absolute(dir));
  request.libraries = options["l"].list();
  return request;
}

/* Collects an empty unit and a unit that includes the header, surveys the
   difference while both are open, and writes the package. */
static int _bind(BindRequest request, Path work, String prefix) {
  Path empty = work.join("empty.x"), probe = work.join("probe.x");
  empty.write_text("\n");
  probe.write_text(%"#include \"$(request.header)\"\n");
  CliRequest collection = xcalloc(1, sizeof(struct CliRequest));
  collection.command = <translate>;
  collection.cpp_symbols = 1;
  collection.include_dirs = request.include_dirs;
  Frontend frontend = Frontend.new(collection);
  ParsedUnit base, header;
  if (!_collect(frontend, empty, base)) return 1;
  defer base.close();
  if (!_collect(frontend, probe, header)) return 1;
  defer header.close();
  return _write(Survey.new(base, header, prefix), request);
}

static int _collect(Frontend frontend, Path path, ParsedUnit &unit) {
  if (frontend.start(path, unit) && unit.collect(frontend)) return 1;
  foreach (List entry in unit.compiler.diagnostics())
    unit.compiler.print_diagnostic(entry);
  unit.close();
  return 0;
}

/* Writes the entry unit's region and each missing package file. */
static int _write(Survey s, BindRequest request) {
  Path src = request.out_dir.join("src");
  src.make_dirs();
  Path entry = src.join(%"$(request.package).x");
  String text = entry.exists()
    ? Survey.replace_region(entry.read_text(), s.region(request))
    : s.entry_unit(request);
  if (!text) {
    fprintf(
      stderr, "x2c bind: %s has no complete x2c bind region; not changed\n",
      entry);
    return 1;
  }
  entry.write_text(text);
  _create(src.join(request.shim), s.shim(request));
  _create(request.out_dir.join("Makefile"), s.makefile(request));
  _create(request.out_dir.join("README.md"), s.readme(request));
  printf(
    "x2c bind: %s: %d handles, %d methods, %d releases, %d raw functions, "
    "%d not forwarded\n",
    request.out_dir, s.handles.len(), s.methods.len(), s.releases.len(),
    s.raw.len(), s.skipped.len());
  return 0;
}

static void _create(Path path, String text) {
  if (!path.exists()) path.write_text(text);
}
