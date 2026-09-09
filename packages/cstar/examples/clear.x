/*  clear.x -- clearing an int buffer and a char buffer, verified and
    ordinary.

    Both loops are the same proof. The reusable steps live in the package's
    own C* proof library, `proof/x2c_array_helpers.c`, and reach x2c as
    methods on the session: `fill_entry` before the loop, `fill_before_store`
    and `fill_after_store` around the store, and `fill_exit` after it. Only
    the element term differs, `Tint` or `Tchar`.

    The invariant is a complete separation-logic assertion, so it uses
    `$cstar.invariant_sl`: it binds the existential `i_v`, states the
    ownership of every cell it touches, and carries the facts the next
    iteration needs.
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
  while (i < n) {
    $cstar.proof(fill_before_store, "Tint", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "0i:int");
    p[i] = 0;
    $cstar.proof(fill_after_store, "Tint", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "0i:int");
    i++;
  }
  $cstar.proof(fill_exit, "i_v:int", "n__pre:int", "xs:(int)list", "0i:int");
}

$cstar.verify_with(
  "xs:(int)list",
  "char_array p xs ** fact(n = &(LENGTH xs))",
  "char_array p (REPLICATE (LENGTH (xs:(int)list)) 0i)"
)
static void clear_char(char *p, int n) {
  int i = 0;
  $cstar.proof(fill_entry, "char_array p__pre", "n__addr:addr", "n__pre:int",
               "xs:(int)list", "0i:int");
  $cstar.invariant_sl(
    "exists i_v. "
    "char_array p__pre (APPEND (REPLICATE (num_of_int i_v) 0i) "
    "                          (list_drop (num_of_int i_v) xs)) ** "
    "data_at p__addr Tptr p__pre ** "
    "data_at n__addr Tint n__pre ** "
    "data_at i__addr Tint i_v ** "
    "fact(n__pre = &(LENGTH xs)) ** "
    "fact(n__pre <= 2147483647i) ** "
    "fact(0i <= i_v && i_v <= n__pre)"
  )
  while (i < n) {
    $cstar.proof(fill_before_store, "Tchar", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "0i:int");
    p[i] = 0;
    $cstar.proof(fill_after_store, "Tchar", "p__pre:addr", "i_v:int",
                 "n__pre:int", "xs:(int)list", "0i:int");
    i++;
  }
  $cstar.proof(fill_exit, "i_v:int", "n__pre:int", "xs:(int)list", "0i:int");
}

static void show_int(const char *label, int *p, int n) {
  printf("%s", label);
  for (int i = 0; i < n; i++) printf(" %d", p[i]);
  printf("\n");
}

int main(void) {
  int numbers[4] = { 3, 1, 4, 1 };
  char letters[3] = { 'a', 'b', 'c' };
  int empty[1] = { 7 };

  clear_int(numbers, 4);
  clear_char(letters, 3);
  clear_int(empty, 0);

  show_int("numbers:", numbers, 4);
  printf("letters: %d %d %d\n", letters[0], letters[1], letters[2]);
  show_int("empty untouched:", empty, 1);
  return 0;
}
