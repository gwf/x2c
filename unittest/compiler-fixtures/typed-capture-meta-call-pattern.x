#include "x2c.x"
#include "meta.x"

/* A typed capture in a meta call's pattern argument binds with its type,
   as an untyped one does. */
meta static List declarator(List fields) =>
  %(!or (bind @fields) (op = (bind @fields) ?));

static void show(List row) {
  match (row) {
    case $declarator(%((binding ? ?(String name)) ?)):
      printf("%s %d\n", name, name.len());
    default: printf("other\n");
  }
}

int main(void) {
  show(%(bind (binding 3 "count") ()));
  show(%(op = (bind (binding 4 "total") ()) 7));
  show(%(bind (binding 5 6) ()));
  return 0;
}
