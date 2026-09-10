---
slug: maps
section: love
tab: maps
---

```x2c
~int main(void) {
// Start with named items and their stock quantities.
Map stock = %{"tea": 12, "coffee": 8, "milk": 6, "sugar": 0};

// Update existing entries or add new ones with the same syntax.
stock["tea"] -= 2;
stock["coffee"] += 5;
stock["cocoa"] = 4;

// Fetch a value directly, or supply a fallback without inserting.
printf("tea: %s; biscuits: %s\n",
  stock["tea"],
  stock.getdefault("biscuits", 0));

// A stored zero is different from an absent key.
Var sugar;
if (stock.try_get("sugar", &sugar))
  puts(%"sugar is stocked: $sugar remaining");

// Visit each key and value; traversal order is unspecified.
foreach (Var (item, quantity), stock)
  puts(%"$item: $quantity");
~return 0;
~}
```

`Map` grows as entries are added, with brackets for reads and updates.
`Map.getdefault` supplies a fallback without inserting; `Map.try_get`
distinguishes a missing key from a stored zero. `foreach` unpacks each
key/value pair. Traversal order is unspecified.
