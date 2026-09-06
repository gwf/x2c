#include "x2c.x"

static int sum(int a, int b) {
  return a + b;
}

macro Expression $call(Expr $callee, Expr $arguments...) => (
  $callee($arguments...)
)

macro Unit $same_use(Expr $values...) => {
  static int $(x2c.ident "answer")(void) {
    return sum($values...);
  }
}

macro Statement $swap(Expr $left, Expr $right) using $temporary => {
  $(x2c.syntax.type $left) $temporary = $left;
  $left = $right;
  $right = $temporary;
}

int first = 20;
int second = 22;

$same_use(first, second);

int main(void) {
  int left = 19, right = 23;
  $swap(left, right);
  printf("%d %d %d\n", $call(sum, left, right), answer(),
                      left * 100 + right);
  return 0;
}
