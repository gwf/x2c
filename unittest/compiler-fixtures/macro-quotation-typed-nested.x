#include "x2c.x"
#include "meta.x"

/* A typed quotation inside a quotation is written as a hole,
   `${$!int{ $b }}`, so that it builds its code first. */
meta static List plus_one(List b) => $!( $!int{ $b } + 1 );

int main(void) { return 0; }
