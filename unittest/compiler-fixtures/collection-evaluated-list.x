#include "x2c.x"

/* `$(a, b, ...)` in code builds a List of evaluated elements, each once
   and in source order. */
static int next(int n) {
  printf("next %d\n", n);
  return n;
}

int main(void) {
  int x = 1;
  String s = "two";
  printf("%s\n", $().repr());
  printf("%s\n", $(x).repr());
  printf("%s\n", $(x, s, 3.5, <sym>, %(q r),).repr());
  printf("%s\n", $($(x), $(), $($(s))).repr());
  printf("%s\n", $(next(1), next(2), next(3)).repr());
  printf("%s\n", $((next(4), next(5)), x = 9, x > 5 ? "big" : "small").repr());
  printf("%s\n", $(%(a b), [1, 2]).repr());
  printf("equal %d\n", $(1, "a") == %(1 "a"));
  printf("empty %d\n", $() == %());
  return 0;
}
