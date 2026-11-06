/*  main.x -- external language server command

    Copyright (c) 2026 Gary William Flake.
*/
#include "system-macros.x"
#include "lsp.x"

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  if (argc == 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
    puts($dedent(%"
      Usage:
        x2c lsp [options]

      Serve the workspace in the current directory over the Language Server
      Protocol on stdio: diagnostics, definitions, hover, completion,
      symbols, references, and rename. Editor setup is described at
      https://x2c-lang.dev/docs/reference/cli.html#language-server

      Options:
        -h, --help                  Show help and exit"));
    return 0;
  }
  int resume = -1;
  if (argc == 3 && !strcmp(argv[1], "--lsp-resume")) resume = atoi(argv[2]);
  else if (argc != 1) _usage_error(argv[1]);
  return lsp_serve(resume);
}

/* The server takes no operands, and no option but help. */
static void _usage_error(const char *word) {
  String text = String.new(word);
  String problem =
    text.startswith("-") ? "unknown option" : "unexpected operand";
  Diagnostics.driver_error(%"lsp: $problem '$text'");
}
