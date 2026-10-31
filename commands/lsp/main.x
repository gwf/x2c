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
      usage: x2c lsp
      Serve one workspace over the Language Server Protocol on stdio."));
    return 0;
  }
  int resume = -1;
  if (argc == 3 && !strcmp(argv[1], "--lsp-resume")) resume = atoi(argv[2]);
  else if (argc != 1) return 2;
  return lsp_serve(resume);
}
