#include "x2c.x"

/* A typed callback adapter returns its callback type's exact result type, so
   a `const` pointer result stays `const`. */

typedef const char *(*Namer)(Var);

static const char *name_of(Symbol value) {
  return value == <yes> ? "yes" : "no";
}

static Namer namer = $x2c.callback.adapt(Namer, name_of);

int main(void) {
  Var answer = <yes>;
  printf("%s\n", namer(answer));
  return 0;
}
