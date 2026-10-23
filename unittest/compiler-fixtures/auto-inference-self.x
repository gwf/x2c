#include "x2c.x"

int main(void) { int value = 1; { auto value = value; (void) value; } return 0; }
