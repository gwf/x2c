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
  foreach(int value, bag)
    total += value;

  foreach(int value, %[4, 5])
    total += value;

  foreach(int byte, %"A")
    total += byte;

  Map one = %{"x": 6};
  foreach(Var value, one)
    total += value.integer();

  foreach(String word, %"aa bbb".words())
    total += word.len();

  printf("%d\n", total);
  return total == 91 ? 0 : 1;
}
