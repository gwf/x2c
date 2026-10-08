#include "x2c.x"
#include "meta.x"

/* A project meta function reports a failure at a node it received, the
   second statement of the block it decorates, rather than at the
   decorator's invocation. */
meta static List single_statement(List body) {
  match (body) case %(block ? ?second):
    x2c_diagnostic_fail_at(
      second, <macro>, "only one statement is allowed", %("reason: example"));
  return %($body);
}
macro Decorator $single(Stmt $body) { @single_statement($body) }

int main(void) {
  int total = 0;
  $single() {
    total += 1;
    total += 2;
  }
  return total;
}
