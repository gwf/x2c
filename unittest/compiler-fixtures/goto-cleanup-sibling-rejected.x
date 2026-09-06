#include "x2c.x"

static void sibling(void) {
  {
    defer (void) 0;
left:
    (void) 0;
  }
  {
    defer (void) 0;
    goto left;
  }
}

int main(void) {
  sibling();
  return 0;
}
