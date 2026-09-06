#include "frontend.x"

#include <stdio.h>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  x2c_initialize_environment(argv[0]);
  Context command = Context.open_isolated_named("AST parity command");
  Frontend frontend = Frontend.new(NULL);
  ParsedUnit parsed;
  if (!frontend.open(String.new(argv[1]), &parsed)) {
    command.close();
    return 1;
  }
  foreach (List node, parsed.ast) printf("\n%s\n", node.repr());
  parsed.close(frontend);
  command.close();
  return 0;
}
