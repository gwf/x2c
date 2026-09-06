#include "x2c.x"

int main(void) {
  Map scores = %{ one: 1, two: 2 };
  Var key = <one>;
  Var bracket_dynamic = scores[key];
  Var method_dynamic = scores.getindex(key);
  Var bracket_scalar = scores[7];
  Var method_scalar = scores.getindex(7);
  scores[7] = 70;
  scores.setindex(8, 80);
  scores[key] = scores.getindex(key).int() + 10;
  printf("%d %d\n", bracket_dynamic.int(), method_dynamic.int());
  printf("%d %d\n", bracket_scalar is void, method_scalar is void);
  printf("%d %d\n", scores[7].int(), scores.getindex(8).int());
  printf("%d %d\n", scores[key].int(), scores.getindex(<two>).int());
  return 0;
}
