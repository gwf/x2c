#include "x2c.x"
$(import "../../src/grammar.xmacro")

static void check(List input, List callee, List arguments) {
  List parts = source_call(input);
  assert(parts && parts.car() === callee &&
         parts.cadr() === arguments);
}

static void check_assignment(List input, List target, List stored) {
  List parts = source_assignment(input);
  assert(parts && parts.car() === target && parts.cadr() === stored);
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
  List target = %(expr (int) (ident $binding));
  List stored = %(expr (int) (literal (int) "3"));
  List assignment = %(op = $target $stored);
  check_assignment(assignment, target, stored);
  check_assignment(%(expr (int) $assignment), target, stored);
  assert(!source_assignment(%(op =
    (bind $binding ()) $stored)));
  assert(!source_assignment(%(expr (int)
    (op = (bind $binding ()) $stored))));
  assert(!source_assignment(%(expr (int) (ident $binding))));
  printf("source call and assignment projections passed\n");
  return 0;
}
