#include "x2c.x"

static int calls;
static int next(void) { return ++calls; }
static int *inferred(int input, size_t *size, int *counter) {
  static int values[] = {[__COUNTER__] = input, next()};
  *size = sizeof(values) / sizeof(values[0]);
  *counter = __COUNTER__;
  return values;
}
static void *address(void) { next(); return &calls; }
static void **self(void) {
  static void *values[] = {(void *)values, address()};
  return values;
}
static int constant_argument(const int input) {
  static const int value = input;
  return value;
}
int main(void) {
  size_t size;
  int counter;
  int *a = inferred(17, &size, &counter), *b = inferred(99, &size, &counter);
  void **same = self();
  int first = constant_argument(23), second = constant_argument(99);
  printf("%d %zu %d %d %d %d %d %d %d\n", a == b, size, a[0], a[1],
    counter, same[0] == same, calls, first, second);
  return 0;
}
