---
slug: two-kinds
section: love
home: true
order: 1
tab: two kinds
title: Equal contents. Distinct identities.
---

```x2c
~#include <assert.h>

~int main(void) {
  // Values: equal content is the same object, so == is a pointer compare.
  String greeting = "hel" + "lo", word = "hello";
  List pair = %(1 2), twin = cons(1, cons(2, NULL));
  assert(greeting == word && pair == twin && pair === twin);

  // Objects: Arrays and Maps have identity; copies of the handle share it.
  Array scores = [7, 3, 9], same = scores, other = [7, 3, 9];
  assert(scores == other && scores !== other);
  same.push(5);
  assert(scores == same && scores === same);
  assert(scores != other && scores !== other);

  // Equal Strings and Lists find the same Map entry.
  Map seen = {(greeting): 1, (pair): 2, done: other.len()};
  printf("%s %s %s\n", seen["hello"], seen[%(1 2)], seen[<done>]);
~  return 0;
~}
```

Strings, Lists, and Symbols share equal values. Arrays and Maps are mutable objects: two separate Arrays can have equal contents without being the same Array.

`==` compares contents; `===` compares identity. String and List keys let you retrieve a Map entry using an independently constructed equal value.
