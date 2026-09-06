#include "x2c.x"

macro Statement $local_alias(Expr $result) => {
  typedef Var Value;
  Value value = (Value) 3;
  if (sizeof(Value) != sizeof(Var)) return 3;
  value += 4;
  $result = value;
}

macro Unit $constructed_alias() => {
  static int $(x2c.ident "constructed")(void) {
    $(quote (
      (typedef ("Var") (bindings (bind ("Value") ())))
      (declare ("Value")
        (bindings (op = (bind ("value") ())
          (expr (int) (literal (int) "8")))))
      (return (int)
        (expr () (cast (decl ("Value") (bindings (bind () ())))
          (expr () (ident ("value"))))))
    ))...
  }
}

$constructed_alias();

int main(void) {
  int result = 0;
  $local_alias(result);
  if (result != 7) return 1;
  if (constructed() != 8) return 2;
  puts("parsed and constructed local aliases agree");
  return 0;
}
