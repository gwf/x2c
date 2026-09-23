/*  comptime-declines-meta-wide-enum.x -- an enum wider than int

    C compilers widen an enum whose values do not fit in int, which moves
    every later field. Compile-time code lays out only an enum whose
    initializers all have int-range types, so a struct holding this one has
    no layout and is refused rather than laid out at the wrong offsets.
*/

#include "x2c.x"

enum Wide { SMALL = 0, WIDE = 0x100000000 };

struct Holder { enum Wide wide; int tail; };

meta int dw_tail(void) {
  struct Holder holder = {0, 9};
  return holder.tail;
}

int main(void) { return 0; }
