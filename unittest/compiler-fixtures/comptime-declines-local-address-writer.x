/*  comptime-declines-local-address-writer.x -- a meta function returns the
    Buffer that a container writer handed back

    `write_str`, `write_repr` and the Buffer writers return their Buffer
    argument, so returning a parameter Buffer through them is allowed, and
    returning a local Buffer's address through them is the escape.
*/

#include "x2c.x"

$(import "comptime-declines-local-address-writer.xmacro")

int main(void) { return 0; }
