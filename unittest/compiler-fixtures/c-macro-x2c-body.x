#include "x2c.x"

// A macro body is translated like any other source, so x2c syntax in it
// works, and an expansion has the type of the expression it spells.
#define GET(c) c.get()
#define COUNT(items) items.len()
#define N 10

typedef struct Box { int v; } *Box;
int Box.get(Box b) => b.v;

int main(void) {
  struct Box box = {7};
  Box b = &box;
  List items = %(1 2 3);
  Var v = N;
  printf("%d %d %d\n", GET(b), COUNT(items), v.int());
  return 0;
}
