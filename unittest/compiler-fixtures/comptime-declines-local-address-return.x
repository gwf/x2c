/*  comptime-declines-local-address-return.x -- a meta function returns the
    address of its own local

    A compile-time call frees its locals when it returns, so the pointer
    would read freed memory. The region check rejects the definition at the
    return rather than installing it.
*/

#include "x2c.x"

$(import "comptime-declines-local-address-return.xmacro")

int main(void) { return 0; }
