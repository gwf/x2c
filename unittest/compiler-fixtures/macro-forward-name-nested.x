#include "x2c.x"

/* A name nothing declares where `$outer` is defined binds the declaration
   its expansion introduces, here the loop variable `$repeat` makes from the
   literal Name `k`. */
macro Stmt $repeat(Name $i, Expr $count, Expr $value, Name $sum) {
  for (int $i = 0; $i < $count; $i++) $sum += $value;
}

macro Stmt $outer(Name $sum) {
  $repeat(k, 3, k * 2, $sum);
}

macro Stmt $declare(Name $name) {
  int $name = 2;
}

macro Stmt $scaled(Name $result) {
  {
    $declare(k);
    $result = k * 3;
  }
}

int main(void) {
  int total = 0, k = 100, scaled = 0;
  $outer(total);
  $scaled(scaled);
  printf("%d %d %d\n", total, scaled, k);
  return total != 6 || scaled != 6 || k != 100;
}
