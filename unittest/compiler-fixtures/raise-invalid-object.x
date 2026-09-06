#include "x2c.x"

typedef struct DetailObject {
  int value;
} *DetailObject;

static void invalid(DetailObject value) {
  raise %(invariant (value $value));
}

int main(void) {
  return 0;
}
