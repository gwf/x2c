#include "x2c.x"

/* A for initializer's reference capture survives the loop and its function.
   Split declarations keep their evaluation order and the loop's scope. */
static int order;

static int initial(int mark, int value) {
  order = order * 10 + mark;
  return value;
}

static Func escaped(void) {
  int i = 99;
  Func f = NULL;
  for (int i = initial(1, 0), limit = i + initial(2, 4); i < limit; i++) {
    f = %!() using &i => ++i;
    if (i == 1) continue;
    if (i == 3) break;
  }
  printf("%d %d\n", order, i);
  return f;
}

int main(void) {
  Func last = NULL;
  for (int i = 0; i < 2; i++) last = %!() using &i => i;
  printf("%d\n", last().int());
  Func f = escaped();
  int first = f().int(), second = f().int();
  printf("%d %d\n", first, second);
  return first == 4 && second == 5 && order == 12 ? 0 : 1;
}
