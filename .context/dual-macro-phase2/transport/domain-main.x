#include "meta.x"
#include <assert.h>
macro Statement $padding() { int unused = 0; }
static int global_pad;
static int helper(int x) => x + 1;
static int other(int x) => x + 100;
$(import "domain-helpers.xmacro")

int main(void) {
  int shift_a = 1, shift_b = 2, shift_c = 3;
  (void) shift_a, (void) shift_b, (void) shift_c;
  int price = 20, tax = 1, discount = 2;
  assert($composed(helper, tax, helper(price + tax)) == 22);
  assert($composed(helper, tax, helper(price + discount)) == 0);
  assert($bridge(helper(price)) == 21);
  {
    int (*helper)(int) = other;
    assert($bridge(helper(price)) == 0);
  }
  $typed(int, price, price += 1;);
  assert(price == 21);
  puts("domain hydration: rigid free mismatch and typed reconstruction pass");
  return 0;
}
