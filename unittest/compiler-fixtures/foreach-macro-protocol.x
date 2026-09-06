#include "x2c.x"

typedef struct Bag {
  List values;
} *Bag;

Iter Bag.iter(Bag bag, Iter dest) {
  return bag.values.iter(dest);
}

protocol Iter(Bag);

int main(void) {
  Bag bag = Scope.malloc(sizeof(struct Bag));
  bag.values = %(1 2 3);
  int total = 0;
  foreach(int value, bag) total += value;
  printf("%d\n", total);
  return total == 6 ? 0 : 1;
}
