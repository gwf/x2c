#include "x2c.x"

static int observed;

static int local_latest(void) {
  int value = 7;
  defer observed = value;
  value = 42;
  return value;
}

static int global_only(void) {
  defer observed++;
  return observed;
}

int main(void) {
  int result = local_latest(), before = global_only();
  printf("%d %d %d\n", result, before, observed);
  return result == 42 && before == 42 && observed == 43 ? 0 : 1;
}
