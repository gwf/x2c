/*  main.x -- external package manager

    Copyright (c) 2026 Gary William Flake.
*/
#include "system-macros.x"
#include "package.x"
#include "args.x"
#include "cli/cli.x"

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  Array arguments = auto CliRequest.command_arguments(argc, argv);
  if (arguments) {
    CliRequest parsed = CliRequest.parse_arguments(arguments);
    return _parsed(parsed);
  }
  List args = Args.from_argv(argc, argv);
  String operation = args ? args.car() : NULL;
  if (!operation || operation == "--help" || operation == "-h") {
    puts($dedent(%"
      Usage:
        x2c package <install|remove|list> [options]

      x2c install, remove, and list are equivalent short forms."));
    return operation ? 0 : 2;
  }
  if (operation == "ensure") return _ensure(args.cdr());
  if (!(operation in %("install" "remove" "list")))
    Diagnostics.driver_error(%"package: unknown operation '$operation'");
  arguments = args;
  return _parsed(CliRequest.parse_arguments(arguments));
}

/* Both public entry paths use the driver's command parser. */
static int _parsed(CliRequest parsed) {
  PackageOptions request = {
    .inputs = parsed.inputs, .index = parsed.index, .sha256 = parsed.sha256,
    .quiet = parsed.quiet, .force = parsed.force
  };
  return _run(parsed.command, request);
}

/* Dependency preparation is an internal operation, separate from the CLI. */
static int _ensure(List args) {
  List spec = %(
    (-q --quiet)
    (--index (value url-or-path))
    (--lock (value path) required)
    (pins repeated));
  Map parsed = NULL;
  try parsed = Args.parse(args, spec);
  catch %(bad-arg (operation "Args.parse") (reason ?why) *):
    Diagnostics.driver_error(%"package ensure: $why");
  PackageOptions request = {
    .inputs = parsed["pins"], .index = parsed["index"], .lock = parsed["lock"],
    .quiet = parsed["quiet"].integer()
  };
  if (request.inputs.len() % 2)
    Diagnostics.driver_error("package ensure: expected name/version pairs");
  return request.ensure();
}

static int _run(String operation, PackageOptions request) {
  switch (operation) {
    case "list": return request.list_packages();
    case "install": return request.install();
    case "remove": return request.remove_package();
  }
  return request.ensure();
}
