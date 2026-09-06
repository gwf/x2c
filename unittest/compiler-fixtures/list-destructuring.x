#include "x2c.x"

static int calls = 0;

static List values(void) {
  calls++;
  return %(1 2 3 4);
}

int main(void) {
  int user_destructure_0 = 9;
  Var (a, b, c) = values();
  int (x, y) = values();
  (int mixed_i, float mixed_x, char mixed_c) = %(5 6.5 ${'m'});
  Var first, missing;
  (first, missing) = %(7);
  (c) = values();
  List source = values();
  List result = (a, b) = source;
  printf("%ld %ld %ld %d %d %d %.1f %c %ld %d %d %d\n",
         a.integer(), b.integer(), c.integer(), x, y,
         mixed_i, mixed_x, mixed_c, first.integer(), missing is void,
         result === source, calls);
  return user_destructure_0 == 9 && calls == 4 ? 0 : 1;
}
