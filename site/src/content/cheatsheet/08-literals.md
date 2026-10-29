---
title: Literals, quoting, and interpolation
group: Values
---

```x2c
~#include <assert.h>
~int main(void) {
int n = 3; String who = "Ada";
List data = %(a (b c) "s" 1.5 $n);          // quoted data; $ evaluates one
List more = %(@data end);                   // @ splices a List in place
Array arr = [n, who, [1, 2]];               // evaluated elements
Map map = {name: who, n: n, (who): 1};      // bare key Symbol; (expr) key
String text = %"$who has $(n * 2) items";   // interpolation
assert(data.len() == 5 && more.len() == 6 && arr.len() == 3);
assert(map[<n>] == 3 && map["Ada"] == 1 && text == "Ada has 6 items");
~return 0;
~}
```

- `%(` is data and `(` is code. `%"..."` interpolates; `"..."` does not.
- `$(a, b)` builds an evaluated List, `${k: v}` an evaluated Map.
- `<sym>` is a Symbol, `%<<a b>>` a SymbolSet, `%!(x) => e` a lambda,
  `$!{ ... }` a quotation of code.
