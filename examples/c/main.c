#include <stdio.h>
#include "account.h"

int main(void) {
  Account ada = Account_new(String_new("Ada"), 0);
  int deposits[] = {1250, 300, 75};
  for (int i = 0; i < 3; i++)
    Account_deposit(ada, deposits[i]);
  printf("%s: %d cents\n", ada->owner, ada->cents);
  return 0;
}
