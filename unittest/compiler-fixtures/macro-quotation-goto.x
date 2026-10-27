#include "x2c.x"
#include "meta.x"

meta List jump(Var target) => $!{ goto $target; };

macro Stmt $skip(Stmt $body) {
  using $done;
  $jump($done);
  $body
  $done:
  ;
}

int main(void) {
  int value = 1;
  $skip(value = 2;);
  $skip(value = 3;);
  printf("%d\n", value);
  return value != 1;
}
