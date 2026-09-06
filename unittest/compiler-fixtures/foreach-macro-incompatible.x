#include "x2c.x"

typedef struct Pair {
  int value;
} Pair;

int main(void) {
  List values = %(1 2 3);
  foreach(Pair value, values) (void) value;
  return 0;
}
