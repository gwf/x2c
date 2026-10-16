/*  main.x -- external build, run, and script command

    Copyright (c) 2026 Gary William Flake.
*/
#include "workflow.x"
#include "script.x"
#include "logger.x"

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  if (argc == 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
    puts("usage: x2c-build <build|run|script> [OPTIONS] [INPUTS...]\n"
         "Use x2c-build <operation> --help for operation options.");
    return 0;
  }
  Array arguments = CliRequest.command_arguments(argc, argv);
  if (!arguments) arguments = CliRequest.read_arguments(argc, argv);
  defer arguments.free();
  String operation = arguments.len() ? arguments[0] : NULL;
  if (operation != "build" && operation != "run" && operation != "script")
    Diagnostics.driver_error("expected build, run, or script");
  CliRequest request = CliRequest.parse_arguments(arguments);
  if (!Compiler.driver_executable())
    Diagnostics.driver_error("matching x2c compiler is unavailable");
  Build.initialize();
  String diagnostics = request.diagnostics_file;
  if (diagnostics && !diagnostics_write_json(diagnostics))
    Diagnostics.driver_error(%"cannot open diagnostics file '$diagnostics'");
  if (request.command == <script> && request.prepare_script()) return 0;
  report_configure(
    request.quiet, request.plain, request.color_mode,
    request.verbose || request.debugging, request.dry_run, request.inspects());
  _configure_logging(request.debugging);
  Frontend.load_support(request);
  Context command = Context.open_isolated_named("compiler command");
  int status = build_request(request);
  command.close();
  if (request.command == <script> && !status) status = request.run_script();
  return status;
}

/* Only --debug logs. Without it there is no sink, so log_should_log is
   false and nothing is rendered or written. */
static void _configure_logging(int debugging) {
  Logger logger = log_get_global_logger();
  if (!logger) return;
  logger.clear_sinks();
  if (!debugging) return;
  logger.set_min_level(<debug>);
  logger.add_stderr_sink();
}
