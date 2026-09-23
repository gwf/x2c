#include "x2c.x"

typedef unsigned char Byte;

meta Byte byte_passthrough(Byte value) => value;
meta int accepts_void_pointer(void *value) {
  Var boxed = value;
  return boxed.tag() == <p48>;
}

meta int conditional_float(int n) =>
  (int) ((n ? 1 : 2.5) / 2 * 10);
meta int conditional_unsigned(int n) => (n ? -1 : 1U) < 0;

meta int byte_update(int n) {
  Byte value = n;
  value += 256;
  return byte_passthrough(value);
}

meta int pointer_tag(int n) {
  void *value = &n;
  value = (void *) &n;
  Var boxed = value;
  return boxed.tag() == <p48> && accepts_void_pointer(value);
}

meta int empty_symbol(int n) {
  Symbol value = n - 1;
  return value.first() == 0;
}

meta int conditional_symbol(int n) {
  Symbol value = n ? <word> : 0;
  return value == <word>;
}

meta int composed_hash(String value) => value.hash() != 0;

int main(int argc, char **argv) {
  (void) argv;
  int one = argc;
  printf("float %d %d %d\n",
    $conditional_float(1), conditional_float(1), conditional_float(one));
  printf("unsigned %d %d %d\n",
    $conditional_unsigned(1), conditional_unsigned(1),
    conditional_unsigned(one));
  printf("byte %d %d %d\n",
    $byte_update(1), byte_update(1), byte_update(one));
  printf("pointer %d %d %d\n",
    $pointer_tag(1), pointer_tag(1), pointer_tag(one));
  printf("symbol %d %d %d\n",
    $empty_symbol(1), empty_symbol(1), empty_symbol(one));
  printf("conditional-symbol %d %d %d %d %d %d\n",
    $conditional_symbol(1), conditional_symbol(1),
    conditional_symbol(one), $conditional_symbol(0),
    conditional_symbol(0), conditional_symbol(one - 1));
  printf("hash %d %d %d\n",
    $composed_hash("word"), composed_hash("word"),
    composed_hash(argc ? "word" : ""));
  return 0;
}
