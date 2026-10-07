#include "x2c.x"

macro Expression $made(Param @params) => %!(@params) => 41;

macro Expression $nested() =>
  $(quote
    (expr ((func ((int))) "Var")
      (lambda
        (params (param (int) (bind ("value") ())))
        (block
          (block
            (declare (int)
              (bindings
                (op = (bind ("value") ())
                  (expr (int) (literal (int) "2"))))))
          (return ("Var") (expr () (ident ("value"))))))));

static int ordinary(int value) {
  { int value = 2; (void) value; }
  return value;
}

int main(void) {
  Func bare = %!(value) => {
    { int value = 2; (void) value; }
    return value;
  };
  Func typed = %!(int value) => {
    { int value = 2; (void) value; }
    return value;
  };
  Func constructed = $nested();
  Func templated = $made(int value);
  printf("%d %d %d %d %d\n", ordinary(7), bare(8).int(), typed(9).int(),
         constructed(10).int(), templated(11).int());
  return 0;
}
