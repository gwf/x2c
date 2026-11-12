---
slug: protocols
aliases: [operators]
section: power
home: true
order: 1
tab: protocols
title: Small contracts, useful combinations.
---

```x2c
~#include <assert.h>
// Reuse Map storage: its keys are the set members.
typedef Map Set;

Set Set.add(Set left, Set right) => left.copy().merge(right);
Set Set.mul(Set left, Set right) => Set.new(left.keys()
  .filter(%!(Var key) => key in right));
Set Set.new(List keys) => keys.foldl(%{},
  %!(Map set, Var key) => set.update_n(1, key, (Var) 1));

// Connect add and mul to the + and * operators.
protocol Map(T) { T T.add(T, T); T T.mul(T, T); }
protocol Map(Set);

~int main(void) {
  // Create two sets, then take their union and intersection.
  Set fruit = Set.new(%(apple pear));
  Set lunch = Set.new(%(pear bread));
  Set set_union = fruit + lunch;
  Set intersection = fruit * lunch;
~  assert(set_union.len() == 3 && set_union.contains(<apple>) &&
~         set_union.contains(<pear>) && set_union.contains(<bread>));
~  assert(fruit.len() == 2 && lunch.len() == 2);
~  assert(Set.new(nil).len() == 0);
~  assert(Set.new(%(apple pear apple)).len() == 2);
~  Set symbols = Set.new(%(apple pear));
~  assert(symbols.contains(<apple>) && symbols.contains(<pear>));
~  assert(intersection.len() == 1 && intersection.contains(<pear>));
~  assert((fruit * fruit).len() == 2);
~  assert((fruit * Set.new(nil)).len() == 0);
~  assert((Set.new(nil) * fruit).len() == 0);
~  assert(fruit.len() == 2 && lunch.len() == 2);
  printf("%d in the union, %d in both\n", set_union.len(), intersection.len());
~  return 0;
~}
```

A Set built on a Map gains union and intersection through operators. The type is a `typedef Map Set`: it reuses Map storage and operations while giving the result a vocabulary of its own.
