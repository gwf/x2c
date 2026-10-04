#include "x2c.x"
#include "meta.x"

/* A Stmt arrow body is one statement, so it may invoke a Stmt macro or
   decorator, or call a meta function that returns statements. */
macro Stmt $hit(Expr $value) { printf("hit %d\n", $value); }
macro Stmt $forward(Expr $value) => $hit($value);
macro Stmt $forward_next(Expr $value) => $forward($value + 1);
macro Expression $twice(Expr $value) => $value * 2;
macro Stmt $show_twice(Expr $value) => printf("twice %d\n", $twice($value));
macro Decorator $again(Stmt $target) {
  $target
  $target
}
macro Stmt $hit_again(Expr $value) => $again() $hit($value);
meta static List both(List code) => $!{ $code $code };
macro Stmt $doubled(Stmt $code) => $both($code);

int main(void) {
  $forward(1);
  if (1) $forward(2);
  $forward_next(2);
  $show_twice(4);
  $hit_again(5);
  $doubled(puts("both"););
  return 0;
}
