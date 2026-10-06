/* A meta static initializer that raises on reset fails the requesting
   compile-time call instead of leaving the earlier value in place. */
#include "x2c.x"

static int calls = 0;

static int init(void) {
  if (++calls > 0) raise %(bad-init);
  return 7;
}

meta static int value = init();
meta int meta_reset_read(void) => value;

int n = $meta_reset_read();
