#include "x2c.x"

static int outward_defer(void) {
  int value = 0;
  {
    defer value = value * 10 + 2;
    value = 1;
    goto done;
  }
done:
  return value;
}

static int outward_finally(void) {
  int value = 0;
  try {
    value = 1;
    goto done;
  }
  finally {
    value = value * 10 + 2;
  }
done:
  return value;
}

static int same_region(void) {
  int value = 0;
  {
    defer value = value * 10 + 3;
again:
    value++;
    if (value < 2) goto again;
  }
  return value;
}

int main(void) {
  int caught = 0;
  try {
    raise %(invariant);
  }
  catch %(invariant):
    caught = 1;
  int first = outward_defer();
  int second = outward_finally();
  int third = same_region();
  printf("%d %d %d %d\n", first, second, third, caught);
  return first == 12 && second == 12 && third == 23 && caught ? 0 : 1;
}
