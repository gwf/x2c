/* A String switch in a public inline function calls a helper with external
   linkage, named for its unit, so a unit that includes the function's
   header links to it, and units with such helpers link together. The
   switch in a static function keeps a static helper. */
#include "string-switch-inline-kinds.x"

inline int code(String s) {
  switch (s) {
    case "b": return 20;
    case "a": return 10;
  }
  return 0;
}

static int private_code(String s) {
  switch (s) {
    case "b": return 200;
    case "a": return 100;
  }
  return 0;
}

int main(void) {
  printf("%d %d %d %d %d\n", kind("b"), kind("z"), code("a"), code("b"),
         private_code("a"));
  return 0;
}
