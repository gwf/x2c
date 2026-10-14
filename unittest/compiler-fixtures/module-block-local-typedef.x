/* A block-scope typedef shadows a file-private type of the same name, as
   it shadows any file-scope type. */
#include <stdio.h>
module { "module-block-local-typedef/member.x" }
int main(void) { printf("%d\n", test()); return 0; }
