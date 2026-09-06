#include "x2c.x"

static void inward(void) {
  goto protected;
  {
    defer (void) 0;
protected:
    (void) 0;
  }
}

int main(void) {
  inward();
  return 0;
}
