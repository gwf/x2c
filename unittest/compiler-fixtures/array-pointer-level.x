/* An Array is a pointer to a struct, so it does not convert to a pointer
   to a pointer: an Array literal in the initializer of a
   `const char *const *` field is a type error at its source line. */

#include "x2c.x"

typedef struct Holder { const char *const *names; int count; } Holder;

int main(void) {
  Holder h = { ["a", "bb"], 2 };
  return h.count;
}
