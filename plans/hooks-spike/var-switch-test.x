#include "x2c.x"
#include "var-switch.x"

static String name(Var v) {
  switch (v) {
    case 2: return "two";
    case 3: return "three";
  }
  return "other";
}

int main(void) {
  printf("%s %s\n", name(2), name(3.5));
  return 0;
}
