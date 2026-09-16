---
slug: c-dots
section: from-c
tab: dots
title: Use a dot for every field.
---

```x2c
#include <stdio.h>
#include <stdlib.h>

typedef struct Account {
  const char *owner;
  int cents;
} Account;

Account *account_new(const char *owner) {
  Account *account = malloc(sizeof *account);
  account.owner = owner;
  account.cents = 0;
  return account;
}

void account_deposit(Account *account, int cents) {
  account.cents += cents;
}

int main(void) {
  Account *ada = account_new("Ada");
  int deposits[] = {1250, 300, 75};
  for (int i = 0; i < 3; i++)
    account_deposit(ada, deposits[i]);
  printf("%s: %d cents\n", ada.owner, ada.cents);
  free(ada);
  return 0;
}
```

A dot reaches a field through a pointer as well as a value, so
`account->cents` becomes `account.cents`. The compiler knows the type and
emits the `->`. Nothing else changed.
