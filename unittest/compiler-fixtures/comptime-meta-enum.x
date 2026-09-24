/*  comptime-meta-enum.x -- enum constants in a `meta` body

    An enumerator of an enum that fits in int has its C value at compile
    time: its initializer, or the previous enumerator plus one. `main`
    prints each value the lowered Lisp produced during translation.
*/

#include "x2c.x"

enum { K = 10 };
enum Color { RED, GREEN, BLUE = 1 << 3, VIOLET, LAST = VIOLET * 2 };

meta int me_k(void) => K;

meta int me_color(int which) {
  switch (which) {
    case 0: return RED;
    case 1: return GREEN;
    case 2: return BLUE;
    case 3: return VIOLET;
  }
  return LAST;
}

int main(void) {
  printf("K      %d\n", $(me_k));
  printf("colors %d %d %d %d %d\n", $(me_color 0), $(me_color 1),
         $(me_color 2), $(me_color 3), $(me_color 4));
  return 0;
}
