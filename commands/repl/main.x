/*  main.x -- external REPL command

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl.x"
#include "args.x"

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(
    argv[0], x2c_embedded_identity());
  List args = Args.from_argv(argc, argv);
  List spec = %(
    (-h --help (help "Show this help"))
    (--dump (help "Print typed AST and lowered Lisp"))
    (--stats (help "Print runtime statistics at exit"))
    (--verbose-stats (help "Print detailed statistics at exit"))
    (--native-module (value file) repeated
      (help "Load a native compile-time module")));
  if (args.contains("-h") || args.contains("--help")) {
    printf("%s", Args.usage("x2c repl", spec));
    return 0;
  }
  Map parsed = NULL;
  try parsed = Args.parse(args, spec);
  catch %(bad-arg *): {
    Stderr.printf("x2c repl: invalid arguments\n");
    return 2;
  }
  CliRequest request = cli_request(<repl>);
  request.native_modules = parsed["native-module"];
  ReplOptions options = {
    .dump = parsed["dump"].integer(),
    .stats = parsed["stats"].integer(),
    .verbose_stats = parsed["verbose-stats"].integer()
  };
  Frontend.load_support(request);
  Context command = Context.open_isolated_named("repl command");
  int result = repl_run(request, options);
  command.close();
  return result;
}
