#include "x2c.x"

/* Function typedefs and function-pointer typedefs use the same argument
   conversions and result type as direct calls. */

typedef String (*Namer)(Var value);
typedef String NamerFunction(Var value);

static String name_of(Var value) => value.repr();

int main(void) {
  Namer namer = name_of;
  NamerFunction *function = name_of;
  printf("%s %s %s\n", namer(<a>), namer(42), namer("text"));
  printf("%s %d\n", function(42), function(42).len());
  return 0;
}
