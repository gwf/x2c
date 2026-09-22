/* `sinf` is marker-derived from cmath.x and was not a row in the former
   handwritten evaluator target inventory. */

#include "x2c.x"

int main(int argc, char **argv) {
  (void) argv;
  printf("%.1f %.1f\n", (double) $sinf(0.0f),
         (double) sinf((float) (argc - 1)));
  return 0;
}
