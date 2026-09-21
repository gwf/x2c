#include "x2c.x"

macro Expression $missing(Expr $value) => $value + 1

int main(void) { return $missing(41); }
