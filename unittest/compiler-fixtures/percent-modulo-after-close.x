#include "x2c.x"

/* After a `)` or `]` that ends an operand, and after the `}` of a compound
   literal, `%(` and `%!` stay modulo. Each line prints the spaced form
   beside the unspaced one. */

static int twice(int x) => 2 * x;

int main(void) {
  int a = 7, b = 5, y = 4, n = 3, arr[] = {10, 11};
  printf("%d %d\n", (a + b) % 5, (a + b) %(5));
  printf("%d %d\n", a % (y), a %(y));
  printf("%d %d\n", (a) % (b), (a) %(b));
  printf("%d %d\n", arr[1] % n, arr[1] %(n));
  printf("%d %d\n", twice(a) % 4, twice(a) %(4));
  printf("%d %d\n", (a) % !0, (a) %!0);
  printf("%d %d\n", (int){9} % (y), (int){9} %(y));
  return 0;
}
