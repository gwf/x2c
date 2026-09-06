---
section: magic
tab: operators
---

```x2c
~#include <assert.h>
// Reuse Map storage: its keys are the set members.
typedef Map Set;

Set Set.new(List keys) => keys.foldl(%{},
  %!(Map set, Var key) => set.update_n(1, key, 1));
Set Set.add(Set left, Set right) => left.copy().merge(right);
Set Set.mul(Set left, Set right) => Set.new(left.keys()
  .filter(%!(Var key) => right.contains(key)));

// Connect add and mul to the + and * operators.
protocol Map(T) { T T.add(T, T); T T.mul(T, T); }
protocol Map(Set);

~int main(void) {
// Create two sets, then take their union and intersection.
Set fruit = Set.new(%(apple pear));
Set lunch = Set.new(%(pear bread));
Set set_union = fruit + lunch;
Set intersection = fruit * lunch;
~assert(set_union.len() == 3 && set_union.contains(<apple>) && set_union.contains(<pear>) && set_union.contains(<bread>));
~assert(fruit.len() == 2 && lunch.len() == 2);
~assert(Set.new(nil).len() == 0);
~assert(Set.new(%(apple pear apple)).len() == 2);
~List names = %(apple pear);
~printf("bare name: Symbol=%d Atom=%d\n", names.car() is Symbol, names.car() is Atom);
~Set symbols = Set.new(names);
~assert(symbols.contains(<apple>) && symbols.contains(<pear>));
~assert(intersection.len() == 1 && intersection.contains(<pear>));
~assert((fruit * fruit).len() == 2);
~assert((fruit * Set.new(nil)).len() == 0);
~assert((Set.new(nil) * fruit).len() == 0);
~assert(fruit.len() == 2 && lunch.len() == 2);
~return 0;
~}
```

`Set.new` reuses `Map` storage. `Set.add` and `Set.mul` define union
and intersection; `protocol Map(Set)` connects them to `+` and `*`.
The operators return new sets, leaving both inputs unchanged. Existing
collections do the storage work while the new type supplies the meaning.
