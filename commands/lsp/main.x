/*  main.x -- external language server command

    Copyright (c) 2026 Gary William Flake.
*/
#include "lsp.x"

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  if (argc == 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
    puts("usage: x2c lsp\nServe one workspace over the Language Server Protocol on stdio.");
    return 0;
  }
  if (argc != 1) return 2;
  return lsp_serve();
}
