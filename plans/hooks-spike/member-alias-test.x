#include "x2c.x"
#include "member-alias.x"

typedef struct Inner { int v; } Inner;
static int Inner.get(Inner i) { return i.v; }
typedef struct Outer { Inner inner; } Outer;
typedef struct Part { int value; } Part;
static int Part.read(Part p) { return p.value; }
typedef struct Both { delegate Part part; Inner inner; } Both;

int main(void) {
  int unused = $alias_member("Outer", "fetch", "inner", "get");
  Outer o = { { 7 } };
  Both b = { { 5 }, { 6 } };
  printf("%d %d %d\n", o.fetch(), b.read(), unused);
  return 0;
}
