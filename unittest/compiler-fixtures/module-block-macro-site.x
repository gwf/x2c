/* A free name in a macro body binds where the expansion lands, so each
   file reads its own static. */
#include <stdio.h>
module { "module-block-macro-site/a.x", "module-block-macro-site/b.x", }
static int counter = 100;
int main(void) { printf("%d %d %d\n", a_read(), b_read(), $read.counter()); return 0; }
