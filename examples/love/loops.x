#include <assert.h>

int main(void) {
  Array orders = [%(tea 2 "Ada"), %(coffee 1 "Grace"), %(tea 1 "Linus")];

  // foreach walks anything with elements; destructure as you go.
  foreach (List order in orders) {
    (Symbol item, int count, String who) = order;
    printf("%s wants %d %s\n", who, count, item.str());
  }

  // A pattern condition binds names right where you test them.
  foreach (List order in orders)
    if (order ~= %(tea ?(int n) ?(String who)) && n > 1)
      puts(%"$who is thirsty");

  // Lambdas and iterator chains read left to right.
  Var total = orders.iter().map(%!(List order) => order[1])
    .foldl(0, %!(sum, count) => sum + count);
  assert(total == 4);

  return 0;
}
