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
  int deposits[] = {1250, 300, 75};
  for (int i = 0; i < 3; i++)
    ada.deposit(deposits[i]);
  printf("%s: %d cents\n", ada.owner, ada.cents);
  return 0;
}
