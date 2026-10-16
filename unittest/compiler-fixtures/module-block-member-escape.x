/* Parent traversal is resolved relative to the file containing the block. */
#include <stdio.h>
module { "module-block/../module-block/implementation.x", }
int main(void) { printf("%d\n", helper(41)); return 0; }
