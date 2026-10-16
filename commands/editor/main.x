/*  main.x -- external semantic editor adapter

    Copyright (c) 2026 Gary William Flake.
*/
#include "editor.x"

String x2c_embedded_identity(void);

int main(int argc, char **argv) {
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity());
  if (argc == 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
    puts("usage: x2c editor RESPONSE SOURCE QUERY OFFSET COUNT "
         "[OVERLAYS...] -- [BUILD-ARGS...]\n"
         "Serve one private semantic editor request.");
    return 0;
  }
  return editor_request(argc, argv);
}
