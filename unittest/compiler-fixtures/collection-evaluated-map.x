#include "x2c.x"

/* `${key: value}` evaluates each key and value once, in source order. A
   natural Map reads a bare key as an Atom, and a quoted Map quotes both. */
static String note(String text) {
  printf("note %s\n", text);
  return text;
}

macro Entry $pair(Expr $k, Expr $v) {
  $k: $v
}
macro Entry $twice(Expr $k, Expr $v) {
  $k: $v,
  $v: $k
}

int main(void) {
  String key = "answer";
  int n = 42;
  printf("%s\n", {key: n}.repr());
  printf("%s\n", %{key: n}.repr());
  printf("%s\n", ${key: n}.repr());
  printf("%s\n", ${<key>: n}.repr());
  printf("%s\n", ${}.repr());
  printf("%s\n", ${note("a"): note("b"), note("c"): note("d"),}.repr());
  printf("%s\n", ${key: 1, key: 2}.repr());
  printf("%s\n", ${key: {key: n}, n: ${key: n}}.repr());
  printf("%s\n", %(row ${key: n} {key: n}).repr());
  printf("%s\n", %[${key: n}, {key: n}].repr());
  printf("%s\n", $(${key: n}, {key: n}).repr());
  printf("%s\n", %"map: $(${key: n})");
  printf("%s\n", ${$pair(key, n), $twice(key, "v")}.repr());
  Map a = ${key: n}, b = ${key: n};
  printf("fresh %d equal %d\n", (void *) a != (void *) b, a == b);
  return 0;
}
