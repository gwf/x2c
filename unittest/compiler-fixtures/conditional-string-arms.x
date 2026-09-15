#include "x2c.x"
#include <string.h>

/* A conditional converts arm by arm. A C string arm beside a String arm, or
   in a String initializer, becomes a canonical String, and a Var arm makes
   the whole conditional a Var. */

int main(int argc, char **argv) {
  String name = argc > 5 ? String.new(argv[0]) : "fallback";
  String joined = %"$name/child";
  String parent = argc > 5 ? NULL : "root";
  printf("%s %d %s %s\n", name, name.len(), joined, parent);
  List args = %("x" "y"), none = NULL;
  String first = args ? args.car() : %"world";
  String other = none ? none.car() : %"world";
  Var mixed = argc > 5 ? args.car() : %"text";
  printf("%s %s %s\n", first, other, mixed.str());
  String program = argc > 5 ? %"never" : argv[0];
  printf("%d\n", program.len() == (int) strlen(argv[0]));
  return 0;
}
