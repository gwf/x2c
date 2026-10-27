#include "x2c.x"

meta int total(int prefix, List @items) {
  foreach (int item in items) prefix += item;
  return prefix;
}
meta int length(List @items) => items.len();
meta List numbers(void) => %(2 3);
meta List empty(void) => NULL;
meta int dynamic(void) {
  Func f = total, zero = length;
  List items = %(2 3);
  return f(1, @items, 4).int() + zero(items).int();
}

int main(void) {
  printf("meta %d %d %d %d\n", $total(1, 2, 3), $total(7),
    $length(), $length($numbers()));
  printf("splice %d %d\n", $total(1, @($numbers()), 4, @($empty())), $dynamic());
  return 0;
}
