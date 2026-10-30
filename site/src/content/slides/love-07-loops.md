---
slug: loops
section: love
tab: loops
title: The loop body is the whole loop.
---

```x2c
#include <assert.h>

int main(void) {
  Array orders = [%(tea 2 "Ada"), %(coffee 1 "Grace"), %(tea 1 "Linus")];

  // foreach walks anything with elements; destructure as you go.
  foreach (List order in orders) {
    (Symbol item, int count, String who) = order;
    printf("%s wants %d %s\n", who, count, item.str());
  }

  // A pattern condition binds names right where you test them.
  foreach (List order in orders)
    if (order ~= %(tea ?(int n) ?(String who)) && n > 1)
      puts(%"$who is thirsty");

  // Lambdas and iterator chains read left to right.
  Var total = orders.iter().map(%!(List order) => order[1])
    .foldl(0, %!(sum, count) => sum + count);
  assert(total == 4);

  // Keyword arguments arrive as a Map; absent keys take defaults.
  puts(label("tea"));
  puts(label("tea", size: "large", sugar: total));
  return 0;
}

static String label(String item, Map @options) {
  String size = options.getdefault(<size>, "small").str();
  int sugar = options.getdefault(<sugar>, 0).integer();
  return %"$size $item, $sugar sugar";
}
```

`foreach` walks anything that has elements, Files and Maps included, and a
List destructures into named parts on the way in. `~=` tests a pattern and
binds its names in one expression. Lambdas are `%!(x) => ...` and chain
left to right.

Keyword arguments arrive in a `Map`, so a call reads like a sentence and
the defaults are in one place.
