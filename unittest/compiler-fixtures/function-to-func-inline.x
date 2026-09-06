#include "x2c.x"

typedef long (*InlineBinary)(long, long);

static long add(long left, long right) {
  return left + right;
}

inline Func inline_direct(void) {
  return add;
}

inline Func inline_pointer(InlineBinary pointer) {
  return pointer;
}

inline Func inline_noncapturing(void) {
  return %!(long value) => value + 1;
}

inline Func inline_capturing(long bias) {
  return %!(long value) => value + bias;
}

int main(void) {
  if (inline_direct()(20, 22).integer() != 42) return 1;
  if (inline_pointer(add)(20, 22).integer() != 42) return 2;
  if (inline_noncapturing()(41).integer() != 42) return 3;
  if (inline_capturing(2)(40).integer() != 42) return 4;
  printf("42\n");
  return 0;
}
