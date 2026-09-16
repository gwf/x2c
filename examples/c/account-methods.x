#include <stdio.h>
#include <stdlib.h>

typedef struct Account {
  const char *owner;
  int cents;
} Account;

Account *Account.new(const char *owner) {
  Account *account = malloc(sizeof *account);
  account.owner = owner;
  account.cents = 0;
  return account;
}

void Account.deposit(Account *account, int cents) {
  account.cents += cents;
}

int main(void) {
  Account *ada = Account.new("Ada");
  int deposits[] = {1250, 300, 75};
  for (int i = 0; i < 3; i++)
    ada.deposit(deposits[i]);
  printf("%s: %d cents\n", ada.owner, ada.cents);
  free(ada);
  return 0;
}
