#include "x2c.x"

$(import "optional-reference-meta.xmacro")

/* The runtime call keeps the C form of the optional references. */
int main(void) { return $exercise(3) != 50 || exercise(3) != 50; }
