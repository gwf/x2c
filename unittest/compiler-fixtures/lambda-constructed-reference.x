#include "x2c.x"

meta static List raw_reference_of(List value) {
  match (value) {
    case %(expr ? (ident ?binding)): {
      List type = %(& @(Code.type(value)));
      List capture = %(capture $binding $type (expr $type (op & $value)));
      List read = %(expr $(Code.type(value))
        (op * (expr $type (ident $binding))));
      return %(expr ("Func") (lambda (params) (captures $capture) $read));
    }
  }
  return %();
}

macro Expression $raw_reference(Expr $value) => $raw_reference_of($value);

int main(void) {
  int value = 1;
  Func reference = $raw_reference(value);
  value = 2;
  printf("constructed reference=%ld outer=%d\n", reference().integer(),
         value);
  return 0;
}
