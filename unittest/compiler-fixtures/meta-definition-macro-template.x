/* A macro cannot produce a bodied meta function. */

#include "x2c.x"

macro Unit $make_meta() { meta int made_meta(int x) { return x; } }

int main(void) { return 0; }
