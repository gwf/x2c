#include "x2c.x"
meta static List raw_lambda(void) =>
  %(expr ((func ((int))) "Var")
    (lambda
      (params (param (int) (bind ("value") ())))
      (block
        (declare (int)
          (bindings
            (op = (bind ("value") ())
              (expr (int) (literal (int) "2")))))
        (return ("Var") (expr () (ident ("value")))))));
macro Expression $raw() => $raw_lambda();
Func f = $raw();
