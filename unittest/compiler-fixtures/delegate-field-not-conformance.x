#include "x2c.x"

typedef struct DelegateIterable {
  int value;
} DelegateIterable;

typedef struct DelegateNotIterable {
  delegate DelegateIterable value;
} DelegateNotIterable;

static Iter DelegateIterable.iter(DelegateIterable value, Iter dest) {
  (void) value;
  return dest;
}

protocol Iter(DelegateIterable);

int main(void) {
  DelegateNotIterable value = { { 1 } };
  int total = 0;
  foreach(int item, value) total += item;
  return total;
}
