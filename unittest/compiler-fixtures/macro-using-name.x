#include "x2c.x"
#include "meta.x"

static int calls;
static int target(int value) { calls++; return value + 1; }

/* `using target` keeps the file-scope function named where the macro is
   written, so a caller's local `target` does not supply it, including when
   the macro is applied as a value. A free name without `using` keeps it
   too. A `Name` argument reads the caller's binding. */
macro Expression $bump(Expr $value) using target => target($value);
macro Expression $bump_free(Expr $value) => target($value);
macro Expression $read_name(Name $name) => $name;

meta static List apply_bump(List code) {
  Macro bump = $bump;
  return bump(code);
}
macro Expression $value_bump(Expr $code) => $apply_bump($code);

int main(void) {
  int target = 33;
  int direct = $bump(target);
  int through_value = $value_bump(target);
  int free = $bump_free(target);
  int landed = $read_name(target);
  printf("%d %d %d %d %d\n", direct, through_value, free, landed, calls);
  return 0;
}
