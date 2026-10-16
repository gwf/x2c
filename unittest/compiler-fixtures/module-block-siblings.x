/* A directory entry lists siblings; each sibling keeps its own statics. */
#include <stdio.h>
module { "module-block-siblings/module-block-siblings.x", }
int main(void) { printf("%d %d\n", first(), second()); return 0; }
