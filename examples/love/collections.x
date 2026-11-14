#include <assert.h>

int main(void) {
  // Immutable Lists share tails and mix value kinds.
  List order = %("tea" 3 2.5), labeled = cons(<order>, order);
  assert(labeled.cdr() == order);

  // Arrays grow and change in place.
  Array basket = ["tea", 3, 2.5];
  basket[1] += 1;
  basket.push(<packed>);
  assert(basket == ["tea", 4, 2.5, <packed>]);

  // Maps find values by key.
  Map details = {name: "tea", quantity: 3, price: 2.5};
  details[<quantity>] += 1;
  assert(basket[1] == details[<quantity>]);
  printf("%s\n%s\n%s: %s\n",
         labeled.repr(), basket.repr(),
         details[<name>], details[<quantity>]);
  return 0;
}
