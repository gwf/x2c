#include "x2c.x"

$(import "../../lib/error-macros.xmacro")

static void bump(int *value, int amount) {
  *value += amount;
}

macro Statement $add_two(Expr $value) => {
  {
    bump(&$value, 2);
  }
}

macro Statement $add_three(Expr $value) => {
  do {
    bump(&$value, 3);
  } while (0)
}

macro Decorator $around(
  Statement $target, Expr $value
) => {
  {
    bump(&$value, 5);
    $target
    bump(&$value, 7);
  }
}

macro Decorator $do_around(
  Statement $target, Expr $value
) => {
  do {
    bump(&$value, 13);
    $target
    bump(&$value, 17);
  } while (0)
}

macro Decorator $outer(Statement $target) => {
  {
    $target
  }
}

static int fallback_probe(int fail) {
  if (fail)
    $error.fallback(23)
    raise %(fallback-p);
  return 42;
}

int main(void) {
  int value = 0;
  if (1)
    $add_two(value);
  else
    value = 1000;
  if (0)
    value = 1000;
  else
    $add_three(value);
  int loop = 1;
  while (loop)
    $around(value)
    loop = 0;
  if (1)
    $outer()
    $do_around(value)
    value += 11;
  else
    value = 1000;
  printf("%d %d\n", value, fallback_probe(0));
  return 0;
}
