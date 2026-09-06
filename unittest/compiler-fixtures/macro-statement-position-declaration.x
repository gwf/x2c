#include "x2c.x"

macro Statement $declaration() => {
  int generated = 1;
}

int main(void) {
  if (1)
    $declaration();
  return 0;
}
