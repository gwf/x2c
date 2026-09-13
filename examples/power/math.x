/*  math.x -- numeric pipelines over ranges and Lists */


int main(void) {
  Scope.retain();

  int odd_squares = 0;
  foreach (Var value, range(1, 10, 1)) {
    int number = value.int();
    if (number % 2 != 0) odd_squares += number * number;
  }
  printf("odd squares: %d\n", odd_squares);

  List quantities = %(2 3 4), prices = %(10 20 30);
  printf("dot product: %d\n", quantities
    .map2(prices, %!(left, right) => left * right)
    .foldl(0, %!(total, term) => total + term).int());

  List coefficients = %(2 -6 2 -1);
  printf("polynomial at 3: %ld\n", coefficients
    .foldl(0, %!(acc, coefficient) => acc * 3 + coefficient).integer());

  int factorial = 1;
  foreach (Var value, range(1, 8, 1)) factorial *= value.int();
  printf("8 factorial: %d\n", factorial);

  Scope.release();
  return 0;
}
