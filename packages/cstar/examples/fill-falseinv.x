/*  fill-falseinv.x -- fill.x with an invariant the loop does not establish.

    The code is the correct fill; only the invariant changed, from
    `0i <= i_v` to `1i <= i_v`. It does not hold when the loop is first
    reached with `i = 0`, so the engine cannot cut the state there and the
    run stops without a report.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify_with(
  "xs:(int)list",
  "int_array p xs ** fact(n = &(LENGTH xs))",
  "int_array p (REPLICATE (LENGTH (xs:(int)list)) v)"
)
static void fill_int(int *p, int n, int v) {
  int i = 0;
  $cstar.proof(fill_entry, "int_array p__pre", "n__addr:addr", "n__pre:int",
               "xs:(int)list", "v__pre:int");
  $cstar.invariant_sl(
    "exists i_v. "
    "int_array p__pre (APPEND (REPLICATE (num_of_int i_v) v__pre) "
    "                         (list_drop (num_of_int i_v) xs)) ** "
    "data_at p__addr Tptr p__pre ** "
    "data_at n__addr Tint n__pre ** "
    "data_at v__addr Tint v__pre ** "
    "data_at i__addr Tint i_v ** "
    "fact(n__pre = &(LENGTH xs)) ** "
    "fact(n__pre <= 2147483647i) ** "
    "fact(1i <= i_v && i_v <= n__pre)"
  )
  while (i < n) {
    $cstar.proof(fill_before_store, "Tint", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "v__pre:int");
    p[i] = v;
    $cstar.proof(fill_after_store, "Tint", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "v__pre:int");
    i++;
  }
  $cstar.proof(fill_exit, "i_v:int", "n__pre:int", "xs:(int)list",
               "v__pre:int");
}

int main(void) {
  int numbers[5] = { 0, 0, 0, 0, 0 };
  int empty[1] = { 9 };

  fill_int(numbers, 5, 42);
  fill_int(empty, 0, 1);

  printf("numbers:");
  for (int i = 0; i < 5; i++) printf(" %d", numbers[i]);
  printf("\nempty untouched: %d\n", empty[0]);
  return 0;
}
