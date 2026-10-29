#include "x2c.x"

#define BLANK
#define MARK(...) 0 __VA_OPT__(+ 1)
#define JOIN(...) pre ## __VA_OPT__(fix)
#define SUFFIX fix
#define PARAM(x, ...) pre ## __VA_OPT__(x)
int pre = 3, prefix = 7;

int main(void) {
  printf("%d %d %d %d %d %d\n", MARK(BLANK), MARK(x), JOIN(x),
         JOIN(BLANK), JOIN(), PARAM(SUFFIX, x));
  return 0;
}
