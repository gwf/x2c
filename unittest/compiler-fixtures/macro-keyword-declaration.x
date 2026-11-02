#include "x2c.x"

/* A keyword alias may name a Declaration macro, whose invocation stays a
   file-scope declaration as the macro's own spelling does. */
macro Declaration $counted(Name $name, Expr $value) {
  int $name(void) { return $value; }
}
keyword counted $counted;

counted(seven, 7);
$counted(eight, 8);

int main(void) {
  printf("%d %d\n", seven(), eight());
  return 0;
}
