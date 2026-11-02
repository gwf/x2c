#include "x2c.x"

static Var same(Var value) => value;

int main(void) {
  String text = "word";
  for (int present = 0; present != 2; present++) {
    Var left = present ? text : NULL, right = present ? NULL : text;
    Var grouped = present ? (text) : (NULL);
    Var zero_first = present ? 0 : text;
    printf("%s %s %s %s\n", left.repr(), right.repr(),
           grouped.repr(), zero_first.repr());
  }
  Func f = same;
  printf("%s %s %s\n", same(NULL).repr(), f((void *) 0).repr(), f(NULL).repr());
  printf("%d %d\n", "ell" in "hello", "z" in ("hello"));
  return 0;
}
