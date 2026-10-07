#include "x2c.x"
#include "meta.x"

int main(void) { List xs = %(1 2); List code = $!( f(${xs}...) ); return 0; }
