---
slug: c-foreach
section: from-c
tab: foreach
title: Loop over the values.
---

```x2c
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
```

`foreach` visits each element of an `Array` literal, so the C array, its
count, and the index are gone. Each step printed `Ada: 1625 cents`, and the
program is about half the length of the C it started as.
