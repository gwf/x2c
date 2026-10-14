/* A block-scope tag shadows a file-private tag of the same name. */
#include <stdio.h>
module { "module-block-local-tag/a.x", }
int main(void) { printf("%d\n", a_run()); return 0; }
