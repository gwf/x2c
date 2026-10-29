/*  main.x -- external native playground command

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl.x"
#include "args.x"

String x2c_embedded_identity(void);

/** Parses native build options with the ordinary build request parser. */
CliRequest repl_native_request(List arguments) {
  Array native = ["build"];
  int operands = 0;
  foreach (String argument, arguments) {
    if (!operands && (argument == "--dump" || argument == "--stats" ||
                      argument == "--verbose-stats")) continue;
    else {
      native.push(argument);
      if (argument == "--") operands = 1;
    }
  }
  CliRequest request = CliRequest.parse_arguments(native);
  request.sources = SourceView.new();
  return request;
}

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  List arguments = Args.from_argv(argc, argv);
  if ("--help" in arguments || "-h" in arguments) {
    puts("usage: x2c repl [OPTIONS] [SOURCES|HEADERS|NATIVE-INPUTS...]\n\n"
         "Start a persistent native library playground. Enter :help for commands.\n\n"
         "  --dump                 Print typed syntax and retained native artifacts\n"
         "  --stats                Print worker statistics at exit\n"
         "  --verbose-stats        Print detailed worker statistics at exit\n"
         "  -I DIR                 Add an x2c/C include directory\n"
         "  --x-include-dir DIR    Add an x2c include directory\n"
         "  --c-include-dir DIR    Add a C include directory\n"
         "  -D NAME[=VALUE]        Define a preprocessor macro\n"
         "  -L DIR, -l LIB         Configure native library linkage\n"
         "  -Xcc ARG, -Wl,ARG      Pass native compiler/linker options\n"
         "  --package-dir DIR      Add a package directory\n"
         "  --native-module FILE   Select a compile-time module\n"
         "  --manifest-path FILE   Use a project manifest\n"
         "  --target NAME          Select its target\n"
         "  --profile NAME         Select its build profile\n\n"
         "Native build options use the same spellings as x2c build.\n"
         "Successful loading and reloading clear prompt and library state.");
    return 0;
  }
  ReplOptions options = repl_reporting_options(arguments);
  CliRequest request = repl_native_request(arguments);
  Context command = Context.open_isolated_named("REPL supervisor");
  int result = repl_run(request, options);
  command.close();
  return result;
}
