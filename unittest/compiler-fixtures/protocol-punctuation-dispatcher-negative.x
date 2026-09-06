#include "x2c.x"

static int rhs_calls;

static int rhs(void) {
  rhs_calls++;
  return 1;
}

int main(void) {
  uchar byte_zero = 0, byte_one = 1;
  uint word_zero = 0, word_one = 1;
  int branch = 0;
  if (byte_zero) branch++;
  if (word_one) branch += 2;
  int byte_false = byte_zero && rhs();
  int byte_true = byte_one && rhs();
  int word_false = word_zero && rhs();
  int word_true = word_one && rhs();
  int byte_zero_dot = byte_zero.truth();
  int byte_one_dot = byte_one.truth();
  int word_zero_dot = word_zero.truth();
  int word_one_dot = word_one.truth();
  int byte_equal_dot = byte_zero.equal(byte_one);
  int word_equal_dot = word_one.equal((uint) 1);
  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    branch, byte_false, byte_true, word_false, word_true, rhs_calls,
    byte_zero == byte_one, word_one == 1,
    byte_zero_dot, byte_one_dot, word_zero_dot, word_one_dot,
    byte_equal_dot, word_equal_dot
  );
  return 0;
}
