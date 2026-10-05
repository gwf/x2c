#include "x2c.x"
#include <stddef.h>

struct WideLayout {
  char padding[5000000000UL];
  char last;
};

int main(void) {
  Var size = sizeof(char[5000000000UL]);
  Var offset = offsetof(struct WideLayout, last);
  char bytes[8];
  Var forward = &bytes[7] - &bytes[0];
  Var backward = &bytes[0] - &bytes[7];
  printf("%ld %ld %ld %ld\n", size.integer(), offset.integer(),
         forward.integer(), backward.integer());
  Var signed_native = (ptrdiff_t) 0, unsigned_native = (size_t) 0;
  printf("%d %d\n", forward.tag() == signed_native.tag(),
         size.tag() == unsigned_native.tag());
  return 0;
}
