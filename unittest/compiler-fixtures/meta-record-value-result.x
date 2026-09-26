#include "x2c.x"

/* A struct returned by value has no compile-time value, so the call is
   reported before the group stages. */

typedef struct Pair { int a, b; } Pair;

meta static Pair pair(int n) => (Pair) {n, n};

int main(void) { return $pair(1).a; }
