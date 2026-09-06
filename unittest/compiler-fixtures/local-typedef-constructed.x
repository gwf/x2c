#include "x2c.x"

typedef int Base;

static int increment(int value) => value + 1;

macro Unit $constructed_types() => {
  static int $(x2c.ident "constructed_types")(void) {
    $(quote (
      (typedef (int) (bindings (bind ("Count") ())))
      (typedef (int)
        (bindings (bind ("Callback")
          (* (fnmod (params (param ("Count") (bind () ()))))))))
      (declare ("Callback")
        (bindings (op = (bind ("callback") ())
          (expr () (ident ("increment"))))))
      (return (int) (expr ()
        (call (expr () (ident ("callback")))
          (args (expr (int) (literal (int) "7"))))))
    ))...
  }
}

macro Expression $constructed_capture(Expr $value) => (
  $(let* ((binding (car (cdr (car (cdr (cdr $value))))))
          (type (x2c.syntax.type $value)))
    `(expr ("Func")
      (lambda (params)
        (captures (capture ,binding ,type ,$value))
        ,$value)))
)

macro Expression $constructed_reference(Expr $value) => (
  $(let* ((binding (car (cdr (car (cdr (cdr $value))))))
          (value-type (x2c.syntax.type $value))
          (type (cons '& value-type))
          (address `(expr ,type (op & ,$value)))
          (read `(expr ,value-type
                   (op * (expr ,type (ident ,binding))))))
     `(expr ("Func")
       (lambda (params)
         (captures (capture ,binding ,type ,address))
         ,read)))
)

$constructed_types();

int main(void) {
  typedef int LocalCount;
  LocalCount value = 9;
  Func captured = $constructed_capture(value);
  value = 10;
  if (constructed_types() != 8 || captured() != 9) return 1;
  typedef Base Alias;
  Alias referent = 1;
  {
    typedef double Base;
    Base fraction = 0.5;
    Func reference = $constructed_reference(referent);
    referent = 2;
    if (reference() != 2 || fraction != 0.5) return 2;
  }
  puts("constructed declarations and resolved capture types preserve scope");
  return 0;
}
