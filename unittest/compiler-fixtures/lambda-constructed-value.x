#include "x2c.x"
macro Expression $held_value() => (
  $(quote (expr ("Func")
    (lambda (params)
      (captures (capture ("held") (int)
        (expr (int) (literal (int) "42"))))
      (expr (int) (ident ("held"))))))
)
int main(void) {
  Func held = $held_value();
  printf("held=%d\n", held().int());
  return 0;
}
