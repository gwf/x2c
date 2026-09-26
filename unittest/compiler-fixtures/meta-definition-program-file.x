/* A bodied meta function belongs in an .xmacro import, not a program. */

#include "x2c.x"

meta int program_meta(int x) => x + 1;

int main(void) { return 0; }
