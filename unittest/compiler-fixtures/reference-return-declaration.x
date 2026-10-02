#include "x2c.x"

int value = 3;
static int &alias(void) { return value; }

int main(void) { return 0; }
