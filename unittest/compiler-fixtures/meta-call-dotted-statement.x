/* A dotted `$` meta call can start a statement: as the type of a declaration
   in a template, and as an expression statement. A visible macro of the same
   name keeps precedence over the meta function. */

#include "x2c.x"
#include "meta.x"

typedef struct Answer { int unused; } Answer;
meta int Answer.value(int base) => base + 40;
meta List Answer.say(void) => $!( puts("say") );
meta int Answer.shadowed(int base) => base;
macro Stmt $Answer.shadowed(Expr $base) { printf("macro %d\n", $base); }

macro Stmt $swap(Expr $left, Expr $right) {
  {
    $Code.type($left) temporary = $left;
    $left = $right;
    $right = temporary;
  }
}

int main(void) {
  int left = 20, right = 22;
  String first = "hello", last = "world";
  $swap(left, right);
  $swap(first, last);
  $Answer.say();
  $Answer.shadowed(2);
  printf("%d %d %s %s %d\n", left, right, first, last, $Answer.value(2));
  return 0;
}
