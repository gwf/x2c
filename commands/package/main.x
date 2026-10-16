/*  main.x -- external package manager

    Copyright (c) 2026 Gary William Flake.
*/
#include "package.x"
#include "args.x"
#include "cli.x"

String x2c_embedded_identity(void);

static List _spec(String operation) {
  List help = %((-h --help (help "Show this help")));
  List quiet = %((-q --quiet (help "Suppress successful receipts")));
  List index = %((--index (value url-or-path)
    (help "Resolve package names through this index")));
  if (operation == "install") return %(
    @help @quiet @index
    (--sha256 (value hex) (help "Require this archive digest"))
    (--force (help "Install a bundle built for another x2c version"))
    (package required));
  if (operation == "remove") return %(@help @quiet (name required));
  if (operation == "list") return help;
  if (operation == "ensure") return %(
    @help @quiet @index (--lock (value path) required) (pins repeated));
  Diagnostics.driver_error(%"package: unknown operation '$operation'");
  return NULL;
}

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  Array arguments = $auto(CliRequest.command_arguments(argc, argv));
  if (arguments) {
    CliRequest parsed = CliRequest.parse_arguments(arguments);
    PackageOptions request = {
      .inputs = parsed.inputs, .index = parsed.index, .sha256 = parsed.sha256,
      .quiet = parsed.quiet, .force = parsed.force
    };
    return _run(parsed.command.str(), request);
  }
  List args = Args.from_argv(argc, argv);
  String operation = args ? args.car() : "--help";
  if (operation == "--help" || operation == "-h") {
    puts("usage: x2c package <install|remove|list> [options]\n"
         "       x2c install, remove, and list are equivalent short forms.");
    return 0;
  }
  List spec = _spec(operation);
  // Help before an operand delimiter does not interpret literal operands.
  for (List rest = args.cdr(); rest; rest = rest.cdr()) {
    String word = rest.car();
    if (word == "--") break;
    if (word == "--help" || word == "-h") {
      printf("%s", Args.usage(%"x2c package $operation", spec));
      return 0;
    }
    if (word == "--index" || word == "--sha256" || word == "--lock")
      if (rest.cdr()) rest = rest.cdr();
  }
  Map parsed = NULL;
  try parsed = Args.parse(args.cdr(), spec);
  catch %(bad-arg (operation "Args.parse") (reason ?why) *): {
    Diagnostics.driver_error(%"package $operation: $why");
  }
  PackageOptions request = {
    .index = parsed["index"], .sha256 = parsed["sha256"],
    .quiet = parsed["quiet"].integer(), .force = parsed["force"].integer()
  };
  if (operation == "install") request.inputs = %(${parsed["package"]});
  else if (operation == "remove") request.inputs = %(${parsed["name"]});
  else if (operation == "ensure") {
    request.lock = parsed["lock"];
    request.inputs = parsed["pins"];
    if (request.inputs.len() % 2)
      Diagnostics.driver_error("package ensure: expected name/version pairs");
  }
  return _run(operation, request);
}

static int _run(String operation, PackageOptions request) {
  if (operation == "list") return request.list_packages();
  if (operation == "install") return request.install();
  if (operation == "remove") return request.remove_package();
  return request.ensure();
}
