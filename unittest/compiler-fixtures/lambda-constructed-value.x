#include "x2c.x"
meta static List held_lambda(void) =>
  %(expr ("Func")
    (lambda (params)
      (captures (capture ("held") (int)
        (expr (int) (literal (int) "42"))))
      (expr (int) (ident ("held")))));
macro Expression $held_value() => $held_lambda();
int main(void) {
  Func held = $held_value();
  printf("held=%d\n", held().int());
  return 0;
}
