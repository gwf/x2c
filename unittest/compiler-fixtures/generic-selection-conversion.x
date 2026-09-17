/* A generic selection has no x2c type of its own. Each association converts
   to the destination, so the selected arm reaches a named value type instead
   of staying a raw C value. */
#include "x2c.x"

int main(void) {
  char *text = "hello";
  int count = 1;
  String named = _Generic(text, char *: "charp", default: "other");
  String other = _Generic(count, char *: "charp", default: "other");
  Var boxed = _Generic(text, char *: 1, default: 2);
  int plain = _Generic(count, char *: 10, default: 20);
  printf("%s %d\n", named.str(), named.len());
  printf("%s %d\n", other.str(), other.len());
  printf("%ld %d\n", (long) boxed.int(), plain);
  return 0;
}
