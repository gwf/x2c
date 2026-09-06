#include "x2c.x"

macro Expression $fixture.value() => (42)
keyword foreach $fixture.value;

int main(void) {
  return foreach();
}
