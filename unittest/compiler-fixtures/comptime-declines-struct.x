/*  comptime-declines-struct.x -- why a struct is refused at compile time

    A refusal stops translation at the first function, so each deliberate
    decline needs its own fixture. This one checks the wording for a struct
    local; see `plans/comptime-x2c-generalization.md`.
*/

#include "x2c.x"

struct Point { int x, y; };

/* A compile-time value is a Lisp value, and the only thing a struct could
   become is a `Map` keyed by field name. That reads back as a reference
   where the source wrote a value, so the whole shape stays out. */
meta int ct_struct(int n) {
  struct Point p = { .x = n, .y = n + 1 };
  return p.x + p.y;
}

int main(void) { return 0; }
