/*  clear-offbyone.x -- clear.x with `i <= n`, which stores one cell past
    the array the contract owns.

    The store the extra iteration performs is outside `int_array p xs`, so
    `fill_before_store` cannot expose a cell for it and the engine refuses
    the step. `main` gives the buffer one spare element, because this
    example still runs as an ordinary program and C would otherwise write
    past it.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify_with(
  "xs:(int)list",
  "int_array p xs ** fact(n = &(LENGTH xs))",
  "int_array p (REPLICATE (LENGTH (xs:(int)list)) 0i)"
)
static void clear_int(int *p, int n) {
  int i = 0;
  $cstar.proof(fill_entry, "int_array p__pre", "n__addr:addr", "n__pre:int",
               "xs:(int)list", "0i:int");
  $cstar.invariant_sl(
    "exists i_v. "
    "int_array p__pre (APPEND (REPLICATE (num_of_int i_v) 0i) "
    "                         (list_drop (num_of_int i_v) xs)) ** "
    "data_at p__addr Tptr p__pre ** "
    "data_at n__addr Tint n__pre ** "
    "data_at i__addr Tint i_v ** "
    "fact(n__pre = &(LENGTH xs)) ** "
    "fact(n__pre <= 2147483647i) ** "
    "fact(0i <= i_v && i_v <= n__pre)"
  )
  while (i <= n) {
    $cstar.proof(fill_before_store, "Tint", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "0i:int");
    p[i] = 0;
    $cstar.proof(fill_after_store, "Tint", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "0i:int");
    i++;
  }
  $cstar.proof(fill_exit, "i_v:int", "n__pre:int", "xs:(int)list", "0i:int");
}

int main(void) {
  int numbers[5] = { 3, 1, 4, 1, 5 };
  clear_int(numbers, 4);
  printf("numbers:");
  for (int i = 0; i < 5; i++) printf(" %d", numbers[i]);
  printf("\n");
  return 0;
}
