#include "x2c.x"

/* A store or update nested in the value of another applies the same
   collection rule again, and a read nested in a key applies the read rule
   again. */
int main(void) {
  Array a = [1, 2], b = [3, 4];
  Var stored = (a[0] = (b[1] = 5));
  Var updated = (a[1] += (b[0] += 2));
  Var read = a[b[0].int() - 5];
  printf("%d %d %d %d %d %d %d\n", stored.int(), updated.int(), read.int(),
         a[0].int(), a[1].int(), b[0].int(), b[1].int());
  return 0;
}
