---
slug: symbols
section: love
home: true
order: 1
tab: names
title: Symbol pleasures.
---

```x2c
~int main(void) {
  // Separate contexts can use the same named value.
  Symbol job = <ready>, network = <ready>;
  printf("same name: %d\n", job == network);

  // The symbol does not declare a C identifier.
  int ready = 1;
  printf("flag: %d; name: %s\n", ready, job.str());

  // Symbol literals are constants, so C switch works.
  switch (job) {
    case <ready>:
      puts("waiting for a worker");
      break;
    case <running>:
      puts("doing the work");
      break;
  }
~  return 0;
~}
```

Symbols are named values that need no enum declaration. The same literal spelling gives the same value in every context. Reuse names without qualifying C identifiers or declaring constants that conflict with other declarations.
