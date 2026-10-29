---
title: Protocols and operators
group: Types
---

```x2c
#include <assert.h>

class Meters { long value; };
protocol Meters(T) { long T.magnitude(T); String T.describe(T); }
long Meters.magnitude(Meters m) => m.value;
String Meters.describe(Meters m) => %"$(m.value) m";

class Km { long value; };
Meters Km.meters(Km k) => Meters.new(k.value * 1000);  // view as the base
String Km.describe(Km k) => %"$(k.value) km";          // override one method
protocol Meters(Km);                                   // adopt, on purpose

typedef Map Set;                                       // operators via protocol
Set Set.add(Set a, Set b) => a.copy().merge(b);
protocol Map(T) { T T.add(T, T); }
protocol Map(Set);

int main(void) {
  Km trip = Km.new(3);
  assert(trip.magnitude() == 3000 && trip.describe() == "3 km");
  Set both = (Set) {a: 1} + (Set) {b: 2};
  assert(both.len() == 2);
  return 0;
}
```

- A protocol names its base type's methods; a participant adopts them
  with `protocol Base(Participant);` and may override any of them.
- Adoption is compile time: no vtable, no registry, no runtime object.
- `add`, `sub`, `mul`, `div`, `equal`, `compare`, `getindex`, `str`
  connect to `+ - * / == < [] %s`.
