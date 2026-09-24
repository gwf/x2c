#include "x2c.x"
#include <stdio.h>

typedef int Count;
typedef long Total;

static Count bump(Count value) => value + 1;
static Total add(Total left, Total right) => left + right;
meta static Count increase(Count &value) => ++value;

meta static Count meta_increase(Count value) {
  Func function = increase;
  return function(value);
}

int main(void) {
  Func first = bump, second = add, third = increase;
  Count value = 4;
  printf("%s\n%s\n%s\n", first.signature().repr(),
         second.signature().repr(), third.signature().repr());
  printf("%d %d %d\n", first(value).int(), third(value).int(), value);
  printf("%d\n", $meta_increase(4));
  return 0;
}
