#include "x2c.x"

// The variadic argument keeps its commas. GNU C's `, ## __VA_ARGS__`
// drops the comma when it is empty, and `__VA_OPT__` holds its tokens
// only when it is not.
#define LOG(fmt, ...) printf(fmt "\n", ##__VA_ARGS__)
#define SHOW(...) printf("%s\n", #__VA_ARGS__)
#define FIRST(a, ...) a
#define OPT(fmt, ...) printf(fmt __VA_OPT__(,) __VA_ARGS__)

int main(void) {
  LOG("none");
  LOG("%d %d", 1, 2);
  SHOW(a, b,  c);
  printf("%d\n", FIRST(7, 8, 9));
  OPT("opt\n");
  OPT("opt %d\n", 5);
  return 0;
}
