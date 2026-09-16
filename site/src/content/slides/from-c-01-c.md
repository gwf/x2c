---
slug: c-start
section: from-c
tab: C
title: Start with a C program.
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
  account->owner = owner;
  account->cents = 0;
  return account;
}

void account_deposit(Account *account, int cents) {
  account->cents += cents;
}

int main(void) {
  Account *ada = account_new("Ada");
  int deposits[] = {1250, 300, 75};
  for (int i = 0; i < 3; i++)
    account_deposit(ada, deposits[i]);
  printf("%s: %d cents\n", ada->owner, ada->cents);
  free(ada);
  return 0;
}
```

This is plain C saved as `account.x`. x2c compiles it without changes and
hands the generated C to your C compiler. The struct, `malloc`, and `printf`
keep their C meaning, and the program prints `Ada: 1625 cents`.
