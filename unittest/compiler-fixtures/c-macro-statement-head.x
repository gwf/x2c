#include "x2c.x"

// A macro may supply a statement's head, a whole statement, or a type.
#define FOR_N(i, n) for (int i = 0; i < n; i++)
#define SWAP(a, b) do { int t = a; a = b; b = t; } while (0)
#define INT int

int main(void) {
  INT total = 0, x = 1, y = 2;
  FOR_N(k, 4) total += k;
  SWAP(x, y);
  printf("%d %d %d\n", total, x, y);
  return 0;
}
