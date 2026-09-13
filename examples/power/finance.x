/*  finance.x -- running financial calculations */


int main(void) {
  Scope.retain();

  List changes = %(20 -5 10 -25);
  Array balances = %[];
  int balance = 100;
  foreach (Var change, changes) balances.push(balance += change.int());
  printf("balances: %s\n", balances.list_free().str());

  Array loans = %[];
  int loan = 1000;
  for (int month = 0; month < 10; month++)
    loans.push(loan = loan * 105 / 100 - 90);
  printf("loan balances: %s\n", loans.list_free().str());

  List growth = %(1.05 0.98 1.12);
  printf("growth multiplier: %f\n",
    growth.foldl(1.0, %!(product, factor) => product * factor).floating());

  Scope.release();
  return 0;
}
