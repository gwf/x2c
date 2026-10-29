#include "x2c.x"
#include "c-macro-module-header/header.h"

MODULE_MEMBERS
int main(void) { printf("%d\n", member()); return 0; }
