#include "x2c.x"

$(import "func-cast.xmacro")

int main(void) {
  int (*pointer)(int) = times13;
  Var v = (Func) (%!(int a) => a * 13);
  Func handles[2];
  for (int i = 0; i < 2; i++)
    handles[i] = (Func) (%!(int a) => a * 13);
  printf("%d\n", ((Func) (%!(int a) => a * 13))(3));
  printf("%d\n", ((Func) times13)(3));
  printf("%d\n", ((Func) pointer)(3));
  printf("%d\n", ((Func) v)(3));
  printf("%d\n", handles[0] == handles[1] ? handles[1](3) : 0);
  printf("%d %d %d\n", $(lambda_cast 3), $(named_cast 3), $(var_cast 3));
  printf("%d %d %d\n", lambda_cast(3), named_cast(3), var_cast(3));
  return 0;
}
