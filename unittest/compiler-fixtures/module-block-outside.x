/* A module may name members outside a same-named companion directory. */
#include <stdio.h>
module { "module-block/implementation.x", }
int main(void) { printf("%d\n", helper(41)); return 0; }
