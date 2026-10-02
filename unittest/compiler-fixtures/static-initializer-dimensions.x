#include "x2c.x"

static int calls;
static int next(void) { return ++calls + 2; }

static int dimensions(void) {
  int values[({ static int size = next(); size; })];
  int (*pointer)[({ static int size = next(); size; })] = NULL;
  return sizeof(values) / sizeof(*values)
    + sizeof(*pointer) / sizeof(**pointer);
}

int main(void) {
  int first = dimensions(), second = dimensions();
  printf("%d %d %d\n", first, second, calls);
  return 0;
}
