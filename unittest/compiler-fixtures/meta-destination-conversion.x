#include "x2c.x"
#include "autodiff.x"

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
meta int constant_string_hash(void) =>
  "abc".hash() == ("a" + "bc").hash();

/* No meta producer makes a File yet, so only the run-time call exercises
   the round trip; the body still installs as a meta function. */
meta int file_round_trip(Var boxed) {
  Var again = boxed.file();
  return again == boxed;
}

/* A boxed <adnode> unboxes to the same node. */
meta int adnode_round_trip(int n) {
  struct AdNode node = {.value = 2.5};
  Var boxed = AdNode.var(&node);
  return (int) (boxed.adnode().value * 2) + n;
}

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
  printf("hash-constant-string %d %d %d\n",
    $constant_string_hash(), constant_string_hash(),
    "abc".hash() == ("a" + "bc").hash());
  printf("file %d\n", file_round_trip(File.var(stdout)));
  printf("adnode %d %d %d\n",
    $adnode_round_trip(0), adnode_round_trip(0), adnode_round_trip(one - 1));
  return 0;
}
