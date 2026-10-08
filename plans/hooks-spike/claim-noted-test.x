#include "claim-noted.x"

/* Run with `x2c run claim-noted.x claim-noted-test.x`; prints
   `declared b = 2` and `3 3`. */

int main(void) {
  int a = 1, b = $noted(2), c = 3;
  Array items = $auto([a, b, c]);
  printf("%d %d\n", c, (int) items.len());
  return 0;
}
