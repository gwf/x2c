#include "x2c.x"
#include "meta.x"

static int calls;
static int target(int value) { calls++; return value + 1; }

/* `using target` keeps the file-scope function named where the macro is
   written, so a caller's local `target` does not supply it, including when
   the macro is applied as a value. A free name without `using` resolves
   where the expansion lands. */
macro Expression $bump(Expr $value) using target => target($value);
macro Expression $read_target() => target;

meta static List apply_bump(List code) {
  Macro bump = $bump;
  return bump(code);
}
macro Expression $value_bump(Expr $code) => $apply_bump($code);

int main(void) {
  int target = 33;
  int direct = $bump(target);
  int through_value = $value_bump(target);
  int landed = $read_target();
  printf("%d %d %d %d\n", direct, through_value, landed, calls);
  return 0;
}
