#include "x2c.x"

macro Expression $literal_only(Literal $value) => ($value)

int input = 1;
int value = $literal_only(input);
