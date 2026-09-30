/* Retain a bound meta call through every destructuring source template. */
#include "x2c.x"
#include "meta.x"

meta static List counted_pair(int seed, int *calls) {
  if (seed < 0) x2c_diagnostic_fail("negative", %("counted_pair"));
  (*calls)++;
  return %($seed ${seed + 1});
}

meta static int typed(int seed) {
  int calls = 0;
  (int x, int y) = counted_pair(seed, &calls);
  return x + y + 100 * calls;
}

meta static int named(int seed) {
  int calls = 0;
  int (x, y) = counted_pair(seed, &calls);
  return x + y + 100 * calls;
}

meta static int discarded(int seed) {
  int calls = 0, x, y;
  (x, y) = counted_pair(seed, &calls);
  return x + y + 100 * calls;
}

meta static int value(int seed) {
  int calls = 0;
  Var x, y;
  List result = (x, y) = counted_pair(seed, &calls);
  return (int) x + (int) y + result.len() + 100 * calls;
}

static List ordinary_pair(int *calls) {
  (*calls)++;
  return %(42 43);
}

int main(void) {
  printf("typed %d\n", $typed(42));
  printf("named %d\n", $named(42));
  printf("discarded %d\n", $discarded(42));
  printf("value %d\n", $value(42));
  int calls = 0;
  Var x, y;
  List result = (x, y) = ordinary_pair(&calls);
  printf("ordinary %d %d %d\n",
    (int) x + (int) y, calls, result.len());
  return 0;
}
