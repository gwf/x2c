#include "x2c.x"

static long add(long left, long right) {
  return left + right;
}

/* A pointer held in a variable carries no target the compiler can adapt.
   Under libffi this fell back to a raw binding; there is no fallback now. */
int main(void) {
  long (*chosen)(long, long) = add;
  Func indirect = Func.new(chosen, %((func ((long) (long))) long));
  return !indirect;
}
