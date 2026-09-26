/*  comptime-declines-local-address-callee.x -- a meta function returns an
    address of its own local that a callee handed back

    `field_of` returns an address inside its parameter's object, and its
    summary says so, so the caller's `return` is the escape.
*/

#include "x2c.x"

struct Box { int value; };

$(import "comptime-declines-local-address-callee.xmacro")

int main(void) { return 0; }
