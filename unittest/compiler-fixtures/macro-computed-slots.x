#include "x2c.x"

/* `retained` is declared directly: when the spliced declaration supplies it,
   the meta group emits `macro_slot_helper` without a type, as
   unittest/STATUS.md records. */
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

$through_sequence(int spliced = 1;);

int retained = 41;

$computed(retained, answer);

int main(void) {
  printf("%d\n", answer() + spliced);
  return 0;
}
