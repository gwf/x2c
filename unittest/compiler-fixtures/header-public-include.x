#include "x2c.x"

/* A unit sees the public types and enumerators that
   `header-public-after-function` declares after its functions and static
   declarations, and C compiles that use against the generated header. */
#include "header-public-after-function.x"

int main(void) {
  Box box = {AFTER_FUNCTION};
  enum Color color = GREEN;
  Count count = AFTER_OBJECT;
  struct Pair pair = {REOPENED, 1};
  struct Tally tally = {5};
  Wrapped wrapped = {2};
  printf("%d %d %d %d %d %d %d %d\n", box.v, color, count, pair.a, pair.b,
         tally.total, wrapped.v, ROWS);
  return 0;
}
