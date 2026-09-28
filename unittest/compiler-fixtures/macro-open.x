#include "x2c.x"
#include "meta.x"

static int calls;
static int target(int value) { calls++; return value + 1; }
typedef int Width;

/* An open definition binds `target` and `Width` where it is applied, in
   the unit's global scope, so a caller's same-named local cannot capture
   them. The closed definition keeps its definition-site meaning too; the
   difference shows when a definition travels to another unit. */
macro open Expression $bump(Expr $value) => target((Width) $value);
macro Expression $closed_bump(Expr $value) => target((Width) $value);

meta static List apply_open(List code) {
  Macro bump = $bump;
  return bump(code);
}
macro Expression $open_bump(Expr $code) => $apply_open($code);

int main(void) {
  int target = 33;
  typedef char Width;
  int open_result = $open_bump(target);
  int closed_result = $closed_bump(target);
  printf("%d %d %d %d\n", open_result, closed_result, calls,
         (int) sizeof(Width));
  return 0;
}
