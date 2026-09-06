#include "x2c.x"

static int source(int value) {
  return value + 1;
}

macro Unit $forward(Function $definition) => {
  $definition
}

$forward(static int forwarded(int value) {
  return source(value);
});

int main(void) {
  printf("%d\n", forwarded(41));
  return 0;
}
