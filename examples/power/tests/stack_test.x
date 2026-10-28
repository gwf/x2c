/* A test file is an ordinary executable x2c program. */
#include "test.x"

$test()
static void push_then_pop(void) {
  Array stack = auto [];
  stack.push(1);
  $expect_eq(stack.pop(), 1);
  $expect_eq(stack.len(), 0);
}

$test.main();
