---
title: Maps
group: Values
---

```x2c
~#include <assert.h>
~int main(void) {
Map stock = {tea: 12, "milk": 6};          // bare key: Symbol; quoted: String
stock[<tea>] -= 2; stock["cocoa"] = 4;      // update or insert
assert(stock[<tea>] == 10 && stock["milk"] == 6 && stock.len() == 3);
assert(stock["none"] is void);              // an absent key reads as void
Var n;
if (stock.try_get("milk", n)) assert(n == 6);
assert(stock.getdefault("none", 0) == 0 && "cocoa" in stock);
foreach ((Var key, int count) in stock) printf("%s=%d ", key, count);
stock.del("cocoa");
assert(!stock.contains("cocoa"));
~return 0;
~}
```

- Any value is a key: Strings, Symbols, numbers, Lists, class values.
- Traversal order is unspecified. `keys()`, `values()`, `enumerate()`.
- `{}` is a fresh empty Map when the destination is a Map. `MapIntInt`
  and friends from `typed-map.x` skip boxing.
