#include "x2c.x"

macro Unit $computed(Expr $value, Name $public) => {
  static $(x2c.syntax.type $value)
  $(x2c.ident "macro_slot_helper")(void) {
    return $value;
  }
  static int $public(void) {
    return $value;
  }
}

macro Unit $through_sequence(Unit $target) => {
  $(list $target)...
}

$through_sequence(int retained = 42;);

$computed(retained, answer);

int main(void) {
  printf("%d\n", answer());
  return 0;
}
