#!/usr/bin/env -S x2c script
// Recovery skips whole declarations before assembling retained statements.
puts("before");
int broken(void) { return 1 +; }
#if 1
puts("between");
#endif
int also_broken(void) { return 2 +; }
puts("after");
