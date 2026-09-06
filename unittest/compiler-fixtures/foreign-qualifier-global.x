#include "x2c.x"
#include "foreign-qualifier-upstream.h"

int main(void) {
  char *version = upstream_version;
  version[0] = 'U';
  printf("%s\n", version);
  return 0;
}
