#include "x2c.x"

macro Expression $increment(Name $value) => ({
  long value = 40;
  (void) value;
  %!() using &$value => ++$value;
});

static int value = 6;

int main(void) {
  Func global = $increment(value);
  int global_result = global();
  printf("%d %d\n", global_result, value);
  {
    int value = 10;
    Func local = $increment(value);
    int local_result = local();
    printf("%d %d\n", local_result, value);
  }
  return 0;
}
