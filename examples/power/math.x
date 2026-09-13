/*  math.x -- lazy numeric pipelines */


int main(void) {
  Scope.retain();

  printf("odd squares: %d\n", range(1, 10, 1)
    .filter(%!(value) => value % 2 != 0)
    .map(%!(value) => value * value)
    .sum().int());

  List quantities = %(2 3 4), prices = %(10 20 30);
  printf("dot product: %d\n", quantities.iter()
    .map2(prices.iter(), %!(left, right) => left * right)
    .sum().int());

  List coefficients = %(2 -6 2 -1);
  printf("polynomial at 3: %ld\n", coefficients.iter()
    .foldl(0, %!(acc, coefficient) => acc * 3 + coefficient).integer());

  printf("8 factorial: %d\n", range(1, 8, 1).product().int());

  Scope.release();
  return 0;
}
