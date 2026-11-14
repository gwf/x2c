---
slug: var
section: love
home: true
order: 0
tab: var
title: So Var, so good.
---

```x2c
~#include <assert.h>

// One parameter and result type; behavior follows the contained value.
Var twice(Var value) => value + value;

~int main(void) {
  // The same function adds numbers and joins text.
  Var number = twice(21), text = twice("ha");
  printf("%s %s\n", number, text);

  // Test a contained type, or inspect its broader kind.
  assert(number is int && text is String);
  printf("%s %s\n", number.kind().str(), text.kind().str());

  // A Var can hold another kind of value later.
  number = "sold out";
  if (number is String)
    printf("%s\n", number);
~  return 0;
~}
```

A Var is one 64-bit slot, the size of a double or pointer on supported targets. It holds numbers, text, names, collections, and participating user types. Functions can accept and return Vars, choosing operations from their contents at runtime. Use `is` to test the contained type and `kind()` to inspect its broader group.
