/* The enumerators of a static enum are private to its file. */
#include <stdio.h>
module { "module-block-enumerators/a.x", "module-block-enumerators/b.x", }
int main(void) { printf("%d %d\n", a_on(), b_on()); return 0; }
