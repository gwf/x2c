---
slug: two-kinds
section: love
tab: two kinds
title: Two kinds of data, never confused.
---

```x2c
#include <assert.h>

int main(void) {
  // Values: equal content is the same object, so == is a pointer compare.
  String greeting = "hel" + "lo", word = "hello";
  List pair = %(1 2), twin = cons(1, cons(2, NULL));
  assert(greeting == word && pair == twin && pair === twin);

  // Objects: Arrays and Maps have identity; copies of the handle share it.
  Array scores = [7, 3, 9], same = scores, other = [7, 3, 9];
  same.push(5);
  assert(scores == same && scores === same);
  assert(scores != other && scores !== other);

  // Any value is a Map key, because equal values are one object.
  Map seen = {(greeting): 1, (pair): 2, done: other.len()};
  printf("%s %s %s\n", seen["hello"], seen[%(1 2)], seen[<done>]);
  return 0;
}
```

Strings, Lists, and Symbols are *values*: equal content is literally the
same object, so `==` is a pointer compare and sharing costs nothing.
Arrays and Maps are *objects*: they have identity, they grow, and two
handles to one Array are one Array.

`==` compares content and `===` compares identity. Values are good Map keys
because there is only one of each.
