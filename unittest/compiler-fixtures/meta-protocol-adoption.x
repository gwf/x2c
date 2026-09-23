#include "x2c.x"

/* A `meta` adoption exposes the conformance's witnesses to the generated
   native target inventory; an Iter operation marked by a prototype binds
   its `_into` target. A callback operation binds through its adapter, so
   the inventory leaves it out. */
typedef struct Bag { List items; } *Bag;
Iter Bag.iter(Bag bag, Iter dest) => bag.items.iter(dest);
meta protocol Iter(Bag);

meta Iter Iter.head(Iter iter, int count, Iter dest);
meta Iter Iter.map(Iter iter, Func fn, Iter dest);

macro Expression $exposed(Expr $name) =>
  $(if (member (list (x2c.literal.value $name)) (_x2c.native-meta.targets))
       1 0);

meta Var twice(Var value) => value * 2;

meta int heads(int offset) {
  struct Iter source, head;
  return range(1, 9, 1).map(twice).head(2).sum().int() * 10 +
         range(1, 9, 1, &source).head(3 + offset, &head).count();
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d %d\n", $exposed("Bag_iter"), $exposed("Iter_head"),
         $exposed("Iter_map"));
  printf("%d %d\n", $heads(0), heads(argc - 1));
  return 0;
}
