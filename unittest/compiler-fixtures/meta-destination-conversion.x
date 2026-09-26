#include "x2c.x"

typedef unsigned char Byte;

typedef String Label;

$(import "meta-destination-conversion.xmacro")

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
  List items = %(a b c d e f g h i j);
  printf("converter %d %d %d %d %d %d\n",
    $label_init(%(a b c d e f g h i j)), label_init(items),
    $label_assign(%(a b c d e f g h i j)), label_assign(items),
    $label_argument(%(a b c d e f g h i j)), label_argument(items));
  return 0;
}
