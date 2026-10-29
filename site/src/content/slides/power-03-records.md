---
slug: records
section: power
tab: derive
title: The type system extends itself.
---

```x2c
#include <assert.h>
#include <derive.x>

typedef struct Point { int x, y; } Point;
typedef struct Person { String name; int age; Point home; Array tags; } Person;

// Ask for the mappings you want; the declared fields supply the rest.
$derive(Point, <map>, <equal>, <repr>);
$derive(Person, <json>, <equal>, <repr>);

int main(void) {
  Person ada = { "Ada", 36, { 3, 4 }, ["math", "engines"] };

  // A struct becomes JSON and comes back as the same struct.
  String text = ada.json();
  Person copy = Person.from_json(text);
  assert(ada.equal(copy));
  puts(text);

  // Representation and nested equality follow the declared fields.
  copy.home.y = 9;
  printf("%d %s\n", ada.equal(copy), copy.repr());
  return 0;
}
```

`$derive` reads a struct's fields and writes the methods: Map and JSON
round trips, equality, `repr`, argument parsing, database rows. No
reflection runtime, no annotation processor, no code generator in the
build. `derive.x` is a few hundred lines of ordinary x2c that happen to run
inside the compiler.

You could have written it. In the Magic section, you will.
