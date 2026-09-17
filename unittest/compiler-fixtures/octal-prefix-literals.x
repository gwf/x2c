#include <stdio.h>

int main(void) {
  int plain = 0o17;
  unsigned suffixed = 0o17u;
  long upper = 0O17L;
  int binary = 0b101;
  int *pair = (int[0o2]){0o1, 0o2};
  printf("%d %u %ld %d %zu\n", plain, suffixed, upper, binary,
         sizeof (int[0o3]) / sizeof (int));
  printf("%d\n", pair[0] + pair[1]);
  return 0;
}
