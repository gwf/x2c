---
slug: c-class
section: from-c
tab: class
title: Declare a class.
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
  int deposits[] = {1250, 300, 75};
  for (int i = 0; i < 3; i++)
    ada.deposit(deposits[i]);
  printf("%s: %d cents\n", ada.owner, ada.cents);
  return 0;
}
```

`class` declares `Account` as a pointer to the struct and generates its
constructor, so the `typedef` and the hand-written `Account.new` are gone.
The object is allocated in the current `Scope`, which releases it, so
`free` and `<stdlib.h>` are gone too. The class also supplies `Var`
conversion, equality, hashing, and printing.
