#include "x2c.x"

macro Expression $forward(Expr $value) => $auto($value);
int main(void) { auto int value = $forward(1); return value; }
