#include "x2c.x"
$(import "../../src/grammar.xmacro")

static void check(List input, List callee, List arguments) {
  List parts = source_call(input);
  assert(parts && parts.car() === callee &&
         parts.cadr() === arguments);
}

int main(void) {
  List binding = %(binding 7 "callee");
  List callee = %(expr ((func ((int))) int) (ident $binding));
  List first = %(expr (int) (literal (int) "1"));
  List second = %(expr (int) (literal (int) "2"));
  List arguments = %($first $second);
  List call = %(call $callee (args @arguments));
  check(call, callee, arguments);
  check(%(expr (int) $call), callee, arguments);
  List empty = %(call $callee (args (expr () ())));
  check(empty, callee, NULL);
  check(%(expr (int) $empty), callee, NULL);
  assert(!source_call(%(expr (int) (ident $binding))));
  printf("source call projection passed\n");
  return 0;
}
