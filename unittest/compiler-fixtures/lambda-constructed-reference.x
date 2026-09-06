#include "x2c.x"

macro Expression $raw_reference(Expr $value) => (
  $(let* ((binding (car (cdr (car (cdr (cdr $value))))))
          (type (cons '& (x2c.syntax.type $value)))
          (address (list 'expr type (list 'op '& $value)))
          (capture (list 'capture binding type address))
          (alias (list 'expr type (list 'ident binding)))
          (read (list 'expr (x2c.syntax.type $value)
                  (list 'op '* alias))))
     (list 'expr '("Func")
       (list 'lambda '(params) (list 'captures capture) read)))
)

int main(void) {
  int value = 1;
  Func reference = $raw_reference(value);
  value = 2;
  printf("constructed reference=%ld outer=%d\n", reference().integer(),
         value);
  return 0;
}
