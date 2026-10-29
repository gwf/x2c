---
title: Derived records and typed collections
group: Types
---

```x2c
#include <assert.h>
#include <derive.x>
#include "typed-array.x"

typedef struct Person { String name; int age; } Person;
$derive(Person, <json>, <equal>, <repr>);          // methods from the fields

int main(void) {
  Person p = { "Ada", 36 };
  Person q = Person.from_json(p.json());           // also to_map / from_map
  assert(p.equal(q) && q.repr() == "Person{ name: \"Ada\", age: 36 }");
  ArrayInt xs = [1, 2, 3];                         // packed, unboxed ints
  xs[1] += 40;
  assert(xs[1] == 42 && xs.len() == 3);
  return 0;
}
```

- Kinds: `<map>`, `<json>`, `<equal>`, `<repr>`, `<args>` (command
  lines), `<row>` (database rows). Nested structs derive recursively.
- `typed-list.x` and `typed-map.x` add `ListInt`, `MapIntInt`, and
  friends; literals build them when that is the declared type.
