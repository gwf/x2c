---
slug: c-call
section: from-c
tab: C calls x2c
title: Or keep main in C.
codeBlocks: 2
---

<div class="feature-code-label">account.x</div>

```x2c
class Account struct {
  String owner;
  int cents;
} *;

void Account.deposit(Account account, int cents) {
  account.cents += cents;
}
```

<div class="feature-code-label">main.c</div>

```c
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
```

Adoption also works from the other side. x2c writes `account.h` when it
translates `account.x`, and C sees an ordinary struct pointer and functions
such as `Account_new` and `Account_deposit`. `x2c build main.c account.x`
compiles both files with your C compiler and links the x2c runtime.
