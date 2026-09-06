#include "x2c.x"
#include "foreign-qualifier-upstream.h"

int main(void) {
  char *label = upstream_monitor_label(0);
  label[0] = 'L';
  printf("%s\n", label);
  return 0;
}
