#include "x2c.x"

int main(void) {
#define LOCAL_VALUE 7
  int value = LOCAL_VALUE;
#if LOCAL_VALUE == 7
  value += 30;
#endif
  printf("%d\n", value);
  int result = value == 37 ? 0 : 1;
#undef LOCAL_VALUE
  return result;
}
