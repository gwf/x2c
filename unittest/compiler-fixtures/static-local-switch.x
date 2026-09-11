#include "x2c.x"
static int initial(void) { return 41; }
int main(void) {
  switch (1) {
    case 0:
      static int value = initial();
    case 1:
      return value;
  }
  return 0;
}
