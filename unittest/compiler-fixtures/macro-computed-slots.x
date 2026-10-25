#include "x2c.x"

/* The spliced declaration supplies `retained`, so the project meta build,
   which leaves `one_item` for the translation, never sees its type. */
meta static List one_item(List target) => %($target);

macro Unit $computed(Expr $value, Name $public) {
  static $Code.type($value)
  $x2c_ident("macro_slot_helper")(void) {
    return $value;
  }
  static int $public(void) {
    return $value;
  }
}

macro Unit $through_sequence(Unit $target) {
  @one_item($target)
}

$through_sequence(int retained = 42;);

$computed(retained, answer);

int main(void) {
  printf("%d\n", answer());
  return 0;
}
