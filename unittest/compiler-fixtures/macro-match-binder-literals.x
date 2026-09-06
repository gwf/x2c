#include "x2c.x"

macro Expression $binder_literals(Expr $value, Expr $items...) => (
  ($value, %(literal ?__macro_expression_value
                     *__macro_splice_items))
)

int main(void) {
  List result = $binder_literals(0, 1, 2);
  List expected = %(literal ?__macro_expression_value
                            *__macro_splice_items);
  printf("%s\n", result.repr().str());
  return result == expected ? 0 : 1;
}
