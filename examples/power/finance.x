/*  finance.x -- running financial calculations */


int main(void) {
  Scope.retain();

  List changes = %(20 -5 10 -25);
  printf("balances: %s\n", changes.iter()
    .accumulate(100).list().str());

  printf("loan balances: %s\n", Iter.repeat(90, 10)
    .scan(1000, %!(balance, payment) => balance * 105 / 100 - payment)
    .list().str());

  List growth = %(1.05 0.98 1.12);
  printf("growth multiplier: %f\n", growth.iter().product().floating());

  Scope.release();
  return 0;
}
