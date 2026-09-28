#include "x2c.x"
macro Expression $raw() =>
  $(quote
    (expr ((func ((int))) "Var")
      (lambda
        (params (param (int) (bind ("value") ())))
        (block
          (declare (int)
            (bindings
              (op = (bind ("value") ())
                (expr (int) (literal (int) "2")))))
          (return ("Var") (expr () (ident ("value"))))))));
Func f = $raw();
