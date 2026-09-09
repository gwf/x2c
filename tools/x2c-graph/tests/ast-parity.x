#include "frontend.x"

#include <stdio.h>

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  x2c_initialize_environment(argv[0]);
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  Frontend frontend = Frontend.new(request);
  Context command = Context.open_isolated_named("AST parity command");
  ParsedUnit parsed;
  if (!frontend.open(String.new(argv[1]), &parsed)) {
    foreach (Var entry, parsed.compiler.diagnostics())
      parsed.compiler.print_diagnostic(entry);
    parsed.close();
    command.close();
    return 1;
  }
  foreach (List node, parsed.ast) printf("\n%s\n", node.repr());
  parsed.close();
  command.close();
  return 0;
}
