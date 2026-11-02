#include "x2c.x"

/* A parenthesized indexed target stores and updates through its
   collection, as the bare target does. */

int main(void) {
  Map m = {"a": 1};
  Array a = [1, 2];
  (m["a"]) += 4;
  (a[0]) += 1;
  (m["a"])++;
  --(a[1]);
  ((m["b"])) = 7;
  printf("%s %s\n", m.repr(), a.repr());
  return 0;
}
