#include "x2c.x"

macro Unit $fixture.generate() => {
  static int generated = 42;
}

keyword generate $fixture.generate;

int main(void) {
  generate();
  return 0;
}
