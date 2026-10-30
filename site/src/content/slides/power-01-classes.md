---
slug: classes
section: power
tab: classes
title: A class is a C type with the chores done.
---

```x2c
#include <assert.h>

// A value class: construction, equality, hashing, and printing come free.
class Point { int x; int y; };

// A pointer class with your own init; new allocates in the current Scope.
class Account { String owner; long cents; } *;

void Account.init(Account account, String owner) {
  account.owner = owner;
  account.cents = 0;
}

void Account.deposit(Account account, long cents) => account.cents += cents;
String Account.repr(Account account) =>
  %"Account($(account.owner), $(account.cents) cents)";

int main(void) {
  Point here = Point.new(3, 4), there = Point.new(3, 4);
  assert(here == there);
  Map labels = {};
  labels[here] = "home";
  printf("%s is %s\n", there.repr(), labels[there]);

  Account ada = auto Account.new("Ada");
  ada.deposit(1250);
  ada.deposit(75);
  printf("%s\n", ada.repr());
  return 0;
}
```

Say `class Point { int x; int y; };` and you get `new`, equality, hashing,
and printing, so a Point can be a Map key or a `%s` argument. Write your
own `init`, `repr`, or `drop` and it replaces the default.

A pointer class allocates in the current Scope, so `auto` frees it when the
block ends. The struct is still a struct, with the same bytes in C.
