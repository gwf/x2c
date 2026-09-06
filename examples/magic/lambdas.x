/*  lambdas.x -- Demonstrate expression lambda literal forms in X2C.

    Invokes the runtime-generated helpers for no-arg, bare-parameter, and
    typed-parameter lambdas, then returns and invokes a captured Func.
*/


#include <stdio.h>

static Func add_to(int bias) {
  return %!(int value) => value + bias;
}

int main(void) {
  int no_arg = Var_integer((%!() => 42)());
  int bare_identity = Var_integer((%!(x) => x.int())(7));
  int bare_first = Var_integer((%!(a, b) => a.int())(1, 2));

  int typed_identity = Var_integer((%!(int x) => x)(41));
  int typed_first = Var_integer((%!(int a, int b) => a)(1, 2));
  Func add_three = add_to(3);

  printf("no-arg: %d\n", no_arg);
  printf("bare identity: %d\n", bare_identity);
  printf("bare first: %d\n", bare_first);
  printf("typed identity: %d\n", typed_identity);
  printf("typed first: %d\n", typed_first);
  printf("captured: %ld\n", add_three(4).integer());

  return 0;
}
