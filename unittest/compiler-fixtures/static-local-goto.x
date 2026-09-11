#include "x2c.x"
static int initial(void) { return 41; }
int main(void) {
  goto later;
  static int value = initial();
later:
  return value;
}
