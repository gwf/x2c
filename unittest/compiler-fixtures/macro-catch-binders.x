#include "x2c.x"

/* A template's catch arm binds its captures through that expansion's own
   handler, once per expansion. */
macro Stmt $caught(Expr $code, Expr $number, Expr $result) {
  try raise %($code (value ${$number}));
  catch %(?cause (value ?value) *rest):
    $result = cause == $code && value == $number && !rest ? value : -1;
}

static macro Unit $catch_function(Name $name) {
  static int $name(void) {
    try raise %(probe (value 5));
    catch %(?cause (value ?value) *rest):
      return cause == <probe> && value == 5 && !rest ? value : -1;
    return -1;
  }
}

$catch_function(unit_caught);

int main(void) {
  int first = 0, second = 0;
  $caught(<probe>, 3, first);
  $caught(<other>, 4, second);
  printf("%d %d\n", first, second);
  return first != 3 || second != 4 || unit_caught() != 5;
}
