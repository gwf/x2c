#include "x2c.x"

typedef List InvalidParent;
typedef InvalidParent InvalidChild;

Iter InvalidParent.iter(InvalidParent values, Iter dest) {
  return List.iter((List) values, dest);
}

protocol Iter(InvalidParent);

int InvalidChild.iter(InvalidChild values, int unused) {
  (void) values;
  return unused;
}

protocol Iter(InvalidChild);

int main(void) {
  InvalidChild values = %(1 2 3);
  foreach(int value, values) (void) value;
  return 0;
}
