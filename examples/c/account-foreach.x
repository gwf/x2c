#include <stdio.h>

class Account struct {
  String owner;
  int cents;
} *;

void Account.deposit(Account account, int cents) {
  account.cents += cents;
}

int main(void) {
  Account ada = Account.new("Ada", 0);
  foreach (int cents, %[1250, 300, 75])
    ada.deposit(cents);
  printf("%s: %d cents\n", ada.owner, ada.cents);
  return 0;
}
