#include "x2c.x"

macro Statement $empty() => {
}

int main(void) {
  if (1)
    $empty();
  return 0;
}
