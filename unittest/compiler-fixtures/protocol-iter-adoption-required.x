#include "x2c.x"

typedef struct Bag {
  List values;
} *Bag;

Iter Bag.iter(Bag bag, Iter dest) {
  return bag.values.iter(dest);
}

int main(void) {
  Bag bag = Scope.malloc(sizeof(struct Bag));
  bag.values = %(1 2 3);
  foreach(int value, bag)
    (void) value;
  return 0;
}
