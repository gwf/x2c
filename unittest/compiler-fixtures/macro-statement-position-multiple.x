#include "x2c.x"

macro Decorator $multiple(Statement $target) => {
  $target
  return 0;
}

int main(void) {
  if (1)
    $multiple()
    puts("target");
  return 0;
}
