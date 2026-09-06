#include "x2c.x"
#include "foreign-qualifier-upstream.h"

int main(void) {
  char *label = upstream_monitor_at(1)->label;
  label[0] = 'R';
  printf("%s\n", label);
  return 0;
}
