// A `meta` function that an included unit exports is callable here.
#include "meta-import-included/bridge.x"

int value(void) { return $twice(4); }
