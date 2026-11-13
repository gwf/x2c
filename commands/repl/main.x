/*  main.x -- external native playground command

    Copyright (c) 2026 Gary William Flake.
*/
#include "system-macros.x"
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
    puts(
      $dedent(%"
      Usage:
        x2c repl [options] [<input>...]

      Start a persistent native library playground. Inputs are x2c sources,
      C headers, and native inputs. Enter :help for commands.

      Options:
        -h, --help                  Show help and exit
            --dump                  Print typed syntax and native artifacts
            --stats                 Print worker statistics at exit
            --verbose-stats         Print detailed worker statistics at exit
        -I <dir>                    Add an x2c/C include directory
            --x-include-dir <dir>   Add an x2c include directory
            --c-include-dir <dir>   Add a C include directory
        -D <name>[=<value>]         Define a preprocessor macro
        -L <dir>, -l <lib>          Configure native library linkage
        -Xcc <arg>, -Wl,<arg>       Pass native compiler and linker options
            --package-dir <dir>     Add a package directory
            --native-module <file>  Select a compile-time module
            --manifest-path <file>  Use a project manifest
            --target <name>         Select its target
            --profile <name>        Select its build profile

      Native build options use the same spellings as x2c build.
      Successful loading and reloading clear prompt and library state."));
    return 0;
  }
  ReplOptions options = repl_reporting_options(arguments);
  CliRequest request = repl_native_request(arguments);
  Context command = Context.open_isolated_named("REPL supervisor");
  int result = repl_run(request, options);
  command.close();
  return result;
}
