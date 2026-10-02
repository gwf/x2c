#include "x2c.x"

macro Expression $sequenced() => $(begin
  (x2c.diagnostic.warn "sequence warning" (list "sequence note"))
  (x2c.literal.int 7));

macro Expression $nil_value() => $(x2c.literal.int
  (if (null? (x2c.diagnostic.warn "nil warning" nil)) 1 0));

macro Expression $final_warning() => $(let
  ((value (begin 9 (x2c.diagnostic.warn "final warning" nil))))
  (x2c.literal.int (if (null? value) 1 0)));

macro Expression $two() => $(begin
  (x2c.diagnostic.warn "first warning" (list "first note"))
  (x2c.diagnostic.warn "second warning" (list "second note"))
  (x2c.literal.int 11));

int main(void) {
  printf("%d %d %d %d\n", $sequenced(), $nil_value(), $final_warning(),
         $two());
  return 0;
}
