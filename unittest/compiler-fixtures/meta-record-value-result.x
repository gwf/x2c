#include "x2c.x"

/* A struct returned by value has no compile-time value, so the call is
   reported before the group stages. */

typedef struct Pair { int a, b; } Pair;

$(import "meta-record-value-result.xmacro")

int main(void) { return $pair(1).a; }
