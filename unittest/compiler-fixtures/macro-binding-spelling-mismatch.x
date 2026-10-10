#include "x2c.x"

macro Expression $spelling(Expr $value) =>
  $(Code.binding_spelling
    (list 'binding
      (car
        (cdr
          (car (cdr (car (cdr (cdr $value)))))))
      "forged"));

int value = $spelling(value);
