#include "x2c.x"

/* A struct result has no compile-time value, which its type decides, so a
   call at file scope is refused before the unit's group builds and leaves
   no placeholder there for C to reject. The unit's other calls still run. */

typedef struct Pair { int a, b; } Pair;

meta static Pair pair(int n) => (Pair) {n, n};
meta static int one(void) => 1;

int first = $one();
int v = $pair(1).a;

int main(void) { return v - first; }
