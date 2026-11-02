#include "x2c.x"

/* A consumer completes a chain whose stage is called through a function
   pointer, as it completes a direct call: through a typedef, a declared
   pointer, a struct field, and a dereferenced pointer. */

typedef Iter (*Stage)(Iter source, Iter dest);
typedef struct Stages { Stage first; } Stages;

static Iter pass(Iter source, Iter dest) => source.iter(dest);

int main(void) {
  List xs = %(1 2 3);
  Stage stage = pass;
  Iter (*plain)(Iter source, Iter dest) = pass;
  Stages stages = {.first = pass};
  printf(
    "%d %s %d %d\n", stage(xs.iter()).count(), plain(xs.iter()).list().repr(),
    stages.first(xs.iter()).sum(), (*plain)(xs.iter()).count());
  return 0;
}
