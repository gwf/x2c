#include "x2c.x"

/* A call through a typedef of a function pointer converts each argument to
   its declared parameter, as a direct call does. */

typedef String (*Namer)(Var value);

static String name_of(Var value) => value.repr();

int main(void) {
  Namer namer = name_of;
  printf("%s %s %s\n", namer(<a>), namer(42), namer("text"));
  return 0;
}
