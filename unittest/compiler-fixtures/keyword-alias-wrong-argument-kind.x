#include "x2c.x"

macro Expression $fixture.named(Name $name) => (0)

keyword named $fixture.named;

int main(void) {
  return named(42);
}
